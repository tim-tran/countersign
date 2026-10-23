require "rails_helper"

RSpec.describe Ledger::ReverseTransaction do
  before { setup_accounts(cash_minor: 50_000) }

  let(:original) { post([ leg("vendor", "debit", 4_000), leg("cash", "credit", 4_000) ]) }

  it "nets to zero and keeps both visible" do
    reversal = described_class.call(transaction_id: original.id, key: "rev-1")
    expect(reversal.reverses).to eq original
    expect(original.reload.reversed_by).to eq reversal
    expect(Ledger::Balance.for("vendor").posted_minor).to eq 0
    expect(LedgerTransaction.count).to eq 3 # funding + original + reversal
    expect_ledger_consistent!
  end

  it "replays with the same key" do
    first = described_class.call(transaction_id: original.id, key: "rev-1")
    again = nil
    expect { again = described_class.call(transaction_id: original.id, key: "rev-1") }.not_to change(Entry, :count)
    expect(again).to eq first
  end

  it "raises NotFound for an unknown transaction" do
    expect { described_class.call(transaction_id: 0, key: "rev-x") }.to raise_error(Ledger::NotFound)
  end

  it "refuses a second reversal and a reversal of a reversal" do
    reversal = described_class.call(transaction_id: original.id, key: "rev-1")
    expect { described_class.call(transaction_id: original.id, key: "rev-2") }.to raise_error(Ledger::InvalidState)
    expect { described_class.call(transaction_id: reversal.id, key: "rev-3") }.to raise_error(Ledger::InvalidState)
  end

  it "can fail with InsufficientFunds when the money was spent" do
    funding_txn = LedgerTransaction.first
    spend("cash", 50_000)
    expect { described_class.call(transaction_id: funding_txn.id, key: "rev-f") }.to raise_error(Ledger::InsufficientFunds)
  end

  it "rejects a duplicate reverses_id under a fresh key, even inside an outer transaction" do
    described_class.call(transaction_id: original.id, key: "rev-1")
    entries = [ leg("vendor", "credit", 4_000), leg("cash", "debit", 4_000) ]
    expect do
      ApplicationRecord.transaction do
        Ledger::PostTransaction.call(key: "rev-dup", entries: entries, operation: "reverse", reverses_id: original.id)
      end
    end.to raise_error(Ledger::InvalidState, /already been reversed/)
  end

  it "maps a reverses_id unique violation to InvalidState and re-raises other ones" do
    original
    allow(Ledger::PostTransaction).to receive(:call)
      .and_raise(ActiveRecord::RecordNotUnique, "PG::UniqueViolation: index_ledger_transactions_on_reverses_id")
    expect { described_class.call(transaction_id: original.id, key: "rev-1") }.to raise_error(Ledger::InvalidState, /already been reversed/)

    allow(Ledger::PostTransaction).to receive(:call)
      .and_raise(ActiveRecord::RecordNotUnique, "PG::UniqueViolation: index_ledger_transactions_on_idempotency_key")
    expect { described_class.call(transaction_id: original.id, key: "rev-1") }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  context "concurrently", :concurrency do
    it "two different keys reversing at once yield one reversal" do
      original # post before the threads start
      results = run_concurrently(10) { |i| described_class.call(transaction_id: original.id, key: "rev-#{i}") }
      expect(results.count { it.is_a?(LedgerTransaction) }).to eq 1
      expect(results.reject { it.is_a?(LedgerTransaction) }).to all(be_a(Ledger::InvalidState))
      expect_ledger_consistent!
    end
  end
end

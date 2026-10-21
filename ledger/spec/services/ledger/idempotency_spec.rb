require "rails_helper"

RSpec.describe Ledger::PostTransaction, "idempotency" do
  before { setup_accounts }

  let(:entries) { [ leg("cash", "debit", 10_000), leg("funding", "credit", 10_000) ] }
  let(:other_entries) { [ leg("cash", "debit", 9_000), leg("funding", "credit", 9_000) ] }
  let(:overdrawing_entries) { [ leg("payable", "debit", 1), leg("funding", "credit", 1) ] }

  it "replay returns the original and moves no money" do
    first = post(entries, key: "payrun-1-capture")
    expect { expect(post(entries, key: "payrun-1-capture")).to eq first }.not_to change(Entry, :count)
  end

  it "replay tolerates ordering and omitted effective_at" do
    first = post(entries, key: "k", metadata: { "a" => 1, "b" => 2 })
    travel 5.seconds do
      expect(post(entries.reverse, key: "k", metadata: { "b" => 2, "a" => 1 })).to eq first
    end
  end

  it "different payload with the same key conflicts" do
    post(entries, key: "k")
    expect { post(other_entries, key: "k") }.to raise_error(Ledger::ConflictError, /"k"/)
  end

  it "failed post leaves no key" do
    expect { post(overdrawing_entries, key: "k") }.to raise_error(Ledger::InsufficientFunds)
    expect(post(entries, key: "k")).to be_persisted
  end

  context "concurrently", :concurrency do
    it "10 concurrent duplicates make one transaction" do
      results = run_concurrently(10) { post(entries, key: "race") }
      expect(results).to all(be_a(LedgerTransaction))
      expect(results.map(&:id).uniq.size).to eq 1
      expect(LedgerTransaction.count).to eq 1
      expect(Ledger::Balance.for("cash").posted_minor).to eq 10_000
    end

    it "concurrent duplicates of a draining spend all get the original" do
      post(entries, key: "fund")
      spend = [ leg("vendor", "debit", 10_000), leg("cash", "credit", 10_000) ]
      before_count = LedgerTransaction.count

      results = run_concurrently(10) { post(spend, key: "dup") }

      expect(results).to all(be_a(LedgerTransaction))
      expect(results.map(&:id).uniq.size).to eq 1
      expect(LedgerTransaction.count).to eq before_count + 1
      expect(Ledger::Balance.for("cash").posted_minor).to eq 0
    end

    it "concurrent duplicates of a draining spend get the original with the query cache on" do
      post(entries, key: "fund")
      spend = [ leg("vendor", "debit", 10_000), leg("cash", "credit", 10_000) ]
      before_count = LedgerTransaction.count

      results = run_concurrently(10) { ActiveRecord::Base.cache { post(spend, key: "dup") } }

      expect(results).to all(be_a(LedgerTransaction))
      expect(results.map(&:id).uniq.size).to eq 1
      expect(LedgerTransaction.count).to eq before_count + 1
    end
  end
end

require "rails_helper"

RSpec.describe Ledger::PostTransaction do
  before { setup_accounts }

  it "writes the transaction, entries and balances" do
    txn = post([ leg("cash", "debit", 10_000), leg("funding", "credit", 10_000) ], metadata: { "note" => "seed" })
    expect(txn.entries.count).to eq 2
    expect(Ledger::Balance.for("cash").posted_minor).to eq 10_000
    expect(Ledger::Balance.for("funding").posted_minor).to eq(-10_000)
    expect(txn.effective_at).to be_within(1.second).of(Time.current)
    expect(txn.metadata).to eq("note" => "seed")
  end

  it "records a caller-supplied effective_at separately from created_at" do
    t = Time.zone.parse("2026-01-15 09:00")
    expect(post([ leg("cash", "debit", 1), leg("funding", "credit", 1) ], effective_at: t).effective_at).to eq t
  end

  it "accepts a Date as the start of that day in the app zone" do
    txn = post([ leg("cash", "debit", 1), leg("funding", "credit", 1) ], effective_at: Date.new(2026, 3, 1))
    expect(txn.effective_at).to eq Time.zone.local(2026, 3, 1)
  end

  it "accepts an ISO-8601 string" do
    txn = post([ leg("cash", "debit", 1), leg("funding", "credit", 1) ], effective_at: "2026-03-01T12:00:00Z")
    expect(txn.effective_at).to eq Time.utc(2026, 3, 1, 12)
  end

  it "rejects an unparseable or unsupported effective_at and writes nothing" do
    [ "garbage", 12_345, {} ].each do |bad|
      expect { post([ leg("cash", "debit", 1), leg("funding", "credit", 1) ], effective_at: bad) }
        .to raise_error(Ledger::InvalidRequest, /effective_at/)
    end
    expect(LedgerTransaction.count).to eq 0
  end

  it "rejects unbalanced" do
    expect { post([ leg("cash", "debit", 100), leg("funding", "credit", 99) ]) }.to raise_error(Ledger::Unbalanced)
  end

  it "rejects a single entry, zero and negative amounts" do
    [ [ leg("cash", "debit", 100) ],
      [ leg("cash", "debit", 0), leg("funding", "credit", 0) ],
      [ leg("cash", "debit", -5), leg("funding", "credit", -5) ] ].each do |entries|
      expect { post(entries) }.to raise_error(Ledger::InvalidRequest)
    end
  end

  it "rejects non-integer amounts and unknown directions" do
    [ "10000", 100.0, BigDecimal("100"), nil ].each do |amt|
      expect { post([ leg("cash", "debit", amt), leg("funding", "credit", amt) ]) }.to raise_error(Ledger::InvalidRequest)
    end
    expect { post([ leg("cash", "up", 1), leg("funding", "credit", 1) ]) }.to raise_error(Ledger::InvalidRequest)
  end

  it "rejects an unknown account" do
    expect { post([ leg("nope", "debit", 1), leg("funding", "credit", 1) ]) }.to raise_error(Ledger::NotFound)
  end

  it "rejects an entry whose currency differs from its account" do
    entries = [ leg("cash", "debit", 1).merge(currency: "CAD"), leg("funding", "credit", 1) ]
    expect { post(entries) }.to raise_error(Ledger::CurrencyMismatch)
  end

  it "balances per currency" do
    expect { post([ leg("cash", "debit", 100), leg("cad_cash", "credit", 100) ]) }.to raise_error(Ledger::Unbalanced)
  end

  it "rejects an insufficient balance" do
    expect { post([ leg("payable", "debit", 100), leg("funding", "credit", 100) ]) }.to raise_error(Ledger::InsufficientFunds)
  end

  it "handles the same account twice" do
    post([ leg("cash", "debit", 500), leg("cash", "credit", 200), leg("funding", "credit", 300) ])
    expect(AccountBalance.find_by(account: Account.find_by(code: "cash"))).to have_attributes(debits_minor: 500, credits_minor: 200)
  end

  it "writes nothing on any rejection" do
    expect { post([ leg("cash", "debit", 100), leg("funding", "credit", 99) ]) rescue nil }
      .not_to change { [ LedgerTransaction.count, Entry.count, AccountBalance.sum(:debits_minor) ] }
  end
end

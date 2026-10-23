require "rails_helper"

RSpec.describe "Ledger concurrency", :concurrency do
  before { setup_accounts(cash_minor: 50_000) }

  it "20 threads spending $100 from $500: exactly 5 succeed" do
    results = run_concurrently(20) do |i|
      post([ leg("vendor", "debit", 10_000), leg("cash", "credit", 10_000) ], key: "spend-#{i}")
    end

    expect(results.count { it.is_a?(LedgerTransaction) }).to eq 5
    expect(results.reject { it.is_a?(LedgerTransaction) }).to all(be_a(Ledger::InsufficientFunds))
    expect(Ledger::Balance.for("cash").posted_minor).to eq 0
  end

  it "opposite-direction transfers do not deadlock" do
    results = run_concurrently(20) do |i|
      from, to = i.even? ? %w[cash vendor] : %w[vendor cash]
      post([ leg(to, "debit", 1), leg(from, "credit", 1) ], key: "swap-#{i}")
    end

    expect(results.grep(ActiveRecord::Deadlocked)).to be_empty
  end

  it "bumps version once per change" do
    expect { post([ leg("vendor", "debit", 1), leg("cash", "credit", 1) ]) }
      .to change { Account.find_by(code: "cash").balance.reload.version }.by(1)
  end
end

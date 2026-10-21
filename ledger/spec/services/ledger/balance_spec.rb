require "rails_helper"

RSpec.describe Ledger::Balance do
  it "debit-normal: debits minus credits" do
    expect(described_class.posted_minor(normal_side: "debit", debits_minor: 500, credits_minor: 200)).to eq 300
  end

  it "credit-normal: credits minus debits" do
    expect(described_class.posted_minor(normal_side: "credit", debits_minor: 500, credits_minor: 200)).to eq(-300)
  end

  it "snapshot subtracts held" do
    account = create(:account)
    account.balance.update!(debits_minor: 10_000, held_minor: 2_500)
    expect(described_class.for(account.code)).to have_attributes(posted_minor: 10_000, held_minor: 2_500, available_minor: 7_500)
  end

  it "unknown code" do
    expect { described_class.for("nope") }.to raise_error(Ledger::NotFound)
  end
end

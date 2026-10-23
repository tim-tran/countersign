require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def load_seeds
    load Rails.root.join("db/seeds.rb")
  end

  it "creates the five-account chart, idempotently" do
    2.times { load_seeds }

    expect(Account.order(:code).pluck(:code, :kind, :normal_side, :currency)).to eq([
      [ "employer_cash", "asset", "debit", "USD" ],
      [ "external_funding", "asset", "debit", "USD" ],
      [ "tax_withholding_payable", "liability", "credit", "USD" ],
      [ "wages_expense", "expense", "debit", "USD" ],
      [ "wages_payable", "liability", "credit", "USD" ]
    ])
  end

  it "lets only external_funding go negative" do
    load_seeds

    expect(Account.where(allow_negative: true).pluck(:code)).to eq([ "external_funding" ])
  end
end

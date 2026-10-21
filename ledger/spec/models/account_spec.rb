require "rails_helper"

RSpec.describe Account do
  it "creates a zero balance row" do
    expect(create(:account).balance).to have_attributes(debits_minor: 0, credits_minor: 0, held_minor: 0, version: 0)
  end

  it "rejects bad kind, side and currency in the database" do
    account = create(:account)
    %w[kind normal_side currency].each do |col|
      expect {
        ApplicationRecord.transaction(requires_new: true) { account.update_column(col, "xx") }
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it "rejects a duplicate code in the database" do
    create(:account, code: "employer_cash")
    expect { build(:account, code: "employer_cash").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

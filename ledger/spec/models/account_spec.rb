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

  it "forbids changing normal_side or kind once the account has entries" do
    setup_accounts
    post([ leg("cash", "debit", 100), leg("funding", "credit", 100) ])
    { "normal_side" => "credit", "kind" => "liability" }.each do |col, value|
      expect {
        ApplicationRecord.transaction(requires_new: true) { Account.find_by!(code: "cash").update_column(col, value) }
      }.to raise_error(ActiveRecord::StatementInvalid, /in use/)
    end
  end

  it "allows changing normal_side and kind on an unused account" do
    account = create(:account)
    expect { account.update_columns(normal_side: "credit", kind: "liability") }.not_to raise_error
  end

  it "rejects a duplicate code in the database" do
    create(:account, code: "employer_cash")
    expect { build(:account, code: "employer_cash").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "gives account_balances no default account_id" do
    expect {
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("INSERT INTO account_balances DEFAULT VALUES")
      end
    }.to raise_error(ActiveRecord::NotNullViolation)
  end
end

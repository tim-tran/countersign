# Invented chart of accounts. Idempotent: safe to run any number of times.
[
  { code: "external_funding", kind: "asset", normal_side: "debit", allow_negative: true },
  { code: "employer_cash", kind: "asset", normal_side: "debit" },
  { code: "wages_expense", kind: "expense", normal_side: "debit" },
  { code: "wages_payable", kind: "liability", normal_side: "credit" },
  { code: "tax_withholding_payable", kind: "liability", normal_side: "credit" }
].each do |attrs|
  Account.find_or_create_by!(code: attrs[:code]) do |account|
    account.assign_attributes(attrs.merge(currency: "USD"))
  end
end

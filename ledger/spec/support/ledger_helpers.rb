module LedgerHelpers
  def leg(code, direction, amount)
    { account_code: code, direction: direction, amount_minor: amount }
  end

  def post(entries, key: SecureRandom.uuid, **opts)
    Ledger::PostTransaction.call(key: key, entries: entries, **opts)
  end

  # Moves money out of `code` to `vendor`.
  def spend(code, amount, key: SecureRandom.uuid)
    post([ leg(code, "credit", amount), leg("vendor", "debit", amount) ], key: key)
  end

  def setup_accounts(cash_minor: 0)
    create(:account, code: "funding", kind: "equity", normal_side: "debit", allow_negative: true)
    create(:account, code: "cash")
    create(:account, code: "vendor")
    create(:account, :credit_normal, code: "payable")
    create(:account, :cad, code: "cad_cash")
    post([ leg("cash", "debit", cash_minor), leg("funding", "credit", cash_minor) ]) if cash_minor.positive?
  end
end

RSpec.configure do |config|
  config.include LedgerHelpers
end

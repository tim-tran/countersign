# Invariants that must hold over the whole ledger after any sequence of posts.
# Each check uses aggregate queries, not per-entry loops.
module LedgerInvariants
  # `label` (e.g. "TRIAL_SEED=12345") is prefixed to every failure message so
  # a failing randomized run always reports how to reproduce it.
  def expect_ledger_consistent!(label: nil)
    expect_debits_equal_credits_per_currency!(label)
    expect_balances_match_entries!(label)
  end

  private

  def labelled(label, message)
    [ label, message ].compact.join(": ")
  end

  def expect_debits_equal_credits_per_currency!(label)
    debits = Entry.where(direction: "debit").group(:currency).sum(:amount_minor)
    credits = Entry.where(direction: "credit").group(:currency).sum(:amount_minor)

    totals = (debits.keys | credits.keys).index_with { |currency| [ debits.fetch(currency, 0), credits.fetch(currency, 0) ] }
    unequal = totals.reject { |_currency, (debit_total, credit_total)| debit_total == credit_total }

    expect(unequal).to be_empty, labelled(label, "debits != credits per currency (currency => [debits, credits]): #{unequal.inspect}")
  end

  def expect_balances_match_entries!(label)
    entry_sums = Entry.group(:account_id, :direction).sum(:amount_minor)
    balances = AccountBalance.pluck(:account_id, :debits_minor, :credits_minor).to_h do |id, debits, credits|
      [ id, [ debits, credits ] ]
    end

    account_ids = balances.keys | entry_sums.keys.map(&:first)
    mismatched = account_ids.filter_map do |id|
      expected = [ entry_sums.fetch([ id, "debit" ], 0), entry_sums.fetch([ id, "credit" ], 0) ]
      actual = balances.fetch(id, [ 0, 0 ])
      [ id, { expected: expected, actual: actual } ] unless expected == actual
    end

    expect(mismatched).to be_empty, labelled(label, "balance rows differ from entry sums (account_id => {expected, actual} as [debits, credits]): #{mismatched.to_h.inspect}")
  end
end

RSpec.configure do |config|
  config.include LedgerInvariants
end

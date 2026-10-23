# Countersign ledger

A double-entry ledger as a Rails 8 API app on PostgreSQL. Amounts are integers in minor units
(`10000` is $100.00); there are no floats anywhere in the domain. Writes go only through the
`Ledger::*` service objects, and the invariants are enforced in Postgres as well as in Ruby.
Design: [ledger core design](../docs/superpowers/specs/2026-10-21-ledger-core-design.md).

**All data is invented.** The accounts, keys and amounts here are made up for illustration.

## Setup

Requires [mise](https://mise.jdx.dev) and a local PostgreSQL.

```sh
mise install            # from the repo root: installs Ruby 4.0.7
cd ledger
bin/setup               # installs gems, prepares the databases
bundle exec rspec       # runs the suite
bin/rubocop             # lint (rubocop-rails-omakase)
```

`bin/rails db:seed` loads a five-account chart (all USD): `external_funding` (asset, may go
negative), `employer_cash` (asset), `wages_expense` (expense), `wages_payable` (liability) and
`tax_withholding_payable` (liability). Seeding is idempotent.

## Walkthrough

Run with `bin/rails runner` against the development database after `bin/rails db:prepare` and
`bin/rails db:seed`. Fund the employer account, accrue wages, hold cash for the pay run,
capture the hold to settle the liability, then post a mistaken transaction and reverse it.

```ruby
def show(code)
  b = Ledger::Balance.for(code)
  puts format("%-24s posted=%8d held=%8d available=%8d", code, b.posted_minor, b.held_minor, b.available_minor)
end

Ledger::PostTransaction.call(key: "fund-0001", entries: [
  { account_code: "employer_cash", direction: "debit", amount_minor: 5_000_000 },
  { account_code: "external_funding", direction: "credit", amount_minor: 5_000_000 }
])
Ledger::PostTransaction.call(key: "accrue-4411", entries: [
  { account_code: "wages_expense", direction: "debit", amount_minor: 4_000_000 },
  { account_code: "wages_payable", direction: "credit", amount_minor: 4_000_000 }
])
hold = Ledger::PlaceHold.call(key: "payrun-4411-hold", account_code: "employer_cash", amount_minor: 4_000_000)
puts "hold #{hold.status}"
show("employer_cash")
hold = Ledger::CaptureHold.call(hold_id: hold.id, key: "payrun-4411-capture", counter_account_code: "wages_payable", amount_minor: 4_000_000)
puts "hold #{hold.status}"
%w[employer_cash external_funding wages_expense wages_payable].each { |c| show(c) }

mistake = Ledger::PostTransaction.call(key: "mistake-0001", entries: [
  { account_code: "wages_expense", direction: "debit", amount_minor: 125_000 },
  { account_code: "tax_withholding_payable", direction: "credit", amount_minor: 125_000 }
])
show("tax_withholding_payable")
Ledger::ReverseTransaction.call(transaction_id: mistake.id, key: "mistake-0001-reversal")
show("tax_withholding_payable")
show("wages_expense")
```

Output:

```
hold active
employer_cash            posted= 5000000 held= 4000000 available= 1000000
hold captured
employer_cash            posted= 1000000 held=       0 available= 1000000
external_funding         posted=-5000000 held=       0 available=-5000000
wages_expense            posted= 4000000 held=       0 available= 4000000
wages_payable            posted=       0 held=       0 available=       0
tax_withholding_payable  posted=  125000 held=       0 available=  125000
tax_withholding_payable  posted=       0 held=       0 available=       0
wages_expense            posted= 4000000 held=       0 available= 4000000
```

In accounting terms: the hold reserves $40,000.00 of the $50,000.00 cash (available drops to
$10,000.00) without moving it. Capturing it credits `employer_cash` and debits `wages_payable`,
which settles the $40,000.00 liability accrued earlier, so it returns to zero while
`wages_expense` keeps the cost. The reversal posts the mirror-image entries, so
`tax_withholding_payable` returns to zero and the mistaken $1,250.00 expense is cancelled out
(`wages_expense` is back at $40,000.00). `external_funding` is the only account allowed to go
negative: it is the source of money entering the system.

To rerun, `bin/rails db:reset` the development database first.

## Guarantees and how they're proven

| Guarantee | Proven by |
| --- | --- |
| Every transaction balances, per currency; mixed currencies are rejected | `spec/services/ledger/post_transaction_spec.rb`, `spec/db/ledger_guards_spec.rb` |
| Writes are idempotent by key, including concurrent duplicates | `spec/services/ledger/idempotency_spec.rb` |
| No overdraft under concurrent postings | `spec/services/ledger/concurrency_spec.rb` |
| Posted rows are immutable (updates and deletes fail in the database) | `spec/db/ledger_guards_spec.rb` |
| Holds reserve funds; capture and release behave as specified | `spec/services/ledger/holds_spec.rb` |
| A transaction can be reversed at most once | `spec/services/ledger/reverse_transaction_spec.rb` |
| Randomized sequences keep the trial balance at zero | `spec/services/ledger/trial_balance_spec.rb` |

Also: `spec/models/account_spec.rb` (account validations), `spec/services/ledger/balance_spec.rb`
(balance snapshots) and `spec/seeds_spec.rb` (the chart of accounts).

## Immutability and TRUNCATE

A `BEFORE UPDATE OR DELETE` row trigger on transactions and entries raises
`ledger rows are immutable`, so even `update_columns` or raw SQL fails. `TRUNCATE` is left
allowed so test cleanup works; a deployed app's database role would not hold `TRUNCATE`.

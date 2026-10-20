# Ledger core: design

Status: Draft (awaiting Tim's review)

## Stack

- Latest stable Ruby, Rails (API mode: `rails new ledger --api -d postgresql -T`) and PostgreSQL, resolved at setup time and pinned in the root `mise.toml` and `ledger/Gemfile.lock`.
- RSpec, FactoryBot, all at their latest stable releases. No other gems unless a task needs one.
- Schema kept as `db/structure.sql` (not `schema.rb`) because triggers and check constraints must round-trip.

## Shape of the code

```
ledger/app/
  models/            Account, LedgerTransaction, Entry, AccountBalance, Hold   (thin; no writes of entries)
  services/ledger/   PostTransaction, PlaceHold, CaptureHold, ReleaseHold, ReverseTransaction, Balance
                     errors.rb (Unbalanced, InsufficientFunds, ConflictError, InvalidState, CurrencyMismatch)
  controllers/v1/    transactions, holds, accounts (balance reads)
```

The model is named `LedgerTransaction` (table `ledger_transactions`) to avoid clashing with
ActiveRecord's `transaction` method.

## Schema

| Table | Columns | Constraints |
|---|---|---|
| `accounts` | id, code, kind, normal_side, currency (char 3), allow_negative bool | `code` unique; check `kind` and `normal_side` in allowed sets |
| `ledger_transactions` | id, idempotency_key, request_hash, effective_at, created_at, metadata jsonb, reverses_id | `idempotency_key` unique; `reverses_id` unique, FK to self (R7.2) |
| `entries` | id, ledger_transaction_id, account_id, direction, amount_minor bigint, currency | check `amount_minor > 0`; check `direction in ('debit','credit')` |
| `account_balances` | account_id PK/FK, debits_minor, credits_minor, held_minor, version | all bigint, default 0; check `held_minor >= 0` |
| `holds` | id, account_id, amount_minor, status, idempotency_key, request_hash, ledger_transaction_id, created_at, updated_at | `idempotency_key` unique; check `status in ('active','captured','released')`; check `amount_minor > 0` |

Entries carry `currency` (copied from the account) so per-currency balancing is a single
`GROUP BY` and can be checked in SQL.

**Balance math (R1.2, one function):**
`posted = normal_side == debit ? debits - credits : credits - debits`;
`available = posted - held`.

## Posting algorithm (R2, R3, R4)

`Ledger::PostTransaction.call(key:, entries:, effective_at: nil, metadata: {})`

1. Validate shape in Ruby: at least 2 entries, positive integers, accounts exist, entry
   currency matches account, debits equal credits per currency. Fail fast with `Unbalanced` /
   `CurrencyMismatch` before touching the DB (R2.1 to R2.3).
2. `request_hash = SHA256(canonical JSON of {op: "post", entries sorted by (account_code, direction, amount), effective_at, metadata})`.
3. Fast path: if a transaction with `key` exists, return it when the hash matches, raise
   `ConflictError` when it does not (R3.2, R3.3).
4. Open a DB transaction:
   - `SELECT ... FROM account_balances WHERE account_id IN (...) ORDER BY account_id FOR UPDATE`
     (fixed order prevents deadlocks, R4.4).
   - For every account whose balance decreases on its normal side, check
     `available - decrease >= 0` unless `allow_negative` (R4.2).
   - Insert the transaction row, then entries, then update balances and bump `version` (R2.4, R4.1).
5. If the insert hits the unique index on `idempotency_key` (a concurrent duplicate won the race),
   rescue `ActiveRecord::RecordNotUnique` *outside* the rolled-back transaction and go back to
   step 3 (R3.4). Because nothing commits on failure, a failed post leaves no key (R3.5).

The unique index is the real guarantee; the fast-path lookup only saves work.

## Immutability (R5)

A `BEFORE UPDATE OR DELETE` row trigger on `entries` and `ledger_transactions` raises
`ledger rows are immutable`. Tests assert that even `update_columns` and raw SQL fail.
`TRUNCATE` is not blocked so test cleanup works; in any deployed environment the app's DB role
would not hold `TRUNCATE` (noted in the README, not built now).

## Holds (R6)

- **Place**: lock the account balance row, check `available >= amount` (unless `allow_negative`),
  insert hold `active`, `held_minor += amount`. Idempotent by the hold's own key + hash.
- **Capture** `(hold, key:, counter_account_code:, amount_minor <= hold.amount_minor)`: lock the
  hold row, then balances in id order. Post a transaction that moves `amount_minor` from the held
  account to the counter account, release the full hold from `held_minor`, set status `captured`
  and `ledger_transaction_id`, all in one DB transaction. Any uncaptured remainder simply becomes
  available again (no partial holds, see out of scope). Replay with the same key returns the hold.
- **Release**: lock the hold, `held_minor -= amount`, status `released`. A second release returns
  the hold unchanged; release after capture (or capture after release) raises `InvalidState`.

Holds are mutable by design (status changes); money movement is still only ever in entries.

## Reversals (R7)

`Ledger::ReverseTransaction.call(transaction_id, key:)` builds the flipped entries and goes
through `PostTransaction`, so locking, balance checks and idempotency are shared. It refuses a
transaction that is itself a reversal; the unique index on `reverses_id` makes a second reversal
fail even under a race. A reversal can fail with `InsufficientFunds` if the money has since been
spent; that is correct behaviour, not a bug.

## HTTP API (R8)

All under `/v1`, JSON, `Authorization: Bearer <LEDGER_API_TOKEN>` compared with
`ActiveSupport::SecurityUtils.secure_compare`. Writes require `Idempotency-Key`.

| Method and path | Purpose |
|---|---|
| `POST /v1/transactions` | Post `{entries: [{account_code, direction, amount_minor}], effective_at?, metadata?}` |
| `GET /v1/transactions/:id` | Transaction with entries and `reverses_id` / `reversed_by_id` |
| `POST /v1/transactions/:id/reversal` | Reverse a transaction |
| `GET /v1/accounts/:code` | Account plus `posted_minor`, `held_minor`, `available_minor` |
| `POST /v1/holds` | Place `{account_code, amount_minor}` |
| `POST /v1/holds/:id/capture` | `{counter_account_code, amount_minor}` |
| `POST /v1/holds/:id/release` | Release |

Errors: `{"error": {"code": "...", "message": "..."}}` with the codes in R8.2. A replayed
request returns the original response body with status 200 (first call returns 201).

Accounts are created by `db/seeds.rb` (an invented chart of accounts: employer cash, wages
expense, wages payable, tax withholding payable, external funding source with
`allow_negative`). No account-creation endpoint yet.

## Test plan (R9 and the plan's six proofs)

| Test | Requirement |
|---|---|
| Randomized trial balance: ~2,000 random valid postings, then sum(debits) = sum(credits) per currency and every balance row equals the sum of its entries | R2, R4.1, R9.1 |
| Concurrency: 20 threads spend $100 from $500, exactly 5 succeed, balance = 0 | R4.2 to R4.4 |
| Idempotency: replay, conflict, 10-thread race, failed post leaves no key | R3 |
| Immutability: update and delete of entries and transactions fail in the DB | R5 |
| Reversal: nets to zero, both visible, cannot reverse twice or reverse a reversal | R7 |
| Holds: available = posted - held; capture, release, replay and invalid transitions | R6 |
| Request specs for each endpoint, auth, and error mapping | R8 |

Thread-based specs run with `use_transactional_fixtures` off and truncate afterwards.

## Rejected alternatives

- **Compute balances from entries on every read** instead of a balance table: simpler, but
  makes the overdraft check a race unless the whole account is locked anyway. Kept the table.
- **Optimistic locking only (`version` + retry)**: works, but retries under contention make the
  concurrency test noisy. Pessimistic `FOR UPDATE` in a fixed order; `version` stays as an audit counter.
- **A gem (e.g. double_entry, keepr)**: hides the parts this project is meant to demonstrate.

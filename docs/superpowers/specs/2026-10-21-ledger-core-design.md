# Ledger core design

Status: awaiting Tim's approval. No plan or code until it is approved.

## Intent and the why

Countersign is a portfolio project about one question: how do you trust what an AI produces
when money is involved? The ledger is the foundation. It is the only component that moves
money; the pay rules engine and the review agent built later can only propose, and a human
approves before anything is posted through the ledger's API.

The ledger has to make one promise and prove it: money is never created, lost or paid twice.
For a reviewer reading the repo, the tests that prove this promise, especially concurrency
and idempotency, matter more than feature breadth.

All accounts, rules, people and amounts are invented. Nothing models a real company's system.

## Goals

- An immutable double-entry ledger in a Rails API app, `ledger/`, inside the `countersign` monorepo.
- Balanced transactions, idempotent writes, overdraft-safe concurrent posting, holds and reversals.
- A small JSON HTTP API so the Python review agent (later) never touches the database.
- Tests that prove each guarantee (listed under "How we know it works").

## Non-goals

- FX or multi-currency conversion. Each account has one currency; a transaction may span
  currencies only if each currency balances on its own.
- Human approval workflow, decision log, outbox/event stream. Those are later features.
- Users, roles, multi-tenancy. One shared API token is enough.
- Partial holds that stay open, hold expiry, scheduled postings.
- Period close, statements, reporting UI, an account-creation endpoint.

## Anti-goals (failure even if it technically works)

- Any path, including a bug in the app, that edits or deletes a posted entry.
- Two concurrent requests overdrawing an account, or a retried request moving money twice.
- Money represented as floats or decimals anywhere in the domain.
- Overbuilding: the whole Countersign project must be doable solo in about three months, and
  the ledger is the biggest risk for eating that budget. If something here isn't needed to
  prove the promise above, leave it out.

## Constraints

- Latest stable releases of every language, framework and library (currently Ruby 4.0.7,
  Rails 8.1.4, PostgreSQL 18.6). Pinned in the root `mise.toml` and `ledger/Gemfile.lock`.
- Rails API mode with Postgres, created with `rails new ledger --api -d postgresql -T` (done).
- RSpec and FactoryBot for tests. No other gems unless a task needs one; no ledger gems
  (double_entry, keepr), because they hide what this project is meant to show.
- Amounts are integers in minor units (`amount_minor`, cents). `$100.00` is `10000`.
- Every invariant that matters is enforced in Postgres (constraints, triggers), not only in Ruby.
- Schema kept as `db/structure.sql`, because triggers and check constraints must round-trip.

## What it does

### Accounts
Each account has a unique `code`, a `kind` (asset, liability, equity, revenue, expense), a
`normal_side` (debit or credit), one ISO currency, and an `allow_negative` flag. One function
computes any balance from the normal side:
`posted = debit-normal ? debits - credits : credits - debits`, and `available = posted - held`.
Accounts come from `db/seeds.rb`: an invented chart of accounts (employer cash, wages expense,
wages payable, tax withholding payable, and an external funding source with `allow_negative`).

### Posting a transaction
A transaction is one atomic business event of two or more entries, each a debit or credit
with a positive integer amount. It is rejected, writing nothing, when:
- it has fewer than two entries, or an amount that isn't a positive integer;
- debits don't equal credits for each currency (`Ledger::Unbalanced`);
- an entry's currency differs from its account's (`Ledger::CurrencyMismatch`);
- it would take an account's available balance below zero and that account doesn't allow
  negatives (`Ledger::InsufficientFunds`).

The transaction, its entries and the balance updates commit in one database transaction.
Each transaction records `effective_at` (business time, caller-supplied, defaults to now)
separately from `created_at` (system time), plus free-form `metadata`.

### Idempotency
Every write carries an idempotency key naming the business event (`payrun-4411-capture`),
not the attempt. The key is stored under a unique constraint with a SHA-256 hash of the
canonical payload.
- Same key, same payload: return the original result, move no money.
- Same key, different payload: `Ledger::ConflictError`, move no money.
- Concurrent requests with one key: exactly one transaction, returned to every caller. The
  unique index is the real guarantee; the loser of the race rescues the unique violation
  outside its rolled-back transaction, re-reads, and returns the winner's result.
- A failed write leaves no key behind, so a corrected retry succeeds.

### Balances and concurrency
A per-account balance row (`debits_minor`, `credits_minor`, `held_minor`, `version`) is
updated in the same database transaction as the entries. Posting locks the affected balance
rows with `SELECT ... FOR UPDATE` in ascending account id order, so concurrent postings can't
deadlock or overdraw. `version` increments on every change as an audit counter.

### Immutability
A `BEFORE UPDATE OR DELETE` row trigger on transactions and entries raises
`ledger rows are immutable`, so even `update_columns` or raw SQL fails. `TRUNCATE` is left
allowed so test cleanup works; the README notes that a deployed app's database role would
not hold `TRUNCATE`.

### Holds
A hold reserves money on an account before it is posted. Placing one checks available
balance like a posting does, adds to `held_minor`, and records it `active` (idempotent by its
own key and hash). From `active` a hold can be:
- **captured** for any amount up to the held amount: one database transaction posts the
  movement from the held account to a named counter account, removes the whole hold from
  `held_minor` (any uncaptured remainder simply becomes available again), and links the hold
  to the posted transaction;
- **released**: removes it from `held_minor`, posts nothing.

Repeating the action that already happened (a replayed capture with the same key, a second
release) returns the hold unchanged. Any other move out of a non-active state is
`Ledger::InvalidState`. Holds are mutable rows by design; money only ever moves in entries.

### Reversals
Mistakes are corrected with a new transaction that references the original (`reverses_id`)
and flips every entry's direction with the same amounts, going through the same posting path
(locks, balance checks, idempotency). A transaction can be reversed at most once (unique
index on `reverses_id`, which also settles races), and a reversal can't itself be reversed;
re-post instead. Both stay visible and net to zero. A reversal can fail with
`InsufficientFunds` if the money has since been spent, and that is correct.

### HTTP API
JSON under `/v1`, authenticated with `Authorization: Bearer <LEDGER_API_TOKEN>` (compared
with `ActiveSupport::SecurityUtils.secure_compare`). Every write requires an
`Idempotency-Key` header. First success returns 201; a replay returns the original body with 200.

| Method and path | Purpose |
|---|---|
| `POST /v1/transactions` | Post `{entries: [{account_code, direction, amount_minor}], effective_at?, metadata?}` |
| `GET /v1/transactions/:id` | Transaction with its entries, `reverses_id` and `reversed_by_id` |
| `POST /v1/transactions/:id/reversal` | Reverse a transaction |
| `GET /v1/accounts/:code` | Account with `posted_minor`, `held_minor`, `available_minor` |
| `POST /v1/holds` | Place `{account_code, amount_minor}` |
| `POST /v1/holds/:id/capture` | Capture `{counter_account_code, amount_minor}` |
| `POST /v1/holds/:id/release` | Release |

Errors are `{"error": {"code": "...", "message": "..."}}` with stable codes:
`unbalanced` 422, `currency_mismatch` 422, `insufficient_funds` 422,
`idempotency_conflict` 409, `invalid_state` 409, `not_found` 404, `unauthorized` 401.

## How we know it works

| Proof | What it shows |
|---|---|
| Randomized trial balance | After ~2,000 random valid postings, debits equal credits per currency and every balance row equals the sum of its entries; prints the seed on failure |
| Concurrency | 20 threads each spend $100 from a $500 account: exactly 5 succeed and the balance ends at 0, never negative |
| Idempotency | Replay returns the original; a different payload conflicts; 10 concurrent duplicates make one transaction; a failed post leaves no key |
| Immutability | Update and delete of entries and transactions fail in the database, including raw SQL |
| Reversal | Nets to zero, both visible; second reversal and reversal-of-reversal rejected, including under a race |
| Holds | Available = posted - held; capture less than held, release, replays, invalid transitions, overdraft via holds |
| API | Request specs for each endpoint, auth, and every error code |

Thread-based specs run against real Postgres with transactional fixtures off, truncating afterwards.

## Decided, and why

- **A stored balance table**, not balances computed from entries on each read. Computing on
  read makes the overdraft check a race unless the account is locked anyway.
- **Pessimistic locking in a fixed order**, not optimistic locking with retries. Retries under
  contention make the concurrency proof noisy; `version` stays as an audit counter.
- **The model is `LedgerTransaction`** (table `ledger_transactions`), to avoid clashing with
  ActiveRecord's `transaction` method.
- **Entries copy their account's currency**, so per-currency balancing is one `GROUP BY` and
  can be checked in SQL.
- **Writes go through service objects** in `ledger/app/services/ledger/` (post, place/capture/
  release hold, reverse, balance); controllers and models never insert entries directly.

## Left to the builder

- Exact file split inside `app/services/ledger/` and the controllers, and serializer style.
- Canonical JSON details for the request hash, as long as logically equal payloads hash equal
  (entry order must not matter).
- How the test suite truncates after thread-based specs, and the GitHub Actions CI setup
  (rspec and rubocop on push, with a Postgres service).
- README wording, as long as it says all data is invented, shows how to run it with curl
  examples, and lists each guarantee with the test that proves it.

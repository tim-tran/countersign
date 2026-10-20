# Ledger core: tasks

Status: Draft. Work top to bottom; each task ends with its test passing and one commit.

- [ ] **T0 Scaffold.** `rails new ledger --api -d postgresql -T`, add RSpec + FactoryBot, switch to
  `structure.sql`, CI workflow running rspec + rubocop on push. Test: an empty spec suite runs green in CI.
- [ ] **T1 Accounts and balance math** (R1). Migration, `Account`, `AccountBalance` created with each
  account, `Ledger::Balance`. Test: debit-normal and credit-normal balances computed correctly.
- [ ] **T2 Post balanced transactions** (R2). `ledger_transactions`, `entries`, `Ledger::PostTransaction`
  with validation and atomic write. Tests: unbalanced, single-entry, zero/negative amount,
  currency mismatch all rejected and write nothing; valid post writes everything.
- [ ] **T3 Randomized trial balance** (R9.1). Test only, using T2. Fails loudly with the seed on failure.
- [ ] **T4 Idempotency** (R3). Key + request hash, fast path, `RecordNotUnique` rescue. Tests: the four
  cases from the plan (replay, conflict, 10-thread race, failed post leaves no key).
- [ ] **T5 Balance locking and overdraft protection** (R4). Fixed-order `FOR UPDATE`, version bump,
  `InsufficientFunds`. Test: 20 x $100 against $500, exactly 5 succeed, balance never negative.
- [ ] **T6 Immutability** (R5). Trigger migration. Tests: `update`, `update_columns`, `destroy`,
  `delete_all` and raw SQL on entries and transactions all raise.
- [ ] **T7 Holds** (R6). Table, place/capture/release services, `held_minor`. Tests: available
  balance math, capture less than held, release, replays, invalid transitions, overdraft via holds.
- [ ] **T8 Reversals** (R7). `ReverseTransaction`. Tests: nets to zero, both visible, second reversal
  and reversal-of-reversal rejected, concurrent double reversal yields one.
- [ ] **T9 HTTP API** (R8). Controllers, bearer auth, `Idempotency-Key`, error mapping, 201 vs 200 on
  replay. Request specs for every endpoint and error code.
- [ ] **T10 Seeds and README** (invented chart of accounts, "all data is invented" notice,
  how to run, curl examples, a short "guarantees and how they're proven" section linking the specs).

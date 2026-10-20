# Ledger core: requirements

Status: Draft (awaiting Tim's review)

## Purpose

Money must never be created, lost or paid twice. The ledger is the single component that
records money movement for Countersign. Everything else (rules engine, review agent) proposes;
only the ledger posts, and only through its API.

## Users

- **Payroll service / operator**: posts approved pay runs and corrections.
- **Review agent (later)**: reads balances and transactions. It never posts directly; a human
  approval step sits between the agent and any write (designed in a later spec).
- **Auditor**: needs to see every movement, including mistakes and their corrections.

## Glossary

- **Minor units**: integer cents. `$100.00` is `10000`.
- **Transaction**: one atomic business event made of two or more entries.
- **Entry**: one debit or credit line against one account.
- **Normal side**: the side (debit or credit) that increases an account's balance.
- **Hold**: money reserved on an account that is not yet posted.
- **Available balance**: posted balance minus active holds.

## Requirements

### R1 Accounts
- R1.1 THE SYSTEM SHALL store accounts with a unique `code`, a `kind` (asset, liability,
  equity, revenue, expense), a `normal_side` (debit or credit), a single ISO currency and an
  `allow_negative` flag.
- R1.2 WHEN an account's balance is requested THE SYSTEM SHALL compute it with one function
  using the account's normal side (debits minus credits for debit-normal, the reverse for credit-normal).

### R2 Posting balanced transactions
- R2.1 WHEN a transaction is posted THE SYSTEM SHALL require at least two entries, each with a
  positive integer `amount_minor`.
- R2.2 IF total debits do not equal total credits for each currency in the transaction THEN THE
  SYSTEM SHALL reject it with `Ledger::Unbalanced` and write nothing.
- R2.3 IF an entry's currency differs from its account's currency THEN THE SYSTEM SHALL reject the transaction.
- R2.4 THE SYSTEM SHALL write a transaction and all of its entries in one database transaction (all or nothing).
- R2.5 THE SYSTEM SHALL record `effective_at` (business time, caller-supplied, defaults to now)
  separately from `created_at` (system time), plus free-form `metadata`.

### R3 Idempotency
- R3.1 THE SYSTEM SHALL require an idempotency key on every write, unique across transactions.
- R3.2 WHEN a write is replayed with the same key and the same payload THE SYSTEM SHALL return
  the original transaction and move no money.
- R3.3 WHEN a write uses an existing key with a different payload THE SYSTEM SHALL raise
  `Ledger::ConflictError` and move no money.
- R3.4 WHEN concurrent requests share a key THE SYSTEM SHALL create exactly one transaction and
  return it to every caller.
- R3.5 IF a write fails THEN THE SYSTEM SHALL leave no record of its key, so a corrected retry can succeed.

### R4 Balances and concurrency
- R4.1 THE SYSTEM SHALL maintain a per-account balance row updated in the same database
  transaction as the entries.
- R4.2 IF a posting would take an account's available balance below zero and the account does not
  allow negatives THEN THE SYSTEM SHALL reject it with `Ledger::InsufficientFunds`.
- R4.3 WHEN 20 concurrent requests each spend $100 from an account holding $500 THE SYSTEM SHALL
  accept exactly 5 and the balance SHALL never be negative.
- R4.4 THE SYSTEM SHALL lock accounts in a fixed order so concurrent postings cannot deadlock.

### R5 Immutability
- R5.1 IF any client, including the application itself, tries to UPDATE or DELETE a transaction
  or entry row THEN the database SHALL refuse it.

### R6 Holds
- R6.1 WHEN a hold is placed THE SYSTEM SHALL reserve the amount against the account's available
  balance, subject to R4.2, and record it as `active`.
- R6.2 WHEN an active hold is captured THE SYSTEM SHALL post a transaction for it (any amount up
  to the held amount) and mark the hold `captured`.
- R6.3 WHEN an active hold is released THE SYSTEM SHALL mark it `released` and post nothing.
- R6.4 IF a hold that is not active is captured or released THEN THE SYSTEM SHALL reject the request
  with `Ledger::InvalidState`, except that repeating the action that already happened (a replayed
  capture with the same key, or a second release) SHALL return the hold unchanged.

### R7 Reversals
- R7.1 WHEN a transaction is reversed THE SYSTEM SHALL post a new transaction referencing the
  original (`reverses_id`) with every entry's direction flipped and the same amounts.
- R7.2 THE SYSTEM SHALL allow a transaction to be reversed at most once, and SHALL NOT allow a
  reversal to be reversed. (Re-post a new transaction instead.)
- R7.3 After a reversal, both transactions SHALL remain visible and the net effect on every account SHALL be zero.

### R8 API
- R8.1 THE SYSTEM SHALL expose posting, holds, reversal, balance and transaction reads over a JSON
  HTTP API, authenticated with a bearer token.
- R8.2 Every write endpoint SHALL require an `Idempotency-Key` header and map domain errors to
  stable error codes (`unbalanced` 422, `insufficient_funds` 422, `idempotency_conflict` 409,
  `not_found` 404, `invalid_state` 409).

### R9 Proof
- R9.1 A randomized test SHALL post thousands of random valid transactions and show total debits
  equal total credits and every stored balance equals the sum of its entries.

## Out of scope / later
- Multi-currency transactions with FX (one currency per account; a transaction may span
  currencies only if each currency balances on its own).
- Human approval workflow, decision log, outbox events (specs `review-agent`, `decision-log`, `event-stream`).
- Users, roles, multi-tenancy. One shared API token is enough for now.
- Partial captures that leave a hold open, hold expiry, scheduled postings.
- Period close, statements, reporting UI.

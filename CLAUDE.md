# Countersign

Portfolio project: an AI-assisted payroll review system with an audited double-entry ledger.
All pay rules, rates, people and amounts are invented. Nothing here models a real company's system.

## Layout

- `ledger/` Rails API app. The only component that moves money.
- `agent/` Python LangGraph review agent (later). Reaches the ledger only through its HTTP API.
- `specs/` One folder per feature, named in kebab-case without number prefixes (`ledger-core/`, `pay-rules/`, ...). Build order lives in the project plan, not in folder names.

## Spec-driven workflow

Every feature goes through three files in `specs/<feature-name>/`, in this order:

1. `requirements.md` What and why. User stories plus numbered acceptance criteria (`R1.2`)
   written as EARS-style statements: `WHEN <trigger> THE SYSTEM SHALL <behaviour>`.
2. `design.md` How. Schema, interfaces, invariants, concurrency, errors, and which
   requirement each design choice satisfies. Records rejected alternatives briefly.
3. `tasks.md` Ordered, small tasks. Each one names the requirement IDs it covers and the
   test that proves it. A task is done when its test passes and the box is ticked.

Rules:

- No implementation code for a feature until its `requirements.md` and `design.md` are
  marked `Status: Approved` by Tim.
- Work one task at a time, in order. Write the failing test from the acceptance criteria
  first, then the code. One task per commit; the commit message names the task (`T3`).
- If the code needs to differ from the spec, stop and update the spec first (and say so).
  The spec is the source of truth, not the code.
- Out-of-scope ideas go in the spec's "Out of scope / later" section, not into the code.
- Keep scope small: the whole project must be doable solo in about three months.

## Dependencies

- Use the latest stable release of every language, framework and library (no pre-releases).
  Pin what was resolved in lockfiles; upgrade deliberately, one dependency per commit.

## Ledger conventions

- Money is always an integer in minor units (`amount_minor`, cents). Never floats or BigDecimal in the domain.
- Ledger writes go through service objects in `ledger/app/services/ledger/`; controllers and
  models never insert entries directly.
- Every invariant that matters is enforced in Postgres (constraints, triggers), not only in Ruby.
- Tests: RSpec. Concurrency tests use real threads against real Postgres, with
  transactional fixtures off for those examples.

## Commands (ledger/)

- `bin/setup` install gems and prepare the database
- `bundle exec rspec` run all tests
- `bundle exec rubocop` lint

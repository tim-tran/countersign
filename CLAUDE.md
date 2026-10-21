# Countersign

Portfolio project: an AI-assisted payroll review system with an audited double-entry ledger.
All pay rules, rates, people and amounts are invented. Nothing here models a real company's system.

## Layout

- `ledger/` Rails API app. The only component that moves money.
- `agent/` Python LangGraph review agent (later). Reaches the ledger only through its HTTP API.
- `docs/superpowers/specs/` Approved designs, one per feature (`YYYY-MM-DD-<topic>-design.md`).
- `docs/superpowers/plans/` Implementation plans written from those designs.

## Constraints

- Keep scope small: the whole project must be doable solo in about three months.
- Use the latest stable release of every language, framework and library (no pre-releases).
  Pin what was resolved in lockfiles; upgrade deliberately, one dependency per commit.
- Only change files inside this repository without asking. Anything outside it (installs,
  dotfiles, global config, background services) needs Tim's OK first.

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

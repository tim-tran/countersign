# Countersign

A double-entry payroll ledger, with an AI-assisted payroll review agent planned on top of it.
All data in this repository is invented.

- [`ledger/`](ledger/README.md): the Rails API app that holds the ledger (accounts, postings, holds, reversals), with the guarantees and the specs that prove them.
- [Ledger core design](docs/superpowers/specs/2026-10-21-ledger-core-design.md): the data model, invariants and trade-offs.

The review agent comes later; it is not part of this repository yet.

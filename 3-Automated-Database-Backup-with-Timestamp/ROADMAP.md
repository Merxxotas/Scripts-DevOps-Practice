# Roadmap — Module 3 (Database Backup Utility)

## Phase 1 — Core (done)
- [x] Bash implementation with CLI parser, guardrails, dump, compress, retain, audit, dry-run.
- [x] PowerShell implementation with parity.
- [x] Bash test suite (stubbed dump tool), 26 tests, 0 failures.

## Phase 2 — Hardening
- [ ] PowerShell test suite (stubbed dump tool).
- [ ] Parity proof across the two implementations.
- [ ] Native review (RDD) of the implementation.

## Phase 3 — Documentation
- [x] SPECS.md, README.md, CODESTYLE.md.
- [ ] ROADMAP.md milestones (this file).
- [ ] docs/ARCHITECTURE_COMPARISON.md, docs/SCENARIOS.md, docs/labs/LAB1-3.md.
- [ ] Wiki pages 16-18 + sidebar + home + architecture page.

## Phase 4 — CI and registration
- [x] CI workflow `.github/workflows/ci-database-backup.yml`.
- [ ] MODULES.md row + root README table row + CHANGELOG entry.
- [ ] Full local matrix verification; close with a `Risk:` line.
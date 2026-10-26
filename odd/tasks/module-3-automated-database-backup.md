# Module 3 — Automated Database Backup with Timestamp

> **Branch:** `feat/3-automated-database-backup` (to be created from `main`)
> **Module folder:** `3-Automated-Database-Backup-with-Timestamp/`
> **Seed:** `db_backup.sh` (1363 bytes) + `db_backup.ps1` (2284 bytes), written 2026-03-09, never committed.
> **Backends:** MySQL (`mysqldump`) and PostgreSQL (`pg_dump`) — MSSQL dropped per scoping decision.
> **Status:** Draft — feature document created; implementation pending.

---

## Specs

### S1 — Scope and module identity

The module is a **database backup utility**: it runs a database dump, compresses the result, stores
it in a backup directory, and prunes backups older than a retention window. It ships as Bash + PowerShell
with full parity, plus tests, docs, CI and wiki pages, per the module contract in `AGENTS.md` §3.

### S2 — Command line interface

Bash flags (short/long): `-t/--db-type`, `-n/--db-name`, `-u/--db-user`, `--db-password`,
`-d/--backup-dir`, `-r/--retention-days`, `-c/--compress` (on/off), `--dry-run`, `-l/--log-file`,
`-v/--verbose`, `-h/--help`. PowerShell params: `-DbType`, `-DbName`, `-DbUser`, `-DbPassword`,
`-BackupDir`, `-RetentionDays`, `-Compress`, `-DryRun`, `-LogFile`, `-Verbose`, `-Help`.

Defaults: db-type `mysql`, db-name `mydatabase`, db-user `backup_user`, backup-dir `./backups`
(Bash) / `C:\Backups\Database` (PowerShell), retention-days `7`, compress `true`.

### S3 — Credential handling

The password is read from `--db-password` → `DB_BACKUP_PASSWORD` env → (no file default). It is
**never** hardcoded, never echoed, never logged in full. A missing password is a configuration error
(exit 1) unless the backend does not require one (none in this module). The password is passed to the
dump tool via its native env var (`MYSQL_PWD`, `PGPASSWORD`) so it does not appear in `ps`.

### S4 — Safety guardrails

- **Path blacklist:** refuse to operate on `/`, `C:\`, `/etc`, `/var`, system directories for the
  backup directory.
- **Existence/permission checks:** backup dir must be creatable/writable.
- **Dry-run:** preview the dump command, target file, compression and retention pruning without
  touching the filesystem or invoking the dump tool.
- **Exit codes:** `0` success, `1` configuration/safety violation, `2` partial failure (dump failed,
  or compression failed, or a retention delete failed).

### S5 — Backup flow

1. Parse + validate flags.
2. Resolve credentials (env/flag). Fail (exit 1) if missing.
3. Validate backup dir (blacklist, creatable). Create if missing.
4. Build timestamp `YYYYMMDD_HHMMSS` and target filename
   `<dbtype>_<dbname>_<timestamp>.sql`.
5. If dry-run: print the planned actions and exit 0 without invoking the dump tool.
6. Invoke the dump tool (`mysqldump`/`pg_dump`) with the resolved credentials, writing to the target
   file. On failure: exit 2 (partial) and log the error.
7. Compress the file (gzip on Bash, zip on PowerShell) and remove the raw `.sql`.
8. Prune backups older than retention-days (by mtime) in the backup dir matching the module's glob.
9. Write an ISO-8601 audit line per run (usage, outcome, files pruned).
10. Exit 0 on full success.

### S6 — Testing strategy

Tests stub `mysqldump`/`pg_dump` on `PATH` (like module 1 stubs `df` and the mail agent). The stub
writes a known payload to the output file and records its invocation. Suites assert: flags, exit codes,
emitted files, dry-run (no dump invoked), guardrails (blacklist), retention pruning, audit log, and
credential handling (password not in argv/audit). Parity tests compare the two implementations' flag
sets. No real database required.

### S7 — Documentation and CI

Module ships `README.md`, `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `tests/`, `docs/`
(ARCHITECTURE_COMPARISON.md, SCENARIOS.md, labs/LAB1-3.md), plus a root
`.github/workflows/ci-database-backup.yml` (path-filtered, multi-OS matrix), a `MODULES.md` row, a
`README.md` table row, and wiki pages 16-18.

### S8 — Scope exclusions (v1)

No incremental/differential backups, no streaming to cloud storage, no MSSQL, no encryption of the
backup file, no `--json`/`--csv` output. One database per invocation. Audit write is best-effort.

---

## Tasks

| ID | Specs | Task | Route | Status | Evidence |
| :--- | :--- | :-- | :-- | :-- | :--- |
| T0 | S1 | Create branch `feat/3-automated-database-backup` from `main` | Inline | ⬜ | — |
| T1 | S2, S3, S4, S5 | Bash implementation: CLI parser, validation, guardrails, dump, compress, retain, audit, dry-run | Inline | ⬜ | — |
| T2 | S2, S3, S4, S5 | PowerShell implementation with full parity | Inline | ⬜ | — |
| T3 | S6 | Bash test suite (stubbed dump tool) | Inline | ⬜ | — |
| T4 | S6 | PowerShell test suite (stubbed dump tool) | Inline | ⬜ | — |
| T5 | S6 | Parity proof across the two implementations | Inline | ⬜ | — |
| T6 | S7 | `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md` | Delegated | ⬜ | — |
| T7 | S7 | `docs/ARCHITECTURE_COMPARISON.md`, `docs/SCENARIOS.md`, `docs/labs/LAB1-3.md` | Delegated | ⬜ | — |
| T8 | S7 | CI workflow `.github/workflows/ci-database-backup.yml` | Inline | ⬜ | — |
| T9 | S7 | Wiki pages 16-18 + sidebar + home + architecture page | Delegated | ⬜ | — |
| T10 | S7 | `MODULES.md`, root `README.md`, `CHANGELOG.md` registration | Inline | ⬜ | — |
| T11 | S5, S6 | Full local matrix verification; close with a `Risk:` line | Inline | ⬜ | — |

### Route declaration and trigger evidence

T1–T5 are inline and sequential: the PowerShell side mirrors the Bash side's observed behaviour, exactly
as in modules 1 and 2. The parallel trigger needs independent units; these are not independent.

T6, T7, T9 are delegated, in parallel, once the implementation is stable: four independent units of
documentation with disjoint edit surfaces.

T8 and T10 are inline (small, mechanical).

### Forecast

~1,500 authored changed lines, against module 1's 5,854 and module 2's smaller volume. The documentation
will be roughly 50 % of the volume, as in modules 1 and 2.

---

## Environment Setup

- **Bash:** GNU bash 4+, `gzip`, `find`, `mktemp`, `stat`. No database client needed for tests (stubbed).
- **PowerShell:** 5.1+ / 7+, no database client needed for tests (stubbed).
- **Tests:** Bash suite runs with `bash tests/test_db_backup.sh`; PowerShell suite runs with `pwsh`.
- **CI:** path-filtered workflow, multi-OS matrix (Linux, macOS, Windows).

---

## Log

**L1** — 2026-10-26. User request, verbatim: "continue with next task or next folder" (after PR #5 merged to main). Module 3 selected per build order in MODULES.md.

**L2** — 2026-10-26. Scoping decision: backends = MySQL + PostgreSQL only (MSSQL dropped). Tests stub
`mysqldump`/`pg_dump` on PATH, mirroring module 1's stub pattern. Compression: gzip on Bash, zip on
PowerShell (platform-native). Retention by mtime. Exit codes 0/1/2. Credential from env/flag, never
hardcoded.

## Close

Pending.
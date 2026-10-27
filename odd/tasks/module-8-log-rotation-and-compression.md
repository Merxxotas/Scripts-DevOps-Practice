# Module 8 — Log Rotation and Compression

Branch: feat/8-log-rotation-and-compression
Delivery strategy: ask-on-risk
Test runner: bash tests/test_log_rotate.sh / pwsh tests/test_log_rotate.ps1

## Specs

S1 — Log file selection and defaults. The script accepts a target log file via `-f/--log-file` (Bash) / `-LogFile` (PowerShell), defaulting to `/var/log/app/application.log` (Bash) / `C:\Logs\application.log` (PowerShell). A missing/empty value is a configuration error (exit 1).

S2 — Size threshold. `-m/--max-size-mb` (Bash) / `-MaxSizeMB` (PowerShell) sets the rotation threshold in megabytes (default 10). The value must be a non-negative integer; a negative or non-numeric value is a configuration error (exit 1). Rotation triggers only when the log file size strictly exceeds the threshold (or `--force` is given).

S3 — Backup count. `-c/--backup-count` (Bash) / `-BackupCount` (PowerShell) sets how many rotated backups to retain (default 5). Must be a positive integer; 0 or negative or non-numeric is a configuration error (exit 1).

S4 — Compression toggle. Compression is on by default (`-z/--compress` / `-Compress` is implicit). `--no-compress` (Bash) / `-NoCompress` (PowerShell) disables compression; the rotated backup is kept as a raw file. Compression uses gzip (`.gz`) on Bash and zip (`.zip`) on PowerShell.

S5 — Force rotation. `--force` (Bash) / `-Force` (PowerShell) rotates regardless of file size.

S6 — Dry-run. `--dry-run` (Bash) / `-DryRun` (PowerShell) prints the planned rotation (backup renames, compression, truncation, pruning) and exits 0 without touching any file.

S7 — Audit log. `--audit-log` (Bash) / `-AuditLog` (PowerShell) appends an ISO-8601 timestamped line per run recording the outcome and the backup file. Best-effort (a write failure does not change the exit code).

S8 — Verbose. `-v/--verbose` (Bash) / `-Verbose` (PowerShell) prints per-step diagnostic detail.

S9 — Help. `-h/--help` (Bash) / `-Help` (PowerShell) prints usage and exits 0.

S10 — Safety guardrails. The script refuses to operate when the log file's resolved directory is a protected system root (`/`, `/etc`, `/var`, `/bin`, ... on POSIX; `C:\`, `C:\Windows`, ... on Windows) and exits 1. It also refuses a log file that does not exist (exit 1) and a log file that is a directory (exit 1).

S11 — Rotation mechanics. When rotation triggers: existing backups are shifted from highest index down to 1 (`.<i>.<ext>` -> `.<i+1>.<ext>`), the current log is copied to `.<1>.<ext>` (compressed when enabled), the current log is truncated to zero bytes, and any backup beyond `backup-count` is removed. The number of backups retained never exceeds `backup-count`.

S12 — No-op. When the file size is within the threshold and `--force` is not given, the script prints "no rotation needed" and exits 0 without modifying anything.

S13 — Exit codes. 0 success (including no-op and dry-run), 1 configuration or safety violation, 2 partial failure (a rename/compression/truncation/prune step failed).

S14 — Output contract. Colorized, human-readable console output with a summary block (log file, size, threshold, backups kept, rotated: yes/no).

S15 — Parity. Bash and PowerShell implement the same flags, defaults, exit codes and guardrails. The parity test compares the two flag sets.

S16 — Tests. Deterministic suite stubbing the filesystem under a temp dir; covers flags, exit codes, emitted files, dry-run, guardrails, retention pruning, audit log. No real system paths touched.

## Tasks

- [x] T1: Create feature document + Engram mirror (this file). route: inline
- [x] T2: Write SPECS.md, README.md, CODESTYLE.md, ROADMAP.md. route: inline
- [x] T3: Harden log_rotate.sh (CLI parser, guardrails, dry-run, exit codes, audit log). route: inline
- [x] T4: Harden log_rotate.ps1 (parity). route: inline
- [x] T5: Write Bash test suite tests/test_log_rotate.sh. route: inline (33 tests, 0 failures)
- [x] T6: Write PowerShell test suite tests/test_log_rotate.ps1. route: inline
- [x] T7: Write docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1-3). route: inline
- [x] T8: Create root CI workflow .github/workflows/ci-log-rotation.yml. route: inline
- [x] T9: Write wiki pages 19-21 + sidebar + Home. route: inline
- [x] T10: Register module in MODULES.md, README.md, CHANGELOG.md, AGENTS.md. route: inline
- [x] T11: Close feature document + Engram mirror. route: inline

## Log

L1: User request (verbatim): "Module 8 (Log Rotation and Compression) — seed on disk only. Convert it to the shipped contract following Module 1/3 as templates: SPECS.md, README.md, CODESTYLE.md, ROADMAP.md, hardened implementation with CLI parser/guardrails/dry-run/exit codes, tests/, docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs), root CI workflow, wiki pages, MODULES.md/README/CHANGELOG registration."

L2: 2026-10-27 — Created feature branch feat/8-log-rotation-and-compression from main (982220d). Feature document created.
L3: 2026-10-27 — Implemented all tasks. Bash suite: 33 tests, 0 failures. Risk: item 3 (new module added; contracts/docs/wiki registered).
L4: 2026-10-27 — CI fixes: shellcheck trailing lines, PS arg binding ($Args shadowing), PS lint warnings, macOS wc padding. Final run 40539743982 all jobs green.
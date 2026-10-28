# Module 4 — Service Monitor and Auto-Restart (CLOSED)

Branch: feat/4-service-monitor-and-auto-restart
Delivery strategy: ask-on-risk
Test runner: bash tests/test_service_monitor.sh / pwsh tests/test_service_monitor.ps1

## Specs

S1 — Service selection and defaults. The script accepts a target service via `-s/--service` (Bash) / `-ServiceName` (PowerShell), defaulting to `nginx` (Bash) / `w3svc` (PowerShell). A missing/empty value is a configuration error (exit 1).

S2 — Max retries. `-r/--max-retries` (Bash) / `-MaxRetries` (PowerShell) sets how many restart attempts are made when the service is down (default 3). Must be a positive integer; 0 or negative or non-numeric is a configuration error (exit 1).

S3 — Retry delay. `--retry-delay` (Bash) / `-RetryDelaySeconds` (PowerShell) sets the seconds to wait between restart attempts (default 5). Must be a non-negative integer; a negative or non-numeric value is a configuration error (exit 1).

S4 — Dry-run. `--dry-run` (Bash) / `-DryRun` (PowerShell) prints the planned monitoring/restart actions and exits 0 without touching the service.

S5 — Audit log. `--audit-log` (Bash) / `-AuditLog` (PowerShell) appends an ISO-8601 timestamped line per run recording the outcome. Best-effort (a write failure does not change the exit code).

S6 — Verbose. `-v/--verbose` (Bash) / `-Verbose` (PowerShell) prints per-step diagnostic detail.

S7 — Help. `-h/--help` (Bash) / `-Help` (PowerShell) prints usage and exits 0.

S8 — Safety guardrails. The service name must match the platform's valid service-name pattern (`^[a-zA-Z0-9_.@-]+$` on POSIX; `^[a-zA-Z0-9_.-]+$` on Windows); an invalid name is a configuration error (exit 1). The script refuses a service that does not exist / is not installed (exit 1).

S9 — Monitoring. When the service is running/active, the script prints a success message and exits 0 without restarting.

S10 — Auto-restart. When the service is down/inactive, the script attempts to restart it up to `max-retries` times, waiting `retry-delay` seconds between attempts. On success it logs a notification (syslog on Bash, Windows Event Log on PowerShell) and exits 0. After exhausting retries it prints a failure message and exits 2.

S11 — Exit codes. 0 success (running or restarted, including dry-run), 1 configuration or safety violation (bad args, invalid service name, service not found), 2 partial failure (restart failed after retries).

S12 — Output contract. Colorized, human-readable console output with a summary block (service, status, retries used, result).

S13 — Parity. Bash and PowerShell implement the same flags, defaults (platform-native service name), exit codes and guardrails. The parity test compares the two flag sets.

S14 — Tests. Deterministic suite stubbing the service manager under a temp dir / mock; covers flags, exit codes, dry-run, guardrails, restart success/failure, audit log. No real system services mutated in tests.

## Tasks

- [x] T1: Create feature document + Engram mirror (this file). route: inline
- [x] T2: Write SPECS.md, README.md, CODESTYLE.md, ROADMAP.md. route: inline
- [x] T3: Harden service_monitor.sh (CLI parser, guardrails, dry-run, exit codes, audit log). route: inline
- [x] T4: Harden service_monitor.ps1 (parity). route: inline
- [x] T5: Write Bash test suite tests/test_service_monitor.sh. route: inline (20 tests, 0 failures)
- [x] T6: Write PowerShell test suite tests/test_service_monitor.ps1. route: inline
- [x] T7: Write docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1-3). route: inline
- [x] T8: Create root CI workflow .github/workflows/ci-service-monitor.yml. route: inline
- [x] T9: Write wiki pages + sidebar. route: inline
- [x] T10: Register module in MODULES.md, README.md, CHANGELOG.md, AGENTS.md. route: inline
- [x] T11: Close feature document + Engram mirror. route: inline

## Log

L1: User request (verbatim): "Module 4 (Service Monitor and Auto-Restart) — seed on disk only. Convert it to the shipped contract following Module 1/3/8 as templates: SPECS.md, README.md, CODESTYLE.md, ROADMAP.md, hardened implementation with CLI parser/guardrails/dry-run/exit codes, tests/, docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs), root CI workflow, wiki pages, MODULES.md/README/CHANGELOG registration."

L2: 2026-10-28 — Created feature branch feat/4-service-monitor-and-auto-restart from main. Feature document created.
L3: 2026-10-28 — Implemented all tasks. Bash suite: 20 tests, 0 failures. Risk: item 3 (new module added; contracts/docs/wiki registered).

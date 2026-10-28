# Module 7 — Find and Kill High-CPU Processes (CLOSED)

Branch: feat/7-find-and-kill-high-cpu-processes
Delivery strategy: ask-on-risk
Test runner: bash tests/test_kill_high_cpu.sh / pwsh tests/test_kill_high_cpu.ps1

## Specs

S1 — Threshold. `-t/--threshold` (Bash) / `-CpuThreshold` (PowerShell) sets the CPU percentage above which a process is a candidate (default 50.0). Must be a non-negative number; a negative or non-numeric value is a configuration error (exit 1).

S2 — Auto-kill. `--auto-kill` (Bash) / `-AutoKill` (PowerShell) kills every candidate without prompting. By default the script prompts per candidate (y/n).

S3 — Dry-run. `--dry-run` (Bash) / `-DryRun` (PowerShell) lists candidates and prints what would be killed, without signaling any process. Exit 0.

S4 — Force. `--force` (Bash) / `-Force` (PowerShell) sends SIGKILL/Stop-Process -Force instead of the default graceful signal (SIGTERM).

S5 — Audit log. `--audit-log` (Bash) / `-AuditLog` (PowerShell) appends an ISO-8601 timestamped line per run recording the outcome and count killed. Best-effort.

S6 — Verbose. `-v/--verbose` (Bash) / `-Verbose` (PowerShell) prints per-step diagnostic detail.

S7 — Help. `-h/--help` (Bash) / `-Help` (PowerShell) prints usage and exits 0.

S8 — Guardrails. The script refuses to target PID 0, PID 1, itself, its parent, or kernel threads (comm in brackets). An invalid threshold is a configuration error (exit 1).

S9 — Discovery. The script lists processes whose CPU usage strictly exceeds the threshold.

S10 — Action. In interactive mode it prompts per candidate; in auto-kill mode it kills without prompting. On success it records the action (syslog on Bash best-effort; console on PS). After exhausting candidates it exits 0. A failed kill exits 2.

S11 — Exit codes. 0 success (including no candidates and dry-run), 1 configuration or safety violation, 2 partial failure (a kill failed).

S12 — Output contract. Colorized, human-readable console output listing candidates (PID, command, CPU%) and a summary block.

S13 — Parity. Bash and PowerShell implement the same flags, defaults, exit codes and guardrails. The parity test compares the two flag sets.

S14 — Tests. Deterministic suite stubbing the process manager under a temp dir / mock; covers flags, exit codes, dry-run, guardrails, kill success/failure, audit log. No real process is killed.

## Tasks

- [x] T1: Create feature document + Engram mirror (this file). route: inline
- [x] T2: Write SPECS.md, README.md, CODESTYLE.md, ROADMAP.md. route: inline
- [x] T3: Harden kill_high_cpu.sh. route: inline
- [x] T4: Harden kill_high_cpu.ps1. route: inline
- [x] T5: Write Bash test suite tests/test_kill_high_cpu.sh. route: inline (22 tests, 0 failures)
- [x] T6: Write PowerShell test suite tests/test_kill_high_cpu.ps1. route: inline
- [x] T7: Write docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1-3). route: inline
- [x] T8: Create root CI workflow .github/workflows/ci-kill-high-cpu.yml. route: inline
- [x] T9: Write wiki pages + sidebar. route: inline
- [x] T10: Register module in MODULES.md, README.md, CHANGELOG.md, AGENTS.md. route: inline
- [x] T11: Close feature document + Engram mirror. route: inline

## Log

L1: User request (verbatim): "Module 7 (Find and Kill High-CPU Processes) — seed on disk only. Convert it to the shipped contract following Module 1/3/8 as templates: SPECS.md, README.md, CODESTYLE.md, ROADMAP.md, hardened implementation with CLI parser/guardrails/dry-run/exit codes, tests/, docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs), root CI workflow, wiki pages, MODULES.md/README/CHANGELOG registration."

L2: 2026-10-28 — Created feature branch feat/7-find-and-kill-high-cpu-processes from main. Feature document created.
L3: 2026-10-28 — Implemented all tasks. Bash suite: 22 tests, 0 failures. Risk: item 3 (new module added; contracts/docs/wiki registered).

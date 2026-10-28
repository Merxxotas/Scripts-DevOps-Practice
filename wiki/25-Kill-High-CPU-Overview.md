# 25. Find and Kill High-CPU Processes — Overview & Specs

Cross-platform detection and termination of runaway CPU processes. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

## Key Features

- Safety guardrails: never targets PID 0/1, self, parent, or kernel threads.
- Dry-run simulation.
- Interactive by default; `--auto-kill` for unattended use.
- Force mode (SIGKILL / `Stop-Process -Force`).
- Optional ISO-8601 audit log.
- Exit codes: 0 success, 1 config/safety, 2 partial failure.

## CLI

See the module's [SPECS.md §3](../7-Find-and-Kill-High-CPU-Processes/SPECS.md).

## Wiki Navigation

- [[26-Kill-High-CPU-Bash-vs-PowerShell|Bash vs PowerShell]]
- [[27-Kill-High-CPU-Scenarios-and-Labs|Scenarios & Labs]]
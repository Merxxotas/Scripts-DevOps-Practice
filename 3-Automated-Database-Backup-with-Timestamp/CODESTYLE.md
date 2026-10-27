# Code Style Guide — Module 3 (Database Backup Utility)

Extends the repository baseline in [`CONTRIBUTING.md`](../CONTRIBUTING.md) §Code Standards and
[`AGENTS.md`](../AGENTS.md) §7.

## Naming

- Bash: `snake_case` functions and variables; `UPPER_SNAKE_CASE` constants.
- PowerShell: `Verb-Noun` functions, `PascalCase` parameters.
- CLI flags: `kebab-case` (Bash), `PascalCase` params (PowerShell).
- Exit codes: `0` success, `1` config/safety, `2` partial failure — documented in README.

## Logging

- No `print()`/`Write-Host` for errors in production paths except user-facing messages.
- Structured audit lines when `--log-file` is given; password never logged.
- Catch specific exceptions; every destructive/long-running action writes an audit line.

## Shell specifics

- Bash: `set -euo pipefail`, `IFS=$'\n\t'`, quote expansions, `[[ ]]`, `$(...)`.
- `--help` exits 0.
- Guardrails: refuse system paths; dry-run must not mutate state.

## Parity

- Bash and PowerShell implement the same flags, defaults, exit codes and guardrails.
- A flag on only one side is a defect.
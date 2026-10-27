# Code Style Guide — Module 8 (Log Rotation and Compression)

All rules in the root [CONTRIBUTING.md](../CONTRIBUTING.md) and [AGENTS.md](../AGENTS.md)
§7 apply. Module-specific additions:

## Naming
- Bash script: `log_rotate.sh`. PowerShell script: `log_rotate.ps1`.
- Test files: `tests/test_log_rotate.sh`, `tests/test_log_rotate.ps1`.
- Backups: `<logfile>.1.gz` (Bash) / `<logfile>.1.zip` (PowerShell); raw when `--no-compress`.

## Implementation
- Bash starts with `set -euo pipefail` and `IFS=$'\n\t'`.
- PowerShell uses `#Requires -Version 5.1` and approved verbs.
- Color output uses the standard palette (RED/GREEN/YELLOW/BLUE/CYAN/RESET).
- All user-facing strings and comments in English.
- Lines under 100 characters.

## Guardrails
- Refuse protected system roots (see SPECS.md §5).
- Require an existing regular log file.
- Validate numeric arguments before use.

## Tests
- Every test runs under a temp directory created with `mktemp -d`.
- No real system paths are touched.
- Stub `gzip`/`Compress-Archive` only when needed; prefer real tools on temp files.
- Parity test compares the two flag sets.
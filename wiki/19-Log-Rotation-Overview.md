# 19. Log Rotation — Overview & Specs

Cross-platform log rotation with compression and retention for a single log file.
Available in **POSIX Bash** (Linux/macOS) and **PowerShell** (Windows), with 100%
feature parity.

## Key Features

- Safety guardrails against protected system roots.
- Dry-run simulation.
- Compression: gzip (Bash) / zip (PowerShell).
- Retention: keep the most recent N backups.
- Optional ISO-8601 audit log.
- Exit codes: 0 success, 1 config/safety, 2 partial failure.

## CLI

See the module's [SPECS.md §3](../8-Log-Rotation-and-Compression/SPECS.md).

## Wiki Navigation

- [Bash vs PowerShell](20-Log-Rotation-Bash-vs-PowerShell)
- [Scenarios & Labs](21-Log-Rotation-Scenarios-and-Labs)
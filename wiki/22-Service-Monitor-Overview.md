# 22. Service Monitor and Auto-Restart — Overview & Specs

Cross-platform service monitoring with automatic restart. Available in **POSIX Bash**
(Linux/macOS, via `systemctl`) and **PowerShell** (Windows, via `Get-Service`), with 100%
feature parity.

## Key Features

- Safety guardrails: service-name validation and existence check.
- Dry-run simulation.
- Auto-restart with configurable retries and delay.
- Optional ISO-8601 audit log.
- Notifications: syslog (Bash) / Windows Event Log (PowerShell).
- Exit codes: 0 success, 1 config/safety, 2 partial failure.

## CLI

See the module's [SPECS.md §3](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/4-Service-Monitor-And-Auto-Restart/SPECS.md).

## Wiki Navigation

- [Bash vs PowerShell](23-Service-Monitor-Bash-vs-PowerShell)
- [Scenarios & Labs](24-Service-Monitor-Scenarios-and-Labs)
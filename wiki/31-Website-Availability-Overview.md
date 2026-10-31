# 31. Website Availability (HTTP Health Check) — Overview & Specs

Cross-platform HTTP health check for a single URL. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

## Key Features

- Safety guardrails: validates URL scheme, timeout and expected code before any request.
- Dry-run simulation: prints target/expected/timeout, no request.
- Metrics: status code, response time, response size.
- Optional SSL certificate expiry reporting (HTTPS only, opt-in).
- Optional ISO-8601 audit log.
- Exit codes: 0 healthy/dry-run, 1 config/safety, 2 unhealthy.

## CLI

See the module's [SPECS.md §3](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/6-Website-Availability-%28HTTP-Health-Check)/SPECS.md).

## Wiki Navigation

- [Bash vs PowerShell](32-Website-Availability-Bash-vs-PowerShell)
- [Scenarios & Labs](33-Website-Availability-Scenarios-and-Labs)

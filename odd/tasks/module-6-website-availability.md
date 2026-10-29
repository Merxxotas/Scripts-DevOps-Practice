# Module 6 — Website Availability (HTTP Health Check)

Branch: feat/6-website-availability
Delivery strategy: ask-on-risk
Test runner: bash tests/test_health_check.sh / pwsh tests/test_health_check.ps1

## Specs

S1 — URL. `-u/--url` (Bash) / `-Url` (PowerShell) sets the target URL (default `https://example.com`). Must start with `http://` or `https://`; otherwise a configuration error (exit 1).

S2 — Timeout. `-t/--timeout` (Bash) / `-TimeoutSec` (PowerShell) sets the maximum request time in seconds (default 10). Must be a positive integer; otherwise a configuration error (exit 1).

S3 — Expected code. `-e/--expected-code` (Bash) / `-ExpectedCode` (PowerShell) sets the HTTP status code considered healthy (default 200). Must be in 100–599; otherwise a configuration error (exit 1).

S4 — SSL check. `--ssl-check` (Bash) / `-SslCheck` (PowerShell) enables SSL certificate expiry reporting (opt-in, default off). Only meaningful for HTTPS URLs.

S5 — Dry-run. `--dry-run` (Bash) / `-DryRun` (PowerShell) prints target/expected/timeout, makes no request, exits 0.

S6 — Audit log. `--audit-log` (Bash) / `-AuditLog` (PowerShell) appends an ISO-8601 timestamped line per run recording URL, status, response time, size and outcome. Best-effort.

S7 — Verbose. `-v/--verbose` (Bash) / `-Verbose` (PowerShell) prints per-step diagnostic detail (curlie-inspired colored output).

S8 — Help. `-h/--help` (Bash) / `-Help` (PowerShell) prints usage and exits 0.

S9 — Guardrails. URL scheme validation, timeout positive integer, expected code 100–599. Config violations exit 1.

S10 — Request. Perform HTTP GET with timeout; capture status code, response time (seconds), response size (bytes).

S11 — Health determination. Status code equals expected → healthy (exit 0). Mismatch or connection failure (status 000 / non-zero curl exit) → unhealthy (exit 2).

S12 — Output contract. Status code (colored), response time, response size, SSL expiry (if --ssl-check). Curlie-inspired friendly formatting.

S13 — Redirects. No redirect following in v1; report the received status code as-is.

S14 — SSL expiry. When --ssl-check and URL is HTTPS, report certificate notAfter date. Best-effort; missing openssl or a failed handshake prints "unavailable" without failing the run.

S15 — Parity. Bash and PowerShell implement the same flags, defaults, exit codes and guardrails.

S16 — Tests. Deterministic suite stubbing curl/Invoke-WebRequest under a temp dir; covers flags, exit codes, dry-run, guardrails, health/mismatch/connection-failure, audit log, SSL. No network.

## Tasks

- [x] T1: Create feature document + Engram mirror (this file). route: inline
- [x] T2: Write SPECS.md, README.md, CODESTYLE.md, ROADMAP.md. route: inline
- [x] T3: Harden health_check.sh (Bash). route: inline
- [x] T4: Harden health_check.ps1 (PowerShell). route: inline
- [x] T5: Write Bash test suite tests/test_health_check.sh. route: inline
- [x] T6: Write PowerShell test suite tests/test_health_check.ps1. route: inline
- [x] T7: Write docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1-3). route: inline
- [x] T8: Create root CI workflow .github/workflows/ci-website-availability.yml. route: inline
- [x] T9: Write wiki pages + sidebar. route: inline
- [x] T10: Register module in MODULES.md, README.md, CHANGELOG.md, AGENTS.md. route: inline
- [ ] T11: Close feature document + Engram mirror. route: inline

## Log

L1: User request (verbatim): "Module 6 (Website Availability / HTTP Health Check) — seed on disk only. Convert it to the shipped contract following Modules 4/7/9 as templates. Flags: -u/--url / -Url (default https://example.com), -t/--timeout / -TimeoutSec (default 10), -e/--expected-code / -ExpectedCode (default 200), --ssl-check / -SslCheck (default off), --dry-run / -DryRun, --audit-log / -AuditLog, -v/--verbose / -Verbose, -h/--help / -Help. Guardrails: URL must start with http:// or https://; timeout positive integer; expected code 100-599. Dry-run: print target/expected/timeout, no request, exit 0. Exit codes: 0 healthy (status matches), 1 config/safety, 2 unhealthy (mismatch or connection failure). Output: status code, response time, size, SSL expiry (if --ssl-check). Audit log: one ISO-8601 line per run. Open decisions resolved: unhealthy exit code = 2; SSL check opt-in; no redirects in v1; keep response size. Testing: stubbed HTTP client, representative status codes, no Playwright, no network. HTTP client: curl as engine with curlie-inspired colored output (Option A)."

L2: 2026-10-29 — Created feature branch feat/6-website-availability from main. Feature document created. Open decisions resolved and recorded.

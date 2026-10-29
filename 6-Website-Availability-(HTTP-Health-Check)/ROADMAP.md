# Website Availability (HTTP Health Check) — Roadmap

## Phase 1 — Foundation (shipped)

- [x] CLI parser (Bash + PowerShell) with help.
- [x] URL scheme validation.
- [x] Timeout and expected-code validation.
- [x] Dry-run mode.
- [x] HTTP request with timeout.
- [x] Health determination (match/mismatch/failure).
- [x] Response time and size reporting.
- [x] SSL expiry reporting (opt-in).
- [x] Audit log.
- [x] Exit codes 0/1/2.
- [x] Tests (Bash + PowerShell).
- [x] CI workflow.
- [x] Docs and wiki.

## Phase 2 — Enhancements (planned)

- [ ] Redirect following (`--follow-redirects`).
- [ ] Continuous monitoring / watch loop.
- [ ] `--json` / `--csv` output.
- [ ] Authentication / custom headers.
- [ ] POST and other HTTP methods.
- [ ] Multiple URLs per invocation.

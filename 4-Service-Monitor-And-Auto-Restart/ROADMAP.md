# Service Monitor and Auto-Restart — Roadmap

## Phase 1 — Foundation (shipped)

- [x] CLI parser (Bash + PowerShell) with help.
- [x] Service-name validation and existence check.
- [x] Running-service detection (exit 0).
- [x] Auto-restart with configurable retries and delay.
- [x] Dry-run mode.
- [x] Audit log.
- [x] Exit codes 0/1/2.
- [x] Tests (Bash + PowerShell).
- [x] CI workflow.
- [x] Docs and wiki.

## Phase 2 — Enhancements (planned)

- [ ] Continuous watch loop / daemon mode.
- [ ] Health-check probe (HTTP/TCP) before restart.
- [ ] Dependency-graph restart (restart dependents).
- [ ] `--json` / `--csv` output.
- [ ] Service enable/disable commands.
- [ ] `--no-restart` monitor-only mode.

## Phase 3 — Integrations (planned)

- [ ] Webhook/ntfy notification on restart.
- [ ] Metrics export (Prometheus textfile).
- [ ] Container orchestration (systemd unit template).
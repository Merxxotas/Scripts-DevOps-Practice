# Kubernetes Pod Monitor and Restart — Roadmap

## Phase 1 — Foundation (shipped)

- [x] CLI parser (Bash + PowerShell) with help.
- [x] Namespace / label / threshold validation.
- [x] kubectl availability check.
- [x] Pod discovery (name, phase, restart count).
- [x] Auto-delete when threshold exceeded.
- [x] Force mode (hard delete).
- [x] Dry-run mode.
- [x] Audit log.
- [x] Exit codes 0/1/2.
- [x] Tests (Bash + PowerShell).
- [x] CI workflow.
- [x] Docs and wiki.

## Phase 2 — Enhancements (planned)

- [ ] Continuous watch loop.
- [ ] Multi-namespace support.
- [ ] `--json` / `--csv` output.
- [ ] Deployment/ReplicaSet management.
- [ ] Resource limits / node awareness.

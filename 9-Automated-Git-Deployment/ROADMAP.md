# Automated Git Deployment — Roadmap

## Phase 1 — Foundation (shipped)

- [x] CLI parser (Bash + PowerShell) with help.
- [x] App/backup dir validation and guardrails.
- [x] Branch name validation.
- [x] Pre-deploy backup (tar.gz / zip).
- [x] Fetch and up-to-date detection.
- [x] Pull and deploy.
- [x] Post-deploy tasks (npm install, service restart) with skip flags.
- [x] Dry-run mode.
- [x] Audit log.
- [x] Exit codes 0/1/2.
- [x] Tests (Bash + PowerShell).
- [x] CI workflow.
- [x] Docs and wiki.

## Phase 2 — Enhancements (planned)

- [ ] Rollback on failure.
- [ ] Multi-environment config.
- [ ] Webhook notification.
- [ ] `--json` / `--csv` output.
- [ ] Container orchestration.
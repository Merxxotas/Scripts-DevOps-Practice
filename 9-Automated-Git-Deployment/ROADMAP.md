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

## Phase 2 — Enhancements

- [x] Rollback on failure (pull failure; `git reset --hard` to the pre-deploy revision; `--no-rollback` / `-NoRollback`).
- [ ] Multi-environment config.
- [ ] Webhook notification.
- [x] `--json` / `--csv` output (`result` gains the additive value `rolled-back`).
- [ ] Container orchestration.
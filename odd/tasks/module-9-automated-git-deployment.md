# Module 9 — Automated Git Deployment (CLOSED)

Branch: feat/9-automated-git-deployment
Delivery strategy: ask-on-risk
Test runner: bash tests/test_git_deploy.sh / pwsh tests/test_git_deploy.ps1

## Specs

S1 — App directory. `-a/--app-dir` (Bash) / `-AppDir` (PowerShell) sets the deployment target directory (default `/var/www/myapp` / `C:\inetpub\wwwroot\myapp`). Must exist and be a directory; a missing/non-directory or protected-root path is a configuration error (exit 1).

S2 — Repository URL. `-r/--repo-url` (Bash) / `-RepoUrl` (PowerShell) sets the remote URL (default seed values). Optional but validated non-empty.

S3 — Branch. `-b/--branch` (Bash) / `-Branch` (PowerShell) sets the branch to deploy (default `main`). Must match `^[a-zA-Z0-9._/-]+$`.

S4 — Backup directory. `--backup-dir` (Bash) / `-BackupDir` (PowerShell) sets where the pre-deploy backup is stored (default `/backup/deployments` / `C:\Backups\Deployments`). Must not be a protected root.

S5 — Skip backup. `--skip-backup` (Bash) / `-SkipBackup` (PowerShell) skips the pre-deploy backup.

S6 — Skip post-deploy. `--skip-post-deploy` (Bash) / `-SkipPostDeploy` (PowerShell) skips npm install and service restart.

S7 — Service. `--service` (Bash) / `-Service` (PowerShell) sets the service to restart (default `myapp` / IIS). Used only when post-deploy runs.

S8 — Dry-run. `--dry-run` (Bash) / `-DryRun` (PowerShell) previews fetch/backup/pull/post-deploy without mutating. Exit 0.

S9 — Audit log. `--audit-log` (Bash) / `-AuditLog` (PowerShell) appends an ISO-8601 line per run. Best-effort.

S10 — Verbose. `-v/--verbose` (Bash) / `-Verbose` (PowerShell) prints per-step detail.

S11 — Help. `-h/--help` (Bash) / `-Help` (PowerShell) prints usage and exits 0.

S12 — Guardrails. Refuse `APP_DIR`/`BACKUP_DIR` in protected system roots; require `APP_DIR` to exist and be a directory; validate branch name. Refuse a dirty working tree (uncommitted changes) unless `--force` (optional, v1: fail on dirty).

S13 — Flow. Backup (unless skipped) → git fetch → compare local/remote. If up-to-date: print message, exit 0. Else: git pull; on success run post-deploy (npm install if package.json; service restart) unless skipped; exit 0. On pull failure: exit 2.

S14 — Exit codes. 0 success (up-to-date or deployed), 1 config/safety violation, 2 partial failure.

S15 — Output contract. Colorized console output with a summary block.

S16 — Parity. Same flags, defaults, exit codes, guardrails.

S17 — Tests. Deterministic suite stubbing git/tar/npm/systemctl (Bash) and process tools (PS); covers up-to-date, deploy, backup, dry-run, guardrails, audit log, exit codes. No real repo touched.

## Tasks

- [x] T1: Create feature document + Engram mirror (this file). route: inline
- [x] T2: Write SPECS.md, README.md, CODESTYLE.md, ROADMAP.md. route: inline
- [x] T3: Harden git_deploy.sh. route: inline
- [x] T4: Harden git_deploy.ps1. route: inline
- [x] T5: Write Bash test suite tests/test_git_deploy.sh. route: inline (23 tests, 0 failures)
- [x] T6: Write PowerShell test suite tests/test_git_deploy.ps1. route: inline
- [x] T7: Write docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1-3). route: inline
- [x] T8: Create root CI workflow .github/workflows/ci-git-deployment.yml. route: inline
- [x] T9: Write wiki pages + sidebar. route: inline
- [x] T10: Register module in MODULES.md, README.md, CHANGELOG.md, AGENTS.md. route: inline
- [x] T11: Close feature document + Engram mirror. route: inline

## Log

L1: User request (verbatim): "Module 9 (Automated Git Deployment) — seed on disk only. Convert it to the shipped contract following Module 1/3/8 as templates: SPECS.md, README.md, CODESTYLE.md, ROADMAP.md, hardened implementation with CLI parser/guardrails/dry-run/exit codes, tests/, docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs), root CI workflow, wiki pages, MODULES.md/README/CHANGELOG registration."

L2: 2026-10-28 — Created feature branch feat/9-automated-git-deployment from main. Feature document created.
L3: 2026-10-28 — Implemented all tasks. Bash suite: 23 tests, 0 failures. Risk: item 3 (new module added; contracts/docs/wiki registered).

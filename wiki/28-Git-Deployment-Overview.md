# 28. Automated Git Deployment — Overview & Specs

Cross-platform automated deployment from a Git repository. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

## Key Features

- Safety guardrails on app/backup dirs and branch name; app dir must be a git work tree.
- Origin verification: an explicitly passed repository URL is checked against `origin`
  (normalized comparison) — mismatch aborts with exit 1 before any side effect.
- Verified pre-deploy backup (tar.gz + `gzip -t` / .NET ZipArchive entry-by-entry SHA-256,
  dotfiles included). Backup failure aborts the deploy: no fetch, no pull, exit 2.
- Automatic rollback on pull failure (`git reset --hard` to the pre-deploy revision;
  `--no-rollback` / `-NoRollback` to disable). Rollback never triggers on post-deploy
  failures; the service is NOT restarted by rollback.
- Up-to-date detection.
- Post-deploy tasks (npm install, service restart) with skip flags.
- Optional ISO-8601 audit log (includes backup verification and rollback entries).
- Exit codes: 0 success, 1 config/safety, 2 partial failure. JSON/CSV `result` gains
  the additive value `rolled-back`.

## CLI

See the module's [SPECS.md §3](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/9-Automated-Git-Deployment/SPECS.md).

## Wiki Navigation

- [Bash vs PowerShell](29-Git-Deployment-Bash-vs-PowerShell)
- [Scenarios & Labs](30-Git-Deployment-Scenarios-and-Labs)

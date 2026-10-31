# 28. Automated Git Deployment — Overview & Specs

Cross-platform automated deployment from a Git repository. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

## Key Features

- Safety guardrails on app/backup dirs and branch name.
- Dry-run simulation.
- Pre-deploy backup (tar.gz / zip).
- Up-to-date detection.
- Post-deploy tasks (npm install, service restart) with skip flags.
- Optional ISO-8601 audit log.
- Exit codes: 0 success, 1 config/safety, 2 partial failure.

## CLI

See the module's [SPECS.md §3](../9-Automated-Git-Deployment/SPECS.md).

## Wiki Navigation

- [Bash vs PowerShell](29-Git-Deployment-Bash-vs-PowerShell)
- [Scenarios & Labs](30-Git-Deployment-Scenarios-and-Labs)
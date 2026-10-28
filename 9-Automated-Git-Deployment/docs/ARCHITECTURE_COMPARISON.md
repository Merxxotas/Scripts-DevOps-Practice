# Architecture Comparison — Automated Git Deployment

## Bash vs PowerShell

| Aspect | Bash (`git_deploy.sh`) | PowerShell (`git_deploy.ps1`) |
| :--- | :--- | :--- |
| Backup | `tar -czf` (.tar.gz) | `Compress-Archive` (.zip) |
| Fetch/compare | `git rev-parse @` vs `@{u}` | `git rev-parse HEAD` vs `origin/<branch>` |
| Pull | `git pull origin <branch>` | `git pull origin <branch>` |
| Post-deploy | `npm install`, `systemctl restart` | `npm install`, `iisreset` |
| Guardrails | protected roots, existing dir, branch regex | same |
| Process tools | external commands (git, tar, npm, systemctl) | cmdlets / `&` |

## Shared contract

Both share flags, defaults, exit codes (0/1/2), dry-run, audit log and summary block. Only the
platform tooling differs.
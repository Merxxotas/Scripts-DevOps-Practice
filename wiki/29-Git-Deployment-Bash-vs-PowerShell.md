# 29. Automated Git Deployment — Bash vs PowerShell

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| Backup | `tar -czf` (.tar.gz) | `Compress-Archive` (.zip) |
| Fetch/compare | `git rev-parse @` vs `@{u}` | `git rev-parse HEAD` vs `origin/<branch>` |
| Pull | `git pull origin <branch>` | `git pull origin <branch>` |
| Post-deploy | `npm install`, `systemctl restart` | `npm install`, `iisreset` |
| Guardrails | protected roots, existing dir, branch regex | same |

Both share flags, defaults, exit codes (0/1/2), dry-run, audit log.
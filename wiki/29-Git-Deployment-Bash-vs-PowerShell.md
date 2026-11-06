# 29. Automated Git Deployment — Bash vs PowerShell

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| Backup | `tar -czf` (.tar.gz), verified with `gzip -t` | .NET `ZipArchive` (.zip, dotfiles-safe), verified entry-by-entry (file set + SHA-256 per entry) |
| Dotfiles in backup | included (`tar -C dir .`) | included (`Get-ChildItem -Force`; `Compress-Archive` cannot add hidden files on PS 7 Unix — not used) |
| Empty app dir | valid empty archive | valid empty archive |
| Fetch/compare | `git rev-parse @` vs `@{u}` | `git rev-parse HEAD` vs `origin/<branch>` |
| Pull | `git pull origin <branch>` | `git pull origin <branch>` |
| Rollback | `git reset --hard` to pre-deploy rev on pull failure (`--no-rollback`) | same (`-NoRollback`) |
| Repo pre-flight | non-repo → exit 1; explicit `-r` checked against `origin` (normalized) | same |
| Post-deploy | `npm install`, `systemctl restart` | `npm install`, `iisreset` |
| Guardrails | protected roots, existing dir, branch regex | same |
| Process tools | external commands (git, tar, npm, systemctl) | cmdlets / `&` |

Both share flags, defaults, exit codes (0/1/2), dry-run, audit log, verified backup gating the
deploy, automatic pull-failure rollback, and the summary block. Only the platform tooling differs.

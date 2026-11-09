# Automated Git Deployment - Technical Specification

## 1. System Overview

The **Automated Git Deployment Utility** deploys the latest version of an application from a
Git repository: it creates a **verified** pre-deployment backup (created AND checked before any
fetch; failure aborts the run with exit 2), fetches remote changes, pulls when behind, and rolls
back to the pre-deploy revision automatically if the pull fails (disable with `--no-rollback`).
Post-deployment tasks (dependency install, service restart) run only on a successful pull. It
runs on POSIX Bash (Linux/macOS) and PowerShell (Windows), with 100% feature parity in flags,
exit codes and guardrails. Dependencies: `git` (required), `tar`/`npm`/service manager (optional, best-effort).

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate app dir, branch name, backup dir                                   |
|  - Safety guardrail: refuse protected system roots; require existing app dir    |
|  - Repo pre-flight: app dir must be a git work tree (exit 1 otherwise); if      |
|    -r/--repo-url was passed explicitly it must match `origin` (normalized       |
|    comparison) - mismatch or missing origin: exit 1, no side effects            |
|  - Backup dir must not be inside the app dir (exit 1; prevents self-archiving)|
|  - Tracked worktree must be clean (git status --porcelain --untracked-files=no |
|    non-empty => exit 1, protects auto-rollback from destroying local edits)     |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                       2. Pre-deployment Backup (verified)                     |
|  - tar.gz (Bash, verified with gzip -t)                                       |
|  - zip via .NET ZipArchive (PS, verified entry-by-entry: same file set,       |
|    SHA-256 per entry vs source tree; Compress-Archive cannot store dotfiles   |
|    on PS 7 Unix and is not used)                                              |
|  - dotfiles included (GNU tar . / .NET enumeration)                           |
|  - FAILURE => no fetch, no pull, no post-deploy: exit 2, app untouched        |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Fetch & Compare                                 |
|  - git fetch origin <branch>                                                    |
|  - If local == remote: "already up to date", exit 0                            |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Deploy                                          |
|  - git pull origin <branch>                                                    |
|  - On pull failure: automatic rollback - git reset --hard to the pre-deploy    |
|    revision (unless --no-rollback); exit 2; JSON/CSV result "rolled-back"      |
|  - Rollback is never triggered by post-deploy failures                          |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Post-deployment (unless skipped)                |
|  - npm install if package.json present                                         |
|  - Restart service (--service)                                                 |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             6. Telemetry & Summary                             |
|  - Print colorized execution summary                                           |
|  - Write ISO-8601 audit log entry (if --audit-log)                             |
|  - Return standardized exit code                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles
1. **Safety First**: guardrails on app/backup dirs; the backup must be created AND verified before any mutation; dry-run never mutates; an explicit `-r/--repo-url` must match `origin`.
2. **Roll back to a known-good state**: if the pull fails, the pre-deploy revision is restored automatically (`git reset --hard`; disable with `--no-rollback`).
3. **Observable & Auditable**: every run is traceable through console output and an optional audit log (including backup verification and rollback entries).
4. **Best-effort post-deploy**: npm/service failures are recorded but do not abort the run and never trigger rollback.

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-a, --app-dir` | `-AppDir` | `/var/www/myapp` / `C:\inetpub\wwwroot\myapp` | Application directory |
| `-r, --repo-url` | `-RepoUrl` | real `origin` if unset | Repository URL. If passed, the run aborts (exit 1) when the configured `origin` differs (normalized comparison); unset prints the actual `origin` |
| `--no-rollback` | `-NoRollback` | off | Do not roll back to the pre-deploy revision if the pull fails |
| `-b, --branch` | `-Branch` | `main` | Branch to deploy |
| `--backup-dir` | `-BackupDir` | `/backup/deployments` / `C:\Backups\Deployments` | Backup directory |
| `--skip-backup` | `-SkipBackup` | off | Skip pre-deploy backup |
| `--skip-post-deploy` | `-SkipPostDeploy` | off | Skip npm install and service restart |
| `--service` | `-Service` | `myapp` / `IIS` | Service to restart |
| `--dry-run` | `-DryRun` | off | Preview only |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `--json` | `-Json` | off | Output result as JSON |
| `--csv` | `-Csv` | off | Output result as CSV |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (up-to-date or deployed) |
| 1 | Configuration or safety violation (invalid args, protected root, non-repo, origin mismatch, dirty tracked worktree, backup dir nested inside app dir) |
| 2 | Partial failure (backup failed/unverified, pull failed, post-deploy failed) |

Exit 2 after a backup failure means **no mutation happened**. Exit 2 after a pull failure
means the tree was rolled back to the pre-deploy revision (unless `--no-rollback`).

---

## 5. Safety Guardrails

- **App dir:** must exist and be a directory; refused if in a protected system root.
- **Repo pre-flight:** the app dir must be a git work tree (`git rev-parse --is-inside-work-tree`); otherwise exit 1 with a clear message. If `-r/--repo-url` was passed explicitly, the configured `origin` must match under a normalized comparison (lowercase host+path; credentials stripped; `git@host:path` ≡ `https://host/path`; trailing `/` and `.git` ignored). Mismatch — or no origin configured — exits 1 before any backup or fetch. Unset, the real `origin` is printed (credentials scrubbed) instead of a placeholder; with no `origin` configured the reported `repo_url` is empty (never a seed placeholder).
- **Dirty worktree:** tracked changes (`git status --porcelain --untracked-files=no` non-empty) abort with exit 1 before any backup or fetch — the automatic `git reset --hard` must never destroy uncommitted edits. Untracked files are ignored (the reset never touches them).
- **Backup verified:** the created archive must pass verification before any fetch/pull — `gzip -t` (Bash) or an entry-by-entry comparison (same file set, SHA-256 per entry vs source tree, `.NET System.IO.Compression`; PowerShell). Recursive enumeration errors abort the backup (fail closed). Verification failure aborts with exit 2; the app is untouched.
- **Backup dir:** refused if in a protected system root. It must not be the app dir or inside it (exit 1) — a self-referencing archive would corrupt both creation and verification.
- **Branch name:** must match `^[a-zA-Z0-9._/-]+$`.
- **Rollback:** on pull failure the pre-deploy revision is restored (`git reset --hard`) unless `--no-rollback`. Rollback failure is logged and audited (never swallowed); exit stays 2. JSON/CSV `result` gains the additive value `rolled-back`.
- **Dry-run:** no backup, fetch, pull, or post-deploy action is performed.

---

## 6. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
outcome (including `Backup verified: <file>` and `Rolled back to <rev> (<app dir>)`). Write
failures are best-effort and do not change the exit code.

---

## 7. Scope Exclusions (v1)

Rollback covers **pull failure only** (git working tree integrity). Post-deploy failures
(npm install, service restart) are recorded but neither abort nor roll back. No
multi-environment config, no webhook; `--json`/`--csv` output is available; no container
orchestration. One app per invocation. Audit write is best-effort.

# Automated Git Deployment - Technical Specification

## 1. System Overview

The **Automated Git Deployment Utility** deploys the latest version of an application from a
Git repository: it creates a pre-deployment backup, fetches remote changes, pulls when behind,
and runs post-deployment tasks (dependency install, service restart). It runs on POSIX Bash
(Linux/macOS) and PowerShell (Windows), with 100% feature parity in flags, exit codes and
guardrails. Dependencies: `git` (required), `tar`/`npm`/service manager (optional, best-effort).

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate app dir, branch name, backup dir                                   |
|  - Safety guardrail: refuse protected system roots; require existing app dir    |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Pre-deployment Backup                           |
|  - tar.gz (Bash) / zip (PS) of app dir (unless --skip-backup)                  |
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
|  - On failure: exit 2                                                          |
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
1. **Safety First**: guardrails on app/backup dirs; dry-run never mutates.
2. **Observable & Auditable**: every run is traceable through console output and an optional audit log.
3. **Best-effort post-deploy**: npm/service failures are recorded but do not abort the run (exit 2 only on pull failure).

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-a, --app-dir` | `-AppDir` | `/var/www/myapp` / `C:\inetpub\wwwroot\myapp` | Application directory |
| `-r, --repo-url` | `-RepoUrl` | seed default | Repository URL |
| `-b, --branch` | `-Branch` | `main` | Branch to deploy |
| `--backup-dir` | `-BackupDir` | `/backup/deployments` / `C:\Backups\Deployments` | Backup directory |
| `--skip-backup` | `-SkipBackup` | off | Skip pre-deploy backup |
| `--skip-post-deploy` | `-SkipPostDeploy` | off | Skip npm install and service restart |
| `--service` | `-Service` | `myapp` / `IIS` | Service to restart |
| `--dry-run` | `-DryRun` | off | Preview only |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (up-to-date or deployed) |
| 1 | Configuration or safety violation |
| 2 | Partial failure (backup/pull/post-deploy failed) |

---

## 5. Safety Guardrails

- **App dir:** must exist and be a directory; refused if in a protected system root.
- **Backup dir:** refused if in a protected system root.
- **Branch name:** must match `^[a-zA-Z0-9._/-]+$`.
- **Dry-run:** no backup, fetch, pull, or post-deploy action is performed.

---

## 6. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
outcome. Write failures are best-effort and do not change the exit code.

---

## 7. Scope Exclusions (v1)

No rollback, no multi-environment config, no webhook, no `--json`/`--csv` output, no
container orchestration. One app per invocation. Audit write is best-effort.

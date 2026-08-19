# Log Cleanup - Scenarios & Interactive Labs 🧪

---

## 🚀 Production Scenarios

1. **High-Traffic Nginx Access Log Purging**: Daily cron job purging uncompressed access logs older than 14 days to prevent root partition disk exhaustion.
2. **Windows Server IIS Application Pool Retention**: Scheduled task pruning recursive nested request logs in `C:\inetpub\logs\LogFiles` older than 30 days.
3. **Database Dump Rotation**: Purging database dumps older than 7 days exceeding 50 MB in size.
4. **CI/CD Runner Workspace Pruning**: Cleaning build workspaces on self-hosted runners to prevent `No space left on device` errors.

---

## 🧪 Interactive Hands-on Labs

| Lab Guide | Focus Area | Key Concepts |
| :--- | :--- | :--- |
| **[Lab 1: Basic Retention & Dry-Run Preview](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/docs/labs/LAB1_BASIC_RETENTION_AND_DRYRUN.md)** | Simulation & Pruning | Setting up mock directories, running simulation mode (`-n`), and executing live deletions. |
| **[Lab 2: Recursive Traversal & Size Filtering](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/docs/labs/LAB2_RECURSIVE_SIZE_FILTERING.md)** | Advanced Filtering | Multi-tiered microservice folders, flat vs. recursive scans, and minimum size filters (`-m`). |
| **[Lab 3: Production Scheduling & Audit Logging](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/docs/labs/LAB3_PRODUCTION_SCHEDULING_AND_AUDIT.md)** | Production Automation | Linux Cron, Windows Task Scheduler, ISO-8601 audit logging, and exit code validation. |


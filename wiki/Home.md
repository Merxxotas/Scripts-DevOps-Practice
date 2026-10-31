# Welcome to the DevOps Automation & Daemons Wiki

Welcome to the central technical documentation and knowledge base for the **Scripts-DevOps-Practice** repository.

This wiki provides comprehensive architecture guides, deep-dive comparisons, step-by-step interactive labs, and operational references for all enterprise automation utilities and daemons in this monorepo.

---

## Table of Contents

### 1. Repository & Core Architecture
- **[01-Monorepo-Architecture](01-Monorepo-Architecture)**: Overview of the multi-language approach (Bash, PowerShell, Python, Go) and module boundaries.

### 2. Module 1: Disk Usage Monitor
- **[13-Disk-Monitor-Overview](13-Disk-Monitor-Overview)**: Sensor, exit-code contract, transports (none/mail/http), config file and doctor.
- **[14-Disk-Monitor-Bash-vs-PowerShell](14-Disk-Monitor-Bash-vs-PowerShell)**: One contract in two runtimes, transport dimension, parity proof.
- **[15-Disk-Monitor-Scenarios-and-Labs](15-Disk-Monitor-Scenarios-and-Labs)**: Scheduled checks, config file, doctor, VPS relay, hands-on labs.

### 3. Module 2: Log Cleanup Utility
- **[05-Log-Cleanup-Overview](05-Log-Cleanup-Overview)**: CLI specs, safety guardrails, space calculation.
- **[06-Log-Cleanup-Bash-vs-PowerShell](06-Log-Cleanup-Bash-vs-PowerShell)**: POSIX byte streams vs .NET pipelines, platform strengths, exit codes.
- **[07-Log-Cleanup-Scenarios-and-Labs](07-Log-Cleanup-Scenarios-and-Labs)**: Nginx, IIS, DB dumps, hands-on labs.

### 4. Module 3: Automated Database Backup
- **[16-Database-Backup-Overview](16-Database-Backup-Overview)**: Cross-platform dump, compression, retention, credential safety, dry-run.
- **[17-Database-Backup-Bash-vs-PowerShell](17-Database-Backup-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof, platform differences.
- **[18-Database-Backup-Scenarios-and-Labs](18-Database-Backup-Scenarios-and-Labs)**: Successful backups, failures, retention, hands-on labs.

### 5. Module 4: Service Monitor and Auto-Restart
- **[22-Service-Monitor-Overview](22-Service-Monitor-Overview)**: Service existence checks, auto-restart, retry policy.
- **[23-Service-Monitor-Bash-vs-PowerShell](23-Service-Monitor-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof.
- **[24-Service-Monitor-Scenarios-and-Labs](24-Service-Monitor-Scenarios-and-Labs)**: Running, stopped, restart failures, hands-on labs.

### 6. Module 5: CPU & Memory Usage Monitor
- **[10-CPU-Monitor-Overview](10-CPU-Monitor-Overview)**: Three implementations, shared JSON contract, defects found while shipping.
- **[11-CPU-Monitor-Bash-vs-PowerShell](11-CPU-Monitor-Bash-vs-PowerShell)**: Dependency-free native scripts, where implementations disagree.
- **[12-CPU-Monitor-Scenarios-and-Labs](12-CPU-Monitor-Scenarios-and-Labs)**: Scheduled checks, runaway-process triage, hands-on labs.

### 7. Module 6: Website Availability (HTTP Health Check)
- **[31-Website-Availability-Overview](31-Website-Availability-Overview)**: HTTP probes, SSL, redirects, status codes.
- **[32-Website-Availability-Bash-vs-PowerShell](32-Website-Availability-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof.
- **[33-Website-Availability-Scenarios-and-Labs](33-Website-Availability-Scenarios-and-Labs)**: Healthy, unhealthy, SSL, hands-on labs.

### 8. Module 7: Find and Kill High-CPU Processes
- **[25-Kill-High-CPU-Overview](25-Kill-High-CPU-Overview)**: Candidate discovery, guardrails, interactive/auto-kill, audit log.
- **[26-Kill-High-CPU-Bash-vs-PowerShell](26-Kill-High-CPU-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof.
- **[27-Kill-High-CPU-Scenarios-and-Labs](27-Kill-High-CPU-Scenarios-and-Labs)**: Guardrails, dry-run, kill failure, hands-on labs.

### 9. Module 8: Log Rotation and Compression
- **[19-Log-Rotation-Overview](19-Log-Rotation-Overview)**: Size-based rotation, compression, retention, dry-run, guardrails.
- **[20-Log-Rotation-Bash-vs-PowerShell](20-Log-Rotation-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof.
- **[21-Log-Rotation-Scenarios-and-Labs](21-Log-Rotation-Scenarios-and-Labs)**: Rotation, retention, exit codes, hands-on labs.

### 10. Module 9: Automated Git Deployment
- **[28-Git-Deployment-Overview](28-Git-Deployment-Overview)**: Backup, fetch, pull, post-deploy, service restart.
- **[29-Git-Deployment-Bash-vs-PowerShell](29-Git-Deployment-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof.
- **[30-Git-Deployment-Scenarios-and-Labs](30-Git-Deployment-Scenarios-and-Labs)**: Up-to-date, deployed, failures, hands-on labs.

### 11. Module 10: Kubernetes Pod Monitor and Restart
- **[34-Kubernetes-Pod-Monitor-Overview](34-Kubernetes-Pod-Monitor-Overview)**: Pod status, restart, kubectl stubbing.
- **[35-Kubernetes-Pod-Monitor-Bash-vs-PowerShell](35-Kubernetes-Pod-Monitor-Bash-vs-PowerShell)**: One contract in two runtimes, parity proof.
- **[36-Kubernetes-Pod-Monitor-Scenarios-and-Labs](36-Kubernetes-Pod-Monitor-Scenarios-and-Labs)**: Healthy, unhealthy, restart, hands-on labs.

### 12. Module 11: EventOps Daemon
- **[02-EventOps-Overview](02-EventOps-Overview)**: Architecture, component breakdown, daemon loops, rules.json schema.
- **[03-EventOps-Python-vs-Go](03-EventOps-Python-vs-Go)**: Memory footprints, Goroutines vs threads, performance metrics.
- **[04-EventOps-Scenarios-and-Labs](04-EventOps-Scenarios-and-Labs)**: Webhook deployments, file watcher debouncing, hands-on labs.

### 13. Quality & Engineering Standards
- **[08-CI-CD-Pipelines](08-CI-CD-Pipelines)**: Path-based GitHub Actions monorepo isolation and multi-OS validation.
- **[09-Code-Style-and-Standards](09-Code-Style-and-Standards)**: B2 English conventions, commenting strategy, branching workflow.

---

## Quick Links

- Repository Source: [GitHub Repository](https://github.com/Merxxotas/Scripts-DevOps-Practice)
- License: [MIT License](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE)

---

**DevOps Automation & Daemons Repository** | Maintained by **Brayan Marin Guirales** | Licensed under [MIT](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE)

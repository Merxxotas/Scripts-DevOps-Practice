---
layout: default
title: Home
---

# DevOps Automation Scripts & Daemons

A multi-language DevOps automation monorepo: **11 self-contained modules** (Bash, PowerShell, Python, Go) with specs, tests, CI and documentation.

[![CI](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-disk-monitor.yml/badge.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE)

## Modules

| # | Module | Tech | Docs |
|---|--------|------|------|
| 1 | Disk Usage Monitoring with Email Alert | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/13-Disk-Monitor-Overview) |
| 2 | Log Cleanup (files older than X days) | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/05-Log-Cleanup-Overview) |
| 3 | Automated Database Backup with Timestamp | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/16-Database-Backup-Overview) |
| 4 | Service Monitor and Auto-Restart | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/22-Service-Monitor-Overview) |
| 5 | CPU and Memory Usage Monitor | Bash / PowerShell / Python / Docker | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/10-CPU-Monitor-Overview) |
| 6 | Website Availability (HTTP Health Check) | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/31-Website-Availability-Overview) |
| 7 | Find and Kill High-CPU Processes | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/25-Kill-High-CPU-Overview) |
| 8 | Log Rotation and Compression | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/19-Log-Rotation-Overview) |
| 9 | Automated Git Deployment | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/28-Git-Deployment-Overview) |
| 10 | Kubernetes Pod Monitor and Restart | Bash / PowerShell | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/34-Kubernetes-Pod-Monitor-Overview) |
| 11 | Scheduling and Automation (EventOps) | Python / Go | [Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/02-EventOps-Overview) |

## Quick Start

```bash
git clone https://github.com/Merxxotas/Scripts-DevOps-Practice.git
cd Scripts-DevOps-Practice/1-Disk-Usage-Monitoring-with-Email-Alert
chmod +x disk_monitor.sh
./disk_monitor.sh --help
```

## Links

- [Full Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki)
- [Source Code](https://github.com/Merxxotas/Scripts-DevOps-Practice)
- [CI Pipelines](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions)
- [License (MIT)](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE)

---

Maintained by Brayan Marin Guirales.

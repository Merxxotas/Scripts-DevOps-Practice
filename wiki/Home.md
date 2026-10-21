# Welcome to the DevOps Automation & Daemons Wiki 🛠️

Welcome to the central technical documentation and knowledge base for the **Scripts-DevOps-Practice** repository.

This wiki provides comprehensive architecture guides, deep-dive comparisons, step-by-step interactive labs, and operational references for all enterprise automation utilities and daemons in this monorepo.

---

## 🗺️ Knowledge Base Architecture

```
+------------------------------------------------------------------------------------------------------------------------------------+
|                                                    DevOps Monorepo Architecture                                                    |
+------------------------------+   ------------------------------+   ------------------------------+   ------------------------------+
                                                                  |
                                                                  v
+------------------------------+   ------------------------------+   ------------------------------+   ------------------------------+
| Module 11: EventOps          |    Module 2: Log Cleanup        |    Module 1: Disk Monitor       |    CI/CD & Standards            |
| - Event-driven automation    |    - Enterprise log retention   |    - Threshold disk monitoring  |    - GitHub Actions             |
| - Python & Go ports          |    - Bash & PowerShell parity   |    - Bash & PowerShell parity   |    - Multi-OS matrices          |
| - Webhook + file watcher     |    - Multi-layer safety guards  |    - Credential-free alert path |    - Static linters             |
+------------------------------+   ------------------------------+   ------------------------------+   ------------------------------+
```

---

## 🗂️ Table of Contents

### 1. Repository & Core Architecture
- **[[01-Monorepo-Architecture|01. Monorepo Architecture]]**: Overview of the multi-language approach (Bash, PowerShell, Python, Go) and module boundaries.

### 2. Module 11: EventOps Daemon
- **[[02-EventOps-Overview|02. EventOps Overview & Specs]]**: Architecture, component breakdown, daemon loops, and `rules.json` schema.
- **[[03-EventOps-Python-vs-Go|03. Python vs. Go Architecture Comparison]]**: Memory footprints, Goroutines vs. threads, performance metrics, and binary compilation.
- **[[04-EventOps-Scenarios-and-Labs|04. EventOps Scenarios & Interactive Labs]]**: Webhook deployments, file watcher debouncing, and 3 hands-on step-by-step labs.

### 3. Module 2: Log Cleanup Utility
- **[[05-Log-Cleanup-Overview|05. Log Cleanup Utility Overview]]**: Dual-native Bash & PowerShell CLI specifications, safety guardrails, and space calculation.
- **[[06-Log-Cleanup-Bash-vs-PowerShell|06. Bash vs. PowerShell Architecture Comparison]]**: POSIX byte streams vs. .NET object pipelines, platform strengths, and exit codes.
- **[[07-Log-Cleanup-Scenarios-and-Labs|07. Log Cleanup Scenarios & Interactive Labs]]**: Nginx, IIS, DB dumps, and 3 hands-on practical labs.

### 4. Module 5: CPU & Memory Usage Monitor
- **[[10-CPU-Monitor-Overview|10. CPU & Memory Usage Monitor — Overview & Specs]]**: Three implementations of one monitor, the shared JSON contract, and the defects found while shipping it.
- **[[11-CPU-Monitor-Bash-vs-PowerShell|11. Bash vs PowerShell vs Python]]**: The dependency-free argument for the native scripts, and where the three implementations still disagree.
- **[[12-CPU-Monitor-Scenarios-and-Labs|12. CPU Monitor Scenarios & Interactive Labs]]**: Scheduled checks, runaway-process triage, and 3 hands-on labs that run the real commands.

### 5. Module 1: Disk Usage Monitor
- **[[13-Disk-Monitor-Overview|13. Disk Usage Monitor — Overview & Specs]]**: The sensor half of the disk loop, the shared exit-code contract, and the credential-free hand-off to the host's mail agent.
- **[[14-Disk-Monitor-Bash-vs-PowerShell|14. Disk Monitor — Bash vs PowerShell]]**: One contract in two runtimes, what the parity guarantees, and where the two legitimately differ.
- **[[15-Disk-Monitor-Scenarios-and-Labs|15. Disk Monitor Scenarios & Interactive Labs]]**: Scheduled checks, the dry run before go-live, the VPS mail relay, and 3 hands-on labs.

### 6. Quality & Engineering Standards
- **[[08-CI-CD-Pipelines|08. CI/CD Pipelines & Testing Philosophy]]**: Path-based GitHub Actions monorepo isolation and multi-OS validation.
- **[[09-Code-Style-and-Standards|09. Code Style & Engineering Standards]]**: B2 English conventions, commenting strategy, and branching workflow.

---

## 🔗 Quick Links
- Repository Source: [GitHub Repository](https://github.com/Merxxotas/Scripts-DevOps-Practice)
- License: [MIT License](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE)


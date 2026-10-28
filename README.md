# DevOps Automation Scripts & Daemons Repository 🛠️

Welcome to the central repository for DevOps automation scripts, event daemons, and system utilities.

This repository is a **multi-language monorepo**. While it includes foundational Bash and PowerShell scripts, it is language-agnostic and uses modern runtimes such as **Python** and **Go** whenever complex event handling, high-performance concurrency, cross-platform portability, or compiled standalone binaries are required.

---

## 🗂️ Project & Module Directory

| Folder / Module | Primary Technologies | Purpose & Architecture |
| :--- | :--- | :--- |
| `1-Disk-Usage-Monitoring-with-Email-Alert` | Bash / PowerShell | disk alerts over mail or HTTP |
| `2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)` | Bash / PowerShell | Automated log retention & directory purging |
| `3-Automated-Database-Backup-with-Timestamp` | Bash / PowerShell | Timestamped database dump & rotation utilities |
| `4-Service-Monitor-And-Auto-Restart` | Bash / PowerShell | System service uptime monitoring & auto-restart |
| `5-CPU-and-Memory-Usage-Monitor` | Bash / PowerShell / Python / Docker | **CPU Monitor:** resource monitoring & process kill/restart, in three implementations sharing one data contract |
| `6-Website-Availability-(HTTP-Health-Check)` | Bash / PowerShell | Web endpoint HTTP status & response time checker |
| `7-Find-and-Kill-High-CPU-Processes` | Bash / PowerShell | Process management & runaway CPU process cleanup |
| `8-Log-Rotation-and-Compression` | Bash / PowerShell | Log archiving, gzip compression, & retention |
| `9-Automated-Git-Deployment` | Bash / PowerShell | Automated deployment pull & service restart scripts |
| `10-Kubernetes-Pod-Monitor-and-Restart` | Bash / PowerShell | K8s pod health monitoring & kubectl management |
| `11-Scheduling-And-Automation` | **Python & Go** | **EventOps:** Cross-platform event-driven automation daemon (Webhooks + File Watcher) |

> **11 modules · 8 shipped (1, 2, 3, 4, 5, 7, 8, 11) · 3 seeds on the working disk.** The live status of
> every module is in [`MODULES.md`](MODULES.md).

---

## ⚡ Technology Stack & Language Flexibility

We select the best technology for each automation challenge:

- 🐚 **Bash & PowerShell**: Used for OS-native shell administration, system task execution, and direct command-line scripting.
- 🐍 **Python**: Used for cross-platform automation engines, rich library ecosystems (`watchdog`), and flexible daemon logic.
- 🐹 **Go**: Used for high-performance compiled binaries (<5MB RAM footprint, ~2ms startup), zero-dependency production deployments, and lightweight Goroutines concurrency.

---

## 🔄 CI/CD Philosophy (GitHub Actions)

Because this is a monorepo, **CI/CD pipelines are strictly segregated by project folder**:
- There is no single "monolithic" build pipeline. Instead, each project has its own dedicated GitHub Actions workflow file in `.github/workflows/`.
- Workflows use Git `paths` filters to trigger *only* when files inside that specific project folder are modified (e.g., modifying files in `11-Scheduling-And-Automation/` triggers `ci-eventops.yml`, leaving other modules untouched).
- Each workflow lives at the **repository root** in `.github/workflows/`. A `.github` folder nested inside a module folder is never executed by GitHub.

---

## 📚 Documentation & Governance

| Document | Purpose |
| :--- | :--- |
| **[`AGENTS.md`](AGENTS.md)** | **Start here.** What this repository is, the working methodology (ODD), the module contract, branching and commit conventions, the CI model, code standards, and known gotchas. |
| **[`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)** | The expanded ODD protocol: the seven phases, the feature document format, task sizing, the test-first policy and the delegation triggers. |
| **[`MODULES.md`](MODULES.md)** | Status of all 11 modules — 5 shipped, 6 seeds — the seed-to-shipped checklist, and the recommended build order. |
| **[`CONTRIBUTING.md`](CONTRIBUTING.md)** | How to contribute: workflow, branch naming, commit format, testing rules, PR checklist. |
| **[`SECURITY.md`](SECURITY.md)** | Reporting a vulnerability privately, response targets, and what does and does not count as a vulnerability here. |
| **[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)** | Community standards. |
| **[`SUPPORT.md`](SUPPORT.md)** | Where to ask questions, and what to include in a bug report. |
| **[`CHANGELOG.md`](CHANGELOG.md)** | Notable changes, newest first. |
| **[`wiki/`](wiki/)** | The knowledge base — architecture, deep-dive comparisons, production scenarios and interactive labs. Also published as the [GitHub Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki). |

> **Working methodology: Organic Driven Development (ODD)** — the gentle-ai implementation. See
> [`AGENTS.md` §2](AGENTS.md) for the index and [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md) for the
> full protocol. The module artifacts (`SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md`,
> `docs/`) remain mandatory; ODD is the process that produces them.

---

## 📜 License
This entire repository is open source and available under the [MIT License](LICENSE).

# Modules

> Inventory, status and build order for every numbered module in this monorepo.
> **Last reviewed: 2026-10-21.**

Each module is a self-contained DevOps automation utility with its own spec, implementation, tests, CI
pipeline and documentation. See [`AGENTS.md`](AGENTS.md) for the module contract and methodology.

---

## Status Legend

| Status | Meaning |
| :--- | :--- |
| ✅ **Shipped** | Committed, CI-covered, documented, tested. |
| 🔵 **Seed (local)** | A raw script pair exists on disk only. No specs, tests, docs or CI. |
| ⬜ **Planned** | Folder exists but holds no implementation. |

---

## Inventory

| # | Module | Tech | Status | CI | Docs |
| :-- | :--- | :--- | :--- | :-- | :-- |
| 1 | Disk Usage Monitoring with Email Alert | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 2 | Log Cleanup (files older than X days) | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 3 | Automated Database Backup with Timestamp | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 4 | Service Monitor and Auto-Restart | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 5 | CPU and Memory Usage Monitor | Bash / PowerShell / Python / Docker | ✅ **Shipped** | ✅ | Full |
| 6 | Website Availability (HTTP Health Check) | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 7 | Find and Kill High-CPU Processes | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 8 | Log Rotation and Compression | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 9 | Automated Git Deployment | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 10 | Kubernetes Pod Monitor and Restart | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 11 | Scheduling and Automation (EventOps) | Python / Go | ✅ **Shipped** | ✅ | Full |

---

## Module Detail

### ✅ 1 — Disk Usage Monitoring with Email Alert *(Shipped)*

A sensor, not an actuator: it measures one mounted filesystem's usage and, on threshold breach, hands
an alert to one of three transports — `none`, `mail` or `http`. `mail` invokes the host's mail agent;
`http` is one request with a body to a URL, so ntfy, Telegram, Discord, Slack and self-hosted
receivers share one code path. Each setting resolves flag → `DISK_MONITOR_*` env → config file →
default. `--doctor` reports the resolved config and what's missing, without measuring or sending.
Crossing the threshold is **not** a failure — the alert is the product, so the run exits `0`. The
transport, config file and doctor are the pattern the remaining seven seed modules inherit.

- `disk_monitor.sh` (Bash) · `disk_monitor.ps1` (PowerShell 7) · `PSScriptAnalyzerSettings.psd1`
- `README.md` · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- `.diskmonitor.conf` — optional; 13 keys in a minimal `key = value` format, git-ignored because
  a `header` may hold a token
- `tests/` — 277 assertions pass on the Bash suite locally; the PowerShell suite mirrors the same
  scenarios and runs in CI
- `docs/` — `ARCHITECTURE_COMPARISON.md`, `SCENARIOS.md`, `labs/LAB1-3`
- CI: `.github/workflows/ci-disk-monitor.yml` — six jobs: `lint-bash` (ShellCheck) and
  `lint-powershell` (PSScriptAnalyzer), `test-bash` on `ubuntu-24.04` and `macos-14`, and
  `test-powershell` on `windows-2022` and `ubuntu-24.04`
- Wiki: [13](wiki/13-Disk-Monitor-Overview.md) · [14](wiki/14-Disk-Monitor-Bash-vs-PowerShell.md) · [15](wiki/15-Disk-Monitor-Scenarios-and-Labs.md)

**Defects found and fixed while shipping it.** The seed was 75 lines that had never run: it had
never been in git, so nothing about it had ever been verified.

| Defect | Fix |
| :--- | :--- |
| The Bash script could not execute at all — it carried CRLF line endings, so the shebang read `/bin/bash^M` | The file is LF, and `.gitattributes` normalises it |
| The Bash side read the capacity from column 5 of `df -h`, the macOS column-layout trap that broke module 5 | It reads the fixed fifth field of the POSIX `df -P` layout |
| The capacity was read from the second-to-last field of `df -P`, which is only right while the mount point is a single word | Both sides read field five, and a regression test drives a stub whose mount point contains a space |
| The PowerShell side never sent — the `Send-MailMessage` call was commented out and it only printed "prepared" | The alert is composed and handed to the resolved mail agent on both sides |
| `Get-WmiObject` was removed in PowerShell 7, but the file declared `#Requires -Version 7.0`, so the fallback was dead on the version it targeted | The Windows path uses `Get-CimInstance Win32_LogicalDisk`; the POSIX path is the primary one |
| PowerShell variables are case-insensitive, so `$mailCommand` shadowed `$MailCommand` and `-MailCommand` was silently discarded | The local is renamed, and the same shadowing is removed from the measurement command |
| The PowerShell harness reported assertions it never ran — a binding error was printed and skipped | The assertions accept empty values, and an erroring assertion now fails the run |
| The Bash harness created the mail-capture file itself, so "the mail agent was never invoked" could not be asserted by the file's absence | The assertion checks the capture's contents |
| The PowerShell suite failed PSScriptAnalyzer — two unapproved verbs, two plural nouns, global counters | Approved verbs, singular nouns, and script-scoped state |

**Known gaps**, recorded rather than hidden: one partition per invocation; no `--json`/`--csv` output and
no direct SMTP transport are deliberate v1 non-goals; the audit write is best-effort (may fail on a
full disk); the CI matrix is x86-only (no ARM64 runner yet).

### ✅ 2 — Log Cleanup *(Shipped)*

Automated log retention and directory purging with safety guardrails, dry-run simulation, space
accounting and audit logging. Full Bash + PowerShell parity.

- `cleanup_logs.sh` · `cleanup_logs.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-cleanup-logs.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [05](wiki/05-Log-Cleanup-Overview.md) · [06](wiki/06-Log-Cleanup-Bash-vs-PowerShell.md) · [07](wiki/07-Log-Cleanup-Scenarios-and-Labs.md)

### ✅ 3 — Automated Database Backup *(Shipped)*

Timestamped database dumps with compression and retention for MySQL and PostgreSQL. Full
Bash + PowerShell parity.

- `db_backup.sh` · `db_backup.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-database-backup.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [16](wiki/16-Database-Backup-Overview.md) · [17](wiki/17-Database-Backup-Bash-vs-PowerShell.md) · [18](wiki/18-Database-Backup-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no incremental/differential backups, no cloud streaming,
no MSSQL, no encryption of the backup file, no `--json`/`--csv` output. One database per
invocation. Audit write is best-effort.

### ✅ 4 — Service Monitor and Auto-Restart *(Shipped)*

Service uptime monitoring with automatic restart for a named service. Full Bash + PowerShell parity.

- `service_monitor.sh` · `service_monitor.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-service-monitor.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [22](wiki/22-Service-Monitor-Overview.md) · [23](wiki/23-Service-Monitor-Bash-vs-PowerShell.md) · [24](wiki/24-Service-Monitor-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no continuous watch loop, no HTTP/TCP health probe, no dependency-graph restart, no `--json`/`--csv` output, no service enable/disable. One service per invocation. Audit write is best-effort. Restart success is verified via the platform service manager; tests stub `systemctl` on Bash and exercise parsing/guardrails/dry-run on PowerShell.

### ✅ 6 — Website Availability (HTTP Health Check) *(Shipped)*

Single-URL HTTP health check reporting status, response time, size and (opt-in) SSL
expiry. Full Bash + PowerShell parity.

- `health_check.sh` · `health_check.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-website-availability.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [31](wiki/31-Website-Availability-Overview.md) · [32](wiki/32-Website-Availability-Bash-vs-PowerShell.md) · [33](wiki/33-Website-Availability-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no redirect following, no continuous watch loop, no
`--json`/`--csv` output, no authentication or custom headers, no other HTTP methods. One URL per
invocation. Audit write is best-effort. SSL expiry requires `openssl` (best-effort).

---

### ✅ 7 — Find and Kill High-CPU Processes *(Shipped)*

Detection and termination of runaway CPU processes. Full Bash + PowerShell parity.

- `kill_high_cpu.sh` · `kill_high_cpu.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-kill-high-cpu.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [25](wiki/25-Kill-High-CPU-Overview.md) · [26](wiki/26-Kill-High-CPU-Bash-vs-PowerShell.md) · [27](wiki/27-Kill-High-CPU-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no continuous watch loop, no `--top` limit, no `--json`/`--csv` output, no process-tree killing, no cgroups/container awareness. One threshold per invocation. Interactive mode is the default; auto-kill requires an explicit flag. CPU metric differs between platforms (instantaneous vs cumulative). Audit write is best-effort.

### ✅ 8 — Log Rotation and Compression *(Shipped)*

Size-based log rotation with compression and retention for a single log file. Full
Bash + PowerShell parity.

- `log_rotate.sh` · `log_rotate.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-log-rotation.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [19](wiki/19-Log-Rotation-Overview.md) · [20](wiki/20-Log-Rotation-Bash-vs-PowerShell.md) · [21](wiki/21-Log-Rotation-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no time-based or date-stamped rotation, no
`copytruncate`/`create` modes, no post-rotation hook, no compression of already-rotated backups,
no `--json`/`--csv` output. One log file per invocation. Audit write is best-effort.

### ✅ 9 — Automated Git Deployment *(Shipped)*

Git-based application deployment with backup, fetch, pull and post-deploy tasks. Full Bash + PowerShell parity.

- `git_deploy.sh` · `git_deploy.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-git-deployment.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [28](wiki/28-Git-Deployment-Overview.md) · [29](wiki/29-Git-Deployment-Bash-vs-PowerShell.md) · [30](wiki/30-Git-Deployment-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no rollback, no multi-environment config, no webhook, no `--json`/`--csv` output, no container orchestration. One app per invocation. Post-deploy (npm/service) failures are recorded but do not abort. Audit write is best-effort.

### ✅ 11 — Scheduling and Automation / EventOps *(Shipped)*

Cross-platform event-driven automation daemon. Replaces polling with reacting: a webhook server and
a debounced filesystem watcher feed a rule engine that dispatches actions asynchronously.

- `EventOps/` (Python: rule engine, webhook + file-watcher triggers, async executor, logger)
- `EventOps-Go/` (Go port: `pkg/ruleengine`, `pkg/executor`, `pkg/triggers`, `pkg/logger`)
- CI: `.github/workflows/ci-eventops.yml` — 3 OS × Python 3.10/3.11/3.12, plus `go vet` and `go test`
- Wiki: [02](wiki/02-EventOps-Overview.md) · [03](wiki/03-EventOps-Python-vs-Go.md) · [04](wiki/04-EventOps-Scenarios-and-Labs.md)

### ✅ 5 — CPU and Memory Usage Monitor *(Shipped)*

A cross-platform system resource monitor with three implementations of the same tool and one shared
data contract. The four-stage capstone of the repository.

| Stage | Contents | Size |
| :-- | :--- | :-- |
| 1 — Native | `system_monitor.sh`, `system_monitor.ps1` | Bash + PowerShell, v1.3.0 |
| 2 — Python | `src/system_monitor/` (6 modules), `tests/` (45 tests) | 1,047 LOC src · 718 LOC tests |
| 3 — Container | Multi-stage `Dockerfile`, `docker-compose.yml` (5 profiles) | non-root UID 1000, read-only rootfs |
| 4 — CI/CD | `.github/workflows/ci-cpu-monitor.yml` | at the repository root |

- `README.md` · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md` · `AGENTS.md`
- `tests/` — Stage 1 suites: 20 Bash tests, 18 PowerShell tests
- `docs/` — `ARCHITECTURE_COMPARISON.md`, `SCENARIOS.md`, `labs/LAB1-3`
- CI: `.github/workflows/ci-cpu-monitor.yml` — 6 jobs across Linux, macOS and Windows
- Wiki: [10](wiki/10-CPU-Monitor-Overview.md) · [11](wiki/11-CPU-Monitor-Bash-vs-PowerShell.md) · [12](wiki/12-CPU-Monitor-Scenarios-and-Labs.md)

**Defects found and fixed while shipping it.** The module had never been in git and its workflows
had never run, so nothing about it had ever been verified.

| Defect | Fix |
| :--- | :--- |
| Two failing tests from contract drift | The under-mocked snapshot was fixed in the test; the positional call was fixed in the implementation |
| `--cpu-threshold` and `--mem-threshold` had no effect at all | Threaded into the display exporter, with a regression test |
| The output followed the host locale, so a comma-decimal locale failed every run | `LC_ALL=C` in Bash, `InvariantCulture` in PowerShell |
| `head` closed the pipe early, and `pipefail` turned that into a failure on any host running more than 100 processes | The limit now lives inside the consumer |
| The container image could never have built | The builder stage was missing `README.md` and `src/`, and the install was editable |
| The PowerShell script failed outright on Linux | The kill log directory no longer depends on `$env:TEMP` |
| The JSON and CSV contracts disagreed between the implementations | All three now emit the same key names |
| 286 lint errors in the Python package | `ruff check` and `ruff format --check` are clean |

**Known gaps**, recorded rather than hidden: disk I/O fields differ between native implementations; the
Bash script has no options for thresholds or process count; memory % is wrong on macOS (file cache
counted as used); exit code 2 is reserved but unused.

### ✅ 10 — Kubernetes Pod Monitor and Restart *(Shipped)*

Kubernetes pod monitoring with auto-restart (delete) for pods whose restart count exceeds a
threshold. Full Bash + PowerShell parity.

- `k8s_monitor.sh` · `k8s_monitor.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-kubernetes-pod-monitor.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [34](wiki/34-Kubernetes-Pod-Monitor-Overview.md) · [35](wiki/35-Kubernetes-Pod-Monitor-Bash-vs-PowerShell.md) · [36](wiki/36-Kubernetes-Pod-Monitor-Scenarios-and-Labs.md)

**Known gaps**, recorded rather than hidden: no continuous watch loop, no multi-namespace, no
deployment/replicaset management, no `--json`/`--csv` output. One namespace + selector per
invocation. Graceful delete by default; hard delete only with `--force`. Audit write is best-effort.
Requires `kubectl` and cluster access.

---

### 🔵 Seed modules — (none)

All eleven modules are now shipped. No seed modules remain.

---

## Build Order

**Recommended sequence**, balancing "finish what exists" against "keep the numbering meaningful".
Module 1 shipped on **2026-10-21** and set the template; the sequence now starts at module 3.

| Priority | Module | Rationale |
| :-- | :--- | :-- |
| — | **5 — CPU and Memory Usage Monitor** | **Shipped.** Completed. |
| — | **1 — Disk Usage Monitoring** | **Shipped.** Completed, and the template for the remaining seeds. |
| — | **3 — Automated Database Backup** | **Shipped.** Complements module 2 — backup creation feeding retention pruning. |
| 2 | **8 — Log Rotation and Compression** | Shares the log-lifecycle domain with modules 2 and 3. |
| — | **4 — Service Monitor and Auto-Restart** | **Shipped.** Completed. |
| — | **7 — Find and Kill High-CPU Processes** | **Shipped.** Completed. |
| — | **9 — Automated Git Deployment** | **Shipped.** Completed. |
| — | **6 — Website Availability** | **Shipped.** Completed. |
| — | **10 — Kubernetes Pod Monitor** | **Shipped.** Completed. |

---

## Adding a New Module

1. Pick the next free number — the folder name must be `<n>-<Descriptive-Name>`.
2. Create the folder and the full contract from §*Seed → Shipped checklist*.
3. Add a row to the inventory above **and** to the module table in [`README.md`](README.md).
4. Add a path-filtered workflow at the repository root.
5. Add the wiki page and the sidebar entry in `wiki/_Sidebar.md`.
6. Update the module count in `README.md` and `wiki/01-Monorepo-Architecture.md`.

---


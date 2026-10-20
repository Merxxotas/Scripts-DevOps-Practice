# Modules

> Inventory, status and build order for every numbered module in this monorepo.
> **Last reviewed: 2026-10-20.**

Each module is a self-contained DevOps automation utility with its own specification, implementation,
tests, CI pipeline and documentation. See [`AGENTS.md`](AGENTS.md) for the module contract and the
working methodology.

---

## Status Legend

| Status | Meaning |
| :--- | :--- |
| ✅ **Shipped** | Committed, CI-covered, documented, tested. |
| 🟡 **Capstone (local)** | Complete body of work on disk, **not committed**, missing root CI wiring. |
| 🔵 **Seed (local)** | A raw script pair exists on disk only. No specs, tests, docs or CI. |
| ⬜ **Planned** | Folder exists but holds no implementation. |

---

## Inventory

| # | Module | Tech | Status | CI | Docs |
| :-- | :--- | :--- | :--- | :-- | :-- |
| 1 | Disk Usage Monitoring with Email Alert | Bash / PowerShell | 🔵 Seed | — | — |
| 2 | Log Cleanup (files older than X days) | Bash / PowerShell | ✅ **Shipped** | ✅ | Full |
| 3 | Automated Database Backup with Timestamp | Bash / PowerShell | 🔵 Seed | — | — |
| 4 | Service Monitor and Auto-Restart | Bash / PowerShell | 🔵 Seed | — | — |
| 5 | CPU and Memory Usage Monitor | Bash / PowerShell / Python / Docker | 🟡 Capstone | ⚠️ Nested | Full |
| 6 | Website Availability (HTTP Health Check) | Bash / PowerShell | 🔵 Seed | — | — |
| 7 | Find and Kill High-CPU Processes | Bash / PowerShell | 🔵 Seed | — | — |
| 8 | Log Rotation and Compression | Bash / PowerShell | 🔵 Seed | — | — |
| 9 | Automated Git Deployment | Bash / PowerShell | 🔵 Seed | — | — |
| 10 | Kubernetes Pod Monitor and Restart | Bash / PowerShell | 🔵 Seed | — | — |
| 11 | Scheduling and Automation (EventOps) | Python / Go | ✅ **Shipped** | ✅ | Full |

---

## Module Detail

### ✅ 2 — Log Cleanup *(Shipped)*

Automated log retention and directory purging with safety guardrails, dry-run simulation, space
accounting and audit logging. Full Bash + PowerShell parity.

- `cleanup_logs.sh` · `cleanup_logs.ps1` · `tests/` · `docs/` (+ 3 labs) · `SPECS.md` · `ROADMAP.md` · `CODESTYLE.md`
- CI: `.github/workflows/ci-cleanup-logs.yml` — ShellCheck, Bash on ubuntu + macOS, PowerShell on Windows + Ubuntu
- Wiki: [05](wiki/05-Log-Cleanup-Overview.md) · [06](wiki/06-Log-Cleanup-Bash-vs-PowerShell.md) · [07](wiki/07-Log-Cleanup-Scenarios-and-Labs.md)

### ✅ 11 — Scheduling and Automation / EventOps *(Shipped)*

Cross-platform event-driven automation daemon. Replaces polling with reacting: a webhook server and
a debounced filesystem watcher feed a rule engine that dispatches actions asynchronously.

- `EventOps/` (Python: rule engine, webhook + file-watcher triggers, async executor, logger)
- `EventOps-Go/` (Go port: `pkg/ruleengine`, `pkg/executor`, `pkg/triggers`, `pkg/logger`)
- CI: `.github/workflows/ci-eventops.yml` — 3 OS × Python 3.10/3.11/3.12, plus `go vet` and `go test`
- Wiki: [02](wiki/02-EventOps-Overview.md) · [03](wiki/03-EventOps-Python-vs-Go.md) · [04](wiki/04-EventOps-Scenarios-and-Labs.md)

### 🟡 5 — CPU and Memory Usage Monitor *(Capstone, local only)*

The most substantial body of work in the repository, and the closest to completion. A four-stage
evolution: native scripts → unified Python package → containerization → CI/CD.

| Stage | Contents | Size |
| :-- | :--- | :-- |
| 1 — Native | `system_monitor.sh`, `system_monitor.ps1`, 8 topic READMEs | Bash + PowerShell, v1.3.0 |
| 2 — Python | `src/system_monitor/` (6 modules), `tests/` (42 tests) | 1,047 LOC src · 718 LOC tests |
| 3 — Container | Multi-stage `Dockerfile`, `docker-compose.yml` (5 profiles), `.dockerignore` | non-root UID 1000, read-only rootfs |
| 4 — CI/CD | 3 GitHub Actions workflows | ⚠️ nested — would never execute |

**Before this module can ship:**

1. Fix the two failing tests (§ *Known Issues* below).
2. Move the three workflows to the **repository root** `.github/workflows/` with `paths:` filters
   scoped to `5-CPU-and-Memory-Usage-Monitor/**`. GitHub does not execute nested workflow folders.
3. Reconcile `5-CPU-and-Memory-Usage-Monitor/.gitignore` — it currently ignores its own `AGENTS.md`.
4. Rebuild the broken `.venv`; never commit it.
5. Add `SPECS.md`, `ROADMAP.md` and `CODESTYLE.md` to match the module contract.
6. Strip generated artifacts (`htmlcov/`, `.coverage`, `coverage.xml`, `.pytest_cache/`, `.ruff_cache/`,
   `__pycache__/`, `uv.lock`).

**Known issues (verified 2026-10-20):** `2 failed, 40 passed`.

| Test | Symptom | Nature |
| :--- | :--- | :--- |
| `tests/test_cli.py::TestCLIMonitor::test_display_mode` | `TypeError: '>' not supported between instances of 'Mock' and 'int'` | The CLI compares `snapshot.cpu_percent` against a threshold, but the test only stubs `snapshot.to_dict()`, so the attribute stays an auto-generated `Mock`. |
| `tests/test_monitor.py::TestSystemMonitorSnapshot::test_get_snapshot` | `Expected: get_process_data(top_n=10)` / `Actual: get_process_data(10)` | Positional vs keyword call — the test and the implementation disagree on the call convention. |

Neither is a production defect; both are test-to-implementation contract drift.

### 🔵 Seed modules — 1, 3, 4, 6, 7, 8, 9, 10

Each holds a single Bash + PowerShell pair of roughly 40–70 lines, written in one sitting on
**2026-03-09**. They are functional sketches, not production utilities: no CLI parser, no safety
guardrails, no dry-run, no audit log, no exit-code contract, no tests, no documentation, no CI.

| # | Module | Files | Purpose |
| :-- | :--- | :--- | :--- |
| 1 | Disk Usage Monitoring with Email Alert | `disk_monitor.sh`, `disk_monitor.ps1` | Threshold-based disk capacity monitoring with mail notification. |
| 3 | Automated Database Backup with Timestamp | `db_backup.sh`, `db_backup.ps1` | Timestamped database dumps with rotation. |
| 4 | Service Monitor and Auto-Restart | `service_monitor.sh`, `service_monitor.ps1` | Service uptime monitoring and automatic restart. |
| 6 | Website Availability (HTTP Health Check) | `health_check.sh`, `health_check.ps1` | Endpoint HTTP status and response-time checking. |
| 7 | Find and Kill High-CPU Processes | `kill_high_cpu.sh`, `kill_high_cpu.ps1` | Runaway CPU process identification and cleanup. |
| 8 | Log Rotation and Compression | `log_rotate.sh`, `log_rotate.ps1` | Log archiving, gzip compression and retention. |
| 9 | Automated Git Deployment | `git_deploy.sh`, `git_deploy.ps1` | Deployment pull and service restart. |
| 10 | Kubernetes Pod Monitor and Restart | `k8s_monitor.sh`, `k8s_monitor.ps1` | K8s pod health monitoring and `kubectl` management. |

**Seed → Shipped checklist** (the same contract modules 2 and 11 satisfy):

- [ ] `SPECS.md` — system overview, architecture, flag/parameter reference, data shapes
- [ ] `ROADMAP.md` — phased milestones
- [ ] `CODESTYLE.md` — module conventions
- [ ] `README.md` — usage, flags, scheduling, troubleshooting
- [ ] Hardened implementation — real CLI parsing, safety guardrails, dry-run, exit codes
- [ ] `tests/` — deterministic suite covering every documented behaviour
- [ ] `docs/ARCHITECTURE_COMPARISON.md`, `docs/SCENARIOS.md`, `docs/labs/LAB1-3.md`
- [ ] Root `.github/workflows/ci-<module>.yml` with `paths:` filters and a multi-OS matrix
- [ ] Wiki page and sidebar entry

---

## Build Order

**Recommended sequence**, balancing "finish what exists" against "keep the numbering meaningful":

| Priority | Module | Rationale |
| :-- | :--- | :-- |
| 1 | **5 — CPU and Memory Usage Monitor** | Largest existing asset, already ~90% built. Converting it to shipped recovers ~6,200 LOC of finished work and closes the two red tests. |
| 2 | **1 — Disk Usage Monitoring** | First module in the series and the direct sibling of module 2 (same Bash/PowerShell CLI shape). Sets the template for the remaining seeds. |
| 3 | **3 — Automated Database Backup** | Complements module 2 — backup creation feeding retention pruning. Natural narrative pairing. |
| 4 | **8 — Log Rotation and Compression** | Shares the log-lifecycle domain with modules 2 and 3. |
| 5 | **4 — Service Monitor and Auto-Restart** | Introduces process/service supervision; pairs with 7. |
| 6 | **7 — Find and Kill High-CPU Processes** | Resource-control counterpart to 4 and 5. |
| 7 | **9 — Automated Git Deployment** | Already referenced by the EventOps specification as a webhook action target. |
| 8 | **6 — Website Availability** | Self-contained HTTP monitoring. |
| 9 | **10 — Kubernetes Pod Monitor** | Highest operational complexity; benefits from the hardened patterns established above. |

---

## Adding a New Module

1. Pick the next free number — the folder name must be `<n>-<Descriptive-Name>`.
2. Create the folder and the full contract from §*Seed → Shipped checklist*.
3. Add a row to the inventory above **and** to the module table in [`README.md`](README.md).
4. Add a path-filtered workflow at the repository root.
5. Add the wiki page and the sidebar entry in `wiki/_Sidebar.md`.
6. Update the module count in `README.md` and `wiki/01-Monorepo-Architecture.md`.

---

*Related: [`AGENTS.md`](AGENTS.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`CHANGELOG.md`](CHANGELOG.md)*

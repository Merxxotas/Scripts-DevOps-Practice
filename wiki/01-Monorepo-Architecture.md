# Monorepo Architecture & Multi-Language Philosophy 🏗️

The **Scripts-DevOps-Practice** repository is designed as an enterprise DevOps monorepo. It organizes diverse automation tasks, system utilities, and background daemons under a unified codebase while maintaining strict module isolation.

---

## ⚡ Multi-Language Strategy

Rather than forcing a single programming language across all operations, the repository adopts a **fit-for-purpose** polyglot model:

| Technology | Role & Use Case | Key Advantages |
| :--- | :--- | :--- |
| 🐚 **POSIX Bash** | OS-native Linux & macOS shell administration | Zero dependencies, instant execution, standard coreutils compatibility. |
| 🔷 **PowerShell** | Windows administration & cross-platform .NET automation | Strongly-typed object pipeline, native Windows API/WMI access, PowerShell Core portability. |
| 🐍 **Python** | Cross-platform orchestration engines & rich ecosystem daemons | Rapid prototyping, extensive standard library, filesystem abstraction (`watchdog`). |
| 🐹 **Go** | High-performance compiled standalone binaries & micro-daemons | Zero-dependency static binaries, <5MB RAM footprint, ~2ms startup, native Goroutines concurrency. |

---

## 📂 Repository Directory Layout

```
Scripts-DevOps-Practice/
├── .github/workflows/                             # Segregated CI/CD workflows per module
│   ├── ci-cleanup-logs.yml                        # Pipeline for Module 2
│   ├── ci-cpu-monitor.yml                         # Pipeline for Module 5
│   ├── ci-disk-monitor.yml                        # Pipeline for Module 1
│   └── ci-eventops.yml                            # Pipeline for Module 11
├── 1-Disk-Usage-Monitoring-with-Email-Alert/      # Disk Usage Monitor (sensor)
│   ├── disk_monitor.sh                            # POSIX Bash script
│   ├── disk_monitor.ps1                           # PowerShell script
│   ├── tests/                                     # Automated test suites
│   └── docs/                                      # Technical specs, architecture & labs
├── 2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/  # Enterprise Log Cleanup
├── 5-CPU-and-Memory-Usage-Monitor/              # CPU & Memory Monitor (capstone)
│   ├── Stage1-Native-Scripts/                   # Bash & PowerShell native scripts
│   ├── Stage2-Python-Unified/                   # Python orchestration package
│   ├── Stage3-Containerization/                 # Container image and compose profiles
│   ├── Stage4-CI-CD-Pipeline/                   # Pipeline definition
│   ├── tests/                                   # Automated test suites
│   └── docs/                                    # Technical specs, architecture & labs
├── ...                                            # Modules 3 to 10
└── 11-Scheduling-And-Automation/                  # EventOps Automation Daemon
    ├── EventOps/                                  # Python daemon implementation
    ├── EventOps-Go/                               # Go daemon implementation
    └── docs/                                      # Production scenarios & interactive labs
```

---

## 📦 Shipped Module Inventory

**Six modules are shipped** — committed, CI-covered, tested and documented:
modules **1**, **2**, **3**, **5**, **8** and **11**. The remaining five are seeds on the
working disk: a raw script pair each, with no contract yet.

| Folder / Module | Primary Technologies | Purpose & Architecture |
| :--- | :--- | :--- |
| `1-Disk-Usage-Monitoring-with-Email-Alert` | Bash / PowerShell | **Disk Monitor:** threshold monitoring, three transports |
| `2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)` | Bash / PowerShell | Automated log retention & directory purging |
| `3-Automated-Database-Backup-with-Timestamp` | Bash / PowerShell | Timestamped database dump & rotation |
| `5-CPU-and-Memory-Usage-Monitor` | Bash / PowerShell / Python / Docker | **CPU Monitor:** resource monitoring & process kill/restart, in three implementations sharing one data contract |
| `11-Scheduling-And-Automation` | **Python & Go** | **EventOps:** cross-platform event-driven automation daemon (Webhooks + File Watcher) |

Each shipped module owns its own pipeline, so changing one module never
triggers another's. The live status of every module — shipped, seed or
planned — is in [`MODULES.md`](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/MODULES.md).

---

## 🎯 Modular Design Invariants

1. **Self-Contained Modules**: Each numbered project directory contains its own code, tests, technical specifications (`SPECS.md`), roadmap (`ROADMAP.md`), code style guide (`CODESTYLE.md`), and user documentation (`README.md`).
2. **Segregated CI/CD**: Modifying a specific project folder triggers only that project's dedicated workflow via GitHub Actions path filtering, preventing unnecessary build runs across unaffected modules.
3. **Parity Across Platforms**: Where scripts are delivered for multiple platforms (e.g. Bash & PowerShell, Python & Go), they adhere to the same command-line flags, configuration schemas, and safety guardrails.


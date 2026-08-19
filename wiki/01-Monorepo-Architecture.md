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
│   └── ci-eventops.yml                            # Pipeline for Module 11
├── 1-Disk-Usage-Monitoring-with-Email-Alert/      # Bash / PowerShell disk monitors
├── 2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/  # Enterprise Log Cleanup
│   ├── cleanup_logs.sh                            # POSIX Bash script
│   ├── cleanup_logs.ps1                           # PowerShell script
│   ├── tests/                                     # Automated test suites
│   └── docs/                                      # Technical specs, architecture & labs
├── ...                                            # Modules 3 to 10
└── 11-Scheduling-And-Automation/                  # EventOps Automation Daemon
    ├── EventOps/                                  # Python daemon implementation
    ├── EventOps-Go/                               # Go daemon implementation
    └── docs/                                      # Production scenarios & interactive labs
```

---

## 🎯 Modular Design Invariants

1. **Self-Contained Modules**: Each numbered project directory contains its own code, tests, technical specifications (`SPECS.md`), roadmap (`ROADMAP.md`), code style guide (`CODESTYLE.md`), and user documentation (`README.md`).
2. **Segregated CI/CD**: Modifying a specific project folder triggers only that project's dedicated workflow via GitHub Actions path filtering, preventing unnecessary build runs across unaffected modules.
3. **Parity Across Platforms**: Where scripts are delivered for multiple platforms (e.g. Bash & PowerShell, Python & Go), they adhere to the same command-line flags, configuration schemas, and safety guardrails.


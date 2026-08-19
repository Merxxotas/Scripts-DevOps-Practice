# Log Cleanup - Bash vs. PowerShell Architecture Comparison 📊

---

## ⚡ Technical Comparison Matrix

| Dimension / Metric | POSIX Bash (`cleanup_logs.sh`) | PowerShell (`cleanup_logs.ps1`) |
| :--- | :--- | :--- |
| **Primary Platform** | Linux, macOS, Unix servers | Windows Server, Windows 10/11, PowerShell Core on Linux |
| **Data Processing Model** | Null-delimited text streams via POSIX pipes (`find -print0`) | Strongly-typed .NET `[System.IO.FileInfo]` object pipeline |
| **Memory Footprint** | ~1.5 MB RAM | ~35 MB RAM |
| **Execution Startup** | **~2 ms** | ~300 ms (CLR & JIT boot) |
| **Timestamp Evaluation** | Epoch seconds arithmetic (`stat` / `date`) | .NET `[DateTime]` comparison (`LastWriteTime -le CutoffDate`) |
| **Error Handling** | `set -euo pipefail` + command trapping | Structured `try { ... } catch { ... }` exception blocks |
| **Dependencies** | **Zero** (Native POSIX coreutils) | **Zero** (Native PowerShell runtime) |

---

## 🚦 Standardized Exit Codes

Both implementations terminate with deterministic process exit codes for seamless monitoring:

| Exit Code | Status | Condition |
| :---: | :--- | :--- |
| `0` | **Success** | Cleanup finished cleanly with 0 errors (including dry-run). |
| `1` | **Safety / Config Violation** | Invalid arguments, non-existent directory, or target is a protected system directory. |
| `2` | **Partial Failure** | One or more eligible files could not be deleted due to OS file locks or permission issues. |


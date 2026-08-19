# Log Cleanup Utility - Technical Overview 🧹

The **Log Cleanup Utility** is an enterprise-grade log retention and storage reclamation solution available in **POSIX Bash** (`cleanup_logs.sh`) and **PowerShell** (`cleanup_logs.ps1`) with 100% feature parity.

---

## 🛡️ Multi-Layer Safety Guardrails

To prevent accidental data loss or catastrophic operating system corruption, both scripts enforce a strict system root directory blacklist:
- **Linux / macOS Protected Roots**: `/`, `/bin`, `/sbin`, `/usr`, `/etc`, `/dev`, `/proc`, `/sys`, `/boot`, `/root`, `/var`, `/private`, `/Library`, `/System`, `/Applications`, `/Volumes`.
- **Windows Protected Roots**: `C:\`, `C:\Windows`, `C:\Windows\System32`, `C:\Program Files`, `C:\Program Files (x86)`, `C:\Users`, `C:\ProgramData`.

---

## 📋 Command-Line Parameter Parity

| Bash Flag | PowerShell Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-d <path>` | `-LogDirectory <string>` | String | *Required* | Target directory path to clean. |
| `-t <days>` | `-Days <int>` | Integer | `30` | Retention threshold in days (older than X days). |
| `-p <pattern>` | `-Pattern <string>` | String | `"*.log"` | Filename matching glob pattern. |
| `-m <mb>` | `-MinSizeMB <double>` | Number | `0` | Minimum file size threshold in MB. |
| `-r` | `-Recursive` | Switch | `false` | Enable deep recursive subdirectory traversal. |
| `-n` | `-DryRun` | Switch | `false` | Simulation mode: preview actions without deleting. |
| `-l <file>` | `-LogFile <string>` | String | `none` | Append persistent ISO-8601 audit logs. |
| `-v` | `-Verbose` | Switch | `false` | Enable verbose per-file diagnostic output. |
| `-h` | `Get-Help` | Switch | `none` | Display help and usage documentation. |

---

## 📊 Dynamic Storage Normalization

The utility aggregates space calculations and outputs human-readable units:
- $< 1024 \text{ B} \rightarrow \text{B}$
- $\ge 1024 \text{ B} \rightarrow \text{KB}$
- $\ge 1024^2 \text{ B} \rightarrow \text{MB}$
- $\ge 1024^3 \text{ B} \rightarrow \text{GB}$


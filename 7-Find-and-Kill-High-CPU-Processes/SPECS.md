# Find and Kill High-CPU Processes - Technical Specification

## 1. System Overview

The **Find and Kill High-CPU Processes Utility** is a cross-platform maintenance solution that
lists processes whose CPU usage exceeds a threshold and, on confirmation (or automatically),
terminates them. It runs on POSIX Bash (Linux/macOS) and PowerShell (Windows), with 100%
feature parity in flags, exit codes and guardrails. No third-party dependencies beyond the
shell and the platform process tools (`ps`/`kill` on Bash; `Get-Process`/`Stop-Process` on
PowerShell).

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate threshold, signal options                                           |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Process Discovery                               |
|  - List processes; filter those with CPU > threshold                            |
|  - Apply guardrails (no PID 0/1, self, parent, kernel threads)                  |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Dry-Run Gate                                    |
|  - If --dry-run: print candidates, exit 0                                      |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Action                                          |
|  - Interactive: prompt per candidate (y/n)                                      |
|  - Auto-kill: terminate all candidates                                          |
|  - Signal: SIGTERM by default, SIGKILL with --force                             |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Telemetry & Summary                             |
|  - Print colorized execution summary                                           |
|  - Write ISO-8601 audit log entry (if --audit-log)                             |
|  - Return standardized exit code                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles
1. **Zero External Dependencies**: only core OS utilities.
2. **Safety First**: never target PID 0/1, self, parent, or kernel threads; dry-run never signals.
3. **Observable & Auditable**: every run is traceable through console output and an optional audit log.

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-t, --threshold` | `-CpuThreshold` | `50.0` | CPU % above which a process is a candidate |
| `--auto-kill` | `-AutoKill` | off | Kill all candidates without prompting |
| `--force` | `-Force` | off | Use SIGKILL / Stop-Process -Force |
| `--dry-run` | `-DryRun` | off | Preview candidates, no signaling |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `--json` | `-Json` | off | Output result as JSON |
| `--csv` | `-Csv` | off | Output result as CSV |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (no candidates, killed, or dry-run) |
| 1 | Configuration or safety violation |
| 2 | Partial failure (a kill failed) |

---

## 5. Safety Guardrails

- **PID guardrails:** never target PID 0, 1, self (`$$`), or the parent (`$PPID`); never target kernel threads (comm in `[brackets]`).
- **Threshold:** must be a non-negative number.
- **Dry-run:** no signal is sent.
- **Interactive default:** prompts per candidate unless `--auto-kill`.

---

## 6. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
outcome and the count killed. Write failures are best-effort and do not change the exit code.

---

## 7. Scope Exclusions (v1)

No continuous monitoring/watch loop, no CPU history, no cgroups/container awareness, no
process-tree killing. One threshold per invocation. Audit write is best-effort.
JSON/CSV output available via `--json`/`--csv`.

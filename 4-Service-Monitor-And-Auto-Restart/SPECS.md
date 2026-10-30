# Service Monitor and Auto-Restart - Technical Specification

## 1. System Overview

The **Service Monitor and Auto-Restart Utility** is a cross-platform maintenance solution that
checks whether a named service is running and, when it is down, attempts to restart it up to a
configurable number of times with a configurable delay between attempts. It runs on POSIX Bash
(Linux/macOS, via `systemctl`) and PowerShell (Windows, via `Get-Service`/`Start-Service`), with
100% feature parity in flags, exit codes and guardrails. No third-party dependencies beyond the
shell and the platform service manager.

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate service name, max retries, retry delay                              |
|  - Safety guardrail: refuse invalid service names                               |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Service Lookup                                  |
|  - Resolve the service; if not installed/not found: exit 1                      |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Status Check                                    |
|  - If running/active: print success, exit 0                                    |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Dry-Run Gate                                    |
|  - If --dry-run: print planned restart attempts, exit 0                        |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Auto-Restart                                     |
|  - Attempt restart up to max-retries, waiting retry-delay between attempts      |
|  - On success: notify (syslog / Event Log), exit 0                             |
|  - On exhaustion: exit 2                                                       |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             6. Telemetry & Summary                             |
|  - Print colorized execution summary                                           |
|  - Write ISO-8601 audit log entry (if --audit-log)                             |
|  - Return standardized exit code                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles
1. **Zero External Dependencies**: only core OS utilities (`systemctl` on Bash; standard .NET / PowerShell runtime on Windows).
2. **Safety First**: destructive operations (restart) are guarded by service-name validation and existence checks.
3. **Dry-Run**: preview every planned action without touching the service.
4. **Observable & Auditable**: every run is traceable through console output and an optional audit log.

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-s, --service` | `-ServiceName` | `nginx` / `w3svc` | Target service name |
| `-r, --max-retries` | `-MaxRetries` | `3` | Restart attempts when down |
| `--retry-delay` | `-RetryDelaySeconds` | `5` | Seconds between attempts |
| `--dry-run` | `-DryRun` | off | Preview only |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `--json` | `-Json` | off | Output result as JSON |
| `--csv` | `-Csv` | off | Output result as CSV |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (running, restarted, or dry-run) |
| 1 | Configuration or safety violation |
| 2 | Partial failure (restart failed after retries) |

---

## 5. Safety Guardrails

- **Service name validation:** the name must match `^[a-zA-Z0-9_.@-]+$` (POSIX) / `^[a-zA-Z0-9_.-]+$` (Windows); any other character is a configuration error (exit 1).
- **Existence:** the service must be installed/registered; a missing service exits 1.
- **Max retries:** must be a positive integer.
- **Retry delay:** must be a non-negative integer.
- **Dry-run:** no restart is performed.

---

## 6. Notifications

- Bash: a syslog line via `logger` ("Service <name> was restarted on <date>").
- PowerShell: a Windows Event Log entry (source `ServiceMonitor`, event id 1001).

Notification failures are best-effort and do not change the exit code.

---

## 7. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
outcome and the service. Write failures are best-effort and do not change the exit code.

---

## 8. Scope Exclusions (v1)

No continuous daemon/watch loop, no health-check HTTP probe, no dependency-graph restart, no
service enable/disable, no container orchestration. One service per invocation. Audit write
is best-effort. JSON/CSV output available via `--json`/`--csv`.

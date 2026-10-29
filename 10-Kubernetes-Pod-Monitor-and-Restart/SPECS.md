# Kubernetes Pod Monitor and Restart - Technical Specification

## 1. System Overview

The **Kubernetes Pod Monitor** lists pods matching a namespace and label selector and, when
a pod's restart count exceeds a threshold, deletes it so the owning controller recreates it.
It runs on POSIX Bash (Linux/macOS) and PowerShell (Windows), with 100% feature parity in
flags, exit codes and guardrails. Depends on the `kubectl` CLI and cluster access.

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate namespace, label selector, threshold                               |
|  - Verify kubectl is available                                                 |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Dry-Run Gate                                    |
|  - If --dry-run: list pods + which would be deleted, exit 0                    |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Discovery                                       |
|  - kubectl get pods -n <ns> -l <selector> -o json                              |
|  - Parse name, phase, restart count (sum across containers)                    |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Action                                          |
|  - For each pod with restarts > threshold: delete (graceful or --force)        |
|  - Record success/failure per pod                                              |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Telemetry & Summary                             |
|  - Print per-pod result + summary block                                        |
|  - Write ISO-8601 audit log entry (if --audit-log)                             |
|  - Return standardized exit code                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles

1. **Safety First**: validate all inputs before any cluster call; dry-run never deletes;
   graceful delete by default, hard delete only with `--force`.
2. **Observable & Auditable**: every run is traceable through console output and an optional
   audit log.
3. **Parity**: identical flags, defaults, exit codes and guardrails on both platforms.

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-n, --namespace` | `-Namespace` | `default` | Kubernetes namespace |
| `-l, --label` | `-LabelSelector` | `app=web` | Label selector |
| `-r, --restart-threshold` | `-RestartThreshold` | `3` | Restart count above which a pod is deleted |
| `--force` | `-Force` | off | Hard delete (`--grace-period=0 --force`) |
| `--dry-run` | `-DryRun` | off | List pods + which would be deleted, no deletion |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `--json` | `-Json` | off | Output result as JSON |
| `--csv` | `-Csv` | off | Output result as CSV |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (including no pods / no deletions) or dry-run |
| 1 | Configuration or safety violation (bad input, kubectl missing) |
| 2 | Partial failure (a delete failed) |

---

## 5. Safety Guardrails

- **Namespace**: non-empty; must be a valid DNS label (lowercase alphanumerics and hyphens).
- **Label selector**: non-empty.
- **Threshold**: non-negative integer.
- **kubectl**: must be available on PATH; otherwise exit 1.
- **Dry-run**: no pod is deleted.
- **Graceful by default**: hard delete only with `--force`.

---

## 6. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
namespace, label selector, threshold, pods seen, deleted count and outcome. Write failures are
best-effort and do not change the exit code.

---

## 7. Scope Exclusions (v1)

No continuous watch loop, no multi-namespace, no pod creation, no deployment/replicaset
management, no resource limits. One namespace + selector per invocation. Audit write is best-effort.

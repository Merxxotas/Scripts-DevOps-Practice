# Disk Usage Monitor — Bash vs PowerShell Architecture Comparison 📊

The Disk Usage Monitor is implemented in both **POSIX Bash** (`disk_monitor.sh`) and **PowerShell**
(`disk_monitor.ps1`). Both are the same program with two coats of paint: one contract, one set of
exit codes, one audit format, one mail hand-off. This document separates what the two
implementations **must** share from what they **may** differ on, and explains the design decisions
that produced the shared contract.

The module measures **one** filesystem per invocation and hands an alert to the **host's mail
agent**. It holds no credentials and opens no socket of its own.

---

## ⚡ Feature & Architecture Matrix

| Dimension / Metric | POSIX Bash (`disk_monitor.sh`) | PowerShell (`disk_monitor.ps1`) |
| :--- | :--- | :--- |
| **Primary Platform** | Linux, macOS, any POSIX host | Windows, Windows Server (also Linux/macOS via PowerShell 7) |
| **Runtime Interpreter** | Bash 4.0+ | PowerShell 7.0+ (`#Requires -Version 7.0`) |
| **Measurement Source** | `df -P <path>` (POSIX output format) | `df -P <path>` on Unix; `Get-CimInstance Win32_LogicalDisk` on Windows |
| **Default Partition** | `/` | `/` on Unix; `$env:SystemDrive\` on Windows |
| **Parameter Syntax** | GNU-style flags: `-p`, `--partition` | PowerShell named parameters: `-Partition` |
| **Verbosity** | `-v` / `--verbose` (own flag) | `-Verbose` (a PowerShell **common parameter**) |
| **Dry Run** | `-n` / `--dry-run` | `-DryRun` (a `[switch]`) |
| **Help** | `-h` / `--help` | `-Help` (a `[switch]`) |
| **Threshold Type** | String, validated by regex at run time | `[int]` with `[ValidateRange(1, 100)]` on the parameter |
| **Notify Type** | String, validated at run time | `[string]` with `[ValidateSet("none", "mail")]` on the parameter |
| **Error Output** | `>&2` on the shell's error stream | `[Console]::Error.WriteLine` |
| **Mail Agent Lookup** | `command -v` on `PATH` | `Get-Command` on `PATH` |
| **External Dependencies** | `df` and a mail agent | `df` (Unix) or the WMI/CIM stack (Windows), and a mail agent |

---

## 🤝 Where the Two Implementations Are Identical

Parity is a repository invariant, not an aspiration: the same flags, the same defaults, the same
validation, the same exit codes and the same messages. The table below is the **contract**; neither
implementation may drift from it.

| Contract element | Shared behaviour |
| :--- | :--- |
| **Option count** | 9 options, one flag per behaviour |
| **Default threshold** | `80` |
| **Default notify backend** | `mail` |
| **Threshold semantics** | Alerts when usage is **strictly greater** than the threshold. Usage *equal* to the threshold does **not** alert. |
| **Exit codes** | `0` success · `1` configuration/safety error · `2` partial failure |
| **Threshold crossing** | Exit `0`. The alert is the product, not an error. |
| **Failure ordering** | Parse → validate → measure → report. The configuration is validated **before** the disk is measured. |
| **Environment contract** | `DISK_MONITOR_TO`, `DISK_MONITOR_MAIL_COMMAND`, `DISK_MONITOR_USAGE_COMMAND`, `DISK_MONITOR_USAGE_OVERRIDE` |
| **Mail contract** | `<mail-command> -s <subject> <recipient>`, with the body on **stdin** |
| **Default mail candidates** | `mail`, then `msmtp` |
| **Audit format** | `<ISO-8601 UTC> [<LEVEL>] <message>`, one line per run, appended |
| **Audit levels** | `INFO` for a completed run, `ERROR` for a failure |
| **Guardrails** | `-n` / `-DryRun` reports without sending; `--notify none` / `-Notify none` suppresses the hand-off entirely |

Both suites assert the same 24 scenarios against the same public interface, so a divergence in any
row above is a test failure, not a documentation drift.

---

## 🔀 Where They Legitimately Differ

These differences are **required by the platform**, not accidental.

| # | Difference | Why it must differ |
| :-- | :-- | :--- |
| 1 | **Measurement source** | `df` does not exist on Windows and `Win32_LogicalDisk` does not exist on Unix. The contract is "report the usage percentage of a mounted filesystem", not "report the output of `df`". |
| 2 | **Default partition** | `/` is the root of a Unix filesystem; `%SystemDrive%\` is the root of a Windows volume. |
| 3 | **Parameter syntax** | Bash has no named parameters; PowerShell has no `--long-options`. The *set* of behaviours is identical. |
| 4 | **Where validation happens** | PowerShell's `[ValidateRange]` / `[ValidateSet]` reject a bad threshold or notify backend **in the parameter binder**, before the script body runs. Bash validates inside `validate_configuration`. The exit code is `1` either way; only the message differs. |
| 5 | **Volume arithmetic** | `Win32_LogicalDisk` reports `Size` and `FreeSpace`, so PowerShell computes `(Size - FreeSpace) / Size`. `df` reports its own capacity column. The two agree to within a rounding point, but they are not bit-identical numbers. |
| 6 | **Verbose flag** | `-Verbose` is already a PowerShell common parameter, so the script captures it once at script scope. Bash needs its own `-v`. |

> **The CI matrix runs the PowerShell suite on Ubuntu as well as Windows.** That is deliberate: it
> proves the POSIX path is the primary one and the Windows volume API is the *fallback*, so a
> design that only works on the author's Linux box never ships.

---

## 🏗️ Design Decisions

### 1. Validate before measure

The configuration is fully resolved **before** the disk is touched: threshold, notify backend,
partition, measurement command, recipient, mail agent.

```text
parse flags → validate configuration → resolve recipient → resolve mail agent → measure → report
```

The alternative — measure first, resolve the mail agent only when an alert is needed — is cheaper
on the happy path and **catastrophically worse** on the failure path. With that ordering, a broken
alerting path is discovered at 03:00, when the disk finally fills, and the operator learns about it
from a full disk instead of from the monitor. Validating first turns that into a failure at
deployment time, where it is cheap to fix.

Cost: one `command -v` lookup per run. Benefit: the alerting path is proven before it is needed.

### 2. A credential-free transport

The module composes a subject and a body, then hands them to an external mail agent:

```text
<mail-command> -s <subject> <recipient>     # body on stdin
```

It holds **no** credentials and performs **no** network call of its own. Everything secret lives in
the mail agent's own configuration, outside this repository and outside the module.

Raw SMTP and webhook transports were considered and rejected:

| Transport | Rejected because |
| :--- | :--- |
| Direct SMTP | A credential lifecycle would have to be duplicated into every module, and the secrets would end up in the repository's history. |
| Webhook | It changes the module's stated purpose from "watch a filesystem" to "integrate with an alerting product", and it would need a second implementation for parity. |

The hand-off also keeps the test suite honest: the mail agent is stubbed on `PATH`, so the suite
never sends a real email and never depends on the host's disk layout.

### 3. Capacity is read from the fifth field

```bash
df -P <path>   # Filesystem 1024-blocks Used Available Capacity Mounted on
```

`df -P` produces exactly one line per filesystem with a fixed six-field POSIX layout. The capacity
is the **fifth** field, and the mount point is everything after it, so it is read as `$5`:

```bash
capacity="$(printf '%s\n' "$output" | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"
```

Three reasons, in order of importance:

1. **It is the only position that is stable across GNU and macOS.** The seed read column `5` of
   `df -h`, and `df -h` is *not* the same layout everywhere: macOS adds an inode column and wraps
   long device names onto a second header line. That is the exact trap that broke module 5.
2. **It survives a mount point containing spaces.** The mount point is the last field and it may
   be several words long, so counting back from the end would read part of the mount point instead
   of the capacity. The fifth field is fixed however many words the mount point has.
3. **`-P` is the format designed for scripts.** The human-readable `-h` format is explicitly not
   guaranteed to be stable.

### 4. Crossing the threshold is not a failure

Usage above the threshold exits `0`. The tool did its job: it measured the disk, compared the
number and raised the alarm. Treating the alarm as an error would make every scheduler, CI step
and monitoring wrapper treat a healthy monitor as a broken one.

The exit code is reserved for the tool's own health:

| Code | Meaning | When |
| :--: | :--- | :--- |
| `0` | Success | The check ran; the alert was delivered, not needed, or deliberately suppressed. |
| `1` | Configuration / safety error | Unknown flag, threshold outside 1–100, missing partition, unset recipient, unresolvable mail agent or measurement command. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent. |

Code `2` is the interesting one: the *check* worked, the *delivery* did not. A full disk on a host
whose mail agent is broken produces `2`, never a silent success.

### 5. Two guardrails, not one

| Guardrail | Effect | Use it when |
| :--- | :--- | :--- |
| `-n` / `-DryRun` | Reports the pending alert and hands **nothing** to the mail agent. | You want to see what would be sent. |
| `--notify none` / `-Notify none` | Suppresses the hand-off **and** the whole alerting configuration. No recipient is required. | You only want the measurement, or you are running the module on a host with no mail agent at all. |

`-n` still resolves the mail agent and the recipient, because validation always runs first. That
is what makes a dry run a genuine rehearsal: it proves the alerting path is live before the disk
fills.

### 6. A forced value is always labelled

`DISK_MONITOR_USAGE_OVERRIDE` replaces the measurement with a fixed percentage. It exists so a
test — or a rehearsal — can drive the alert path on a host that is not actually full.

A forced value is **never** presented as a measured one. The report prints `(overridden)` beside
the percentage, and the audit log records `Source: overridden` instead of `Source: measured`:

```text
2026-10-21T16:33:41Z [INFO] ALERT SENT to ops@example.com (Usage: 91%, Source: overridden, Threshold: 80%)
```

A monitor whose output can lie is worse than no monitor. The label is what makes the override safe
to use in a lab.

### 7. The audit log is an artefact, not a side effect

Every run appends exactly one ISO-8601 line to `-l` / `-LogFile`:

```text
2026-10-21T16:32:54Z [INFO] Usage within threshold (Usage: 49%, Source: measured, Threshold: 80%)
2026-10-21T16:32:54Z [INFO] ALERT SENT to ops@example.com (Usage: 91%, Source: overridden, Threshold: 80%)
2026-10-21T16:32:54Z [ERROR] FAILED to hand the alert to the mail agent (Usage: 91%, Source: overridden)
```

Two properties matter:

- **The timestamp is UTC and ISO-8601**, so lines from several hosts interleave into one readable
  timeline without a timezone puzzle.
- **A failing audit write never breaks the measurement.** The write is best-effort by design: a
  monitor that dies because its log directory is read-only is a monitor that stops monitoring. The
  trade-off is stated plainly in [SCENARIOS.md](SCENARIOS.md) — on a full disk the audit line may
  be the thing that cannot be written.

---

## 🧭 When to Use Which Implementation?

| Use case | Recommended engine | Justification |
| :--- | :--- | :--- |
| **Ubuntu/Debian servers, including the Oracle Cloud VPS** | **Bash (`disk_monitor.sh`)** | Zero startup overhead, native cron integration, `df -P` is already there. |
| **macOS workstations and servers** | **Bash (`disk_monitor.sh`)** | The POSIX `df` layout is the layout the parser was written against. |
| **Windows Server and IIS hosts** | **PowerShell (`disk_monitor.ps1`)** | The native volume API reports the volume the path belongs to, and the flag syntax matches the host's shell. |
| **Fleet where both a Unix and a Windows host exist** | **Both** | The flags, defaults, validation and exit codes are identical, so the same runbook drives both. |

---

## 📎 Related Documents

- [SCENARIOS.md](SCENARIOS.md) — the operational failure modes and their exit codes.
- [Lab 1 — Threshold & Dry-Run](labs/LAB1_THRESHOLD_AND_DRY_RUN.md) — measure, compare and rehearse.
- [Lab 2 — Exit Codes & Audit Log](labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — the exit-code contract, end to end.
- [Lab 3 — Production Deployment on a VPS Relay](labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md) — cron plus a transactional relay.
- [`../README.md`](../README.md) — usage, flags and troubleshooting.

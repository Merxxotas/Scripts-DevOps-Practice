# Disk Usage Monitor — Technical Specification

## 1. System Overview

The **Disk Usage Monitor** measures the usage of **one** mounted filesystem and hands an alert
to the **host's mail agent** when the usage crosses a threshold.

It is a monitoring tool, not a remediation tool: it reports, it never deletes, prunes or
restarts. Its contract is deliberately small:

- **Measure** one partition and produce a usage percentage.
- **Compare** that percentage against a threshold and alert when it is **strictly greater**.
- **Hand** the composed alert to a mail agent the host already provides.
- **Record** one audit line per run, so an operator can prove what happened.

Three properties shape every decision in this specification:

| Property | Consequence |
| :--- | :--- |
| **Credential-free** | The module holds no secret, reads no credential file and opens no socket of its own. Everything secret lives in the mail agent's own configuration. |
| **Host-agnostic** | The contract does not vary per host. What differs between hosts is the mail agent, not the monitor. |
| **Parity** | The Bash and the PowerShell implementation expose the same flags, the same defaults, the same validation, the same exit codes and the same messages. |

Both implementations ship in the module folder:

| Implementation | File | Runtime |
| :--- | :--- | :--- |
| POSIX Bash | `disk_monitor.sh` | Bash 4.0+ on Linux and macOS |
| PowerShell | `disk_monitor.ps1` | PowerShell 7.0+ on Windows, Linux and macOS |

---

## 2. Core Architecture

The module is a linear pipeline. Every stage hands a value to the next one, and each stage can
end the run with a specific exit code.

```
+--------------------------------------------------------------------------------+
|                            1. Parse & Resolve                                 |
|  - Read the flags / parameters                                                  |
|  - Resolve the partition, the recipient and the mail agent                      |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                         2. Validate the Configuration                          |
|  - Threshold inside 1-100, notify backend in {none, mail}                       |
|  - Partition exists, measurement command resolvable                            |
|  - Recipient set, mail agent resolvable                                         |
|  - Fail with exit 1 BEFORE the disk is touched                                  |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                              3. Measure                                        |
|  - df -P on Linux and macOS, Win32_LogicalDisk on Windows                       |
|  - Capacity taken from the fifth field of the POSIX layout                      |
|  - A forced value short-circuits the measurement and is labelled overridden     |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                           4. Compare & Report                                  |
|  - usage > threshold ? warn : report that usage is within the threshold         |
|  - Dry run: report the pending alert, hand nothing to the mail agent            |
|  - Notify none: suppress the hand-off, no recipient needed                      |
|  - Otherwise: <mail-command> -s <subject> <recipient>, body on stdin            |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                            5. Audit & Exit                                    |
|  - Append exactly one ISO-8601 line to the audit log                           |
|  - Exit 0, 1 or 2                                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles

1. **Validate before measure.** The configuration is fully resolved before the disk is
   touched. The alternative discovers a broken alerting path at 03:00, when the disk finally
   fills, and the operator learns about it from a full disk instead of from the monitor.
2. **A credential-free transport.** The module composes a subject and a body and hands them
   to an external mail agent. It holds no credentials and performs no network call of its own.
3. **Crossing the threshold is not a failure.** The alert is the product, not an error. A
   monitor that exited non-zero every time it fired would be indistinguishable from a monitor
   that was broken.
4. **A forced value is always labelled.** An overridden percentage is never presented as a
   measured one, in the report or in the audit log.
5. **The audit write is best-effort.** A monitor that dies because its log directory is
   read-only is a monitor that stops monitoring.
6. **One contract, two implementations.** The data contract is written once. The PowerShell
   side mirrors the observed behaviour of the Bash side rather than designing its own.

---

## 3. Technology Stack & Runtime Requirements

| Component | Linux / macOS target | Windows target |
| :--- | :--- | :--- |
| **Primary script** | `disk_monitor.sh` | `disk_monitor.ps1` |
| **Runtime interpreter** | Bash 4.0+ | PowerShell 7.0+ (`#Requires -Version 7.0`) |
| **Measurement source** | `df -P <path>` | `df -P <path>` on Unix; `Get-CimInstance Win32_LogicalDisk` on Windows |
| **Mail agent** | `mail`, then `msmtp` | `mail`, then `msmtp` |
| **Audit sink** | A file appended by the module | A file appended by the module |
| **External dependencies** | None beyond the operating system | None beyond the operating system |

The PowerShell implementation runs on Linux `pwsh` as well, because the CI matrix exercises it
on Ubuntu. The POSIX path is therefore the primary one and the Windows volume API is the
fallback.

---

## 4. Command-Line Interface

Both implementations accept the same nine options with the same defaults. The syntax differs
because the shells differ; the behaviour does not.

### 4.1 Bash implementation (`disk_monitor.sh`)

```
disk_monitor.sh [OPTIONS]
```

| Flag | Long form | Argument | Description | Default |
| :--- | :--- | :--- | :--- | :--- |
| `-p` | `--partition` | `<path>` | Mount point to watch | `/` |
| `-t` | `--threshold` | `<percent>` | Alert when usage is **strictly greater** | `80` |
| `-n` | `--dry-run` | — | Report the alert, hand nothing to the mail agent | off |
| — | `--notify` | `<none\|mail>` | Notification backend | `mail` |
| — | `--to` | `<address>` | Recipient of the alert | `$DISK_MONITOR_TO` |
| — | `--mail-command` | `<cmd>` | Mail agent to hand the alert to | platform default |
| `-l` | `--log-file` | `<file>` | Append an ISO-8601 audit line per run | none |
| `-v` | `--verbose` | — | Diagnostic output | off |
| `-h` | `--help` | — | Usage, exit codes and examples | — |

### 4.2 PowerShell implementation (`disk_monitor.ps1`)

```
disk_monitor.ps1 [-Partition <String>] [-Threshold <Int32>] [-DryRun] [-Notify <String>]
                 [-To <String>] [-MailCommand <String>] [-LogFile <String>] [-Help]
                 [-Verbose]
```

| Parameter | Type | Description | Default |
| :--- | :--- | :--- | :--- |
| `-Partition` | `[string]` | Mount point to watch | `/` on Unix, `$env:SystemDrive\` on Windows |
| `-Threshold` | `[int]` | Alert when usage is **strictly greater** | `80` |
| `-DryRun` | `[switch]` | Report the alert, hand nothing to the mail agent | off |
| `-Notify` | `[string]` | Notification backend, `none` or `mail` | `mail` |
| `-To` | `[string]` | Recipient of the alert | `$env:DISK_MONITOR_TO` |
| `-MailCommand` | `[string]` | Mail agent to hand the alert to | platform default |
| `-LogFile` | `[string]` | Append an ISO-8601 audit line per run | none |
| `-Help` | `[switch]` | Usage, exit codes and examples | — |
| `-Verbose` | common parameter | Diagnostic output | off |

`-Verbose` is a PowerShell **common parameter**, so the script captures it once in the script
scope. Inside a function `$PSBoundParameters` describes the function's own parameters, not the
script's, so the flag would never be seen there.

### 4.3 Validation rules

| Rule | Bash | PowerShell | Exit |
| :--- | :--- | :--- | :--: |
| Threshold is an integer in `1`–`100` | regex and range check inside `validate_configuration` | `[ValidateRange(1, 100)]` on the parameter | `1` |
| Notify backend is `none` or `mail` | string comparison inside `validate_configuration` | `[ValidateSet("none", "mail")]` on the parameter | `1` |
| An unknown option is rejected | the `case` default branch | the parameter binder | `1` |
| An option given without its value is rejected | `require_value` | the parameter binder | `1` |
| The partition must exist | `[[ ! -d "$PARTITION" ]]` | `Test-Path -PathType Container` | `1` |

The Bash and the PowerShell side both reject a bad threshold and a bad notify backend, and the
contract is exit `1` for both. Only the **message** differs, because PowerShell rejects them in
the parameter binder, before the script body runs.

---

## 5. The Environment Contract

The environment contract is identical on both sides. It exists so that a scheduled run carries
its own configuration and the command line cannot drift away from it.

| Variable | Purpose | Effect when unset |
| :--- | :--- | :--- |
| `DISK_MONITOR_TO` | Recipient of the alert | The recipient must come from `--to` / `-To`, or the run fails with `1` |
| `DISK_MONITOR_MAIL_COMMAND` | Mail agent to hand the alert to | The platform candidate list is used: `mail`, then `msmtp` |
| `DISK_MONITOR_USAGE_COMMAND` | The measurement command | `df` on Unix; the Windows volume API on Windows |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage, `0`–`100` | The disk is measured for real |

Two precedence rules decide which value wins:

```text
recipient  :  --to / -To  ->  DISK_MONITOR_TO
mail agent :  --mail-command / -MailCommand  ->  DISK_MONITOR_MAIL_COMMAND  ->  mail  ->  msmtp
```

`DISK_MONITOR_USAGE_OVERRIDE` has **no** flag equivalent. It is a rehearsal device: it lets a
test drive the alert path on a host that is not full. The report labels the resulting number
`(overridden)` and the audit line records `Source: overridden`, so a forced value can never be
mistaken for a measurement.

---

## 6. Data Shapes

### 6.1 The console report

The report goes to **stdout**; every error goes to **stderr**. The field layout is identical on
both sides.

| Field | Type | Source | Notes |
| :--- | :--- | :--- | :--- |
| `Partition` | path | `-p` / `-Partition` | The mount point that was watched |
| `Usage` | integer percent | measurement or override | Always followed by the provenance in parentheses |
| *provenance* | `measured` or `overridden` | `DISK_MONITOR_USAGE_OVERRIDE` | `overridden` when a value was forced |
| `Threshold` | integer percent | `-t` / `-Threshold` | The value the usage was compared against |
| `Mail Agent` | path | resolved agent | `(not resolved: notification disabled)` when the backend is `none` |
| `Recipient` | address | `--to` / `-To` | Printed only when the notify backend is `mail` |
| `Execution Mode` | label | `-n` / `-DryRun` | `LIVE (Alerts Active)` or `DRY RUN (Simulation)` |
| `Audit Log File` | path | `-l` / `-LogFile` | Printed only when an audit file is configured |
| `Diagnostics` | string | `-v` / `-Verbose` | Printed only in verbose mode |

### 6.2 The audit line

Every run appends **exactly one** line to the audit log:

```text
<ISO-8601 UTC timestamp> [<LEVEL>] <message>
```

The levels are `INFO` for a completed run and `ERROR` for a failure. The message vocabulary is
fixed:

| Message | Level |
| :--- | :--: |
| `Usage within threshold (Usage: <n>%, Source: <measured\|overridden>, Threshold: <t>%)` | `INFO` |
| `ALERT SENT to <address> (Usage: <n>%, Source: <measured\|overridden>, Threshold: <t>%)` | `INFO` |
| `[DRY RUN] Would send an alert to <address> (Usage: <n>%, Source: ..., Threshold: <t>%)` | `INFO` |
| `Alert suppressed by --notify none (Usage: <n>%, Source: <measured\|overridden>)` | `INFO` |
| `FAILED to hand the alert to the mail agent (Usage: <n>%, Source: ...)` | `ERROR` |
| `Invalid threshold: '<value>'.` | `ERROR` |
| `Invalid notify backend: '<value>'.` | `ERROR` |
| `Invalid usage override: '<value>'.` | `ERROR` |
| `Partition does not exist: '<path>'.` | `ERROR` |
| `Measurement command not found: '<command>'.` | `ERROR` |
| `No alert recipient configured.` | `ERROR` |
| `No mail agent could be resolved.` | `ERROR` |
| `Could not read the disk usage of '<path>'.` | `ERROR` |

An **unknown flag** produces no audit line at all: the argument parser rejects it before the
audit path is known. It is visible on stderr, not in the log.

A failing audit write is never fatal. The measurement is reported and the run continues.

Two messages name the platform's own spelling of a flag — `--notify none` and `--to` on the
Bash side, `-Notify none` and `-To` on the PowerShell side. The sentence, the level and the
rest of the vocabulary are identical; only the flag spelling follows the shell the operator
is typing into.

### 6.3 The composed alert

| Part | Shape | Example |
| :--- | :--- | :--- |
| Subject | `Disk Alert: <partition> at <usage>%` | `Disk Alert: / at 91%` |
| Body, line 1 | `Disk usage on <host> is at <usage>% (threshold: <threshold>%).` | `Disk usage on web-01 is at 91% (threshold: 80%).` |
| Body, line 2 | empty | |
| Body, line 3 | `Partition : <partition>` | `Partition : /` |
| Body, line 4 | `Usage    : <usage>%` | `Usage    : 91%` |
| Body, line 5 | `Threshold: <threshold>%` | `Threshold: 80%` |
| Body, line 6 | `Time     : <ISO-8601 UTC>` | `Time     : 2026-10-21T16:30:00Z` |

The body carries everything the on-call engineer needs to act without opening a second tool.

---

## 7. The Measurement Source

On Linux and macOS the module reads the POSIX output format:

```bash
df -P <path>
```

```text
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p2   704130048 344131112 359029080      49% /
```

Six fields in a fixed order: filesystem, blocks, used, available, capacity, mount point. The
capacity is the **fifth** field, which is its fixed position in that layout, so a mount point
that contains spaces cannot shift it. The value is validated as an integer before it is used, so
an unparsable line fails the run rather than reporting a wrong number.

`df -P` is used rather than `df -h` because `-P` is the format designed for scripts. The
human-readable format is explicitly not guaranteed to be stable, and its column layout differs
between GNU and macOS — the exact trap that broke module 5.

On Windows the module reads the native volume API:

```powershell
Get-CimInstance -ClassName Win32_LogicalDisk
```

and computes `(Size - FreeSpace) / Size`, rounded to an integer percentage. The two sources
agree to within a rounding point; they are not bit-identical numbers.

---

## 8. The Notification Contract

The module composes the subject and the body and then hands them to an external mail agent:

```text
<mail-command> -s <subject> <recipient>      # the body arrives on stdin
```

| Rule | Value |
| :--- | :--- |
| Invocation form | `<mail-command> -s <subject> <recipient>` |
| Body transport | Standard input |
| Subject | `Disk Alert: <partition> at <usage>%` |
| Default candidates | `mail`, then `msmtp` |
| Resolution order | `--mail-command` → `DISK_MONITOR_MAIL_COMMAND` → `mail` → `msmtp` |

The candidate list covers the agents that honour this contract. A host that ships a `mail`
binary with no MTA behind it still resolves, and then fails the hand-off with exit `2` — which
is the correct outcome, because the check worked and the delivery did not.

---

## 9. Exit Codes

Exit codes are a public contract. A scheduler, a CI step or a wrapper script reacts to them.

| Code | Meaning | Condition |
| :--: | :--- | :--- |
| `0` | **Success** | The check ran and the alert was delivered, not needed, or deliberately suppressed. |
| `1` | **Configuration / safety error** | Unknown flag, threshold outside `1`–`100`, unsupported notify backend, partition that does not exist, recipient unset, unresolvable mail agent, unresolvable measurement command. |
| `2` | **Partial failure** | The usage could not be read, or the alert could not be handed to the mail agent. |

**Crossing the threshold is not a failure.** The run that detects a full disk exits `0`. Only
the monitor's own breakdown exits non-zero. A `1` says the deployment is wrong and will stay
wrong until someone edits a file; a `2` says the measurement or the delivery failed right now
and may succeed on the next run.

---

## 10. Platform Differences

These differences are required by the platform, not accidental.

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| **Measurement source** | `df -P` | `df -P` on Unix; `Win32_LogicalDisk` on Windows |
| **Default partition** | `/` | `/` on Unix; `$env:SystemDrive\` on Windows |
| **Parameter syntax** | GNU-style flags | PowerShell named parameters |
| **Where the threshold is validated** | Inside `validate_configuration` | In the parameter binder, before the script body runs |
| **Volume arithmetic** | `df` reports the capacity column | `(Size - FreeSpace) / Size`, rounded |
| **Verbosity flag** | `-v` / `--verbose`, the module's own flag | `-Verbose`, a PowerShell common parameter captured in the script scope |
| **Flag named inside a message** | `--to`, `--notify`, `--mail-command` | `-To`, `-Notify`, `-MailCommand` |
| **Error stream** | `>&2` | `[Console]::Error.WriteLine` |

---

## 11. Safety Guardrails

The module notifies, so it ships guardrails. Two of them suppress the hand-off, and the rest
of the pipeline is built so that a mistake is caught before it can reach the mail agent.

| Guardrail | Effect | Use it when |
| :--- | :--- | :--- |
| `-n` / `--dry-run` | Reports the pending alert and hands **nothing** to the mail agent. | You want to see what would be sent. |
| `--notify none` / `-Notify none` | Suppresses the hand-off **and** the alerting configuration. No recipient is required. | You only want the measurement, or the host has no mail agent at all. |
| Validate before measure | A broken alerting path is reported at deployment time. | Always on; it cannot be turned off. |
| Threshold range check | A threshold outside `1`–`100` is a configuration error. | Always on. |
| Partition existence check | A partition that does not exist is a configuration error. | Always on. |
| Forced values are labelled | An overridden percentage never reads as a measured one. | Always on. |
| Best-effort audit write | A failing log write never breaks the measurement. | Always on. |

`-n` still resolves the mail agent and the recipient, because validation always runs first.
That is what makes a dry run a genuine rehearsal: it proves the alerting path is live before the
disk fills.

The module holds **no** secret. It reads no credential, stores no credential and logs no
credential. The alert recipient is an address, not a secret; the relay credential lives in the
mail agent's own configuration, outside this repository.

---

## 12. CI/CD Pipeline & Automated Testing

### 12.1 Monorepo segregation

The workflow is isolated to this module and lives at the repository root, because GitHub never
executes a workflow nested inside a module folder:

- **File**: `.github/workflows/ci-disk-monitor.yml`
- **Trigger filter**: `1-Disk-Usage-Monitoring-with-Email-Alert/**`, plus the workflow file itself

### 12.2 Quality gates & test matrix

| Job | Runner | Gate |
| :--- | :--- | :--- |
| Lint Bash | `ubuntu-24.04` | `shellcheck -x` on the implementation and the suite |
| Test Bash | `ubuntu-24.04`, `macos-14` | The Bash suite |
| Lint PowerShell | `windows-2022` | `PSScriptAnalyzer` with the module's `PSScriptAnalyzerSettings.psd1` |
| Test PowerShell | `windows-2022`, `ubuntu-24.04` | The PowerShell suite |

The PowerShell suite runs on **Ubuntu as well as Windows** on purpose: the Windows-native volume
API cannot be stubbed on `PATH`, so the shared environment contract is what makes the alert
branch testable on both. A design that only works on the author's Linux box is not a design
yet.

### 12.3 Test design

Both suites drive the **public interface** — flags, exit codes, emitted files — and both are
deterministic:

- The measurement command is replaced by a stub, so the suite never depends on the host's real
  disk layout.
- The mail agent is replaced by a stub, so the suite never sends a real email.
- The sandbox lives in a temporary directory that the suite removes in teardown.
- The threshold boundary, the forced value and the replaced command cover the cases a real
  disk cannot produce on demand.

---

## 13. Related Documents

- Usage, scheduling and troubleshooting: [`README.md`](README.md)
- Where the two implementations agree and where they differ:
  [`docs/ARCHITECTURE_COMPARISON.md`](docs/ARCHITECTURE_COMPARISON.md)
- The operational failure modes: [`docs/SCENARIOS.md`](docs/SCENARIOS.md)
- Hands-on labs: [`docs/labs/`](docs/labs/)
- Module conventions: [`CODESTYLE.md`](CODESTYLE.md)
- Milestones: [`ROADMAP.md`](ROADMAP.md)
- Repository standards: [`../AGENTS.md`](../AGENTS.md)

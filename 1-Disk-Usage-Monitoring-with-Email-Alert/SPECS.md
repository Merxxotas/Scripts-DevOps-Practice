# Disk Usage Monitor — Technical Specification

## 1. System Overview

The **Disk Usage Monitor** measures the usage of **one** mounted filesystem and hands an alert
to a **transport** — the host's mail agent or an HTTP endpoint — when the usage crosses a
threshold.

It is a monitoring tool, not a remediation tool: it reports, it never deletes, prunes or
restarts. Its contract is deliberately small:

- **Resolve** every setting from a flag, an environment variable, a configuration file or a
  built-in default, in that order.
- **Measure** one partition and produce a usage percentage.
- **Compare** that percentage against a threshold and alert when it is **strictly greater**.
- **Hand** the composed alert to the mail agent or the HTTP endpoint the configuration selects.
- **Record** one audit line per run, so an operator can prove what happened.
- **Report** the resolved configuration with `--doctor`, without measuring and without sending.

Three properties shape every decision in this specification:

| Property | Consequence |
| :--- | :--- |
| **No credential of its own** | The module reads no credential file and opens no socket of its own. A mail agent holds its own credential; an HTTP header the caller supplies may carry one, and the module never prints or logs it. |
| **Host-agnostic** | The contract does not vary per host. What differs between hosts is the mail agent or the HTTP client, not the monitor. |
| **Parity** | The Bash and the PowerShell implementation expose the same flags, the same defaults, the same validation, the same exit codes and the same report fields. The message vocabulary is identical; only a flag spelling inside a message follows the shell. |

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
|                               1. Parse & Resolve                               |
| - Read the flags / parameters and the configuration file                       |
| - Resolve every setting: flag, environment, file, default                      |
+--------------------------------------------------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                         2. Validate the Configuration                          |
| - Threshold 1-100, notify backend in {none, mail, http}                        |
| - HTTP: endpoint, timeout, method, header, client                              |
| - Partition exists, measurement command resolvable                             |
| - Recipient and mail agent resolvable when mail                                |
| - Fail with exit 1 BEFORE the disk is touched                                  |
+--------------------------------------------------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                                   3. Measure                                   |
| - df -P on Linux and macOS, Win32_LogicalDisk on Windows                       |
| - Capacity taken from the fifth field of the POSIX layout                      |
| - A forced value short-circuits the measurement and is labelled overridden     |
+--------------------------------------------------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                              4. Compare & Report                               |
| - usage > threshold ? warn : report that usage is within the threshold         |
| - Dry run: report the pending alert, hand nothing to the transport             |
| - Notify none: suppress the hand-off, no recipient needed                      |
| - mail: <mail-command> -s <subject> <recipient>, body on stdin                 |
| - http: render the body template, then the client posts it to the URL          |
+--------------------------------------------------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                                5. Audit & Exit                                 |
| - Append exactly one ISO-8601 line to the audit log                            |
| - Exit 0, 1 or 2                                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles

1. **Validate before measure.** The configuration is fully resolved before the disk is
   touched. The alternative discovers a broken alerting path at 03:00, when the disk finally
   fills, and the operator learns about it from a full disk instead of from the monitor.
2. **No credential of its own.** The module composes a subject and a body and hands them to an
   external program — a mail agent, or an HTTP client. It stores no credential and performs no
   network call of its own. A credential reaches the transport only through a value the caller
   supplies, such as a header.
3. **Crossing the threshold is not a failure.** The alert is the product, not an error. A
   monitor that exited non-zero every time it fired would be indistinguishable from a monitor
   that was broken.
4. **A forced value is always labelled.** An overridden percentage is never presented as a
   measured one, in the report or in the audit log.
5. **The audit write is best-effort.** A monitor that dies because its log directory is
   read-only is a monitor that stops monitoring.
6. **One contract, two implementations.** The data contract is written once. The PowerShell
   side mirrors the observed behaviour of the Bash side rather than designing its own.
7. **One transport, no provider code.** Every HTTP notification service is reached by the same
   request shape — a method, a URL, optional headers and a rendered body. A provider is a
   configuration, never a branch in the code.
8. **The doctor reports; it does not act.** It reads the resolved configuration and the
   resolvable dependencies and changes nothing: no measurement, no request, no write.

---

## 3. Technology Stack & Runtime Requirements

| Component | Linux / macOS target | Windows target |
| :--- | :--- | :--- |
| **Primary script** | `disk_monitor.sh` | `disk_monitor.ps1` |
| **Runtime interpreter** | Bash 4.0+ | PowerShell 7.0+ (`#Requires -Version 7.0`) |
| **Measurement source** | `df -P <path>` | `df -P <path>` on Unix; `Get-CimInstance Win32_LogicalDisk` on Windows |
| **Mail agent** | `mail`, then `msmtp` | `mail`, then `msmtp` |
| **HTTP client** | `curl` | `curl.exe` |
| **Audit sink** | A file appended by the module | A file appended by the module |
| **External dependencies** | None beyond the operating system | None beyond the operating system |

`curl` ships with most mainstream Linux distributions, with macOS, and with Windows 10 (1803)
and later, so the HTTP transport usually needs no installation. A minimal image that lacks it is
reported by `--doctor`, and `--http-command` accepts any curl-compatible client. The module still
has no library dependency of its own: the client is a command, not an imported package.

The PowerShell implementation runs on Linux `pwsh` as well, because the CI matrix exercises it
on Ubuntu. The POSIX path is therefore the primary one and the Windows volume API is the
fallback.

---

## 4. Command-Line Interface

Both implementations accept the same sixteen options with the same defaults. The syntax differs
because the shells differ; the behaviour does not.

### 4.1 Bash implementation (`disk_monitor.sh`)

```
disk_monitor.sh [OPTIONS]
```

| Flag | Long form | Argument | Description | Default |
| :--- | :--- | :--- | :--- | :--- |
| `-p` | `--partition` | `<path>` | Mount point to watch | `/` |
| `-t` | `--threshold` | `<percent>` | Alert when usage is **strictly greater** | `80` |
| `-n` | `--dry-run` | — | Report the alert, hand nothing to the transport | off |
| — | `--notify` | `<none\|mail\|http>` | Transport | `mail` |
| — | `--to` | `<address>` | Recipient of the alert, for the mail transport | `$DISK_MONITOR_TO` |
| — | `--mail-command` | `<cmd>` | Mail agent to hand the alert to | platform default |
| — | `--url` | `<url>` | HTTP endpoint | `$DISK_MONITOR_URL` |
| — | `--body-template` | `<text>` | HTTP request body | the plain-text message |
| — | `--header` | `'Name: value'` | Extra HTTP header; repeatable | none |
| — | `--timeout` | `<seconds>` | HTTP timeout | `10` |
| — | `--http-command` | `<cmd>` | HTTP client | `curl` |
| `-l` | `--log-file` | `<file>` | Append an ISO-8601 audit line per run | none |
| — | `--json` | — | Output result as JSON | off |
| — | `--csv` | — | Output result as CSV | off |
| — | `--config` | `<file>` | Configuration file to read | resolution chain, §5.4 |
| — | `--doctor` | — | Report what is configured and what is missing | — |
| `-v` | `--verbose` | — | Diagnostic output | off |
| `-h` | `--help` | — | Usage, exit codes and examples | — |

### 4.2 PowerShell implementation (`disk_monitor.ps1`)

```
disk_monitor.ps1 [-Partition <String>] [-Threshold <String>] [-DryRun] [-Notify <String>]
                 [-To <String>] [-MailCommand <String>] [-Url <String>] [-BodyTemplate <String>]
                 [-Header <String[]>] [-Timeout <String>] [-HttpCommand <String>]
                 [-LogFile <String>] [-Config <String>] [-Doctor] [-Help] [-Verbose]
```

| Parameter | Type | Description | Default |
| :--- | :--- | :--- | :--- |
| `-Partition` | `[string]` | Mount point to watch | `/` on Unix, `$env:SystemDrive\` on Windows |
| `-Threshold` | `[string]` | Alert when usage is **strictly greater** | `80` |
| `-DryRun` | `[switch]` | Report the alert, hand nothing to the transport | off |
| `-Notify` | `[string]` | Transport, `none`, `mail` or `http` | `mail` |
| `-To` | `[string]` | Recipient of the alert, for the mail transport | `$env:DISK_MONITOR_TO` |
| `-MailCommand` | `[string]` | Mail agent to hand the alert to | platform default |
| `-Url` | `[string]` | HTTP endpoint | `$env:DISK_MONITOR_URL` |
| `-BodyTemplate` | `[string]` | HTTP request body | the plain-text message |
| `-Header` | `[string[]]` | Extra HTTP header; repeatable | none |
| `-Timeout` | `[string]` | HTTP timeout | `10` |
| `-HttpCommand` | `[string]` | HTTP client | `curl` |
| `-LogFile` | `[string]` | Append an ISO-8601 audit line per run | none |
| `-Config` | `[string]` | Configuration file to read | resolution chain, §5.4 |
| `-Doctor` | `[switch]` | Report what is configured and what is missing | — |
| `-Help` | `[switch]` | Usage, exit codes and examples | — |
| `-Verbose` | common parameter | Diagnostic output | off |

`-Verbose` is a PowerShell **common parameter**, so the script captures it once in the script
scope. Inside a function `$PSBoundParameters` describes the function's own parameters, not the
script's, so the flag would never be seen there.

`-Threshold` and `-Timeout` are **strings**, not numbers. The environment and the configuration
file can hold a value that is not a number, and the tool has to report that value instead of
failing to bind it. The parameter block therefore carries no `[ValidateRange]` and no
`[ValidateSet]`: every value, whatever its source, is judged by the same validation the doctor
runs.

### 4.3 Validation rules

| Rule | Bash | PowerShell | Exit |
| :--- | :--- | :--- | :--: |
| Threshold is an integer in `1`–`100` | `is_valid_threshold` in `validate_configuration` | `Test-ThresholdValue` in `Invoke-DiskMonitor` | `1` |
| Notify backend is `none`, `mail` or `http` | string comparison in `validate_configuration` | the same comparison in `Invoke-DiskMonitor` | `1` |
| Timeout is a whole number above zero | `is_valid_timeout` | `Test-TimeoutValue` in `Invoke-DiskMonitor` | `1` |
| The endpoint is an `http` or `https` URL | regex in `validate_configuration` | the same rule in `Invoke-DiskMonitor` | `1` |
| The method is an HTTP token | regex in `validate_configuration` | the same rule in `Invoke-DiskMonitor` | `1` |
| A header matches `Name: value` | `check_headers` | `Assert-HttpHeader` | `1` |
| An unknown option is rejected | the `case` default branch | the parameter binder | `1` |
| An option given without its value is rejected | `require_value` | the parameter binder | `1` |
| The partition must exist | `[[ ! -d "$PARTITION" ]]` | `Test-Path -PathType Container` | `1` |

Both sides validate **after** the resolution, so a bad value is reported the same way whichever
source supplied it. Because the PowerShell binder no longer refuses one, `--doctor` can report
the offending value and its origin instead of the tool dying before the report exists. Only the
flag spelling quoted in a message follows the shell the operator is typing into.

### 4.4 The doctor command

`--doctor` answers one question: can this tool do its job on this host? It resolves the
configuration, checks that the measurement command and the transport client can be found, and
reports whether a recipient or an endpoint is set. It measures nothing, sends nothing and writes
nothing.

```text
============================================================
                 Disk Usage Monitor - Doctor
============================================================
Platform            : Linux (cachyos)
Config file         : (none found)
Partition           : / (default)
Threshold           : 80% (default)
Notify backend      : mail (default)
Endpoint            : (not required)
Recipient           : (not set)
HTTP client         : (not required)
Mail agent          : /usr/bin/mail (default)
Measurement command : /usr/bin/df (default)
Audit log file      : (not set)
HTTP headers        : 0 (default)
------------------------------------------------------------
Status              : NOT READY
  - No recipient is configured. Set --to, or DISK_MONITOR_TO, or the 'to' key in the configuration file.
```

| Rule | Value |
| :--- | :--- |
| Provenance marker | `(default)`, `(flag)`, `(environment)` or `(config)`; `(not required)` when the active transport does not use the setting; `(none found)` or `(not found: <path>)` for a configuration file that is absent, where the second is a problem |
| Exit `0` | The tool is ready to run |
| Exit `1` | Something is missing; every problem carries a one-line remedy |
| A header value | Never shown — the report gives the header count and its source |
| A configuration file other users can read | A warning with its remedy; it does not change the exit code |
| A missing dependency | Reported with the install command of the platform the tool was found on |

The report is the whole product: a doctor that changed the host would be a second thing to
verify before the first thing could be trusted.

---

## 5. The Configuration Model

One model resolves every setting, whether it names a partition, a transport or a timeout. The
model has four sources, one order, and one rule for reporting where a value came from.

### 5.1 Precedence

```text
command-line flag  ->  environment variable  ->  configuration file  ->  built-in default
```

The first source that supplies a value wins, and the run records which source it was. `--doctor`
prints that record. The order is not configurable: a value on the command line always wins, so a
scheduled command can override a shared file without editing it.

### 5.2 The environment contract

Fourteen variables, identical on both sides. They exist so that a scheduled run carries its own
configuration and the command line cannot drift away from it.

| Variable | Purpose | Effect when unset |
| :--- | :--- | :--- |
| `DISK_MONITOR_PARTITION` | Mount point to watch | `/` on Unix; the root of the current drive on Windows |
| `DISK_MONITOR_THRESHOLD` | The alert threshold, `1`–`100` | `80` |
| `DISK_MONITOR_NOTIFY` | Transport: `none`, `mail` or `http` | `mail` |
| `DISK_MONITOR_TO` | Recipient of the alert | `--to` / `-To` or the `to` key must supply it, or a `mail` run fails with `1` |
| `DISK_MONITOR_MAIL_COMMAND` | Mail agent to hand the alert to | The platform candidate list is used: `mail`, then `msmtp` |
| `DISK_MONITOR_LOG_FILE` | Audit log path | No audit line is written |
| `DISK_MONITOR_USAGE_COMMAND` | The measurement command | `df` on Unix; the Windows volume API on Windows |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage, `0`–`100` | The disk is measured for real |
| `DISK_MONITOR_CONFIG` | Configuration file to read | `./.diskmonitor.conf`, then `~/.config/disk-monitor/config` |
| `DISK_MONITOR_URL` | HTTP endpoint | `--url` / `-Url` or the `url` key must supply it, or an `http` run fails with `1` |
| `DISK_MONITOR_BODY_TEMPLATE` | HTTP request body template | The plain-text message is sent |
| `DISK_MONITOR_HEADER` | One extra HTTP header, `Name: value` | No extra header is sent |
| `DISK_MONITOR_TIMEOUT` | HTTP timeout in seconds | `10` |
| `DISK_MONITOR_HTTP_COMMAND` | HTTP client | `curl` |

`DISK_MONITOR_USAGE_OVERRIDE` has **no** flag equivalent. It is a rehearsal device: it lets a
test drive the alert path on a host that is not full. The report labels the resulting number
`(overridden)` and the audit line records `Source: overridden`, so a forced value can never be
mistaken for a measurement.

### 5.3 The configuration file

Both implementations read the same file, in a minimal `key = value` format that needs no parser
library: a minimal Linux image has no `jq` and no TOML library, and Windows PowerShell has no
TOML parser.

```ini
# .diskmonitor.conf
url = https://ntfy.sh/your-topic
partition = /
threshold = 85
body_template = {body}
header = Authorization: Bearer your-token
```

| Rule | Behaviour |
| :--- | :--- |
| Comment | A line whose first non-space character is `#` |
| Separator | The first `=`; the spaces around the key and the value are trimmed |
| Quoting | A value may be wrapped in single or double quotes to protect its spaces |
| Unknown key | Reported by name and ignored |
| Malformed line | Reported by its **line number** and ignored; the line is never echoed, because it may hold a token |
| Both of the last two | A warning: the run continues |

The set is fixed at thirteen keys:

| Key | Meaning | Default |
| :--- | :--- | :--- |
| `partition` | Mount point to watch | `/`, or the current drive on Windows |
| `threshold` | Alert threshold, `1`–`100` | `80` |
| `notify` | Transport: `none`, `mail` or `http` | `mail` |
| `to` | Mail recipient | none |
| `mail_command` | Mail agent | `mail`, then `msmtp` |
| `log_file` | Audit log path | none |
| `usage_command` | Measurement command | `df` |
| `usage_override` | Forced usage percentage, `0`–`100` | none |
| `url` | HTTP endpoint | none |
| `body_template` | HTTP request body | the plain-text message |
| `method` | HTTP request method | `POST` |
| `timeout` | HTTP timeout in seconds | `10` |
| `header` | One extra HTTP header; repeat the key for several | none |

`method` is the only setting with no flag and no environment variable: an HTTP method is a
transport detail, not something a scheduled line changes.

### 5.4 Which file is read

```text
--config <file>  ->  DISK_MONITOR_CONFIG  ->  ./.diskmonitor.conf  ->  ~/.config/disk-monitor/config
```

A file named by `--config` or `DISK_MONITOR_CONFIG` must exist; a missing one is exit `1`. An
absent default file is not an error, and the built-in defaults are used. A file that exists but
cannot be read by the account that runs the tool is also exit `1`, because falling back to the
defaults would measure the disk with another threshold and another transport. The same resolution
runs on both implementations, and `--doctor` reports its result as the `Config file` field.

### 5.5 The file is sensitive

A configuration file may hold a bearer token in a `header` value. Three rules follow:

- The repository ignores `.diskmonitor.conf`, so a local file cannot be committed by accident.
- `--doctor` warns when the selected file is readable by other users, and prints the remedy for
  the platform it found. The warning does not change the exit code, because the tool still runs.
  The remedy is a command the reader pastes, so the path is quoted for the shell of the platform;
  on Windows the remedy also removes the explicit `Everyone` grant that caused the warning. The
  read-access remedy printed by the doctor and by a run is quoted the same way, and it ends the
  line so nothing of the sentence is pasted as part of the path.
- A file that exists but cannot be read is a problem and exits `1`, in the doctor and in a run.
- Nothing copies a line of the file into a log, and the doctor reports the header count and its
  source, never a value.

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
| `Mail Agent` | path | resolved agent | `(not resolved: notification disabled)` when the backend is `none`; omitted when the backend is `http` |
| `Recipient` | address | `--to` / `-To` | Printed only when the notify backend is `mail` |
| `Endpoint` | URL | `--url` / `-Url` | Printed instead of `Mail Agent` when the backend is `http` |
| `HTTP Client` | path | resolved client | Printed when the backend is `http` |
| `Execution Mode` | label | `-n` / `-DryRun` | `LIVE (Alerts Active)` or `DRY RUN (Simulation)` |
| `Audit Log File` | path | `-l` / `-LogFile` | Printed only when an audit file is configured |
| `Diagnostics` | string | `-v` / `-Verbose` | Printed only in verbose mode |
| `Transport` | string | `-v` / `-Verbose` | Printed only in verbose mode with the `http` backend: endpoint, template, method and timeout sources, client and header count |

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
| `ALERT SENT to <address or endpoint> (Usage: <n>%, Source: <measured\|overridden>, Threshold: <t>%)` | `INFO` |
| `[DRY RUN] Would send an alert to <address or endpoint> (Usage: <n>%, Source: ..., Threshold: <t>%)` | `INFO` |
| `Alert suppressed by --notify none (Usage: <n>%, Source: <measured\|overridden>)` | `INFO` |
| `FAILED to hand the alert to the mail agent (Usage: <n>%, Source: ...)` | `ERROR` |
| `FAILED to hand the alert to the HTTP client (Usage: <n>%, Source: ...)` | `ERROR` |
| `Invalid threshold: '<value>'.` | `ERROR` |
| `Invalid notify backend: '<value>'.` | `ERROR` |
| `Invalid usage override: '<value>'.` | `ERROR` |
| `Invalid HTTP endpoint: '<value>'.` | `ERROR` |
| `Invalid HTTP timeout: '<value>'.` | `ERROR` |
| `Invalid HTTP method: '<value>'.` | `ERROR` |
| `Malformed HTTP header.` | `ERROR` |
| `Malformed HTTP header: it carries a line break.` | `ERROR` |
| `Partition does not exist: '<path>'.` | `ERROR` |
| `Measurement command not found: '<command>'.` | `ERROR` |
| `No alert recipient configured.` | `ERROR` |
| `No mail agent could be resolved.` | `ERROR` |
| `No HTTP endpoint configured.` | `ERROR` |
| `No HTTP client could be resolved.` | `ERROR` |
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

## 8. The Transport Contract

The module composes the subject and the body once. A transport delivers them, and the transport
is selected by `--notify` / `-Notify`.

### 8.1 The transport set

| Value | Transport | Needs | Available |
| :--- | :--- | :--- | :--- |
| `none` | Suppresses the hand-off entirely | Nothing | Since the baseline |
| `mail` | The host's mail agent | A recipient, and an agent on `PATH` | Since the baseline |
| `http` | An external HTTP client | An endpoint | Since this specification |

A value outside that set is a configuration error with exit `1`. `smtp` is **refused**, not
reserved: `--notify smtp` exits `1` and the refusal names `none`, `mail` and `http`, so no
deployment can select a transport that does not exist. The seam stays a value, and the behaviour
of `mail` is unchanged.

### 8.2 The mail transport

```text
<mail-command> -s <subject> <recipient>      # the body arrives on stdin
```

| Rule | Value |
| :--- | :--- |
| Invocation form | `<mail-command> -s <subject> <recipient>` |
| Body transport | Standard input |
| Subject | `Disk Alert: <partition> at <usage>%` |
| Default candidates | `mail`, then `msmtp` |
| Resolution order | `--mail-command` → `DISK_MONITOR_MAIL_COMMAND` → `mail_command` → `mail` → `msmtp` |

The candidate list covers the agents that honour this contract. A host that ships a `mail`
binary with no MTA behind it still resolves, and then fails the hand-off with exit `2` — which
is the correct outcome, because the check worked and the delivery did not.

### 8.3 The HTTP transport

One HTTP transport covers every HTTP notification service, because ntfy, Telegram, Discord,
Slack and a self-hosted receiver are all the same primitive: a request with a body to a URL. The
transport therefore carries no provider-specific code, and adding a provider is a configuration,
not a code path.

| Setting | Flag | Environment | Config key | Default |
| :--- | :--- | :--- | :--- | :--- |
| The endpoint | `--url <url>` | `DISK_MONITOR_URL` | `url` | none — required |
| The request body | `--body-template <text>` | `DISK_MONITOR_BODY_TEMPLATE` | `body_template` | the plain-text message |
| Extra headers | `--header 'Name: value'` | `DISK_MONITOR_HEADER` | `header` | none |
| The method | — | — | `method` | `POST` |
| The timeout in seconds | `--timeout <seconds>` | `DISK_MONITOR_TIMEOUT` | `timeout` | `10` |

The client is invoked as:

```text
<http-command> --silent --show-error --fail --max-time <seconds> --request <method> \
               --header 'Name: value'... --data-binary @- <url>
```

The rendered body is written to standard input, followed by a newline. `--fail` is what turns an
HTTP error status into a failed hand-off: without it the client exits `0` for a `4xx` or a `5xx`,
and a rejected alert would be reported and audited as sent. A replacement for the default `curl`
must accept that argument set; a wrapper that rejects an unknown option fails every HTTP alert with
exit `2`. No flag supplies the
method: `method` is a configuration key with the default `POST`, because an HTTP method is a
transport detail and not something a scheduled line changes. An endpoint that is not an `http`
or `https` URL, a timeout that is not a whole number above zero, a method that is not an HTTP
token, and a header that does not match `Name: value` each exit `1`.

### 8.4 The body template

| Placeholder | Value | Example |
| :--- | :--- | :--- |
| `{subject}` | The alert subject | `Disk Alert: / at 91%` |
| `{body}` | The composed plain-text alert, six lines | `Disk usage on web-01 is at 91% ...` |
| `{partition}` | The watched mount point | `/` |
| `{usage}` | The usage, carrying the percent sign | `91%` |
| `{threshold}` | The threshold, carrying the percent sign | `80%` |
| `{recipient}` | The address the alert is addressed to; for this transport, the endpoint | `https://ntfy.sh/disk-alerts` |
| `{host}` | The host that ran the check | `web-01` |
| `{timestamp}` | ISO-8601 UTC | `2026-10-22T17:45:42Z` |

Three rules make the template safe to use as JSON:

1. The template is rendered in a **single pass**, so a substituted value is never scanned again.
2. An unknown placeholder is copied verbatim, which is what keeps a JSON body's braces intact.
3. When no template is configured, the composed plain-text alert is the body.

`{body}` spans six lines, and a JSON string cannot carry a raw line feed. A JSON template
therefore uses the single-line placeholders — `{"text":"{subject} on {host}"}` renders valid
JSON, while `{"text":"{body}"}` does not.

### 8.5 Client resolution

```text
--http-command <cmd>  ->  DISK_MONITOR_HTTP_COMMAND  ->  curl
```

The client is an external command resolved on `PATH`, so the same client is used on every
platform, and the test suites replace it on `PATH` instead of opening a socket. On Windows the
resolver searches `curl`, then `curl.exe`, and accepts only an **application**: the legacy
PowerShell `curl` alias cannot capture the name, and the real `curl.exe` is reached.

### 8.6 Secrecy

A header may carry a bearer token, and the audit log is a durable file. The transport therefore
follows three rules:

- A header value is **never** printed, never reported as an error and never written to the audit
  log. The report and the doctor give the header count and the source of the header list.
- A header that is malformed is described by its position and the expected shape, never by its
  content.
- The configuration file that may hold the header is treated as sensitive: the repository
  ignores it, and `--doctor` reports one that other users can read.

One boundary is unavoidable and is documented rather than hidden: an endpoint is part of the
record (`ALERT SENT to <endpoint>`), so a token embedded in the **URL** appears in the report and
in the audit line. That is the shape of an API such as Telegram's, where the token is a path
segment — not a logging choice. A provider that accepts the token in a header keeps it quiet.

---

## 9. Exit Codes

Exit codes are a public contract. A scheduler, a CI step or a wrapper script reacts to them.

| Code | Meaning | Condition |
| :--: | :--- | :--- |
| `0` | **Success** | The check ran and the alert was delivered, not needed, or deliberately suppressed. |
| `1` | **Configuration / safety error** | Unknown flag; threshold outside `1`–`100`; unsupported transport; partition that does not exist; recipient unset for the `mail` transport; endpoint, timeout, method or header invalid; unresolvable mail agent, HTTP client or measurement command; unreadable configuration file; malformed configuration value. |
| `2` | **Partial failure** | The usage could not be read, or the alert could not be handed to the mail agent or the HTTP client. |

**Crossing the threshold is not a failure.** The run that detects a full disk exits `0`. Only
the monitor's own breakdown exits non-zero. A `1` says the deployment is wrong and will stay
wrong until someone edits a file; a `2` says the measurement or the delivery failed right now
and may succeed on the next run.

`--doctor` reuses `0` and `1` as a readiness answer: `0` means ready, `1` means something is
missing. It never returns `2`, because it measures nothing and sends nothing.

---

## 10. Platform Differences

These differences are required by the platform, not accidental.

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| **Measurement source** | `df -P` | `df -P` on Unix; `Win32_LogicalDisk` on Windows |
| **Default partition** | `/` | `/` on Unix; `$env:SystemDrive\` on Windows |
| **Parameter syntax** | GNU-style flags | PowerShell named parameters |
| **Where a value is validated** | Inside `validate_configuration`, after the resolution | Inside `Invoke-DiskMonitor`, after the resolution |
| **HTTP client** | `curl` | `curl.exe`, resolved as an application so the alias cannot capture it |
| **Configuration file** | The same `key = value` format | The same `key = value` format |
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
| `-n` / `--dry-run` | Reports the pending alert and hands **nothing** to the transport. | You want to see what would be sent. |
| `--notify none` / `-Notify none` | Suppresses the hand-off **and** the alerting configuration. No recipient is required. | You only want the measurement, or the host has no transport at all. |
| `--doctor` | Reports what is configured and what is missing, and changes nothing. | Before the first scheduled run, and after every edit to the configuration. |
| Validate before measure | A broken alerting path is reported at deployment time. | Always on; it cannot be turned off. |
| Threshold range check | A threshold outside `1`–`100` is a configuration error. | Always on. |
| Partition existence check | A partition that does not exist is a configuration error. | Always on. |
| Forced values are labelled | An overridden percentage never reads as a measured one. | Always on. |
| Best-effort audit write | A failing log write never breaks the measurement. | Always on. |
| A header value is never logged | A token in a header cannot reach the audit file or the console. | Always on. |
| A readable-by-others configuration file is reported | The doctor names the exposure and the remedy. | Always on. |

`-n` still resolves the transport and its target, because validation always runs first.
That is what makes a dry run a genuine rehearsal: it proves the alerting path is live before the
disk fills.

The module stores **no** secret of its own. It reads no credential file and logs no credential.
The alert recipient is an address, not a secret; a mail relay credential lives in the mail
agent's own configuration, outside this repository. The one secret the module can carry is a
header value the caller supplies for the HTTP transport, and §8.6 fixes how it is handled.

---

## 12. Scope and Reuse

### 12.1 Deliberately out of scope

| Deferred item | Why |
| :--- | :--- |
| An SMTP transport | It needs an account, a domain and a credential lifecycle; a free account is not guaranteed to stay free, and self-hosting a relay is blocked on many VPS providers. |
| A local-mail-only transport | A local mail agent exists on Linux and not on Windows, so it cannot be the universal path. |
| A provider-specific transport | The HTTP transport already reaches every provider; a second path would be one more thing to maintain per provider. |

Both deferred transports are **refused, not reserved**: `--notify smtp` exits `1` and the
refusal names `none`, `mail` and `http`. The seam stays a value, so adding one later is a change
to the set and not a redesign.

### 12.2 The pattern is the deliverable

The transport, the configuration model and the doctor are the template for modules 3, 4, 6, 7, 8,
9 and 10. A module that adopts them keeps its own measurement and its own module contract, and
takes four things from here unchanged:

| Taken from here | What it gives the adopting module |
| :--- | :--- |
| The transport set | `none`, `mail` and `http` with one meaning each |
| The configuration model | Four sources, one order, a provenance record |
| The doctor | A readiness answer, and the remedy for the platform it runs on |
| The exit-code contract | `0`, `1` and `2`, unchanged in meaning |

No part of the pattern needs a paid service, and none of it is distribution-specific: the file
format needs no parser library, the HTTP client is bundled with macOS, with Windows 10 and later,
and with most mainstream Linux distributions, and any dependency is a free command on `PATH` that
the caller can replace.

---

## 13. CI/CD Pipeline & Automated Testing

### 13.1 Monorepo segregation

The workflow is isolated to this module and lives at the repository root, because GitHub never
executes a workflow nested inside a module folder:

- **File**: `.github/workflows/ci-disk-monitor.yml`
- **Trigger filter**: `1-Disk-Usage-Monitoring-with-Email-Alert/**`, plus the workflow file itself

### 13.2 Quality gates & test matrix

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

### 13.3 Test design

Both suites drive the **public interface** — flags, exit codes, emitted files — and both are
deterministic:

- The measurement command is replaced by a stub, so the suite never depends on the host's real
  disk layout.
- The mail agent is replaced by a stub, so the suite never sends a real email.
- The HTTP client is replaced by a stub on `PATH`, so the request is captured and asserted
  without opening a socket.
- The parity tests read the other implementation as a source file and compare the long flags,
  the parameters, the `DISK_MONITOR_*` names and the configuration keys as sets, in both
  directions, so a setting added to one side and forgotten on the other fails both suites.
- The sandbox lives in a temporary directory that the suite removes in teardown.
- The threshold boundary, the forced value and the replaced command cover the cases a real
  disk cannot produce on demand.

---

## 14. Related Documents

- Usage, scheduling and troubleshooting: [`README.md`](README.md)
- Where the two implementations agree and where they differ:
  [`docs/ARCHITECTURE_COMPARISON.md`](docs/ARCHITECTURE_COMPARISON.md)
- The operational failure modes: [`docs/SCENARIOS.md`](docs/SCENARIOS.md)
- Hands-on labs: [`docs/labs/`](docs/labs/)
- Module conventions: [`CODESTYLE.md`](CODESTYLE.md)
- Milestones: [`ROADMAP.md`](ROADMAP.md)
- Repository standards: [`../AGENTS.md`](../AGENTS.md)

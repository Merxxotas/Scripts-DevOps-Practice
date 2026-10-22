# Disk Usage Monitor — Bash vs PowerShell Architecture Comparison 📊

The Disk Usage Monitor is implemented in both **POSIX Bash** (`disk_monitor.sh`) and **PowerShell**
(`disk_monitor.ps1`). Both are the same program with two coats of paint: one contract, one set of
exit codes, one audit format, one transport contract. This document separates what the two
implementations **must** share from what they **may** differ on, and explains the design decisions
that produced the shared contract.

The module measures **one** filesystem per invocation and hands an alert to the **configured
transport** — the host's mail agent, or an HTTP endpoint. The module opens no socket of its own: an
external HTTP client sends the request, and a credential travels in a header the caller supplies.

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
| **Threshold Type** | String, validated by the script at run time | `[string]`, validated by the script at run time |
| **Notify Type** | String, validated at run time (`none`, `mail`, `http`) | `[string]`, validated at run time (`none`, `mail`, `http`) |
| **Error Output** | `>&2` on the shell's error stream | `[Console]::Error.WriteLine` |
| **Mail Agent Lookup** | `command -v` on `PATH` | `Get-Command` on `PATH` |
| **HTTP Client Lookup** | `command -v`, or the path of a file | `Get-Command -CommandType Application`, or the path of a file |
| **Config File Reader** | `while read` over the file | `Get-Content` over the file |
| **External Dependencies** | `df` and a mail agent, or `df` and `curl` | `df` (Unix) or the WMI/CIM stack (Windows), plus a mail agent or `curl` |

---

## 🤝 Where the Two Implementations Are Identical

Parity is a repository invariant, not an aspiration: the same flags, the same defaults, the same
validation, the same exit codes and the same messages. The table below is the **contract**; neither
implementation may drift from it.

| Contract element | Shared behaviour |
| :--- | :--- |
| **Option count** | 16 options, one flag per behaviour |
| **Default threshold** | `80` |
| **Default notify backend** | `mail` |
| **Threshold semantics** | Alerts when usage is **strictly greater** than the threshold. Usage *equal* to the threshold does **not** alert. |
| **Exit codes** | `0` success · `1` configuration/safety error · `2` partial failure |
| **Threshold crossing** | Exit `0`. The alert is the product, not an error. |
| **Failure ordering** | Parse → resolve → validate → measure → report. The configuration is validated **before** the disk is measured. |
| **Precedence** | Flag → environment variable → configuration file → built-in default |
| **Environment contract** | 14 `DISK_MONITOR_*` variables, listed below the table |
| **Config file keys** | 13 keys, listed below the table |
| **Mail contract** | `<mail-command> -s <subject> <recipient>`, with the body on **stdin** |
| **HTTP contract** | One external client argv, with the body on **stdin** (detailed later in this document) |
| **Default mail candidates** | `mail`, then `msmtp` |
| **Default HTTP client** | `curl` |
| **Audit format** | `<ISO-8601 UTC> [<LEVEL>] <message>`, one line per run, appended |
| **Audit levels** | `INFO` for a completed run, `ERROR` for a failure |
| **Header secrecy** | The value is never printed or logged; only count and source |
| **Guardrails** | `-n` / `-DryRun` reports without sending; `notify none` suppresses the hand-off |

The 14 environment variables are `DISK_MONITOR_PARTITION`, `DISK_MONITOR_THRESHOLD`,
`DISK_MONITOR_NOTIFY`, `DISK_MONITOR_TO`, `DISK_MONITOR_MAIL_COMMAND`, `DISK_MONITOR_LOG_FILE`,
`DISK_MONITOR_USAGE_COMMAND`, `DISK_MONITOR_USAGE_OVERRIDE`, `DISK_MONITOR_CONFIG`,
`DISK_MONITOR_URL`, `DISK_MONITOR_BODY_TEMPLATE`, `DISK_MONITOR_HEADER`, `DISK_MONITOR_TIMEOUT`
and `DISK_MONITOR_HTTP_COMMAND`.

The 13 configuration keys are `partition`, `threshold`, `notify`, `to`, `mail_command`,
`log_file`, `usage_command`, `usage_override`, `url`, `body_template`, `method`, `timeout` and
`header`.

Both suites assert the same scenario matrix against the same public interface, and the parity tests
compare the two declarations, so a divergence in any row above is a test failure, not a
documentation drift.

---

## 🔀 Where They Legitimately Differ

These differences are **required by the platform**, not accidental.

| # | Difference | Why it must differ |
| :-- | :-- | :--- |
| 1 | **Measurement source** | `df` does not exist on Windows and `Win32_LogicalDisk` does not exist on Unix. The contract is "report the usage percentage of a mounted filesystem", not "report the output of `df`". |
| 2 | **Default partition** | `/` is the root of a Unix filesystem; `%SystemDrive%\` is the root of a Windows volume. |
| 3 | **Parameter syntax** | Bash has no named parameters; PowerShell has no `--long-options`. The *set* of behaviours is identical. |
| 4 | **Where validation happens** | Both validate in the script, before measuring. PowerShell's parameters are strings on purpose: a value the binder refused would never reach the doctor. The exit code is `1` either way; only the message differs. |
| 5 | **Volume arithmetic** | `Win32_LogicalDisk` reports `Size` and `FreeSpace`, so PowerShell computes `(Size - FreeSpace) / Size`. `df` reports its own capacity column. The two agree to within a rounding point, but they are not bit-identical numbers. |
| 6 | **Verbose flag** | `-Verbose` is already a PowerShell common parameter, so the script captures it once at script scope. Bash needs its own `-v`. |
| 7 | **Template rendering** | Bash uses parameter expansion; PowerShell uses `IndexOf(Ordinal)`. Both substitute in one left-to-right pass and never rescan a value. |
| 8 | **Config parsing** | `while read` versus `Get-Content`; both split on the first `=`, strip one layer of quotes and accept the same 13 keys. |
| 9 | **HTTP client lookup** | `command -v` versus `Get-Command -Application`; the latter avoids the legacy `curl` alias on Windows. |
| 10 | **Flag provenance** | Bash keeps `FLAG_*_SET`; PowerShell captures `$PSBoundParameters.ContainsKey(...)` at script scope. |
| 11 | **Config path expansion** | `${HOME:-.}` versus `$env:HOME`; the same four candidates in the same order. |

> **The CI matrix runs the PowerShell suite on Ubuntu as well as Windows.** That is deliberate: it
> proves the POSIX path is the primary one and the Windows volume API is the *fallback*, so a
> design that only works on the author's Linux box never ships.

---

## 🌐 The Transport as a Comparison Dimension

The branch adds a second transport, an HTTP request, and a configuration file that both
implementations parse. The transport is where the two languages diverge most in *how* they do it
and least in *what* they do, which makes it the clearest place to see the contract.

### The shared transport contract

| Setting | Flag | Environment | Config key | Default |
| :--- | :--- | :--- | :--- | :--- |
| Endpoint | `--url` / `-Url` | `DISK_MONITOR_URL` | `url` | none — required for `http` |
| Request body | `--body-template` / `-BodyTemplate` | `DISK_MONITOR_BODY_TEMPLATE` | `body_template` | the plain-text message |
| Extra headers | `--header` / `-Header` | `DISK_MONITOR_HEADER` | `header` | none |
| Method | — | — | `method` | `POST` |
| Timeout | `--timeout` / `-Timeout` | `DISK_MONITOR_TIMEOUT` | `timeout` | `10` |
| Client | `--http-command` / `-HttpCommand` | `DISK_MONITOR_HTTP_COMMAND` | — | `curl` |

There is no `--method` flag and no method environment variable: the method is a configuration key
only, and it defaults to `POST`. That asymmetry is deliberate. The one setting that no environment
variable and no flag carries is the one a JSON provider rarely needs to change, and adding both
would create two more sources for a setting whose default is already the common answer.

### Rendering the body template

The template supports eight placeholders: `{subject}`, `{body}`, `{partition}`, `{usage}`,
`{threshold}`, `{recipient}`, `{host}` and `{timestamp}`. `{usage}` and `{threshold}` arrive with
the percent sign already attached. `{recipient}` is the endpoint for the HTTP transport.

Both implementations render in **one left-to-right pass**:

1. Find the earliest known placeholder in the remaining template.
2. Copy the literal text before it.
3. Append the value.
4. Continue *after* the placeholder, so the value is never scanned again.

That last rule is what keeps a JSON template intact. A partition named `{usage}` cannot be expanded
a second time, and the JSON braces are not placeholders, so they are copied verbatim. The rendered
body is written to the client's standard input followed by one newline.

| Step | Bash | PowerShell |
| :--- | :--- | :--- |
| Find the placeholder | `${rest%%"{$key}"*}` and the prefix length | `$rest.IndexOf("{" + $key + "}", Ordinal)` |
| Append and continue | `${rest:$((best_position + ${#best_key} + 2))}` | `$rest.Substring($bestIndex + $bestKey.Length + 2)` |
| Unknown placeholder | copied verbatim | copied verbatim |

### Parsing the `key = value` file

Neither implementation uses a parser library. A minimal Linux image has no `jq` and no TOML
library, and Windows PowerShell has no TOML parser, so the file format is the smallest one both
can read without a dependency.

Both sides skip a blank line and a `#` comment, split on the **first** `=`, trim both sides, strip
one layer of matching single or double quotes, and map the key through a fixed set of 13 names.
An unknown key is a warning, not a failure. A repeated scalar key keeps the last value. A repeated
`header` key accumulates, because a request may carry several headers.

The one thing a `key = value` parser must not do is echo the line it cannot parse: the line may be a
bearer token pasted into the wrong file. Both sides name the line by its **number only**:

```text
Warning: ignoring malformed line 2 in '/etc/disk-monitor/disk-monitor.conf'.
```

### Applying the four-level precedence

Every setting goes through the same resolution:

```text
flag  →  environment variable  →  configuration file  →  built-in default
```

and every resolved setting carries the **name of the source it came from**, which is what the
doctor and the verbose report print. The rules are the same on both sides:

- A flag counts when the parser saw it, even when its value is empty.
- An environment variable counts when it is non-empty; whitespace is a value, not an absence.
- A configuration value counts when it is non-empty, by the same rule.
- The built-in default is the floor, and it is labelled `default`.

The mechanics differ only because the languages do:

| Step | Bash | PowerShell |
| :--- | :--- | :--- |
| Was the flag supplied? | `FLAG_*_SET` set by `parse_arguments` | `$PSBoundParameters.ContainsKey(...)`, captured at script scope |
| Read the environment | `${DISK_MONITOR_X:-}` | `[string]$env:DISK_MONITOR_X` |
| Return value and source | `printf '%s\t%s'`, split on the tab | a `[pscustomobject]@{ Value; Source }` |

The PowerShell capture has to happen at script scope. Inside a function, `$PSBoundParameters`
describes the function's own parameters, so a flag read there would look absent and only the
environment would ever win.

### Resolving and invoking the external HTTP client

The client is an **external command**, not a library call:

```text
--http-command  →  DISK_MONITOR_HTTP_COMMAND  →  curl
```

That choice is what makes the transport universal. `curl` ships with macOS and with Windows 10
(1803) and later, and it is one package away on Linux, so the transport needs no language runtime
or library. It is also what makes the test suite deterministic: the suite puts a stub earlier on
`PATH` and the module invokes the stub, on every platform, without a network.

| Step | Bash | PowerShell |
| :--- | :--- | :--- |
| Resolve a named client | `command -v` | `Get-Command -CommandType Application` |
| Accept a path | `[[ -f ]]` | `Test-Path -LiteralPath ... -PathType Leaf` |
| Default lookup | `command -v curl` | `curl`, then `curl.exe`, as applications |

The invocation is the same argv on both sides:

```text
<client> --silent --show-error --fail --max-time <seconds> --request <method> \
         [--header '<Name: value>']... --data-binary @- <url>
```

with the rendered body on standard input. `--silent --show-error` keeps the client quiet on success
and still reports why a request failed; `--fail` makes an HTTP error status a non-zero exit, so a
rejected alert is a failed hand-off and not a recorded delivery. `--data-binary @-` sends the body
byte for byte, including its newlines.

PowerShell's `-CommandType Application` is not decoration. In Windows PowerShell, `curl` is an alias
for `Invoke-WebRequest`; asking for an application reaches the real `curl.exe` and can never be
captured by the alias. The Windows CI runner proves it: the doctor reports a file on disk.

A client that resolves but exits non-zero is a **partial failure**: exit `2`. The client's own
diagnostics are left on the error stream, so the operator sees why.

### Keeping a header out of the log

A header may carry a bearer token, and the audit log is a durable file. Both implementations
therefore follow the same rule: **the value is never printed, never reported and never written**.

| Surface | What it shows |
| :--- | :--- |
| Normal report | Nothing about headers |
| Verbose report | `headers 1 (flag)` — the count and the source |
| Doctor | `HTTP headers : 1 (flag)` — the count and the source |
| Audit log | The endpoint, the usage, the source and the threshold; no header |
| Malformed header | `Error: Header 1 is malformed. Expected 'Name: value'.` — the position, not the text |
| Malformed config line | The line number, not the line |

The configuration file is treated as sensitive for the same reason. The repository ignores
`.diskmonitor.conf`, the doctor warns when the file is readable by a group or by others, and no
code path copies its contents into a log.

Two limits are worth stating plainly rather than hiding:

1. **The endpoint is printed and logged.** A provider that embeds its token in the URL path —
   Telegram, Discord and Slack webhooks all do — puts that token in the audit log. A header-based
   endpoint (ntfy with `Authorization:`) does not. Treat a webhook URL as a secret.
2. **The header value is visible in the process argument list while the request runs.** That is how
   every HTTP client receives a header. The alternative would write the token to a file, which is
   worse. The module does not print it; the operating system shows it to a local user who can
   already read the process table.

---

## 🏗️ Design Decisions

### 1. Validate before measure

The configuration is fully resolved **before** the disk is touched: threshold, notify backend,
partition, measurement command, and the whole transport — the recipient and mail agent, or the
endpoint, method, timeout, headers and HTTP client.

```text
parse flags → load config → apply precedence → validate → resolve transport → measure → report
```

The alternative — measure first, resolve the transport only when an alert is needed — is cheaper
on the happy path and **catastrophically worse** on the failure path. With that ordering, a broken
alerting path is discovered at 03:00, when the disk finally fills, and the operator learns about it
from a full disk instead of from the monitor. Validating first turns that into a failure at
deployment time, where it is cheap to fix.

Cost: one or two `command -v` lookups per run. Benefit: the alerting path is proven before it is
needed.

### 2. One primitive, two transports

The module composes a subject and a body, then hands them to the configured transport. The `mail`
transport is unchanged:

```text
<mail-command> -s <subject> <recipient>     # body on stdin
```

The `http` transport is one request with a body to a URL:

```text
<http-command> --silent --show-error --fail --max-time <seconds> --request <method> \
               [--header '<Name: value>']... --data-binary @- <url>
```

That single primitive covers ntfy, Telegram, Discord, Slack and a self-hosted receiver, so the
transport carries **no provider-specific code**. The only provider-specific part is the body
template, and a template is data, not code. One implementation therefore serves every provider,
which is what makes "any provider" affordable instead of a per-provider branch.

Neither transport opens a socket in the module. The mail agent and the HTTP client are external
commands resolved on `PATH`, and the suite replaces both with stubs, so no test sends a real email
or a real request and no test depends on the host's disk layout.

Credentials live outside the module. The mail agent holds its own configuration; the HTTP
transport forwards a header the caller supplies and never prints or logs its value. The module
itself is still credential-free.

Direct SMTP remains out of scope. It needs an account and a domain, the credential lifecycle would
have to be duplicated into every module, and the secrets would end up in the repository's history.
A provider-specific integration remains out of scope too: it would change the module's stated
purpose from "watch a filesystem" to "integrate with an alerting product", and it would need one
implementation per provider for parity.

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
| `1` | Configuration / safety error | Unknown flag, threshold outside 1–100, missing partition, unset recipient, missing endpoint, invalid URL, timeout or method, malformed header, unresolvable mail agent, HTTP client or measurement command. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent or the HTTP client. |

Code `2` is the interesting one: the *check* worked, the *delivery* did not. A full disk on a host
whose mail agent or HTTP client is broken produces `2`, never a silent success.

### 5. Two guardrails, not one

| Guardrail | Effect | Use it when |
| :--- | :--- | :--- |
| `-n` / `-DryRun` | Reports the pending alert and hands **nothing** to the transport. | You want to see what would be sent. |
| `--notify none` / `-Notify none` | Suppresses the hand-off **and** the whole alerting configuration. No recipient and no endpoint are required. | You only want the measurement, or you are running the module on a host with no transport at all. |

`-n` still resolves the transport — the mail agent and recipient, or the HTTP client and endpoint —
because validation always runs first. That is what makes a dry run a genuine rehearsal: it proves
the alerting path is live before the disk fills.

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

The same line is written for the HTTP transport, with the endpoint in place of the recipient:

```text
2026-10-22T17:45:46Z [INFO] ALERT SENT to https://ntfy.sh/lab-disk-alerts (Usage: 91%, Source: overridden, Threshold: 80%)
2026-10-22T17:46:01Z [ERROR] FAILED to hand the alert to the HTTP client (Usage: 91%, Source: overridden)
```

The endpoint is recorded because it is the address that was attempted; a header value never is.

### 8. The doctor answers the deployment question before cron does

`--doctor` resolves the configuration, prints every value with the source it came from, checks that
the measurement command and the transport client exist, and reports what is missing with a remedy.
It measures nothing and sends nothing.

The exit code is the deployment verdict: `0` ready, `1` something missing. That is what lets a
provisioning script stop before it writes a cron entry that can only fail. A monitor that is
misconfigured should be discovered at deploy time, not at 03:00 when the disk fills — the same
argument as decision 1, applied to the configuration itself.

The remedy is per platform on purpose. On this Linux host a missing client is reported with the
package manager that is actually installed; on macOS with `brew`; on Windows the remedy says that
`curl.exe` ships with Windows 10 (1803) and later. A generic suggestion is not an instruction the
reader can run.

---

## 🧭 When to Use Which Implementation?

| Use case | Recommended engine | Justification |
| :--- | :--- | :--- |
| **Ubuntu/Debian servers, including the Oracle Cloud VPS** | **Bash (`disk_monitor.sh`)** | Zero startup overhead, native cron integration, `df -P` is already there. |
| **macOS workstations and servers** | **Bash (`disk_monitor.sh`)** | The POSIX `df` layout is the layout the parser was written against. |
| **Windows Server and IIS hosts** | **PowerShell (`disk_monitor.ps1`)** | The native volume API reports the volume the path belongs to, and the flag syntax matches the host's shell. |
| **Fleet where both a Unix and a Windows host exist** | **Both** | The flags, defaults, validation and exit codes are identical, so the same runbook drives both. |
| **A host with no MTA that must still alert** | **Both**, with `--notify http` | The HTTP transport needs only `curl`, which ships with the platform, and one endpoint. |
| **A host that already has a working mail relay** | **Both**, with `--notify mail` | The existing hand-off is unchanged; the relay stays where it is. |

---

## 📎 Related Documents

- [SCENARIOS.md](SCENARIOS.md) — the operational failure modes and their exit codes.
- [Lab 1 — Threshold, Dry-Run & Configuration](labs/LAB1_THRESHOLD_AND_DRY_RUN.md) — measure, compare, rehearse and prove the precedence.
- [Lab 2 — Exit Codes & Audit Log](labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — the exit-code contract, end to end.
- [Lab 3 — Production Deployment with the Universal Transport](labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md) — HTTP as the primary path, a relay as the migration path.
- [`../README.md`](../README.md) — usage, flags and troubleshooting.

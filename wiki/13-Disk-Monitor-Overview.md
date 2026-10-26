# 13. Disk Usage Monitor — Overview & Specs

> Module 1 of the [Scripts-DevOps-Practice](https://github.com/Merxxotas/Scripts-DevOps-Practice)
> monorepo: a threshold monitor that measures one filesystem and hands an
> alert to a transport — `none`, `mail` or `http` — when the filesystem
> crosses the threshold.

---

## What it is

A sensor, not an actuator. The module measures the usage of one mounted
filesystem and, when that usage passes a threshold, it hands an alert to one
of three transports. It deletes nothing, rotates nothing and restarts
nothing. A `--doctor` command reports what the configuration resolves to
before the first scheduled run.

| Concern | Value |
| :--- | :--- |
| Implementations | `disk_monitor.sh` (Bash) · `disk_monitor.ps1` (PowerShell 7) |
| Watched filesystems | one per invocation |
| Alert transports | `none` · `mail` (default) · `http` |
| Credentials held | none of its own — an HTTP header may carry a token |
| Sockets opened | none of its own — the HTTP client opens the connection |
| Runtime dependencies | `df` or the volume API · a mail agent · an HTTP client |

Three properties are the reason the module was designed this way, and they
are worth stating before anything else:

* **The module holds no credential store.** For `mail`, whatever
  authentication the agent needs belongs to the agent, and never enters this
  repository. For `http`, a header value may carry a bearer token, read from
  the configuration file; it is never printed, never reported as an error and
  never written to the audit log.
* **The module opens no socket of its own.** There is no SMTP conversation
  and no HTTP client inside the script. The `http` transport resolves an
  external client as a command and hands it the request, exactly as the
  `mail` transport hands a message to a mail agent.
* **The transport is a value, not a code path.** `--notify` selects `none`,
  `mail` or `http`. The report, the dry run, the audit record and the exit
  codes are shared by all three.

---

## Where it sits in the repository

Module 1 and module 2 are two halves of the same operational loop:

| | Module 1 — Disk Usage Monitor | Module 2 — Log Cleanup |
| :--- | :--- | :--- |
| Role | **sensor** — reports the pressure | **actuator** — relieves it |
| Action | measures, reports, alerts | deletes, prunes, accounts |
| State | read-only | destructive, with guardrails |

Module 1 notices that a filesystem is filling up. Module 2 is what a human
then points at the problem. Keeping the two apart is what makes the sensor
safe to schedule every five minutes on every host: a monitor that only
reports cannot damage anything.

Module 1 is also the **template for the remaining seed modules**. Its shape
— a Bash and a PowerShell implementation of one contract, guardrails, a
dry-run mode, an exit-code contract, a test suite, a CI pipeline — is the
shape the other seven seeds will be converted to.

---

## The CLI surface

Both implementations expose the same set, with the same defaults. The
parity suite compares the two sets as set equality (see
[page 14](14-Disk-Monitor-Bash-vs-PowerShell.md)).

| Flag | PowerShell | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `-p, --partition <path>` | `-Partition` | `/` · the system drive | Mount point to watch |
| `-t, --threshold <percent>` | `-Threshold` | `80` | Alert when usage is strictly greater |
| `-n, --dry-run` | `-DryRun` | off | Report the alert and hand it nowhere |
| `--notify <none\|mail\|http>` | `-Notify` | `mail` | Transport backend |
| `--to <address>` | `-To` | `DISK_MONITOR_TO` | Mail recipient |
| `--mail-command <cmd>` | `-MailCommand` | platform candidates | Mail agent to hand the alert to |
| `--url <url>` | `-Url` | none — required for `http` | HTTP endpoint |
| `--body-template <text>` | `-BodyTemplate` | the plain-text message | HTTP request body |
| `--header 'Name: value'` | `-Header` | none | Extra HTTP header; repeatable |
| `--timeout <seconds>` | `-Timeout` | `10` | HTTP timeout; whole number above zero |
| `--http-command <cmd>` | `-HttpCommand` | `curl` | HTTP client to send the request with |
| `-l, --log-file <file>` | `-LogFile` | none | Path to append ISO-8601 audit records |
| `--config <file>` | `-Config` | see the precedence below | Configuration file to read |
| `--doctor` | `-Doctor` | — | Report what is configured and what is missing |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output, including where each value came from |
| `-h, --help` | `-Help` | — | Usage and examples |

`--threshold` accepts `1`–`100` only. `--notify` accepts `none`, `mail` or
`http` only; any other value exits `1` with a refusal that names the three
supported backends. `--timeout` accepts a whole number of seconds above
zero. An unknown flag is a configuration error.

**There is no `--method` flag.** The HTTP method is a configuration key only,
default `POST`, because it is a property of the endpoint and not of the
invocation. Everything else in the table can be set on the command line.

The **strictly greater** comparison is deliberate. A filesystem sitting at
exactly 80 % with a threshold of 80 is not over the threshold, so no alert
fires. That single comparison is what keeps a monitor from mailing every
five minutes about a filesystem that has been at 80 % for a week.

---

## Exit codes

Exit codes are a public contract. A scheduler reads them, so they are
documented, stable, and identical on both sides.

| Code | Meaning | Condition |
| :--: | :--- | :--- |
| `0` | Success | The check ran; the alert was delivered, not needed, or suppressed. |
| `1` | Configuration / safety error | A value the tool cannot use, or an input it must refuse. |
| `2` | Partial failure | The usage could not be read, or the hand-off failed. |

The conditions behind `1`:

* an unknown flag, or a `--notify` value other than `none`, `mail` or `http`;
* a threshold outside `1`–`100`, or a value that is not an integer;
* a partition that does not exist;
* for `mail`: no recipient, or a mail agent that cannot be resolved;
* for `http`: no endpoint, an endpoint that is not an `http`/`https` URL, a
  timeout outside its range, a malformed header, an invalid method, or an
  HTTP client that cannot be resolved;
* a configuration file named explicitly that does not exist, or a malformed
  value read from a configuration file.

The conditions behind `2` are the two that happen after validation: the
measurement produced nothing usable, or the resolved transport failed.

**Crossing the threshold is not a failure.** The tool did its job and
reported the condition, so it still exits `0`. The alert is the product, not
an error.

**A failed hand-off is `2`, not `1`.** The check worked; the delivery did
not. That distinction is what tells an operator reading a cron log whether
the measurement was broken or the mail or HTTP path was.

**The doctor has its own two-code contract.** `--doctor` exits `0` when the
tool is ready to run and `1` when something is missing. It never reports `2`,
because it measures nothing and sends nothing.

---

## The environment contract

Identical on both sides: fourteen variables, every one optional. A flag
overrides the environment, which overrides the configuration file, which
overrides the built-in default.

| Variable | Effect | Overridden by |
| :--- | :--- | :-- |
| `DISK_MONITOR_PARTITION` | The mount point to watch. | `--partition` / `-Partition` |
| `DISK_MONITOR_THRESHOLD` | The alert threshold. | `--threshold` / `-Threshold` |
| `DISK_MONITOR_NOTIFY` | The transport backend. | `--notify` / `-Notify` |
| `DISK_MONITOR_TO` | The mail recipient. | `--to` / `-To` |
| `DISK_MONITOR_MAIL_COMMAND` | The mail agent. | `--mail-command` / `-MailCommand` |
| `DISK_MONITOR_LOG_FILE` | The audit log path. | `--log-file` / `-LogFile` |
| `DISK_MONITOR_CONFIG` | The configuration file to read. | `--config` / `-Config` |
| `DISK_MONITOR_URL` | The HTTP endpoint. | `--url` / `-Url` |
| `DISK_MONITOR_BODY_TEMPLATE` | The HTTP body. | `--body-template` / `-BodyTemplate` |
| `DISK_MONITOR_HEADER` | Extra HTTP headers, one per line. | `--header` / `-Header` |
| `DISK_MONITOR_TIMEOUT` | The HTTP timeout in seconds. | `--timeout` / `-Timeout` |
| `DISK_MONITOR_HTTP_COMMAND` | The HTTP client. | `--http-command` / `-HttpCommand` |
| `DISK_MONITOR_USAGE_COMMAND` | The command that measures the filesystem. | no flag |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage, labelled `overridden`. | no flag |

The **deployment knobs** — recipient, backend, endpoint, headers, log path —
are the ones a scheduler sets once per host. The last two are the
**measurement knobs**: they let the measurement be stubbed or forced, which
is what makes the test suite deterministic and what lets an operator rehearse
an alert without waiting for a disk to fill up. `DISK_MONITOR_USAGE_COMMAND`
replaces the `df` call on Unix, and on Windows it replaces the volume API
query.

The environment is where a scheduler belongs. A cron entry does not need a
recipient repeated in a flag; the recipient lives in the host's service
environment, and the same script runs on the next host with a different
recipient.

A variable set to an empty string is not a value: the next source in the
precedence supplies the setting instead. That rule is identical on both
sides, and it is why an empty `DISK_MONITOR_TO` in a unit file does not
silently disable the recipient.

---

## How the measurement works

**On Unix**, the module runs `df -P <path>` and reads the capacity from the
fifth field.

The `-P` flag is the whole reason the module works on macOS. The
human-readable format (`df -h`) can wrap a long filesystem name onto a line
of its own, which shifts every column after it — the exact trap that broke
module 5 on macOS. The POSIX format guarantees one line per filesystem and a
fixed column layout:

```
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p2   704130048 344127680 359049408      49% /
```

The capacity is the fifth field from the left, and the mount point is
everything after it. Reading the fifth field means the position does not
depend on the length of the filesystem name, the size of the block count, or
the width of the percentage — and it does not depend on the mount point
either, which may be several words long, as on `/mnt/My Backup`.

**On Windows**, the module asks the volume API directly:
`Get-CimInstance Win32_LogicalDisk`, then computes
`round((size - free) / size * 100)`.

**Failing safe.** Both implementations validate what they read. A capacity
that is not a number is rejected, and the run exits `2` rather than
reporting a wrong figure.

---

## The transports

`--notify` chooses one backend per invocation. The choice changes what the
alert is handed to; it changes nothing else.

| Backend | Needs | Hands the alert to | Typical use |
| :--- | :--- | :--- | :--- |
| `none` | nothing | nowhere — the alert is suppressed | a host with no alerting path yet |
| `mail` (default) | a recipient and a mail agent | the host's mail agent | a Linux host |
| `http` | an endpoint and an HTTP client | `curl` or another client | any HTTP receiver |

`none` still measures, still reports and still crosses the threshold — it
prints `Alert suppressed by --notify none.` and exits `0`. It is a way to
watch a disk without a delivery path, not a way to skip the check.

### `mail` — the existing path

The module composes a subject and a body and hands them to an external mail
agent with this contract:

```
<mail-command> -s <subject> <recipient>      # body on stdin
```

The agent is resolved in this order:

1. `--mail-command` / `-MailCommand`
2. `DISK_MONITOR_MAIL_COMMAND`
3. the platform default candidate list — `mail`, then `msmtp`

An override that cannot be resolved is an **error**, not a reason to fall
back to the candidate list. A typo in a mail-agent path must not silently
turn into a different agent than the one the operator configured.

### `http` — one primitive for every notification service

ntfy, Telegram, Discord, Slack and a self-hosted receiver are the same
primitive: a request with a body to a URL. The transport therefore carries
**no provider-specific code**. A provider is a URL, a body template and
optionally a header.

#### The request

The transport runs the resolved client as a command:

```
<http-command> --silent --show-error --fail --max-time <seconds> \
               --request <method> --header <name: value>... \
               --data-binary @- <url>
```

The rendered body goes to the client's standard input, followed by a
newline. `--fail` is what makes an HTTP error status a failed hand-off: the
client exits non-zero for a `4xx` or a `5xx`, the module exits `2` and the
audit line says `FAILED`. Without it the client exits `0` for the same
response and a rejected alert would be recorded as sent. The method comes
from the configuration key `method` and defaults to `POST`; there is no flag
for it. `--header` may be repeated, and one value may carry several headers,
one per line.

#### The body template

`--body-template` replaces the default plain-text message. Eight
placeholders are substituted in a single left-to-right pass, so a substituted
value is never substituted twice and a JSON template keeps its braces:

| Placeholder | Value |
| :--- | :--- |
| `{subject}` | the composed subject, `Disk Alert: / at 91%` |
| `{body}` | the full plain-text message |
| `{partition}` | the watched mount point |
| `{usage}` | the usage, **with** the percent sign, `91%` |
| `{threshold}` | the threshold, **with** the percent sign, `80%` |
| `{recipient}` | the endpoint the alert is addressed to |
| `{host}` | the host the measurement was taken on |
| `{timestamp}` | the UTC ISO-8601 timestamp of the alert |

An unknown placeholder is copied verbatim, which is what keeps a JSON
template intact. A JSON body for ntfy needs no provider code:

```bash
./disk_monitor.sh -n --notify http --url https://ntfy.sh/disk-alerts \
  --body-template '{"topic":"disk","message":"{body}"}'
```

#### The client

The client is an **external command**, so the same code path works on every
platform and the test suite can replace it on `PATH`. It is resolved in this
order:

1. `--http-command` / `-HttpCommand`
2. `DISK_MONITOR_HTTP_COMMAND`
3. `curl`

On Windows the PowerShell side asks the binder for an **application** and
never for an alias, so the legacy `curl` alias cannot be captured and the
real `curl.exe` is reached. That distinction is what makes the transport
work on a stock Windows host, where `curl` in a PowerShell prompt may mean
`Invoke-WebRequest`.

#### Secrets

A header may carry a bearer token. The module is built so that the value
never reaches an output:

* it is not printed in the report, not even with `--verbose`;
* it is not reported as an error, and a malformed header is named by its
  number and its position, never by its contents;
* it is not written to the audit log.

The doctor reports the **count** of headers and where they came from —
`flag`, `environment`, `config` or `default` — and never a value.

One limitation is recorded rather than hidden: the header is passed to the
client as a command-line argument, so it is visible in the process argument
list while the request runs. That is how every HTTP client takes a header.
The alternative writes the token to a file, which is worse.

**The configuration is validated before the disk is measured.** The
recipient and the mail agent, or the endpoint and the HTTP client, are
resolved first, so a broken alerting path is reported immediately, at the
start of the run, rather than at the moment an alert is actually needed. A
monitor that only discovers it cannot send mail when the disk fills up has
failed exactly when it was needed.

---

## The configuration file

Both implementations read the same file, in a minimal `key = value` format
with no parser library. A minimal Linux image has no `jq` and no TOML
library, and Windows PowerShell has no TOML parser, so the format is chosen
to need nothing.

```
# .diskmonitor.conf
url = https://ntfy.sh/your-topic
partition = /
threshold = 85
body_template = {body}
header = Authorization: Bearer your-token
```

The rules are small on purpose:

* `#` starts a comment line; blank lines are ignored.
* A value may be wrapped in single or double quotes; the quotes are removed.
* `header` may appear more than once, and all of them are sent.
* A line without `=` is **malformed**: it is ignored, named by its line
  number and never echoed, because a line pasted by mistake may hold a token.
* An unknown key is ignored with a warning that names the key; the doctor
  also names the line.

The file accepts thirteen keys:

| Key | Corresponds to | Key | Corresponds to |
| :--- | :--- | :--- | :--- |
| `partition` | the watched mount point | `usage_command` | the measurement command |
| `threshold` | the alert threshold | `usage_override` | the forced usage |
| `notify` | the transport backend | `url` | the HTTP endpoint |
| `to` | the mail recipient | `body_template` | the HTTP body |
| `mail_command` | the mail agent | `method` | the HTTP method |
| `log_file` | the audit log path | `timeout` | the HTTP timeout |
| `header` | extra HTTP headers | | |

### Precedence

Every setting resolves through the same four layers, and the winning layer
is recorded so the doctor can report it:

| Layer | Example (`threshold`) | Wins when |
| :--- | :--- | :--- |
| 1. Command-line flag | `-t 83` | the flag was supplied |
| 2. Environment variable | `DISK_MONITOR_THRESHOLD=84` | no flag was supplied |
| 3. Configuration file | `threshold = 85` | neither of the above |
| 4. Built-in default | `80` | nothing else supplied it |

The file itself is found in this order:

1. `--config <file>` / `-Config`
2. `DISK_MONITOR_CONFIG`
3. `./.diskmonitor.conf` — the working directory
4. `~/.config/disk-monitor/config`

A file named explicitly must exist: if it does not, the run exits `1` rather
than silently continuing without the configuration the operator asked for. A
file that exists but cannot be read is exit `1` for the same reason: the run
would otherwise measure the disk with defaults the operator never chose. An
absent *default* file is not an error, because most hosts configure the tool
through the environment alone.

### The file is sensitive

The repository ignores `.diskmonitor.conf`, because a header may hold a
token. The doctor warns when the file can be read by other users and prints
the `chmod 600` remedy; the warning does not make the tool "not ready",
because a fresh file is readable by others until it is restricted. The
remedy is meant to be pasted, so the path is quoted for the shell of the
platform, and the Windows remedy also removes the explicit `Everyone` grant
that caused the warning.

---

## The doctor

`--doctor` reports what is configured and what is missing. It changes
nothing: it does not measure the disk and it does not send anything.

It reports:

* the platform, and the configuration file that was found, or that none was;
* every resolved setting, with the layer it came from — `flag`,
  `environment`, `config` or `default`;
* whether the measurement command resolves, and whether the transport client
  resolves;
* whether the recipient or the endpoint is set, and whether the values are
  valid;
* the header **count** and its source, never a header value;
* one line per problem, with the remedy, and one warning line per warning.

It exits `0` when the tool is ready to run and `1` when something is
missing. A missing dependency is named with the install command of the
platform the doctor was run on, not a generic suggestion. A measurement
command that came from the configuration file is different: it comes from no
package, so the remedy points at the setting instead of at an installer.

On this Linux host, with an isolated `HOME` and nothing configured, the
report is:

```
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
  - No recipient is configured. Set --to, or DISK_MONITOR_TO, or the 'to' key in the
    configuration file.
```

The `Platform` line names the distribution this run found; on Windows it
reads `Windows`, and on macOS `macOS`. The `Mail agent` and `Measurement
command` paths are this host's. The last line is wrapped here; the tool
prints it on one line.

Colour escape sequences are omitted from the captured output in this wiki;
the tool always emits them.

---

## A worked example

Every example below runs from the module directory with an empty `HOME`
(`HOME=$(mktemp -d)`), so no configuration file of your own is found. The
usage is forced with `DISK_MONITOR_USAGE_OVERRIDE`, so the numbers in the
output are the numbers in the text; a measured run shows whatever your disk
is at.

A dry run with the default `mail` transport. Nothing is handed to the mail
agent:

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
HOME=$(mktemp -d) DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh -n --to ops@example.com -p / -t 80
```

```
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /usr/bin/mail
Recipient         : ops@example.com
Execution Mode    : DRY RUN (Simulation)
WARNING: Disk usage exceeds the threshold.
[DRY RUN] Would send an alert to ops@example.com
```

The exit code is `0`: the check completed, and the alert was deliberately
suppressed. The `Mail Agent` path is this host's; a host whose agent cannot
be resolved shows an error and exits `1` even in a dry run, because the
delivery path is validated before anything else happens.

The same check over the `http` transport swaps the mail lines for an endpoint
and a client:

```bash
HOME=$(mktemp -d) DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh -n --notify http --url https://ntfy.sh/disk-alerts -p / -t 80
```

```
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://ntfy.sh/disk-alerts
HTTP Client       : /usr/bin/curl
Execution Mode    : DRY RUN (Simulation)
WARNING: Disk usage exceeds the threshold.
[DRY RUN] Would send an alert to https://ntfy.sh/disk-alerts
```

### Seeing the composed alert without sending mail

Point `--mail-command` at a harmless program and the message becomes
visible:

```bash
S=$(mktemp -d)
printf '#!/bin/bash\necho "ARGV: $*"\ncat\n' > "$S/fake-mail"
chmod +x "$S/fake-mail"

HOME=$(mktemp -d) DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh \
  --to ops@example.com --mail-command "$S/fake-mail" -p / -t 80
```

```
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /tmp/tmp.rdV64FzrQb/fake-mail
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
ARGV: -s Disk Alert: / at 91% ops@example.com
Disk usage on cachy-os is at 91% (threshold: 80%).

Partition : /
Usage    : 91%
Threshold: 80%
Time     : 2026-10-22T17:49:56Z
Alert sent to ops@example.com
```

The path under `/tmp` is the scratch directory of that run, and the host
name and timestamp come from the machine — yours differ.

### Seeing the HTTP request without a network

The same trick works for the HTTP transport, because the client is just an
external command. A stub client prints its argument list and the body it
receives on standard input:

```bash
S=$(mktemp -d)
printf '#!/bin/sh\necho "ARGV: $*"\ncat\n' > "$S/fake-curl"
chmod +x "$S/fake-curl"

HOME=$(mktemp -d) DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh \
  --notify http --url https://ntfy.sh/disk \
  --http-command "$S/fake-curl" \
  --body-template '{"usage":"{usage}","topic":"disk"}' -p / -t 80
```

```
ARGV: --silent --show-error --fail --max-time 10 --request POST --data-binary @- https://ntfy.sh/disk
{"usage":"91%","topic":"disk"}
```

The argument list is the request contract, and the second line is the
rendered body. `{usage}` kept its percent sign, and the JSON braces survived
because only known placeholders are substituted.

### Reading the failures

```bash
./disk_monitor.sh -t 0 --to ops@example.com
echo "exit=$?"
```

```
Error: Threshold must be an integer between 1 and 100.
exit=1
```

```bash
./disk_monitor.sh -p /nope-not-here --notify none
echo "exit=$?"
```

```
Error: Partition '/nope-not-here' does not exist.
exit=1
```

The other two the transport adds:

```bash
./disk_monitor.sh --notify smtp
echo "exit=$?"

./disk_monitor.sh --notify http --to ops@example.com
echo "exit=$?"
```

```
Error: Notify backend must be 'none', 'mail' or 'http'.
exit=1
Error: No endpoint. Use --url, or set DISK_MONITOR_URL.
exit=1
```

---

## The audit log

`--log-file` appends one ISO-8601 line per run. Each record is wrapped here
to fit the page; the tool writes it on one line:

```
2026-10-22T17:50:19Z [INFO] [DRY RUN] Would send an alert to ops@example.com
(Usage: 91%, Source: overridden, Threshold: 80%)
```

The same run over the HTTP transport records the endpoint instead of the
recipient:

```
2026-10-22T17:50:19Z [INFO] [DRY RUN] Would send an alert to https://ntfy.sh/disk
(Usage: 91%, Source: overridden, Threshold: 80%)
```

The line records the usage, **where the number came from** (`measured` or
`overridden`) and the threshold it was compared against — the three facts
needed to reconstruct why the run behaved the way it did, months later. It
never records a header value.

---

## Deliberate non-goals

Recorded so they are decisions rather than omissions:

* one partition per invocation — a host with a busy data volume and a busy
  log volume runs the tool twice
* no `--json` or `--csv` output — the report is meant to be read by a human
  and by an exit code, not parsed
* no SMTP transport — it needs an account, a domain and a credential
  lifecycle in every module, and a header on a free HTTP endpoint covers the
  same need
* no local webhook library — the HTTP transport invokes `curl` as a command,
  so it depends on nothing that a stock Linux or Windows host lacks
* no container image and no Python implementation — the module has to be
  convertible seven more times, and a template carrying a container stage is
  one nobody converts seven times

---

## Where to go next

* [14. Bash vs PowerShell](14-Disk-Monitor-Bash-vs-PowerShell.md)
* [15. Scenarios & Interactive Labs](15-Disk-Monitor-Scenarios-and-Labs.md)
* [05. Log Cleanup Overview](05-Log-Cleanup-Overview.md)
* [09. Code Style & Engineering Standards](09-Code-Style-and-Standards.md)

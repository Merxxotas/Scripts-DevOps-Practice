# Disk Usage Monitor (Email Alert) 💾

[![CI Disk Monitor](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-disk-monitor.yml/badge.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-disk-monitor.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.0%2B-5391FE?logo=powershell&logoColor=white)](https://microsoft.com/powershell)

A zero-dependency disk usage monitor that **measures one filesystem** and **hands an alert to a
transport** when the usage crosses a threshold. The transport is the host's mail agent or any
HTTP endpoint: ntfy, Telegram, Discord, Slack, a self-hosted receiver, or the one you write.
The module opens no socket of its own — the HTTP transport calls an external client — and it
stores no credential of its own; a header the caller supplies may carry one.

Available in **POSIX Bash** for Linux / macOS and **PowerShell** for Windows and cross-platform
hosts, with 100% feature parity: the same flags, the same defaults, the same validation, the
same exit codes and the same report fields.

---

## 🚀 Key Features

- 📊 **Portable measurement** — `df -P` on Linux and macOS, the native volume API on Windows.
  The capacity is read from its **fixed position** in the POSIX layout, so a mount point with
  spaces cannot shift it and the column layout never depends on the host.
- 🚨 **Threshold alerting** — the alert fires when usage is **strictly greater** than the
  threshold. Usage *equal* to the threshold stays quiet.
- 🌐 **One HTTP transport, every provider** — `--notify http` posts the alert to a URL. ntfy,
  Telegram, Discord, Slack and a self-hosted receiver are all the same primitive, so there is
  no provider-specific code and adding a provider never means editing the module.
- 📬 **Credential-free by default** — the mail transport hands the alert to the agent the host
  already provides. No secret in the repository, no socket of its own, no SMTP lifecycle.
- 🗂️ **Configuration file** — 13 keys in a `key = value` format that needs no parser library,
  for the settings that do not belong on a scheduled command line. A flag wins over an
  environment variable, which wins over the file, which wins over the built-in default.
- 🩺 **Doctor** — `--doctor` reports what is configured, where each value came from, and what
  is missing. It measures nothing and sends nothing, so it is safe to run first on a new host.
- 🧪 **Two suppression guardrails** — `--dry-run` rehearses the pending alert without sending
  anything; `--notify none` turns the alerting off entirely and needs neither a recipient nor a
  mail agent.
- 🧾 **Audit log** — one ISO-8601 UTC line per run, appended to the file you choose.
- 🚦 **Exit codes as a contract** — `0` success, `1` configuration or safety error, `2` partial
  failure. A scheduler can react to them.
- ⚖️ **Full parity** — both implementations expose the same options, and the Bash suite asserts
  277 behaviours against the same public interface the PowerShell suite mirrors.

---

## 📂 Directory Structure

```
1-Disk-Usage-Monitoring-with-Email-Alert/
├── disk_monitor.sh                  # POSIX Bash implementation (Linux / macOS)
├── disk_monitor.ps1                 # PowerShell implementation (Windows / cross-platform)
├── PSScriptAnalyzerSettings.psd1    # Analyzer settings for the CI lint gate
├── README.md                        # This document
├── SPECS.md                         # Technical specification & architecture
├── ROADMAP.md                       # Phased milestones
├── CODESTYLE.md                     # Coding conventions
├── tests/                           # Automated suites (277 assertions on the Bash side)
│   ├── test_disk_monitor.sh
│   └── test_disk_monitor.ps1
└── docs/                            # In-depth guides & interactive labs
    ├── ARCHITECTURE_COMPARISON.md
    ├── SCENARIOS.md
    └── labs/
        ├── LAB1_THRESHOLD_AND_DRY_RUN.md
        ├── LAB2_EXIT_CODES_AND_AUDIT_LOG.md
        └── LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md
```

---

## ⚡ Quick Start

### Linux / macOS (Bash)

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
chmod +x disk_monitor.sh

# Measure only: no recipient, no mail agent, nothing can be sent
./disk_monitor.sh -p / -t 80 --notify none
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 49% (measured)
Threshold         : 80%
Mail Agent        : (not resolved: notification disabled)
Execution Mode    : LIVE (Alerts Active)
Disk usage is within the threshold.
```

To post the same alert to an HTTP endpoint instead, change the transport:

```bash
./disk_monitor.sh --notify http --url https://ntfy.sh/disk-alerts
```

### Windows (PowerShell)

```powershell
.\disk_monitor.ps1 -Partition C:\ -Threshold 80 -Notify none
.\disk_monitor.ps1 -Notify http -Url https://ntfy.sh/disk-alerts
```

Both implementations accept the same sixteen options. The full reference is below.

---

## 📋 Command-Line Reference

| Bash flag | PowerShell parameter | Argument | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-p <path>` | `-Partition <string>` | Path | `/` on Unix, the system drive on Windows | Mount point to watch. |
| `-t <percent>` | `-Threshold <string>` | Integer | `80` | Alert when usage is **strictly greater**. Range `1`–`100`. |
| `-n` | `-DryRun` | Switch | off | Report the alert, hand nothing to the transport. |
| `--notify <name>` | `-Notify <string>` | String | `mail` | Transport: `none`, `mail` or `http`. Any other value exits `1`. |
| `--to <address>` | `-To <string>` | Address | `$DISK_MONITOR_TO` | Recipient of the alert, used by the mail transport. |
| `--mail-command <cmd>` | `-MailCommand <string>` | Path or name | platform default | Mail agent to hand the alert to. |
| `--url <url>` | `-Url <string>` | URL | `$DISK_MONITOR_URL` | HTTP endpoint. Required when `--notify http`. |
| `--body-template <text>` | `-BodyTemplate <string>` | Template | the plain-text message | HTTP request body. |
| `--header 'Name: value'` | `-Header <string[]>` | Header | none | Extra HTTP header. Repeatable, and one value may carry several, one per line. |
| `--timeout <seconds>` | `-Timeout <string>` | Integer | `10` | HTTP timeout. A whole number of seconds above zero. |
| `--http-command <cmd>` | `-HttpCommand <string>` | Path or name | `curl` | HTTP client to send the request with. |
| `-l <file>` | `-LogFile <string>` | Path | none | Append an ISO-8601 audit line per run. |
| `--config <file>` | `-Config <string>` | Path | resolution chain | Configuration file to read. |
| `--doctor` | `-Doctor` | Switch | — | Report what is configured and what is missing. |
| `-v` | `-Verbose` | Switch | off | Diagnostic output. |
| `-h` | `-Help` | Switch | — | Usage, exit codes and examples. |

There is **no** `--method` flag on either side. The request method is a configuration key,
`method`, and it defaults to `POST`.

The full help text is available on both sides:

```bash
./disk_monitor.sh --help
```

```text
Disk Usage Monitor (Bash)
Usage: ./disk_monitor.sh [OPTIONS]

Optional Arguments:
  -p, --partition <path>    Mount point to watch (default: /).
  -t, --threshold <percent> Alert when usage is strictly greater (default: 80).
  -n, --dry-run             Report the alert without handing it to the mail agent.
      --notify <none|mail|http>
                             Notification backend (default: mail).
      --to <address>        Alert recipient (default: $DISK_MONITOR_TO).
      --mail-command <cmd>  Mail agent to hand the alert to.
      --url <url>           HTTP endpoint to post the alert to.
      --body-template <text>
                             HTTP request body (default: the plain-text message).
      --header 'Name: value'
                             Extra HTTP header. One value may carry several
                             headers, one per line, and the flag may be
                             repeated.
      --timeout <seconds>   HTTP request timeout in seconds (default: 10).
      --http-command <cmd>  HTTP client to send the request with (default: curl).
  -l, --log-file <file>     Path to append ISO-8601 audit records.
      --config <file>       Configuration file to read (default: ./.diskmonitor.conf).
      --doctor              Report what is configured and what is missing.
  -v, --verbose             Enable diagnostic output.
  -h, --help                Show this help and usage documentation.

Configuration:
  A flag wins over an environment variable, which wins over the
  configuration file, which wins over the built-in default. The environment
  variables are DISK_MONITOR_PARTITION, DISK_MONITOR_THRESHOLD,
  DISK_MONITOR_NOTIFY, DISK_MONITOR_TO, DISK_MONITOR_MAIL_COMMAND,
  DISK_MONITOR_LOG_FILE, DISK_MONITOR_USAGE_COMMAND,
  DISK_MONITOR_USAGE_OVERRIDE, DISK_MONITOR_CONFIG, DISK_MONITOR_URL,
  DISK_MONITOR_BODY_TEMPLATE, DISK_MONITOR_HEADER, DISK_MONITOR_TIMEOUT and
  DISK_MONITOR_HTTP_COMMAND.

HTTP transport:
  One transport covers every HTTP notification service, because a request
  with a body to a URL is the same primitive everywhere. The body template
  supports {subject}, {body}, {partition}, {usage}, {threshold},
  {recipient}, {host} and {timestamp}; a JSON template therefore speaks to
  Telegram, Discord and Slack without provider-specific code. {recipient} is
  the endpoint the alert is addressed to, and {usage} and {threshold} carry
  the percent sign. The rendered body is written to the client's standard
  input, followed by a newline. A header value is never printed and never
  written to the audit log, because it may carry a token.

Doctor:
  --doctor reports the resolved configuration and where each value came
  from, whether the measurement command and the transport client can be
  resolved, and whether the recipient or the endpoint is set. It measures
  nothing and sends nothing. It exits 0 when the tool is ready to run and 1
  when something is missing, with one line per problem and the remedy for
  it. A missing dependency is named with the install command of the platform
  the tool was found on.

Exit Codes:
  0  The check completed; the alert was delivered, not needed, or suppressed.
  1  Configuration or safety error (bad flag, threshold, partition, recipient,
     mail agent, endpoint, timeout, method, header or HTTP client).
  2  Partial failure (the usage could not be read, or the alert could not be
     handed to the mail agent or the HTTP client).

Examples:
  ./disk_monitor.sh -p / -t 80 --to ops@example.com
  ./disk_monitor.sh -p /home -t 90 -n -v
  ./disk_monitor.sh --notify http --url https://ntfy.sh/disk-alerts
  ./disk_monitor.sh --doctor
```

The PowerShell equivalent is `Get-Help .\disk_monitor.ps1 -Full`.

---

## 🌱 Environment Contract

The same fourteen variables work on both implementations. They exist so a scheduled run carries
its own configuration and the command line cannot drift away from it.

| Variable | Purpose | Effect when unset |
| :--- | :--- | :--- |
| `DISK_MONITOR_PARTITION` | Mount point to watch | `/` on Unix; the root of the current drive on Windows |
| `DISK_MONITOR_THRESHOLD` | The alert threshold, `1`–`100` | `80` |
| `DISK_MONITOR_NOTIFY` | Transport: `none`, `mail` or `http` | `mail` |
| `DISK_MONITOR_TO` | Recipient of the alert | The recipient must come from `--to` / `-To` or the `to` key, or a `mail` run exits `1` |
| `DISK_MONITOR_MAIL_COMMAND` | Mail agent to hand the alert to | The candidate list is used: `mail`, then `msmtp` |
| `DISK_MONITOR_LOG_FILE` | Audit log path | No audit line is written |
| `DISK_MONITOR_USAGE_COMMAND` | The measurement command | `df` on Unix; the Windows volume API on Windows |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage, `0`–`100` | The disk is measured for real |
| `DISK_MONITOR_CONFIG` | Configuration file to read | `./.diskmonitor.conf`, then `~/.config/disk-monitor/config` |
| `DISK_MONITOR_URL` | HTTP endpoint | `--url` / `-Url` or the `url` key must supply it, or an `http` run exits `1` |
| `DISK_MONITOR_BODY_TEMPLATE` | HTTP request body template | The plain-text message is sent |
| `DISK_MONITOR_HEADER` | One extra HTTP header, `Name: value` | No extra header is sent |
| `DISK_MONITOR_TIMEOUT` | HTTP timeout in seconds | `10` |
| `DISK_MONITOR_HTTP_COMMAND` | HTTP client | `curl` |

Precedence is fixed, and the same for every setting:

```text
command-line flag  ->  environment variable  ->  configuration file  ->  built-in default
```

```text
recipient  :  --to / -To  ->  DISK_MONITOR_TO  ->  the 'to' key  ->  (none)
mail agent :  --mail-command / -MailCommand  ->  DISK_MONITOR_MAIL_COMMAND
              ->  the 'mail_command' key  ->  mail  ->  msmtp
endpoint   :  --url / -Url  ->  DISK_MONITOR_URL  ->  the 'url' key  ->  (none)
```

> `DISK_MONITOR_USAGE_OVERRIDE` is a **rehearsal device**, not a production setting. A forced
> value is labelled `(overridden)` in the report and `Source: overridden` in the audit log, so
> it can never be mistaken for a measurement. Never set it in a scheduled job — it would blind
> the monitor.

---

## 🗂️ Configuration File

A scheduled command line long enough to carry a transport stops being readable, and a token does
not belong in a crontab. The configuration file holds those settings instead. Both
implementations read the **same** file, in a `key = value` format that needs no parser library:
a minimal Linux image has no `jq` and no TOML library, and Windows PowerShell has no TOML
parser.

```ini
# .diskmonitor.conf — ignored by git, and worth chmod 600
partition = /
threshold = 85
notify = http
url = https://ntfy.sh/your-topic
body_template = {body}
header = Authorization: Bearer your-token
```

A line whose first non-space character is `#` is a comment, the first `=` separates the key from
the value, and the spaces around either are trimmed. A value may be quoted to protect its spaces.
A line that cannot be parsed is reported by its **number** and ignored — the line itself is never
echoed, because a line pasted into the file by mistake may hold a token. An unknown key is
reported by name, and ignored. Both are warnings: the run continues.

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
| `header` | One extra HTTP header. Repeat the key for several. | none |

`method` is the only setting with no flag and no environment variable: an HTTP method is a
transport detail, not something a cron line changes.

### Which file is read

```text
--config <file>  ->  DISK_MONITOR_CONFIG  ->  ./.diskmonitor.conf  ->  ~/.config/disk-monitor/config
```

The first candidate that applies is used. A file named by `--config` or `DISK_MONITOR_CONFIG`
must exist — a missing one exits `1` and is reported by the doctor. An absent default file is
not an error: the built-in defaults are used.

### Precedence and provenance

Every setting is resolved through the same four levels:

```text
command-line flag  ->  environment variable  ->  configuration file  ->  built-in default
```

The resolved value carries the level it came from, and `--doctor` prints it. The same command
line, environment and file therefore produce the same report on both implementations.

> **The file may hold a secret.** `.diskmonitor.conf` is listed in the repository's
> `.gitignore`, and the doctor warns when a file other users can read is selected. Keep it at
> `chmod 600`. Its contents are never copied into the audit log.

---

## 🌐 HTTP Transport

`--notify http` hands the alert to an HTTP endpoint instead of the mail agent. One transport
covers **every** HTTP notification service, because ntfy, Telegram, Discord, Slack and a
self-hosted receiver are all the same primitive: a request with a body to a URL. There is no
provider-specific code, so adding a provider never means editing the module. Nothing in the
transport needs a paid service: it calls an endpoint you already have, with a client the
operating system provides.

The request is made by an external client, resolved as a command:

```text
<http-command> --silent --show-error --fail --max-time <seconds> \
               --request <method> --header 'Name: value'... \
               --data-binary @- <url>        # the rendered body on standard input
```

The default is `curl`, and any replacement must accept that argument set — including `--fail`,
which is what turns an HTTP error status into a failed hand-off. A wrapper that rejects an unknown
option fails every HTTP alert with exit `2`, loudly rather than silently.

| Setting | Flag | Environment | Config key | Default |
| :--- | :--- | :--- | :--- | :--- |
| The endpoint | `--url <url>` | `DISK_MONITOR_URL` | `url` | none — required |
| The request body | `--body-template <text>` | `DISK_MONITOR_BODY_TEMPLATE` | `body_template` | the plain-text message |
| Extra headers | `--header 'Name: value'` | `DISK_MONITOR_HEADER` | `header` | none |
| The method | — | — | `method` | `POST` |
| The timeout | `--timeout <seconds>` | `DISK_MONITOR_TIMEOUT` | `timeout` | `10` |

`--header` is repeatable, and one value may carry several headers separated by line breaks. An
entry that does not match `Name: value` exits `1`.

### Body template placeholders

| Placeholder | Replaced with | Example |
| :--- | :--- | :--- |
| `{subject}` | The alert subject | `Disk Alert: / at 91%` |
| `{body}` | The whole plain-text alert | `Disk usage on web-01 is at 91% ...` |
| `{partition}` | The watched mount point | `/` |
| `{usage}` | The usage, with the percent sign | `91%` |
| `{threshold}` | The threshold, with the percent sign | `80%` |
| `{recipient}` | The address the alert is addressed to — here, the endpoint | `https://ntfy.sh/disk-alerts` |
| `{host}` | The host that ran the check | `web-01` |
| `{timestamp}` | ISO-8601 UTC | `2026-10-22T17:45:42Z` |

The template is rendered in a single pass: a substituted value is never scanned again, and an
unknown placeholder is copied verbatim, which is what keeps a JSON body's braces intact. The
rendered body is written to the client's standard input followed by a newline.

> **`{body}` spans six lines, and a JSON string cannot hold a raw line break.** A template such
> as `{"text":"{body}"}` therefore produces invalid JSON. Use the single-line placeholders
> inside a JSON body: `{"text":"{subject} on {host}"}` renders valid JSON.

### Which client is used

```text
--http-command <cmd>  ->  DISK_MONITOR_HTTP_COMMAND  ->  curl
```

The client is an external command, so the same client runs on every platform, and the test
suites replace it on `PATH` instead of opening a socket.

When the transport is `http`, the console report prints `Endpoint` and `HTTP Client` in place
of `Mail Agent` and `Recipient`, and the audit line records the endpoint instead of the
recipient. With `-v` / `-Verbose`, a `Transport` line names the source of the endpoint, the
template, the method, the timeout and the client, and gives the header count — never a header
value.

> **Windows:** the client is `curl.exe`, which ships with Windows 10 and later. The resolver
> searches `curl`, then `curl.exe`, and accepts only an **application** — never a command alias.
> Windows PowerShell 5.1 maps `curl` to the `Invoke-WebRequest` alias, so the distinction is what
> keeps the real client in the path. The implementation declares `#Requires -Version 7.0` and
> branches on `$IsWindows`, a variable that only PowerShell 6 and later define, so Windows
> PowerShell 5.1 is not a supported host.

### Worked examples

Each example below takes the same code path; only the URL, the headers and the template change.
Add `DISK_MONITOR_USAGE_OVERRIDE=91` to rehearse one without a full disk, or `--dry-run` to see
the pending alert without calling the client at all.

**ntfy** — plain-text body, and the `Title` header sets the notification title:

```bash
./disk_monitor.sh --notify http \
    --url 'https://ntfy.sh/disk-alerts' \
    --header 'Title: Disk alert' \
    --body-template '{body}'
```

Use an unguessable topic name. A protected topic takes
`header = Authorization: Bearer <token>` in the configuration file.

**Telegram** — the bot token and the chat id stay out of the command line:

```bash
export TELEGRAM_BOT_TOKEN='123456789:replace-me'
export TELEGRAM_CHAT_ID='replace-me'

./disk_monitor.sh --notify http \
    --url "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --header 'Content-Type: application/json' \
    --body-template "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"{subject} on {host}\"}"
```

**Discord** — a webhook URL takes a `content` field:

```bash
export DISCORD_WEBHOOK='https://discord.com/api/webhooks/replace-me/replace-me'

./disk_monitor.sh --notify http \
    --url "$DISCORD_WEBHOOK" \
    --header 'Content-Type: application/json' \
    --body-template '{"content":"{subject} on {host}"}'
```

**Slack** — an incoming webhook takes a `text` field:

```bash
export SLACK_WEBHOOK='https://hooks.slack.com/services/replace-me/replace-me/replace-me'

./disk_monitor.sh --notify http \
    --url "$SLACK_WEBHOOK" \
    --header 'Content-Type: application/json' \
    --body-template '{"text":"{subject} on {host}"}'
```

**A self-hosted receiver** — plain text, and two headers:

```bash
./disk_monitor.sh --notify http \
    --url 'http://127.0.0.1:8080/alert' \
    --header 'Content-Type: text/plain' \
    --header 'X-Alert-Source: disk-monitor' \
    --body-template '{body}'
```

> **A token takes two shapes, and only one of them is quiet.** A header value is never printed,
> never reported and never written to the audit log; the doctor reports how many headers are set
> and where they came from, never their values. A token embedded in the **URL** is printed in
> the report and written to the audit line by the `ALERT SENT to <endpoint>` record — which is
> unavoidable for an API like Telegram's, where the token is part of the path. Prefer a header
> when the provider offers one, and treat an endpoint that carries a token as a secret.

---

## 🩺 The Doctor

`--doctor` reports what is configured, where each value came from, and what is missing. It
measures nothing and sends nothing, so it is the first command to run on a new host.

```bash
./disk_monitor.sh --doctor
```

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

That report was produced on a Linux host with an isolated `HOME` and nothing configured. The
frame is colourised at a terminal; the text is what a pipe or a log receives.

| Marker | Meaning |
| :--- | :--- |
| `(default)` | The built-in default is in effect |
| `(flag)` | A command-line flag supplied the value |
| `(environment)` | A `DISK_MONITOR_*` variable supplied the value |
| `(config)` | The configuration file supplied the value |
| `(not required)` | The active transport does not use this setting |
| `(none found)` / `(not found: <path>)` | No default file exists / the selected file does not exist — the latter is a problem |
| `(cannot be read: <path>)` | The selected file exists but this account cannot read it — a problem |

The exit code answers one question — can this tool do its job?

| Code | Meaning |
| :--: | :--- |
| `0` | **Ready.** Every setting the active transport needs is resolvable. |
| `1` | **Not ready.** Something is missing, and every problem is listed with a one-line remedy. |

A ready host prints `Status              : READY` and exits `0`; the frame and the field list are
the same. The remedy names the install command of the platform the tool was found on, not a
generic suggestion. A configuration file that other users can read is reported as a **warning**
with its remedy and does **not** change the exit code: the tool still runs, and a freshly created
file is readable by others until it is restricted. The remedy is a command you can paste, with the
path quoted the way the shell of that platform reads it, including a path that holds a quote. A
file whose permission bits the doctor cannot read at all is reported with the same warning and the
same remedy: the tool cannot tell whether it is safe, so it treats it as unsafe. A file that exists
but cannot be read is a **problem** and exits `1`: without it the run would fall
back to the defaults, and the doctor is where the permission of the file is named.

---

## 🧪 Worked Examples

Every example below is safe to run: it either disables the alerting, rehearses it, or points
the mail agent at a harmless stand-in.

### 1. Measure only

```bash
./disk_monitor.sh -p / -t 80 --notify none
```

```text
Partition         : /
Usage             : 49% (measured)
Threshold         : 80%
Mail Agent        : (not resolved: notification disabled)
Execution Mode    : LIVE (Alerts Active)
Disk usage is within the threshold.
```

Exit code `0`. With `--notify none` the module does not even look for a mail agent.

### 2. Rehearse the alert without sending it

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 -n --to ops@example.com
```

```text
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /usr/bin/mail
Recipient         : ops@example.com
Execution Mode    : DRY RUN (Simulation)
WARNING: Disk usage exceeds the threshold.
[DRY RUN] Would send an alert to ops@example.com
```

Exit code `0`, and **nothing was sent**. The mail agent and the recipient are still resolved,
because validation always runs first — that is what makes a dry run a genuine rehearsal of the
production path.

### 3. See the composed alert without sending it

Build a stand-in that records the hand-off and delivers nothing:

```bash
mkdir -p /tmp/disk-monitor-demo
cat > /tmp/disk-monitor-demo/fake-mail-agent.sh <<'EOF'
#!/bin/bash
# A harmless stand-in for the host mail agent: it records the hand-off and
# delivers nothing, so the example can never send a real email.
printf 'ARGV      : %s\n' "$*"
printf '%s\n' '--- body received on stdin ---'
cat
EOF
chmod +x /tmp/disk-monitor-demo/fake-mail-agent.sh
```

Then run the alert path against it:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 --to ops@example.com \
    --mail-command /tmp/disk-monitor-demo/fake-mail-agent.sh
```

```text
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /tmp/disk-monitor-demo/fake-mail-agent.sh
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
ARGV      : -s Disk Alert: / at 91% ops@example.com
--- body received on stdin ---
Disk usage on web-01 is at 91% (threshold: 80%).

Partition : /
Usage    : 91%
Threshold: 80%
Time     : 2026-10-21T16:53:18Z
Alert sent to ops@example.com
```

Exit code `0`. That is the whole mail contract in one line:

```text
<mail-command> -s <subject> <recipient>      # the body arrives on stdin
```

> The host name in the body is the name of the machine the monitor ran on; it is shown here as
> a placeholder.

### 4. Record an audit trail

```bash
./disk_monitor.sh -p / -t 80 --notify none -l /tmp/disk-monitor-demo/audit.log
cat /tmp/disk-monitor-demo/audit.log
```

```text
2026-10-21T16:53:20Z [INFO] Usage within threshold (Usage: 49%, Source: measured, Threshold: 80%)
```

One ISO-8601 UTC line per run. The timestamp is UTC so lines from several hosts interleave into
one readable timeline.

### 5. Diagnose a configuration error

```bash
./disk_monitor.sh -t 101 --to ops@example.com
echo "exit=$?"
```

```text
Error: Threshold must be an integer between 1 and 100.
exit=1
```

The configuration is validated **before** the disk is measured, so a broken alerting path is
reported immediately rather than when an alert is needed.

---

## 🚦 Exit Codes

| Exit Code | Status | Meaning |
| :---: | :--- | :--- |
| `0` | **Success** | The check ran; the alert was delivered, not needed, or deliberately suppressed. |
| `1` | **Configuration Error** | Unknown flag; bad threshold, partition, transport, recipient, endpoint, timeout, method, header, mail agent, HTTP client or measurement command; unreadable configuration file, or a configuration value that fails validation. |
| `2` | **Partial Failure** | The usage could not be read, or the alert could not be handed to the mail agent or the HTTP client. |

> **Crossing the threshold is not a failure.** The run that detects a full disk exits `0` —
> the alert is the product, not an error. A `1` says the deployment is broken and will stay
> broken; a `2` says the measurement or the delivery failed right now and may succeed on the
> next run.

> **`--doctor` reuses `0` and `1` as a readiness answer**, not as the result of a run: `0` means
> ready, `1` means something is missing. It never returns `2`, because it measures nothing and
> sends nothing.

---

## ⏰ Production Scheduling

### Linux (cron)

`/etc/cron.d/disk-monitor`:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DISK_MONITOR_TO=ops@example.com
DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp

17 7 * * * root /usr/local/bin/disk-monitor -p / -t 80 -l /var/log/disk-monitor/audit.log
```

Four decisions in that entry, each of them load-bearing:

| Decision | Why |
| :--- | :--- |
| `PATH=` is set explicitly | `cron` starts with a minimal `PATH`. Without it, `df` and `msmtp` may not be found. |
| `DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp` | An **absolute path**. Many minimal images ship a `mail` binary with no MTA behind it; pinning the agent removes the guesswork. |
| `DISK_MONITOR_TO=ops@example.com` | The recipient lives in the environment, so the command line and the address cannot drift apart. |
| `-l /var/log/disk-monitor/audit.log` | Cron **ignores the exit code**. The audit log is the durable channel. |

Rehearse the exact cron command line before it goes live — append `--notify none` so nothing
can be sent:

```bash
DISK_MONITOR_TO=ops@example.com DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp \
    ./disk_monitor.sh -p / -t 80 -l /tmp/disk-monitor-demo/audit.log --notify none
```

```text
Partition         : /
Usage             : 49% (measured)
Threshold         : 80%
Mail Agent        : (not resolved: notification disabled)
Execution Mode    : LIVE (Alerts Active)
Audit Log File    : /tmp/disk-monitor-demo/audit.log
Disk usage is within the threshold.
```

Exit code `0`.

The same entry carries the HTTP transport. Keep the endpoint and any token in the configuration
file, so neither appears in the crontab, and let the cron line name only what changes per host:

```cron
17 7 * * * root /usr/local/bin/disk-monitor --config /etc/disk-monitor/config.conf -l /var/log/disk-monitor/audit.log
```

That file holds a secret if it carries a header, so keep it at `chmod 600`; `--doctor` reports
one that other users can read.

### Linux (systemd timer)

`/etc/systemd/system/disk-monitor.service`:

```ini
[Unit]
Description=Disk usage monitor for the root filesystem

[Service]
Type=oneshot
Environment=DISK_MONITOR_TO=ops@example.com
Environment=DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp
ExecStart=/usr/local/bin/disk-monitor -p / -t 80 -l /var/log/disk-monitor/audit.log
```

`/etc/systemd/system/disk-monitor.timer`:

```ini
[Unit]
Description=Run the disk usage monitor every hour

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

A systemd timer is stricter than cron and more useful here: it **does** act on a non-zero exit
code, through `OnFailure=`. In the failure handler systemd exposes `$EXIT_STATUS` and
`$SERVICE_RESULT`, so the handler can distinguish the three cases exactly: `0` needs no
action, `1` should page the operator, `2` should be recorded and retried.

Enable it on the target host with `systemctl daemon-reload` followed by
`systemctl enable --now disk-monitor.timer`.

### Windows (Task Scheduler)

Register a daily task from an elevated PowerShell prompt on the Windows host:

```powershell
$Argument = "-NoProfile -File C:\Ops\disk_monitor.ps1 -Partition C:\ -Threshold 80 " +
    "-LogFile C:\Ops\disk-monitor.log"
$Action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument $Argument
$Trigger = New-ScheduledTaskTrigger -Daily -At 7am
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "DiskMonitor" `
    -Description "Alerts when a volume crosses its threshold"
```

Set `DISK_MONITOR_TO` and `DISK_MONITOR_MAIL_COMMAND` in the task's environment, or pass
`-To` and `-MailCommand` in `$Argument`.

> **The audit log must live on a different volume than the one you watch.** On a genuinely full
> disk the audit line may be the thing that cannot be written.

---

## 🔧 Troubleshooting

| Symptom | Likely cause | What to check |
| :--- | :--- | :--- |
| `Error: No recipient. Use --to, or set DISK_MONITOR_TO.` | The recipient is unset. | Set `DISK_MONITOR_TO`, or pass `--to` / `-To`. |
| `Error: No mail agent found. Install one, or set --mail-command or DISK_MONITOR_MAIL_COMMAND.` | No mail agent is on `PATH`. | `command -v mail`; `command -v msmtp`; set `DISK_MONITOR_MAIL_COMMAND` to an absolute path. |
| `Error: Partition '/x' does not exist.` | The mount point is wrong or is not mounted. | `df -P /x`; the module checks the path before it measures. |
| `Error: Threshold must be an integer between 1 and 100.` | The threshold is out of range or not a number. | `-t` takes `1`–`100`. |
| `Error: Could not read the disk usage of '/'.` | The measurement command resolved but failed. | The exit code is `2`, not `1`; the configuration is fine and the measurement is not. |
| `Error: The alert could not be handed to the mail agent.` | The mail agent exists but refused the message. | Usually no MTA behind the `mail` binary. Exit code `2`. |
| `Error: No endpoint. Use --url, or set DISK_MONITOR_URL.` | `--notify http` was selected with nothing configured. | Pass `--url`, set `DISK_MONITOR_URL`, or add `url` to the configuration file. |
| `Error: Endpoint '<x>' is not a valid http or https URL.` | The endpoint is not an `http://` or `https://` URL. | A URL with a space in it fails the same check. Exit code `1`. |
| `Error: Timeout must be an integer of seconds greater than zero.` | `--timeout` is not a whole number, or is `0`. | `--timeout 15`, not `15s` and not `1.5`. |
| `Error: Header 1 is malformed. Expected 'Name: value'.` | A `--header` value has no colon, or starts with a space or a colon. | Quote the whole header: `--header 'Name: value'`. |
| `Error: HTTP method must be a token, for example POST.` | The `method` key holds something that is not an HTTP token. | Fix `method` in the configuration file, or remove it to use `POST`. |
| `Error: No HTTP client found. Install one, or set --http-command or DISK_MONITOR_HTTP_COMMAND.` | No client is on `PATH`. | `command -v curl`; on Windows `where.exe curl.exe`. |
| `Error: The alert could not be handed to the HTTP client.` | The client ran and failed — a refused connection, a DNS failure or a 4xx. | Exit code `2`; the check worked and the delivery did not. |
| `--doctor` prints `NOT READY` | Something the active transport needs is missing. | Read the remedy line under the status; each problem has its own. |
| A JSON endpoint rejects the request as malformed | The template embeds `{body}`, which spans six lines. | Use single-line placeholders: `{"text":"{subject} on {host}"}`. |
| A Windows run reports the wrong client | The name resolved to the `Invoke-WebRequest` alias. | The resolver asks for an application, so it reaches `curl.exe`; pass `-HttpCommand curl.exe` to pin it. |
| The alert never arrives | The relay rejected it or the provider quarantined it. | The mail agent's own log, and the provider's delivery log. |
| The cron job does not run at all | The file is not in `/etc/cron.d/`, or its name is wrong. | `ls -l /etc/cron.d/`; the file must be owned by root and not group- or world-writable. |
| `bad interpreter: /bin/bash^M` | The script carries CRLF line endings. | `file disk_monitor.sh` must not say `with CRLF line terminators`. |
| The audit log is missing a run | The run failed before the audit path was known — an unknown flag leaves no trace. | The error is on stderr, not in the log. |

> **A failing audit write never breaks the measurement.** The write is best-effort by design: a
> monitor that dies because its log directory is read-only is a monitor that stopped
> monitoring. The consequence is that the durable channel has to live somewhere that is *not*
> the filesystem being watched.

---

## 📚 Deep Dives, Labs & Wiki

| Document | What it covers |
| :--- | :--- |
| [`docs/ARCHITECTURE_COMPARISON.md`](docs/ARCHITECTURE_COMPARISON.md) | Where the two implementations must agree, where they legitimately differ, and why. |
| [`docs/SCENARIOS.md`](docs/SCENARIOS.md) | The seven operational failure modes and the exit code each one produces. |
| [`docs/labs/LAB1_THRESHOLD_AND_DRY_RUN.md`](docs/labs/LAB1_THRESHOLD_AND_DRY_RUN.md) | Measure, compare and rehearse — the threshold boundary, without sending anything. |
| [`docs/labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md`](docs/labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md) | Every `0`, every `1`, every `2`, end to end. |
| [`docs/labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md`](docs/labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md) | Deploy on a VPS with a transactional relay, cron entry and log rotation. |
| [`SPECS.md`](SPECS.md) | The technical specification: architecture, data shapes, guardrails. |
| [`wiki/13-Disk-Monitor-Overview.md`](../wiki/13-Disk-Monitor-Overview.md) | The wiki overview of the module. |
| [`wiki/14-Disk-Monitor-Bash-vs-PowerShell.md`](../wiki/14-Disk-Monitor-Bash-vs-PowerShell.md) | The wiki comparison of the two implementations. |
| [`wiki/15-Disk-Monitor-Scenarios-and-Labs.md`](../wiki/15-Disk-Monitor-Scenarios-and-Labs.md) | The wiki index of the scenarios and the labs. |

---

## 🧪 Running the Tests

```bash
bash 1-Disk-Usage-Monitoring-with-Email-Alert/tests/test_disk_monitor.sh
```

The Bash suite runs anywhere Bash does and reports **277 assertions, 0 failed**. The PowerShell
suite needs PowerShell 7 and runs in the module's CI pipeline on **Windows and Ubuntu**, because
the Windows-native volume API cannot be stubbed on `PATH` — the shared environment contract is
what makes the alert branch testable on both.

Both suites replace the measurement command, the mail agent and the HTTP client on `PATH`, so
neither touches the host's real disk layout and neither can send a real email or a real HTTP
request.

---

## 📜 License

This project is licensed under the [MIT License](../LICENSE).

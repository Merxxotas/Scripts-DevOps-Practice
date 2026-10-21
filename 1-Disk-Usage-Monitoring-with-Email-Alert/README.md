# Disk Usage Monitor (Email Alert) 💾

[![CI Disk Monitor](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-disk-monitor.yml/badge.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-disk-monitor.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.0%2B-5391FE?logo=powershell&logoColor=white)](https://microsoft.com/powershell)

A zero-dependency disk usage monitor that **measures one filesystem** and **hands an alert to
the host's mail agent** when the usage crosses a threshold. It holds no credentials and opens
no socket of its own.

Available in **POSIX Bash** for Linux / macOS and **PowerShell** for Windows and cross-platform
hosts, with 100% feature parity: the same flags, the same defaults, the same validation, the
same exit codes and the same messages.

---

## 🚀 Key Features

- 📊 **Portable measurement** — `df -P` on Linux and macOS, the native volume API on Windows.
  The capacity is read from its **fixed position** in the POSIX layout, so a mount point with
  spaces cannot shift it and the column layout never depends on the host.
- 🚨 **Threshold alerting** — the alert fires when usage is **strictly greater** than the
  threshold. Usage *equal* to the threshold stays quiet.
- 📬 **Credential-free** — the module composes the alert and hands it to the mail agent the
  host already provides. No secret in the repository, no socket of its own, no SMTP lifecycle.
- 🧪 **Two guardrails** — `--dry-run` rehearses the pending alert without sending anything;
  `--notify none` turns the alerting off entirely and needs neither a recipient nor a mail
  agent.
- 🧾 **Audit log** — one ISO-8601 UTC line per run, appended to the file you choose.
- 🚦 **Exit codes as a contract** — `0` success, `1` configuration or safety error, `2` partial
  failure. A scheduler can react to them.
- ⚖️ **Full parity** — the Bash suite and the PowerShell suite assert the same 55 behaviours
  against the same public interface.

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
├── tests/                           # Automated test suites (55 assertions each)
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

### Windows (PowerShell)

```powershell
.\disk_monitor.ps1 -Partition C:\ -Threshold 80 -Notify none
```

Both implementations accept the same nine options. The full reference is below.

---

## 📋 Command-Line Reference

| Bash flag | PowerShell parameter | Argument | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-p <path>` | `-Partition <string>` | Path | `/` on Unix, the system drive on Windows | Mount point to watch. |
| `-t <percent>` | `-Threshold <int>` | Integer | `80` | Alert when usage is **strictly greater**. Range `1`–`100`. |
| `-n` | `-DryRun` | Switch | off | Report the alert, hand nothing to the mail agent. |
| `--notify <none\|mail>` | `-Notify <string>` | String | `mail` | Notification backend. `none` disables the hand-off entirely. |
| `--to <address>` | `-To <string>` | Address | `$DISK_MONITOR_TO` | Recipient of the alert. |
| `--mail-command <cmd>` | `-MailCommand <string>` | Path | platform default | Mail agent to hand the alert to. |
| `-l <file>` | `-LogFile <string>` | Path | none | Append an ISO-8601 audit line per run. |
| `-v` | `-Verbose` | Switch | off | Diagnostic output. |
| `-h` | `-Help` | Switch | — | Usage, exit codes and examples. |

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
      --notify <none|mail>  Notification backend (default: mail).
      --to <address>        Alert recipient (default: $DISK_MONITOR_TO).
      --mail-command <cmd>  Mail agent to hand the alert to.
  -l, --log-file <file>     Path to append ISO-8601 audit records.
  -v, --verbose             Enable diagnostic output.
  -h, --help                Show this help and usage documentation.

Exit Codes:
  0  The check completed; the alert was delivered, not needed, or suppressed.
  1  Configuration or safety error (bad flag, threshold, partition, recipient,
     or mail agent).
  2  Partial failure (the usage could not be read, or the alert could not be
     handed to the mail agent).
```

---

## 🌱 Environment Contract

The same four variables work on both implementations. They exist so a scheduled run carries
its own configuration and the command line cannot drift away from it.

| Variable | Purpose | Effect when unset |
| :--- | :--- | :--- |
| `DISK_MONITOR_TO` | Recipient of the alert | The recipient must come from `--to` / `-To`, or the run exits `1`. |
| `DISK_MONITOR_MAIL_COMMAND` | Mail agent to hand the alert to | The candidate list is used: `mail`, then `msmtp`. |
| `DISK_MONITOR_USAGE_COMMAND` | The measurement command | `df` on Unix; the Windows volume API on Windows. |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage, `0`–`100` | The disk is measured for real. |

Precedence is fixed:

```text
recipient  :  --to / -To  ->  DISK_MONITOR_TO
mail agent :  --mail-command / -MailCommand  ->  DISK_MONITOR_MAIL_COMMAND  ->  mail  ->  msmtp
```

> `DISK_MONITOR_USAGE_OVERRIDE` is a **rehearsal device**, not a production setting. A forced
> value is labelled `(overridden)` in the report and `Source: overridden` in the audit log, so
> it can never be mistaken for a measurement. Never set it in a scheduled job — it would blind
> the monitor.

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
| `1` | **Configuration Error** | Unknown flag, threshold outside `1`–`100`, unsupported notify backend, partition that does not exist, recipient unset, or an unresolvable mail agent or measurement command. |
| `2` | **Partial Failure** | The usage could not be read, or the alert could not be handed to the mail agent. |

> **Crossing the threshold is not a failure.** The run that detects a full disk exits `0` —
> the alert is the product, not an error. A `1` says the deployment is broken and will stay
> broken; a `2` says the measurement or the delivery failed right now and may succeed on the
> next run.

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

The Bash suite runs anywhere Bash does. The PowerShell suite needs PowerShell 7 and runs in the
module's CI pipeline on **Windows and Ubuntu**, because the Windows-native volume API cannot
be stubbed on `PATH` — the shared environment contract is what makes the alert branch testable
on both.

---

## 📜 License

This project is licensed under the [MIT License](../LICENSE).

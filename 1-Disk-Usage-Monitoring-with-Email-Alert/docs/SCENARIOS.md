# Disk Usage Monitor — Real-World Production Scenarios 🚀

A disk that fills at 03:00 takes the database with it. The Disk Usage Monitor exists to turn that
silent failure into an email you can act on. This document walks through the seven situations an
operator actually meets, and states the **exit code** each one produces, because that is what a
scheduler, a CI step or a wrapper script reacts to.

Every output below was captured from a real run of `disk_monitor.sh`. The commands are shown
exactly as they were executed, from the module folder.

---

## 📋 Table of Contents

1. [Scenario 1: The Disk Crosses the Threshold](#scenario-1-the-disk-crosses-the-threshold)
2. [Scenario 2: The Mail Agent Is Missing](#scenario-2-the-mail-agent-is-missing)
3. [Scenario 3: The Recipient Is Unset](#scenario-3-the-recipient-is-unset)
4. [Scenario 4: The Measurement Command Is Broken](#scenario-4-the-measurement-command-is-broken)
5. [Scenario 5: A Full Disk on a Host with No MTA](#scenario-5-a-full-disk-on-a-host-with-no-mta)
6. [Scenario 6: What a Cron Job Sees](#scenario-6-what-a-cron-job-sees)
7. [Scenario 7: What a Systemd Timer Would See](#scenario-7-what-a-systemd-timer-would-see)

---

## 📎 The Exit-Code Contract at a Glance

| Code | Meaning | Triggered by |
| :--: | :--- | :--- |
| `0` | Success | The check ran; the alert was delivered, not needed, or deliberately suppressed. |
| `1` | Configuration / safety error | Unknown flag, threshold outside 1–100, missing partition, unset recipient, unresolvable mail agent, unresolvable measurement command. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent. |

> **The threshold crossing itself is exit `0`.** The alert is the product, not an error. A monitor
> that returned non-zero every time it fired would be indistinguishable from a monitor that was
> broken.

---

## Scenario 1: The Disk Crosses the Threshold

### Problem

The root filesystem on an application server is over the threshold. The operator is asleep and does
not look at a dashboard until the morning.

### What the module does

It measures the filesystem, sees that the usage is above the threshold, composes the alert and
hands it to the mail agent. The hand-off is a command invocation, not a socket, so the module
itself never fails because of the network.

### Command

```bash
./disk_monitor.sh -p / -t 40 --to ops@example.com \
    --mail-command /tmp/lab1_disk/fake-mail-agent.sh
```

> Two deliberate choices. The threshold is **below** the real usage of this host (49 %), so the
> breach is real rather than simulated — on a production host the threshold would be 80 % and the
> disk would be the one that fills up. And the mail agent is a harmless stand-in, so the
> documentation run never sends an email. A production host would use `/usr/bin/mail` or
> `/usr/bin/msmtp` here.

### Observed behaviour

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 49% (measured)
Threshold         : 40%
Mail Agent        : /tmp/lab1_disk/fake-mail-agent.sh
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
ARGV      : -s Disk Alert: / at 49% ops@example.com
--- body received on stdin ---
Disk usage on cachy-os is at 49% (threshold: 40%).

Partition : /
Usage    : 49%
Threshold: 40%
Time     : 2026-10-21T16:36:04Z
Alert sent to ops@example.com
```

**Exit code: `0`.** The monitor is healthy; the disk is not.

### Operational note

The alert carries the partition, the percentage, the threshold and a UTC timestamp — enough for the
on-call engineer to act without opening a second tool. The matching audit line is:

```text
2026-10-21T16:41:07Z [INFO] ALERT SENT to ops@example.com (Usage: 49%, Source: measured, Threshold: 40%)
```

> The audit line records `Source: measured` because this run measured the disk for real. A run
> that used `DISK_MONITOR_USAGE_OVERRIDE` to force the percentage records `Source: overridden`
> instead — a forced value is never presented as a measured one.

---

## Scenario 2: The Mail Agent Is Missing

### Problem

The host was rebuilt from a minimal image. `mail` and `msmtp` are not installed, and
`DISK_MONITOR_MAIL_COMMAND` is not set. The monitor would have no way to deliver an alert.

### What the module does

It resolves the mail agent **before** measuring the disk, so the broken alerting path is reported
at deployment time instead of at 03:00 when the disk finally fills.

### Command

```bash
./disk_monitor.sh --mail-command /tmp/lab2_disk/not-a-real-agent --to ops@example.com
```

### Observed behaviour

```text
Error: No mail agent found. Install one, or set --mail-command or DISK_MONITOR_MAIL_COMMAND.
```

**Exit code: `1`** — a configuration error. Nothing was measured and nothing was sent.

### Remediation

Install a mail agent (`msmtp` is the natural choice; see
[Lab 3](labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md)), or point `DISK_MONITOR_MAIL_COMMAND` at
an agent that already exists. The resolution order is:

```text
--mail-command  →  DISK_MONITOR_MAIL_COMMAND  →  "mail"  →  "msmtp"
```

---

## Scenario 3: The Recipient Is Unset

### Problem

The cron entry was copied from a wiki page and the `--to` argument was lost in the edit. The
monitor now has a mail agent but nobody to send to.

### What the module does

It refuses to run rather than quietly delivering into a black hole. The error names the
environment variable, so the fix is one line.

### Command

```bash
./disk_monitor.sh --notify mail
```

### Observed behaviour

```text
Error: No recipient. Use --to, or set DISK_MONITOR_TO.
```

**Exit code: `1`** — a configuration error.

### Remediation

Set the recipient once, in the environment, so the flag and the value cannot drift apart:

```bash
export DISK_MONITOR_TO=ops@example.com
```

> **Escape hatch:** `--notify none` needs no recipient at all. It is the right mode for a host
> that only collects the measurement, and it is the mode that keeps the monitor running on a host
> with no mail agent at all.

---

## Scenario 4: The Measurement Command Is Broken

### Problem

`DISK_MONITOR_USAGE_COMMAND` points at a wrapper that was renamed, or at a `df` replacement that
fails on this filesystem. The monitor can no longer answer the only question it exists to answer.

There are **two distinct failures** here, and they produce **different exit codes**.

### 4a. The command cannot be resolved — exit `1`

```bash
DISK_MONITOR_USAGE_COMMAND=/tmp/lab2_disk/not-a-real-command \
    ./disk_monitor.sh -p / -t 80 --to ops@example.com
```

```text
Error: Measurement command '/tmp/lab2_disk/not-a-real-command' was not found.
```

**Exit code: `1`** — a configuration error. The tool cannot ever succeed with this setting.

### 4b. The command runs but fails — exit `2`

A command that resolves and then exits non-zero (a broken wrapper, a filesystem that `df` cannot
read, a `PATH` problem inside the wrapper):

```bash
DISK_MONITOR_USAGE_COMMAND=/tmp/lab2_disk/df-broken \
    ./disk_monitor.sh -p / -t 80 --to ops@example.com
```

```text
Error: Could not read the disk usage of '/'.
```

**Exit code: `2`** — a partial failure. The configuration was fine; the measurement was not.

### Why the distinction matters

`1` says *the deployment is wrong* and will stay wrong until someone edits a file. `2` says *the
measurement failed right now* and may succeed on the next run. A scheduler that pages on `1` and
merely records `2` is reacting to the right thing.

---

## Scenario 5: A Full Disk on a Host with No MTA

### Problem

The disk reaches 100 %. The host has no MTA — no `sendmail`, no `postfix`, no `exim`. The
`mail` binary may exist, but it has nothing to hand the message to.

### The diagnostic

```bash
command -v sendmail postfix exim4
ls -l /usr/sbin/sendmail
```

```text
ls: cannot access '/usr/sbin/sendmail': No such file or directory
```

`command -v` printed nothing: there is no local MTA. On such a host the `mail` client exists but
cannot deliver, so the hand-off fails.

### What the module does

The check succeeds, the alert is composed, and the hand-off fails. The monitor reports the failure
loudly rather than pretending the disk is fine.

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 49% (measured)
Threshold         : 40%
Mail Agent        : /tmp/lab2_disk/failing-mail-agent.sh
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
Error: The alert could not be handed to the mail agent.
```

> Two deliberate choices in that transcript. The threshold is `40` so the breach reproduces
> immediately on a host that is not actually full — on a production host the disk would be at
> 100 %. And the mail agent is a stand-in that always refuses the hand-off, because the
> documentation run must not deliver anything. On the real host the agent would be
> `/usr/bin/mail` — present, but with no `sendmail` behind it to talk to.

**Exit code: `2`** — the check worked, the delivery did not.

### The audit line

```text
2026-10-21T16:40:51Z [ERROR] FAILED to hand the alert to the mail agent (Usage: 49%, Source: measured)
```

### The hard truth about a 100 % disk

The audit log is a file on the same filesystem that just filled up. The write is **best-effort by
design** — a monitor that dies because its log directory is read-only is a monitor that stops
monitoring — so on a genuinely full disk the audit line may be the one thing that cannot be
written. The same failure mode, reproduced with a path that cannot be created:

```bash
./disk_monitor.sh -p / -t 80 --notify none -l /etc/disk-monitor/audit.log
```

```text
Audit Log File    : /etc/disk-monitor/audit.log
Disk usage is within the threshold.
./disk_monitor.sh: line 87: /etc/disk-monitor/audit.log: No such file or directory
```

**Exit code: `0`.** The measurement is never broken by a failing audit write. The consequence is
that the durable channel has to live somewhere that is *not* the filesystem being watched — a
second disk, a remote collector, or the syslog.

### Remediation

1. Free space. The monitor reports, it does not remediate.
2. Fix the delivery path: install `msmtp` and a relay
   ([Lab 3](labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md)), or point the audit log at a
   different filesystem.

---

## Scenario 6: What a Cron Job Sees

### Problem

The module runs from `cron` every night at 07:17. The operator needs to know what the scheduler
does with the exit code — and what it does **not** do.

### The cron entry

`/etc/cron.d/disk-monitor`:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DISK_MONITOR_TO=ops@example.com
DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp

17 7 * * * root /usr/local/bin/disk-monitor -p / -t 80 -l /var/log/disk-monitor/audit.log
```

### What cron actually does with the result

| Behaviour | Reality |
| :--- | :--- |
| **Exit code** | **Ignored.** Cron runs the job and moves on. A `2` does not page anyone. |
| **Exit status** | Recorded in syslog by the daemon: `CRON[1234]: (root) CMD (...) exited with status 2`. |
| **Standard output / error** | Mailed to `MAILTO` — or to the crontab owner when `MAILTO` is unset — when a MTA is installed; otherwise it lands in syslog. On a host with no MTA, **nobody sees it**. |
| **Audit log** | The only channel that survives on every host. |

### Consequences

- **Cron is not an alerting system.** The module's own mail hand-off is the alerting path; cron
  only starts it. Wiring the same mail agent into cron's `MAILTO` and into the module means two
  channels, not one.
- **A `2` exit code is invisible without syslog.** If the operator never reads syslog and the
  audit log is on the full disk, the failure is genuinely invisible. That is the argument for
  shipping the audit log to a second filesystem or to the syslog.
- **The cron environment is minimal.** `cron` has a tiny `PATH` and no profile, which is why the
  entry above sets `PATH` and the two `DISK_MONITOR_*` variables explicitly, and why
  `DISK_MONITOR_MAIL_COMMAND` is an **absolute** path.

### The exit code a wrapper can act on

To make a non-zero code mean something under cron, wrap the call:

```bash
/usr/local/bin/disk-monitor -p / -t 80 -l /var/log/disk-monitor/audit.log \
    || logger -t disk-monitor "monitor failed with exit code $?"
```

`logger` writes to syslog, which is the one channel that is always present.

---

## Scenario 7: What a Systemd Timer Would See

### Problem

The same job, but scheduled by `systemd` instead of cron. Systemd is stricter and more useful
here: it **does** act on a non-zero exit code, and it can hand the failure to another unit.

### The unit

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

### Acting on a failure

```ini
[Unit]
Description=Record a disk monitor failure
OnFailure=disk-monitor-failure@%n.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/record-monitor-failure %n
```

In the failure handler, systemd exposes the failed unit's status as `$EXIT_STATUS` (the numeric
exit code) and `$SERVICE_RESULT` (`exit-code`, `signal`, `timeout`, …). The handler can therefore
distinguish exactly the three cases this module defines:

| `$EXIT_STATUS` | Meaning | What the handler should do |
| :--: | :--- | :--- |
| `0` | The check ran. The alert was delivered, not needed, or suppressed. | Nothing. Note that a fired alert is still a `0`. |
| `1` | Configuration error. | Page: the deployment is broken and will stay broken. |
| `2` | Partial failure. | Record and retry: the measurement or the delivery failed right now. |

### Enabling it

```bash
systemctl daemon-reload
systemctl enable --now disk-monitor.timer
systemctl list-timers disk-monitor.timer
```

### Why a timer is often the better choice here

| Property | cron | systemd timer |
| :--- | :--- | :--- |
| Acts on a non-zero exit code | No | Yes, through `OnFailure=` |
| Environment control | Inline in the entry file | `Environment=` in the unit |
| Restart on transient failure | No | Yes — `Restart=on-failure` is allowed for `Type=oneshot`; `always` and `on-success` are not. |
| Log capture | syslog only | `journalctl -u disk-monitor` |
| Missed-run handling | No | `Persistent=true` catches up after a reboot |

---

## 📎 Related Documents

- [ARCHITECTURE_COMPARISON.md](ARCHITECTURE_COMPARISON.md) — where the two implementations agree and where they differ.
- [Lab 2 — Exit Codes & Audit Log](labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — reproduce every exit code in this document.
- [Lab 3 — Production Deployment on a VPS Relay](labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md) — cron plus a transactional relay on a real VPS.
- [`../README.md`](../README.md) — usage, flags and troubleshooting.

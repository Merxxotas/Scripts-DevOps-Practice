# 13. Disk Usage Monitor — Overview & Specs

> Module 1 of the [Scripts-DevOps-Practice](https://github.com/Merxxotas/Scripts-DevOps-Practice)
> monorepo: a threshold monitor that measures one filesystem and hands an
> alert to the host's mail agent when the filesystem crosses the threshold.

---

## What it is

A sensor, not an actuator. The module measures the usage of one mounted
filesystem and, when that usage passes a threshold, it hands an alert to the
mail agent the host already provides. It deletes nothing, rotates nothing and
restarts nothing.

| Concern | Value |
| :--- | :--- |
| Implementations | `disk_monitor.sh` (Bash) · `disk_monitor.ps1` (PowerShell 7) |
| Watched filesystems | one per invocation |
| Alert transport | a hand-off to the host's mail agent |
| Credentials held | **none** |
| Sockets opened | **none** |
| Runtime dependencies | `df` (Unix) or the Windows volume API · a mail agent |

Two properties are the reason the module was designed this way, and they are
worth stating before anything else:

* **The module holds no credentials.** It composes a message and hands it to
  another program. Whatever authentication the mail agent needs belongs to
  the mail agent's own configuration, and never enters this repository.
* **The module opens no socket of its own.** There is no SMTP conversation, no
  webhook call, no HTTP request. The only network traffic is the mail
  agent's.

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

Both implementations expose the same set, with the same defaults.

| Flag | Long form | PowerShell | Default | Meaning |
| :--- | :-- | :-- | :-- | :-- |
| `-p` | `--partition <path>` | `-Partition` | `/` (Unix) · the system drive (Windows) | Mount point to watch |
| `-t` | `--threshold <percent>` | `-Threshold` | `80` | Alert when usage is **strictly greater** |
| `-n` | `--dry-run` | `-DryRun` | off | Report the alert, hand nothing to the mail agent |
| — | `--notify <none\|mail>` | `-Notify` | `mail` | `none` disables the hand-off entirely |
| — | `--to <address>` | `-To` | `DISK_MONITOR_TO` | Recipient of the alert |
| — | `--mail-command <cmd>` | `-MailCommand` | platform default | The mail agent to hand the alert to |
| `-l` | `--log-file <file>` | `-LogFile` | none | Append an audit line per run |
| `-v` | `--verbose` | `-Verbose` | off | Diagnostic output |
| `-h` | `--help` | `-Help` | — | Usage and examples |

`--threshold` accepts `1`–`100` only. `--notify` accepts `none` or `mail`
only. An unknown flag is a configuration error.

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
| `0` | Success | The check ran, the threshold state was reported, and the alert was delivered, not needed, or deliberately suppressed. |
| `1` | Configuration / safety error | Unknown flag, threshold outside `1`–`100`, partition that does not exist, recipient unset, mail agent that cannot be resolved, or measurement command that cannot be resolved. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent. |

**Crossing the threshold is not a failure.** The tool did its job and
reported the condition, so it still exits `0`. The alert is the product, not
an error.

**A failed hand-off is `2`, not `1`.** The check worked; the delivery did
not. That distinction is what tells an operator reading a cron log whether
the measurement was broken or the mail path was.

---

## The environment contract

Identical on both sides. Every variable is optional, and the two deployment
knobs have a flag that overrides them.

| Variable | Effect | Overridden by |
| :--- | :--- | :-- |
| `DISK_MONITOR_TO` | The alert recipient. | `--to` / `-To` |
| `DISK_MONITOR_MAIL_COMMAND` | The mail agent to hand the alert to. | `--mail-command` / `-MailCommand` |
| `DISK_MONITOR_USAGE_COMMAND` | The command that measures the filesystem. | no flag |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage, labelled `overridden` in the report and in the audit log. | no flag |

The first two are the deployment knobs: the environment a scheduler runs
with, overridable per invocation. The last two are the **measurement
knobs** — they let the measurement be stubbed or forced, which is what makes
the test suite deterministic and what lets an operator rehearse an alert
without waiting for a disk to fill up. `DISK_MONITOR_USAGE_COMMAND` replaces
the `df` call on Unix, and on Windows it replaces the volume API query.

The environment is where a scheduler belongs. A cron entry does not need a
recipient repeated in a flag; the recipient lives in the host's service
environment, and the same script runs on the next host with a different
recipient.

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

## The notification hand-off

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

**The configuration is validated before the disk is measured.** The recipient
and the mail agent are resolved first, so a broken alerting path is reported
immediately, at the start of the run, rather than at the moment an alert is
actually needed. A monitor that only discovers it cannot send mail when the
disk fills up has failed exactly when it was needed.

---

## A worked example

A dry run against the real filesystem, with a threshold low enough that the
alert path fires. Nothing is handed to the mail agent:

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
./disk_monitor.sh -n --to ops@example.com -p / -t 40
```

```
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 49% (measured)
Threshold         : 40%
Mail Agent        : /usr/bin/mail
Recipient         : ops@example.com
Execution Mode    : DRY RUN (Simulation)
WARNING: Disk usage exceeds the threshold.
[DRY RUN] Would send an alert to ops@example.com
```

The exit code is `0`: the check completed, and the alert was deliberately
suppressed.

### Seeing the composed alert without sending mail

Point `--mail-command` at a harmless program and the message becomes
visible:

```bash
printf '#!/bin/bash\necho "ARGV: $*"\ncat\n' > /tmp/fake-mail
chmod +x /tmp/fake-mail

./disk_monitor.sh --to ops@example.com --mail-command /tmp/fake-mail -p / -t 40
```

```
ARGV: -s Disk Alert: / at 49% ops@example.com
Disk usage on web-01 is at 49% (threshold: 40%).

Partition : /
Usage    : 49%
Threshold: 40%
Time     : 2026-10-21T16:33:40Z
Alert sent to ops@example.com
```

The first line of the body names the host the measurement was taken on.

### Reading the failures

```bash
./disk_monitor.sh -t 0 --to ops@example.com
echo $?
```

```
Error: Threshold must be an integer between 1 and 100.
1
```

```bash
./disk_monitor.sh -p /nope-not-here --notify none
```

```
Error: Partition '/nope-not-here' does not exist.
```

---

## The audit log

`--log-file` appends one ISO-8601 line per run:

```
2026-10-21T16:33:40Z [INFO] [DRY RUN] Would send an alert to ops@example.com (Usage: 49%, Source: measured, Threshold: 40%)
```

The line records the usage, **where the number came from** (`measured` or
`overridden`) and the threshold it was compared against — the three facts
needed to reconstruct why the run behaved the way it did, months later.

---

## Deliberate non-goals

Recorded so they are decisions rather than omissions:

* one partition per invocation — a host with a busy data volume and a busy
  log volume runs the tool twice
* no `--json` or `--csv` output — the report is meant to be read by a human
  and by an exit code, not parsed
* no direct SMTP or webhook transport — a credential lifecycle in every
  module is a cost the module refuses to pay
* no container image and no Python implementation — the module has to be
  convertible seven more times, and a template carrying a container stage is
  one nobody converts seven times

---

## Where to go next

* [14. Bash vs PowerShell](14-Disk-Monitor-Bash-vs-PowerShell.md)
* [15. Scenarios & Interactive Labs](15-Disk-Monitor-Scenarios-and-Labs.md)
* [05. Log Cleanup Overview](05-Log-Cleanup-Overview.md)
* [09. Code Style & Engineering Standards](09-Code-Style-and-Standards.md)

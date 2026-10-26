# Lab 1: Threshold, Dry-Run & a Safe Rehearsal 🧪

## Objective

Learn the three things the monitor does, in the order it does them: **measure** the filesystem,
**compare** the result against the threshold, and **rehearse** the alert without sending it. Then
learn where the threshold comes from, because a flag, an environment variable, a configuration file
and a built-in default can all supply it, and only one of them wins.

By the end of this lab you will be able to read a disk report, explain the exact boundary at which
the alert fires, prove the alerting path is alive — and predict which of the four sources supplies
each setting.

---

## 📋 Prerequisites

- A Linux or macOS host with Bash 4+ (or a Windows host with PowerShell 7+).
- Execution permission on `disk_monitor.sh` (or `disk_monitor.ps1`).
- No mail account, no credentials, no MTA. **This lab never sends an email.**

> Run every command from the module folder:
> ```bash
> cd 1-Disk-Usage-Monitoring-with-Email-Alert
> ```

---

## Step 1: Read the Raw Measurement

The module reads the filesystem with `df -P`, the POSIX output format. Look at it first, so the
module's report is not a black box:

```bash
df -P /
```

```text
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p2   704130048 344148516 359007100      49% /
```

Six fields, one line per filesystem. The capacity is the field **immediately before** the mount
point — that is exactly what the module reads, as `$(NF-1)`. It is the only position that stays
correct on both GNU and macOS, and it survives a mount point that contains spaces.

Now let the module do the measuring. `--notify none` turns the alerting off entirely, so nothing
can be sent:

```bash
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

Two things to read here:

- **`49% (measured)`** — the number came from the filesystem. The word in brackets is the
  provenance of the number, and it is always there.
- **`(not resolved: notification disabled)`** — with `--notify none` the module does not even
  look for a mail agent. It needs neither a recipient nor a mail agent to measure.

---

## Step 2: The Threshold Comparison and Its Boundary

The alert fires when usage is **strictly greater** than the threshold. Usage *equal* to the
threshold does **not** alert. That boundary is a contract, so let us walk to it.

To drive a known number without touching the real disk, the module honours
`DISK_MONITOR_USAGE_OVERRIDE`. It is labelled `overridden` everywhere it appears — the report and
the audit log — so a forced value can never be mistaken for a measured one.

### Usage exactly at the threshold — no alert

```bash
DISK_MONITOR_USAGE_OVERRIDE=80 ./disk_monitor.sh -p / -t 80 --notify none
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 80% (overridden)
Threshold         : 80%
Mail Agent        : (not resolved: notification disabled)
Execution Mode    : LIVE (Alerts Active)
Disk usage is within the threshold.
```

### One point over the threshold — alert

```bash
DISK_MONITOR_USAGE_OVERRIDE=81 ./disk_monitor.sh -p / -t 80 --notify none
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 81% (overridden)
Threshold         : 80%
Mail Agent        : (not resolved: notification disabled)
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
Alert suppressed by --notify none.
```

`80 %` is quiet, `81 %` warns. The comparison is strictly greater, on both sides of the boundary.

> **The alert is not a failure.** Both runs exit `0`. The monitor did its job; the disk is the
> problem, not the tool. Exit code `2` would mean the *tool* broke, not the disk.

---

## Step 3: Rehearse the Alert Safely

`--dry-run` (or `-n`) reports the pending alert and hands **nothing** to the mail agent. Note
that the mail agent and the recipient are still resolved — validation always runs first, so a dry
run is a genuine rehearsal of the production path:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 -n --to ops@example.com
```

```text
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

**Nothing was sent.** The mail agent was resolved (`/usr/bin/mail` here) so the rehearsal proves
the alerting path is live — but the agent was never invoked. The "Try it yourself" exercise at
the end of this lab proves that with a marker file, so you can rehearse with complete confidence
even on a host whose mail agent is live.

Add `-v` to see the resolved configuration in one line:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 -n -v --to ops@example.com
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /usr/bin/mail
Recipient         : ops@example.com
Execution Mode    : DRY RUN (Simulation)
Diagnostics        : mail agent '/usr/bin/mail', recipient 'ops@example.com', dry-run 'true'
WARNING: Disk usage exceeds the threshold.
[DRY RUN] Would send an alert to ops@example.com
```

---

## Step 4: Inspect the Composed Alert Without Sending It

To see the exact subject and body the module would deliver, point `--mail-command` at a harmless
stand-in that records the hand-off and delivers nothing.

Create the stand-in:

```bash
mkdir -p /tmp/lab1_disk
cat > /tmp/lab1_disk/fake-mail-agent.sh <<'EOF'
#!/bin/bash
# A harmless stand-in for the host mail agent. It records the hand-off and
# delivers nothing, so the lab can never send a real email.
printf 'ARGV      : %s\n' "$*"
printf '%s\n' '--- body received on stdin ---'
cat
EOF
chmod +x /tmp/lab1_disk/fake-mail-agent.sh
```

Now run the alert path for real, against the stand-in:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 --to ops@example.com \
    --mail-command /tmp/lab1_disk/fake-mail-agent.sh
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /tmp/lab1_disk/fake-mail-agent.sh
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
ARGV      : -s Disk Alert: / at 91% ops@example.com
--- body received on stdin ---
Disk usage on cachy-os is at 91% (threshold: 80%).

Partition : /
Usage    : 91%
Threshold: 80%
Time     : 2026-10-21T16:36:46Z
Alert sent to ops@example.com
```

This is the whole mail contract in one line:

```text
<mail-command> -s <subject> <recipient>      # the body arrives on stdin
```

The subject is `Disk Alert: <partition> at <usage>%`. The body carries the hostname, the partition,
the usage, the threshold and a UTC timestamp — enough for the on-call engineer to act without
opening a second tool.

**Exit code: `0`.** The alert was handed off successfully.

### On Windows

```powershell
$env:DISK_MONITOR_USAGE_OVERRIDE = "91"
.\disk_monitor.ps1 -Partition C:\ -Threshold 80 -DryRun -To ops@example.com
```

The PowerShell side accepts the same environment contract and the same threshold semantics. Its
help text is available with `.\disk_monitor.ps1 -Help`.

---

## Step 5: The Configuration File and the Four-Level Precedence

A production deployment should not carry six flags in a cron entry. The module reads a
`key = value` file, and the command line still wins over it. The order is:

```text
flag  →  environment variable  →  configuration file  →  built-in default
```

Create a configuration file under `/tmp`, not in the repository. The repository ignores
`.diskmonitor.conf` because it may hold a token, and this lab keeps every artifact in the scratch
directory for the same reason:

```bash
cat > /tmp/lab1_disk/lab1.conf <<'EOF'
# Lab 1 configuration
partition = /
threshold = 70
notify = none
EOF
chmod 600 /tmp/lab1_disk/lab1.conf
```

`notify = none` keeps the lab offline: no recipient and no mail agent are needed. The file is mode
`600` because a real one may carry an HTTP bearer token.

Now walk the ladder. Each run prints the resolved threshold and the **source** of every setting on
the `Diagnostics` line, so the winner is visible rather than inferred.

### 5a. Nothing configured — the built-in default wins

```bash
./disk_monitor.sh --notify none -v
```

```text
Usage             : 50% (measured)
Threshold         : 80%
Diagnostics        : partition default, threshold default, notify flag, recipient default, mail command default, log file default, usage command default, usage override default
```

`threshold default` and `80%` come from the built-in default. (`50%` is this machine's real usage;
on your host the number will differ. `notify flag` is the `--notify none` on the command line.)

### 5b. The configuration file supplies the threshold

```bash
./disk_monitor.sh --config /tmp/lab1_disk/lab1.conf -v
```

```text
Usage             : 50% (measured)
Threshold         : 70%
Diagnostics        : partition config, threshold config, notify config, recipient default, mail command default, log file default, usage command default, usage override default
```

`threshold config` and `70%` come from the file. The `partition` and `notify` values come from the
file too, because this run carries no flag for them.

### 5c. The environment beats the file

```bash
DISK_MONITOR_THRESHOLD=60 ./disk_monitor.sh --config /tmp/lab1_disk/lab1.conf -v
```

```text
Usage             : 50% (measured)
Threshold         : 60%
Diagnostics        : partition config, threshold environment, notify config, recipient default, mail command default, log file default, usage command default, usage override default
```

`threshold environment` and `60%`: the file says `70`, and the environment overrode it. The other
settings still come from the file, which is the point of a per-setting source.

### 5d. The flag beats everything

```bash
DISK_MONITOR_THRESHOLD=60 ./disk_monitor.sh --config /tmp/lab1_disk/lab1.conf -t 50 -v
```

```text
Usage             : 50% (measured)
Threshold         : 50%
Diagnostics        : partition config, threshold flag, notify config, recipient default, mail command default, log file default, usage command default, usage override default
```

`threshold flag` and `50%`: the command line won over both the environment and the file.

### What the four runs prove

| Run | Threshold | Source label | Why |
| :--- | :---: | :--- | :--- |
| 5a | `80%` | `default` | Nothing else supplied a value. |
| 5b | `70%` | `config` | The file supplied it. |
| 5c | `60%` | `environment` | The environment outranks the file. |
| 5d | `50%` | `flag` | The flag outranks everything. |

Every run exits `0`. The threshold changed; the contract did not.

### Where the file is found

The path follows the same kind of order:

```text
--config  →  DISK_MONITOR_CONFIG  →  ./.diskmonitor.conf  →  ~/.config/disk-monitor/config
```

An explicit `--config` that does not exist is a configuration error, exit `1`. A missing default
file is not an error: the tool simply uses the defaults. This is why a cron entry can carry only
`--config /etc/disk-monitor/disk-monitor.conf` and nothing else.

---

## Step 6: Clean Up

```bash
rm -rf /tmp/lab1_disk
```

---

## ✅ What You Should See

| Check | Expected |
| :--- | :--- |
| `df -P /` | Six fields, capacity in the fifth position from the left. |
| Step 1 report | `Usage : <n>% (measured)` and `Disk usage is within the threshold.` |
| Step 2, usage `80` / threshold `80` | **No** warning. Usage equal to the threshold is quiet. |
| Step 2, usage `81` / threshold `80` | `WARNING: Disk usage exceeds the threshold.` |
| Step 3 dry run | `Execution Mode : DRY RUN (Simulation)` and `[DRY RUN] Would send an alert to ...` |
| Step 4 | The subject and body printed by the stand-in, then `Alert sent to ops@example.com` |
| Step 5a–5d | `Threshold : 80%`, then `70%`, `60%`, `50%` |
| Step 5 source labels | `threshold default` → `config` → `environment` → `flag` |
| Step 5 file discovery | `--config` beats `DISK_MONITOR_CONFIG`, then `./.diskmonitor.conf`, then `~/.config/disk-monitor/config` |
| Every exit code above | `0` — including the run that breached the threshold |

---

## 🧪 Try It Yourself

1. **Walk the boundary from the other side.** Run
   `DISK_MONITOR_USAGE_OVERRIDE=79 ./disk_monitor.sh -p / -t 80 --notify none` and then the same
   with `80`. Both are quiet. Now change the threshold to `78` with the same `79` value and watch
   the warning appear. Which number moved — the usage or the threshold? Does it matter?

2. **Prove the dry run never calls the mail agent.** Put a stand-in that writes a marker file
   instead of the one from Step 4:

   ```bash
   printf '#!/bin/bash\ntouch /tmp/lab1_disk/mail-was-called\n' > /tmp/lab1_disk/marker.sh
   chmod +x /tmp/lab1_disk/marker.sh
   DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 -n --to ops@example.com \
       --mail-command /tmp/lab1_disk/marker.sh
   ls /tmp/lab1_disk/mail-was-called
   ```

   The `ls` reports no such file: the dry run resolved the agent but never invoked it. Remove the
   marker file, then repeat the command **without** `-n` and check that the file now exists.

3. **Watch a real breach.** Drop the threshold below the real usage of your host and use the
   harmless stand-in from Step 4. Run `df -P /` first, note the percentage, then run:

   ```bash
   ./disk_monitor.sh -p / -t 1 --to ops@example.com \
       --mail-command /tmp/lab1_disk/fake-mail-agent.sh
   ```

   The report now carries a **measured** number and a real breach.

---

## 📎 Related Documents

- [Lab 2 — Exit Codes & Audit Log](LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — the exit-code contract, end to end.
- [SCENARIOS.md](../SCENARIOS.md) — the operational failure modes.
- [`../../README.md`](../../README.md) — usage, flags and troubleshooting.

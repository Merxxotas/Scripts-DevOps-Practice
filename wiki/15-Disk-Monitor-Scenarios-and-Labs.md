# 15. Disk Monitor — Scenarios & Interactive Labs

> How module 1 is deployed in practice — over a mail agent or an HTTP
> endpoint, from flags, the environment or a configuration file — and the
> hands-on labs that run the real commands, including the doctor.

---

## The scenarios

### A scheduled check on a Linux host

```cron
DISK_MONITOR_TO=ops@example.com
*/5 * * * * /opt/disk-monitor/disk_monitor.sh -p / -t 80 -l /var/log/disk-monitor/audit.log
```

Two details matter more than they look.

**`cron` does not inherit the login environment.** A variable exported in an
interactive shell is invisible to a cron job, so `DISK_MONITOR_TO` has to be
declared in the crontab itself (as above) or inside a wrapper script that
`cron` calls.

**The exit code is the result.** The cron job succeeds when the check
completes, whether or not the disk is over the threshold. An alert is a
`0` — the tool did its job. A `1` or a `2` in the cron log means something
is genuinely broken, and that is the only thing worth paging on.

### The same check under systemd

On a modern host, a systemd timer is the better scheduler: it gives the
run a journal, it survives a reboot without a `cron` daemon, and the exit
status is recorded per run.

```ini
# /etc/systemd/system/disk-monitor.service
[Unit]
Description=Disk usage check

[Service]
Type=oneshot
Environment=DISK_MONITOR_TO=ops@example.com
ExecStart=/opt/disk-monitor/disk_monitor.sh -p / -t 80 -l /var/log/disk-monitor/audit.log
```

A service that uses the `http` transport keeps its token out of the unit file
by pointing at the configuration file instead:

```ini
Environment=DISK_MONITOR_CONFIG=/etc/disk-monitor.conf
ExecStart=/opt/disk-monitor/disk_monitor.sh --notify http -p / -t 80
```

```ini
# /etc/systemd/system/disk-monitor.timer
[Unit]
Description=Run the disk usage check every five minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now disk-monitor.timer
systemctl list-timers disk-monitor.timer
```

Those three run on the host that owns the unit, as root.

### The same check on a Windows host

On the Windows host, with PowerShell 7 installed:

```powershell
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-File C:\Tools\disk_monitor.ps1 -Threshold 80 -To ops@example.com"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "Disk Monitor" -Action $action -Trigger $trigger
```

The PowerShell implementation defaults to the **system drive**, so
`-Partition` is only needed when the volume to watch is not `C:\`.

A Windows host without a mail agent uses the same HTTP transport, with the
same parameter names:

```powershell
.\disk_monitor.ps1 -Notify http -Url https://ntfy.sh/disk-alerts -DryRun
```

That is the path a Windows host should take: the platform has no local mail
agent, and `-Notify mail` on Windows reports exactly that. The client is
resolved as an application, so `-HttpCommand curl` reaches `curl.exe` and not
the legacy PowerShell alias.

### Watching a data volume instead of the root

One partition per invocation means a host with two volumes to watch runs the
tool twice. On the host that owns those volumes:

```bash
./disk_monitor.sh -p /var/lib/data -t 85 --to ops@example.com
./disk_monitor.sh -p /var/log -t 70 --to ops@example.com
```

Different thresholds are usually right: a log volume fills faster and is
cheaper to prune, so it deserves an earlier warning than a data volume. A
path that does not exist is refused with exit `1`, so a typo in a `cron`
entry fails loudly instead of watching nothing.

### Notifying over HTTP instead of mail

The `http` backend turns the same check into one request to a URL. Anything
that accepts a request with a body works: ntfy, Telegram, Discord, Slack, or
a receiver you host yourself.

```cron
DISK_MONITOR_URL=https://ntfy.sh/disk-alerts
*/5 * * * * /opt/disk-monitor/disk_monitor.sh --notify http -p / -t 80 -l /var/log/disk-audit.log
```

A header is where a token belongs, and a `cron` environment line is a poor
place to keep one: the token would sit in the crontab. Put the header in the
configuration file instead, and keep the crontab to the endpoint.

The report swaps `Mail Agent` and `Recipient` for `Endpoint` and
`HTTP Client`. A dry run still shows both, and hands nothing to the client:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -n --notify http \
  --url https://ntfy.sh/disk-alerts -p / -t 80
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

The client path is the one this host resolved; on Windows it names
`curl.exe`.

### Configuring the host once

A host that checks five partitions does not want five command lines. The
configuration file holds what does not change; the flag holds what does.

```bash
S=$(mktemp -d)
install -m 600 /dev/null "$S/diskmonitor.conf"
cat > "$S/diskmonitor.conf" <<'EOF'
notify = http
url = https://ntfy.sh/disk-alerts
threshold = 85
header = Authorization: Bearer your-token
body_template = {"topic":"disk","message":"{body}"}
EOF

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh --config "$S/diskmonitor.conf" -n
```

```
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 85%
Endpoint          : https://ntfy.sh/disk-alerts
HTTP Client       : /usr/bin/curl
Execution Mode    : DRY RUN (Simulation)
WARNING: Disk usage exceeds the threshold.
[DRY RUN] Would send an alert to https://ntfy.sh/disk-alerts
```

`install -m 600` creates the file private from the first byte, so there is no
window in which a token is world-readable. On a real host the file lives
somewhere like `/etc/disk-monitor.conf`, and `DISK_MONITOR_CONFIG` in the unit
file points at it.

The precedence is visible in the report. The file says `85`; the environment
wins over it:

```bash
DISK_MONITOR_THRESHOLD=84 DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh --config "$S/diskmonitor.conf" -n
```

```
Threshold         : 84%
```

and the flag wins over the environment:

```bash
DISK_MONITOR_THRESHOLD=84 DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh --config "$S/diskmonitor.conf" -n -t 83
```

```
Threshold         : 83%
```

**The default lookup is relative to the working directory**, not to the
script. A cron job whose `cwd` is `/root` reads `/root/.diskmonitor.conf`, not
the file next to the script. That is why a scheduled host should pass
`--config` or `DISK_MONITOR_CONFIG` with an absolute path.

### The doctor before the first run

`--doctor` answers "will this host alert?" without measuring the disk and
without sending anything. Continuing in the same shell:

```bash
./disk_monitor.sh --config "$S/diskmonitor.conf" --doctor
```

```
============================================================
                 Disk Usage Monitor - Doctor
============================================================
Platform            : Linux (cachyos)
Config file         : /tmp/tmp.wLiBMeN5pN/diskmonitor.conf
Partition           : / (default)
Threshold           : 85% (config)
Notify backend      : http (config)
Endpoint            : https://ntfy.sh/disk-alerts (config)
Recipient           : (not required)
HTTP client         : /usr/bin/curl (default)
Mail agent          : (not required)
Measurement command : /usr/bin/df (default)
Audit log file      : (not set)
HTTP headers        : 1 (config)
------------------------------------------------------------
Status              : READY
```

The exit code is `0`, and the word `READY` says the tool would run. Every
value is followed by the layer it came from, which is what makes a
precedence problem visible: `threshold` reads `85% (config)` here, and would
read `(flag)` or `(environment)` if one of those had supplied it.

The scratch path and the platform name are this run's. The header count is
`1`, and the token itself does not appear anywhere on the page.

Without the configuration, the same command reports `NOT READY` and exits
`1`:

```bash
./disk_monitor.sh --doctor; echo "exit=$?"
```

```
Status              : NOT READY
  - No recipient is configured. Set --to, or DISK_MONITOR_TO, or the 'to' key in the
    configuration file.
exit=1
```

The remedy is one line in the tool's output; it is wrapped here to fit the
page. The full report was shown on
[page 13](13-Disk-Monitor-Overview.md#the-doctor); the last two lines are
the verdict and the remedy.

### Going live without sending mail

Before a scheduled deployment, prove the alerting path with a forced usage
value and a dry run. Nothing is measured and nothing is sent:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -n --to ops@example.com -p / -t 80
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

The report says **`overridden`**, not `measured`. A forced value that
silently looked like a real measurement would be the worst possible bug in a
monitor, so the source of every number is part of the report and part of
the audit log. The record is wrapped here; the tool writes it on one line:

```
2026-10-21T16:37:36Z [INFO] [DRY RUN] Would send an alert to ops@example.com
(Usage: 91%, Source: overridden, Threshold: 80%)
```

### Proving the HTTP request without a network

The HTTP client is an external command, so a stub on the path proves the
whole request path with no network and no real service. The stub below
receives the rendered body on standard input, and the run writes its full
output to a file so the token can be searched for afterwards:

```bash
S=$(mktemp -d)
printf '#!/bin/sh\necho "fake-curl: request received"\ncat\n' > "$S/fake-curl"
chmod +x "$S/fake-curl"

HOME=$(mktemp -d) DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh \
  --notify http --url https://ntfy.sh/disk-alerts \
  --http-command "$S/fake-curl" \
  --header 'Authorization: Bearer s3cr3t-token' \
  --body-template '{"usage":"{usage}"}' \
  --log-file "$S/audit.log" -p / -t 80 -v > "$S/run.out" 2>&1

grep -c 's3cr3t' "$S/run.out" || true
grep -c 's3cr3t' "$S/audit.log" || true
```

```
0
0
```

Both counts are zero even with `-v`: the verbose output adds the provenance
of each value and the header **count**, and the audit log adds the delivery
and the numbers. Neither adds the token.

That is the check worth repeating after changing a transport: the token
reaches the client and nothing else.

### The alert as the trigger for module 2

The two modules close a loop:

1. Module 1 measures the filesystem every five minutes and alerts when the
   usage passes the threshold.
2. The alert reaches a human — or a runbook.
3. Module 2 prunes the logs and recovers the space.

The important boundary is that module 1 never triggers module 2 directly.
A monitor that could delete files on its own would be a monitor with a
destructive side effect and no dry run, and it would be exactly the kind of
tool that one bad threshold turns into an outage. The sensor reports; the
actuator acts; a human is in the loop.

### The reference deployment: a VPS with a mail relay

The module was written to run on the user's Oracle Cloud VPS — an
`aarch64` Ubuntu instance. Two infrastructure facts shape the deployment,
and **neither of them belongs in the module**:

* **Outbound TCP port 25 is blocked** on tenancies created after
  2021-06-23, and the block cannot be lifted from the VCN security list. The
  VPS therefore relays through a third-party provider on port 587, where the
  provider handles DKIM signing.
* **The credentials belong to the relay, not to the module.** The mail agent
  on the VPS holds them. The module never sees them.

The module's contract is unchanged by any of this. It resolves a mail agent,
composes a message and hands it over. Swapping the relay configuration is
an operation on the host, not a change to the tool.

The **HTTP transport is the other answer to the port-25 block.** It needs no
relay and no port 25: the alert is one request to an `https` endpoint, and
the token, if the endpoint needs one, is a header in the configuration file.
That is why the transport was added before the remaining seed modules were
converted — a host that cannot send mail is no longer a host that cannot
alert.

### Checking a specific volume on a Windows host

```powershell
.\disk_monitor.ps1 -Partition D:\ -Threshold 75 -To ops@example.com -DryRun
```

The Windows implementation reads the volume API directly, so the figure it
reports is the one Windows itself reports in Explorer.

---

## The labs

The first three labs live with the module, in
[`1-Disk-Usage-Monitoring-with-Email-Alert/docs/labs/`](https://github.com/Merxxotas/Scripts-DevOps-Practice/tree/main/1-Disk-Usage-Monitoring-with-Email-Alert/docs/labs).
The fourth is written on this page, because it is the one that needs no
files beyond a scratch directory.

### LAB 1 — Measure, compare and rehearse the alert

Fifteen minutes. Covers the raw measurement, the **strictly greater**
comparison and its exact boundary — usage at the threshold does not alert,
one point over does — the dry run, and how to inspect the composed alert
without sending it.

**[Lab 1: Measure, Compare & Rehearse the Alert](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/1-Disk-Usage-Monitoring-with-Email-Alert/docs/labs/LAB1_THRESHOLD_AND_DRY_RUN.md)**

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
./disk_monitor.sh -n --to ops@example.com -p / -t 40
```

### LAB 2 — The exit-code contract and the audit log

Twenty minutes. Covers all three exit codes — `0` for a completed check in
its three forms (nothing to send, alert delivered, alert suppressed), `1`
for the configuration errors, `2` for the partial failures — and the
ISO-8601 audit log end to end.

**[Lab 2: The Exit-Code Contract & the Audit Log](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/1-Disk-Usage-Monitoring-with-Email-Alert/docs/labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md)**

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
./disk_monitor.sh -t 0 --to ops@example.com; echo "exit=$?"
./disk_monitor.sh -p /nope-not-here --notify none; echo "exit=$?"
```

### LAB 3 — Production deployment on a VPS with a relay

Thirty minutes. Covers installing `msmtp` on the VPS, configuring the relay
in `/etc/msmtprc`, the permissions on the credentials file, the cron entry,
the first live alert, and rotating the audit log.

**[Lab 3: Production Deployment on a VPS with a Relay](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/1-Disk-Usage-Monitoring-with-Email-Alert/docs/labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md)**

### LAB 4 — The transport, the configuration and the doctor

Twenty minutes, and it runs from this page. It needs the module directory and
nothing else: no mail agent, no network, no service.

**Step 1 — ask the doctor about an unconfigured host.** It must refuse:

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
./disk_monitor.sh --doctor; echo "exit=$?"
```

```
Status              : NOT READY
  - No recipient is configured. Set --to, or DISK_MONITOR_TO, or the 'to' key in the
    configuration file.
exit=1
```

The remedy line is wrapped here, as on page 13.

**Step 2 — create a private configuration and ask again.** This is the
scenario *Configuring the host once*, run as a lab; the file is created
`600`, so the doctor has nothing to warn about.

```bash
S=$(mktemp -d)
install -m 600 /dev/null "$S/diskmonitor.conf"
cat > "$S/diskmonitor.conf" <<'EOF'
notify = http
url = https://ntfy.sh/disk-alerts
threshold = 85
header = Authorization: Bearer your-token
body_template = {"topic":"disk","message":"{body}"}
EOF

./disk_monitor.sh --config "$S/diskmonitor.conf" --doctor; echo "exit=$?"
```

The verdict is `Status : READY` and the exit code is `0`. The report must
show `Threshold : 85% (config)`, `Notify backend : http (config)` and
`HTTP headers : 1 (config)`.

**Step 3 — dry-run the same configuration.** Nothing is sent:

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh --config "$S/diskmonitor.conf" -n
echo "exit=$?"
```

The report shows `Endpoint`, `HTTP Client`, `DRY RUN (Simulation)` and
`[DRY RUN] Would send an alert to https://ntfy.sh/disk-alerts`, and the exit
code is `0`.

**Step 4 — prove the token does not leak.** A stub client receives the
request; the run writes everything it prints to a file, and both that file
and the audit log are searched for the token. Both counts must be `0`.

```bash
S4=$(mktemp -d)
printf '#!/bin/sh\ncat >/dev/null\n' > "$S4/fake-curl"
chmod +x "$S4/fake-curl"

HOME=$(mktemp -d) DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh \
  --notify http --url https://ntfy.sh/disk-alerts \
  --http-command "$S4/fake-curl" \
  --header 'Authorization: Bearer s3cr3t-token' \
  --log-file "$S4/audit.log" -p / -t 80 -v > "$S4/run.out" 2>&1

grep -c 's3cr3t' "$S4/run.out" || true
grep -c 's3cr3t' "$S4/audit.log" || true
```

```
0
0
```

**Step 5 — refuse what is out of scope.** `smtp` is not a backend, and the
refusal names the three that are:

```bash
./disk_monitor.sh --notify smtp; echo "exit=$?"
```

```
Error: Notify backend must be 'none', 'mail' or 'http'.
exit=1
```

A finished lab leaves the host with a working doctor, a private
configuration, a proven request path and no token in any log.

---

## Running the test suite

The Bash suite runs locally and needs nothing but Bash:

```bash
cd 1-Disk-Usage-Monitoring-with-Email-Alert
bash tests/test_disk_monitor.sh
```

```
============================================================
Tests Summary: 277 Passed, 0 Failed
============================================================
```

The suite never sends a real email, never opens a network connection and
never depends on the host's disk layout: the measurement command, the mail
agent and the HTTP client are stubbed, and every configuration file lives
under a temporary sandbox. That is what makes 277 assertions deterministic.

Since the parity work, the suite also reads `disk_monitor.ps1` as a source
file and compares the flag set, the environment names and the configuration
keys with the Bash side — see
[page 14](14-Disk-Monitor-Bash-vs-PowerShell.md#the-parity-proof-and-what-it-costs).

The PowerShell suite mirrors the Bash suite case for case, and it performs
the same comparison in the other direction. This host has neither `pwsh` nor
`shellcheck`, so both are CI-only gates here: the PowerShell suite runs on
`windows-2022` and `ubuntu-24.04`, and the Bash lint on `ubuntu-24.04`.

```powershell
pwsh -File 1-Disk-Usage-Monitoring-with-Email-Alert/tests/test_disk_monitor.ps1
```

---

## The CI pipeline

The module's pipeline lives at the repository root, in
`.github/workflows/ci-disk-monitor.yml`, and is path-filtered to
`1-Disk-Usage-Monitoring-with-Email-Alert/**` — plus the workflow file
itself.

| Job | Runner | Gate |
| :--- | :--- | :--- |
| `lint-bash` | `ubuntu-24.04` | ShellCheck on the script and the suite |
| `test-bash` | `ubuntu-24.04`, `macos-14` | the Bash suite |
| `lint-powershell` | `windows-2022` | PSScriptAnalyzer on the script and the suite |
| `test-powershell` | `windows-2022`, `ubuntu-24.04` | the PowerShell suite |

Four jobs, six runner instances: the two test jobs are matrices, so the
transport is exercised on Linux, macOS and Windows by the same suite.

Two details of that matrix are deliberate:

* **macOS is in the Bash matrix** because macOS is the reason the module
  uses `df -P` at all: the human-readable `df -h` layout is not the same on
  BSD as on GNU, and the POSIX layout the module depends on has to be proven
  on both.
* **Ubuntu is in the PowerShell matrix** because PowerShell 7 runs on Linux,
  and an implementation that only works on Windows is an implementation that
  only the author could test. The same reasoning that once broke module 5's
  PowerShell script on Linux applies here in advance.

See
[08. CI/CD Pipelines & Testing Philosophy](08-CI-CD-Pipelines.md) for the
monorepo-wide model.

---

## Where to go next

* [13. Disk Usage Monitor — Overview & Specs](13-Disk-Monitor-Overview.md)
* [14. Bash vs PowerShell](14-Disk-Monitor-Bash-vs-PowerShell.md)
* [05. Log Cleanup Overview](05-Log-Cleanup-Overview.md)

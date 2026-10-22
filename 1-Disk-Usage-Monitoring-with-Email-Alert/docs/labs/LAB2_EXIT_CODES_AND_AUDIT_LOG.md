# Lab 2: The Exit-Code Contract & the Audit Log 🔢

## Objective

Exercise the **entire exit-code contract** of the module — every `0`, every `1`, every `2` — and
read the audit log that records what happened. When this lab is finished you will be able to write
a wrapper that reacts correctly to the monitor, because you know exactly what each code means and
what it does *not* mean.

---

## 📋 Prerequisites

- A Linux or macOS host with Bash 4+ (or a Windows host with PowerShell 7+).
- Execution permission on `disk_monitor.sh` (or `disk_monitor.ps1`).
- No mail account, no credentials, no MTA. **This lab never sends an email.**
- No network access. The HTTP transport is exercised with a stand-in client on `PATH`.

> Run every command from the module folder:
> ```bash
> cd 1-Disk-Usage-Monitoring-with-Email-Alert
> ```

---

## Step 1: The Contract in One Table

| Code | Meaning | Produced by |
| :--: | :--- | :--- |
| `0` | Success | The check ran; the alert was delivered, not needed, or deliberately suppressed. |
| `1` | Configuration / safety error | Unknown flag, threshold outside 1–100, missing partition, unset recipient, missing endpoint, invalid URL, timeout, method or header, unresolvable mail agent, HTTP client or measurement command. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent or the HTTP client. |

> **A breach is not a failure.** The run that *detects* a full disk exits `0`. Only the monitor's
> own breakdown exits non-zero. If your wrapper pages on every non-zero exit, it will page on the
> disk filling up — the one event that is supposed to be an `INFO` line in the audit log.

---

## Step 2: Build the Sandbox

Two stubs let us reach the failure paths without breaking the host. The measurement stub resolves
but fails; the mail stub resolves but refuses the hand-off.

```bash
mkdir -p /tmp/lab2_disk

cat > /tmp/lab2_disk/df-broken <<'EOF'
#!/bin/bash
# A measurement command that resolves but always fails, so the module can
# exercise the "usage could not be read" path.
echo "df: simulated failure" >&2
exit 1
EOF

cat > /tmp/lab2_disk/failing-mail-agent.sh <<'EOF'
#!/bin/bash
# A mail agent that refuses the hand-off, so the module can exercise the
# partial-failure path without sending anything.
cat >/dev/null
exit 1
EOF

cat > /tmp/lab2_disk/fake-mail-agent.sh <<'EOF'
#!/bin/bash
# A harmless stand-in for the host mail agent: it records nothing and
# delivers nothing.
cat >/dev/null
exit 0
EOF

cat > /tmp/lab2_disk/recording-http-client.sh <<'EOF'
#!/bin/bash
# A stand-in for the HTTP client: records the request shape and delivers
# nothing. It never echoes a header value.
method=""; timeout=""; headers=0; names=""; last=""; prev=""
for arg in "$@"; do
    case "$prev" in
        --request) method="$arg" ;;
        --max-time) timeout="$arg" ;;
        --header) headers=$((headers + 1)); names="$names ${arg%%:*}" ;;
    esac
    prev="$arg"; last="$arg"
done
printf 'method  : %s\n' "$method"
printf 'timeout : %s\n' "$timeout"
printf 'headers : %s (%s)\n' "$headers" "$names"
printf 'url     : %s\n' "$last"
printf '%s\n' '--- body on stdin ---'
cat
EOF

cat > /tmp/lab2_disk/failing-http-client.sh <<'EOF'
#!/bin/bash
# A client that resolves but refuses the request, so the module can exercise
# the "the check worked, the delivery did not" path.
cat >/dev/null
exit 7
EOF

chmod +x /tmp/lab2_disk/df-broken
chmod +x /tmp/lab2_disk/failing-mail-agent.sh
chmod +x /tmp/lab2_disk/fake-mail-agent.sh
chmod +x /tmp/lab2_disk/recording-http-client.sh
chmod +x /tmp/lab2_disk/failing-http-client.sh
```

`recording-http-client.sh` is the same contract as `curl`: it accepts the argv the module builds,
reads the body from stdin and exits `0`. `failing-http-client.sh` reads the body and exits `7`,
which stands in for a refused connection or a timeout.

Start from a clean environment so the host's own variables cannot influence the result:

```bash
unset DISK_MONITOR_TO DISK_MONITOR_MAIL_COMMAND
unset DISK_MONITOR_USAGE_OVERRIDE DISK_MONITOR_USAGE_COMMAND
```

---

## Step 3: Exercise `0` — Success

### 0a — Below the threshold, nothing sent

```bash
./disk_monitor.sh -p / -t 80 --notify none
echo "exit=$?"
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
exit=0
```

### 0b — Above the threshold, alert delivered

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 --to ops@example.com \
    --mail-command /tmp/lab2_disk/fake-mail-agent.sh
echo "exit=$?"
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /tmp/lab2_disk/fake-mail-agent.sh
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
Alert sent to ops@example.com
exit=0
```

### 0c — Above the threshold, alert deliberately suppressed

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 -n --to ops@example.com
echo "exit=$?"
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
exit=0
```

**All three are `0`.** The alert was delivered, not needed, or suppressed — three different
outcomes, one code. That is the point: `0` means *the monitor worked*.

---

## Step 4: Exercise `1` — Configuration and Safety Errors

Every `1` below is detected **before** the disk is measured, because validation runs first.

### 1a — Unknown flag

```bash
./disk_monitor.sh --this-flag-does-not-exist
echo "exit=$?"
```

```text
Error: Unknown option '--this-flag-does-not-exist'.
exit=1
```

The full help text is printed to stdout alongside the error, so the operator sees the correct
syntax immediately.

### 1b — Threshold outside 1–100

```bash
./disk_monitor.sh -t 101 --to ops@example.com
echo "exit=$?"
```

```text
Error: Threshold must be an integer between 1 and 100.
exit=1
```

### 1c — Partition does not exist

```bash
./disk_monitor.sh -p /no/such/partition --to ops@example.com
echo "exit=$?"
```

```text
Error: Partition '/no/such/partition' does not exist.
exit=1
```

### 1d — Recipient unset

```bash
./disk_monitor.sh --notify mail
echo "exit=$?"
```

```text
Error: No recipient. Use --to, or set DISK_MONITOR_TO.
exit=1
```

### 1e — Mail agent cannot be resolved

```bash
./disk_monitor.sh --mail-command /tmp/lab2_disk/not-a-real-agent --to ops@example.com
echo "exit=$?"
```

```text
Error: No mail agent found. Install one, or set --mail-command or DISK_MONITOR_MAIL_COMMAND.
exit=1
```

### 1f — Measurement command cannot be resolved

```bash
DISK_MONITOR_USAGE_COMMAND=/tmp/lab2_disk/not-a-real-command \
    ./disk_monitor.sh -p / -t 80 --to ops@example.com
echo "exit=$?"
```

```text
Error: Measurement command '/tmp/lab2_disk/not-a-real-command' was not found.
exit=1
```

### 1g — The HTTP endpoint is missing

`--notify http` without a URL is exactly as broken as `mail` without a recipient: there is nowhere
to send the alert. It is refused before the disk is measured.

```bash
./disk_monitor.sh --notify http
echo "exit=$?"
```

```text
Error: No endpoint. Use --url, or set DISK_MONITOR_URL.
exit=1
```

> **Rule of thumb for `1`:** it will stay broken until someone edits a file. A scheduler should
> page on it.

---

## Step 5: Exercise `2` — Partial Failures

`2` is the "the check worked, the delivery did not" code. Both cases below are worth telling apart
from `1`, because both may succeed on the next run.

### 2a — The usage could not be read

```bash
DISK_MONITOR_USAGE_COMMAND=/tmp/lab2_disk/df-broken \
    ./disk_monitor.sh -p / -t 80 --to ops@example.com
echo "exit=$?"
```

```text
Error: Could not read the disk usage of '/'.
exit=2
```

The command resolved — so the configuration is valid — but the measurement itself failed.

### 2b — The alert could not be handed to the mail agent

```bash
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 --to ops@example.com \
    --mail-command /tmp/lab2_disk/failing-mail-agent.sh
echo "exit=$?"
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /tmp/lab2_disk/failing-mail-agent.sh
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
Error: The alert could not be handed to the mail agent.
exit=2
```

Note that the report on stdout still shows the breach. The monitor did its job and said so; the
delivery failed and it said that too. **This is the dangerous case**: the disk is over the
threshold and nobody was told.

### 2c — The alert could not be handed to the HTTP client

The same distinction applies to the HTTP transport. A client that resolves — so the configuration
is valid — but cannot deliver is a partial failure, not a configuration error:

```bash
AUDIT=/tmp/lab2_disk/transport-audit.log
rm -f "$AUDIT"

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 --notify http \
    --url https://example.invalid/disk \
    --http-command /tmp/lab2_disk/failing-http-client.sh -l "$AUDIT"
echo "exit=$?"
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://example.invalid/disk
HTTP Client       : /tmp/lab2_disk/failing-http-client.sh
Execution Mode    : LIVE (Alerts Active)
Audit Log File    : /tmp/lab2_disk/transport-audit.log
WARNING: Disk usage exceeds the threshold.
Error: The alert could not be handed to the HTTP client.
exit=2
```

The audit line:

```text
2026-10-22T17:53:35Z [ERROR] FAILED to hand the alert to the HTTP client (Usage: 91%, Source: overridden)
```

`1` says the deployment is wrong; `2` says the request was attempted and failed. An unreachable
endpoint, a timeout and an HTTP error status all produce `2`: the client is asked to fail, so a
`4xx` or `5xx` is a failed hand-off and never a recorded delivery. The first two may succeed on the
next run; the third usually needs the endpoint, the credential or the routing fixed first.

---

## Step 6: The Audit Log, End to End

Now run the whole matrix again, this time with `-l` pointing at one file, and read what the
monitor recorded.

```bash
AUDIT=/tmp/lab2_disk/audit.log
rm -f "$AUDIT"

run() {
    local label="$1"; shift
    "$@" -l "$AUDIT" >/dev/null 2>&1
    printf '%s exit=%s\n' "$label" "$?"
}

run 0a ./disk_monitor.sh -p / -t 80 --notify none
run 1a ./disk_monitor.sh --this-flag-does-not-exist
run 1b ./disk_monitor.sh -t 101 --to ops@example.com
run 1c ./disk_monitor.sh -p /no/such/partition --to ops@example.com
run 1d ./disk_monitor.sh --notify mail
run 1e ./disk_monitor.sh --mail-command /tmp/lab2_disk/not-a-real-agent --to ops@example.com
run 1f env DISK_MONITOR_USAGE_COMMAND=/tmp/lab2_disk/not-a-real-command \
    ./disk_monitor.sh -p / -t 80 --to ops@example.com
run 2a env DISK_MONITOR_USAGE_COMMAND=/tmp/lab2_disk/df-broken \
    ./disk_monitor.sh -p / -t 80 --to ops@example.com
run 2b env DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --to ops@example.com --mail-command /tmp/lab2_disk/failing-mail-agent.sh
run 0c env DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 -n \
    --to ops@example.com
run 0b env DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --to ops@example.com --mail-command /tmp/lab2_disk/fake-mail-agent.sh
```

```text
0a exit=0
1a exit=1
1b exit=1
1c exit=1
1d exit=1
1e exit=1
1f exit=1
2a exit=2
2b exit=2
0c exit=0
0b exit=0
```

The audit log:

```bash
cat "$AUDIT"
```

```text
2026-10-21T16:40:14Z [INFO] Usage within threshold (Usage: 49%, Source: measured, Threshold: 80%)
2026-10-21T16:40:14Z [ERROR] Invalid threshold: '101'.
2026-10-21T16:40:14Z [ERROR] Partition does not exist: '/no/such/partition'.
2026-10-21T16:40:14Z [ERROR] No alert recipient configured.
2026-10-21T16:40:14Z [ERROR] No mail agent could be resolved.
2026-10-21T16:40:14Z [ERROR] Measurement command not found: '/tmp/lab2_disk/not-a-real-command'.
2026-10-21T16:40:14Z [ERROR] Could not read the disk usage of '/'.
2026-10-21T16:40:14Z [ERROR] FAILED to hand the alert to the mail agent (Usage: 91%, Source: overridden)
2026-10-21T16:40:14Z [INFO] [DRY RUN] Would send an alert to ops@example.com (Usage: 91%, Source: overridden, Threshold: 80%)
2026-10-21T16:40:14Z [INFO] ALERT SENT to ops@example.com (Usage: 91%, Source: overridden, Threshold: 80%)
```

### Reading the log

| Observation | Why it matters |
| :--- | :--- |
| **11 runs, 10 lines.** | The unknown flag (`1a`) produced **no** line: the flag parser rejects the argument before the audit log path is configured. An unknown flag is visible on stderr, not in the log. |
| **One line per run.** | The log is a timeline, not a transcript. |
| **ISO-8601 UTC timestamps.** | Lines from several hosts interleave into one readable chronology. |
| **`Source: measured` vs `Source: overridden`.** | A forced value is always labelled. The `0b` and `0c` lines say `overridden` because this lab forced the percentage. |
| **`[INFO]` for a breach, `[ERROR]` for a failure.** | A fired alert is `INFO`, not `ERROR`. The disk being full is not the tool's fault. |

---

## Step 7: A Header Value Never Reaches the Log

A header may carry a bearer token. The audit log is a durable file that outlives the run, so the
module never writes a header value into it — and never prints one either. Prove it on this host.

### 7a. Run the HTTP transport with a secret header

```bash
AUDIT=/tmp/lab2_disk/header-audit.log
OUT=/tmp/lab2_disk/header-run.out
rm -f "$AUDIT" "$OUT"

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 --notify http \
    --url https://ntfy.sh/lab-disk-alerts \
    --header 'Authorization: Bearer S3CRET-TOKEN' \
    --http-command /tmp/lab2_disk/recording-http-client.sh \
    -l "$AUDIT" > "$OUT" 2>&1
echo "exit=$?"
```

```text
exit=0
```

The recording client received the header — it prints the count and the name, never the value:

```text
method  : POST
timeout : 10
headers : 1 ( Authorization)
url     : https://ntfy.sh/lab-disk-alerts
```

### 7b. Grep the audit log and the captured output for the secret

```bash
grep -c 'S3CRET-TOKEN' "$AUDIT" "$OUT" || true
```

```text
/tmp/lab2_disk/header-audit.log:0
/tmp/lab2_disk/header-run.out:0
```

Zero in the audit log and zero in everything the monitor printed. The `|| true` is there because
`grep` exits `1` when it finds nothing, and finding nothing is the expected result.

The audit line records the endpoint and the measurement, not the credential:

```text
2026-10-22T17:53:42Z [INFO] ALERT SENT to https://ntfy.sh/lab-disk-alerts (Usage: 91%, Source: overridden, Threshold: 80%)
```

### 7c. The doctor reports a count, not a value

```bash
./disk_monitor.sh --notify http --url https://ntfy.sh/lab-disk-alerts \
    --header 'Authorization: Bearer S3CRET-TOKEN' --doctor
```

An excerpt of the report:

```text
HTTP headers        : 1 (flag)
Status              : READY
```

The number says the header is configured, the provenance says where it came from, and the value is
absent. `-v` shows the same pair on the `Transport` line: `headers 1 (flag)`.

### 7d. A malformed header is named by position

```bash
./disk_monitor.sh --notify http --url https://example.invalid/disk \
    --header 'Bearer S3CRET-TOKEN'
echo "exit=$?"
```

```text
Error: Header 1 is malformed. Expected 'Name: value'.
exit=1
```

The error names header `1`, not its text. A value with no colon is the common paste error; the
refusal is a configuration error (`1`), and the token is not echoed.

### What this does not hide

The value is visible in the process argument list while the request runs, because that is how an
HTTP client receives a header. The module cannot change that without writing the token to a file,
which is worse. The endpoint is printed and logged too: if the URL itself holds a token — a
Telegram, Discord or Slack webhook URL does — that token is in the audit log. The header mechanism
protects the header, not the URL.

---

## Step 8: Clean Up

```bash
rm -rf /tmp/lab2_disk
```

---

## ✅ What You Should See

| Check | Expected |
| :--- | :--- |
| Every `0` case | Exit `0`, including the run that breached the threshold. |
| Every `1` case | A single `Error:` line on **stderr**, exit `1`. |
| Every `2` case | A single `Error:` line on **stderr**, exit `2`. |
| The unknown flag | The help text on stdout **and** the error on stderr. |
| The audit log | 10 lines for 11 runs — the unknown flag leaves no trace. |
| The `ALERT SENT` line | Present only for the run whose mail agent succeeded. |
| `--notify http` with no endpoint | `Error: No endpoint. Use --url, or set DISK_MONITOR_URL.`, exit `1`. |
| A failing HTTP client | `Error: The alert could not be handed to the HTTP client.`, exit `2`, one `[ERROR]` line. |
| `grep -c 'S3CRET-TOKEN'` | `0` in both the audit log and the captured output. |
| The doctor with one header | `HTTP headers : 1 (flag)` and no value. |

---

## 🧪 Try It Yourself

1. **Write the wrapper.** Using only the exit code, write a three-line shell snippet that pages
   on `1`, retries on `2` and stays silent on `0`. Then check it against the matrix above:

   ```bash
   ./disk_monitor.sh -p / -t 80 --notify none \
       || case "$?" in
             1) echo "page the operator: the deployment is broken" ;;
             2) echo "retry later: the measurement or the delivery failed" ;;
           esac
   ```

2. **Prove the audit write is best-effort.** Point the log at a path that cannot be created and
   watch the exit code stay `0`:

   ```bash
   ./disk_monitor.sh -p / -t 80 --notify none -l /etc/disk-monitor/audit.log
   echo "exit=$?"
   ```

   The report ends with:

   ```text
   Audit Log File    : /etc/disk-monitor/audit.log
   Disk usage is within the threshold.
   ./disk_monitor.sh: line 208: /etc/disk-monitor/audit.log: No such file or directory
   exit=0
   ```

   A monitor that died because its log directory was read-only would be a monitor that stopped
   monitoring. The trade-off is that the durable channel has to live somewhere else.

3. **Prove the log survives a restart.** Run the module twice against the same `-l` file and
   confirm the second run **appends** rather than truncating:

   ```bash
   AUDIT=/tmp/lab2_disk/append.log
   rm -f "$AUDIT"
   ./disk_monitor.sh -p / -t 80 --notify none -l "$AUDIT" >/dev/null 2>&1
   ./disk_monitor.sh -p / -t 80 --notify none -l "$AUDIT" >/dev/null 2>&1
   wc -l < "$AUDIT"
   ```

   The result is `2`: one line per run, appended. Then point the log at a **directory** and run
   again — the module reports the problem on stderr and still exits `0`:

   ```bash
   rm -f "$AUDIT"; mkdir -p "$AUDIT"
   ./disk_monitor.sh -p / -t 80 --notify none -l "$AUDIT"
   echo "exit=$?"
   ```

   The report ends with:

   ```text
   Audit Log File    : /tmp/lab2_disk/append.log
   Disk usage is within the threshold.
   ./disk_monitor.sh: line 208: /tmp/lab2_disk/append.log: Is a directory
   exit=0
   ```

---

## 📎 Related Documents

- [Lab 1 — Measure, Compare & Rehearse](LAB1_THRESHOLD_AND_DRY_RUN.md) — the measurement and the threshold boundary.
- [SCENARIOS.md](../SCENARIOS.md) — the operational failure modes and their exit codes.
- [`../../README.md`](../../README.md) — usage, flags and troubleshooting.

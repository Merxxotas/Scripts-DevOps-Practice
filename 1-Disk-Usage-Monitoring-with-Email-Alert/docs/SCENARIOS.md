# Disk Usage Monitor — Real-World Production Scenarios 🚀

A disk that fills at 03:00 takes the database with it. The Disk Usage Monitor exists to turn that
silent failure into an alert you can act on — an email, a phone notification, or a message in a team
channel. This document walks through the situations an operator actually meets, and states the
**exit code** each one produces, because that is what a scheduler, a CI step or a wrapper script
reacts to.

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
8. [Scenario 8: A Phone Alert with ntfy](#scenario-8-a-phone-alert-with-ntfy)
9. [Scenario 9: A Team Chat Message with Telegram](#scenario-9-a-team-chat-message-with-telegram)
10. [Scenario 10: A Discord Channel](#scenario-10-a-discord-channel)
11. [Scenario 11: A Slack Workspace](#scenario-11-a-slack-workspace)
12. [Scenario 12: A Self-Hosted Receiver](#scenario-12-a-self-hosted-receiver)
13. [Scenario 13: A Doctor-First Deployment Check](#scenario-13-a-doctor-first-deployment-check)
14. [Scenario 14: A Cron Job That Reads the Configuration File](#scenario-14-a-cron-job-that-reads-the-configuration-file)

---

## 📎 The Exit-Code Contract at a Glance

| Code | Meaning | Triggered by |
| :--: | :--- | :--- |
| `0` | Success | The check ran; the alert was delivered, not needed, or deliberately suppressed. |
| `1` | Configuration / safety error | Unknown flag, threshold outside 1–100, missing partition, unset recipient, missing endpoint, invalid URL, timeout, method or header, unresolvable mail agent, HTTP client or measurement command. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent or the HTTP client. |

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
./disk_monitor.sh: line 208: /etc/disk-monitor/audit.log: No such file or directory
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

## 🧰 Before the Transport Scenarios

Scenarios 8 to 11 and 14 use one recording client. It accepts the module's contract, prints the
request shape and delivers nothing, so no request leaves the machine. It never echoes a header
value.

```bash
mkdir -p /tmp/scenarios_disk
cat > /tmp/scenarios_disk/recording-http-client.sh <<'EOF'
#!/bin/bash
# A stand-in for the HTTP client: records the request and delivers nothing.
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
chmod +x /tmp/scenarios_disk/recording-http-client.sh
```

---

## Scenario 8: A Phone Alert with ntfy

### Problem

The operator is on call and does not want the alert in an inbox that nobody reads after 18:00. The
host has no MTA, and no mail credential should be stored on it.

### What the module does

`--notify http` composes one request and hands it to an external HTTP client. ntfy accepts a JSON
body with a topic and a message, and a `Title` header that becomes the notification title.

```bash
NTFY='{"topic":"disk-alerts-example","message":"Disk on {host} at {usage}"}'

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --notify http --url https://ntfy.sh/disk-alerts-example \
    --body-template "$NTFY" --header 'Title: Disk alert' \
    --header 'Authorization: Bearer S3CRET-TOKEN' \
    --http-command /tmp/scenarios_disk/recording-http-client.sh
```

### Observed behaviour

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://ntfy.sh/disk-alerts-example
HTTP Client       : /tmp/scenarios_disk/recording-http-client.sh
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
method  : POST
timeout : 10
headers : 2 ( Title Authorization)
url     : https://ntfy.sh/disk-alerts-example
--- body on stdin ---
{"topic":"disk-alerts-example","message":"Disk on cachy-os at 91%"}
Alert sent to https://ntfy.sh/disk-alerts-example
```

**Exit code: `0`.** The recording client accepted the request; in production the same command with
the real `curl` reaches the topic.

### Operational note

- **The topic name is the address.** Anyone who knows it can read and publish to it. Use a long,
  unguessable topic, or a reserved topic with `Authorization: Bearer <token>`.
- **The header value is not printed.** The report shows the count and the source only; the audit log
  never holds the token.
- **The plain-text body works too.** Omit `--body-template` and the module sends its default
  message; ntfy uses the body as the message and the subject as the title.

---

## Scenario 9: A Team Chat Message with Telegram

### Problem

The team already coordinates in Telegram, and the alert should arrive where the conversation is
already happening.

### What the module does

Telegram's Bot API takes a JSON body at
`https://api.telegram.org/bot<token>/sendMessage`, with `chat_id` and `text`. The same HTTP
transport sends it; only the template and the URL change.

```bash
TG='{"chat_id":"123456789","text":"Disk {partition} at {usage}"}'

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --notify http --url 'https://api.telegram.org/botEXAMPLE-TOKEN/sendMessage' \
    --body-template "$TG" --header 'Content-Type: application/json' \
    --http-command /tmp/scenarios_disk/recording-http-client.sh
```

### Observed behaviour

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://api.telegram.org/botEXAMPLE-TOKEN/sendMessage
HTTP Client       : /tmp/scenarios_disk/recording-http-client.sh
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
method  : POST
timeout : 10
headers : 1 ( Content-Type)
url     : https://api.telegram.org/botEXAMPLE-TOKEN/sendMessage
--- body on stdin ---
{"chat_id":"123456789","text":"Disk / at 91%"}
Alert sent to https://api.telegram.org/botEXAMPLE-TOKEN/sendMessage
```

**Exit code: `0`.**

### Operational note

- **`Content-Type` is not optional here.** `curl --data-binary` sends
  `application/x-www-form-urlencoded` by default. Telegram, Discord and Slack all parse a JSON body
  and need `--header 'Content-Type: application/json'`. This is the most common reason a request
  that "looks right" is rejected.
- **The bot token is in the URL, and the URL is printed and logged.** The doctor and the audit line
  both name the endpoint, so the token is durable in the audit log. Treat that file as sensitive, or
  use a receiver that authenticates with a header instead.
- **`chat_id` is not secret, the token is.** Keep the token in the configuration file, mode `600`.

---

## Scenario 10: A Discord Channel

### Problem

The operations channel is on Discord, and the team wants the disk warning beside the deploy
messages.

### What the module does

A Discord incoming webhook accepts `{"content": "..."}` at its webhook URL. One HTTP request, no
provider code.

```bash
DC='{"content":"Disk usage on {host} is {usage} (threshold {threshold})"}'

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --notify http --url 'https://discord.com/api/webhooks/EXAMPLE/TOKEN' \
    --body-template "$DC" --header 'Content-Type: application/json' \
    --http-command /tmp/scenarios_disk/recording-http-client.sh
```

### Observed behaviour

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://discord.com/api/webhooks/EXAMPLE/TOKEN
HTTP Client       : /tmp/scenarios_disk/recording-http-client.sh
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
method  : POST
timeout : 10
headers : 1 ( Content-Type)
url     : https://discord.com/api/webhooks/EXAMPLE/TOKEN
--- body on stdin ---
{"content":"Disk usage on cachy-os is 91% (threshold 80%)"}
Alert sent to https://discord.com/api/webhooks/EXAMPLE/TOKEN
```

**Exit code: `0`.**

### Operational note

- **The webhook URL is the credential.** It is printed in the report and written to the audit log.
  Anyone with the URL can post to the channel. Rotate the webhook if the log leaves the host.
- **Discord rejects a body over 2,000 characters.** The default message is far below that; a
  template that repeats `{body}` several times may not be.

---

## Scenario 11: A Slack Workspace

### Problem

The platform team lives in Slack and wants the alert in `#ops-alerts`.

### What the module does

A Slack incoming webhook accepts `{"text": "..."}`. The transport does not know it is Slack.

```bash
SL='{"text":"Disk usage on {host} is {usage} (threshold {threshold})"}'

DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --notify http --url 'https://hooks.slack.com/services/EXAMPLE/TOKEN' \
    --body-template "$SL" --header 'Content-Type: application/json' \
    --http-command /tmp/scenarios_disk/recording-http-client.sh
```

### Observed behaviour

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://hooks.slack.com/services/EXAMPLE/TOKEN
HTTP Client       : /tmp/scenarios_disk/recording-http-client.sh
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
method  : POST
timeout : 10
headers : 1 ( Content-Type)
url     : https://hooks.slack.com/services/EXAMPLE/TOKEN
--- body on stdin ---
{"text":"Disk usage on cachy-os is 91% (threshold 80%)"}
Alert sent to https://hooks.slack.com/services/EXAMPLE/TOKEN
```

**Exit code: `0`.**

### Operational note

The webhook URL is a secret, as on Discord, and it is logged. Slack's free plan is enough for an
incoming webhook; no paid tier is required.

---

## Scenario 12: A Self-Hosted Receiver

### Problem

The operator does not want a third party to see the hostnames and disk percentages, and already
runs a small service on the network. The alert should go there.

### What the module does

Any URL that accepts a POST is a valid endpoint. This run uses a one-shot receiver on
`127.0.0.1` and the **real** client, `curl`, so the whole path is exercised: resolve the client,
render the body, send the request, read the status.

```bash
cat > /tmp/scenarios_disk/receiver.py <<'EOF'
"""A one-shot HTTP receiver: print the request, answer 204, exit."""
import http.server
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        print("method :", self.command)
        print("path   :", self.path)
        print("body   :", self.rfile.read(length).decode("utf-8", "replace"))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).handle_request()
EOF

python3 /tmp/scenarios_disk/receiver.py 8081 &
DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh -p / -t 80 \
    --notify http --url http://127.0.0.1:8081/alert \
    --body-template '{"text":"Disk on {host} at {usage}"}' \
    --header 'Content-Type: application/json'
wait
```

### Observed behaviour

The monitor:

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : http://127.0.0.1:8081/alert
HTTP Client       : /usr/bin/curl
Execution Mode    : LIVE (Alerts Active)
WARNING: Disk usage exceeds the threshold.
Alert sent to http://127.0.0.1:8081/alert
```

The receiver:

```text
method : POST
path   : /alert
body   : {"text":"Disk on cachy-os at 91%"}
```

**Exit code: `0`.** `curl` reports success for the `204` answer, so the module treats the hand-off
as delivered. The client path here is `/usr/bin/curl`, resolved from `PATH` because no
`--http-command` was given.

### Operational note

- **A 4xx or 5xx is a transport failure.** The module calls `curl` with `--fail`, so an HTTP error
  status is a non-zero client exit: the module reports `Error: The alert could not be handed to the
  HTTP client.`, exits `2`, and the audit line says `FAILED`. The response body is not printed; the
  `curl:` line carries the status.
- **Put the receiver behind TLS** if it is not on loopback. The header is a plain-text credential
  otherwise, and so is the body.
- **The receiver is the durable side.** If it is down, the alert is lost after the client's timeout;
  the audit log is the only local record.

---

## Scenario 13: A Doctor-First Deployment Check

### Problem

A deployment script is about to write a cron entry. It should stop if the alerting path cannot work,
rather than discover that at 03:00.

### What the module does

`--doctor` resolves every setting, reports the source of each value, checks that the measurement
command and the transport client exist, and measures nothing and sends nothing. It exits `0` when
the tool is ready and `1` when something is missing.

```bash
cat > /tmp/scenarios_disk/disk-monitor.conf <<'EOF'
partition = /
threshold = 80
notify = http
url = https://ntfy.sh/disk-alerts-example
body_template = {"topic":"disk-alerts-example","message":"Disk on {host} at {usage}"}
header = Title: Disk alert
header = Authorization: Bearer S3CRET-TOKEN
timeout = 10
log_file = /var/log/disk-monitor/audit.log
EOF
chmod 600 /tmp/scenarios_disk/disk-monitor.conf

./disk_monitor.sh --config /tmp/scenarios_disk/disk-monitor.conf --doctor
```

### Observed behaviour

```text
============================================================
                 Disk Usage Monitor - Doctor
============================================================
Platform            : Linux (cachyos)
Config file         : /tmp/scenarios_disk/disk-monitor.conf
Partition           : / (config)
Threshold           : 80% (config)
Notify backend      : http (config)
Endpoint            : https://ntfy.sh/disk-alerts-example (config)
Recipient           : (not required)
HTTP client         : /usr/bin/curl (default)
Mail agent          : (not required)
Measurement command : /usr/bin/df (default)
Audit log file      : /var/log/disk-monitor/audit.log (config)
HTTP headers        : 2 (config)
------------------------------------------------------------
Status              : READY
```

**Exit code: `0`.** The header values never appear: the report says there are two, and where they
came from.

Remove the `url` key and ask again:

```bash
printf 'notify = http\npartition = /\nthreshold = 80\n' > /tmp/scenarios_disk/broken.conf
chmod 600 /tmp/scenarios_disk/broken.conf
./disk_monitor.sh --config /tmp/scenarios_disk/broken.conf --doctor
```

```text
============================================================
                 Disk Usage Monitor - Doctor
============================================================
Platform            : Linux (cachyos)
Config file         : /tmp/scenarios_disk/broken.conf
Partition           : / (config)
Threshold           : 80% (config)
Notify backend      : http (config)
Endpoint            : (not set)
Recipient           : (not required)
HTTP client         : /usr/bin/curl (default)
Mail agent          : (not required)
Measurement command : /usr/bin/df (default)
Audit log file      : (not set)
HTTP headers        : 0 (default)
------------------------------------------------------------
Status              : NOT READY
  - No endpoint is configured. Set --url, or DISK_MONITOR_URL, or the 'url' key in the configuration file.
```

**Exit code: `1`.** A deployment script can treat that as "do not write the cron entry".

### Operational note

The platform line and the resolved paths are machine-dependent: this run was on `Linux (cachyos)`
with `/usr/bin/curl` and `/usr/bin/df`. Elsewhere the distribution name and the paths differ; the
verdict does not.

---

## Scenario 14: A Cron Job That Reads the Configuration File

### Problem

The cron entry has grown a long command line: partition, threshold, recipient, client. One value is
changed in one place and the others drift. The deployment should carry **no flags** beyond the
configuration path.

### The configuration file

`/etc/disk-monitor/disk-monitor.conf`, owned by root, mode `600`:

```ini
# /etc/disk-monitor/disk-monitor.conf
partition = /
threshold = 80
notify = http
url = https://ntfy.sh/disk-alerts-example
body_template = {"topic":"disk-alerts-example","message":"Disk on {host} at {usage}"}
header = Title: Disk alert
header = Authorization: Bearer S3CRET-TOKEN
timeout = 10
log_file = /var/log/disk-monitor/audit.log
```

### The cron entry

`/etc/cron.d/disk-monitor`:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

17 7 * * * root /usr/local/bin/disk-monitor --config /etc/disk-monitor/disk-monitor.conf
```

### Observed behaviour

Rehearsed locally with the recording client and a forced percentage, because this host is not full.
The local copy of the file points the audit log at a writable path and omits the token:

```bash
cat > /tmp/scenarios_disk/cron.conf <<'EOF'
partition = /
threshold = 80
notify = http
url = https://ntfy.sh/disk-alerts-example
body_template = {"topic":"disk-alerts-example","message":"Disk on {host} at {usage}"}
header = Title: Disk alert
timeout = 10
log_file = /tmp/scenarios_disk/audit.log
EOF
chmod 600 /tmp/scenarios_disk/cron.conf

DISK_MONITOR_USAGE_OVERRIDE=91 \
DISK_MONITOR_HTTP_COMMAND=/tmp/scenarios_disk/recording-http-client.sh \
    ./disk_monitor.sh --config /tmp/scenarios_disk/cron.conf
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : https://ntfy.sh/disk-alerts-example
HTTP Client       : /tmp/scenarios_disk/recording-http-client.sh
Execution Mode    : LIVE (Alerts Active)
Audit Log File    : /tmp/scenarios_disk/audit.log
WARNING: Disk usage exceeds the threshold.
method  : POST
timeout : 10
headers : 1 ( Title)
url     : https://ntfy.sh/disk-alerts-example
--- body on stdin ---
{"topic":"disk-alerts-example","message":"Disk on cachy-os at 91%"}
Alert sent to https://ntfy.sh/disk-alerts-example
```

The audit line:

```text
2026-10-22T17:51:18Z [INFO] ALERT SENT to https://ntfy.sh/disk-alerts-example (Usage: 91%, Source: overridden, Threshold: 80%)
```

**Exit code: `0`.** Every setting except the client came from the file; the command line carried
one flag, `--config`.

### Operational note

- **The configuration path is resolved in a fixed order:** `--config` → `DISK_MONITOR_CONFIG` →
  `./.diskmonitor.conf` → `~/.config/disk-monitor/config`. An explicit `--config` that does not
  exist is a configuration error, exit `1`; an absent default file is not an error.
- **Cron ignores the exit code.** The audit log is the durable record; wrap the call with
  `|| logger -t disk-monitor "monitor failed with exit code $?"` if you need syslog to see it.
- **`DISK_MONITOR_USAGE_OVERRIDE` is a rehearsal device.** It is in the command above so the alert
  path runs on a host that is not full. It must not appear in the cron entry.
- **The configuration file is sensitive.** It holds the bearer token, so it is mode `600`, owned by
  root, and git-ignored. The doctor warns if other users can read it.

---

## 📎 Related Documents

- [ARCHITECTURE_COMPARISON.md](ARCHITECTURE_COMPARISON.md) — where the two implementations agree and where they differ.
- [Lab 2 — Exit Codes & Audit Log](labs/LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — reproduce every exit code in this document.
- [Lab 3 — Production Deployment with the Universal Transport](labs/LAB3_PRODUCTION_DEPLOYMENT_ON_A_VPS_RELAY.md) — HTTP as the primary path, a relay as the migration path.
- [`../README.md`](../README.md) — usage, flags and troubleshooting.

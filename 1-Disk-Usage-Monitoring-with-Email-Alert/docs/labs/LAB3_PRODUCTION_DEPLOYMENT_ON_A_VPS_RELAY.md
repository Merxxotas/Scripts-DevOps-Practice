# Lab 3: Production Deployment with the Universal Transport 🚀

## Objective

Deploy the Disk Usage Monitor the way it runs in production: the module on an Ubuntu server,
scheduled by `cron`, with its settings in a root-only configuration file and its alerts handed to
an **HTTP endpoint** by `curl`. Then check the same deployment with the module's own `--doctor`
command, rehearse the exact production command line on your workstation, and keep the mail relay
as a **migration path** for a host that must still send email.

Two ideas carry the lab:

- **The transport is configuration, not code.** `--notify http` and `--notify mail` select the same
  hand-off; the module never opens a socket and never holds a credential.
- **A deployment you cannot inspect is a deployment you cannot trust.** `--doctor` reports every
  resolved value, where it came from, and what is missing — before `cron` is allowed to run it.

---

## 📋 Prerequisites

| Requirement | Notes |
| :--- | :--- |
| An Ubuntu server (the reference target is an **Oracle Cloud VPS**, Ubuntu, `aarch64`) | `uname -m` prints `aarch64`. The module is architecture-neutral: it runs `df -P` and `curl`. |
| Root access | `sudo` for the configuration, the installed script and the cron entry. |
| An HTTP endpoint that accepts a `POST` | An `ntfy` topic, a self-hosted receiver, or a Telegram, Discord or Slack webhook. |
| `curl` | Installed by default on Ubuntu and the module's default HTTP client. |
| `python3` **on your workstation** | Only for the local receiver in Step 6. Not needed on the VPS. |
| A recipient address and an SMTP relay | Only for the migration path in Step 10. |

> **Step 6 rehearses the production command line on your workstation** against a receiver on
> `127.0.0.1`, so nothing in this lab posts to a third party until you decide to.

---

## Step 1: Why the Transport Decides the Deployment

A hosted VPS often cannot send mail directly. **Oracle Cloud blocks outbound TCP port 25 by default
for tenancies created after 2021-06-23**, and the block has three properties that shape any
email-based deployment:

| Property | Consequence |
| :--- | :--- |
| It applies to **all outbound SMTP**, not to one destination. | Installing Postfix or `sendmail` and pointing it at a remote MX server does not work. |
| It **cannot be lifted from the VCN security list**. | The security list governs traffic to instances; an egress rule for port 25 does not override it. |
| Lifting it needs an **Oracle Support request**, and free-tier accounts are often declined. | Treat it as permanent. Do not plan around it. |

An HTTP endpoint sidesteps all of it: outbound `443` is the same path `apt-get` already uses, and no
port is special. No SMTP credential and no signing key lives on the host — at most an HTTP token
does, in the same root-only file.

| Path | What leaves the host | What lives on the host | When to choose it |
| :--- | :--- | :--- | :--- |
| **HTTP** (this lab's primary path) | One HTTPS `POST` with a rendered body | The endpoint, and possibly a bearer token in a header | Default. Works behind the port-25 block and needs no relay. |
| **Mail relay** (Step 10) | SMTP submission on `587` to a provider | The relay password, in a root-only file | An existing relay, a provider that only speaks email, or a compliance trail in an inbox. |

What changes between them is **configuration only**. The script, the exit codes, the audit format
and the threshold logic are identical.

---

## Step 2: The Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│ Oracle Cloud VPS — Ubuntu, aarch64                               │
│                                                                  │
│  cron (07:17 daily)                                              │
│    └── /usr/local/bin/disk-monitor                               │
│          ├── /etc/disk-monitor/disk-monitor.conf  (root, 600)    │
│          ├── df -P /            → the measurement                │
│          └── curl ... --data-binary @- <endpoint>                │
│                └── HTTPS :443  → ntfy / receiver / webhook       │
│                                                                  │
│  audit log: /var/log/disk-monitor/audit.log                      │
└──────────────────────────────────────────────────────────────────┘
```

The command line carries **no flags and no token**: everything comes from the configuration file,
which `cron` names in one environment variable. That keeps the secret out of `ps` and keeps the
schedule readable.

---

## Step 3: Install the Script

Nothing extra is needed for HTTP. Confirm the client is there (on the VPS):

```bash
command -v curl
```

Ubuntu images usually have `curl`; if `command -v` prints nothing, install it. The module resolves
the client by name, so an absolute path in the configuration is only needed when the client is not
on `cron`'s `PATH`, or when several clients are installed.

Copy the script to `/usr/local/bin/disk-monitor` and make it executable:

```bash
sudo install -o root -g root -m 755 disk_monitor.sh /usr/local/bin/disk-monitor
```

Check the line endings before you trust it. A script with CRLF endings has a shebang of
`/bin/bash\r` and **cannot execute at all** — the error is `bad interpreter`:

```bash
file disk_monitor.sh
```

```text
disk_monitor.sh: Bourne-Again shell script, ASCII text executable
```

The installed copy must report the same thing. A `with CRLF line terminators` suffix in that
output means the file cannot run.

---

## Step 4: Put the Endpoint in a Configuration File

A cron line is read by humans and visible in `ps`; a token in it leaks twice. Put every setting in
one file instead, owned by root and readable only by root.

### 4.1 Create the file

```bash
sudo install -d -o root -g root -m 700 /etc/disk-monitor
sudo install -o root -g root -m 600 /dev/null /etc/disk-monitor/disk-monitor.conf
sudo tee /etc/disk-monitor/disk-monitor.conf >/dev/null <<'EOF'
# /etc/disk-monitor/disk-monitor.conf
partition = /
threshold = 80
notify = http
url = https://ntfy.sh/disk-alerts-example
body_template = {"topic":"disk-alerts-example","message":"Disk on {host} at {usage}"}
header = Content-Type: application/json
header = Title: Disk alert
header = Authorization: Bearer S3CRET-TOKEN
timeout = 10
log_file = /var/log/disk-monitor/audit.log
EOF
```

Replace the endpoint and `S3CRET-TOKEN` with your own. An `ntfy` topic needs no credential — drop
the `Authorization` line for a public topic. Telegram, Discord and Slack webhooks carry their
token **in the URL**, which Section 4.4 explains how to treat.

### 4.2 The format

A line is `key = value`; the key ends at the **first** `=`, so a value may contain more. A line
starting with `#` is a comment. A value may be wrapped in single or double quotes to protect
leading or trailing spaces. A malformed line is reported by number and never echoed — it may hold
a token pasted by mistake.

| Key | Meaning |
| :--- | :--- |
| `partition` | Mount point to watch. |
| `threshold` | Alert when usage is strictly greater. |
| `notify` | `none`, `mail` or `http`. Selects exactly one transport. |
| `url` | Endpoint for `http`. |
| `body_template` | Request body; placeholders below. |
| `header` | One `Name: value`. Repeat the key for several headers. |
| `timeout` | Whole seconds for the request; default `10`. |
| `method` | HTTP method; default `POST`. Configuration file only. |
| `log_file` | Audit log path. |
| `to` | Recipient, for `mail`. |
| `mail_command` | Mail agent, for `mail`. |
| `usage_command` | Measurement command; default `df`. |
| `usage_override` | Forced percentage. Labs and tests only. |

An environment variable beats the file, and a flag beats both: **flag > environment > file >
default**. Use the file for the deployment, and a flag only for a one-off override.

### 4.3 The body template

The template is the request body, so a JSON document speaks to every service that accepts JSON.
The placeholders are `{subject}`, `{body}`, `{partition}`, `{usage}`, `{threshold}`, `{recipient}`,
`{host}` and `{timestamp}`. In HTTP mode `{recipient}` is the endpoint, and `{usage}` and
`{threshold}` already carry the percent sign — the example above posts `91%`, not `91`.

`curl --data-binary` sends the body **without a JSON content type**. Without the explicit
`Content-Type: application/json` header, many services either reject the request or parse the body
as form data and deliver an empty message. That header is not optional for a JSON template.

### 4.4 What the endpoint exposes, and what it does not

The module is honest about its limits, and so is this lab:

- A **header value** is never printed and never written to the audit log. That is why the token
  belongs in `Authorization`.
- The **endpoint is printed and audited**, because the audit line names where the alert went. A
  webhook URL that embeds its token therefore ends up in the audit log. Restrict the log's
  permissions like any other secret, or front the webhook with a proxy.
- While the client runs, a header value is visible in its **argument list** on the host. The
  module does not write a temporary file to hide it; `curl` receives it as an argument.

At rest, the configuration file is the only place the credential is configured. Keep it at `600`:

```bash
stat -c '%a %U:%G %n' /etc/disk-monitor/disk-monitor.conf
```

On the VPS, it reads:

```text
600 root root /etc/disk-monitor/disk-monitor.conf
```

> **Nothing in this section belongs in the repository.** Not the host, not the endpoint, not the
> token. The module holds no credentials and opens no socket; `curl` does, with what the caller
> supplies.

---

## Step 5: Doctor Before You Schedule

`--doctor` is the deployment's preflight. It reads and resolves every setting, reports where each
value came from, checks that the measurement command and the HTTP client exist, and lists every
missing item with its remedy — the install command for the platform it was found on, and the
setting that can replace the tool. **It measures nothing and sends nothing.**

Run it on the VPS before the cron entry exists:

```bash
sudo /usr/local/bin/disk-monitor --config /etc/disk-monitor/disk-monitor.conf --doctor
echo "exit=$?"
```

The rehearsal in Step 6 runs the same command against the same file shape. Its exact output on the
reference workstation was:

```text
============================================================
                 Disk Usage Monitor - Doctor
============================================================
Platform            : Linux (cachyos)
Config file         : /tmp/lab3_prod/disk-monitor.conf
Partition           : / (config)
Threshold           : 80% (config)
Notify backend      : http (config)
Endpoint            : https://ntfy.sh/disk-alerts-example (config)
Recipient           : (not required)
HTTP client         : /usr/bin/curl (default)
Mail agent          : (not required)
Measurement command : /usr/bin/df (default)
Audit log file      : /var/log/disk-monitor/audit.log (config)
HTTP headers        : 3 (config)
------------------------------------------------------------
Status              : READY
exit=0
```

Read it in three parts:

| Part | What it proves |
| :--- | :--- |
| The parenthesised **source** | `(config)`, `(flag)`, `(environment)` or `(default)`. A value you thought you set, showing `(default)`, is a typo in the file. |
| **HTTP headers** | The **count**, never the values. `3` here means the three `header` lines were parsed. |
| **Status** | `READY` with exit `0`, or `NOT READY` with exit `1` and one `-` line per problem, each naming its fix. |

`READY` proves the deployment is resolvable, not that the endpoint accepts your request. That is
what the first live alert in Step 7 is for.

---

## Step 6: Rehearse the Production Command Line Locally

Do this on your workstation, in the module directory. The receiver is a one-shot HTTP server on
`127.0.0.1`; the module talks to it with the same `/usr/bin/curl` the VPS will use.

### 6.1 Create the rehearsal configuration

```bash
LAB=/tmp/lab3_prod
mkdir -p "$LAB/log" "$LAB/home"

cat > "$LAB/disk-monitor.conf" <<'EOF'
# /etc/disk-monitor/disk-monitor.conf
partition = /
threshold = 80
notify = http
url = https://ntfy.sh/disk-alerts-example
body_template = {"topic":"disk-alerts-example","message":"Disk on {host} at {usage}"}
header = Content-Type: application/json
header = Title: Disk alert
header = Authorization: Bearer S3CRET-TOKEN
timeout = 10
log_file = /var/log/disk-monitor/audit.log
EOF
chmod 600 "$LAB/disk-monitor.conf"
```

This is the production file, byte for byte. The rehearsal overrides two things on the command line:
the endpoint and the audit log, because `/var/log` needs root.

### 6.2 Run the doctor

```bash
HOME="$LAB/home" ./disk_monitor.sh --config "$LAB/disk-monitor.conf" --doctor
echo "exit=$?"
```

The output is the `READY` block shown in Step 5, with `/tmp/lab3_prod/disk-monitor.conf` as
the config path.

### 6.3 Start a receiver

```bash
cat > "$LAB/receiver.py" <<'EOF'
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

python3 "$LAB/receiver.py" 8082 > "$LAB/receiver.out" &
sleep 1
```

### 6.4 Run the production command line

`DISK_MONITOR_USAGE_OVERRIDE=91` forces a breach on a host that is not full, so the alert path can
be exercised:

```bash
HOME="$LAB/home" DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh --config "$LAB/disk-monitor.conf" \
    --url http://127.0.0.1:8082/alert --log-file "$LAB/log/audit.log"
echo "exit=$?"
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Endpoint          : http://127.0.0.1:8082/alert
HTTP Client       : /usr/bin/curl
Execution Mode    : LIVE (Alerts Active)
Audit Log File    : /tmp/lab3_prod/log/audit.log
WARNING: Disk usage exceeds the threshold.
Alert sent to http://127.0.0.1:8082/alert
exit=0
```

The receiver prints what actually arrived:

```bash
cat "$LAB/receiver.out"
```

```text
method : POST
path   : /alert
body   : {"topic":"disk-alerts-example","message":"Disk on cachy-os at 91%"}
```

The token, the `Title` header and the JSON content type were all sent; the receiver only prints
the body. The hostname in the body is the machine's, so yours will differ. The audit log records
the hand-off:

```bash
cat "$LAB/log/audit.log"
```

```text
2026-10-22T18:00:01Z [INFO] ALERT SENT to http://127.0.0.1:8082/alert (Usage: 91%, Source: overridden, Threshold: 80%)
```

`Source: overridden` is the module refusing to let a forced value masquerade as a measurement.
**Remove `DISK_MONITOR_USAGE_OVERRIDE` before going live.**

### 6.5 Break it on purpose

Point the same command at a closed port:

```bash
HOME="$LAB/home" DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh --config "$LAB/disk-monitor.conf" \
    --url http://127.0.0.1:9/alert --timeout 2 --log-file "$LAB/log/audit.log"
echo "exit=$?"
```

The report ends with:

```text
WARNING: Disk usage exceeds the threshold.
curl: (7) Failed to connect to 127.0.0.1:9 after 0 ms: Could not connect to server
Error: The alert could not be handed to the HTTP client.
exit=2
```

The measurement succeeded and the hand-off did not, so the exit code is `2` — a partial failure,
exactly as the exit-code contract says. The audit log keeps the `ERROR` line, which is the only
record `cron` will leave behind:

```text
2026-10-22T18:00:10Z [ERROR] FAILED to hand the alert to the HTTP client (Usage: 91%, Source: overridden)
```

The text after `curl: (7)` comes from your `curl` build, so the wording may differ; the exit code
and the `Error:` line will not.

### 6.6 Prove that an error status is a failed hand-off

The module asks `curl` for `--fail`, so an HTTP error status is a non-zero client exit and the
hand-off fails like any other. A receiver that answers `401`:

```bash
cat > "$LAB/reject.py" <<'EOF'
import http.server
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(401)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"unauthorized\n")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).handle_request()
EOF

python3 "$LAB/reject.py" 8084 &
sleep 1

HOME="$LAB/home" DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh --config "$LAB/disk-monitor.conf" \
    --url http://127.0.0.1:8084/alert --log-file "$LAB/log/audit.log"
echo "exit=$?"
```

The report ends with:

```text
WARNING: Disk usage exceeds the threshold.
curl: (22) The requested URL returned error: 401
Error: The alert could not be handed to the HTTP client.
exit=2
```

The client refused the response, so the module reports the failed hand-off and the audit line says
so:

```text
2026-10-22T18:13:14Z [ERROR] FAILED to hand the alert to the HTTP client (Usage: 91%, Source: overridden)
```

Nothing says `ALERT SENT`, because nothing was delivered. Without `--fail` the client would have
exited `0` for that same `401` and the durable record would have claimed a delivery that the service
rejected — which is the one failure a disk monitor cannot afford to report as success.

**Exit `2` means the request was attempted and the service did not accept it.** The exit code alone
does not tell you whether the endpoint, the credential or the routing is wrong; the status in the
`curl:` line and the provider's own log do. That is why the first live alert in Step 7 still matters:
it is the only check that the whole path delivers.

### 6.7 Prove the header stayed out of the log

The token travelled in a header, and the audit line names the endpoint:

```bash
grep -c 'S3CRET-TOKEN' "$LAB/log/audit.log"
grep -c 'http://127.0.0.1:8082/alert' "$LAB/log/audit.log"
```

```text
0
1
```

`grep -c` exits non-zero when the count is zero; that is `grep` reporting "no match", not a failed
command. The count is the point: the token is in the request and nowhere in the durable record.

### 6.8 Clean up the rehearsal

```bash
rm -rf "$LAB"
```

---

## Step 7: The First Live Alert

On the VPS, with the real endpoint in place, force one alert and watch it arrive. The override goes
through `sudo env`, because `sudo` resets the environment and would otherwise drop it:

```bash
sudo env DISK_MONITOR_USAGE_OVERRIDE=95 \
    /usr/local/bin/disk-monitor --config /etc/disk-monitor/disk-monitor.conf
echo "exit=$?"
```

Expect `Alert sent to <your endpoint>` and exit `0`. The message arrives at the endpoint with the
rendered body — for the example file, `Disk on <hostname> at 95%`. An HTTP error status would have
exited `2` (Step 6.6), so exit `0` here means the service accepted the request; confirm the message
at the endpoint or in the provider's delivery log anyway.

Then remove the override and run it for real:

```bash
sudo /usr/local/bin/disk-monitor --config /etc/disk-monitor/disk-monitor.conf
```

Read the log the cron job will keep appending to:

```bash
sudo tail -n 20 /var/log/disk-monitor/audit.log
```

The line reads `Usage within threshold (Usage: <n>%, Source: measured, Threshold: 80%)`. The
percentage is this host's, not a fixed number.

> The module creates `/var/log/disk-monitor` if it is missing, but a log that cannot be written is
> **not** a fatal error: the run still exits `0`, and the shell prints its own redirect error. Run
> the module once by hand and confirm the file exists before you rely on it. A monitor with no
> audit trail is a monitor you cannot question later.

---

## Step 8: The Cron Entry

`/etc/cron.d/disk-monitor`:

```bash
sudo tee /etc/cron.d/disk-monitor >/dev/null <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DISK_MONITOR_CONFIG=/etc/disk-monitor/disk-monitor.conf

17 7 * * * root /usr/local/bin/disk-monitor
EOF
```

The job line carries **no arguments at all**. Four decisions in that file, each of them
load-bearing:

| Decision | Why |
| :--- | :--- |
| `DISK_MONITOR_CONFIG=...` | The path is absolute. `cron` gives the job this variable, the module reads the file, and the flags never appear in `ps`. |
| The empty line before the job | `/etc/cron.d` applies variable assignments to every entry below them; the blank line is for readability only. |
| `PATH=` is set explicitly | `cron` starts with a minimal `PATH`. Without it, `df` and `curl` may not be found. |
| No `DISK_MONITOR_USAGE_OVERRIDE` | That variable forces the reported percentage instead of measuring the disk. It exists for labs and tests; in production it would blind the monitor. |

The filename must match Debian's rule for `/etc/cron.d`: letters, digits, underscores and hyphens,
no dot. `disk-monitor` is valid; `disk-monitor.conf` would be ignored. The file must be owned by
root and must not be group- or world-writable, or `cron` skips it.

`cron` **ignores the exit code**, so the audit log is the durable channel. That is why it lives in
the configuration file, not on the command line.

---

## Step 9: Rotate the Audit Log

The audit log grows by one line per run. Rotate it like any other log.

`/etc/logrotate.d/disk-monitor`:

```bash
sudo tee /etc/logrotate.d/disk-monitor >/dev/null <<'EOF'
/var/log/disk-monitor/audit.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

sudo logrotate -d /etc/logrotate.d/disk-monitor
```

`-d` is a dry run: it prints what `logrotate` would do without touching anything.

> `copytruncate` copies the file and then truncates it in place. The module opens the log in
> append mode for each run and closes it immediately, so a rename-and-recreate rotation would also
> be safe — but `copytruncate` removes even the small window in which a line could be written
> between the rename and the recreate.

---

## Step 10: Migration Path — Keep Mail for a While

If the deployment must keep email — an existing relay, a provider that only speaks SMTP, or a
compliance trail in an inbox — the transport changes, and nothing else does. The module still
knows nothing about SMTP: it composes a subject and a body and hands them to
`<mail-command> -s <subject> <recipient>`.

### 10.1 Install `msmtp` on the VPS

```bash
sudo apt-get update
sudo apt-get install -y msmtp
```

> Do **not** install `msmtp-mta`. That package registers `msmtp` as the system's sendmail
> alternative, which would make the host look like a mail server to everything else on it. The
> module calls `msmtp` explicitly; nothing else on the host should be able to send mail.

### 10.2 Configure the relay

Two files, both **root only**, both outside the repository:

```bash
sudo install -o root -g root -m 600 /dev/null /etc/msmtprc
sudo tee /etc/msmtprc >/dev/null <<'EOF'
defaults
logfile /var/log/msmtp.log
tls_trust_file /etc/ssl/certs/ca-certificates.crt

account default : relay.example.com
host relay.example.com
port 587
auth on
tls on
tls_starttls on
from ops@example.com
user relay-user
passwordeval "cat /etc/msmtprc.secrets"
EOF

sudo install -o root -g root -m 600 /dev/null /etc/msmtprc.secrets
sudo tee /etc/msmtprc.secrets >/dev/null <<'EOF'
RELAY_PASSWORD
EOF
```

Replace `RELAY_PASSWORD` with the credential your provider issued, and `relay.example.com` with
its SMTP endpoint. `passwordeval` keeps the secret out of the main configuration file and out of
`msmtp`'s argument list.

Check the relay before you change the monitor — these run **on the VPS**:

```bash
msmtp -C                      # the effective configuration, no connection
msmtp --serverinfo            # a real connection on 587
echo "relay test" | msmtp -s "relay test" you@example.com
```

`msmtp -C` prints the host, port, account and `from` address. `--serverinfo` prints the server's
banner and authentication methods; if it hangs or fails, outbound `587` is blocked too. The third
command delivers a message to an address **you** control; no output means success, and
`/var/log/msmtp.log` records the transaction.

### 10.3 Switch the configuration file

Replace the HTTP block with the mail keys; `notify` selects exactly one transport, so the HTTP
keys are ignored in this mode:

```bash
sudo tee /etc/disk-monitor/disk-monitor.conf >/dev/null <<'EOF'
# /etc/disk-monitor/disk-monitor.conf, mail transport
partition = /
threshold = 80
notify = mail
to = ops@example.com
mail_command = /usr/bin/msmtp
log_file = /var/log/disk-monitor/audit.log
EOF
```

Then run the doctor again. It should report `Notify backend: mail`, a `Recipient`, a `Mail agent`
and `Endpoint: (not required)` — a different set of checks, the same exit contract.

### 10.4 Rehearse the hand-off

The relay is the host's business, so the rehearsal replaces `msmtp` with a stand-in that records
the contract and delivers nothing:

```bash
LAB=/tmp/lab3_prod
mkdir -p "$LAB/home" "$LAB/bin"

cat > "$LAB/bin/msmtp" <<'EOF'
#!/bin/bash
# A stand-in for msmtp. It accepts the module's contract
# (-s <subject> <recipient>, body on stdin) and delivers nothing.
printf 'relay  : relay.example.com:587\n'
printf 'subject: %s\n' "$2"
printf 'to     : %s\n' "$3"
printf 'body   : %s\n' "$(cat)"
EOF
chmod +x "$LAB/bin/msmtp"

cat > "$LAB/mail.conf" <<EOF
partition = /
threshold = 80
notify = mail
to = ops@example.com
mail_command = $LAB/bin/msmtp
log_file = $LAB/log/audit.log
EOF

HOME="$LAB/home" DISK_MONITOR_USAGE_OVERRIDE=91 \
  ./disk_monitor.sh --config "$LAB/mail.conf"
echo "exit=$?"
```

The report ends with the hand-off:

```text
WARNING: Disk usage exceeds the threshold.
relay  : relay.example.com:587
subject: Disk Alert: / at 91%
to     : ops@example.com
body   : Disk usage on cachy-os is at 91% (threshold: 80%).

Partition : /
Usage    : 91%
Threshold: 80%
Time     : 2026-10-22T18:00:15Z
Alert sent to ops@example.com
exit=0
```

The stand-in proves the contract: `-s` receives the subject, the recipient is the third argument,
and the body arrives on standard input. The real `msmtp` receives exactly the same three things.

---

## Step 11: Troubleshooting

| Symptom | Likely cause | What to check |
| :--- | :--- | :--- |
| `Error: Configuration file '...' does not exist.` | The path in `--config` or `DISK_MONITOR_CONFIG` is wrong. | `ls -l` the file; an explicit path must exist. |
| `Error: No endpoint. Use --url, or set DISK_MONITOR_URL.` | `notify = http` with no `url`. | The config key and the config path. `--doctor` names the same problem with the file's remedy. |
| Doctor: `No endpoint is configured.` | Same cause, caught before the measurement. | Add `url`, or set `DISK_MONITOR_URL`. |
| `Error: Notify backend must be 'none', 'mail' or 'http'.` | A backend the module does not have, such as `smtp` or `email`. | There is no SMTP transport; mail means a mail **agent**. Use `mail` with `msmtp`. |
| `Error: The alert could not be handed to the HTTP client.` (exit `2`) | The client could not complete the request: DNS, TLS, a refused connection, a timeout or an HTTP error status. | Run the same `curl` by hand; read the `curl:` line above the error. |
| `curl: (7) Failed to connect` | The endpoint is unreachable or the port is closed. | The URL, the host firewall, and the VCN egress rules. |
| `curl: (22) The requested URL returned error: 401` | The service rejected the request. `curl` was asked to fail, so an error status is a failed hand-off. | The token, the header name, the topic or webhook path, and the provider's log. |
| The endpoint receives a form-encoded body | The JSON content type is missing. | Add `header = Content-Type: application/json`. |
| `Error: No HTTP client found.` | `curl` is not installed, or not on `cron`'s `PATH`. | `command -v curl`; set `PATH=` and `http_command` if needed. |
| The alert never arrives, exit `0` | The endpoint accepted the request and dropped the message, or the recipient is wrong. | The provider's delivery log; the audit line names the endpoint that saw the `POST`. |
| No audit log, and a shell redirect error | The log path is not writable by the user running the module. | Run as root, or point `log_file` at a writable path. A write failure is not fatal. |
| The cron job does not run at all | The file is not in `/etc/cron.d/`, the name contains a dot, or the mode is wrong. | `ls -l /etc/cron.d/disk-monitor`; root-owned, not group- or world-writable. |

---

## ✅ What You Should See

| Check | Expected |
| :--- | :--- |
| `--doctor` with a complete file | `Status: READY`, exit `0`, every value carrying its source. |
| `--doctor` with no endpoint | `Status: NOT READY`, exit `1`, one `-` line naming the missing key. |
| The rehearsal (Step 6) | `Alert sent to http://127.0.0.1:8082/alert`, exit `0`. |
| The receiver | `POST /alert` with the rendered JSON body. |
| The rehearsal audit line | `Source: overridden` — the forced value is labelled. |
| The unreachable endpoint (Step 6.5) | `Error: The alert could not be handed to the HTTP client.`, exit `2`. |
| An HTTP error status (Step 6.6) | `curl: (22) ...`, `Error: The alert could not be handed to the HTTP client.`, exit `2`, `FAILED` in the log. |
| The first live alert (Step 7) | `Alert sent to <endpoint>`, exit `0`, and the message at the endpoint. |
| The real run | `Usage within threshold` and `Source: measured` in the audit log. |
| The mail rehearsal (Step 10.4) | The subject, recipient and body printed by the stand-in, exit `0`. |
| `sudo tail /var/log/disk-monitor/audit.log` | One ISO-8601 line per run. |

---

## 🧪 Try It Yourself

1. **Let the doctor catch a missing endpoint.** With no configuration file in play, ask for the
   HTTP transport and read the verdict:

   ```bash
   ./disk_monitor.sh --notify http --doctor
   echo "exit=$?"
   ```

   The report ends with:

   ```text
   Status              : NOT READY
     - No endpoint is configured. Set --url, or DISK_MONITOR_URL, or the 'url' key in the configuration file.
   exit=1
   ```

   One problem, one remedy, exit `1`. That is the check `cron` will never run for you.

2. **Reject a backend that does not exist.** There is no SMTP transport, and the module says so
   before it measures anything:

   ```bash
   ./disk_monitor.sh --notify smtp
   echo "exit=$?"
   ```

   ```text
   Error: Notify backend must be 'none', 'mail' or 'http'.
   exit=1
   ```

3. **Suppress an alert without losing the record.** `--notify none` is the safe way to exercise
   the alert path on a host you do not want to notify: everything runs, nothing leaves the host,
   and the audit line says so.

   ```bash
   DISK_MONITOR_USAGE_OVERRIDE=91 ./disk_monitor.sh --notify none \
       --log-file /tmp/lab3-none.log
   echo "exit=$?"
   cat /tmp/lab3-none.log
   ```

   The report ends with:

   ```text
   WARNING: Disk usage exceeds the threshold.
   Alert suppressed by --notify none.
   exit=0
   ```

   ```text
   2026-10-22T17:59:17Z [INFO] Alert suppressed by --notify none (Usage: 91%, Source: overridden)
   ```

   Exit `0` means "the check completed and no alert was needed or sent", not "the disk is
   healthy". The audit line is what tells the two apart. Remove `/tmp/lab3-none.log` when done.

---

## 📎 Related Documents

- [SCENARIOS.md](../SCENARIOS.md) — ntfy, Telegram, Discord, Slack, a self-hosted receiver, and
  the doctor-first check.
- [ARCHITECTURE_COMPARISON.md](../ARCHITECTURE_COMPARISON.md) — the shared contract and why the
  transport is a hand-off, not a provider integration.
- [Lab 1 — Measure, Compare & Rehearse](LAB1_THRESHOLD_AND_DRY_RUN.md) — the threshold boundary,
  the dry run, and the precedence ladder.
- [Lab 2 — Exit Codes & Audit Log](LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — every exit code end to end,
  and the header-secrecy experiment.
- [`../../README.md`](../../README.md) — usage, flags, environment variables and troubleshooting.

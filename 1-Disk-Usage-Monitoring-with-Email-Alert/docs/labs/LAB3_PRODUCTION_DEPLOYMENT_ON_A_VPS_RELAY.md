# Lab 3: Production Deployment on a VPS with a Relay 🚀

## Objective

Deploy the Disk Usage Monitor the way it runs in production: the module on an Ubuntu server,
scheduled by `cron`, handing its alert to a **relay** that reaches the recipient — without the
server ever holding a credential that belongs to the repository, and without the deployment
breaking on the Oracle Cloud port-25 block.

---

## 📋 Prerequisites

| Requirement | Notes |
| :--- | :--- |
| An Ubuntu server (the reference target is an **Oracle Cloud VPS**, Ubuntu, `aarch64`) | `uname -m` prints `aarch64`. The module is architecture-neutral: it runs `df -P`. |
| Root access | `sudo` for the configuration and the cron entry. |
| A third-party **transactional email provider** with an SMTP endpoint | The provider's credentials live on the server, never in this repository. |
| `msmtp` | Installed in Step 3. |
| A recipient address | Where the alert should arrive. |

> **Step 8 rehearses the exact production command line on your workstation** with a stand-in relay,
> so nothing in this lab sends a real email before you are ready.

---

## Step 1: Why the Alert Needs a Relay

A hosted VPS cannot usually talk to a mail server directly, and the reason is worth understanding
before you configure anything.

**Oracle Cloud blocks outbound TCP port 25 by default for tenancies created after 2021-06-23.**
That block has three properties that shape this deployment:

| Property | Consequence |
| :--- | :--- |
| It applies to **all outbound SMTP**, not to a specific destination. | Installing Postfix or `sendmail` on the VPS and letting it talk to a remote MX server does not work. |
| It **cannot be lifted from the VCN security list**. | The VCN security list governs inbound traffic to instances; adding an egress rule for port 25 does not override the block. |
| Lifting it requires an **Oracle Support request**, and **free-tier accounts are often declined**. | Treat it as permanent. Do not plan around it. |

**The workaround: relay through a transactional email provider on port 587.**

```text
your server ──► provider SMTP endpoint :587 (STARTTLS) ──► recipient
```

The provider is allowed to send on port 25 from its own infrastructure, and it **signs the message
with DKIM** for you. Your server never talks to port 25 and never holds the DKIM private key.

Two consequences for this module:

1. The host needs an SMTP **client** that speaks submission on 587 — `msmtp` is the natural one.
2. The module still knows nothing about any of this. It composes a message and hands it to
   `<mail-command> -s <subject> <recipient>`. The relay is entirely the host's business.

---

## Step 2: The Architecture

```text
┌──────────────────────────────────────────────────────────────┐
│ Oracle Cloud VPS — Ubuntu, aarch64                           │
│                                                              │
│  cron (07:17 daily)                                          │
│    └── /usr/local/bin/disk-monitor -p / -t 80               │
│          ├── df -P /            → the measurement             │
│          └── msmtp -s <subject> <recipient>                  │
│                └── /etc/msmtprc  (root only, mode 600)       │
│                      └── relay.example.com:587 (STARTTLS)   │
│                            └── provider signs with DKIM      │
│                                  └── recipient               │
│                                                              │
│  audit log: /var/log/disk-monitor/audit.log                  │
└──────────────────────────────────────────────────────────────┘
```

---

## Step 3: Install `msmtp` on the VPS

```bash
sudo apt-get update
sudo apt-get install -y msmtp
```

> Do **not** install `msmtp-mta`. That package registers `msmtp` as the system's sendmail
> alternative, which would make the host look like a mail server to everything else on it. The
> module calls `msmtp` explicitly; nothing else on the host should be able to send mail.

Verify:

```bash
command -v msmtp
```

It prints the absolute path, for example `/usr/bin/msmtp`. Remember it — the cron entry needs the
absolute path, because `cron` has almost no `PATH`.

---

## Step 4: Configure the Relay

Two files, both **root only**, both outside the repository.

### `/etc/msmtprc`

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
```

### `/etc/msmtprc.secrets`

```bash
sudo install -o root -g root -m 600 /dev/null /etc/msmtprc.secrets
sudo tee /etc/msmtprc.secrets >/dev/null <<'EOF'
RELAY_PASSWORD
EOF
```

Replace `RELAY_PASSWORD` with the credential your provider issued, and `relay.example.com` with
your provider's SMTP endpoint. `passwordeval` keeps the secret out of the main configuration file
and out of the process's argument list.

### Check the permissions

```bash
stat -c '%a %U:%G %n' /etc/msmtprc /etc/msmtprc.secrets
```

Both files must read `600 root root`. A relay credential that any local user can read is a
credential that leaks.

> **Nothing in this section belongs in the repository.** Not the host, not the endpoint, not the
> password. The module itself holds no credentials and opens no socket — the relay's
> configuration is the only place a secret exists on the host.

---

## Step 5: Verify the Relay

Run these **on the VPS**.

```bash
msmtp -C
```

`msmtp -C` prints the effective configuration without connecting. Check that the host, the port,
the account and the `from` address are the ones you expect.

Then ask the provider who it is:

```bash
msmtp --serverinfo
```

This performs a real connection and prints the server's banner and supported authentication
methods. If it hangs or fails, the relay is not reachable on port 587 and there is no point
installing the monitor yet.

Finally, send yourself a message through the relay — to an address **you** control, so this is
never an accidental delivery to a third party:

```bash
echo "relay test" | msmtp -s "relay test" you@example.com
```

No output means success. `msmtp` logs the transaction to `/var/log/msmtp.log`; check it if the
message does not arrive.

---

## Step 6: Install the Module on the VPS

Copy `disk_monitor.sh` to `/usr/local/bin/disk-monitor` and make it executable:

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

Run it once, by hand, with the alerting switched off:

```bash
sudo /usr/local/bin/disk-monitor -p / -t 80 --notify none
```

If it prints a report and returns `0`, the measurement works on this host.

---

## Step 7: The Cron Entry

`/etc/cron.d/disk-monitor`:

```bash
sudo tee /etc/cron.d/disk-monitor >/dev/null <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DISK_MONITOR_TO=ops@example.com
DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp

17 7 * * * root /usr/local/bin/disk-monitor -p / -t 80 -l /var/log/disk-monitor/audit.log
EOF
```

Four decisions in that entry, each of them load-bearing:

| Decision | Why |
| :--- | :--- |
| `PATH=` is set explicitly | `cron` starts with a minimal `PATH`. Without it, `df` and `msmtp` may not be found. |
| `DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp` | **Absolute path.** The module's candidate list is `mail`, then `msmtp` — and many Ubuntu images ship a `mail` binary with no working MTA behind it. Pinning the agent removes the guesswork. |
| `DISK_MONITOR_TO=ops@example.com` | The recipient lives in the environment, so the command line and the address cannot drift apart. |
| `-l /var/log/disk-monitor/audit.log` | The audit log is the durable channel. Cron **ignores the exit code**, so this file is how you find out what happened. The module creates the parent directory if it is missing. |

> **Do not set `DISK_MONITOR_USAGE_OVERRIDE` in the cron entry.** That variable forces the reported
> percentage instead of measuring the disk. It exists for labs and tests; in production it would
> blind the monitor.

---

## Step 8: Rehearse the Exact Cron Command Line

Rehearse the production command line **before** the cron entry goes live, using a stand-in relay
that records the hand-off and delivers nothing.

### 8.1 Build the stand-in relay

```bash
LAB=/tmp/lab3_disk
mkdir -p "$LAB/bin" "$LAB/log"

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
```

### 8.2 Run the exact cron command line

```bash
DISK_MONITOR_TO=ops@example.com \
DISK_MONITOR_MAIL_COMMAND="$LAB/bin/msmtp" \
DISK_MONITOR_USAGE_OVERRIDE=91 \
./disk_monitor.sh -p / -t 80 -l "$LAB/log/audit.log"
echo "exit=$?"
```

```text
============================================================
                DevOps Disk Usage Monitor
============================================================
Partition         : /
Usage             : 91% (overridden)
Threshold         : 80%
Mail Agent        : /tmp/lab3_disk/bin/msmtp
Recipient         : ops@example.com
Execution Mode    : LIVE (Alerts Active)
Audit Log File    : /tmp/lab3_disk/log/audit.log
WARNING: Disk usage exceeds the threshold.
relay  : relay.example.com:587
subject: Disk Alert: / at 91%
to     : ops@example.com
body   : Disk usage on cachy-os is at 91% (threshold: 80%).

Partition : /
Usage    : 91%
Threshold: 80%
Time     : 2026-10-21T16:38:46Z
Alert sent to ops@example.com
exit=0
```

The audit log:

```bash
cat "$LAB/log/audit.log"
```

```text
2026-10-21T16:38:46Z [INFO] ALERT SENT to ops@example.com (Usage: 91%, Source: overridden, Threshold: 80%)
```

`DISK_MONITOR_USAGE_OVERRIDE=91` is a **rehearsal device**: it forces a breach on a host that is
not full, so the alert path can be exercised. Note `Source: overridden` in the audit line — the
module never lets a forced value masquerade as a measurement. **Remove it before going live.**

### 8.3 Clean up the rehearsal

```bash
rm -rf /tmp/lab3_disk
```

---

## Step 9: The First Live Alert

On the VPS, with the real relay in place, force one alert to yourself and watch it arrive. The
variables go through `sudo env`, because `sudo` resets the environment and would otherwise drop
them:

```bash
sudo env DISK_MONITOR_TO=you@example.com DISK_MONITOR_USAGE_OVERRIDE=95 \
    /usr/local/bin/disk-monitor -p / -t 80
echo "exit=$?"
```

You should receive a message whose subject is `Disk Alert: / at 95%` and whose body carries the
hostname, the partition, the usage, the threshold and the UTC timestamp. The exit code is `0` —
the alert was delivered.

Then remove the override and run it for real:

```bash
sudo /usr/local/bin/disk-monitor -p / -t 80 -l /var/log/disk-monitor/audit.log
```

Read the audit log the cron job will keep appending to:

```bash
sudo tail -n 20 /var/log/disk-monitor/audit.log
```

```text
2026-10-21T16:32:54Z [INFO] Usage within threshold (Usage: 49%, Source: measured, Threshold: 80%)
```

---

## Step 10: Rotate the Audit Log

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

## Step 11: Troubleshooting

| Symptom | Likely cause | What to check |
| :--- | :--- | :--- |
| `Error: No mail agent found.` | `msmtp` is not installed, or not on `cron`'s `PATH`. | `command -v msmtp`; set `DISK_MONITOR_MAIL_COMMAND` to the absolute path in the cron entry. |
| `Error: No recipient.` | `DISK_MONITOR_TO` is missing from the cron entry. | The cron file must define it, since `cron` does not inherit your shell's environment. |
| The alert never arrives | The relay rejected it, or the provider quarantined it. | `/var/log/msmtp.log`, the provider's delivery log, and the DKIM status of the received message. |
| `msmtp --serverinfo` hangs | Outbound 587 is blocked too. | Check the VCN security list's egress rules and the host firewall. |
| The alert arrives but is marked as spam | No DKIM, or a mismatched `from` address. | DKIM is the provider's job; make sure the `from` address is one the provider is allowed to sign for. |
| `exited with status 2` in syslog | The measurement or the hand-off failed. | `sudo tail -n 20 /var/log/disk-monitor/audit.log` — the `ERROR` line names the cause. |
| `exited with status 1` in syslog | The configuration is wrong. | The `ERROR` line names the bad setting. This one will not fix itself. |
| The cron job does not run at all | The file is not in `/etc/cron.d/`, or the name is wrong. | `ls -l /etc/cron.d/`; the file must be owned by root and **must not** be group- or world-writable. |

---

## ✅ What You Should See

| Check | Expected |
| :--- | :--- |
| `msmtp -C` on the VPS | Your host, port `587` and account. |
| `msmtp --serverinfo` on the VPS | The provider's banner and authentication methods. |
| The rehearsal (Step 8) | The subject, the recipient and the body printed by the stand-in, then `Alert sent to ops@example.com`, exit `0`. |
| The rehearsal audit line | `Source: overridden` — the forced value is labelled. |
| The first live alert (Step 9) | A message titled `Disk Alert: / at 95%` in your inbox. |
| The real run | `Usage : <n>% (measured)` and `Source: measured` in the audit log. |
| `sudo tail /var/log/disk-monitor/audit.log` | One ISO-8601 line per run. |

---

## 🧪 Try It Yourself

1. **Prove the cron entry is the production command line.** Copy the cron entry's command into a
   shell, append ` --notify none`, and run it. If the report matches what cron produces, the
   entry is correct:

   ```bash
   sudo env DISK_MONITOR_TO=ops@example.com DISK_MONITOR_MAIL_COMMAND=/usr/bin/msmtp \
       /usr/local/bin/disk-monitor -p / -t 80 --notify none
   ```

2. **Test the relay's failure mode.** Point the module at a mail agent that cannot be resolved
   and confirm it refuses to run *before* measuring, with exit `1`:

   ```bash
   sudo env DISK_MONITOR_TO=ops@example.com \
       DISK_MONITOR_MAIL_COMMAND=/usr/bin/definitely-not-a-mail-agent \
       /usr/local/bin/disk-monitor -p / -t 80
   echo "exit=$?"
   ```

   ```text
   Error: No mail agent found. Install one, or set --mail-command or DISK_MONITOR_MAIL_COMMAND.
   exit=1
   ```

   A deployment that cannot alert should fail at deploy time, not at 03:00.

3. **Watch the audit log fill up.** Run the module five times in a row with different
   thresholds, then read the log:

   ```bash
   for t in 10 20 30 40 50; do
       sudo /usr/local/bin/disk-monitor -p / -t "$t" --notify none \
           -l /var/log/disk-monitor/audit.log >/dev/null
   done
   sudo tail -n 5 /var/log/disk-monitor/audit.log
   ```

   Five runs, five lines, one timestamp each. The four lower thresholds are above the real usage,
   so they record `Alert suppressed by --notify none`; the highest one is below it and records
   `Usage within threshold`. **Not one of them says `ALERT SENT`** — `--notify none` suppressed
   the hand-off every time.

---

## 📎 Related Documents

- [SCENARIOS.md](../SCENARIOS.md) — the operational failure modes, cron and systemd.
- [ARCHITECTURE_COMPARISON.md](../ARCHITECTURE_COMPARISON.md) — why the transport is a hand-off to the host's mail agent.
- [Lab 1 — Measure, Compare & Rehearse](LAB1_THRESHOLD_AND_DRY_RUN.md) — the threshold boundary and the dry run.
- [Lab 2 — Exit Codes & Audit Log](LAB2_EXIT_CODES_AND_AUDIT_LOG.md) — every exit code, end to end.
- [`../../README.md`](../../README.md) — usage, flags and troubleshooting.

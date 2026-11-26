# Lab 1: Webhook Automation & HTTP Triggering 🧪

In this hands-on lab, you will configure an EventOps daemon (Python or Go) to listen for HTTP POST webhooks, trigger an automated shell script, and audit log entries.

---

## 🎯 Objectives
- Configure a custom webhook rule in `rules.json`.
- Start the EventOps daemon.
- Simulate external webhook triggers using `curl`.
- Inspect the central log file (`eventops.log`) for stdout/stderr execution metrics.

---

## 🛠️ Step-by-Step Instructions

### Step 1: Create a Working Directory & Rules Configuration
From the repository root, start the lab shell (do not source the helper):

```bash
bash 11-Scheduling-And-Automation/docs/labs/webhook_lab_shell.sh
```

The helper creates a private temporary workspace, `rules.json` with `/alert` and `/deploy`
webhook rules, and a new `webhook.secret` with mode 600. It exports the secret only inside
its child shell and displays the workspace path. Copy that path for the second terminal.
Your original shell's directory, environment, functions, traps and umask are unchanged.
Keep this shell open until you finish the lab. Never put the secret or workspace in git.

---

### Step 2: Generate a Shared Secret & Start the EventOps Daemon

The webhook listener refuses to start without a shared HMAC secret. The lab shell already
created and exported one. In that shell, start one daemon, replacing `/path/to` with the
absolute repository location:

#### Option A: Running Python Daemon
```bash
python3 /path/to/11-Scheduling-And-Automation/EventOps/eventops.py start --config rules.json --port 8080
```

#### Option B: Running Go Daemon
```bash
go run /path/to/11-Scheduling-And-Automation/EventOps-Go/main.go start --config rules.json --port 8080
```

**Expected Startup Log Output:**
```text
[2026-08-12 15:00:00] [INFO] [Main] Starting EventOps Daemon...
[2026-08-12 15:00:00] [INFO] [WebhookServer] Webhook Server listening on http://127.0.0.1:8080
[2026-08-12 15:00:00] [INFO] [Main] EventOps Daemon is now active and monitoring events.
```

**If the secret is missing**, the daemon aborts with a clear error instead of listening anonymously:
```text
[ERROR] [Main] Failed to start Webhook Server: EVENTOPS_WEBHOOK_SECRET is not set; refusing to start the webhook listener...
```

---

### Step 3: Trigger the Webhooks via `curl`

The daemon only accepts POSTs whose `X-Hub-Signature-256` header carries a valid
HMAC-SHA256 of the raw body. In a second terminal, open a child Bash shell, change to the
workspace path displayed by the first terminal, and load its secret. Replace the example path
with that exact path; keep the quotes if it contains spaces:

```bash
bash --noprofile --norc
cd -- '/path/to/displayed/workspace' || exit
EVENTOPS_WEBHOOK_SECRET=$(<webhook.secret) || exit
export EVENTOPS_WEBHOOK_SECRET
sign() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$EVENTOPS_WEBHOOK_SECRET" -hex | awk '{print $NF}'; }
```

Run the following requests in that second child shell:

#### Test Trigger 1: Health Alert Webhook
```bash
BODY='{}'
curl -X POST http://localhost:8080/alert -H "X-Hub-Signature-256: sha256=$(sign "$BODY")" --data "$BODY"
```
**Expected HTTP Response:**
```json
{
  "status": "success",
  "rule": "Health Alert Webhook",
  "message": "Action triggered successfully"
}
```

#### Test Trigger 2: Deployment Webhook
```bash
BODY='{}'
curl -X POST http://localhost:8080/deploy -H "X-Hub-Signature-256: sha256=$(sign "$BODY")" --data "$BODY"
```
**Expected HTTP Response:**
```json
{
  "status": "success",
  "rule": "Deployment Webhook",
  "message": "Action triggered successfully"
}
```

#### Test Trigger 3: Missing or Invalid Signature (401 Verification)
```bash
curl -X POST http://localhost:8080/deploy   # no signature header at all
```
**Expected HTTP Response:**
```json
{
  "status": "error",
  "message": "Missing or invalid signature"
}
```

#### Test Trigger 4: Unknown Endpoint (404 Error Verification)
```bash
BODY='{}'
curl -X POST http://localhost:8080/nonexistent -H "X-Hub-Signature-256: sha256=$(sign "$BODY")" --data "$BODY"
```
**Expected HTTP Response:**
```json
{
  "status": "error",
  "message": "No webhook rule matching endpoint '/nonexistent'"
}
```

---

### Step 4: Verify Executed Logs & File Output

Check generated action output logs:
```bash
cat alert.log
cat deploy.log
```

Inspect `eventops.log`:
```bash
cat eventops.log
```

### Step 5: Clean Up

Stop the daemon and exit the second child shell. Then exit the first lab shell. The helper
removes its workspace, including `webhook.secret`, after the lab shell exits. An uncatchable kill
or system crash can prevent cleanup: if that happens, remove the displayed workspace manually.
Do not save or commit the secret.

---

## 💡 Lab Challenge
Add a third rule in `rules.json` that triggers a script displaying current memory/disk utilization on your system (`df -h` or `free -m`) and verify its output!

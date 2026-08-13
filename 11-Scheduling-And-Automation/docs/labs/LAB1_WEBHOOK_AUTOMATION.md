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
Create a temporary workspace directory `lab1_workspace`:

```bash
mkdir -p lab1_workspace
cd lab1_workspace
```

Create `rules.json` with two webhook endpoints:

```json
{
  "rules": [
    {
      "name": "Health Alert Webhook",
      "type": "webhook",
      "endpoint": "/alert",
      "action": "echo '[ALERT] System health check triggered!' >> alert.log"
    },
    {
      "name": "Deployment Webhook",
      "type": "webhook",
      "endpoint": "/deploy",
      "action": "echo '[DEPLOY] Automated build initiated.' >> deploy.log"
    }
  ]
}
```

---

### Step 2: Start the EventOps Daemon

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
[2026-08-12 15:00:00] [INFO] [WebhookServer] Webhook Server listening on http://0.0.0.0:8080
[2026-08-12 15:00:00] [INFO] [Main] EventOps Daemon is now active and monitoring events.
```

---

### Step 3: Trigger the Webhooks via `curl`

Open a new terminal window and send HTTP POST requests:

#### Test Trigger 1: Health Alert Webhook
```bash
curl -X POST http://localhost:8080/alert
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
curl -X POST http://localhost:8080/deploy
```
**Expected HTTP Response:**
```json
{
  "status": "success",
  "rule": "Deployment Webhook",
  "message": "Action triggered successfully"
}
```

#### Test Trigger 3: Unknown Endpoint (404 Error Verification)
```bash
curl -X POST http://localhost:8080/nonexistent
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

---

## 💡 Lab Challenge
Add a third rule in `rules.json` that triggers a script displaying current memory/disk utilization on your system (`df -h` or `free -m`) and verify its output!

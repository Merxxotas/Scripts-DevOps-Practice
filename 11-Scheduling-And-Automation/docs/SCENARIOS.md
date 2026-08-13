# EventOps - Real-World Production Scenarios 🚀

EventOps replaces legacy time-based polling schedulers (like Cron or Windows Task Scheduler) by reacting to system and network events in real time. Below are three detailed production deployment scenarios demonstrating how to use EventOps effectively.

---

## 📋 Table of Contents
1. [Scenario 1: Automated Git Deployment via Webhook](#scenario-1-automated-git-deployment-via-webhook)
2. [Scenario 2: Nginx Service Auto-Reload on Config Modification](#scenario-2-nginx-service-auto-reload-on-config-modification)
3. [Scenario 3: Cross-Platform (Windows PowerShell / Linux Bash) Automation](#scenario-3-cross-platform-automation)

---

## Scenario 1: Automated Git Deployment via Webhook

### Overview
In a modern CI/CD pipeline, when developers push code to the `main` branch, GitHub Actions or GitLab CI sends an HTTP POST notification to your deployment server. EventOps catches this webhook and instantly triggers an automated git pull and build script without running a polling cron job every minute.

### Configuration (`rules.json`)
```json
{
  "rules": [
    {
      "name": "Production Git Deployment",
      "type": "webhook",
      "endpoint": "/deploy-prod",
      "action": "bash /opt/scripts/deploy_prod.sh"
    }
  ]
}
```

### Deployment Script (`/opt/scripts/deploy_prod.sh`)
```bash
#!/usr/bin/env bash
set -e
echo "Starting production deployment..."
cd /var/www/my-app
git pull origin main
npm install --production
systemctl restart my-app.service
echo "Deployment successfully completed!"
```

### Triggering the Webhook
External CI/CD or curl request:
```bash
curl -X POST http://deploy-server.internal:8080/deploy-prod
```

### Log Audit (`eventops.log`)
```text
[2026-08-12 14:30:00] [INFO] [WebhookServer] Received POST request on /deploy-prod
[2026-08-12 14:30:00] [INFO] [WebhookServer] Triggering rule 'Production Git Deployment' for endpoint '/deploy-prod'
[2026-08-12 14:30:00] [INFO] [Executor] Executing action [Production Git Deployment]: bash /opt/scripts/deploy_prod.sh
[2026-08-12 14:30:04] [INFO] [Executor] [stdout [Production Git Deployment]] Starting production deployment...
[2026-08-12 14:30:06] [INFO] [Executor] [stdout [Production Git Deployment]] Deployment successfully completed!
[2026-08-12 14:30:06] [INFO] [Executor] Action [Production Git Deployment] completed successfully.
```

---

## Scenario 2: Nginx Service Auto-Reload on Config Modification

### Overview
System administrators frequently update web server configuration files (`/etc/nginx/nginx.conf` or `/etc/nginx/sites-available/app.conf`). EventOps monitors the configuration path and automatically tests and reloads Nginx the millisecond the file is saved.

### Configuration (`rules.json`)
```json
{
  "rules": [
    {
      "name": "Nginx Config Reload",
      "type": "file_change",
      "watch_path": "/etc/nginx/nginx.conf",
      "action": "nginx -t && systemctl reload nginx"
    }
  ]
}
```

### Triggering the Event
Simply save changes to `/etc/nginx/nginx.conf`. The `watchdog` (Python) or `fsnotify` (Go) OS filesystem watcher triggers EventOps instantly.

### Smart Debouncing in Action
Text editors like `vim` or `VSCode` often write temporary atomic files or trigger 3–5 rapid OS modification events upon saving a single file. EventOps enforces a 2-second cooldown:
```text
[2026-08-12 14:35:10] [INFO] [FileWatcher] File change detected on '/etc/nginx/nginx.conf'. Triggering rule 'Nginx Config Reload'
[2026-08-12 14:35:10] [DEBUG] [FileWatcher] Debounced file change event for rule 'Nginx Config Reload' (0.01s < 2.00s cooldown)
[2026-08-12 14:35:10] [DEBUG] [FileWatcher] Debounced file change event for rule 'Nginx Config Reload' (0.03s < 2.00s cooldown)
```

---

## Scenario 3: Cross-Platform Automation

### Overview
EventOps runs natively on Linux, macOS, and Windows. Depending on the operating system, shell actions execute in the native shell environment.

### Linux / macOS Action Example
```json
{
  "name": "Log Rotation Trigger",
  "type": "webhook",
  "endpoint": "/rotate-logs",
  "action": "gzip -k /var/log/app/*.log"
}
```

### Windows Action Example (PowerShell / CMD)
```json
{
  "name": "IIS Service Restart",
  "type": "webhook",
  "endpoint": "/iis-restart",
  "action": "powershell.exe -Command \"Restart-Service -Name W3SVC\""
}
```

# EventOps - Event-Driven Automation Daemon ⚡

**EventOps** is a lightweight, cross-platform background automation daemon designed to replace legacy, polling-based cron jobs and scheduled tasks by triggering actions in real time when system and network events occur.

---

## 🏗️ Core Architecture

```
+-------------------------------------------------------------------------------+
|                               EventOps Daemon Loop                            |
+---------------------------------------+---------------------------------------+
                                        |
         +------------------------------+------------------------------+
         |                                                             |
         v                                                             v
+-------------------------------+                             +-------------------------------+
|    Webhook Server Trigger     |                             |     File Watcher Trigger      |
|  - Listens on HTTP 0.0.0.0    |                             |  - Inotify / FSEvents / Win   |
|  - Matches URL endpoint path  |                             |  - 2-Second Cooldown Debounce |
+---------------+---------------+                             +---------------+---------------+
                |                                                             |
                +------------------------------+------------------------------+
                                               |
                                               v
                                +-------------------------------+
                                |          Rule Engine          |
                                |  - Parses & validates schema  |
                                |  - Routes to matching action  |
                                +---------------+---------------+
                                                |
                                                v
                                +-------------------------------+
                                |     Asynchronous Executor     |
                                |  - Non-blocking execution     |
                                |  - Output capture & logging   |
                                +-------------------------------+
```

---

## ⚙️ Configuration Schema (`rules.json`)

All automation behaviors are configured via a single declarative JSON schema:

```json
{
  "rules": [
    {
      "name": "Production Webhook Deployment",
      "type": "webhook",
      "endpoint": "/deploy-prod",
      "action": "bash /opt/scripts/deploy.sh"
    },
    {
      "name": "Nginx Config Reload on File Change",
      "type": "file_change",
      "watch_path": "/etc/nginx/nginx.conf",
      "action": "systemctl reload nginx"
    }
  ]
}
```

---

## 🔍 Key Capabilities

1. **Webhook Trigger**: Built-in HTTP server listening on configurable ports. Matches incoming POST requests against registered endpoints and returns structured JSON responses.
2. **Filesystem Watcher**: Listens for file modification, creation, or deletion events with a built-in **2-second cooldown debouncing engine** to prevent rapid-fire redundant script executions.
3. **Asynchronous Non-Blocking Execution**: Actions are dispatched to background threads (Python) or Goroutines (Go), ensuring that long-running scripts do not block incoming triggers.
4. **Centralized ISO-8601 Logging**: Captures stdout, stderr, and exit codes for every triggered task into `eventops.log`.


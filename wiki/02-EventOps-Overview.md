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
|  - Listens on HTTP 127.0.0.1 (HMAC-authenticated) |                             |  - Inotify / FSEvents / Win   |
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

## 🔐 Webhook Request Contract

The webhook listener is fail-closed and speaks one body contract in both implementations:

| Situation | Answer |
| :--- | :--- |
| Valid `X-Hub-Signature-256` over the payload, endpoint registered | `200` + action dispatched |
| Signed body sent with `Transfer-Encoding: chunked` (no `Content-Length`) | `200` — the framing is decoded and the HMAC covers the payload itself |
| Missing, malformed or mismatched signature | `401` generic — "Missing or invalid signature" |
| Malformed or truncated chunked framing | `401` generic — corrupted bytes never reach the rule engine |
| Decoded body over 1 MB | `413` |
| Unknown endpoint (valid signature) | `404` |
| `GET` | `405` |
| `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS` | `501` — the stdlib handler's answer for an unimplemented method |

Two properties are deliberate. The signature is verified **before** rule matching, so an unauthenticated
caller cannot probe which endpoints exist. And a sender that switches to chunked framing — GitHub does so
above its payload threshold — is not punished for it: reading only `Content-Length` would sign an empty
body and reject a perfectly valid request.


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


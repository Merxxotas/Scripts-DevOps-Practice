# EventOps - Production Scenarios & Interactive Labs 🧪

---

## 🚀 Production Deployment Scenarios

### Scenario 1: Automated Git Webhook Deployment
Trigger an automated `git pull` and container rebuild whenever a push notification is delivered from GitHub/GitLab webhooks to `http://server:8080/deploy`.

### Scenario 2: Service Auto-Reload on Configuration Changes
Monitor configuration files (e.g. `/etc/nginx/conf.d/app.conf`) and automatically trigger syntax validation (`nginx -t`) and reload (`systemctl reload nginx`) upon file changes.

---

## 🧪 Interactive Hands-on Labs

| Lab Guide | Focus Area | What You Will Learn |
| :--- | :--- | :--- |
| **[Lab 1: Webhook Automation](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/11-Scheduling-And-Automation/docs/labs/LAB1_WEBHOOK_AUTOMATION.md)** | HTTP Triggers | Setting up `rules.json`, firing curl POST requests, and verifying asynchronous background execution. |
| **[Lab 2: File Watcher Debounce](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/11-Scheduling-And-Automation/docs/labs/LAB2_FILE_WATCHER_DEBOUNCE.md)** | Filesystem Monitoring | Monitoring log and config files, testing rapid-fire file writes, and validating the 2-second debouncing engine. |
| **[Lab 3: Python vs. Go Benchmark](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/11-Scheduling-And-Automation/docs/labs/LAB3_GO_VS_PYTHON.md)** | Performance & Profiling | Benchmarking RAM usage, binary startup latencies, and high-throughput trigger load testing. |


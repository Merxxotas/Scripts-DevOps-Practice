# EventOps ⚡
> **Stop waiting for the clock. Start reacting to the system.**

[![Python](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)
[![Go](https://img.shields.io/badge/Go-1.20%2B-00ADD8.svg)](https://go.dev/)
[![CI/CD](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-eventops.yml/badge.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-eventops.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

EventOps is a lightweight, cross-platform automation daemon that replaces traditional time-based schedulers (like Cron or Windows Task Scheduler). Instead of running scripts on a rigid timer, EventOps monitors your system and network in real-time, executing shell commands the exact millisecond an event occurs.

EventOps is implemented in both **Python** (`EventOps/`) and **Go** (`EventOps-Go/`).

---

## 📑 Table of Contents
- [Features](#-features)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
  - [Running Python Edition](#1-python-edition-eventops)
  - [Running Go Edition](#2-go-edition-eventops-go)
- [Configuration](#-configuration)
  - [Webhook Triggers](#1-webhook-triggers)
  - [File Watcher Triggers](#2-file-watcher-triggers)
- [Documentation & Hands-on Labs](#-documentation--hands-on-labs)
- [Logging & Auditing](#-logging--auditing)
- [CI/CD & GitHub Actions](#-cicd--github-actions)
- [Development Roadmap](#-development-roadmap)

---

## ✨ Features
- **Dual Runtime Support:** Available in Python (`EventOps/`) and compiled Go (`EventOps-Go/`).
- **Event-Driven Execution:** Trigger scripts instantly via incoming HTTP webhooks or filesystem modifications.
- **Cross-Platform:** Works natively on Linux, macOS, and Windows.
- **Zero-Friction Configuration:** Define all your automation rules in a single, human-readable `rules.json` file.
- **Asynchronous & Non-Blocking:** Long-running deployment scripts won't block the daemon from catching new events.
- **Smart Debouncing:** Built-in cooldowns (2.0s) prevent rapid-fire OS file events from triggering script execution storms.
- **CI/CD Integrated:** Tested and validated automatically across Ubuntu, macOS, and Windows matrix environments via GitHub Actions.

---

## 🏗️ Architecture
EventOps runs as a single background daemon that spawns independent listener threads/goroutines:
1. **The Webhook Server:** A lightweight HTTP server listening for POST requests.
2. **The File Watcher:** Uses OS-native APIs (`inotify`, `FSEvents`, `ReadDirectoryChangesW`) via `watchdog` (Python) / `fsnotify` (Go).
3. **The Rule Engine:** Parses your JSON configuration and routes incoming events to the correct action.
4. **The Executor:** Spawns subprocesses to run your shell/bash/powershell scripts and safely captures their output.

---

## 🚀 Quick Start

### 1. Python Edition (`EventOps/`)
```bash
# Install dependencies
pip install -r EventOps/requirements.txt

# Start daemon
python eventops.py start
```

### 2. Go Edition (`EventOps-Go/`)
```bash
# Run directly with Go
cd EventOps-Go
go run main.go start

# Or build standalone release binary (<10MB)
go build -o eventops main.go
./eventops start
```

*Tip: Press `Ctrl+C` to gracefully shut down either daemon at any time.*

---

## ⚙️ Configuration

All automations are defined in `rules.json`. The syntax is simple and declarative.

### 1. Webhook Triggers
Perfect for integrating with external services like GitHub Actions, Slack, or CI/CD pipelines.

```json
{
  "name": "Production Git Deploy",
  "type": "webhook",
  "endpoint": "/deploy-prod",
  "action": "bash /opt/scripts/deploy.sh"
}
```
**How to trigger:**
```bash
curl -X POST http://localhost:8080/deploy-prod
```

### 2. File Watcher Triggers
Perfect for auto-reloading services when configuration files change, or processing data as soon as a file is downloaded.

```json
{
  "name": "Nginx Auto-Restart",
  "type": "file_change",
  "watch_path": "/etc/nginx/nginx.conf",
  "action": "systemctl restart nginx"
}
```
**How to trigger:** Simply edit and save `/etc/nginx/nginx.conf`. EventOps will instantly restart the service.

---

## 📚 Documentation & Hands-on Labs

Explore the comprehensive `docs/` folder for scenario guides and interactive tutorials:

- 📖 [**Production Scenarios Guide**](docs/SCENARIOS.md): Webhook CI/CD deployments, Nginx config reloads, and cross-platform PowerShell/Bash actions.
- ⚡ [**Python vs Go Architecture Comparison**](docs/ARCHITECTURE_COMPARISON.md): Detailed comparison of concurrency models, RAM usage (~28MB vs ~5MB), and startup times.
- 🧪 [**Lab 1: Webhook Automation & HTTP Triggering**](docs/labs/LAB1_WEBHOOK_AUTOMATION.md): Step-by-step webhook setup and testing lab.
- 🧪 [**Lab 2: File Watcher & Smart Debouncing**](docs/labs/LAB2_FILE_WATCHER_DEBOUNCE.md): Step-by-step filesystem watching and 2.0s debouncing cooldown lab.
- 🧪 [**Lab 3: Benchmarking Python vs Go Daemons**](docs/labs/LAB3_GO_VS_PYTHON.md): Hands-on lab for running both daemons side-by-side and measuring RAM/CPU metrics.

---

## 📝 Logging & Auditing

Every action EventOps takes—whether it's catching a webhook, detecting a file change, or executing a script—is meticulously recorded in `eventops.log`.

The executor captures both `stdout` (standard output) and `stderr` (errors) from your scripts, meaning you never lose visibility into what your background scripts are doing.

**Example Log Output:**
```text
[2026-08-12 14:30:01] [INFO] [Webhook] Received POST on /deploy-prod
[2026-08-12 14:30:01] [INFO] [Executor] Executing action: bash /opt/scripts/deploy.sh
[2026-08-12 14:30:05] [INFO] [Executor] Action completed successfully.
```

---

## ⚙️ CI/CD & GitHub Actions

EventOps uses **GitHub Actions** to maintain code quality across both Python and Go implementations. Any pull requests or merges to the `main` branch trigger:
- Multi-OS testing matrix (`ubuntu-24.04`, `macos-14`, `windows-2022`).
- Python linting (`ruff`), Go vetting (`go vet`), and complete `pytest` & `go test` test suites.

Look for the passing CI/CD badge at the top of the repository to confirm stability!

---

## 🗺️ Development Roadmap
This project was built using **Spec Driven Development (SDD)**. If you are interested in how the architecture was designed and implemented step-by-step, please refer to the following technical documents:
- `SPECS.md`: Complete technical and architectural specifications.
- `ROADMAP.md`: The phase-by-phase implementation checklist.

# EventOps ⚡
> **Stop waiting for the clock. Start reacting to the system.**

[![Python](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)
[![CI/CD](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-eventops.yml/badge.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-eventops.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

EventOps is a lightweight, cross-platform automation daemon that replaces traditional time-based schedulers (like Cron or Windows Task Scheduler). Instead of running scripts on a rigid timer, EventOps monitors your system and network in real-time, executing shell commands the exact millisecond an event occurs.

---

## 📑 Table of Contents
- [Features](#-features)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
  - [Webhook Triggers](#1-webhook-triggers)
  - [File Watcher Triggers](#2-file-watcher-triggers)
- [Logging & Auditing](#-logging--auditing)
- [CI/CD & GitHub Actions](#-cicd--github-actions)
- [Development Roadmap](#-development-roadmap)

---

## ✨ Features
- **Event-Driven Execution:** Trigger scripts instantly via incoming HTTP webhooks or filesystem modifications.
- **Cross-Platform:** Works natively on Linux, macOS, and Windows.
- **Zero-Friction Configuration:** Define all your automation rules in a single, human-readable `rules.json` file.
- **Asynchronous & Non-Blocking:** Long-running deployment scripts won't block the daemon from catching new events.
- **Smart Debouncing:** Built-in cooldowns prevent rapid-fire OS file events from triggering a script multiple times simultaneously.
- **CI/CD Integrated:** Designed to be tested and deployed automatically via GitHub Actions pipelines.

---

## 🏗️ Architecture
EventOps runs as a single background daemon that spawns independent listener threads:
1. **The Webhook Server:** A lightweight HTTP server listening for POST requests.
2. **The File Watcher:** Uses OS-native APIs (inotify, FSEvents) to monitor directories for changes.
3. **The Rule Engine:** Parses your JSON configuration and routes incoming events to the correct action.
4. **The Executor:** Spawns subprocesses to run your shell/bash/powershell scripts and safely captures their output.

---

## 🚀 Quick Start

### 1. Prerequisites
You need Python 3.8+ installed. Install the only required external dependency (`watchdog`):
```bash
pip install -r requirements.txt
```

### 2. Configure Your Rules
Edit `rules.json` to define what EventOps should listen for. See the [Configuration](#-configuration) section below for examples.

### 3. Start the Daemon
Run the daemon in the background:
```bash
python eventops.py start
```
*Tip: You can press `Ctrl+C` to gracefully shut down the daemon at any time.*

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

EventOps strictly uses **GitHub Actions** to maintain code quality. Any pull requests or merges to the `main` branch will automatically trigger:
- Multi-OS environment testing (Linux, macOS, Windows).
- Syntax and Code Style linting.
- Automated suite of Unit Tests.

Look for the passing CI/CD badge at the top of the repository to confirm stability!

---

## 🗺️ Development Roadmap
This project was built using **Spec Driven Development (SDD)**. If you are interested in how the architecture was designed and implemented step-by-step, please refer to the following technical documents included in this repository:
- `SPECS.md`: Complete technical and architectural specifications.
- `ROADMAP.md`: The phase-by-phase implementation checklist.

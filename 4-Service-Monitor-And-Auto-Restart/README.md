# Service Monitor and Auto-Restart 🩺

Cross-platform service monitoring with automatic restart. Available in **POSIX Bash**
(Linux/macOS, via `systemctl`) and **PowerShell** (Windows, via `Get-Service`), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: validates the service name and confirms the service is installed.
- 🧪 **Dry-Run Simulation**: preview the planned restart attempts without touching the service.
- 🔁 **Auto-Restart**: retries a failed restart up to a configurable number of times.
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- 🔔 **Notifications**: syslog on Bash, Windows Event Log on PowerShell.
- ⚙️ **Zero Dependencies** beyond the shell and the platform service manager.

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x service_monitor.sh

# Check a service (restart if down)
./service_monitor.sh -s nginx

# Dry run
./service_monitor.sh -s nginx --dry-run

# Custom retries and delay
./service_monitor.sh -s nginx -r 5 --retry-delay 10
```

### Windows (PowerShell)

```powershell
# Check a service (restart if down)
.\service_monitor.ps1 -ServiceName w3svc

# Dry run
.\service_monitor.ps1 -ServiceName w3svc -DryRun

# Custom retries and delay
.\service_monitor.ps1 -ServiceName w3svc -MaxRetries 5 -RetryDelaySeconds 10
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` success · `1` configuration or safety violation · `2` partial failure (restart failed).

---

## Tests

```bash
bash tests/test_service_monitor.sh
pwsh tests/test_service_monitor.ps1
```

The suite runs without mutating real system services (Bash stubs `systemctl`; PowerShell
exercises parsing, guardrails and dry-run).

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.
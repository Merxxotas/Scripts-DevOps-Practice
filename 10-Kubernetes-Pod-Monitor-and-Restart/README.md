# Kubernetes Pod Monitor and Restart 🩺

Cross-platform monitoring and auto-restart of Kubernetes pods whose restart count exceeds a
threshold. Available in **POSIX Bash** (Linux/macOS) and **PowerShell** (Windows), with 100%
feature parity. Requires `kubectl` and cluster access.

---

## Key Features

- 🛡️ **Safety Guardrails**: validates namespace, label selector and threshold before any cluster call.
- 🧪 **Dry-Run Simulation**: list pods and preview deletions without deleting.
- ⚡ **Force mode**: hard delete (`--grace-period=0 --force`) when graceful termination is insufficient.
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- 🩺 **Graceful by default**: hard delete only with `--force`.

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x k8s_monitor.sh

# Monitor default namespace, app=web, threshold 3
./k8s_monitor.sh

# Custom namespace/selector/threshold
./k8s_monitor.sh -n production -l app=api -r 5

# Dry run
./k8s_monitor.sh --dry-run

# Hard delete
./k8s_monitor.sh --force

# Audit log
./k8s_monitor.sh --audit-log /tmp/k8s.log
```

### Windows (PowerShell)

```powershell
# Monitor default namespace
.\k8s_monitor.ps1

# Custom
.\k8s_monitor.ps1 -Namespace production -LabelSelector app=api -RestartThreshold 5

# Dry run
.\k8s_monitor.ps1 -DryRun

# Hard delete
.\k8s_monitor.ps1 -Force

# Audit log
.\k8s_monitor.ps1 -AuditLog C:\temp\k8s.log
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` success or dry-run · `1` configuration or safety violation (bad input, kubectl missing) · `2` partial failure (a delete failed).

---

## Tests

```bash
bash tests/test_k8s_monitor.sh
pwsh tests/test_k8s_monitor.ps1
```

The suites stub `kubectl`; no cluster is required.

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.

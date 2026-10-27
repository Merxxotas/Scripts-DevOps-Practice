# Log Rotation and Compression 🔄

Cross-platform log rotation with compression and retention. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: refuses protected system roots; requires an existing regular log file.
- 🧪 **Dry-Run Simulation**: preview renames, compression, truncation and pruning without touching anything.
- 📦 **Compression**: gzip on Bash (`.gz`), zip on PowerShell (`.zip`).
- 🧹 **Retention**: keeps the most recent N backups; prunes the rest.
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- ⚙️ **Zero Dependencies** beyond the shell and standard compression tooling.

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x log_rotate.sh

# Dry run
./log_rotate.sh -f /var/log/app/application.log -m 10 -c 5 --dry-run

# Real rotation when the file exceeds 10 MB
./log_rotate.sh -f /var/log/app/application.log -m 10 -c 5

# Force rotation regardless of size
./log_rotate.sh -f /var/log/app/application.log --force
```

### Windows (PowerShell)

```powershell
# Dry run
.\log_rotate.ps1 -LogFile C:\Logs\application.log -MaxSizeMB 10 -BackupCount 5 -DryRun

# Real rotation
.\log_rotate.ps1 -LogFile C:\Logs\application.log -MaxSizeMB 10 -BackupCount 5

# Force rotation
.\log_rotate.ps1 -LogFile C:\Logs\application.log -Force
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` success · `1` configuration or safety violation · `2` partial failure.

---

## Tests

```bash
bash tests/test_log_rotate.sh
pwsh tests/test_log_rotate.ps1
```

The suite runs entirely under a temporary directory; no real system paths are touched.

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.
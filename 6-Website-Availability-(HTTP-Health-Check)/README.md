# Website Availability (HTTP Health Check) 🌐

Cross-platform HTTP health check for a single URL. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: validates URL scheme, timeout and expected code before any request.
- 🧪 **Dry-Run Simulation**: print target/expected/timeout without making a request.
- 📊 **Metrics**: status code, response time, response size.
- 🔒 **SSL Expiry**: optional certificate expiry reporting for HTTPS URLs.
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- ⚙️ **Zero Dependencies** beyond the shell and the platform HTTP client.

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x health_check.sh

# Basic check (default https://example.com)
./health_check.sh

# Custom URL and expected code
./health_check.sh -u https://example.com -e 200

# Dry run
./health_check.sh --dry-run

# With SSL expiry and audit log
./health_check.sh -u https://example.com --ssl-check --audit-log /tmp/hc.log
```

### Windows (PowerShell)

```powershell
# Basic check
.\health_check.ps1

# Custom URL and expected code
.\health_check.ps1 -Url https://example.com -ExpectedCode 200

# Dry run
.\health_check.ps1 -DryRun

# With SSL expiry and audit log
.\health_check.ps1 -Url https://example.com -SslCheck -AuditLog C:\temp\hc.log
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` healthy or dry-run · `1` configuration or safety violation · `2` unhealthy (mismatch or connection failure).

---

## Tests

```bash
bash tests/test_health_check.sh
pwsh tests/test_health_check.ps1
```

The Bash suite stubs `curl`; no network is used. The PowerShell suite mocks `Invoke-WebRequest`.

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.

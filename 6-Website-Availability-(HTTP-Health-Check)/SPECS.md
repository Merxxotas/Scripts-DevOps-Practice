# Website Availability (HTTP Health Check) - Technical Specification

## 1. System Overview

The **Website Availability Utility** performs a single HTTP GET against a target URL and
reports whether the response status matches the expected code, along with response time,
response size and (optionally) SSL certificate expiry. It runs on POSIX Bash (Linux/macOS)
and PowerShell (Windows), with 100% feature parity in flags, exit codes and guardrails.
No third-party dependencies beyond the shell and the platform HTTP client (`curl` on Bash;
`Invoke-WebRequest` on PowerShell).

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate URL scheme, timeout, expected code                                  |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Dry-Run Gate                                    |
|  - If --dry-run: print target/expected/timeout, exit 0                          |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Request                                         |
|  - HTTP GET with timeout; capture status code, time, size                       |
|  - No redirect following in v1                                                  |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Health Determination                            |
|  - status == expected  -> healthy (exit 0)                                     |
|  - mismatch / failure  -> unhealthy (exit 2)                                    |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Telemetry & Output                              |
|  - Print status code (colored), response time, size                            |
|  - SSL expiry if --ssl-check (HTTPS only, best-effort)                          |
|  - Write ISO-8601 audit log entry (if --audit-log)                             |
+--------------------------------------------------------------------------------+
```

### Design Principles

1. **Zero External Dependencies**: only the shell and the platform HTTP client.
2. **Safety First**: validate all inputs before any network activity; dry-run never requests.
3. **Observable & Auditable**: every run is traceable through console output and an optional audit log.
4. **Friendly Output**: curlie-inspired colorized, concise output.

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-u, --url` | `-Url` | `https://example.com` | Target URL (must be http:// or https://) |
| `-t, --timeout` | `-TimeoutSec` | `10` | Request timeout in seconds (positive integer) |
| `-e, --expected-code` | `-ExpectedCode` | `200` | HTTP status code considered healthy (100-599) |
| `--ssl-check` | `-SslCheck` | off | Report SSL certificate expiry (HTTPS only) |
| `--dry-run` | `-DryRun` | off | Print target/expected/timeout, no request |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `--json` | `-Json` | off | Output result as JSON |
| `--csv` | `-Csv` | off | Output result as CSV |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Healthy (status matches expected) or dry-run |
| 1 | Configuration or safety violation |
| 2 | Unhealthy (status mismatch or connection failure) |

---

## 5. Safety Guardrails

- **URL scheme**: must start with `http://` or `https://`.
- **Timeout**: must be a positive integer.
- **Expected code**: must be in 100-599.
- **Dry-run**: no HTTP request is made.
- **Redirects**: not followed in v1; the received status code is reported as-is.

---

## 6. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
URL, status code, response time, size and outcome. Write failures are best-effort and do not
change the exit code.

---

## 7. SSL Expiry

When `--ssl-check` is given and the URL is HTTPS, the script reports the certificate
`notAfter` date. Best-effort: if `openssl` is unavailable or the handshake fails, it prints
"unavailable" without failing the run.

---

## 8. Scope Exclusions (v1)

No redirect following, no continuous monitoring/watch loop, no authentication, no custom headers, no POST/other methods. One URL per invocation. Audit write is best-effort.

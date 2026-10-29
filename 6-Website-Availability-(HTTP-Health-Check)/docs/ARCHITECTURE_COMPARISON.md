# Architecture Comparison — Website Availability (HTTP Health Check)

## Bash vs PowerShell

| Aspect | Bash (`health_check.sh`) | PowerShell (`health_check.ps1`) |
| :--- | :--- | :--- |
| HTTP client | `curl` (no redirects) | `Invoke-WebRequest -SkipHttpErrorCheck` |
| Timing | curl `%{time_total}` | `Stopwatch` around the request |
| Size | curl `%{size_download}` | `RawContentLength` |
| SSL expiry | `openssl s_client` + `openssl x509` | `openssl` if available, else unavailable |
| Audit log | append with `>>` (best-effort) | `Out-File -Append` (best-effort) |

## Shared contract

Both share flags, defaults (`https://example.com`, 10s, 200), exit codes (0/1/2), dry-run,
audit log and the status/time/size/SSL-expiry output. Only the HTTP client and timing source
differ (platform-native). No redirect following in v1 on either side.

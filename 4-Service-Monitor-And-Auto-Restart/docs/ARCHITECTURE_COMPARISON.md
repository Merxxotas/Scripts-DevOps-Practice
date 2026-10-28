# Architecture Comparison — Service Monitor and Auto-Restart

## Bash vs PowerShell

| Aspect | Bash (`service_monitor.sh`) | PowerShell (`service_monitor.ps1`) |
| :--- | :--- | :--- |
| Service manager | `systemctl` | `Get-Service` / `Start-Service` |
| Platform | Linux / macOS | Windows (and pwsh on Linux) |
| Status check | `systemctl is-active --quiet` | `$svc.Status -eq 'Running'` |
| Existence check | `systemctl show --property=LoadState` | `Get-Service -ErrorAction Stop` |
| Restart | `systemctl restart` | `Start-Service` |
| Notification | `logger` (syslog) | `Write-EventLog` (Application log) |
| Delay | `sleep` | `Start-Sleep` |
| Validation | regex `^[a-zA-Z0-9_.@-]+$` | regex `^[a-zA-Z0-9_.-]+$` |

## Shared contract

Both implementations share the same flags (semantically), defaults for retries (3) and delay (5),
exit codes (0/1/2), dry-run behaviour, audit-log format and summary block. Only the service
manager and the default service name differ (platform-native).
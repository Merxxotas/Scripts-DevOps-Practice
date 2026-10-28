# 23. Service Monitor — Bash vs PowerShell

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| Service manager | `systemctl` | `Get-Service` / `Start-Service` |
| Default service | `nginx` | `w3svc` |
| Status check | `systemctl is-active --quiet` | `$svc.Status -eq 'Running'` |
| Existence check | `systemctl show --property=LoadState` | `Get-Service -ErrorAction Stop` |
| Restart | `systemctl restart` | `Start-Service` |
| Notification | `logger` (syslog) | `Write-EventLog` |
| Delay | `sleep` | `Start-Sleep` |

Both share flags (semantically), retries (3), delay (5), exit codes (0/1/2), dry-run, audit log.
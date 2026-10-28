# 26. Find and Kill High-CPU — Bash vs PowerShell

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| Process listing | `ps -eo pid,ppid,pcpu,comm` | `Get-Process` |
| CPU metric | `ps` instantaneous `%CPU` | cumulative CPU / elapsed seconds |
| Termination | `kill -TERM` / `kill -9` | `Stop-Process` / `-Force` |
| Guardrails | PID 0/1, self, parent, kernel threads | same, via `Test-GuardedPid` |
| Interactive | `read -p` per candidate | `Read-Host` per candidate |

Both share flags, default (50.0), exit codes (0/1/2), dry-run, audit log.
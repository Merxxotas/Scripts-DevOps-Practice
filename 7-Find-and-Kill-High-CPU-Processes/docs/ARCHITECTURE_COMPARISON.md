# Architecture Comparison — Find and Kill High-CPU Processes

## Bash vs PowerShell

| Aspect | Bash (`kill_high_cpu.sh`) | PowerShell (`kill_high_cpu.ps1`) |
| :--- | :--- | :--- |
| Process listing | `ps -eo pid,ppid,pcpu,comm` | `Get-Process` |
| CPU metric | `ps` instantaneous `%CPU` | cumulative CPU / elapsed seconds |
| Termination | `kill -TERM` / `kill -9` | `Stop-Process` / `-Force` |
| Guardrails | PID 0/1, self, parent, kernel threads | same, via `Test-GuardedPid` |
| Interactive | `read -p` per candidate | `Read-Host` per candidate |
| Delay | `sleep 0.5` after SIGTERM | none (synchronous) |

## Shared contract

Both share flags, defaults (50.0), exit codes (0/1/2), dry-run, audit log and summary block. Only the process tooling and CPU metric differ (platform-native).
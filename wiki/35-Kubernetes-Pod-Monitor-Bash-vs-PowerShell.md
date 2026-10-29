# 35. Kubernetes Pod Monitor — Bash vs PowerShell

## Shared contract

Both implement the same flags, defaults (`default`, `app=web`, 3), exit codes (0/1/2),
dry-run, audit log and per-pod output.

## Differences

| Aspect | Bash (`k8s_monitor.sh`) | PowerShell (`k8s_monitor.ps1`) |
| :--- | :--- | :--- |
| kubectl output | `kubectl ... -o jsonpath` (line format) | `kubectl ... -o jsonpath` (line format) |
| Restart aggregation | sum comma-separated counts | sum comma-separated counts |
| Delete | `kubectl delete pod` (+ `--force` flags) | `kubectl delete pod` (+ `--force` flags) |

Graceful delete by default on both; hard delete only with `--force`.

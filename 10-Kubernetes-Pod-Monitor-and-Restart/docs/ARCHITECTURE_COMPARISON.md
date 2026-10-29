# Architecture Comparison — Kubernetes Pod Monitor and Restart

## Bash vs PowerShell

| Aspect | Bash (`k8s_monitor.sh`) | PowerShell (`k8s_monitor.ps1`) |
| :--- | :--- | :--- |
| kubectl output | `kubectl ... -o jsonpath` (line format) | `kubectl ... -o jsonpath` (line format) |
| JSON parsing | none (jsonpath produces lines) | none (jsonpath produces lines) |
| Restart aggregation | sum comma-separated counts | sum comma-separated counts |
| Delete | `kubectl delete pod` (+ `--force` flags) | `kubectl delete pod` (+ `--force` flags) |

## Shared contract

Both share flags, defaults (`default`, `app=web`, 3), exit codes (0/1/2), dry-run, audit log and
per-pod output. Only the kubectl invocation plumbing differs (platform-native).

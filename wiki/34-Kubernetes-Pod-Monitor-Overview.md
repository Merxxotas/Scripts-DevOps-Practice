# 34. Kubernetes Pod Monitor and Restart — Overview & Specs

Cross-platform monitoring and auto-restart of Kubernetes pods whose restart count exceeds a
threshold. Available in **POSIX Bash** (Linux/macOS) and **PowerShell** (Windows), with 100%
feature parity. Requires `kubectl` and cluster access.

## Key Features

- Safety guardrails: validates namespace, label selector and threshold before any cluster call.
- Dry-run simulation: list pods + which would be deleted, no deletion.
- Force mode: hard delete (`--grace-period=0 --force`); graceful by default.
- Optional ISO-8601 audit log.
- Exit codes: 0 success/dry-run, 1 config/safety, 2 partial failure.

## CLI

See the module's [SPECS.md §3](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/10-Kubernetes-Pod-Monitor-and-Restart/SPECS.md).

## Wiki Navigation

- [Bash vs PowerShell](35-Kubernetes-Pod-Monitor-Bash-vs-PowerShell)
- [Scenarios & Labs](36-Kubernetes-Pod-Monitor-Scenarios-and-Labs)

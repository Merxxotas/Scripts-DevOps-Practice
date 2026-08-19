# Monorepo CI/CD & Testing Philosophy 🔄

---

## 🎯 Path-Based Segregation Strategy

In a large DevOps monorepo, running every test across every script on every commit leads to slow builds, wasted compute credits, and unnecessary CI flakiness.

Our repository strictly isolates workflows using GitHub Actions `paths` triggers:

```yaml
on:
  push:
    branches: [ main, 'feat/**', 'fix/**' ]
    paths:
      - '2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/**'
      - '.github/workflows/ci-cleanup-logs.yml'
```

---

## 🌐 Multi-OS Validation Matrix

All pipelines validate cross-platform compatibility across stable, pinned operating systems:

| Platform | Runner Image | Validated Runtimes & Utilities |
| :--- | :--- | :--- |
| **Ubuntu Linux** | `ubuntu-24.04` | POSIX Bash, Python 3.10-3.12, Go 1.22+, PowerShell Core (`pwsh`), ShellCheck |
| **Apple macOS** | `macos-14` | BSD `stat` / `date` Bash compatibility, Apple Silicon / ARM64 execution |
| **Microsoft Windows** | `windows-2022` | Windows PowerShell 5.1+, PowerShell 7+, Windows path formatting |

---

## 🛡️ Static Analysis & Linting Gates

1. **Bash**: ShellCheck (`shellcheck -x`) enforcing zero SC2059 format string warnings, variable quoting, and POSIX compliance.
2. **Python**: Ruff (`ruff check` and `ruff format --check`) enforcing PEP-8 and modern Python practices.
3. **Go**: `go vet ./...` and `go test -v ./...` ensuring zero race conditions and strict type correctness.
4. **PowerShell**: PSScriptAnalyzer rules and strict typing with `[CmdletBinding()]`.


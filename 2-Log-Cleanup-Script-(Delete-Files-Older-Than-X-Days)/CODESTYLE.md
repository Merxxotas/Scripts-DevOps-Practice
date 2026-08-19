# Log Cleanup Utility - Code Style & Best Practices

This document establishes the coding standards, design patterns, and engineering conventions for the Log Cleanup Utility codebase. All contributions must adhere strictly to these rules to maintain a production-ready, highly maintainable, and reliable DevOps toolset.

---

## 1. Language & Global Conventions
- **English Only:** All code identifiers, function names, parameter names, comments, log messages, and commit messages must be written in English.
- **B2 Level English:** Keep the language clear, simple, and direct. Avoid overly complex idioms or ambiguous wording to ensure universal readability across distributed engineering teams.
- **Branching & PR Workflow:**
  - Direct commits to `main` are prohibited.
  - Work must be performed in dedicated branches named with standard prefixes: `feat/<feature-name>`, `fix/<bug-name>`, or `docs/<docs-name>`.
  - Merges into `main` require passing all automated CI/CD pipeline checks.

---

## 2. Bash Coding Standards (`cleanup_logs.sh`)

- **Strict Mode:** Always include `set -euo pipefail` at the top of every Bash script to fail fast on unset variables or failed pipeline commands.
- **Quoting:** Always quote variable expansions (e.g., `"$file_path"`, `"$log_dir"`) to prevent word-splitting and path-injection issues with spaces or special characters.
- **Naming Conventions:**
  - Functions: `snake_case` with descriptive verb prefixes (e.g., `validate_target_directory`, `format_file_size`).
  - Local Variables: `snake_case` declared with `local` inside functions (e.g., `local file_size=0`).
  - Constants & Environment Variables: `UPPER_SNAKE_CASE` (e.g., `DEFAULT_RETENTION_DAYS`, `PROTECTED_DIRS`).
- **Static Analysis Compliance:** Code must pass ShellCheck validation with zero warnings (`shellcheck -x cleanup_logs.sh`).
- **Portability:** Use standard POSIX-compatible utilities. When relying on GNU/BSD differences (such as `stat` or `date`), implement robust platform-detection fallbacks.

---

## 3. PowerShell Coding Standards (`cleanup_logs.ps1`)

- **Advanced Function Architecture:** Always declare `[CmdletBinding()]` and a strongly-typed `param()` block at the script root.
- **Strict Typing:** Explicitly type all parameters (e.g., `[string]$LogDirectory`, `[int]$Days`, `[switch]$DryRun`).
- **Naming Conventions:**
  - Variables: `PascalCase` or `camelCase` with clear intent (e.g., `$LogDirectory`, `$CutoffDate`, `$ReclaimedBytes`).
  - Parameters: Standard PowerShell approved parameter names (e.g., `-LogDirectory`, `-DryRun`, `-Verbose`).
- **Error Handling:** Use `try { ... } catch { ... }` blocks for all I/O, file deletion, and directory access operations. Do not suppress errors with `-ErrorAction SilentlyContinue` without explicit justification and logging.
- **Static Analysis Compliance:** Code must pass PSScriptAnalyzer validation with zero rule violations.

---

## 4. Debugging & Observability

- **Clear Console Feedback:** Output must clearly differentiate between informational messages, dry-run simulations, success confirmations, and critical errors using standardized ANSI colors or PowerShell host formatting.
- **Deterministic Exit Codes:** Every script must explicitly terminate with standardized exit codes:
  - `0`: Successful execution.
  - `1`: Configuration, argument, or safety violation.
  - `2`: Partial failure (some files failed deletion).
- **Audit Logging:** When a log file is configured, messages must be written in standard ISO-8601 timestamped format: `YYYY-MM-DDTHH:MM:SSZ [LEVEL] Message`.

---

## 5. Commenting Strategy

- **Technical & Concise:** Comments must be brief, precise, and purely technical.
- **Explain the "Why", Not the "What":** Write self-documenting code. Use comments only to explain non-obvious engineering decisions, OS quirks, regex complexities, or platform workarounds.
- **Zero Dead Code:** Never leave commented-out code blocks or orphaned debugging lines in the codebase.
- **Header Documentation:** Scripts must begin with a concise synopsis outlining the purpose, parameters, and example invocations.

---

## 6. Code Examples of Production Standards

### Good Bash Style Example

```bash
#!/bin/bash
set -euo pipefail

# Validates that the target path is not a critical system root
validate_safety_guardrails() {
    local target_dir="${1:-}"
    local resolved_path
    resolved_path=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")

    local protected_roots=("/" "/etc" "/var" "/usr" "/bin" "/sbin" "/boot" "/root")
    for protected in "${protected_roots[@]}"; do
        if [[ "$resolved_path" == "$protected" ]]; then
            echo -e "\033[0;31mError: Target directory '$resolved_path' is protected by safety guardrails.\033[0m" >&2
            return 1
        fi
    done
    return 0
}
```

### Good PowerShell Style Example

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$Days = 30,

    [switch]$DryRun
)

# Protect against accidental execution on root or critical system directories
$Blacklist = @("C:", "C:Windows", "C:WindowsSystem32", "C:Program Files", "C:Program Files (x86)")
$ResolvedPath = (Resolve-Path -Path $LogDirectory -ErrorAction Stop).Path

if ($Blacklist -contains $ResolvedPath) {
    Write-Error "Execution blocked: '$ResolvedPath' is a protected system directory."
    exit 1
}
```


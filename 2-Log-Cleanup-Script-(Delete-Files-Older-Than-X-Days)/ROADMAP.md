# Log Cleanup Utility - Development Roadmap

This roadmap follows Spec-Driven Development (SDD) based on `SPECS.md`. It defines the sequential implementation phases required to deliver the enterprise-grade log cleanup utility.

---

## Phase 1: Foundation & Parameter Parsing
- [ ] **Bash CLI Argument Parser:** Implement robust argument handling in `cleanup_logs.sh` using `getopts` with support for `-d`, `-t`, `-p`, `-m`, `-r`, `-n`, `-l`, `-v`, and `-h`.
- [ ] **PowerShell Parameter Block:** Implement advanced `[CmdletBinding()]` parameter block in `cleanup_logs.ps1` with typed parameters (`[string]$LogDirectory`, `[int]$Days`, `[string]$Pattern`, `[double]$MinSizeMB`, `[switch]$Recursive`, `[switch]$DryRun`, `[string]$LogFile`).
- [ ] **Help & Usage Menus:** Write comprehensive CLI help documentation accessible via `-h` (Bash) and `Get-Help` (PowerShell).

---

## Phase 2: Discovery, Filtering & Safety Guardrails
- [ ] **Root & System Directory Blacklist:** Implement strict validation rejecting execution on root paths (`/`, `C:\`, system directories) to prevent accidental data loss.
- [ ] **Path & Permission Validation:** Verify directory existence and test write/delete permissions before starting discovery.
- [ ] **Age & Timestamp Calculation:**
  - Bash: Calculate cutoff epoch timestamp and filter using `find` (`-mtime` / `-mmin`) with sub-second accuracy where supported.
  - PowerShell: Compute `CutoffDate = (Get-Date).AddDays(-$Days)` and filter files by `LastWriteTime`.
- [ ] **Pattern & Size Filtering:** Filter regular files by glob pattern (default `*.log`) and minimum file size threshold (`-m / -MinSizeMB`).
- [ ] **Recursion Control:** Support both flat single-directory scans (default) and deep traversal (`-r / -Recursive`) without following external symbolic links.

---

## Phase 3: Space Accounting & Execution Layer
- [ ] **Dynamic Space Normalization:** Accumulate file sizes in bytes and implement conversion utilities rendering human-readable formats (Bytes, KB, MB, GB).
- [ ] **Dry-Run Simulation Mode:** When `-n / -DryRun` is set, simulate deletions, log targeted paths, and calculate projected reclaimed space without modifying filesystem state.
- [ ] **Safe File Deletion Engine:** Execute atomic file removals, trap I/O and permission exceptions, and maintain real-time metrics of deleted vs. failed files.

---

## Phase 4: Output Formatting, Audit Logging & Telemetry
- [ ] **Colorized Console Reporting:** Display formatted terminal tables and status icons (`✓` success, `[DRY RUN]` preview, `✗` error) with ANSI color codes.
- [ ] **Persistent Audit File Logging:** If `-l / -LogFile` is configured, append ISO-8601 timestamped audit logs recording run parameters, file actions, and aggregate metrics.
- [ ] **Exit Code Standardization:** Return exit code `0` on clean completion, `1` on configuration/safety violations, and `2` on partial deletion failures.

---

## Phase 5: Monorepo CI/CD Pipeline & Automated Testing
- [ ] **CI Workflow Setup:** Create `.github/workflows/ci-cleanup-logs.yml` configured with path triggers targeting `'2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/**'`.
- [ ] **Static Code Analysis & Linting:**
  - Enforce ShellCheck on `cleanup_logs.sh`.
  - Enforce PSScriptAnalyzer on `cleanup_logs.ps1`.
- [ ] **Automated Test Matrix:**
  - Run Bash test suites across `ubuntu-24.04` and `macos-14` with mock directory trees, fake timestamps, and permission edge cases.
  - Run PowerShell test suites on `windows-2022` validating recursive deletion, dry-run safety, and space reporting.

---

## Phase 6: Final Documentation & Verification
- [ ] **Complete README.md:** Finalize usage instructions, cron examples, Windows Task Scheduler configs, and troubleshooting tables.
- [ ] **Code Style Compliance:** Ensure full compliance with `CODESTYLE.md`.
- [ ] **PR & Merge to Main:** Submit pull request from feature branch, verify all CI checks pass, and merge cleanly into `main`.


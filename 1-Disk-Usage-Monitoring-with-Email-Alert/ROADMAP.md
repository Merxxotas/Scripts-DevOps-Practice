# Disk Usage Monitor — Development Roadmap

This roadmap records the **observed outcomes** of the module's development. Every checked box
is backed by something that actually happened — a commit, a test run or a CI run. Every
unchecked box is something that has **not** happened yet, and it stays unchecked until it does.

Last verified: **2026-10-22**.

---

## Phase 0: Baseline

- [x] **Seed captured as the baseline:** `disk_monitor.sh` and `disk_monitor.ps1` entered git
  as the pre-remediation state, so the fix has a visible before and after (commit `078dda1`).
- [x] **The seed's defects recorded:** the PowerShell side never sent (`Send-MailMessage`
  commented out), `Get-WmiObject` was removed in PowerShell 7 while the file declared
  `#Requires -Version 7.0`, the Bash side read `df -h` column 5, and the Bash side carried CRLF
  line endings, so its shebang could not execute.

---

## Phase 1: The CLI Contract (Bash)

- [x] **Flag surface:** `-p/--partition`, `-t/--threshold`, `-n/--dry-run`, `--notify`,
  `--to`, `--mail-command`, `-l/--log-file`, `-v/--verbose`, `-h/--help`, with the defaults
  `/`, `80` and `mail`.
- [x] **Threshold validation:** an integer outside `1`–`100` is a configuration error with
  exit `1`.
- [x] **Notify backend validation:** a value other than `none` or `mail` is a configuration
  error with exit `1`.
- [x] **Partition existence check:** a partition that does not exist is a configuration error
  with exit `1`.
- [x] **Help text:** `-h` prints the usage, the exit codes and two examples, and exits `0`.

---

## Phase 2: The Portable Measurement Source

- [x] **POSIX output format:** `df -P` replaced `df -h`, so the column layout is identical on
  GNU and macOS.
- [x] **Capacity read from its fixed position:** the fifth field of the six-field POSIX layout,
  so a mount point containing spaces cannot shift it. The value is validated as an integer
  before it is reported.
- [x] **Regression test for the spaced mount point:** a stub whose mount point is
  `/mnt/my disk` drives the parser and asserts the capacity is still read correctly.
- [x] **Windows-native fallback:** `Get-CimInstance Win32_LogicalDisk`, with
  `(Size - FreeSpace) / Size` rounded to an integer percentage.
- [x] **Forced usage value:** `DISK_MONITOR_USAGE_OVERRIDE` short-circuits the measurement and
  is labelled `overridden` in the report and `Source: overridden` in the audit log.
- [x] **Replaceable measurement command:** `DISK_MONITOR_USAGE_COMMAND` supplies an alternative
  `df`, which is what makes the failure paths reachable in a test.

---

## Phase 3: The Notification Transport

- [x] **The mail contract:** `<mail-command> -s <subject> <recipient>` with the body on stdin.
- [x] **Resolution order:** `--mail-command` → `DISK_MONITOR_MAIL_COMMAND` → `mail` → `msmtp`.
- [x] **Recipient resolution:** `--to` → `DISK_MONITOR_TO`; an unset recipient is a
  configuration error with exit `1`.
- [x] **Validate before measure:** the mail agent and the recipient are resolved before the
  disk is touched, so a broken alerting path fails at deployment time.
- [x] **Guardrail `--notify none`:** the hand-off and the alerting configuration are both
  suppressed, and no recipient is required.
- [x] **Guardrail `--dry-run`:** the pending alert is reported and nothing is handed over.
- [x] **Hand-off failure:** a mail agent that refuses the message produces exit `2`, not `0`.

---

## Phase 4: Reporting, Audit Log & Exit Codes

- [x] **One audit line per run:** `<ISO-8601 UTC> [<LEVEL>] <message>`, appended to the file
  given by `-l`.
- [x] **Fixed message vocabulary:** the `INFO` and `ERROR` messages are listed in
  [`SPECS.md`](SPECS.md) §6.2, with one vocabulary on both sides.
- [x] **Best-effort audit write:** a failing log write is reported but never breaks the
  measurement.
- [x] **Exit-code contract:** `0` success, `1` configuration or safety error, `2` partial
  failure — documented in the help text of both implementations.
- [x] **A breach is not a failure:** the run that detects a full disk exits `0`.

---

## Phase 5: Test Suites

- [x] **Bash suite, RED observed before GREEN:** the first observation against the untouched
  seed reported 1 passed and 41 failed, every failure caused by the CRLF shebang (exit 126);
  with the line endings corrected the suite reported 16 passed and 26 failed, isolating the
  missing features from the broken file.
- [x] **Bash suite, GREEN locally:** **55 passed, 0 failed**, re-run against the current tree.
- [x] **PowerShell suite:** mirrors the same 55 assertions against the same public interface.
- [x] **Deterministic isolation:** the measurement command and the mail agent are replaced by
  stubs, so neither suite depends on the host's real disk layout and neither can send a real
  email.
- [x] **Regression coverage for the defects found in review:** the spaced mount point, the
  shadowed parameter, the threshold boundary (equal usage does not alert) and the
  forced-value labelling are all pinned by a test.

---

## Phase 6: CI/CD Pipeline

- [x] **Workflow at the repository root:** `.github/workflows/ci-disk-monitor.yml`, path
  filtered to `1-Disk-Usage-Monitoring-with-Email-Alert/**` and to the workflow file itself.
- [x] **ShellCheck gate:** `shellcheck -x` on the implementation and the suite — **green** on
  `ubuntu-24.04` (run `39639801166`, job `Lint Bash (ShellCheck)`).
- [x] **Bash suite job:** **green** on `ubuntu-24.04` and on `macos-14` (run `39639801166`, jobs
  `Test Bash on ubuntu-24.04` and `Test Bash on macos-14`).
- [x] **PSScriptAnalyzer gate:** defined with the module's `PSScriptAnalyzerSettings.psd1`,
  running on `windows-2022`.
- [x] **PowerShell suite job:** runs on `windows-2022` **and** on `ubuntu-24.04`, so the POSIX
  path is proven on a Unix runner and the Windows volume API is proven on Windows (run
  `39639801166`, jobs `Test PowerShell on windows-2022` and `Test PowerShell on ubuntu-24.04`).
- [x] **PSScriptAnalyzer gate green:** run `39639801166` reports **green** (job
  `Lint PowerShell (PSScriptAnalyzer)`). The `PSUseShouldProcessForStateChangingFunctions`
  warning that run `39638453222` raised on the environment verbs is gone: the verbs were renamed
  to `Enter-TestEnvironment` and `Exit-TestEnvironment` in commit `8391412`, and neither trips
  the state-changing-verb rule.
- [x] **PowerShell suite green:** run `39639801166` reports **55 passed, 0 failed** on both
  runners, the same count as the Bash suite. The twelve exit-code assertions that were open in
  run `39638453222` now observe the real process exit code. The harness kept its last exit code
  in `$script:LastExitCode`, and because PowerShell variable names are case-insensitive that
  name shadowed the automatic `$LASTEXITCODE` inside the script: every read of the tool's exit
  code returned the harness's own initialised `0`. The twelve assertions expecting `1` or `2`
  failed on that value, and the ones expecting `0` passed for the wrong reason. Commit
  `8391412` renamed the state variable to `$script:LastRunExitCode`, so the harness observes
  the code the tool actually returned — and the exit-code contract holds on both
  implementations.

---

## Phase 7: Documentation

- [x] **Module deep dives:** [`docs/ARCHITECTURE_COMPARISON.md`](docs/ARCHITECTURE_COMPARISON.md),
  [`docs/SCENARIOS.md`](docs/SCENARIOS.md) and the three labs in [`docs/labs/`](docs/labs/).
- [x] **Wiki pages:** `wiki/13-Disk-Monitor-Overview.md`,
  `wiki/14-Disk-Monitor-Bash-vs-PowerShell.md`,
  `wiki/15-Disk-Monitor-Scenarios-and-Labs.md`, with the sidebar entries in
  `wiki/_Sidebar.md`.
- [x] **Module contract documents:** [`SPECS.md`](SPECS.md), [`ROADMAP.md`](ROADMAP.md),
  [`CODESTYLE.md`](CODESTYLE.md) and [`README.md`](README.md).
- [x] **Repository index registration:** the row in `MODULES.md` and its module-detail section,
  the module table in the root `README.md` and the `CHANGELOG.md` entry for the module.
- [ ] **Pull request and merge to `main`:** the branch carries work-unit commits, and the
  merge waits for the open CI gates above.

---

## Phase 8: The Universal Transport

The transport, the configuration file and the doctor that turn a Linux-and-a-mail-agent alert
path into one that runs on any Linux distribution and on Windows. A box is checked only when a
run observed it; nothing here is checked because the code was written.

- [x] **The configuration file, both implementations:** thirteen keys in a `key = value` format
  with no parser library, the four-source precedence and the provenance record, proven by **77
  passed, 0 failed** on all four suite jobs in run `39646002248` (commit `a3cea7a` and three
  fixes).
- [x] **The HTTP transport, both implementations:** one transport with no provider-specific
  code, an external client resolved on `PATH`, and a header value that never reaches an output,
  proven by **171 passed, 0 failed** on all four suite jobs in run `39654069737` (commits
  `fd12e3e` and `aae787e`).
- [x] **The doctor, both implementations:** a provenance report, a readiness exit code and the
  remedy of the platform it runs on, proven by **243 passed, 0 failed** on the Bash suite and
  **green on all six CI jobs** in run `39677118704` (commits `cc99bd4`, `df29e38`, `efba983`
  and `e5c32d5`).
- [x] **Parity as a test, not a practice:** the long flags, the parameters, the
  `DISK_MONITOR_*` names and the configuration keys are compared as sets in both directions;
  **257 passed, 0 failed** on the Bash suite, fourteen assertions more than the 243 above
  (commit `a93f0be`).
- [x] **A deferred transport is refused, not reserved:** `--notify smtp` exits `1` and the
  refusal names `none`, `mail` and `http`, on both sides (commit `a93f0be`).
- [x] **An HTTP error status is a failed hand-off, not a delivery:** the client is asked to
  fail, so a `4xx` or `5xx` exits `2` and the audit line says `FAILED` instead of `ALERT SENT`;
  **260 passed, 0 failed** on the Bash suite, three assertions more than the parity commit above.
- [x] **The advisories of the four reviews are closed or accepted:** the ShellCheck finding of
  the parity extractors, the mode whose leading zero the host drops, the remedy the reader
  pastes, the empty-scrape guards and the weak assertions; **271 passed, 0 failed** on the Bash
  suite, fourteen assertions more than the parity commit above.
- [x] **The read-access remedy is paste-safe too:** the correction review found the second sink
  of the quoting defect — the `chmod u+r` remedy of the doctor and of a run interpolated the
  path raw, and the run copy ended with the period of the sentence. Both are quoted with the
  helper the restrict remedy already used, the command ends the line on both sides, and a test
  pastes each remedy from a path that holds a quote; **277 passed, 0 failed** on the Bash suite,
  six assertions more than the advisory batch.
- [x] **The mail transport still works:** a mail run exits `0`, reaches the agent with the
  recipient, and never touches the HTTP client (commit `a93f0be`).
- [x] **The transport work passed its native review:** receipt `review-7f70ee03fae2019c`,
  approved without a correction, with ten non-blocking advisories queued as follow-up.
- [ ] **The branch tip is green on all six CI jobs:** the last observed run predates the parity
  commit, so this box waits for the push.
- [ ] **The module documents describe the transport:** this change is written but not yet
  reviewed or merged.
- [ ] **Merged to `main`.**

> The PowerShell suite and both lint gates are **CI-only on the development host**, where `pwsh`
> and `shellcheck` are not installed. A PowerShell box is checked only when a run reports it,
> never because the Bash side passed.

---

## Non-Goals Recorded for v1

These are decisions, not omissions. They are listed so a later reader does not mistake them
for work that was forgotten.

- One partition per invocation.
- No machine-readable output (`--json` / `--csv`).
- No SMTP transport. `smtp` is refused by name: the HTTP transport covers every webhook and
  chat API, so a second path would add a provider-specific surface without adding a provider.
- No containerisation and no Python implementation.
- No ARM64 CI job — the repository's matrix is x86-only, and adding one touches a shipped
  module's pipeline, which is its own scope.

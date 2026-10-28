# Changelog

All notable changes to this repository are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **No tags exist yet.** Until the first release tag is cut, entries are grouped by date rather
> than by version number. See [Versioning](#versioning) for the convention going forward.

---

## [Unreleased]

### Added

- **`AGENTS.md`** — the router for the repository: what it is, the module contract, branching and
  commit conventions, the CI model, the code standards baseline, a navigation map, and the known
  state and gotchas.
- **`MODULES.md`** — inventory and status of all 11 modules, the seed-to-shipped remediation
  checklist, and the recommended build order.
- **`SECURITY.md`** — supported versions, private vulnerability reporting, response targets, a
  precise in-scope / out-of-scope definition, and security guidance for users and contributors.
- **`CONTRIBUTING.md`** — the contributor-facing workflow: ODD process, branching, commit format,
  testing rules, module contract, and a pull request checklist.
- **`CODE_OF_CONDUCT.md`** — Contributor Covenant 2.1, adapted.
- **`SUPPORT.md`** — support channels, scope of support, and the environment details worth
  attaching to a bug report.
- **`CHANGELOG.md`** — this file.
- **`.github/PULL_REQUEST_TEMPLATE.md`** — verification, documentation, and risk checklist.
- **`.github/ISSUE_TEMPLATE/bug_report.md`** and **`.github/ISSUE_TEMPLATE/feature_request.md`** —
  structured reporting paths.
- **`odd/METHODOLOGY.md`** — the expanded ODD protocol for this repository: the seven phases with
  their local rules, the ODD-versus-SDD relationship, the feature-document format, task sizing,
  the test-first policy and the delegation triggers. Moved out of `AGENTS.md` so that file can stay
  within a readable size while remaining the entry point.

### Changed

- **Methodology: Spec-Driven Development → Organic Driven Development (ODD).** The repo now runs the
  gentle-ai ODD protocol — authorize, explore, resolve uncertainty, classify, track, implement task
  by task, close — with a mandatory `Risk:` line on every code change. Module artifacts
  (`SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md`, `docs/`) remain mandatory; they are now
  produced *by* the ODD flow rather than written entirely up front. See
  [`AGENTS.md` §2](AGENTS.md).

- **`AGENTS.md` reduced from 551 to 300 lines, and rebuilt as a router instead of a second copy of
  everything.** The file was duplicating two other sources — it restated the contributor workflow
  already in `CONTRIBUTING.md`, and restated the ODD protocol already installed with the agent
  harness — so three copies of the same facts could drift apart. It now holds only the
  agent-facing invariants, the module contract, the CI model, the known gotchas and a navigation
  map, and points at the single home of every other fact.

  Every section number (`§1`–`§10`, `§2.1`–`§2.10`, `§5.1`, `§5.2`) and every block quoted
  verbatim as a specification in `odd/tasks/module-5-capstone-shipment.md` were preserved, so no
  cross-reference in the repository broke.

- **`CONTRIBUTING.md` §Code Standards is now the full shared baseline** — language and naming
  conventions, log levels, commenting and docstring rules, shell specifics, and the security
  rules. It previously deferred to `AGENTS.md` §7 for detail that `AGENTS.md` no longer carried,
  which had left those rules with no home; the direction is now one-way: `AGENTS.md` §7 holds the
  must-know summary and points here for the rest.

---

## 2026-10-22 — Disk Usage Monitoring module: universal transport

**Module 1 — Disk Usage Monitoring with Email Alert** gains a transport that works on any Linux
distribution or Windows version, a minimal configuration file and a `--doctor` command. The `mail`
transport keeps working exactly as before; the new `http` transport is one request with a body to
a URL, so every HTTP notification service is covered without provider-specific code.

### Added

- **The `http` transport** — `--notify http` sends the alert as a request with a body to any URL,
  with `--url`, `--body-template`, `--header` and `--timeout`, and the method from the
  configuration file. The body template supports `{subject}`, `{body}`, `{partition}`, `{usage}`,
  `{threshold}`, `{recipient}`, `{host}` and `{timestamp}`, so a JSON template speaks to Telegram,
  Discord and Slack. The client is an external command, resolved as `--http-command` →
  `DISK_MONITOR_HTTP_COMMAND` → `curl`, so the same client is used on every platform.
- **The configuration file** — a minimal `key = value` format with 13 keys and no parser library,
  because a minimal Linux image has no `jq` or TOML library and Windows PowerShell has no TOML
  parser. The path resolves as `--config` → `DISK_MONITOR_CONFIG` → `./.diskmonitor.conf` →
  `~/.config/disk-monitor/config`, and every setting resolves as flag → `DISK_MONITOR_*`
  environment variable → file → built-in default.
- **`--doctor`** — reports the resolved configuration and where each value came from, whether the
  measurement command and the transport client resolve, and whether the recipient or endpoint is
  set. It measures nothing and sends nothing. Exit `0` when the tool is ready and `1` when
  something is missing, with a one-line remedy for the platform it was found on.
- **A parity test** — each suite reads the other implementation as a source file and compares the
  flags, the `DISK_MONITOR_*` names and the configuration keys as set equality in both directions,
  so a flag added on one side and forgotten on the other fails both suites.

### Changed

- **The transport set is `none`, `mail` and `http`.** `mail` is unchanged, and any other value,
  including `smtp`, exits `1` with a refusal that names the three supported transports.
- **A header value is never printed and never written to the audit log**, because a header may
  carry a bearer token. `.diskmonitor.conf` is git-ignored for the same reason.
- **The exit codes keep their meaning** — `0` success, `1` configuration or safety violation, `2`
  partial failure. A missing endpoint, a missing HTTP client, an unreadable configuration file and
  a malformed value exit `1`; an attempted request that fails exits `2`.
- **`MODULES.md` and the root `README.md`** — module 1 now describes both transports, the observed
  Bash test count and the six-job CI matrix.

### Fixed

- **The PowerShell help omitted `http`.** The comment-based help offered `none` and `mail`, so
  `Get-Help` on Windows described a transport set without the new backend. The parity test caught
  it, and the help now lists all three.
- **The doctor called a readable file private.** The host prints a mode without its leading
  zeros, so a file whose owner has no permission lost the digit the classifier assumed, and a
  file the group and the others could read was reported as private. The mode is now read from
  the right, whatever its length.
- **The remedy of the doctor broke on a path that holds a quote**, which made the command the
  reader pastes unusable. The path is quoted for the shell of the platform, and the Windows
  remedy removes the explicit `Everyone` grant that caused the warning instead of leaving it in
  place. The read-access remedy of both the doctor and a run carried the same defect in a second
  place, and its run-path copy ended with the period of the sentence, which the reader would have
  pasted as part of the path; both are quoted now and the command ends the line.
- **An unreadable configuration file killed the run with a shell error** instead of a typed
  configuration error, and the doctor — the command whose job is to name that problem — never
  ran. An existing file this account cannot read is now a problem for the doctor and exit `1`
  for a run.
- **The parity extractors tripped the ShellCheck gate.** A literal `$` in a single-quoted `sed`
  program is reported as SC2016, so the lint job of the Bash half failed; the anchor now spells
  the `$` as a bracket expression.

### Verification

- **Bash suite, local** — 277 assertions passed, 0 failed.
- **PowerShell suite and both lint gates** — CI-only on the development machine, which has neither
  `pwsh` nor `shellcheck`; the workflow runs the PowerShell suite on `windows-2022` and
  `ubuntu-24.04`, and runs ShellCheck and PSScriptAnalyzer on the implementation and its suite.

---

## 2026-10-21 — Disk Usage Monitoring module

**Module 1 — Disk Usage Monitoring with Email Alert** goes from a seed script pair to a fully
shipped module: a threshold monitor that measures one mounted filesystem and hands an alert to the
mail agent the host already provides. It holds no credentials and opens no socket of its own, and
it is the template the remaining seven seed modules will be converted to.

### Added — the module

- **`1-Disk-Usage-Monitoring-with-Email-Alert/`** — the whole module, tracked for the first time.
  A Bash implementation and a PowerShell 7 implementation of one contract: the same flags, the
  same defaults, the same validation, the same exit codes and the same messages.
- **`disk_monitor.sh`** and **`disk_monitor.ps1`** — the two implementations. The Bash side takes
  `-p, --partition`, `-t, --threshold`, `-n, --dry-run`, `--notify`, `--to`, `--mail-command`,
  `-l, --log-file`, `-v, --verbose` and `-h, --help`; the PowerShell side takes `-Partition`,
  `-Threshold`, `-DryRun`, `-Notify`, `-To`, `-MailCommand`, `-LogFile`, `-Verbose` and `-Help`.
- **Exit-code contract** — `0` success, `1` configuration or safety error, `2` partial failure.
  Crossing the threshold is not a failure: the alert is the product, so the run still exits `0`.
- **A credential-free notification transport** — the alert is composed and handed to the host's
  mail agent as `<mail-command> -s <subject> <recipient>`, with the body on stdin. The agent is
  resolved from `--mail-command`, then `DISK_MONITOR_MAIL_COMMAND`, then the platform default
  candidates (`mail`, then `msmtp`), and the whole alerting path is validated before the disk is
  measured.
- **Guardrails** — a dry-run mode that reports the pending alert and hands nothing to the mail
  agent, and a `--notify none` backend that suppresses the hand-off entirely and needs no
  recipient.
- **An ISO-8601 audit log** — `--log-file` appends one line per run recording the usage, where the
  number came from (`measured` or `overridden`) and the threshold it was compared against.
- **`tests/test_disk_monitor.sh`** and **`tests/test_disk_monitor.ps1`** — 25 scenarios and 55
  assertions per implementation, mirrored one for one so both sides are held to the same contract.
  The measurement command and the mail agent are stubbed, so the suite never depends on the host's
  real disk layout and never sends a real email.
- **`docs/ARCHITECTURE_COMPARISON.md`** — the two implementations side by side, where they must
  agree and where the platform requires them to differ.
- **`docs/SCENARIOS.md`** — the operational failure modes and their exit codes.
- **`docs/labs/LAB1…LAB3.md`** — three hands-on labs.
- **`SPECS.md`**, **`ROADMAP.md`**, **`CODESTYLE.md`** and a complete `README.md` — the module
  contract, satisfied.

### Added — CI

- **`.github/workflows/ci-disk-monitor.yml`** — path-filtered to the module folder, four jobs:
  ShellCheck on the Bash script and its suite, the Bash suite on `ubuntu-24.04` and `macos-14`,
  PSScriptAnalyzer on the PowerShell script and its suite, and the PowerShell suite on
  `windows-2022` and `ubuntu-24.04`.

### Fixed

- **The Bash script could not execute at all.** It carried CRLF line endings, so the shebang read
  `/bin/bash^M` and every invocation exited 126. The module had never been in git, so nobody had
  ever run the file.
- **The Bash side read the capacity from column 5 of `df -h`.** That is the macOS column-layout
  trap that broke module 5. It now reads the fixed fifth field of the POSIX `df -P` layout.
- **The capacity was read from the second-to-last field of `df -P`.** That is only correct while
  the mount point is a single word, because the field is split on whitespace. Both sides now read
  field five, and a regression test drives a stub whose mount point contains a space.
- **The PowerShell side never sent anything.** The `Send-MailMessage` call was commented out, so
  it printed "prepared" and stopped, while the Bash side sent for real.
- **`Get-WmiObject` was removed in PowerShell 7**, but the file declared `#Requires -Version 7.0`,
  so its fallback path was dead on the version it targeted. The Windows path now uses
  `Get-CimInstance Win32_LogicalDisk`, with the POSIX path as the primary one.
- **`-MailCommand` was silently discarded.** PowerShell variables are case-insensitive, so the
  local `$mailCommand` shadowed the `$MailCommand` parameter and only the environment variable
  worked. The local is renamed, and the same shadowing is removed from the measurement command.
- **The PowerShell harness reported assertions it never ran.** Under strict mode a mandatory
  string parameter rejects an empty value, so an assertion against empty output raised a binding
  error that was printed and skipped. The assertions accept empty values now, and an erroring
  assertion fails the run instead of disappearing from the summary.
- **The Bash harness created the mail-capture file itself**, so "the mail agent was never
  invoked" could never be asserted by the file's absence. The assertion now checks the capture's
  contents.
- **The PowerShell suite failed PSScriptAnalyzer** — two unapproved verbs, two plural nouns, and
  shared counters held in global variables. The verbs are approved, the nouns are singular, and
  the shared state lives in the script scope.
- **The seed had no CLI parser, no guardrails, no dry-run, no exit-code contract and no tests.**
  All of it is new.

### Changed

- **`MODULES.md` and `README.md`** — module 1 is marked shipped, the seed group is now seven
  modules, and the build order starts at module 3.

### Verification

- **Bash suite, local** — 55 assertions, 55 passed, 0 failed.
- **PowerShell suite and the two lint gates** — CI-only on the development machine, which has
  neither `pwsh` nor `shellcheck`; the pipeline runs the PowerShell suite on Windows and on
  Ubuntu.

### Known gaps

Recorded rather than hidden: one partition per invocation, no `--json` or `--csv` output and no
direct SMTP or webhook transport are deliberate v1 non-goals; the audit write is best-effort, so
on a full disk the audit line may be the thing that cannot be written; and the CI matrix is
x86-only, so there is no ARM64 runner yet.

### Documentation — knowledge base

- **`wiki/13-Disk-Monitor-Overview.md`**, **`wiki/14-Disk-Monitor-Bash-vs-PowerShell.md`** and
  **`wiki/15-Disk-Monitor-Scenarios-and-Labs.md`**, with the sidebar, the home page and
  `wiki/01-Monorepo-Architecture.md` updated.

---

## 2026-10-27 — Automated Database Backup module

**Module 3 — Automated Database Backup with Timestamp** goes from a seed script pair to a fully
shipped module: a cross-platform backup utility that runs a dump, compresses the result, stores
it in a backup directory, and prunes backups older than a retention window. Supports MySQL and
PostgreSQL. Full Bash + PowerShell parity.

### Added — the module

- **`3-Automated-Database-Backup-with-Timestamp/`** — the whole module, tracked for the first
  time. A Bash implementation and a PowerShell implementation of one contract.
- **`db_backup.sh`** and **`db_backup.ps1`** — the two implementations, with CLI flags `-t/--db-type`,
  `-n/--db-name`, `-u/--db-user`, `--db-password`, `-d/--backup-dir`, `-r/--retention-days`,
  `-c/--compress`, `--no-compress`, `--dry-run`, `-l/--log-file`, `-v/--verbose`, `-h/--help`.
- **Exit-code contract** — `0` success, `1` configuration/safety violation, `2` partial failure.
- **Credential safety** — password from `--db-password` or `DB_BACKUP_PASSWORD`, passed via
  `MYSQL_PWD` / `PGPASSWORD`, never echoed or logged.
- **Safety guardrails** — path blacklist for system directories, creatable/writable backup dir,
  dry-run mode, standardized exit codes.
- **Compression** — gzip on Bash, zip on PowerShell; raw `.sql` removed after success.
- **Retention pruning** — deletes backups older than N days by mtime; best-effort per file.
- **ISO-8601 audit log** — `--log-file` appends one line per run.
- **`tests/test_db_backup.sh`** (26 tests) and **`tests/test_db_backup.ps1`** (31 tests, incl.
  parity proof). Stubs `mysqldump`/`pg_dump` on `PATH`; no real database required.
- **`SPECS.md`**, **`ROADMAP.md`**, **`CODESTYLE.md`**, **`README.md`**.
- **`docs/ARCHITECTURE_COMPARISON.md`**, **`docs/SCENARIOS.md`**, **`docs/labs/LAB1-3.md`**.

### Added — CI

- **`.github/workflows/ci-database-backup.yml`** — path-filtered, multi-OS matrix.

### Added — knowledge base

- **`wiki/16-Database-Backup-Overview.md`**, **`wiki/17-Database-Backup-Bash-vs-PowerShell.md`**,
  **`wiki/18-Database-Backup-Scenarios-and-Labs.md`**, with the sidebar, the home page and
  `wiki/01-Monorepo-Architecture.md` updated.

### Changed

- **`MODULES.md`**, **`README.md`**, **`AGENTS.md`** — module 3 marked shipped; seed group now six
  modules.

### Verification

- **Bash suite, local** — 26 tests, 0 failures.
- **PowerShell suite** — CI-only (no `pwsh` on the development machine).

### Known gaps

Recorded rather than hidden: no incremental/differential backups, no cloud streaming, no MSSQL,
no encryption of the backup file, no `--json`/`--csv` output. One database per invocation. Audit
write is best-effort.

---

## 2026-10-28 — Service Monitor and Auto-Restart module

**Module 4 — Service Monitor and Auto-Restart** goes from a seed script pair to a fully shipped
module: a cross-platform utility that checks whether a named service is running and, when it is
down, attempts to restart it up to a configurable number of times with a configurable delay.
Full Bash + PowerShell parity.

### Added — the module

- **`4-Service-Monitor-And-Auto-Restart/`** — the whole module, tracked for the first time. A Bash
  implementation and a PowerShell implementation of one contract.
- **`service_monitor.sh`** and **`service_monitor.ps1`** — the two implementations, with CLI flags
  `-s/--service`, `-r/--max-retries`, `--retry-delay`, `--dry-run`, `--audit-log`,
  `-v/--verbose`, `-h/--help`.
- **Exit-code contract** — `0` success, `1` configuration/safety violation, `2` partial failure.
- **Safety guardrails** — service-name validation, existence check, validates numeric arguments,
  dry-run mode.
- **Notifications** — syslog on Bash, Windows Event Log on PowerShell (best-effort).
- **ISO-8601 audit log** — `--audit-log` appends one line per run.
- **`tests/test_service_monitor.sh`** (20 tests) and **`tests/test_service_monitor.ps1`**. Bash suite
  stubs `systemctl` via a fake binary on `PATH`; no real system services touched.
- **`SPECS.md`**, **`ROADMAP.md`**, **`CODESTYLE.md`**, **`README.md`**.
- **`docs/ARCHITECTURE_COMPARISON.md`**, **`docs/SCENARIOS.md`**, **`docs/labs/LAB1-3.md`**.

### Added — CI

- **`.github/workflows/ci-service-monitor.yml`** — path-filtered, multi-OS matrix.

### Added — knowledge base

- **`wiki/22-Service-Monitor-Overview.md`**, **`wiki/23-Service-Monitor-Bash-vs-PowerShell.md`**,
  **`wiki/24-Service-Monitor-Scenarios-and-Labs.md`**, with the sidebar updated.

### Changed

- **`MODULES.md`**, **`README.md`**, **`AGENTS.md`** — module 4 marked shipped; seed group now
  four modules.

### Verification

- **Bash suite, local** — 20 tests, 0 failures.
- **PowerShell suite** — CI-only (no `pwsh` on the development machine).

### Known gaps

Recorded rather than hidden: no continuous watch loop, no HTTP/TCP health probe, no
dependency-graph restart, no `--json`/`--csv` output, no service enable/disable. One service per
invocation. Audit write is best-effort.

---

## 2026-10-27 — Log Rotation and Compression module

**Module 8 — Log Rotation and Compression** goes from a seed script pair to a fully shipped
module: a cross-platform utility that rotates a single log file when it exceeds a size
threshold, compresses the current log into the first backup slot, truncates the active log, and
prunes backups beyond the retention count. Full Bash + PowerShell parity.

### Added — the module

- **`8-Log-Rotation-and-Compression/`** — the whole module, tracked for the first time. A Bash
  implementation and a PowerShell implementation of one contract.
- **`log_rotate.sh`** and **`log_rotate.ps1`** — the two implementations, with CLI flags
  `-f/--log-file`, `-m/--max-size-mb`, `-c/--backup-count`, `-z/--compress`, `--no-compress`,
  `--force`, `--dry-run`, `--audit-log`, `-v/--verbose`, `-h/--help`.
- **Exit-code contract** — `0` success, `1` configuration/safety violation, `2` partial failure.
- **Safety guardrails** — path blacklist for system directories, requires an existing regular log
  file, validates numeric arguments, dry-run mode.
- **Compression** — gzip on Bash, zip on PowerShell; raw file kept with `--no-compress`.
- **Retention pruning** — shifts backups and removes any index beyond the count; best-effort per file.
- **ISO-8601 audit log** — `--audit-log` appends one line per run.
- **`tests/test_log_rotate.sh`** (33 tests) and **`tests/test_log_rotate.ps1`**. Runs under a temp
  directory; no real system paths touched.
- **`SPECS.md`**, **`ROADMAP.md`**, **`CODESTYLE.md`**, **`README.md`**.
- **`docs/ARCHITECTURE_COMPARISON.md`**, **`docs/SCENARIOS.md`**, **`docs/labs/LAB1-3.md`**.

### Added — CI

- **`.github/workflows/ci-log-rotation.yml`** — path-filtered, multi-OS matrix.

### Added — knowledge base

- **`wiki/19-Log-Rotation-Overview.md`**, **`wiki/20-Log-Rotation-Bash-vs-PowerShell.md`**,
  **`wiki/21-Log-Rotation-Scenarios-and-Labs.md`**, with the sidebar, the home page and
  `wiki/01-Monorepo-Architecture.md` updated.

### Changed

- **`MODULES.md`**, **`README.md`**, **`AGENTS.md`** — module 8 marked shipped; seed group now
  five modules.

### Verification

- **Bash suite, local** — 33 tests, 0 failures.
- **PowerShell suite** — CI-only (no `pwsh` on the development machine).

### Known gaps

Recorded rather than hidden: no time-based or date-stamped rotation, no `copytruncate`/`create`
modes, no post-rotation hook, no compression of already-rotated backups, no `--json`/`--csv`
output. One log file per invocation. Audit write is best-effort.

---

## 2026-10-20 — CPU and Memory Usage Monitor module

**Module 5 — CPU and Memory Usage Monitor** goes from a capstone that existed only on disk to a
fully shipped module: three implementations of the same tool, one shared data contract, a test
suite per platform, and a CI pipeline that actually executes.

### Added — the module

- **`5-CPU-and-Memory-Usage-Monitor/`** — the whole module, tracked for the first time. Four
  stages: native Bash and PowerShell scripts, a unified Python package, a hardened container
  image, and the pipeline documentation.
- **`tests/test_system_monitor.sh`** and **`tests/test_system_monitor.ps1`** — 20 Bash tests and
  18 PowerShell tests, mirroring each other so both native implementations are held to the same
  contract. They cover the flags, the exit codes, the emitted files, the JSON and CSV key names,
  the locale independence and the `-WhatIf` preview.
- **`docs/ARCHITECTURE_COMPARISON.md`** — the three implementations side by side, where they agree
  and where they still differ.
- **`docs/SCENARIOS.md`** — scheduled checks, runaway-process triage, safe process termination,
  and the locale failure mode.
- **`docs/labs/LAB1…LAB3.md`** — three hands-on labs. Every command in them was executed and the
  expected output is the real output.
- **`SPECS.md`**, **`ROADMAP.md`**, **`CODESTYLE.md`** and a complete `README.md` — the module
  contract, satisfied.

### Added — CI

- **`.github/workflows/ci-cpu-monitor.yml`** — path-filtered to the module folder, six jobs:
  ShellCheck and the Bash suite on Linux and macOS, PSScriptAnalyzer and the PowerShell suite on
  Windows and Linux, ruff and pytest for Stage 2 **and** Stage 3 across three operating systems
  and Python 3.9, 3.12 and 3.13, and a container build with a smoke test.

### Fixed

- **`--cpu-threshold` and `--mem-threshold` had no effect at all.** The CLI parsed both flags and
  stored them, but the display exporter never received them and hardcoded 80. They now reach the
  output, with a regression test per flag.
- **The Bash script failed on every run under a comma-decimal locale.** `LC_NUMERIC=es_CO.UTF-8`
  made `printf` reject the values `awk` produced, so a successful run exited 1. The script now pins
  `LC_ALL`, and the test suite runs it under a comma-decimal locale to prove it.
- **The Bash script failed on any host running more than 100 processes.** `head` closed the pipe
  early, `sort` took a SIGPIPE, and `pipefail` turned that into a failed pipeline. The limit now
  lives inside the consumer.
- **The PowerShell script could not run on Linux at all.** The kill log directory came from
  `$env:TEMP`, which only exists on Windows, so `Join-Path` received a null path.
- **The container image had never been buildable.** The builder stage copied only
  `pyproject.toml`, so the package metadata had no `README.md` to point at and hatchling had no
  `src/system_monitor` to build; the install was also editable, resolving the package back to a
  stage the runtime image does not have.
- **The JSON and CSV contracts disagreed between the implementations.** All three now emit the same
  snake_case key names.
- **The two failing tests** — contract drift between the tests and the implementation, not
  production defects.
- **286 lint errors in the Python package** — `ruff check` and `ruff format --check` are clean.
- **Mojibake in the Bash log messages** — the emoji had been double-encoded when the file was
  authored on Windows, so the script printed garbage. The file is plain ASCII now.
- **The PowerShell script now supports `-WhatIf` and `-Confirm`** on the three functions that stop
  and restart processes, while the default still acts immediately without prompting.

### Changed

- **`.gitattributes` added at the repository root.** Line endings are now pinned for every text
  file, implementing the fix AGENTS.md §9 already recommended. Without it, a Windows checkout
  turned the Bash shebangs into CRLF and broke the scripts.
- **`MODULES.md`, `README.md` and `AGENTS.md`** — module 5 is marked shipped, the build order now
  starts at module 1, and the known gaps are recorded rather than hidden.

### Documentation — knowledge base

- **`wiki/10-CPU-Monitor-Overview.md`**, **`wiki/11-CPU-Monitor-Bash-vs-PowerShell.md`** and
  **`wiki/12-CPU-Monitor-Scenarios-and-Labs.md`**, with the sidebar and home page updated.

---

## 2026-08-19 — Log Cleanup module and knowledge base

**Module 2 — Log Cleanup (Delete Files Older Than X Days)** goes from seed script to fully shipped
module. Enterprise Bash and PowerShell implementations with 100% feature parity, a test suite per
platform, and a dedicated CI pipeline.

### Added

- **`cleanup_logs.sh`** — POSIX Bash implementation with `getopts` parsing for `-d`, `-t`, `-p`,
  `-m`, `-r`, `-n`, `-l`, `-v`, `-h`.
- **`cleanup_logs.ps1`** — PowerShell implementation with a typed `[CmdletBinding()]` parameter block:
  `LogDirectory`, `Days`, `Pattern`, `MinSizeMB`, `Recursive`, `DryRun`, `LogFile`.
- **Safety guardrails** — a blacklist that refuses root and critical system paths (`/`, `/etc`,
  `/var`, `C:\`, `C:\Windows`), plus existence and write/delete permission validation.
- **Dry-run simulation** — previews targeted paths and projected reclaimed space without touching
  the filesystem.
- **Space accounting** — byte accumulation rendered as Bytes, KB, MB and GB.
- **Persistent audit logging** — optional ISO-8601 timestamped log of run parameters, per-file
  actions and aggregate metrics.
- **Exit code contract** — `0` success, `1` configuration or safety violation, `2` partial failure.
- **`tests/test_cleanup_logs.sh`** and **`tests/test_cleanup_logs.ps1`** — 12 Bash tests and the
  PowerShell equivalent, covering help, missing arguments, guardrail blocks, dry-run preservation,
  successful deletion, recent-file retention, flat versus recursive scans, and audit log creation.
- **`docs/ARCHITECTURE_COMPARISON.md`** — POSIX byte streams versus .NET object pipelines, with a
  feature matrix and a detailed architecture breakdown.
- **`docs/SCENARIOS.md`** — production scenarios for high-traffic Nginx/Apache servers, Windows
  Server IIS, automated database dump purging, and CI/CD runner artifact pruning.
- **`docs/labs/LAB1…LAB3.md`** — three hands-on labs: basic retention and dry-run preview, recursive
  traversal with size thresholds, and production scheduling with audit logging.

### Added — knowledge base

- **`wiki/`** — ten-page knowledge base: monorepo architecture, EventOps overview, Python versus
  Go comparison, EventOps scenarios and labs, Log Cleanup overview, Bash versus PowerShell
  comparison, Log Cleanup scenarios and labs, CI/CD philosophy, code standards, plus home,
  sidebar and footer.

### Added — CI

- **`.github/workflows/ci-cleanup-logs.yml`** — path-filtered to the module folder. ShellCheck on
  the Bash script and its test suite, the Bash suite on `ubuntu-24.04` and `macos-14`, and the
  PowerShell suite on `windows-2022` and `ubuntu-24.04`.

### Fixed

- **ShellCheck SC2059 warnings** in the Bash implementation.
- **macOS path guardrails** — behaviour that differed between GNU and BSD userland.
- **PowerShell invocation syntax** in the CI workflow.
- **PowerShell cross-platform path nesting** — nested directory handling on non-Windows runners.
- **Flat scan filter** — the flat (non-recursive) mode no longer descends into subdirectories.

### Documentation

- **Module artifacts** — `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md` and a complete `README.md` with
  usage, a full CLI reference, cron and Task Scheduler examples, and a troubleshooting table.

---

## 2026-08-12 — 2026-08-13 — EventOps module

**Module 11 — Scheduling and Automation** introduces the multi-language dimension of the
repository: a Python event-driven automation daemon and its Go port.

### Added — Python (`EventOps/`)

- **Rule engine** — parses, validates and loads `rules.json`.
- **Webhook server trigger** — a built on `http.server`; extracts the URI path, matches it against
  `webhook` rules, executes on a match, and returns `200 OK` with a JSON payload or `404 Not Found`.
- **File watcher trigger** — built on `watchdog`; matches `on_modified` events against `watch_path`
  rules with a 2-second debounce cooldown.
- **Asynchronous executor** — runs actions on a background thread so long-running scripts never
  block a trigger, piping stdout and stderr into the central logger.
- **Centralized logging** — events recorded to `eventops.log` with timestamps and levels.
- **Daemon integration** — `eventops.py` starts both triggers as background threads with graceful
  shutdown on `KeyboardInterrupt`.
- **Tests** — unit and integration coverage for the rule engine, executor, file watcher, webhook
  server and end-to-end event routing.

### Added — Go (`EventOps-Go/`)

- **Go port** of the full architecture — `main.go` plus `pkg/ruleengine`, `pkg/executor`,
  `pkg/triggers` and `pkg/logger`, using `fsnotify` for filesystem monitoring.
- **CLI entry point** and a full unit plus end-to-end integration test suite.

### Added — documentation

- **`docs/SCENARIOS.md`**, **`docs/ARCHITECTURE_COMPARISON.md`** and **three interactive labs** —
  webhook automation, file watcher debouncing, and Go versus Python.
- **`SPECS.md`**, **`ROADMAP.md`**, **`CODESTYLE.md`** and a module `README.md`.

### Added — CI

- **`.github/workflows/ci-eventops.yml`** — `ubuntu-24.04`, `macos-14` and `windows-2022` across
  Python `3.10`, `3.11` and `3.12`. Ruff linting and format check, pytest, and — after the Go port
  — `go vet` and `go test`.

### Fixed

- **Rule engine path casing** — `watch_path` equality preserved the original absolute path casing,
  fixing a Windows comparison failure.
- **Windows path quoting** in end-to-end integration tests.
- **Cross-platform string equality** in the Go executor unit test.
- **Native OS shell redirection** for cross-platform integration tests.
- **Pipe reader race** — the Go executor now waits for pipe readers before calling `cmd.Wait`.
- **Windows file path formatting** for `cmd` redirection, using forward slashes.

### Changed

- **README** — reframed the repository as a multi-language monorepo (Bash, PowerShell, Python, Go)
  rather than a Bash and PowerShell collection.
- **CI triggers** — enabled on `feat/**` and `fix/**` branches, not only `main`.
- **OS versions pinned** — `ubuntu-24.04`, `macos-14`, `windows-2022` instead of floating aliases,
  with the README badge URL corrected.

### Repository initialization

- Initial structure, LICENSE, `.gitignore`, and the EventOps documentation set.

---

## Versioning

- Module versions are tracked independently in each module's own documentation. The EventOps Go
  implementation is currently **v2.0.0**; the Log Cleanup utility is **v1.0.0**.
- The **repository** follows SemVer from the first release tag onward. A tag on `main` marks a
  repository release and this file gains a version heading.
- Every tag maps to a date heading here until that tag exists.

---

## Related

- [`AGENTS.md`](AGENTS.md) · [`MODULES.md`](MODULES.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md)

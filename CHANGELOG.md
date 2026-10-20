# Changelog

All notable changes to this repository are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **No tags exist yet.** Until the first release tag is cut, entries are grouped by date rather
> than by version number. See [Versioning](#versioning) for the convention going forward.

---

## [Unreleased]

### Added

- **`AGENTS.md`** — the single source of truth for the repository: what it is, the ODD working
  methodology, the module contract, branching and commit conventions, the CI model, testing and
  code standards, a navigation map, and the known state and gotchas.
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

### Changed

- **Methodology: Spec-Driven Development → Organic Driven Development (ODD).** The repo now runs the
  gentle-ai ODD protocol — authorize, explore, resolve uncertainty, classify, track, implement task
  by task, close — with a mandatory `Risk:` line on every code change. Module artifacts
  (`SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md`, `docs/`) remain mandatory; they are now
  produced *by* the ODD flow rather than written entirely up front. See
  [`AGENTS.md` §2](AGENTS.md).

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

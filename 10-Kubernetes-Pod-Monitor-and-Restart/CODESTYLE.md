# Kubernetes Pod Monitor and Restart — Code Style

Module-specific conventions. The repository-wide baseline lives in [`CONTRIBUTING.md`](../CONTRIBUTING.md)
and [`wiki/09-Code-Style-and-Standards.md`](../wiki/09-Code-Style-and-Standards.md).

## Naming

- Bash: `snake_case` functions and variables; `UPPER_SNAKE_CASE` constants/defaults.
- PowerShell: `Verb-Noun` functions (approved verbs); `PascalCase` parameters; `$script:` scope for state.
- CLI flags: `kebab-case` on Bash, `PascalCase` on PowerShell, identical semantics.

## Structure

- `set -euo pipefail` and `IFS=$'\n\t'` at the top of the Bash script.
- A single `main()` entry point invoked as `main "$@"`.
- Color constants are `readonly`.
- One function per concern (parse, validate, discover, act, audit).

## Safety

- Validate namespace, label selector and threshold before any cluster call.
- Verify kubectl is available before acting.
- Dry-run never deletes a pod.
- Graceful delete by default; hard delete only with `--force`.
- Audit log writes are best-effort (`|| true` / try-catch).

## Logging

- Colorized output to stdout; errors to stderr.
- Audit log writes are best-effort.

## Tests

- All kubectl calls are stubbed under a temp dir (Bash) or via PATH (PowerShell).
- Tests drive the public interface only (flags, exit codes, output).
- Bash suite stubs `kubectl` via fake binaries on `PATH`.

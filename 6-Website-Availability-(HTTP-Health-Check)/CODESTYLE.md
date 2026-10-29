# Website Availability (HTTP Health Check) — Code Style

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
- One function per concern (parse, validate, request, determine, output, audit).

## Safety

- Validate URL scheme, timeout and expected code before any request.
- Dry-run never makes a request.
- No redirect following in v1.
- Audit log writes are best-effort (`|| true` / try-catch).

## Logging

- Colorized, curlie-inspired output to stdout; errors to stderr.
- Audit log writes are best-effort.

## Tests

- All HTTP requests are stubbed under a temp dir (Bash) or mocked (PowerShell).
- Tests drive the public interface only (flags, exit codes, output).
- Bash suite stubs `curl` via fake binaries on `PATH`.

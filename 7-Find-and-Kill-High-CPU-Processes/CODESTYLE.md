# Find and Kill High-CPU Processes — Code Style

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
- One function per concern (parse, discover, guardrail, kill, audit).

## Safety

- Never target PID 0, 1, self, parent, or kernel threads (comm in brackets).
- Validate the threshold before any process listing.
- Dry-run never signals a process.
- Interactive mode is the default; auto-kill requires an explicit flag.

## Logging

- Colorized output to stdout; errors to stderr.
- Audit log writes are best-effort (`|| true` / try-catch).

## Tests

- All process listing and signaling is stubbed under a temp dir.
- Tests drive the public interface only (flags, exit codes, output).
- Bash suite stubs `ps` and `kill` via fake binaries on `PATH`.
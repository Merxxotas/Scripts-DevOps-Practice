# Service Monitor and Auto-Restart — Code Style

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
- One function per concern (parse, validate, check, restart, audit).

## Safety

- Validate the service name against the platform pattern before any service-manager call.
- Confirm the service exists before attempting a restart.
- Never interpolate the service name into a shell string; pass it as an argument.
- Dry-run never calls the service manager.

## Logging

- Colorized output to stdout; errors to stderr.
- Audit log writes are best-effort (`|| true` / try-catch).

## Tests

- All filesystem and service-manager activity is stubbed under a temp dir.
- Tests drive the public interface only (flags, exit codes, output, emitted files).
- Bash suite stubs `systemctl` via a fake binary on `PATH`.

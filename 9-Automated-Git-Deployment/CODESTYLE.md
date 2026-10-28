# Automated Git Deployment — Code Style

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
- One function per concern (parse, validate, backup, fetch, deploy, post-deploy, audit).

## Safety

- Validate app dir and backup dir before any git operation.
- Refuse protected system roots.
- Dry-run never mutates.
- Require a clean working tree (no stash-and-hope).

## Logging

- Colorized output to stdout; errors to stderr.
- Audit log writes are best-effort (`|| true` / try-catch).

## Tests

- All git, tar, npm and service-manager activity is stubbed under a temp dir.
- Tests drive the public interface only (flags, exit codes, output).
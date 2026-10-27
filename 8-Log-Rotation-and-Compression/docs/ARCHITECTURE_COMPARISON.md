# Architecture Comparison — Log Rotation and Compression

## Overview

Both implementations follow the same six-stage pipeline (input validation, size check,
dry-run gate, rotation, retention, telemetry). The differences are the host's
native tooling and object model.

## Platform Differences

| Concern | Bash (POSIX) | PowerShell (Windows) |
| :--- | :--- | :--- |
| Compression tool | `gzip` → `.gz` | `Compress-Archive` → `.zip` |
| File size | `stat -c %s` / `stat -f %z` | `(Get-Item).Length` |
| Truncation | `: > file` (fallback `truncate -s 0`) | `Clear-Content` |
| Path blacklist | POSIX roots | Windows roots (+ POSIX for cross-host) |
| Console output | ANSI escapes via `printf` | ANSI escapes via `$([char]27)` |

## Parity

Flags, defaults, exit codes (0/1/2) and guardrails are identical. The parity test in
`tests/test_log_rotate.sh` (Test 17) asserts that every documented flag appears in both
implementations. The PowerShell suite mirrors the Bash scenarios.

## Legitimate Differences

- Compression format differs (`.gz` vs `.zip`) because each platform uses its native tool.
- Path separators and case sensitivity differ by host.
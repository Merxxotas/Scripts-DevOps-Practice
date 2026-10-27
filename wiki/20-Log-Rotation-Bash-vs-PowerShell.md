# 20. Log Rotation — Bash vs PowerShell

One contract in two runtimes. The compression format differs (`.gz` vs `.zip`) because
each platform uses its native tool; everything else (flags, defaults, exit codes,
guardrails) is identical.

## Parity proof

The Bash suite (Test 17) asserts that every documented flag appears in both
implementations. The PowerShell suite mirrors the Bash scenarios.
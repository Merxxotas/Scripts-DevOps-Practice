# Module 8 — Log Rotation Guard + Verify-Before-Truncate

Branch: fix/module8-log-rotate-guard
Delivery strategy: ask-on-risk → single PR (user decision 2026-11-05), work-unit commits
Test runner: bash tests/test_log_rotate.sh / pwsh tests/test_log_rotate.ps1 (+ shellcheck / PSScriptAnalyzer)
Risk line: item 1 (irreversible truncation of existing stored data)

## Specs

S1 — Two-tier safety guard, Bash. The Bash guard must be the port of module 2's
two-level logic: `port de la lógica de dos niveles del módulo 2 al guard bash`.
Acceptance:
- The guard evaluates the PARENT DIRECTORY of the log file, on BOTH the
  input path and its resolved (realpath) path; trailing separators are
  normalized before comparison.
- Full-tree roots block the root itself and every subtree below it:
  /bin /sbin /usr /usr/bin /usr/sbin /etc /dev /proc /sys /boot /root
  /private/etc, and C:/Windows on Windows.
- Exact-only roots block only the root itself (children stay legitimate:
  e.g. /var/log/app): / /var /var/run /var/log /tmp /home /private
  /private/var /private/tmp /Library /System /Applications /Volumes,
  plus the user's home (HOME and its realpath; UserProfile on Windows),
  and C:/ C:/Program Files C:/Program Files (x86) C:/ProgramData C:/Users.
- Refusal messages distinguish "inside the protected system tree" from
  "is a protected system root"; exit 1; audit line kept.
- Blacklist semantics documented in SPECS.md §5.

S2 — Verify the rotated artifact before zeroing the original.
`truncate-in-place sin verificar el artefacto rotado antes de anular el original (gzip -t / cmp)`.
Acceptance:
- Raw copy (or no-compress artifact) is verified byte-exact against the
  original with `cmp` (PowerShell: SHA-256 hash equality) before anything
  destructive happens.
- Compress path additionally requires `gzip -t` to pass and
  `gzip -cd <slot1.gz>` to compare equal to the original (PowerShell:
  extract the `.zip` to a temp dir and compare SHA-256 of the extracted
  payload against the original).
- On any verification failure: no truncation, `FAILED_COUNT` increments,
  exit 2, artifacts are preserved for inspection, audit line records the
  failure. The original log is never touched without a verified backup.
- Truncation stays gated on `FAILED_COUNT == 0`.

S3 — Bash ↔ PowerShell parity.
`paridad Bash ↔ PowerShell (log_rotate.ps1, 401 líneas)` (module 8 audit item 1).
Acceptance:
- log_rotate.ps1 gains the same two-tier guard (ConvertTo-GuardPath
  normalization, OrdinalIgnoreCase, same roots, same two-candidates check)
  and the same verify-before-truncate behavior; same flags, defaults and
  exit codes (0/1/2); same failure semantics (no truncate, artifacts kept).
- PS test suite gains guard tests (OS-adaptive: Windows C:\Windows\...,
  POSIX /etc/passwd) and verify-happy-path coverage; PS suite green on
  windows-2022 and ubuntu-24.04 CI legs.
- Specs/README/wiki document both implementations.

S4 — No regressions.
Acceptance: all pre-existing bash and PS tests stay green (21 bash + PS
suite), `shellcheck -x` and PSScriptAnalyzer clean, and outputs for valid
inputs are byte-identical to the base commit (differential check).

## Tasks

T1 — S1,S2 (Bash) — inline — two-tier guard + verify-before-truncate + RED/GREEN tests — [x] fa70f6e (54/54)
T2 — S1,S3 (PowerShell) — inline — same guard + verification + PS tests (pwsh 7.6.9 local), CI-adaptive — [x] 5a681d6 (30/30)
T3 — S1-S3 (docs) — inline — SPECS.md §5/§6, README/wiki 19-20 — commit pending
T4 — S1-S4 (verify+deliver) — inline + independent verifier (item 1) — RDD assess, CI, PR, merge --admin --rebase — commit: n/a

## Log

L1 — User (2026-11-05, verbatim — resuming module 8 audit item):
"Guard bash compara solo exact-match (\"/etc\" sí, \"/etc/nginx\" no) — portar la lógica de dos niveles del módulo 2 (full-tree vs raíces exactas); truncate-in-place sin verificar el artefacto rotado antes de anular el original (gzip -t / cmp); paridad obligatoria Bash ↔ PowerShell (log_rotate.ps1, 401 líneas)."

L2 — User (2026-11-05, verbatim):
"Okay, continuemos con lo que sugieres: módulo 8 (Log Rotation) — port de la lógica de dos niveles del módulo 2 al guard bash + gzip -t/cmp antes de truncar el original + paridad Bash↔PowerShell."

L3 — User (2026-11-05, verbatim):
"Empecemos a trabajar, en un PR único tal y como sugieres. Gracias.

Además recuerda de que ya se puede usar powershell en este sistema para tratar de cortar la fricción con los tests o cualquier cosa escrita en powershell."

L4 — Planning decision (2026-11-05): task sized LARGE (item 1: truncation of
existing stored data). Delivery: single PR (user decision), work-unit
commits (bash+tests / ps+tests / docs). Verifier independent after own
checks; RDD assess after commit. Forecast > 400 authored lines. Test-first:
RED tests in both suites before implementation. Verification of the PS side
runs locally with pwsh 7.6.9 (+ PSScriptAnalyzer 1.25.0) instead of waiting
for CI. Scratch under /tmp/opencode or mktemp; subagents report paths,
parent cleans.

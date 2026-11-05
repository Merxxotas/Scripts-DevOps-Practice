#!/usr/bin/env bash
# Mirror the files Stage 3 shares with Stage 2, or verify that they match.
#
# Why this exists: Stage 3 (Containerization) ships a byte-identical copy of
# Stage 2's package (pyproject.toml, src/system_monitor/, tests/) so each
# stage stays a self-contained, copyable unit. Hand edits drift; this script
# is the single place that knows which paths are shared. READMEs differ on
# purpose and are never touched.
#
# Usage:
#   ./sync-stage3.sh           Replace the shared paths in Stage 3 with Stage
#                              2's copies - anything extra there is deleted
#   ./sync-stage3.sh --check   Verify they match; exit 1 and list drift if not
#   ./sync-stage3.sh --help    Show this help

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
STAGE2="${SCRIPT_DIR}/Stage2-Python-Unified"
STAGE3="${SCRIPT_DIR}/Stage3-Containerization"

# Shared paths, relative to each stage root. Keep this list literal and short:
# it is the contract of what must not drift.
SHARED_PATHS=(
  pyproject.toml
  src/system_monitor
  tests
)

# Local tool caches are not part of the mirror. Without these exclusions a
# developer venv or pytest cache would either fail --check or leak into a copy.
DIFF_EXCLUDES=(
  --exclude=__pycache__
  --exclude='*.pyc'
  --exclude='*.pyo'
  --exclude=.pytest_cache
  --exclude=.ruff_cache
)
TAR_EXCLUDES=(
  --exclude=__pycache__
  --exclude='*.pyc'
  --exclude='*.pyo'
  --exclude=.pytest_cache
  --exclude=.ruff_cache
)

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'sync-stage3: %s\n' "$*" >&2
  exit 2
}

mode=sync
for arg in "$@"; do
  case "${arg}" in
    --check) mode=check ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: ${arg} (try --help)" ;;
  esac
done

# Guard the fixed layout before any copy or delete runs. The destructive
# branch below removes exactly the directories named in SHARED_PATHS inside
# this one known stage folder; verify that folder first.
[[ -d "${STAGE2}" ]] || die "Stage 2 directory not found: ${STAGE2}"
[[ -d "${STAGE3}" ]] || die "Stage 3 directory not found: ${STAGE3}"
[[ "${STAGE3}" == "${SCRIPT_DIR}/Stage3-Containerization" ]] \
  || die "refusing to operate on unexpected path: ${STAGE3}"

check_parity() {
  local drift=0 path
  for path in "${SHARED_PATHS[@]}"; do
    [[ -e "${STAGE2}/${path}" ]] || die "Stage 2 is missing shared path: ${path}"
    if ! diff -rq "${DIFF_EXCLUDES[@]}" -- "${STAGE2}/${path}" "${STAGE3}/${path}"; then
      drift=1
    fi
  done
  if [[ "${drift}" -ne 0 ]]; then
    printf 'sync-stage3: Stage 3 has drifted from Stage 2.\n' >&2
    printf 'sync-stage3: run ./sync-stage3.sh to mirror, then review with git diff.\n' >&2
    return 1
  fi
  printf 'sync-stage3: Stage 3 mirrors Stage 2 (%s).\n' "${SHARED_PATHS[*]}"
}

sync_mirror() {
  local path
  for path in "${SHARED_PATHS[@]}"; do
    local src="${STAGE2}/${path}" dst="${STAGE3}/${path}"
    [[ -e "${src}" ]] || die "Stage 2 is missing shared path: ${path}"
    if [[ -d "${src}" ]]; then
      rm -rf -- "${dst}"
      (cd -- "${STAGE2}" && tar "${TAR_EXCLUDES[@]}" -cf - -- "${path}") \
        | (cd -- "${STAGE3}" && tar -xf -)
    else
      cp -f -- "${src}" "${dst}"
    fi
    printf 'sync-stage3: mirrored %s\n' "${path}"
  done
  printf 'sync-stage3: done. Review with: git status --short && git diff\n'
}

case "${mode}" in
  check) check_parity ;;
  sync) sync_mirror ;;
esac

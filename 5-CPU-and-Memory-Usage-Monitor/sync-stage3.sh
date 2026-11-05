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
  cat <<'EOF'
Mirror the files Stage 3 shares with Stage 2, or verify that they match.

Usage:
  ./sync-stage3.sh           Replace the shared paths in Stage 3 with Stage
                             2's copies - anything extra there is deleted
  ./sync-stage3.sh --check   Verify they match; exit 1 and list drift if not
  ./sync-stage3.sh --help    Show this help
EOF
}

die() {
  printf 'sync-stage3: %s\n' "$*" >&2
  exit 2
}

# Fail closed on symlinks anywhere in the source or destination subtree. A
# symlinked parent would make rm -rf act inside the link target instead of
# the module (observed: a symlinked Stage 3 relocated the deletions), and a
# symlinked destination would follow the link on copy and overwrite an
# external file. SCRIPT_DIR is already canonical (pwd -P).
assert_no_symlink_path() {
  local path="$1" cursor
  case "${path}" in
    "${SCRIPT_DIR}" | "${SCRIPT_DIR}"/*) ;;
    *) return 0 ;;
  esac
  cursor="${path}"
  while [[ "${cursor}" != "${SCRIPT_DIR}" ]]; do
    if [[ -L "${cursor}" ]]; then
      die "refusing to operate through symlink: ${cursor}"
    fi
    cursor="$(dirname -- "${cursor}")"
  done
}

expected_type() {
  case "$1" in
    pyproject.toml) echo file ;;
    *) echo dir ;;
  esac
}

# Verify that the shared path has the expected type in ${1} and is present.
# Returns 0 on match, 1 on mismatch with a diagnostic on stderr.
expect_type() {
  local stage="$1" path="$2" expect="$3" target
  if [[ "${stage}" == stage3 ]]; then
    target="${STAGE3}/${path}"
  else
    target="${STAGE2}/${path}"
  fi
  if [[ "${expect}" == file ]]; then
    [[ -f "${target}" ]] && return 0
    printf 'sync-stage3: %s in %s is missing or not a regular file\n' "${path}" "${stage}" >&2
    return 1
  fi
  [[ -d "${target}" ]] && return 0
  printf 'sync-stage3: %s in %s is missing or not a directory\n' "${path}" "${stage}" >&2
  return 1
}

mode=sync
for arg in "$@"; do
  case "${arg}" in
    --check) mode=check ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: ${arg} (try --help)" ;;
  esac
done

[[ -d "${STAGE2}" ]] || die "Stage 2 directory not found: ${STAGE2}"
[[ -d "${STAGE3}" ]] || die "Stage 3 directory not found: ${STAGE3}"

# Same symlink rules on both sides; a broken Stage 2 is refused the same as
# a broken Stage 3, never silently "fixed" by deleting it.
for path in "${SHARED_PATHS[@]}"; do
  assert_no_symlink_path "${STAGE2}/${path}"
  assert_no_symlink_path "${STAGE3}/${path}"
done

check_parity() {
  local drift=0 path expect
  for path in "${SHARED_PATHS[@]}"; do
    expect="$(expected_type "${path}")"
    expect_type stage2 "${path}" "${expect}" || die "Stage 2 layout is invalid at ${path}; refusing to guess"
    if ! expect_type stage3 "${path}" "${expect}"; then
      drift=1
      continue
    fi
    if ! diff -rq "${DIFF_EXCLUDES[@]}" -- "${STAGE2}/${path}" "${STAGE3}/${path}"; then
      drift=1
    fi
  done
  if [[ "${drift}" -ne 0 ]]; then
    printf 'sync-stage3: Stage 3 has drifted from Stage 2.\n' >&2
    printf 'sync-stage3: run ./sync-stage3.sh to mirror, then review with git diff.\n' >&2
    return 1
  fi
  printf 'sync-stage3: Stage 3 mirrors Stage 2.\n'
}

sync_mirror() {
  local path src dst
  for path in "${SHARED_PATHS[@]}"; do
    src="${STAGE2}/${path}"
    dst="${STAGE3}/${path}"
    expect_type stage2 "${path}" "$(expected_type "${path}")" \
      || die "Stage 2 is missing shared path: ${path}"
    # Replace, never merge: the destination is removed first (rm -rf removes
    # a symlink itself, never the link target), so a stale file, directory,
    # or symlinked pyproject.toml can no longer survive the copy.
    rm -rf -- "${dst}"
    if [[ -d "${src}" ]]; then
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

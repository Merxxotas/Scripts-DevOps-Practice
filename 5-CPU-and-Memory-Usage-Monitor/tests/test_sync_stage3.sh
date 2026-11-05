#!/usr/bin/env bash
# Regression tests for sync-stage3.sh.
#
# The parity mirror is destructive by design (it deletes the shared paths in
# Stage 3 before copying), so the tests run against a throwaway copy created
# with mktemp -d and removed on exit. Nothing here touches the real stages.

set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf -- "${SCRATCH}"' EXIT

cp "${ROOT}/sync-stage3.sh" "${SCRATCH}/sync-stage3.sh"
chmod 755 "${SCRATCH}/sync-stage3.sh"

fail_count=0
ok() {
  local want="$1" got="$2" label="$3"
  if [[ "${want}" == "${got}" ]]; then
    printf 'ok: %s\n' "${label}"
  else
    printf 'FAIL: %s (want %s, got %s)\n' "${label}" "${want}" "${got}"
    fail_count=$((fail_count + 1))
  fi
}

# Run a command that is allowed to fail; print its exit code via $RC.
run() {
  RC=0
  "$@" >/dev/null 2>&1 || RC=$?
}

# A minimal two-stage layout with identical content, the same shape as the
# real module but tiny and deterministic.
mk_stages() {
  mkdir -p "${SCRATCH}/Stage2-Python-Unified/src/system_monitor" \
           "${SCRATCH}/Stage2-Python-Unified/tests" \
           "${SCRATCH}/Stage3-Containerization/src/system_monitor" \
           "${SCRATCH}/Stage3-Containerization/tests"
  printf 'a=1\n' > "${SCRATCH}/Stage2-Python-Unified/pyproject.toml"
  printf 'x\n' > "${SCRATCH}/Stage2-Python-Unified/src/system_monitor/mod.py"
  printf 't\n' > "${SCRATCH}/Stage2-Python-Unified/tests/test_x.py"
  cp "${SCRATCH}/Stage2-Python-Unified/pyproject.toml" \
     "${SCRATCH}/Stage3-Containerization/pyproject.toml"
  cp "${SCRATCH}/Stage2-Python-Unified/src/system_monitor/mod.py" \
     "${SCRATCH}/Stage3-Containerization/src/system_monitor/mod.py"
  cp "${SCRATCH}/Stage2-Python-Unified/tests/test_x.py" \
     "${SCRATCH}/Stage3-Containerization/tests/test_x.py"
}

reset_stages() {
  rm -rf -- "${SCRATCH}/Stage2-Python-Unified" "${SCRATCH}/Stage3-Containerization"
  mk_stages
}

sync() {
  (cd -- "${SCRATCH}" && ./sync-stage3.sh "$@")
}

# R1: a clean mirror passes --check.
reset_stages
run sync --check
ok 0 "${RC}" "check passes on a clean mirror"

# R2: content drift is reported as exit 1.
reset_stages
printf 'y\n' >> "${SCRATCH}/Stage3-Containerization/src/system_monitor/mod.py"
run sync --check
ok 1 "${RC}" "check exits 1 on content drift"

# R3: an unexpected file in the mirror is reported, and sync removes it.
reset_stages
printf 's\n' > "${SCRATCH}/Stage3-Containerization/tests/stray_probe.py"
run sync --check
ok 1 "${RC}" "check exits 1 on a stray mirror file"
run sync
RC=0; [[ ! -e "${SCRATCH}/Stage3-Containerization/tests/stray_probe.py" ]] || RC=1
ok 0 "${RC}" "sync deletes files that Stage 2 does not have"

# R4: unknown arguments exit 2.
reset_stages
run sync --bogus
ok 2 "${RC}" "unknown argument exits 2"

# R5: a missing stage directory exits 2 before doing anything.
reset_stages
mv "${SCRATCH}/Stage3-Containerization" "${SCRATCH}/Stage3-hidden"
run sync --check
ok 2 "${RC}" "missing Stage 3 exits 2 for check"
run sync
ok 2 "${RC}" "missing Stage 3 exits 2 for sync"
mv "${SCRATCH}/Stage3-hidden" "${SCRATCH}/Stage3-Containerization"

# R6: pyproject.toml replaced by a directory must not survive sync as a
# directory, and --check must never report a broken mirror as clean.
reset_stages
rm -- "${SCRATCH}/Stage3-Containerization/pyproject.toml"
mkdir "${SCRATCH}/Stage3-Containerization/pyproject.toml"
run sync --check
ok 1 "${RC}" "check exits 1 when pyproject.toml is a directory"
run sync
RC=0; [[ -f "${SCRATCH}/Stage3-Containerization/pyproject.toml" ]] || RC=1
ok 0 "${RC}" "sync leaves pyproject.toml as a regular file"

# R7: a symlinked pyproject.toml must not redirect the copy into an
# external file.
reset_stages
printf 'precious\n' > "${SCRATCH}/victim.txt"
rm -- "${SCRATCH}/Stage3-Containerization/pyproject.toml"
ln -s "${SCRATCH}/victim.txt" "${SCRATCH}/Stage3-Containerization/pyproject.toml"
run sync
RC=0; grep -qx precious "${SCRATCH}/victim.txt" || RC=1
ok 0 "${RC}" "external file behind a symlinked pyproject.toml stays untouched"

# R8: a symlinked Stage 3 directory must be refused, and its target must
# survive untouched.
reset_stages
mkdir "${SCRATCH}/decoy"
printf 'keep\n' > "${SCRATCH}/decoy/keep-me.txt"
mv "${SCRATCH}/Stage3-Containerization" "${SCRATCH}/Stage3-real"
ln -s "${SCRATCH}/decoy" "${SCRATCH}/Stage3-Containerization"
run sync
ok 2 "${RC}" "a symlinked Stage 3 is refused"
run sync --check
ok 2 "${RC}" "check refuses the symlinked layout too"
RC=0; [[ -f "${SCRATCH}/decoy/keep-me.txt" ]] || RC=1
ok 0 "${RC}" "the symlink target keeps its files"
mv "${SCRATCH}/Stage3-Containerization" "${SCRATCH}/Stage3-refusal-probe"
mv "${SCRATCH}/Stage3-real" "${SCRATCH}/Stage3-Containerization"

# R9: a symlinked intermediate directory must also be refused (the mirror's
# rm -rf would otherwise act inside the link target).
reset_stages
mkdir "${SCRATCH}/elsewhere"
printf 'keep\n' > "${SCRATCH}/elsewhere/keep-me.txt"
rm -rf -- "${SCRATCH}/Stage3-Containerization/src"
ln -s "${SCRATCH}/elsewhere" "${SCRATCH}/Stage3-Containerization/src"
run sync
ok 2 "${RC}" "a symlinked src/ is refused"
RC=0; [[ -f "${SCRATCH}/elsewhere/keep-me.txt" ]] || RC=1
ok 0 "${RC}" "the intermediate symlink target keeps its files"

if [[ "${fail_count}" -ne 0 ]]; then
  printf 'test_sync_stage3: %d check(s) failed\n' "${fail_count}" >&2
  exit 1
fi
printf 'test_sync_stage3: all checks passed\n'

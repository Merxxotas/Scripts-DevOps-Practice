#!/bin/bash
# ==============================================================================
# Test Suite: test_log_rotate.sh
# Description: Automated integration and unit test suite for log_rotate.sh.
#              Every test drives the public interface: flags, exit codes and
#              emitted files. All filesystem activity happens under a temp dir.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROTATE_SCRIPT="$SCRIPT_DIR/log_rotate.sh"
ROTATE_SCRIPT_PS="$SCRIPT_DIR/log_rotate.ps1"
TEST_SANDBOX="$(mktemp -d "/tmp/test_log_rotate.XXXXXX")"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

LAST_STDOUT=""
LAST_STDERR=""
LAST_EXIT_CODE=0

setup() {
    rm -rf "$TEST_SANDBOX"
    mkdir -p "$TEST_SANDBOX"
}

teardown() {
    rm -rf "$TEST_SANDBOX"
    mkdir -p "$TEST_SANDBOX"
}

run_rotate() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0

    "$ROTATE_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

    LAST_STDOUT="$(cat "$stdout_file" 2>/dev/null || true)"
    LAST_STDERR="$(cat "$stderr_file" 2>/dev/null || true)"
    LAST_EXIT_CODE="$exit_code"
}

assert_equals() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (expected '%s', got '%s')\n" "$RED" "$RESET" "$label" "$expected" "$actual" >&2
        ((FAILED_TESTS++)) || true
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (missing '%s')\n" "$RED" "$RESET" "$label" "$needle" >&2
        ((FAILED_TESTS++)) || true
    fi
}

assert_file_exists() {
    local path="$1" label="$2"
    if [[ -f "$path" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (file missing: %s)\n" "$RED" "$RESET" "$label" "$path" >&2
        ((FAILED_TESTS++)) || true
    fi
}

assert_file_not_exists() {
    local path="$1" label="$2"
    if [[ ! -e "$path" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (file exists: %s)\n" "$RED" "$RESET" "$label" "$path" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# ---------- tests ----------

test_help_menu() {
    setup
    run_rotate --help
    assert_equals "0" "$LAST_EXIT_CODE" "Test 1a: --help exits 0"
    assert_contains "$LAST_STDOUT" "Usage" "Test 1b: help shows usage"
}

test_missing_file() {
    setup
    run_rotate -f "$TEST_SANDBOX/nope.log"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 2: missing file exits 1"
}

test_directory_as_log() {
    setup
    mkdir -p "$TEST_SANDBOX/subdir"
    run_rotate -f "$TEST_SANDBOX/subdir"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 3: directory as log file exits 1"
}

test_guardrail() {
    setup
    run_rotate -f "/etc/passwd" -m 0
    assert_equals "1" "$LAST_EXIT_CODE" "Test 4: protected system path exits 1"
}

test_bad_max_size() {
    setup
    printf 'x\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m abc
    assert_equals "1" "$LAST_EXIT_CODE" "Test 5: non-numeric max-size exits 1"
}

test_bad_backup_count() {
    setup
    printf 'x\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -c 0
    assert_equals "1" "$LAST_EXIT_CODE" "Test 6: zero backup-count exits 1"
}

test_noop() {
    setup
    printf 'small\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 10
    assert_equals "0" "$LAST_EXIT_CODE" "Test 7a: no-op exits 0"
    assert_contains "$LAST_STDOUT" "No rotation needed" "Test 7b: no-op message"
    assert_file_not_exists "$TEST_SANDBOX/f.log.1.gz" "Test 7c: no backup created"
}

test_rotation_basic() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    # ensure size > 0 threshold
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0
    assert_equals "0" "$LAST_EXIT_CODE" "Test 8a: rotation exits 0"
    assert_file_exists "$TEST_SANDBOX/f.log.1.gz" "Test 8b: backup created"
    # original truncated
    local sz
    sz=$(wc -c < "$TEST_SANDBOX/f.log")
    assert_equals "0" "$sz" "Test 8c: original truncated to 0"
}

test_dry_run() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    local before
    before=$(wc -c < "$TEST_SANDBOX/f.log")
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --dry-run
    assert_equals "0" "$LAST_EXIT_CODE" "Test 9a: dry-run exits 0"
    assert_contains "$LAST_STDOUT" "DRY RUN" "Test 9b: dry-run label"
    assert_file_not_exists "$TEST_SANDBOX/f.log.1.gz" "Test 9c: no backup created"
    local after
    after=$(wc -c < "$TEST_SANDBOX/f.log")
    assert_equals "$before" "$after" "Test 9d: file unchanged"
}

test_force() {
    setup
    printf 'tiny\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" --force
    assert_equals "0" "$LAST_EXIT_CODE" "Test 10a: force exits 0"
    assert_file_exists "$TEST_SANDBOX/f.log.1.gz" "Test 10b: backup created"
}

test_no_compress() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --no-compress
    assert_equals "0" "$LAST_EXIT_CODE" "Test 11a: no-compress exits 0"
    assert_file_exists "$TEST_SANDBOX/f.log.1" "Test 11b: raw backup created"
    assert_file_not_exists "$TEST_SANDBOX/f.log.1.gz" "Test 11c: no gz created"
}

test_retention_shift() {
    setup
    local f="$TEST_SANDBOX/f.log"
    printf 'v1\n' > "$f"
    run_rotate -f "$f" --force >/dev/null 2>&1
    printf 'v2\n' > "$f"
    run_rotate -f "$f" --force >/dev/null 2>&1
    printf 'v3\n' > "$f"
    run_rotate -f "$f" --force >/dev/null 2>&1
    # with backup-count 5 (default), all three backups present
    assert_file_exists "$TEST_SANDBOX/f.log.1.gz" "Test 12a: .1 exists"
    assert_file_exists "$TEST_SANDBOX/f.log.2.gz" "Test 12b: .2 exists"
    assert_file_exists "$TEST_SANDBOX/f.log.3.gz" "Test 12c: .3 exists"
}

test_retention_prune() {
    setup
    local f="$TEST_SANDBOX/f.log"
    # backup-count 1: only one retained
    printf 'v1\n' > "$f"
    run_rotate -f "$f" -c 1 --force >/dev/null 2>&1
    printf 'v2\n' > "$f"
    run_rotate -f "$f" -c 1 --force >/dev/null 2>&1
    assert_file_exists "$TEST_SANDBOX/f.log.1.gz" "Test 13a: .1 exists"
    assert_file_not_exists "$TEST_SANDBOX/f.log.2.gz" "Test 13b: .2 pruned"
}

test_audit_log() {
    setup
    printf 'line\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" --force --audit-log "$TEST_SANDBOX/audit.log"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 14a: audit run exits 0"
    assert_file_exists "$TEST_SANDBOX/audit.log" "Test 14b: audit file created"
    assert_contains "$(cat "$TEST_SANDBOX/audit.log")" "Rotation completed" "Test 14c: audit content"
}

test_verbose() {
    setup
    printf 'line\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" --force --verbose
    assert_contains "$LAST_STDOUT" "copying" "Test 15: verbose shows steps"
}

test_no_compress_raw_not_gz() {
    setup
    printf 'line\n' > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" --force --no-compress --verbose
    assert_contains "$LAST_STDOUT" "Rotated to" "Test 16: no-compress rotated"
}

test_parity_flags() {
    setup
    # Bash flags present in script
    for flag in --log-file --max-size-mb --backup-count --no-compress --force --dry-run --audit-log --verbose --help; do
        if grep -q -- "$flag" "$ROTATE_SCRIPT"; then
            :
        else
            printf "%b[FAIL]%b missing bash flag %s\n" "$RED" "$RESET" "$flag" >&2
            ((FAILED_TESTS++)) || true
            continue
        fi
    done
    # PowerShell params present
    for param in LogFile MaxSizeMB BackupCount NoCompress Force DryRun AuditLog Verbose Help; do
        if grep -q -- "$param" "$ROTATE_SCRIPT_PS"; then
            :
        else
            printf "%b[FAIL]%b missing ps param %s\n" "$RED" "$RESET" "$param" >&2
            ((FAILED_TESTS++)) || true
            continue
        fi
    done
    printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "Test 17: parity flags present"
    ((PASSED_TESTS++)) || true
}

# ---------- runner ----------

run_all() {
    test_help_menu
    test_missing_file
    test_directory_as_log
    test_guardrail
    test_bad_max_size
    test_bad_backup_count
    test_noop
    test_rotation_basic
    test_dry_run
    test_force
    test_no_compress
    test_retention_shift
    test_retention_prune
    test_audit_log
    test_verbose
    test_no_compress_raw_not_gz
    test_parity_flags
}

run_all

teardown

printf "\n%b========================================%b\n" "$CYAN" "$RESET"
printf "Tests Passed: %b%d%b\n" "$GREEN" "$PASSED_TESTS" "$RESET"
printf "Tests Failed: %b%d%b\n" "$RED" "$FAILED_TESTS" "$RESET"
printf "%b========================================%b\n" "$CYAN" "$RESET"

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi
exit 0
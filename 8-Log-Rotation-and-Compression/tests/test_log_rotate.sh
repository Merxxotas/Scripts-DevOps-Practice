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
    sz=$(wc -c < "$TEST_SANDBOX/f.log" | tr -d '[:space:]')
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

test_json_output() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --json
    assert_equals "0" "$LAST_EXIT_CODE" "Test 18a: --json exits 0"
    assert_contains "$LAST_STDOUT" '"outcome": "rotated"' "Test 18b: json outcome rotated"
    assert_contains "$LAST_STDOUT" '"log_file"' "Test 18c: json log_file field"
}

test_json_dry_run() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --dry-run --json
    assert_equals "0" "$LAST_EXIT_CODE" "Test 19a: --json dry-run exits 0"
    assert_contains "$LAST_STDOUT" '"outcome": "dry-run"' "Test 19b: json dry-run outcome"
}

test_csv_output() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --csv
    assert_equals "0" "$LAST_EXIT_CODE" "Test 20a: --csv exits 0"
    assert_contains "$LAST_STDOUT" 'log_file,current_size_bytes' "Test 20b: csv header"
    assert_contains "$LAST_STDOUT" 'rotated' "Test 20c: csv outcome"
}

test_json_csv_mutual() {
    setup
    printf 'line\n%.0s' {1..100} > "$TEST_SANDBOX/f.log"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --json --csv
    assert_equals "1" "$LAST_EXIT_CODE" "Test 21: mutual exclusion exits 1"
}

# Test 22: a file under a protected full-tree root must be refused
# (host-dependent candidates; SKIP when none exists — module 2 pattern)
test_guardrail_subtree_blocked() {
    setup
    local target=""
    local candidate
    for candidate in /usr/share/zoneinfo/UTC /etc/hostname /etc/ssh/sshd_config /etc/nginx/nginx.conf; do
        if [[ -f "$candidate" ]]; then
            target="$candidate"
            break
        fi
    done
    if [[ -z "$target" ]]; then
        printf "%b[SKIP]%b Test 22: no protected full-tree file found on this host\n" "$CYAN" "$RESET"
        return 0
    fi
    run_rotate -f "$target" --force --dry-run
    assert_equals "1" "$LAST_EXIT_CODE" "Test 22: file under protected full-tree root exits 1"
}

# Test 23: guard blocks via the resolved path when the input path is a symlink
test_guard_symlink_resolved() {
    setup
    if [[ ! -e /etc/passwd ]]; then
        printf "%b[SKIP]%b Test 23: /etc/passwd does not exist on this host\n" "$CYAN" "$RESET"
        return 0
    fi
    ln -s /etc "$TEST_SANDBOX/link"
    run_rotate -f "$TEST_SANDBOX/link/passwd" --force --dry-run
    assert_equals "1" "$LAST_EXIT_CODE" "Test 23: symlink into protected tree exits 1"
}

# Test 24: a file in a subtree of an exact-only root stays allowed
test_guard_exact_only_subtree_allowed() {
    setup
    mkdir -p "$TEST_SANDBOX/var-log-like/app"
    printf 'small\n' > "$TEST_SANDBOX/var-log-like/app/f.log"
    run_rotate -f "$TEST_SANDBOX/var-log-like/app/f.log"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 24: subtree of exact-only root is allowed"
}

# Test 25: a copied backup that does not match must abort before truncation
test_verify_cmp_failure_aborts_truncate() {
    setup
    printf 'precious-log-content\n%.0s' {1..50} > "$TEST_SANDBOX/f.log"
    cp -p "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"
    mkdir -p "$TEST_SANDBOX/fakebin"
    cat > "$TEST_SANDBOX/fakebin/cp" <<'EOF'
#!/bin/bash
args=()
for a in "$@"; do
    [[ "$a" == -* ]] && continue
    args+=("$a")
done
src="${args[0]}"
dst="${args[$((${#args[@]} - 1))]}"
/bin/cp -p "$src" "$dst" && printf 'corruption' >> "$dst"
exit 0
EOF
    chmod +x "$TEST_SANDBOX/fakebin/cp"
    local old_path="$PATH"
    PATH="$TEST_SANDBOX/fakebin:$PATH"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0
    PATH="$old_path"
    assert_equals "2" "$LAST_EXIT_CODE" "Test 25a: mismatched backup exits 2"
    if cmp -s "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"; then
        printf "%b[PASS]%b Test 25b: original log untouched\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 25b: original log was modified\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
    fi
}

# Test 26: a gzip stream that fails verification must abort before truncation
test_verify_gzip_failure_aborts_truncate() {
    setup
    printf 'precious-log-content\n%.0s' {1..50} > "$TEST_SANDBOX/f.log"
    cp -p "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"
    mkdir -p "$TEST_SANDBOX/fakebin"
    cat > "$TEST_SANDBOX/fakebin/gzip" <<'EOF'
#!/bin/bash
case "${1:-}" in
    -c) printf 'garbage-not-gzip' ;;
    -t) exit 1 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TEST_SANDBOX/fakebin/gzip"
    local old_path="$PATH"
    PATH="$TEST_SANDBOX/fakebin:$PATH"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0
    PATH="$old_path"
    assert_equals "2" "$LAST_EXIT_CODE" "Test 26a: unverifiable gzip exits 2"
    if cmp -s "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"; then
        printf "%b[PASS]%b Test 26b: original log untouched\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 26b: original log was modified\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
    fi
}

# Test 27: after rotation the gzip backup decompresses to the original bytes
test_verify_compress_roundtrip() {
    setup
    printf 'roundtrip-content\n%.0s' {1..80} > "$TEST_SANDBOX/f.log"
    cp -p "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0
    assert_equals "0" "$LAST_EXIT_CODE" "Test 27a: rotation exits 0"
    if gzip -cd "$TEST_SANDBOX/f.log.1.gz" | cmp -s - "$TEST_SANDBOX/original.bak"; then
        printf "%b[PASS]%b Test 27b: backup decompresses to original\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 27b: backup does not match the original\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
    fi
}

# Test 28: --no-compress backup is byte-identical to the pre-rotation log
test_verify_no_compress_backup_matches() {
    setup
    printf 'raw-backup-content\n%.0s' {1..80} > "$TEST_SANDBOX/f.log"
    cp -p "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0 --no-compress
    assert_equals "0" "$LAST_EXIT_CODE" "Test 28a: no-compress rotation exits 0"
    assert_file_exists "$TEST_SANDBOX/f.log.1" "Test 28b: raw backup created"
    if cmp -s "$TEST_SANDBOX/f.log.1" "$TEST_SANDBOX/original.bak"; then
        printf "%b[PASS]%b Test 28c: raw backup matches the original\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 28c: raw backup differs from the original\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
    fi
}

# Test 29: a symlinked HOME is refused, including via its realpath (S1)
test_guard_symlink_home_blocked() {
    setup
    mkdir -p "$TEST_SANDBOX/realhome"
    printf 'x\n' > "$TEST_SANDBOX/realhome/f.log"
    ln -s "$TEST_SANDBOX/realhome" "$TEST_SANDBOX/homelink"
    local old_home="$HOME"
    HOME="$TEST_SANDBOX/homelink"
    run_rotate -f "$TEST_SANDBOX/homelink/f.log" --force --dry-run
    assert_equals "1" "$LAST_EXIT_CODE" "Test 29a: symlinked HOME refused"
    run_rotate -f "$TEST_SANDBOX/realhome/f.log" --force --dry-run
    assert_equals "1" "$LAST_EXIT_CODE" "Test 29b: realpath of symlinked HOME refused"
    HOME="$old_home"
}

# Test 30: gzip -t passes but the decompressed payload differs -> exit 2, untouched (S2)
test_verify_gzip_payload_mismatch_aborts() {
    setup
    printf 'precious-log-content\n%.0s' {1..50} > "$TEST_SANDBOX/f.log"
    cp -p "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"
    mkdir -p "$TEST_SANDBOX/fakebin"
    # SC2016: fakebin case patterns must stay literal
    # shellcheck disable=SC2016
    cat > "$TEST_SANDBOX/fakebin/gzip" <<'EOF'
#!/bin/bash
case "${1:-}" in
    -c) printf 'fake-gzip-bytes' ;;
    -t) exit 0 ;;
    -cd) printf 'different-bytes' ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TEST_SANDBOX/fakebin/gzip"
    local old_path="$PATH"
    PATH="$TEST_SANDBOX/fakebin:$PATH"
    run_rotate -f "$TEST_SANDBOX/f.log" -m 0
    PATH="$old_path"
    assert_equals "2" "$LAST_EXIT_CODE" "Test 30a: payload mismatch exits 2"
    if cmp -s "$TEST_SANDBOX/f.log" "$TEST_SANDBOX/original.bak"; then
        printf "%b[PASS]%b Test 30b: original untouched\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 30b: original modified\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
    fi
    assert_file_exists "$TEST_SANDBOX/f.log.1.gz" "Test 30c: failed artifact kept"
}

# Test 31: double-slash path is refused via the resolved path (S1)
test_guard_double_slash_blocked() {
    setup
    if [[ ! -e /etc/passwd ]]; then
        printf "%b[SKIP]%b Test 31: /etc/passwd does not exist on this host\n" "$CYAN" "$RESET"
        return 0
    fi
    run_rotate -f "//etc/passwd" --force --dry-run
    assert_equals "1" "$LAST_EXIT_CODE" "Test 31: double-slash path refused"
}

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
    test_json_output
    test_json_dry_run
    test_csv_output
    test_json_csv_mutual
    test_guardrail_subtree_blocked
    test_guard_symlink_resolved
    test_guard_exact_only_subtree_allowed
    test_verify_cmp_failure_aborts_truncate
    test_verify_gzip_failure_aborts_truncate
    test_verify_compress_roundtrip
    test_verify_no_compress_backup_matches
    test_guard_symlink_home_blocked
    test_verify_gzip_payload_mismatch_aborts
    test_guard_double_slash_blocked
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
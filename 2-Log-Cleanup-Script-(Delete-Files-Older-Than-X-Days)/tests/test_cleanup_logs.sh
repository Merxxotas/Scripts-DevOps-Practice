#!/bin/bash
# ==============================================================================
# Test Suite: test_cleanup_logs.sh
# Description: Automated integration and unit test suite for cleanup_logs.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup_logs.sh"
TEST_SANDBOX="$(mktemp -d /tmp/test_log_cleanup.XXXXXX)"
trap 'rm -rf "$TEST_SANDBOX"' EXIT

# ANSI colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

setup() {
    rm -rf "$TEST_SANDBOX"
    mkdir -p "$TEST_SANDBOX/sub1" "$TEST_SANDBOX/sub2"
}

teardown() {
    rm -rf "$TEST_SANDBOX"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (Expected: '%s', Got: '%s')\n" "$RED" "$RESET" "$test_name" "$expected" "$actual" >&2
        ((FAILED_TESTS++)) || true
    fi
}


assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (missing '%s')\n" "$RED" "$RESET" "$test_name" "$needle" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# Test 1: Help menu returns 0
test_help_menu() {
    local exit_code=0
    "$CLEANUP_SCRIPT" -h >/dev/null 2>&1 || exit_code=$?
    assert_equals "0" "$exit_code" "Test 1: Help menu exits with code 0"
}

# Test 2: Missing required directory flag fails with code 1
test_missing_directory() {
    local exit_code=0
    "$CLEANUP_SCRIPT" >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 2: Missing directory argument exits with code 1"
}

# Test 3: Protected system directory triggers safety guardrail
test_safety_guardrails() {
    local exit_code=0
    "$CLEANUP_SCRIPT" -d "/etc" >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 3a: Safety guardrail blocks /etc with exit code 1"

    exit_code=0
    "$CLEANUP_SCRIPT" -d "/var" >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 3b: Safety guardrail blocks /var with exit code 1"
}

# Test 4: Dry-run simulation mode does not delete files
test_dry_run_mode() {
    setup
    # Create old log file (40 days old)
    local old_file="$TEST_SANDBOX/old_app.log"
    echo "test log content" > "$old_file"
    
    # Touch file with timestamp 40 days in the past (Linux & macOS support)
    if date -d "40 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "40 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-40d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-40d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi

    local exit_code=0
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 -n >/dev/null 2>&1 || exit_code=$?
    
    local file_exists="no"
    [[ -f "$old_file" ]] && file_exists="yes"

    assert_equals "0" "$exit_code" "Test 4a: Dry-run exits with code 0"
    assert_equals "yes" "$file_exists" "Test 4b: Dry-run preserves file on disk"
    teardown
}

# Test 5: Live execution deletes files exceeding retention age
test_retention_deletion() {
    setup
    local old_file="$TEST_SANDBOX/purge_me.log"
    local new_file="$TEST_SANDBOX/keep_me.log"
    
    echo "purgeable log" > "$old_file"
    echo "recent log" > "$new_file"

    if date -d "45 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "45 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-45d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-45d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi

    local exit_code=0
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 >/dev/null 2>&1 || exit_code=$?

    local old_exists="no"
    local new_exists="no"
    [[ -f "$old_file" ]] && old_exists="yes"
    [[ -f "$new_file" ]] && new_exists="yes"

    assert_equals "0" "$exit_code" "Test 5a: Cleanup exits with code 0"
    assert_equals "no" "$old_exists" "Test 5b: Stale file successfully deleted"
    assert_equals "yes" "$new_exists" "Test 5c: Recent file retained"
    teardown
}

# Test 6: Recursive traversal cleans subdirectories
test_recursive_cleanup() {
    setup
    local sub_old_file="$TEST_SANDBOX/sub1/sub_old.log"
    echo "sub log content" > "$sub_old_file"

    if date -d "50 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "50 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$sub_old_file"
    elif date -v-50d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-50d +"%Y%m%d%H%M")
        touch -t "$past_date" "$sub_old_file"
    fi

    # Flat scan must NOT delete subfolder file
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 >/dev/null 2>&1 || true
    local sub_exists_flat="no"
    [[ -f "$sub_old_file" ]] && sub_exists_flat="yes"
    assert_equals "yes" "$sub_exists_flat" "Test 6a: Flat scan skips subdirectory files"

    # Recursive scan MUST delete subfolder file
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 -r >/dev/null 2>&1 || true
    local sub_exists_rec="no"
    [[ -f "$sub_old_file" ]] && sub_exists_rec="yes"
    assert_equals "no" "$sub_exists_rec" "Test 6b: Recursive scan purges subdirectory files"
    teardown
}

# Test 7: Audit logfile creation
test_audit_logging() {
    setup
    local audit_file="$TEST_SANDBOX/logs/audit.log"
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 -l "$audit_file" >/dev/null 2>&1 || true
    
    local audit_created="no"
    [[ -f "$audit_file" ]] && audit_created="yes"
    assert_equals "yes" "$audit_created" "Test 7: Audit logfile is successfully created"
    teardown
}

# Test 8: -t 0 must be rejected (spec: retention days must be a positive integer)
test_retention_zero_rejected() {
    setup
    local old_file="$TEST_SANDBOX/purge_me.log"
    echo "purgeable log" > "$old_file"
    if date -d "45 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "45 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-45d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-45d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi

    local exit_code=0
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 0 >/dev/null 2>&1 || exit_code=$?

    local file_exists="no"
    [[ -f "$old_file" ]] && file_exists="yes"

    assert_equals "1" "$exit_code" "Test 8a: -t 0 is rejected with exit code 1"
    assert_equals "yes" "$file_exists" "Test 8b: -t 0 leaves files untouched"
    teardown
}

# Test 9: -m must reject non-numeric garbage like "1a5" (unescaped dot regression)
test_min_size_garbage_rejected() {
    setup
    local exit_code=0
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 -m "1a5" >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 9: -m '1a5' is rejected with exit code 1"
    teardown
}

# Test 10: a directory under a critical root (e.g. /etc/ssh) must be refused too
test_guardrail_subtree() {
    local guard_target="/etc/ssh"
    if [[ ! -d "$guard_target" ]]; then
        printf "%b[SKIP]%b Test 10: %s does not exist on this host\n" "$CYAN" "$RESET" "$guard_target"
        return 0
    fi

    local exit_code=0
    "$CLEANUP_SCRIPT" -d "$guard_target" -n >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 10: Safety guardrail blocks /etc/ssh even with -n (subtree of protected root)"
}

# Test 11: $HOME itself must be refused (children of it remain allowed)
test_guardrail_home_root() {
    local exit_code=0
    "$CLEANUP_SCRIPT" -d "$HOME" -n >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 11: Safety guardrail blocks \$HOME itself"
}

# Test 12: when mtime cannot be determined, the file must NOT be deleted (fail closed)
test_fail_closed_on_mtime_failure() {
    setup
    local old_file="$TEST_SANDBOX/purge_me.log"
    echo "purgeable log" > "$old_file"
    if date -d "45 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "45 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-45d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-45d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi

    # Stub PATH so every mtime source fails: stat always exits 1, and
    # `date -r` exits 1 (everything else defers to the real date).
    local real_date stub_dir
    real_date="$(command -v date)"
    stub_dir="$TEST_SANDBOX/stubbin"
    mkdir -p "$stub_dir"

    printf '#!/bin/bash\nexit 1\n' > "$stub_dir/stat"
    chmod +x "$stub_dir/stat"

    cat > "$stub_dir/date" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "-r" ]]; then
    exit 1
fi
exec "$real_date" "\$@"
EOF
    chmod +x "$stub_dir/date"

    local exit_code=0
    PATH="$stub_dir:$PATH" "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 >/dev/null 2>&1 || exit_code=$?

    local file_exists="no"
    [[ -f "$old_file" ]] && file_exists="yes"

    assert_equals "2" "$exit_code" "Test 12a: Uninspectable file yields exit code 2 (partial failure)"
    assert_equals "yes" "$file_exists" "Test 12b: Uninspectable file is NOT deleted (fail closed)"
    teardown
}

# Test 13: /var/log itself is protected (spec section 5.1); subfolders remain usable
test_guardrail_var_log_exact() {
    local exit_code=0
    "$CLEANUP_SCRIPT" -d "/var/log" -n >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" "Test 13: Safety guardrail blocks /var/log exact match"
}

# Test 14: when size cannot be determined, the file must NOT be deleted (fail closed)
test_fail_closed_on_size_failure() {
    setup
    local old_file="$TEST_SANDBOX/purge_me.log"
    echo "purgeable log" > "$old_file"
    if date -d "45 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "45 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-45d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-45d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi

    # Stub PATH so the size lookup fails but mtime works: `stat` passes the
    # %Y query to the real stat and fails the %s query; `wc` always fails.
    local real_stat real_date stub_dir
    real_stat="$(command -v stat)"
    real_date="$(command -v date)"
    stub_dir="$TEST_SANDBOX/stubbin"
    mkdir -p "$stub_dir"

    cat > "$stub_dir/stat" <<EOF
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == "%s" || "\$arg" == "%z" ]]; then
        exit 1
    fi
done
exec "$real_stat" "\$@"
EOF
    chmod +x "$stub_dir/stat"
    printf '#!/bin/bash\nexit 1\n' > "$stub_dir/wc"
    chmod +x "$stub_dir/wc"

    local exit_code=0
    PATH="$stub_dir:$PATH" "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 >/dev/null 2>&1 || exit_code=$?

    local file_exists="no"
    [[ -f "$old_file" ]] && file_exists="yes"

    assert_equals "2" "$exit_code" "Test 14a: Unreadable size yields exit code 2 (partial failure)"
    assert_equals "yes" "$file_exists" "Test 14b: Unreadable size is NOT deleted (fail closed)"
    teardown
}

# Run all tests
printf "%bStarting Bash Log Cleanup Test Suite...%b\n" "$CYAN" "$RESET"
test_json_dry_run() {
    setup
    local old_file="$TEST_SANDBOX/purge_me.log"
    echo "purgeable log" > "$old_file"
    if date -d "45 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "45 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-45d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-45d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 -n --json >"$stdout_file" 2>/dev/null
    local ec=$?
    local out
    out=$(cat "$stdout_file")
    assert_equals "0" "$ec" "Test JSONa: --json exits 0"
    assert_contains "$out" '"outcome": "dry-run"' "Test JSONb: json outcome dry-run"
    assert_contains "$out" '"scanned"' "Test JSONc: json scanned field"
    teardown
}

test_csv_dry_run() {
    setup
    local old_file="$TEST_SANDBOX/purge_me.log"
    echo "purgeable log" > "$old_file"
    if date -d "45 days ago" +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -d "45 days ago" +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    elif date -v-45d +%s >/dev/null 2>&1; then
        local past_date
        past_date=$(date -v-45d +"%Y%m%d%H%M")
        touch -t "$past_date" "$old_file"
    fi
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 -n --csv >"$stdout_file" 2>/dev/null
    local ec=$?
    local out
    out=$(cat "$stdout_file")
    assert_equals "0" "$ec" "Test CSVa: --csv exits 0"
    assert_contains "$out" "path,size_bytes" "Test CSVb: csv header"
    teardown
}

test_json_csv_mutual() {
    setup
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local ec=0
    "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 --json --csv >"$stdout_file" 2>/dev/null || ec=$?
    assert_equals "1" "$ec" "Test MUTa: mutual exclusion exits 1"
    teardown
}

test_help_menu
test_missing_directory
test_safety_guardrails
test_dry_run_mode
test_retention_deletion
test_recursive_cleanup
test_audit_logging
test_json_dry_run
test_csv_dry_run
test_json_csv_mutual
test_retention_zero_rejected
test_min_size_garbage_rejected
test_guardrail_subtree
test_guardrail_home_root
test_fail_closed_on_mtime_failure
test_guardrail_var_log_exact
test_fail_closed_on_size_failure

printf "============================================================\n"
printf "Tests Summary: %b%d Passed%b, %b%d Failed%b\n" "$GREEN" "$PASSED_TESTS" "$RESET" "$RED" "$FAILED_TESTS" "$RESET"
printf "============================================================\n"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0

#!/bin/bash
# ==============================================================================
# Test Suite: test_cleanup_logs.sh
# Description: Automated integration and unit test suite for cleanup_logs.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup_logs.sh"
TEST_SANDBOX="/tmp/test_log_cleanup_$$"

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

# Run all tests
printf "%bStarting Bash Log Cleanup Test Suite...%b\n" "$CYAN" "$RESET"
test_help_menu
test_missing_directory
test_safety_guardrails
test_dry_run_mode
test_retention_deletion
test_recursive_cleanup
test_audit_logging

printf "============================================================\n"
printf "Tests Summary: %b%d Passed%b, %b%d Failed%b\n" "$GREEN" "$PASSED_TESTS" "$RESET" "$RED" "$FAILED_TESTS" "$RESET"
printf "============================================================\n"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0

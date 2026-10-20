#!/usr/bin/env bash
# ==============================================================================
# Test Suite: test_system_monitor.sh
# Description: Integration tests for the Stage 1 native Bash implementation.
#
# The suite exercises the public interface only: the command-line flags, the
# exit codes and the files the script emits. Every test is deterministic: the
# filesystem is isolated under a temporary directory and nothing depends on
# the host's disk layout, its running processes or its locale.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/Stage1-Native-Scripts/system_monitor.sh"
TEST_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/test_system_monitor.XXXXXX")"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

# The output and the exit code of the last captured command. They are kept so
# that a failing assertion can show what the script actually printed: without
# this, a command that fails under `set -e` kills the suite before any
# assertion runs and the failure is completely silent.
LAST_OUTPUT=""
LAST_EXIT_CODE=0

# Runs the monitor script and captures its output and its exit code.
capture() {
    local exit_code=0
    LAST_OUTPUT=$("$MONITOR_SCRIPT" "$@" 2>&1) || exit_code=$?
    LAST_EXIT_CODE=$exit_code
}

cleanup() {
    rm -rf "$TEST_SANDBOX"
}
trap cleanup EXIT

# Assert two values are equal.
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        printf "%b[FAIL]%b %s (Expected: '%s', Got: '%s')\n" \
            "$RED" "$RESET" "$test_name" "$expected" "$actual" >&2
        if [[ -n "$LAST_OUTPUT" ]]; then
            printf "  --- the script printed ---\n%s\n  ---------------------------\n" \
                "$LAST_OUTPUT" >&2
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Assert a command exits with the expected code.
assert_exit_code() {
    local expected="$1"
    local test_name="$2"
    shift 2

    capture "$@"
    assert_equals "$expected" "$LAST_EXIT_CODE" "$test_name"
}

# Assert a string contains a substring.
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        printf "%b[FAIL]%b %s (Expected to contain: '%s')\n" \
            "$RED" "$RESET" "$test_name" "$needle" >&2
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Assert a JSON document parses and reports the expected top-level keys.
assert_json_keys() {
    local file="$1"
    local expected_keys="$2"
    local test_name="$3"

    local actual_keys
    actual_keys=$(python3 -c "
import json, sys
with open(sys.argv[1]) as handle:
    print(','.join(sorted(json.load(handle).keys())))
" "$file" 2>/dev/null || echo "PARSE_ERROR")

    assert_equals "$expected_keys" "$actual_keys" "$test_name"
}

# ------------------------------------------------------------------------------
# Test 1: The help output succeeds and describes the interface
# ------------------------------------------------------------------------------
test_help_output() {
    capture --help
    local output="$LAST_OUTPUT"
    assert_exit_code 0 "Test 1a: --help exits with code 0"
    assert_contains "$output" "Usage:" "Test 1b: --help prints the usage line"
    assert_contains "$output" "--json" "Test 1c: --help documents --json"
    assert_contains "$output" "--export" "Test 1d: --help documents --export"
}

# ------------------------------------------------------------------------------
# Test 2: The version output succeeds and names the tool
# ------------------------------------------------------------------------------
test_version_output() {
    capture --version
    local output="$LAST_OUTPUT"
    assert_exit_code 0 "Test 2a: --version exits with code 0"
    assert_contains "$output" "System Resource Monitor" "Test 2b: --version names the tool"
}

# ------------------------------------------------------------------------------
# Test 3: An unknown option is rejected
# ------------------------------------------------------------------------------
test_unknown_option() {
    capture --definitely-not-a-flag
    local output="$LAST_OUTPUT"
    assert_contains "$output" "Unknown option" "Test 3a: an unknown option is reported"
    assert_exit_code 1 "Test 3b: an unknown option exits with code 1" \
        "$MONITOR_SCRIPT" --definitely-not-a-flag
}

# ------------------------------------------------------------------------------
# Test 4: The watch interval is validated against its documented range
# ------------------------------------------------------------------------------
test_interval_validation() {
    capture --watch 400
    local output="$LAST_OUTPUT"
    assert_contains "$output" "at most" "Test 4a: an out-of-range interval is reported"
    assert_exit_code 1 "Test 4b: an out-of-range interval exits with code 1" \
        "$MONITOR_SCRIPT" --watch 400
}

# ------------------------------------------------------------------------------
# Test 5: The JSON output is valid and carries the documented contract
# ------------------------------------------------------------------------------
test_json_output() {
    local json_file="$TEST_SANDBOX/report.json"

    "$MONITOR_SCRIPT" --json --export "$json_file" >/dev/null 2>&1
    assert_exit_code 0 "Test 5a: --json --export exits with code 0"

    if [[ ! -f "$json_file" ]]; then
        printf "%b[FAIL]%b %s (the export file was not created)\n" \
            "$RED" "$RESET" "Test 5b: --json --export creates the file" >&2
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return
    fi
    printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "Test 5b: --json --export creates the file"
    PASSED_TESTS=$((PASSED_TESTS + 1))

    assert_json_keys "$json_file" \
        "aggregated_totals,cpu_percent,disk_io,disk_usage,memory_percent,os,timestamp,top_processes" \
        "Test 5c: the JSON document carries the documented top-level keys"
}

# ------------------------------------------------------------------------------
# Test 6: The CSV output carries the documented header
# ------------------------------------------------------------------------------
test_csv_output() {
    local csv_file="$TEST_SANDBOX/report.csv"

    "$MONITOR_SCRIPT" --csv --export "$csv_file" >/dev/null 2>&1
    assert_exit_code 0 "Test 6a: --csv --export exits with code 0"

    local header
    header=$(head -1 "$csv_file" 2>/dev/null || echo "")
    assert_equals \
        "timestamp,os,metric_type,name,pid,cpu_percent,ram_mb,instances,mount_point,device,percent_used" \
        "$header" \
        "Test 6b: the CSV header matches the documented column order"
}

# ------------------------------------------------------------------------------
# Test 7: Exporting to a directory produces a timestamped file
# ------------------------------------------------------------------------------
test_export_to_directory() {
    local export_dir="$TEST_SANDBOX/exports"
    mkdir -p "$export_dir"

    "$MONITOR_SCRIPT" --json --export "$export_dir/" >/dev/null 2>&1
    assert_exit_code 0 "Test 7a: --export to a directory exits with code 0"

    local created
    # wc pads its count to a fixed width on BSD, which macOS ships, so the
    # whitespace is stripped before the comparison.
    created=$(find "$export_dir" -name 'system_monitor_*.json' | wc -l | tr -d '[:space:]')
    assert_equals "1" "$created" "Test 7b: --export to a directory creates one timestamped file"
}

# ------------------------------------------------------------------------------
# Test 7c: The reported mount points are paths
#
# macOS inserts extra columns into the df output, so a parser that assumes
# fixed positions reports the inode count instead of the mount point. This
# check is what catches that.
# ------------------------------------------------------------------------------
test_disk_mount_points() {
    local json_file="$TEST_SANDBOX/disks.json"
    "$MONITOR_SCRIPT" --json --export "$json_file" >/dev/null 2>&1

    local mount_points
    mount_points=$(python3 -c "
import json, sys
with open(sys.argv[1]) as handle:
    for disk in json.load(handle)['disk_usage']:
        print(disk['mount_point'])
" "$json_file" 2>/dev/null || echo "PARSE_ERROR")

    local bad=""
    while IFS= read -r mount_point; do
        [[ -z "$mount_point" ]] && continue
        [[ "$mount_point" == /* ]] || bad="$bad $mount_point"
    done <<< "$mount_points"

    assert_equals "" "$bad" "Test 7c: every reported mount point is an absolute path"
}

# ------------------------------------------------------------------------------
# Test 8: Killing a process that does not exist fails cleanly
# ------------------------------------------------------------------------------
test_kill_missing_process() {
    assert_exit_code 1 "Test 8: killing a missing PID exits with code 1" \
        "$MONITOR_SCRIPT" --kill 999999999
}

# ------------------------------------------------------------------------------
# Test 9: The output does not depend on the host locale
#
# Under a locale whose decimal separator is a comma the script used to emit
# values that printf could not parse, and the run failed with a non-zero
# exit. The script pins LC_NUMERIC=C, so every locale has to work.
# ------------------------------------------------------------------------------
test_locale_independence() {
    local checked=0
    local locale_name

    # The installed locale names are spelled inconsistently across systems
    # (es_CO.utf8, es_CO.UTF-8), so they are compared without case or dashes.
    local available
    available=$(locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d '_')

    for locale_name in "es_CO.UTF-8" "de_DE.UTF-8" "fr_FR.UTF-8"; do
        local normalized
        normalized=$(printf '%s' "$locale_name" | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d '_')

        if ! printf '%s\n' "$available" | grep -qx "$normalized"; then
            continue
        fi
        checked=$((checked + 1))

        local json_file="$TEST_SANDBOX/locale_${normalized}.json"
        local exit_code=0
        LC_ALL="$locale_name" "$MONITOR_SCRIPT" --json --export "$json_file" >/dev/null 2>&1 || exit_code=$?
        assert_equals "0" "$exit_code" "Test 9: the script succeeds under $locale_name"

        local parsed
        parsed=$(python3 -c "
import json, sys
with open(sys.argv[1]) as handle:
    json.load(handle)
print('valid')
" "$json_file" 2>/dev/null || echo "invalid")
        assert_equals "valid" "$parsed" "Test 9: the JSON output is valid under $locale_name"
    done

    if [[ $checked -eq 0 ]]; then
        printf "%b[PASS]%b %s (no comma-decimal locale is installed, nothing to check)\n" \
            "$GREEN" "$RESET" "Test 9: locale independence"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
}

# ------------------------------------------------------------------------------
# Run the suite
# ------------------------------------------------------------------------------
test_help_output
test_version_output
test_unknown_option
test_interval_validation
test_json_output
test_csv_output
test_export_to_directory
test_disk_mount_points
test_kill_missing_process
test_locale_independence

echo ""
echo "=============================================="
echo "Tests Passed: $PASSED_TESTS"
echo "Tests Failed: $FAILED_TESTS"
echo "=============================================="

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi
exit 0

#!/bin/bash
# ==============================================================================
# Test Suite: test_disk_monitor.sh
# Description: Automated integration and unit test suite for disk_monitor.sh.
#              Every test drives the public interface: flags, exit codes and
#              emitted output. Disk usage and the mail agent are stubbed on
#              PATH so the suite never touches the real filesystem layout and
#              never sends a real email.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/disk_monitor.sh"
TEST_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/test_disk_monitor.XXXXXX")"
STUB_DIR="$TEST_SANDBOX/stubs"
CAPTURE_FILE="$TEST_SANDBOX/mail_capture.txt"
ORIGINAL_PATH="$PATH"

# ANSI colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

# Captured results of the last run_monitor invocation.
LAST_STDOUT=""
LAST_STDERR=""
LAST_EXIT_CODE=0

# Creates the stub directory with a fake df and a fake mail agent.
# The stubs read their behaviour from environment variables so a test can
# change the world without rewriting the stub.
setup() {
    rm -rf "$TEST_SANDBOX"
    mkdir -p "$STUB_DIR"

    cat > "$STUB_DIR/df" <<'STUB'
#!/bin/bash
# Fake df. Emits the POSIX six-field layout so the module's parser is
# exercised exactly as it would be on a real host.
if [[ "${STUB_DF_FAIL:-0}" == "1" ]]; then
    echo "df: simulated failure" >&2
    exit 1
fi
usage="${STUB_DF_USAGE:-49}"
printf 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
printf '/dev/stub0        1000000  500000    500000      %s%% /\n' "$usage"
STUB
    chmod +x "$STUB_DIR/df"

    cat > "$STUB_DIR/df_spaced" <<'STUB'
#!/bin/bash
# Fake measurement command whose mount point contains a space. The capacity
# is still the fifth field, because the mount point is last and may be
# several words long.
printf 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
printf '/dev/stub0        1000000  500000    500000      63%% /mnt/my disk\n'
STUB
    chmod +x "$STUB_DIR/df_spaced"

    cat > "$STUB_DIR/df_alt" <<'STUB'
#!/bin/bash
# Fake measurement command used to prove the command can be replaced.
usage="${STUB_DF_ALT_USAGE:-77}"
printf 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
printf '/dev/stub0        1000000  500000    500000      %s%% /\n' "$usage"
STUB
    chmod +x "$STUB_DIR/df_alt"

    cat > "$STUB_DIR/mail" <<'STUB'
#!/bin/bash
# Fake mail agent. Records its arguments and stdin so the test can assert
# on the composed message without sending anything.
{
    printf 'ARGV:%s\n' "$*"
    printf 'STDIN-BEGIN\n'
    cat
    printf 'STDIN-END\n'
} >> "${STUB_MAIL_CAPTURE:-/dev/null}"
if [[ "${STUB_MAIL_FAIL:-0}" == "1" ]]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/mail"

    PATH="$STUB_DIR:$ORIGINAL_PATH"
    export PATH
    : > "$CAPTURE_FILE"
    export STUB_MAIL_CAPTURE="$CAPTURE_FILE"
    export STUB_DF_USAGE=49
    export STUB_DF_FAIL=0
    export STUB_MAIL_FAIL=0
    unset DISK_MONITOR_TO DISK_MONITOR_MAIL_COMMAND DISK_MONITOR_USAGE_OVERRIDE DISK_MONITOR_USAGE_COMMAND || true
}

teardown() {
    rm -rf "$TEST_SANDBOX"
    PATH="$ORIGINAL_PATH"
    export PATH
}

# Removes ANSI escape sequences so assertions can match plain text.
strip_ansi() {
    sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g'
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
        printf "%b[FAIL]%b %s (Expected to contain: '%s')\n" "$RED" "$RESET" "$test_name" "$needle" >&2
        ((FAILED_TESTS++)) || true
    fi
}

assert_file_exists() {
    local path="$1"
    local test_name="$2"

    if [[ -f "$path" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (File not found: '%s')\n" "$RED" "$RESET" "$test_name" "$path" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# Asserts that the mail agent was never invoked. The capture file is created
# by the harness itself, so the assertion is on its contents, not its absence.
assert_capture_empty() {
    local test_name="$1"
    local capture=""

    if [[ -f "$CAPTURE_FILE" ]]; then
        capture="$(cat "$CAPTURE_FILE" 2>/dev/null || true)"
    fi

    if [[ -z "$capture" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (Expected no mail activity, got: '%s')\n" \
            "$RED" "$RESET" "$test_name" "$capture" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# Runs the monitor and captures stdout, stderr and the exit code.
run_monitor() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0

    "$MONITOR_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

    LAST_STDOUT="$(strip_ansi < "$stdout_file")"
    LAST_STDERR="$(strip_ansi < "$stderr_file")"
    LAST_EXIT_CODE="$exit_code"
}

# Test 1: Help menu exits with code 0 and documents the flags.
test_help_menu() {
    setup
    run_monitor -h
    assert_equals "0" "$LAST_EXIT_CODE" "Test 1a: Help menu exits with code 0"
    assert_contains "$LAST_STDOUT" "Disk Usage Monitor" "Test 1b: Help menu names the tool"
    assert_contains "$LAST_STDOUT" "--threshold" "Test 1c: Help menu documents --threshold"
    assert_contains "$LAST_STDOUT" "--dry-run" "Test 1d: Help menu documents --dry-run"
    assert_contains "$LAST_STDOUT" "--notify" "Test 1e: Help menu documents --notify"
    teardown
}

# Test 2: An unknown flag is a configuration error.
test_unknown_flag() {
    setup
    run_monitor --this-flag-does-not-exist
    assert_equals "1" "$LAST_EXIT_CODE" "Test 2: Unknown flag exits with code 1"
    teardown
}

# Test 3: The threshold is validated as an integer between 1 and 100.
test_threshold_validation() {
    setup
    run_monitor -t 0
    assert_equals "1" "$LAST_EXIT_CODE" "Test 3a: Threshold 0 exits with code 1"
    run_monitor -t 101
    assert_equals "1" "$LAST_EXIT_CODE" "Test 3b: Threshold 101 exits with code 1"
    run_monitor -t abc
    assert_equals "1" "$LAST_EXIT_CODE" "Test 3c: Non-numeric threshold exits with code 1"
    teardown
}

# Test 4: The notify backend is validated against the supported set.
test_notify_validation() {
    setup
    run_monitor --notify carrier-pigeon --to ops@example.com
    assert_equals "1" "$LAST_EXIT_CODE" "Test 4: Unsupported notify backend exits with code 1"
    teardown
}

# Test 5: A partition that does not exist is a configuration error.
test_missing_partition() {
    setup
    run_monitor -p "$TEST_SANDBOX/does-not-exist" --to ops@example.com
    assert_equals "1" "$LAST_EXIT_CODE" "Test 5: Missing partition exits with code 1"
    teardown
}

# Test 6: A missing recipient is a configuration error when mail is enabled.
test_missing_recipient() {
    setup
    run_monitor --notify mail
    assert_equals "1" "$LAST_EXIT_CODE" "Test 6a: Missing recipient exits with code 1"
    assert_contains "$LAST_STDERR" "DISK_MONITOR_TO" "Test 6b: Missing recipient names the environment variable"
    teardown
}

# Test 7: An unresolvable mail agent is a configuration error.
test_missing_mail_agent() {
    setup
    run_monitor --mail-command "$TEST_SANDBOX/not-a-real-agent" --to ops@example.com
    assert_equals "1" "$LAST_EXIT_CODE" "Test 7: Unresolvable mail agent exits with code 1"
    assert_contains "$LAST_STDERR" "mail" "Test 7b: Unresolvable mail agent explains itself"
    teardown
}

# Test 8: Usage below the threshold exits 0 and sends nothing.
test_below_threshold() {
    setup
    export STUB_DF_USAGE=42
    run_monitor -t 80 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 8a: Usage below the threshold exits with code 0"
    assert_contains "$LAST_STDOUT" "42%" "Test 8b: The report shows the measured usage"
    assert_capture_empty "Test 8c: No alert is sent below the threshold"
    teardown
}

# Test 9: Usage above the threshold sends the alert and still exits 0.
test_above_threshold() {
    setup
    export STUB_DF_USAGE=91
    run_monitor -t 80 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 9a: Usage above the threshold exits with code 0"
    assert_contains "$LAST_STDOUT" "WARNING" "Test 9b: The report warns about the breach"

    local capture=""
    capture="$(cat "$CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ops@example.com" "Test 9c: The alert carries the recipient"
    assert_contains "$capture" "91%" "Test 9d: The alert body carries the measured usage"
    assert_contains "$capture" "Disk Alert" "Test 9e: The alert carries the expected subject"
    teardown
}

# Test 10: Usage exactly at the threshold does not alert.
test_threshold_boundary() {
    setup
    export STUB_DF_USAGE=80
    run_monitor -t 80 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 10a: Usage equal to the threshold exits with code 0"
    assert_capture_empty "Test 10b: Usage equal to the threshold does not alert"
    teardown
}

# Test 11: Dry-run reports the alert without handing it to the mail agent.
test_dry_run() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 -n --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 11a: Dry-run exits with code 0"
    assert_contains "$LAST_STDOUT" "DRY RUN" "Test 11b: Dry-run announces itself"
    assert_capture_empty "Test 11c: Dry-run hands nothing to the mail agent"
    teardown
}

# Test 12: --notify none never touches the mail agent.
test_notify_none() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 12a: --notify none exits with code 0"
    assert_capture_empty "Test 12b: --notify none hands nothing to the mail agent"
    teardown
}

# Test 13: --notify none needs no recipient.
test_notify_none_needs_no_recipient() {
    setup
    run_monitor --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 13: --notify none requires no recipient"
    teardown
}

# Test 14: The audit log is written.
test_audit_log() {
    setup
    local audit_file="$TEST_SANDBOX/logs/audit.log"
    export STUB_DF_USAGE=95
    run_monitor -t 80 --to ops@example.com -l "$audit_file"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 14a: Run with an audit log exits with code 0"
    assert_file_exists "$audit_file" "Test 14b: The audit log file is created"

    local audit_content=""
    audit_content="$(cat "$audit_file" 2>/dev/null || true)"
    assert_contains "$audit_content" "95" "Test 14c: The audit log records the measured usage"
    teardown
}

# Test 15: A disk usage read failure is a partial failure.
test_usage_read_failure() {
    setup
    export STUB_DF_FAIL=1
    run_monitor -t 80 --to ops@example.com
    assert_equals "2" "$LAST_EXIT_CODE" "Test 15: An unreadable disk usage exits with code 2"
    teardown
}

# Test 16: A failed alert hand-off is a partial failure.
test_alert_handoff_failure() {
    setup
    export STUB_DF_USAGE=95
    export STUB_MAIL_FAIL=1
    run_monitor -t 80 --to ops@example.com
    assert_equals "2" "$LAST_EXIT_CODE" "Test 16: A failed alert hand-off exits with code 2"
    teardown
}

# Test 17: The recipient falls back to the environment variable.
test_recipient_from_environment() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_TO="oncall@example.com"
    run_monitor -t 80
    assert_equals "0" "$LAST_EXIT_CODE" "Test 17a: The environment recipient is accepted"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "oncall@example.com" "Test 17b: The environment recipient is used"
    teardown
}

# Test 18: The mail command can be overridden by the environment.
test_mail_command_from_environment() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_MAIL_COMMAND="$STUB_DIR/mail"
    run_monitor -t 80 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 18: The mail command can come from the environment"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "ops@example.com" "Test 18b: The overridden mail command is used"
    teardown
}

# Test 19: The verbose flag is accepted and reports the resolved configuration.
test_verbose() {
    setup
    run_monitor -v --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 19a: The verbose flag is accepted"
    assert_contains "$LAST_STDOUT" "Partition" "Test 19b: The report names the watched partition"
    teardown
}

# Test 20: A forced usage value is honoured and labelled as such.
test_usage_override() {
    setup
    export DISK_MONITOR_USAGE_OVERRIDE=91
    run_monitor -t 80 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 20a: A forced usage value is accepted"
    assert_contains "$LAST_STDOUT" "91%" "Test 20b: The forced value is reported"
    assert_contains "$LAST_STDOUT" "overridden" "Test 20c: The report labels the value as overridden"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "91%" "Test 20d: The alert carries the forced value"
    teardown
}

# Test 21: An invalid forced usage value is a configuration error.
test_invalid_usage_override() {
    setup
    export DISK_MONITOR_USAGE_OVERRIDE=abc
    run_monitor -t 80 --to ops@example.com
    assert_equals "1" "$LAST_EXIT_CODE" "Test 21: An invalid usage override exits with code 1"
    teardown
}

# Test 22: The measurement command can be replaced.
test_usage_command_override() {
    setup
    export STUB_DF_ALT_USAGE=77
    export DISK_MONITOR_USAGE_COMMAND="$STUB_DIR/df_alt"
    run_monitor -t 70 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 22a: A replaced measurement command is accepted"
    assert_contains "$LAST_STDOUT" "77%" "Test 22b: The replaced command supplies the usage"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "77%" "Test 22c: The alert carries the replaced value"
    teardown
}

# Test 23: An unresolvable measurement command is a configuration error.
test_missing_usage_command() {
    setup
    export DISK_MONITOR_USAGE_COMMAND="$TEST_SANDBOX/not-a-real-command"
    run_monitor -t 80 --to ops@example.com
    assert_equals "1" "$LAST_EXIT_CODE" "Test 23: An unresolvable measurement command exits with code 1"
    teardown
}

# Test 24: The default measurement source works against the real host.
test_default_measurement_source() {
    setup
    PATH="$ORIGINAL_PATH"
    export PATH
    run_monitor -t 100 --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 24a: The default measurement source exits with code 0"
    assert_contains "$LAST_STDOUT" "measured" "Test 24b: The default source is labelled as measured"
    teardown
}

# Test 25: A mount point containing spaces does not shift the capacity column.
test_mount_point_with_spaces() {
    setup
    export DISK_MONITOR_USAGE_COMMAND="$STUB_DIR/df_spaced"
    run_monitor -t 60 --to ops@example.com
    assert_equals "0" "$LAST_EXIT_CODE" "Test 25a: A spaced mount point exits with code 0"
    assert_contains "$LAST_STDOUT" "63%" "Test 25b: The capacity is read from its fixed position"
    teardown
}

# Run all tests
printf "%bStarting Bash Disk Monitor Test Suite...%b\n" "$CYAN" "$RESET"
test_help_menu
test_unknown_flag
test_threshold_validation
test_notify_validation
test_missing_partition
test_missing_recipient
test_missing_mail_agent
test_below_threshold
test_above_threshold
test_threshold_boundary
test_dry_run
test_notify_none
test_notify_none_needs_no_recipient
test_audit_log
test_usage_read_failure
test_alert_handoff_failure
test_recipient_from_environment
test_mail_command_from_environment
test_verbose
test_usage_override
test_invalid_usage_override
test_usage_command_override
test_missing_usage_command
test_default_measurement_source
test_mount_point_with_spaces

printf "============================================================\n"
printf "Tests Summary: %b%d Passed%b, %b%d Failed%b\n" "$GREEN" "$PASSED_TESTS" "$RESET" "$RED" "$FAILED_TESTS" "$RESET"
printf "============================================================\n"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0

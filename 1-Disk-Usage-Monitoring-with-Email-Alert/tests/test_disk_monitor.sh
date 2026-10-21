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
HTTP_CAPTURE_FILE="$TEST_SANDBOX/http_capture.txt"
HTTP_ALT_CAPTURE_FILE="$TEST_SANDBOX/http_capture_alt.txt"
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

    cat > "$STUB_DIR/curl" <<'STUB'
#!/bin/bash
# Fake HTTP client. Records its arguments, one per line, and its stdin, so
# the test can assert on the composed request without touching the network.
{
    printf 'ARGC:%s\n' "$#"
    printf 'ARG:%s\n' "$@"
    printf 'STDIN-BEGIN\n'
    cat
    printf 'STDIN-END\n'
} >> "${STUB_HTTP_CAPTURE:-/dev/null}"
if [[ "${STUB_HTTP_FAIL:-0}" == "1" ]]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/curl"

    cat > "$STUB_DIR/curl_alt" <<'STUB'
#!/bin/bash
# Fake HTTP client used to prove the client can be replaced. It writes to a
# capture file of its own, so the test can tell which client was used.
{
    printf 'ARGC:%s\n' "$#"
    printf 'ARG:%s\n' "$@"
    printf 'STDIN-BEGIN\n'
    cat
    printf 'STDIN-END\n'
} >> "${STUB_HTTP_CAPTURE_ALT:-/dev/null}"
exit 0
STUB
    chmod +x "$STUB_DIR/curl_alt"

    PATH="$STUB_DIR:$ORIGINAL_PATH"
    export PATH
    : > "$CAPTURE_FILE"
    : > "$HTTP_CAPTURE_FILE"
    : > "$HTTP_ALT_CAPTURE_FILE"
    export STUB_MAIL_CAPTURE="$CAPTURE_FILE"
    export STUB_HTTP_CAPTURE="$HTTP_CAPTURE_FILE"
    export STUB_HTTP_CAPTURE_ALT="$HTTP_ALT_CAPTURE_FILE"
    export STUB_DF_USAGE=49
    export STUB_DF_FAIL=0
    export STUB_MAIL_FAIL=0
    export STUB_HTTP_FAIL=0
    unset DISK_MONITOR_TO DISK_MONITOR_MAIL_COMMAND DISK_MONITOR_USAGE_OVERRIDE DISK_MONITOR_USAGE_COMMAND \
        DISK_MONITOR_CONFIG DISK_MONITOR_THRESHOLD DISK_MONITOR_PARTITION DISK_MONITOR_NOTIFY \
        DISK_MONITOR_LOG_FILE DISK_MONITOR_URL DISK_MONITOR_BODY_TEMPLATE DISK_MONITOR_HEADER \
        DISK_MONITOR_TIMEOUT DISK_MONITOR_HTTP_COMMAND || true
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
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (Expected NOT to contain: '%s')\n" "$RED" "$RESET" "$test_name" "$needle" >&2
        ((FAILED_TESTS++)) || true
    fi
}

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

# Asserts that the HTTP client was never invoked.
assert_http_capture_empty() {
    local test_name="$1"
    local capture=""

    if [[ -f "$HTTP_CAPTURE_FILE" ]]; then
        capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    fi

    if [[ -z "$capture" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (Expected no HTTP activity, got: '%s')\n" \
            "$RED" "$RESET" "$test_name" "$capture" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# Asserts that the text matches an extended regular expression.
assert_matches() {
    local haystack="$1"
    local pattern="$2"
    local test_name="$3"

    if [[ "$haystack" =~ $pattern ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$test_name"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (Expected to match: '%s')\n" \
            "$RED" "$RESET" "$test_name" "$pattern" >&2
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

# Test 26: A configuration file supplies the partition and the threshold.
test_config_file_values() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf '# a comment line\npartition = /tmp\nthreshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    run_monitor --config "$config_file" --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 26a: A configuration file is accepted"
    assert_contains "$LAST_STDOUT" "/tmp" "Test 26b: The configured partition is used"
    assert_contains "$LAST_STDOUT" "WARNING" "Test 26c: The configured threshold is used"
    teardown
}

# Test 27: A command line flag overrides the configuration file.
test_config_precedence_flag() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'threshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    run_monitor --config "$config_file" --threshold 90 --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 27a: The run succeeds"
    assert_not_contains "$LAST_STDOUT" "WARNING" "Test 27b: The flag overrides the configured threshold"
    teardown
}

# Test 28: An environment variable overrides the configuration file.
test_config_precedence_environment() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'threshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    export DISK_MONITOR_THRESHOLD=90
    run_monitor --config "$config_file" --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 28a: The run succeeds"
    assert_not_contains "$LAST_STDOUT" "WARNING" "Test 28b: The environment overrides the configured threshold"
    teardown
}

# Test 29: A command line flag overrides the environment variable.
test_config_precedence_flag_over_environment() {
    setup
    export STUB_DF_USAGE=70
    export DISK_MONITOR_THRESHOLD=90
    run_monitor --threshold 20 --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 29a: The run succeeds"
    assert_contains "$LAST_STDOUT" "WARNING" "Test 29b: The flag overrides the environment"
    teardown
}

# Test 30: The configuration file supplies the recipient.
test_config_file_recipient() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'to = oncall@example.com\nthreshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    run_monitor --config "$config_file" --mail-command "$STUB_DIR/mail"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 30a: The run succeeds"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "oncall@example.com" "Test 30b: The configured recipient is used"
    teardown
}

# Test 31: A configuration file that does not exist is a configuration error.
test_config_file_missing() {
    setup
    run_monitor --config "$TEST_SANDBOX/no-such-file.conf" --notify none
    assert_equals "1" "$LAST_EXIT_CODE" "Test 31: A missing configuration file exits with code 1"
    teardown
}

# Test 32: A malformed line is reported and ignored; the rest still applies.
test_config_file_malformed_line() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'this line has no separator\nthreshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    run_monitor --config "$config_file" --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 32a: The run succeeds despite a malformed line"
    assert_contains "$LAST_STDERR" "malformed" "Test 32b: The malformed line is reported"
    assert_contains "$LAST_STDOUT" "WARNING" "Test 32c: The valid lines are still applied"
    teardown
}

# Test 33: An unknown key is reported and ignored.
test_config_file_unknown_key() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'threshold = 60\nnot_a_real_key = value\n' > "$config_file"
    export STUB_DF_USAGE=70
    run_monitor --config "$config_file" --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 33a: The run succeeds despite an unknown key"
    assert_contains "$LAST_STDERR" "not_a_real_key" "Test 33b: The unknown key is reported"
    teardown
}

# Test 34: A quoted value keeps its spaces.
test_config_file_quoted_value() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'to = "ops team@example.com"\nthreshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    run_monitor --config "$config_file" --mail-command "$STUB_DIR/mail"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 34a: The run succeeds"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "ops team@example.com" "Test 34b: The quoted value keeps its spaces"
    teardown
}

# Test 35: The configuration file path can come from the environment.
test_config_file_from_environment() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'threshold = 60\n' > "$config_file"
    export STUB_DF_USAGE=70
    export DISK_MONITOR_CONFIG="$config_file"
    run_monitor --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 35a: The run succeeds"
    assert_contains "$LAST_STDOUT" "WARNING" "Test 35b: The configured threshold is used"
    teardown
}

# Test 36: A configuration file without a separator is not a valid file.
test_config_file_without_separator() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'partition = /tmp\nthreshold = 60\n' > "$config_file"
    run_monitor --config "$config_file" --notify none
    assert_equals "0" "$LAST_EXIT_CODE" "Test 36a: A well formed configuration file is accepted"
    teardown
}

# Test 37: The HTTP transport posts the alert to the endpoint.
test_http_transport_sends_the_request() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 37a: The HTTP transport exits with code 0"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "https://ntfy.sh/disk-alerts" "Test 37b: The request carries the endpoint"
    assert_contains "$capture" "ARG:--request" "Test 37c: The request carries the method option"
    assert_contains "$capture" "ARG:POST" "Test 37d: The default method is POST"
    assert_contains "$capture" "ARG:--max-time" "Test 37e: The request carries the timeout option"
    assert_contains "$capture" "ARG:10" "Test 37f: The default timeout is ten seconds"
    assert_contains "$capture" "95%" "Test 37g: The request body carries the measured usage"
    teardown
}

# Test 38: The body template placeholders are substituted.
test_http_body_template_placeholders() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -p "$TEST_SANDBOX" -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --body-template '{host}|{partition}|{usage}|{threshold}|{recipient}|{timestamp}|{subject}' \
        --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 38a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "|" "Test 38b: The template is rendered"
    assert_contains "$capture" "|$TEST_SANDBOX|" "Test 38c: The partition placeholder is substituted"
    assert_contains "$capture" "|95%|80%|" "Test 38d: The usage and threshold placeholders are substituted"
    assert_contains "$capture" "https://ntfy.sh/disk-alerts|" "Test 38e: The recipient placeholder is the endpoint"
    assert_contains "$capture" "Disk Alert" "Test 38f: The subject placeholder is substituted"
    assert_matches "$capture" '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "Test 38g: The timestamp placeholder is substituted"
    teardown
}

# Test 39: The default body template is the plain-text message.
test_http_default_body_template() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -p "$TEST_SANDBOX" -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 39a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "Disk usage on" "Test 39b: The default body is the plain-text message"
    assert_contains "$capture" "Partition : $TEST_SANDBOX" "Test 39c: The default body carries the partition"
    assert_contains "$capture" "Threshold: 80%" "Test 39d: The default body carries the threshold"
    teardown
}

# Test 40: A missing endpoint is a configuration error.
test_http_missing_endpoint() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --http-command "$STUB_DIR/curl"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 40a: A missing endpoint exits with code 1"
    assert_contains "$LAST_STDERR" "DISK_MONITOR_URL" "Test 40b: The missing endpoint names the environment variable"
    teardown
}

# Test 41: An unresolvable HTTP client is a configuration error.
test_http_missing_client() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --http-command "$TEST_SANDBOX/not-a-real-client"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 41: An unresolvable HTTP client exits with code 1"
    teardown
}

# Test 42: A failed request is a partial failure.
test_http_request_failure() {
    setup
    export STUB_DF_USAGE=95
    export STUB_HTTP_FAIL=1
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "2" "$LAST_EXIT_CODE" "Test 42: A failed HTTP request exits with code 2"
    teardown
}

# Test 43: A header value is never reported and never logged.
test_http_header_value_is_never_reported() {
    setup
    export STUB_DF_USAGE=95
    local audit_file="$TEST_SANDBOX/logs/audit.log"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --header "Authorization: Bearer super-secret-token" --http-command "$STUB_DIR/curl" \
        -l "$audit_file"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 43a: The run succeeds"

    local audit_content=""
    audit_content="$(cat "$audit_file" 2>/dev/null || true)"
    assert_not_contains "$LAST_STDOUT" "super-secret-token" "Test 43b: The header value is not printed"
    assert_not_contains "$LAST_STDERR" "super-secret-token" "Test 43c: The header value is not reported as an error"
    assert_not_contains "$audit_content" "super-secret-token" "Test 43d: The header value is not written to the audit log"
    teardown
}

# Test 44: The endpoint falls back to the environment variable.
test_http_endpoint_from_environment() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_URL="https://ntfy.sh/from-env"
    run_monitor -t 80 --notify http --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 44a: The run succeeds"
    assert_contains "$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)" "https://ntfy.sh/from-env" "Test 44b: The environment endpoint is used"
    teardown
}

# Test 45: The body template falls back to the environment variable.
test_http_body_template_from_environment() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_BODY_TEMPLATE='{"text":"{body}"}'
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 45a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" '{"text":"Disk usage on' "Test 45b: The environment body template is used"
    teardown
}

# Test 46: The timeout falls back to the environment variable.
test_http_timeout_from_environment() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_TIMEOUT="42"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 46a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:--max-time" "Test 46b: The request carries the timeout option"
    assert_contains "$capture" "ARG:42" "Test 46c: The environment timeout is used"
    teardown
}

# Test 47: The method and the endpoint come from the configuration file.
test_http_values_from_config_file() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'method = PUT\nurl = https://ntfy.sh/from-config\n' > "$config_file"
    export STUB_DF_USAGE=95
    run_monitor --config "$config_file" -t 80 --notify http --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 47a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:PUT" "Test 47b: The configured method is used"
    assert_contains "$capture" "https://ntfy.sh/from-config" "Test 47c: The configured endpoint is used"
    teardown
}

# Test 48: The flag wins over the environment and the configuration file.
test_http_precedence_flag_wins() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'url = https://ntfy.sh/from-config\n' > "$config_file"
    export STUB_DF_USAGE=95
    export DISK_MONITOR_URL="https://ntfy.sh/from-env"
    run_monitor --config "$config_file" -t 80 --notify http --url "https://ntfy.sh/from-flag" \
        --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 48a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "https://ntfy.sh/from-flag" "Test 48b: The flag wins"
    assert_not_contains "$capture" "https://ntfy.sh/from-env" "Test 48c: The environment is not used"
    assert_not_contains "$capture" "https://ntfy.sh/from-config" "Test 48d: The configuration file is not used"
    teardown
}

# Test 49: The HTTP client can be replaced by the flag and by the environment.
test_http_client_can_be_replaced() {
    setup
    export STUB_DF_USAGE=95

    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl_alt"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 49a: The run succeeds with a replaced client"
    assert_contains "$(cat "$HTTP_ALT_CAPTURE_FILE" 2>/dev/null || true)" "https://ntfy.sh/disk-alerts" "Test 49b: The replaced client carries the request"

    : > "$HTTP_ALT_CAPTURE_FILE"
    export DISK_MONITOR_HTTP_COMMAND="$STUB_DIR/curl_alt"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 49c: The run succeeds with an environment client"
    assert_contains "$(cat "$HTTP_ALT_CAPTURE_FILE" 2>/dev/null || true)" "https://ntfy.sh/disk-alerts" "Test 49d: The environment client carries the request"
    teardown
}

# Test 50: The default client on PATH is used when nothing overrides it.
test_http_default_client_on_path() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 50a: The run succeeds with the default client"
    assert_contains "$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)" "https://ntfy.sh/disk-alerts" "Test 50b: The default client carries the request"
    teardown
}

# Test 51: A malformed timeout is a configuration error.
test_http_invalid_timeout() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_TIMEOUT="abc"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 51a: A malformed timeout exits with code 1"

    export DISK_MONITOR_TIMEOUT="0"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 51b: A zero timeout exits with code 1"
    teardown
}

# Test 52: A malformed method is a configuration error.
test_http_invalid_method() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'method = "BAD METHOD"\n' > "$config_file"
    export STUB_DF_USAGE=95
    run_monitor --config "$config_file" -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --http-command "$STUB_DIR/curl"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 52: A malformed method exits with code 1"
    teardown
}

# Test 53: A malformed header is a configuration error and its value is not reported.
test_http_invalid_header() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --header "not-a-header-value" --http-command "$STUB_DIR/curl"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 53a: A malformed header exits with code 1"
    assert_not_contains "$LAST_STDERR" "not-a-header-value" "Test 53b: The malformed header value is not reported"
    teardown
}

# Test 54: A malformed endpoint is a configuration error.
test_http_invalid_endpoint() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "not-a-url" --http-command "$STUB_DIR/curl"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 54: A malformed endpoint exits with code 1"
    teardown
}

# Test 55: A header reaches the request.
test_http_header_reaches_the_request() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --header "X-Title: Disk" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 55a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:--header" "Test 55b: The request carries the header option"
    assert_contains "$capture" "ARG:X-Title: Disk" "Test 55c: The request carries the header value"
    teardown
}

# Test 56: A JSON body template keeps its braces.
test_http_json_body_template() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --body-template '{"text":"{body}"}' --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 56a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" '{"text":"Disk usage on' "Test 56b: The JSON template keeps its braces"
    teardown
}

# Test 57: Several headers come from the configuration file.
test_http_headers_from_config_file() {
    setup
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'header = X-One: 1\nheader = X-Two: 2\nurl = https://ntfy.sh/disk-alerts\n' > "$config_file"
    export STUB_DF_USAGE=95
    run_monitor --config "$config_file" -t 80 --notify http --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 57a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:X-One: 1" "Test 57b: The first configured header is used"
    assert_contains "$capture" "ARG:X-Two: 2" "Test 57c: The second configured header is used"
    teardown
}

# Test 62: One header value may carry several headers, one per line.
test_http_header_value_with_several_lines() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --header $'X-One: 1\nX-Two: 2' --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 62a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:X-One: 1" "Test 62b: The first header of the value is used"
    assert_contains "$capture" "ARG:X-Two: 2" "Test 62c: The second header of the value is used"
    teardown
}

# Test 63: The flag may be repeated.
test_http_repeated_header_flag() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --header "X-One: 1" --header "X-Two: 2" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 63a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:X-One: 1" "Test 63b: The first header is used"
    assert_contains "$capture" "ARG:X-Two: 2" "Test 63c: The second header is used"
    teardown
}

# Test 58: The report names the endpoint and never a header value.
test_http_report_shows_the_endpoint_only() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --header "Authorization: Bearer secret-value" --http-command "$STUB_DIR/curl"
    assert_contains "$LAST_STDOUT" "https://ntfy.sh/disk-alerts" "Test 58a: The report names the endpoint"
    assert_not_contains "$LAST_STDOUT" "secret-value" "Test 58b: The report never names a header value"
    teardown
}

# Test 59: Usage below the threshold sends no request.
test_http_below_threshold_sends_nothing() {
    setup
    export STUB_DF_USAGE=42
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 59a: Usage below the threshold exits with code 0"
    assert_http_capture_empty "Test 59b: No request is sent below the threshold"
    teardown
}

# Test 60: Dry-run reports the alert and sends no request.
test_http_dry_run_sends_nothing() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 -n --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 60a: Dry-run exits with code 0"
    assert_contains "$LAST_STDOUT" "DRY RUN" "Test 60b: Dry-run announces itself"
    assert_http_capture_empty "Test 60c: Dry-run sends no request"
    teardown
}

# Test 61: The mail transport keeps working next to the HTTP transport.
test_mail_transport_still_works() {
    setup
    export STUB_DF_USAGE=95
    run_monitor -t 80 --notify mail --to ops@example.com --mail-command "$STUB_DIR/mail"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 61a: The mail transport exits with code 0"
    assert_contains "$(cat "$CAPTURE_FILE" 2>/dev/null || true)" "ops@example.com" "Test 61b: The mail transport still delivers"
    assert_http_capture_empty "Test 61c: The mail transport does not touch the HTTP client"
    teardown
}

# Test 64: The header comes from the environment variable.
test_http_header_from_environment() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_HEADER="X-From-Env: 1"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 64a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_contains "$capture" "ARG:X-From-Env: 1" "Test 64b: The environment header is used"
    teardown
}

# Test 65: A header flag that was supplied wins over the environment, even
# when its value is empty.
test_http_empty_header_flag_wins() {
    setup
    export STUB_DF_USAGE=95
    export DISK_MONITOR_HEADER="X-From-Env: 1"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --header "" \
        --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 65a: The run succeeds"

    local capture=""
    capture="$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)"
    assert_not_contains "$capture" "ARG:X-From-Env: 1" "Test 65b: The environment header is not used"
    teardown
}

# Test 66: A client that exists but cannot be run is a partial failure.
test_http_non_runnable_client() {
    setup
    export STUB_DF_USAGE=95
    local unusable="$TEST_SANDBOX/not-executable.txt"
    printf 'not a client\n' > "$unusable"
    chmod 644 "$unusable"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$unusable"
    assert_equals "2" "$LAST_EXIT_CODE" "Test 66: A client that cannot be run exits with code 2"
    teardown
}

# Test 67: A header value from the environment never reaches an output.
test_http_environment_header_is_never_reported() {
    setup
    export STUB_DF_USAGE=95
    local audit_file="$TEST_SANDBOX/logs/audit.log"
    export DISK_MONITOR_HEADER="Authorization: Bearer env-secret-token"
    run_monitor -t 80 --notify http --url "https://ntfy.sh/disk-alerts" --http-command "$STUB_DIR/curl" \
        -l "$audit_file"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 67a: The run succeeds"

    local audit_content=""
    audit_content="$(cat "$audit_file" 2>/dev/null || true)"
    assert_contains "$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)" "Authorization: Bearer env-secret-token" "Test 67b: The header does reach the request"
    assert_not_contains "$LAST_STDOUT" "env-secret-token" "Test 67c: The header value is not printed"
    assert_not_contains "$LAST_STDERR" "env-secret-token" "Test 67d: The header value is not reported as an error"
    assert_not_contains "$audit_content" "env-secret-token" "Test 67e: The header value is not written to the audit log"
    teardown
}

# Test 68: A header value from the configuration file never reaches an output.
test_http_config_header_is_never_reported() {
    setup
    export STUB_DF_USAGE=95
    local audit_file="$TEST_SANDBOX/logs/audit.log"
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'header = Authorization: Bearer config-secret-token\nurl = https://ntfy.sh/disk-alerts\n' > "$config_file"
    run_monitor --config "$config_file" -t 80 --notify http --http-command "$STUB_DIR/curl" \
        -l "$audit_file"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 68a: The run succeeds"

    local audit_content=""
    audit_content="$(cat "$audit_file" 2>/dev/null || true)"
    assert_contains "$(cat "$HTTP_CAPTURE_FILE" 2>/dev/null || true)" "Authorization: Bearer config-secret-token" "Test 68b: The header does reach the request"
    assert_not_contains "$LAST_STDOUT" "config-secret-token" "Test 68c: The header value is not printed"
    assert_not_contains "$LAST_STDERR" "config-secret-token" "Test 68d: The header value is not reported as an error"
    assert_not_contains "$audit_content" "config-secret-token" "Test 68e: The header value is not written to the audit log"
    teardown
}

# Test 69: A malformed configuration line is named, never shown, because a
# line pasted into the file by mistake may hold a token.
test_http_malformed_config_line_is_not_echoed() {
    setup
    export STUB_DF_USAGE=95
    local config_file="$TEST_SANDBOX/diskmonitor.conf"
    printf 'Authorization: Bearer pasted-secret-token\nthreshold = 60\n' > "$config_file"
    run_monitor --config "$config_file" -t 80 --notify http --url "https://ntfy.sh/disk-alerts" \
        --http-command "$STUB_DIR/curl"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 69a: The run succeeds"

    assert_contains "$LAST_STDERR" "malformed" "Test 69b: The malformed line is reported"
    assert_not_contains "$LAST_STDERR" "pasted-secret-token" "Test 69c: The malformed line is not echoed"
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
test_config_file_values
test_config_precedence_flag
test_config_precedence_environment
test_config_precedence_flag_over_environment
test_config_file_recipient
test_config_file_missing
test_config_file_malformed_line
test_config_file_unknown_key
test_config_file_quoted_value
test_config_file_from_environment
test_config_file_without_separator
test_http_transport_sends_the_request
test_http_body_template_placeholders
test_http_default_body_template
test_http_missing_endpoint
test_http_missing_client
test_http_request_failure
test_http_header_value_is_never_reported
test_http_endpoint_from_environment
test_http_body_template_from_environment
test_http_timeout_from_environment
test_http_values_from_config_file
test_http_precedence_flag_wins
test_http_client_can_be_replaced
test_http_default_client_on_path
test_http_invalid_timeout
test_http_invalid_method
test_http_invalid_header
test_http_invalid_endpoint
test_http_header_reaches_the_request
test_http_json_body_template
test_http_headers_from_config_file
test_http_header_value_with_several_lines
test_http_repeated_header_flag
test_http_report_shows_the_endpoint_only
test_http_below_threshold_sends_nothing
test_http_dry_run_sends_nothing
test_mail_transport_still_works
test_http_header_from_environment
test_http_empty_header_flag_wins
test_http_non_runnable_client
test_http_environment_header_is_never_reported
test_http_config_header_is_never_reported
test_http_malformed_config_line_is_not_echoed

printf "============================================================\n"
printf "Tests Summary: %b%d Passed%b, %b%d Failed%b\n" "$GREEN" "$PASSED_TESTS" "$RESET" "$RED" "$FAILED_TESTS" "$RESET"
printf "============================================================\n"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0

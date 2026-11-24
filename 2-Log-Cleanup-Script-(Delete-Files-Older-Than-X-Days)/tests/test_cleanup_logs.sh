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
    setup
    local exit_code=0 match=no
    "$CLEANUP_SCRIPT" -h > "$TEST_SANDBOX/stdout" 2> "$TEST_SANDBOX/stderr" || exit_code=$?
    cat > "$TEST_SANDBOX/expected" <<EOF
Log Cleanup Utility (Bash)
Usage: $CLEANUP_SCRIPT -d <directory> [OPTIONS]

Required Arguments:
  -d <path>         Target directory containing log files to clean.

Optional Arguments:
  -t <days>         Retention threshold in days (default: 30).
  -p <pattern>      Filename glob matching pattern (default: "*.log").
  -m <mb>           Minimum file size threshold in Megabytes (default: 0).
  -r                Recursively scan child directories (default: flat scan).
  -n                Dry-run simulation mode (preview without deleting).
  -l <file>         Path to append persistent ISO-8601 audit logs.
      --json            Output result as JSON.
      --csv             Output result as CSV.
  -v                Enable verbose per-file diagnostic output.
  -h                Show this help and usage documentation.

Examples:
  $CLEANUP_SCRIPT -d /var/log/myapp -t 14 -n
  $CLEANUP_SCRIPT -d /var/log/myapp -t 30 -p "*.log" -r -l /var/log/cleanup_audit.log
EOF
    cmp -s "$TEST_SANDBOX/expected" "$TEST_SANDBOX/stdout" && match=yes
    assert_equals '0' "$exit_code" 'Test 1: Help exits 0'
    assert_equals 'yes' "$match" 'Test 1: Help stdout matches the existing interface'
    assert_equals '' "$(cat "$TEST_SANDBOX/stderr")" 'Test 1: Help emits no stderr'
    teardown
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

test_incomplete_scan() {
    local mode="$1"
    shift
    setup
    local candidate="$TEST_SANDBOX/purge_me.log"
    printf '%s\n' 'original log' > "$candidate"
    touch -t 200001010000 "$candidate"
    mkdir -p "$TEST_SANDBOX/bin"
    local fake_find="$TEST_SANDBOX/bin/find"
    cat > "$fake_find" <<'STUB'
#!/bin/bash
printf '%s\0' "$1/purge_me.log"
exit 1
STUB
    chmod +x "$fake_find"

    local ec=0
    PATH="$TEST_SANDBOX/bin:$PATH" "$CLEANUP_SCRIPT" -d "$TEST_SANDBOX" -t 30 \
        -l "$TEST_SANDBOX/audit.txt" "$@" > "$TEST_SANDBOX/stdout" \
        2> "$TEST_SANDBOX/stderr" || ec=$?

    assert_equals '2' "$ec" "$mode: incomplete scan exits 2"
    assert_equals 'original log' "$(cat "$candidate" 2>/dev/null || true)" \
        "$mode: candidate remains untouched"
    assert_equals '' "$(cat "$TEST_SANDBOX/stdout")" "$mode: no partial report on stdout"
    local diagnostic='Error: File enumeration failed; no log files were processed.'
    assert_equals "$diagnostic" "$(cat "$TEST_SANDBOX/stderr")" "$mode: stderr diagnostic"
    assert_contains "$(cat "$TEST_SANDBOX/audit.txt")" "[ERROR] $diagnostic" \
        "$mode: audit records the enumeration failure"
    teardown
}

test_scan_ignores_tmpdir() {
    local temp_name="$1"
    setup
    local target="$TEST_SANDBOX/sub1"
    local candidate="$target/keep.log"
    local marker="$TEST_SANDBOX/mtime-reference"
    mkdir "$target/tmp"
    touch -t 200001010000 "$marker"
    touch -r "$marker" "$target/tmp"
    printf '%s\n' 'recent log' > "$candidate"

    local stdout ec=0
    stdout=$(TMPDIR="$target/$temp_name" "$CLEANUP_SCRIPT" -d "$target" \
        -r -n -p '*' --json 2> "$TEST_SANDBOX/stderr") || ec=$?

    assert_equals '0' "$ec" "Scan with TMPDIR=$temp_name exits 0"
    local expected
    expected=$(printf '%s\n' '{' '  "scanned": 1,' '  "eligible": 0,' '  "deleted": 0,' \
        '  "failed": 0,' '  "uninspectable": 0,' '  "reclaimed_bytes": 0,' \
        '  "outcome": "dry-run",' '  "files": []' '}')
    assert_equals "$expected" "$stdout" 'Scan counts only the input log'
    assert_equals '' "$(cat "$TEST_SANDBOX/stderr")" 'Successful scan emits no stderr'
    local modified=no
    [[ "$target/tmp" -nt "$marker" || "$target/tmp" -ot "$marker" ]] && modified=yes
    assert_equals 'no' "$modified" 'Dry-run leaves the temporary directory mtime intact'
    assert_equals '' "$(ls -A "$target/tmp")" 'Scan does not leave a spool behind'
    assert_equals 'no' "$([[ -e "$target/missing" ]] && echo yes || echo no)" \
        'Scan does not create a missing temporary directory'
    assert_equals 'recent log' "$(cat "$candidate")" 'Dry-run leaves the input log untouched'
    teardown
}

test_large_incomplete_scan() {
    if [[ "$(uname -s)" != Linux ]]; then
        printf '[SKIP] Linux virtual memory limit probe\n'
        return
    fi
    setup
    local target="$TEST_SANDBOX/sub1" rc=0
    printf 'keep\n' > "$target/old.log"
    touch -t 200001010000 "$target/old.log"
    mkdir "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/find" <<'STUB'
#!/bin/bash
printf '%s\0' "$1/old.log"
printf -v component '%0250d' 0
printf -v record '%s/' "$1" "$component" "$component" "$component" "$component"
for ((i = 0; i < 45056; i++)); do
    printf '%s.log\0' "$record" || exit 4
done
exit 3
STUB
    chmod +x "$TEST_SANDBOX/bin/find"
    (
        ulimit -v 32768
        PATH="$TEST_SANDBOX/bin:$PATH" "$CLEANUP_SCRIPT" -d "$target" --json
    ) > "$TEST_SANDBOX/stdout" 2> "$TEST_SANDBOX/stderr" || rc=$?
    assert_equals '2' "$rc" 'Large incomplete scan fails closed within 32 MiB'
    assert_equals '' "$(cat "$TEST_SANDBOX/stdout")" 'Large failure emits no report'
    assert_equals 'Error: File enumeration failed; no log files were processed.' \
        "$(cat "$TEST_SANDBOX/stderr")" 'Large failure emits the scan diagnostic'
    assert_equals 'keep' "$(cat "$target/old.log" 2>/dev/null || true)" \
        'Large incomplete scan preserves the first candidate'
    teardown
}

test_spool_write_failure() {
    setup
    local target="$TEST_SANDBOX/sub1" rc=0
    printf 'keep\n' > "$target/old.log"
    touch -t 200001010000 "$target/old.log"
    mkdir "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/find" <<'STUB'
#!/bin/bash
printf '%s\0' "$1/old.log"
printf '%16384s\0' ''
STUB
    chmod +x "$TEST_SANDBOX/bin/find"
    (
        ulimit -f 1
        PATH="$TEST_SANDBOX/bin:$PATH" "$CLEANUP_SCRIPT" -d "$target" --json
    ) > "$TEST_SANDBOX/stdout" 2> "$TEST_SANDBOX/stderr" || rc=$?
    assert_equals '2' "$rc" 'Spool write failure exits 2'
    assert_equals '' "$(cat "$TEST_SANDBOX/stdout")" 'Spool failure emits no report'
    assert_equals 'Error: File enumeration failed; no log files were processed.' \
        "$(cat "$TEST_SANDBOX/stderr")" 'Spool failure emits the scan diagnostic'
    assert_equals 'keep' "$(cat "$target/old.log" 2>/dev/null || true)" \
        'Spool write failure preserves the first candidate'
    teardown
}

test_nul_path_and_parent_signal() {
    setup
    local target="$TEST_SANDBOX/sub1" rc=0 name=$'first log\nwith newline and \\backslash.log'
    printf 'first\n' > "$target/$name"
    printf 'second\n' > "$target/second.log"
    touch -t 200001010000 "$target/$name" "$target/second.log"
    mkdir "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/find" <<'STUB'
#!/bin/bash
printf '%s\0' "$1/"$'first log\nwith newline and \\backslash.log' "$1/second.log"
STUB
    cat > "$TEST_SANDBOX/bin/rm" <<'STUB'
#!/bin/bash
if [[ "${2:-}" == */first* ]]; then
    /bin/rm "$@" || exit
    kill -TERM "$PPID"
else
    exec /bin/rm "$@"
fi
STUB
    chmod +x "$TEST_SANDBOX/bin/find" "$TEST_SANDBOX/bin/rm"
    PATH="$TEST_SANDBOX/bin:$PATH" "$CLEANUP_SCRIPT" -d "$target" --csv \
        > "$TEST_SANDBOX/stdout" 2> "$TEST_SANDBOX/stderr" &
    local cleanup_pid=$!
    wait "$cleanup_pid" 2>/dev/null || rc=$?
    assert_equals '143' "$rc" 'TERM interrupts the cleanup process itself'
    assert_equals 'no' "$([[ -e "$target/$name" ]] && echo yes || echo no)" \
        'Deletion receives the exact NUL-delimited pathname'
    assert_equals 'second' "$(cat "$target/second.log" 2>/dev/null || true)" \
        'TERM prevents the next deletion'
    assert_equals '' "$(cat "$TEST_SANDBOX/stdout")" 'Interrupted CSV emits no report'
    assert_equals '' "$(cat "$TEST_SANDBOX/stderr")" 'Interrupted CSV has no CLI diagnostic'
    teardown
}

test_retention_clock_precedes_scan() {
    setup
    local target="$TEST_SANDBOX/sub1" out rc=0
    printf 'inert\n' > "$target/edge.log"
    TZ=UTC touch -t 200001010000.01 "$target/edge.log"
    mkdir "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/date" <<'STUB'
#!/bin/bash
if [[ "$*" == +%s ]]; then
    if [[ -e "$SCAN_MARKER" ]]; then echo 949276810; else echo 949276800; fi
else
    command -p date "$@"
fi
STUB
    cat > "$TEST_SANDBOX/bin/find" <<'STUB'
#!/bin/bash
touch "$SCAN_MARKER"
printf '%s\0' "$1/edge.log"
STUB
    chmod +x "$TEST_SANDBOX/bin/"{date,find}
    out=$(SCAN_MARKER="$TEST_SANDBOX/scan-started" PATH="$TEST_SANDBOX/bin:$PATH" \
        "$CLEANUP_SCRIPT" -d "$target" -t 30 --csv 2> "$TEST_SANDBOX/stderr") || rc=$?
    assert_equals '0' "$rc" 'Retention boundary: cleanup exits 0'
    assert_equals 'path,size_bytes' "$out" 'Scan time does not advance the retention cutoff'
    assert_equals '' "$(cat "$TEST_SANDBOX/stderr")" 'Retention boundary: no stderr'
    assert_equals 'inert' "$(cat "$target/edge.log" 2>/dev/null || true)" \
        'File within retention at scan start is preserved'
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
test_incomplete_scan 'Live recursive JSON' -r --json
test_incomplete_scan 'Dry-run flat CSV' -n --csv
test_scan_ignores_tmpdir tmp
test_scan_ignores_tmpdir missing
test_large_incomplete_scan
test_spool_write_failure
test_nul_path_and_parent_signal
test_retention_clock_precedes_scan

printf "============================================================\n"
printf "Tests Summary: %b%d Passed%b, %b%d Failed%b\n" "$GREEN" "$PASSED_TESTS" "$RESET" "$RED" "$FAILED_TESTS" "$RESET"
printf "============================================================\n"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0

#!/bin/bash
# ==============================================================================
# Test Suite: test_db_backup.sh
# Description: Automated integration and unit test suite for db_backup.sh.
#              Every test drives the public interface: flags, exit codes and
#              emitted output. The database dump tool is stubbed on PATH so the
#              suite never needs a real database.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/db_backup.sh"
BACKUP_SCRIPT_PS="$SCRIPT_DIR/db_backup.ps1"
TEST_SANDBOX="$(mktemp -d "/tmp/test_db_backup.XXXXXX")"
STUB_DIR="$TEST_SANDBOX/stubs"
CAPTURE_FILE="$TEST_SANDBOX/dump_capture.txt"
ORIGINAL_PATH="$PATH"

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
    mkdir -p "$STUB_DIR"
    unset STUB_DUMP_FAIL STUB_DUMP_CAPTURE STUB_DB_NAME 2>/dev/null || true

    cat > "$STUB_DIR/mysqldump" <<'STUB'
#!/bin/bash
# Fake mysqldump. Writes a known payload to the output file named by -r or stdout,
# records its invocation, and honours STUB_DUMP_FAIL / STUB_DUMP_USAGE.
printf 'DUMP-CALLED\n' >> "${STUB_DUMP_CAPTURE:-/dev/null}"
if [[ "${STUB_DUMP_FAIL:-0}" == "1" ]]; then
    echo "mysqldump: simulated failure" >&2
    exit 1
fi
# Find output target: -r <file> or redirect; here we accept trailing positional db name
# and write to stdout unless -r given.
out=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    if [[ "${args[$i]}" == "-r" ]]; then
        out="${args[$((i+1))]}"
        break
    fi
    i=$((i+1))
done
if [[ -n "$out" ]]; then
    printf 'FAKE SQL DUMP for %s\n' "${STUB_DB_NAME:-mydatabase}" > "$out"
else
    printf 'FAKE SQL DUMP for %s\n' "${STUB_DB_NAME:-mydatabase}"
fi
exit 0
STUB
    chmod +x "$STUB_DIR/mysqldump"

    cat > "$STUB_DIR/pg_dump" <<'STUB'
#!/bin/bash
printf 'DUMP-CALLED\n' >> "${STUB_DUMP_CAPTURE:-/dev/null}"
if [[ "${STUB_DUMP_FAIL:-0}" == "1" ]]; then
    echo "pg_dump: simulated failure" >&2
    exit 1
fi
out=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    if [[ "${args[$i]}" == "-f" ]]; then
        out="${args[$((i+1))]}"
        break
    fi
    i=$((i+1))
done
if [[ -n "$out" ]]; then
    printf 'FAKE SQL DUMP for %s\n' "${STUB_DB_NAME:-mydatabase}" > "$out"
else
    printf 'FAKE SQL DUMP for %s\n' "${STUB_DB_NAME:-mydatabase}"
fi
exit 0
STUB
    chmod +x "$STUB_DIR/pg_dump"

    export PATH="$STUB_DIR:$ORIGINAL_PATH"
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
}

teardown() {
    export PATH="$ORIGINAL_PATH"
    rm -rf "$TEST_SANDBOX"
    mkdir -p "$TEST_SANDBOX"
    : > "$CAPTURE_FILE" 2>/dev/null || true
}

run_backup() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0

    "$BACKUP_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

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

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (unexpected '%s')\n" "$RED" "$RESET" "$label" "$needle" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# ---------- tests ----------

test_help_menu() {
    setup
    run_backup --help
    assert_equals "0" "$LAST_EXIT_CODE" "Test 1a: --help exits 0"
    assert_contains "$LAST_STDOUT" "Database Backup Utility" "Test 1b: help names the tool"
    teardown
}

test_unknown_flag() {
    setup
    run_backup --frobnicate
    assert_equals "1" "$LAST_EXIT_CODE" "Test 2: unknown flag exits 1"
    teardown
}

test_missing_password() {
    setup
    unset DB_BACKUP_PASSWORD 2>/dev/null || true
    run_backup --db-name foo --backup-dir "$TEST_SANDBOX/bk" --notify none 2>/dev/null || true
    # password required
    run_backup --db-name foo --backup-dir "$TEST_SANDBOX/bk"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 3: missing password exits 1"
    teardown
}

test_db_type_validation() {
    setup
    run_backup --db-type oracle --db-password secret --backup-dir "$TEST_SANDBOX/bk"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 4a: unsupported db type exits 1"
    teardown
}

test_retention_validation() {
    setup
    run_backup --db-password secret --retention-days 5000 --backup-dir "$TEST_SANDBOX/bk"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 5a: retention out of range exits 1"
    run_backup --db-password secret --retention-days abc --backup-dir "$TEST_SANDBOX/bk"
    assert_equals "1" "$LAST_EXIT_CODE" "Test 5b: non-numeric retention exits 1"
    teardown
}

test_guardrail_blocked_path() {
    setup
    run_backup --db-password secret --backup-dir /etc
    assert_equals "1" "$LAST_EXIT_CODE" "Test 6a: blocked path /etc exits 1"
    run_backup --db-password secret --backup-dir /
    assert_equals "1" "$LAST_EXIT_CODE" "Test 6b: blocked path / exits 1"
    teardown
}

test_dry_run() {
    setup
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    run_backup --db-password secret --backup-dir "$TEST_SANDBOX/bk" --dry-run
    assert_equals "0" "$LAST_EXIT_CODE" "Test 7a: dry-run exits 0"
    assert_contains "$LAST_STDOUT" "DRY RUN" "Test 7b: dry-run announces itself"
    # dump tool must NOT have been invoked
    if [[ -s "$CAPTURE_FILE" ]]; then
        printf "%b[FAIL]%b Test 7c: dump tool was invoked during dry-run\n" "$RED" "$RESET" >&2
        ((FAILED_TESTS++)) || true
    else
        printf "%b[PASS]%b Test 7c: dump tool not invoked during dry-run\n" "$GREEN" "$RESET"
        ((PASSED_TESTS++)) || true
    fi
    teardown
}

test_backup_created() {
    setup
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    run_backup --db-password secret --backup-dir "$bk"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 8a: backup exits 0"
    # a compressed file should exist
    local found
    found="$(find "$bk" -name '*.sql.gz' 2>/dev/null | head -1)"
    if [[ -n "$found" ]]; then
        printf "%b[PASS]%b Test 8b: compressed backup created\n" "$GREEN" "$RESET"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 8b: no compressed backup found\n" "$RED" "$RESET" >&2
        ((FAILED_TESTS++)) || true
    fi
    teardown
}

test_dump_failure() {
    setup
    export STUB_DUMP_FAIL=1
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    run_backup --db-password secret --backup-dir "$bk"
    assert_equals "2" "$LAST_EXIT_CODE" "Test 9: dump failure exits 2"
    teardown
}

test_retention_prunes_old() {
    setup
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    mkdir -p "$bk"
    # create an old backup file (portable mtime: 10 days ago)
    : > "$bk/mysql_mydatabase_20200101_000000.sql.gz"
    python3 - "$bk/mysql_mydatabase_20200101_000000.sql.gz" <<'PYEOF'
import os, sys, time
p = sys.argv[1]
t = time.time() - 10 * 86400
os.utime(p, (t, t))
PYEOF
    run_backup --db-password secret --backup-dir "$bk" --retention-days 7
    assert_equals "0" "$LAST_EXIT_CODE" "Test 10a: backup exits 0"
    if [[ ! -f "$bk/mysql_mydatabase_20200101_000000.sql.gz" ]]; then
        printf "%b[PASS]%b Test 10b: old backup pruned\n" "$GREEN" "$RESET"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 10b: old backup not pruned\n" "$RED" "$RESET" >&2
        ((FAILED_TESTS++)) || true
    fi
    teardown
}

test_postgresql_backend() {
    setup
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    run_backup --db-type postgresql --db-password secret --backup-dir "$bk"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 11a: postgresql backup exits 0"
    local found
    found="$(find "$bk" -name 'postgresql_*.sql.gz' 2>/dev/null | head -1)"
    if [[ -n "$found" ]]; then
        printf "%b[PASS]%b Test 11b: postgresql backup created\n" "$GREEN" "$RESET"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 11b: no postgresql backup found\n" "$RED" "$RESET" >&2
        ((FAILED_TESTS++)) || true
    fi
    teardown
}

test_password_from_env() {
    setup
    export DB_BACKUP_PASSWORD=secret
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    run_backup --db-name foo --backup-dir "$bk"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 12: password from env exits 0"
    unset DB_BACKUP_PASSWORD
    teardown
}

test_no_compress() {
    setup
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    run_backup --db-password secret --backup-dir "$bk" --no-compress
    assert_equals "0" "$LAST_EXIT_CODE" "Test 13a: no-compress exits 0"
    local found
    found="$(find "$bk" -name '*.sql' 2>/dev/null | head -1)"
    if [[ -n "$found" ]]; then
        printf "%b[PASS]%b Test 13b: raw .sql retained when --no-compress\n" "$GREEN" "$RESET"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 13b: no raw .sql found\n" "$RED" "$RESET" >&2
        ((FAILED_TESTS++)) || true
    fi
    teardown
}

test_audit_log() {
    setup
    export STUB_DUMP_CAPTURE="$CAPTURE_FILE"
    : > "$CAPTURE_FILE"
    local bk="$TEST_SANDBOX/bk"
    local audit="$TEST_SANDBOX/audit.log"
    run_backup --db-password secret --backup-dir "$bk" -l "$audit"
    assert_equals "0" "$LAST_EXIT_CODE" "Test 14a: backup with audit exits 0"
    if [[ -f "$audit" ]]; then
        printf "%b[PASS]%b Test 14b: audit log created\n" "$GREEN" "$RESET"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 14b: audit log not created\n" "$RED" "$RESET" >&2
        ((FAILED_TESTS++)) || true
    fi
    teardown
}

# Parity: ensure help mentions both backends
test_help_mentions_backends() {
    setup
    run_backup --help
    assert_contains "$LAST_STDOUT" "mysql" "Test 15a: help mentions mysql"
    assert_contains "$LAST_STDOUT" "postgresql" "Test 15b: help mentions postgresql"
    teardown
}

# Run all tests
printf "%bStarting DB Backup Test Suite...%b\n" "$CYAN" "$RESET"
test_help_menu
test_unknown_flag
test_missing_password
test_db_type_validation
test_retention_validation
test_guardrail_blocked_path
test_dry_run
test_backup_created
test_dump_failure
test_retention_prunes_old
test_postgresql_backend
test_password_from_env
test_no_compress
test_audit_log
test_help_mentions_backends

printf "============================================================\n"
printf "Tests Summary: %b%d Passed%b, %b%d Failed%b\n" "$GREEN" "$PASSED_TESTS" "$RESET" "$RED" "$FAILED_TESTS" "$RESET"
printf "============================================================\n"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0
#!/usr/bin/env bash
#
# db_backup.sh — Automated Database Backup with Timestamp
#
# Runs a database dump, compresses the result, stores it in a backup directory
# and prunes backups older than a retention window. Supports MySQL (mysqldump)
# and PostgreSQL (pg_dump). Credentials come from a flag or an environment
# variable and are never hardcoded, echoed or written to the audit log in full.
#
# Usage: db_backup.sh [OPTIONS]
#
# Exit codes:
#   0  success (backup created, compressed, retention applied)
#   1  configuration or safety violation
#   2  partial failure (dump, compression or retention step failed)

set -euo pipefail
IFS=$'\n\t'

# ---------- colours ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------- defaults ----------
DB_TYPE="mysql"
DB_NAME="mydatabase"
DB_USER="backup_user"
DB_PASSWORD=""
BACKUP_DIR="./backups"
RETENTION_DAYS=7
COMPRESS=true
DRY_RUN=false
LOG_FILE=""
VERBOSE=false


COLOR_RED="$RED"
COLOR_GREEN="$GREEN"
COLOR_YELLOW="$YELLOW"
COLOR_BLUE="$BLUE"
COLOR_RESET="$NC"

# ---------- helpers ----------

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s [%s] %s\n' "$timestamp" "$level" "$message" >>"$LOG_FILE" 2>/dev/null || true
    fi
    if [[ "$VERBOSE" == true || "$level" == "ERROR" || "$level" == "WARNING" ]]; then
        printf '%s\n' "$message" >&2
    fi
}

print_error() {
    printf '%bError: %s%b\n' "$COLOR_RED" "$1" "$COLOR_RESET" >&2
}

print_info() {
    printf '%b%s%b\n' "$COLOR_BLUE" "$1" "$COLOR_RESET"
}

print_success() {
    printf '%b%s%b\n' "$COLOR_GREEN" "$1" "$COLOR_RESET"
}

print_warning() {
    printf '%b%s%b\n' "$COLOR_YELLOW" "$1" "$COLOR_RESET" >&2
}

# ---------- guardrails ----------

is_blocked_path() {
    local path="$1"
    local lower
    lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        /|/etc|/etc/*|/var|/var/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/lib64|/lib64/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/root|/root/*)
            return 0
            ;;
    esac
    case "$lower" in
        c:|c:\\|c:\\windows|c:\\windows\\*|c:\\program\ files|c:\\program\ files\\*|c:\\users)
            return 0
            ;;
    esac
    return 1
}

# ---------- validation ----------

is_valid_db_type() {
    case "$1" in
        mysql|postgresql|postgres) return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_retention() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 0 ]] && [[ "$1" -le 3650 ]]
}

normalize_db_type() {
    case "$1" in
        postgres) printf 'postgresql' ;;
        *) printf '%s' "$1" ;;
    esac
}

# ---------- CLI parsing ----------

show_help() {
    cat <<EOF
Database Backup Utility (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -t, --db-type <mysql|postgresql>
                             Database engine (default: mysql).
  -n, --db-name <name>       Database name (default: mydatabase).
  -u, --db-user <user>       Database user (default: backup_user).
      --db-password <pass>   Database password (default: \$DB_BACKUP_PASSWORD).
  -d, --backup-dir <path>    Directory to store backups (default: ./backups).
  -r, --retention-days <n>   Delete backups older than n days (default: 7).
  -c, --compress             Compress the backup (default: on). Use --no-compress to disable.
      --no-compress          Do not compress the backup.
      --dry-run              Preview without dumping, compressing or deleting.
  -l, --log-file <file>      Append ISO-8601 audit records.
  -v, --verbose              Enable diagnostic output.
  -h, --help                 Show this help and exit 0.

Configuration:
  A flag wins over an environment variable, which wins over the built-in
  default. The password is read from --db-password, then DB_BACKUP_PASSWORD.
  No other setting has an environment variable in v1.

Exit Codes:
  0  success (backup created, compressed, retention applied)
  1  configuration or safety violation
  2  partial failure (dump, compression or retention step failed)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--db-type)
                DB_TYPE="$2"; shift 2 ;;
            -n|--db-name)
                DB_NAME="$2"; shift 2 ;;
            -u|--db-user)
                DB_USER="$2"; shift 2 ;;
            --db-password)
                DB_PASSWORD="$2"; shift 2 ;;
            -d|--backup-dir)
                BACKUP_DIR="$2"; shift 2 ;;
            -r|--retention-days)
                RETENTION_DAYS="$2"; shift 2 ;;
            -c|--compress)
                COMPRESS=true; shift ;;
            --no-compress)
                COMPRESS=false; shift ;;
            --dry-run)
                DRY_RUN=true; shift ;;
            -l|--log-file)
                LOG_FILE="$2"; shift 2 ;;
            -v|--verbose)
                VERBOSE=true; shift ;;
            -h|--help)
                show_help; exit 0 ;;
            --)
                shift; break ;;
            *)
                print_error "Unknown option: $1"
                exit 1 ;;
        esac
    done
}

# ---------- dump command resolution ----------

dump_command_for() {
    local db_type="$1"
    case "$db_type" in
        mysql) printf 'mysqldump' ;;
        postgresql) printf 'pg_dump' ;;
    esac
}

# ---------- main ----------

main() {
    parse_args "$@"

    DB_TYPE="$(normalize_db_type "$DB_TYPE")"

    # Validate db type
    if ! is_valid_db_type "$DB_TYPE"; then
        print_error "Unsupported database type: '$DB_TYPE'. Use mysql or postgresql."
        exit 1
    fi

    # Validate db name
    if [[ -z "$DB_NAME" ]]; then
        print_error "Database name must not be empty."
        exit 1
    fi

    # Validate db user
    if [[ -z "$DB_USER" ]]; then
        print_error "Database user must not be empty."
        exit 1
    fi

    # Resolve password
    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD="${DB_BACKUP_PASSWORD:-}"
    fi
    if [[ -z "$DB_PASSWORD" ]]; then
        print_error "Database password is required. Pass --db-password or set DB_BACKUP_PASSWORD."
        exit 1
    fi

    # Validate retention
    if ! is_valid_retention "$RETENTION_DAYS"; then
        print_error "Retention days must be an integer between 0 and 3650."
        exit 1
    fi

    # Guardrail: backup dir
    if is_blocked_path "$BACKUP_DIR"; then
        print_error "Refusing to use a system path as the backup directory: '$BACKUP_DIR'."
        exit 1
    fi

    local dump_tool
    dump_tool="$(dump_command_for "$DB_TYPE")"

    local timestamp
    timestamp="$(date +"%Y%m%d_%H%M%S")"
    local backup_file="${BACKUP_DIR}/${DB_TYPE}_${DB_NAME}_${timestamp}.sql"
    local compressed_file="${backup_file}.gz"

    print_info "=== Database Backup Utility ==="
    print_info "Database type : $DB_TYPE"
    print_info "Database name : $DB_NAME"
    print_info "Backup dir    : $BACKUP_DIR"
    print_info "Backup file   : $backup_file"
    print_info "Retention     : $RETENTION_DAYS days"
    print_info "Compress      : $COMPRESS"

    # Dry run
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would create backup directory: $BACKUP_DIR"
        print_info "[DRY RUN] Would invoke: $dump_tool ... > $backup_file"
        if [[ "$COMPRESS" == true ]]; then
            print_info "[DRY RUN] Would compress: $backup_file -> $compressed_file"
        fi
        print_info "[DRY RUN] Would prune backups older than $RETENTION_DAYS days in $BACKUP_DIR"
        log_message "INFO" "Dry run: planned backup $backup_file (no changes made)."
        exit 0
    fi

    # Create backup dir
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        print_error "Cannot create backup directory: '$BACKUP_DIR'."
        exit 1
    fi
    if [[ ! -w "$BACKUP_DIR" ]]; then
        print_error "Backup directory is not writable: '$BACKUP_DIR'."
        exit 1
    fi

    # Resolve dump tool
    if ! command -v "$dump_tool" >/dev/null 2>&1; then
        print_error "Database dump tool not found: '$dump_tool'. Install it and retry."
        exit 1
    fi

    # Run dump
    local dump_status=0
    case "$DB_TYPE" in
        mysql)
            MYSQL_PWD="$DB_PASSWORD" "$dump_tool" "-u${DB_USER}" "$DB_NAME" >"$backup_file" 2>/dev/null || dump_status=$?
            ;;
        postgresql)
            PGPASSWORD="$DB_PASSWORD" "$dump_tool" -U "$DB_USER" -d "$DB_NAME" -f "$backup_file" || dump_status=$?
            ;;
    esac

    if [[ $dump_status -ne 0 ]]; then
        print_error "Database dump failed (exit $dump_status)."
        log_message "ERROR" "Dump failed for $DB_TYPE/$DB_NAME (exit $dump_status)."
        rm -f "$backup_file"
        exit 2
    fi

    print_success "Backup created: $backup_file"
    log_message "INFO" "Backup created: $backup_file"

    # Compress
    if [[ "$COMPRESS" == true ]]; then
        if ! gzip -f "$backup_file" 2>/dev/null; then
            print_error "Compression failed for $backup_file."
            log_message "ERROR" "Compression failed for $backup_file."
            exit 2
        fi
        print_success "Compressed: $compressed_file"
        log_message "INFO" "Compressed: $compressed_file"
    fi

    # Retention pruning
    local pruned=0
    local prune_failed=0
    if [[ -d "$BACKUP_DIR" ]]; then
        while IFS= read -r -d '' old_file; do
            if rm -f "$old_file" 2>/dev/null; then
                pruned=$((pruned + 1))
                log_message "INFO" "Pruned old backup: $old_file"
            else
                prune_failed=$((prune_failed + 1))
                log_message "WARNING" "Failed to prune: $old_file"
            fi
        done < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.sql.gz' \) -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
    fi

    if [[ $prune_failed -gt 0 ]]; then
        print_warning "Retention pruning partially failed ($prune_failed file(s))."
        log_message "WARNING" "Retention pruning partial failure: $prune_failed file(s)."
    fi

    print_success "Backup complete. Pruned $pruned old backup(s)."
    log_message "INFO" "Backup complete for $DB_TYPE/$DB_NAME. Pruned $pruned old backup(s)."

    if [[ $prune_failed -gt 0 ]]; then
        exit 2
    fi
    exit 0
}

main "$@"

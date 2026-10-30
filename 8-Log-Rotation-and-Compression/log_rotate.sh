#!/bin/bash
# ==============================================================================
# Script Name: log_rotate.sh
# Description: Cross-platform log rotation with compression and retention.
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ANSI color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_RESET='\033[0m'

# Default configuration
LOG_FILE="/var/log/app/application.log"
MAX_SIZE_MB=10
BACKUP_COUNT=5
COMPRESS=true
FORCE=false
DRY_RUN=false
AUDIT_LOG=""
VERBOSE=false
OUTPUT_MODE="human"
JSON_OUTPUT=false
CSV_OUTPUT=false

# Metrics / state
ROTATED=false
FAILED_COUNT=0

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf "%bError: Option '%s' requires a value.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
        exit 1
    fi
}

is_nonneg_int() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

is_pos_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

show_help() {
    cat <<EOF
Log Rotation and Compression Utility (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -f, --log-file <path>     Target log file (default: /var/log/app/application.log).
  -m, --max-size-mb <n>     Rotation threshold in megabytes (default: 10).
  -c, --backup-count <n>    Number of rotated backups to retain (default: 5).
  -z, --compress            Compress the rotated backup (default).
      --no-compress          Keep the rotated backup raw (no compression).
      --force                Rotate regardless of file size.
      --dry-run              Preview actions without touching anything.
      --audit-log <file>     Append ISO-8601 audit log entries.
      --json                Output result as JSON.
      --csv                 Output result as CSV.
  -v, --verbose             Enable diagnostic output.
  -h, --help                Show this help and usage documentation.

Examples:
  $0 -f /var/log/app/application.log -m 10 -c 5 --dry-run
  $0 -f /var/log/app/application.log -m 10 -c 5
  $0 -f /var/log/app/application.log --force --no-compress
EOF
}

log_message() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"
    if [[ -n "$AUDIT_LOG" ]]; then
        printf "%s [%s] %s\n" "$timestamp" "$level" "$message" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
}

get_file_size() {
    local file="$1"
    # GNU stat
    stat -c %s "$file" 2>/dev/null || \
    # BSD stat (macOS)
    stat -f %z "$file" 2>/dev/null || \
    wc -c < "$file" 2>/dev/null || echo 0
}

get_realpath() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null || echo "$path"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$path" 2>/dev/null || echo "$path"
    else
        echo "$path"
    fi
}

validate_safety_guardrails() {
    local target="$1"
    local resolved
    resolved="$(get_realpath "$target")"

    local dir
    dir="$(dirname "$resolved")"

    local norm_dir="$dir"
    if [[ "$norm_dir" != "/" ]]; then
        norm_dir="${norm_dir%/}"
    fi

    local -a protected_paths=(
        "/"
        "/bin"
        "/sbin"
        "/usr"
        "/usr/bin"
        "/usr/sbin"
        "/etc"
        "/dev"
        "/proc"
        "/sys"
        "/boot"
        "/root"
        "/var"
        "/tmp"
        "/home"
        "/private"
        "/private/etc"
        "/private/var"
        "/private/tmp"
        "/Library"
        "/System"
        "/Applications"
        "/Volumes"
    )

    for protected in "${protected_paths[@]}"; do
        if [[ "$norm_dir" == "$protected" ]]; then
            printf "%bError: Safety violation! Log file '%s' is in a protected system directory.%b\n" \
                "$COLOR_RED" "$target" "$COLOR_RESET" >&2
            log_message "ERROR" "Execution blocked: log file '$target' in protected directory '$dir'."
            return 1
        fi
    done
    return 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--log-file)
                require_value "$1" "$#"
                LOG_FILE="$2"
                shift 2
                ;;
            -m|--max-size-mb)
                require_value "$1" "$#"
                MAX_SIZE_MB="$2"
                shift 2
                ;;
            -c|--backup-count)
                require_value "$1" "$#"
                BACKUP_COUNT="$2"
                shift 2
                ;;
            -z|--compress)
                COMPRESS=true
                shift
                ;;
            --no-compress)
                COMPRESS=false
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --audit-log)
                require_value "$1" "$#"
                AUDIT_LOG="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --csv)
                CSV_OUTPUT=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                printf "%bError: Unknown option '%s'.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
                show_help
                exit 1
                ;;
            *)
                printf "%bError: Unexpected argument '%s'.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
                exit 1
                ;;
        esac
    done

    if $JSON_OUTPUT && $CSV_OUTPUT; then
        printf "%bError: Cannot use --json and --csv together.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if $JSON_OUTPUT; then
        OUTPUT_MODE="json"
    elif $CSV_OUTPUT; then
        OUTPUT_MODE="csv"
    else
        OUTPUT_MODE="human"
    fi

    if [[ -z "$LOG_FILE" ]]; then
        printf "%bError: Log file path is required.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if ! is_nonneg_int "$MAX_SIZE_MB"; then
        printf "%bError: Max size must be a non-negative integer (MB).%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if ! is_pos_int "$BACKUP_COUNT"; then
        printf "%bError: Backup count must be a positive integer.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
}

# Build the backup filename for index i
backup_name() {
    local idx="$1"
    if [[ "$COMPRESS" == true ]]; then
        printf "%s.%s.gz" "$LOG_FILE" "$idx"
    else
        printf "%s.%s" "$LOG_FILE" "$idx"
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    parse_arguments "$@"

    # Existence + regular file
    if [[ ! -e "$LOG_FILE" ]]; then
        printf "%bError: Log file '%s' does not exist.%b\n" "$COLOR_RED" "$LOG_FILE" "$COLOR_RESET" >&2
        log_message "ERROR" "Log file does not exist: $LOG_FILE"
        exit 1
    fi
    if [[ -d "$LOG_FILE" ]]; then
        printf "%bError: Log file '%s' is a directory.%b\n" "$COLOR_RED" "$LOG_FILE" "$COLOR_RESET" >&2
        log_message "ERROR" "Log file is a directory: $LOG_FILE"
        exit 1
    fi

    if ! validate_safety_guardrails "$LOG_FILE"; then
        exit 1
    fi

    local file_size
    file_size="$(get_file_size "$LOG_FILE")"
    local max_size_bytes=$(( MAX_SIZE_MB * 1048576 ))

    local resolved
    resolved="$(get_realpath "$LOG_FILE")"

    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b            DevOps Log Rotation Utility                    %b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "Log File         : %b%s%b\n" "$COLOR_CYAN" "$resolved" "$COLOR_RESET"
        printf "Current Size     : %b%s bytes%b\n" "$COLOR_CYAN" "$file_size" "$COLOR_RESET"
        printf "Max Size         : %b%s MB (%s bytes)%b\n" "$COLOR_CYAN" "$MAX_SIZE_MB" "$max_size_bytes" "$COLOR_RESET"
        printf "Backup Count     : %b%s%b\n" "$COLOR_CYAN" "$BACKUP_COUNT" "$COLOR_RESET"
        printf "Compression      : %b%s%b\n" "$COLOR_CYAN" "$COMPRESS" "$COLOR_RESET"
        if [[ -n "$AUDIT_LOG" ]]; then
            printf "Audit Log        : %b%s%b\n" "$COLOR_CYAN" "$AUDIT_LOG" "$COLOR_RESET"
        fi
        printf "\n"
    fi

    # Decide whether rotation is needed
    local need_rotate=false
    if [[ "$FORCE" == true ]]; then
        need_rotate=true
    elif [[ "$file_size" -gt "$max_size_bytes" ]]; then
        need_rotate=true
    fi

    if [[ "$need_rotate" == false ]]; then
        if [[ "$OUTPUT_MODE" == "human" ]]; then
            printf "%bNo rotation needed (size %s <= threshold %s).%b\n" "$COLOR_GREEN" "$file_size" "$max_size_bytes" "$COLOR_RESET"
        fi
        log_message "INFO" "No rotation needed for '$resolved' (size=$file_size, threshold=$max_size_bytes)."
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            printf '{\n  "log_file": "%s",\n  "current_size_bytes": %s,\n  "max_size_bytes": %s,\n  "backup_count": %s,\n  "compress": %s,\n  "rotated": false,\n  "failed_steps": 0,\n  "outcome": "no-rotation-needed"\n}\n' "$resolved" "$file_size" "$max_size_bytes" "$BACKUP_COUNT" "$([[ "$COMPRESS" == true ]] && echo true || echo false)"
        elif [[ "$OUTPUT_MODE" == "csv" ]]; then
            printf 'log_file,current_size_bytes,max_size_bytes,backup_count,compress,rotated,failed_steps,outcome\n'
            printf '"%s",%s,%s,%s,%s,false,0,"no-rotation-needed"\n' "$resolved" "$file_size" "$max_size_bytes" "$BACKUP_COUNT" "$([[ "$COMPRESS" == true ]] && echo true || echo false)"
        fi
        exit 0
    fi

    # Dry-run plan
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$OUTPUT_MODE" == "human" ]]; then
            printf "%b[DRY RUN]%b Rotation planned for '%s':\n" "$COLOR_YELLOW" "$COLOR_RESET" "$resolved"
            # shift plan
            local i
            for (( i=BACKUP_COUNT; i>=1; i-- )); do
                local src
                src="$(backup_name "$i")"
                local dst
                dst="$(backup_name $((i+1)))"
                if [[ -f "$src" ]]; then
                    printf "  %b[DRY RUN]%b would move %s -> %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$src" "$dst"
                fi
            done
            printf "  %b[DRY RUN]%b would copy %s -> %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$LOG_FILE" "$(backup_name 1)"
            if [[ "$COMPRESS" == true ]]; then
                printf "  %b[DRY RUN]%b would compress %s -> %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$(backup_name 1)" "$(backup_name 1)"
            fi
            printf "  %b[DRY RUN]%b would truncate %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$LOG_FILE"
            local prune_idx=$((BACKUP_COUNT + 1))
            local prune_name
            prune_name="$(backup_name "$prune_idx")"
            if [[ -f "$prune_name" ]]; then
                printf "  %b[DRY RUN]%b would remove %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$prune_name"
            fi
        fi
        log_message "INFO" "[DRY RUN] Rotation planned for '$resolved'."
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            printf '{\n  "log_file": "%s",\n  "current_size_bytes": %s,\n  "max_size_bytes": %s,\n  "backup_count": %s,\n  "compress": %s,\n  "rotated": false,\n  "failed_steps": 0,\n  "outcome": "dry-run"\n}\n' "$resolved" "$file_size" "$max_size_bytes" "$BACKUP_COUNT" "$([[ "$COMPRESS" == true ]] && echo true || echo false)"
        elif [[ "$OUTPUT_MODE" == "csv" ]]; then
            printf 'log_file,current_size_bytes,max_size_bytes,backup_count,compress,rotated,failed_steps,outcome\n'
            printf '"%s",%s,%s,%s,%s,false,0,"dry-run"\n' "$resolved" "$file_size" "$max_size_bytes" "$BACKUP_COUNT" "$([[ "$COMPRESS" == true ]] && echo true || echo false)"
        fi
        exit 0
    fi

    # Live rotation
    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf "%bRotating...%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
    fi

    # Shift existing backups from highest down
    local i
    for (( i=BACKUP_COUNT; i>=1; i-- )); do
        local src dst
        src="$(backup_name "$i")"
        dst="$(backup_name $((i+1)))"
        if [[ -f "$src" ]]; then
            if [[ "$VERBOSE" == true && "$OUTPUT_MODE" == "human" ]]; then
                printf "  shifting %s -> %s\n" "$src" "$dst"
            fi
            if ! mv -f "$src" "$dst" 2>/dev/null; then
                printf "%b✗ Failed to move %s -> %s%b\n" "$COLOR_RED" "$src" "$dst" "$COLOR_RESET" >&2
                log_message "ERROR" "Failed to move $src -> $dst"
                ((FAILED_COUNT++)) || true
            fi
        fi
    done

    # Copy current log to slot 1
    local slot1
    slot1="$(backup_name 1)"
    # slot1 may end in .gz; copy to a temp raw name first
    local raw_slot="${LOG_FILE}.1"
    if [[ "$COMPRESS" == true ]]; then
        raw_slot="${LOG_FILE}.1"
    fi

    if [[ "$VERBOSE" == true && "$OUTPUT_MODE" == "human" ]]; then
        printf "  copying %s -> %s\n" "$LOG_FILE" "$raw_slot"
    fi
    if ! cp -p "$LOG_FILE" "$raw_slot" 2>/dev/null; then
        printf "%b✗ Failed to copy %s -> %s%b\n" "$COLOR_RED" "$LOG_FILE" "$raw_slot" "$COLOR_RESET" >&2
        log_message "ERROR" "Failed to copy $LOG_FILE -> $raw_slot"
        ((FAILED_COUNT++)) || true
    else
        if [[ "$COMPRESS" == true ]]; then
            if [[ "$VERBOSE" == true && "$OUTPUT_MODE" == "human" ]]; then
                printf "  compressing %s -> %s\n" "$raw_slot" "$slot1"
            fi
            if gzip -c "$raw_slot" > "$slot1" 2>/dev/null; then
                rm -f "$raw_slot" 2>/dev/null || true
                if [[ "$OUTPUT_MODE" == "human" ]]; then
                    printf "%b✓ Rotated to %s%b\n" "$COLOR_GREEN" "$slot1" "$COLOR_RESET"
                fi
                ROTATED=true
            else
                printf "%b✗ Compression failed for %s%b\n" "$COLOR_RED" "$raw_slot" "$COLOR_RESET" >&2
                log_message "ERROR" "Compression failed for $raw_slot"
                # keep raw as backup
                mv -f "$raw_slot" "$slot1" 2>/dev/null || true
                ((FAILED_COUNT++)) || true
            fi
        else
            # raw_slot already equals slot1 in no-compress mode
            if [[ "$OUTPUT_MODE" == "human" ]]; then
                printf "%b✓ Rotated to %s%b\n" "$COLOR_GREEN" "$slot1" "$COLOR_RESET"
            fi
            ROTATED=true
        fi
    fi

    # Truncate current log
    if [[ "$FAILED_COUNT" -eq 0 ]]; then
        if [[ "$VERBOSE" == true && "$OUTPUT_MODE" == "human" ]]; then
            printf "  truncating %s\n" "$LOG_FILE"
        fi
        if ! : > "$LOG_FILE" 2>/dev/null; then
            # fallback
            if ! truncate -s 0 "$LOG_FILE" 2>/dev/null; then
                printf "%b✗ Failed to truncate %s%b\n" "$COLOR_RED" "$LOG_FILE" "$COLOR_RESET" >&2
                log_message "ERROR" "Failed to truncate $LOG_FILE"
                ((FAILED_COUNT++)) || true
            fi
        fi
    fi

    # Prune beyond backup count
    local prune_idx=$((BACKUP_COUNT + 1))
    local prune_name
    prune_name="$(backup_name "$prune_idx")"
    if [[ -f "$prune_name" ]]; then
        if [[ "$VERBOSE" == true && "$OUTPUT_MODE" == "human" ]]; then
            printf "  pruning %s\n" "$prune_name"
        fi
        if ! rm -f "$prune_name" 2>/dev/null; then
            printf "%b✗ Failed to remove %s%b\n" "$COLOR_RED" "$prune_name" "$COLOR_RESET" >&2
            log_message "ERROR" "Failed to remove $prune_name"
            ((FAILED_COUNT++)) || true
        else
            if [[ "$OUTPUT_MODE" == "human" ]]; then
                printf "%b✓ Removed old backup %s%b\n" "$COLOR_YELLOW" "$prune_name" "$COLOR_RESET"
            fi
        fi
    fi

    # Summary
    local current_size
    current_size="$(get_file_size "$LOG_FILE")"
    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf "\n%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "Log File         : %b%s%b\n" "$COLOR_BOLD" "$resolved" "$COLOR_RESET"
        printf "Rotated          : %b%s%b\n" "$COLOR_BOLD" "$ROTATED" "$COLOR_RESET"
        printf "Backup Count     : %b%s%b\n" "$COLOR_BOLD" "$BACKUP_COUNT" "$COLOR_RESET"
        printf "Failed Steps     : %b%d%b\n" "$COLOR_RED" "$FAILED_COUNT" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    fi

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        printf '{\n  "log_file": "%s",\n  "current_size_bytes": %s,\n  "max_size_bytes": %s,\n  "backup_count": %s,\n  "compress": %s,\n  "rotated": %s,\n  "failed_steps": %s,\n  "outcome": "%s"\n}\n' "$resolved" "$current_size" "$max_size_bytes" "$BACKUP_COUNT" "$([[ "$COMPRESS" == true ]] && echo true || echo false)" "$([[ "$ROTATED" == true ]] && echo true || echo false)" "$FAILED_COUNT" "$([[ "$FAILED_COUNT" -gt 0 ]] && echo failed || echo rotated)"
    elif [[ "$OUTPUT_MODE" == "csv" ]]; then
        printf 'log_file,current_size_bytes,max_size_bytes,backup_count,compress,rotated,failed_steps,outcome\n'
        printf '"%s",%s,%s,%s,%s,%s,%s,"%s"\n' "$resolved" "$current_size" "$max_size_bytes" "$BACKUP_COUNT" "$([[ "$COMPRESS" == true ]] && echo true || echo false)" "$([[ "$ROTATED" == true ]] && echo true || echo false)" "$FAILED_COUNT" "$([[ "$FAILED_COUNT" -gt 0 ]] && echo failed || echo rotated)"
    fi

    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        log_message "ERROR" "Rotation completed with failures for '$resolved' (failed=$FAILED_COUNT)."
        exit 2
    fi

    log_message "INFO" "Rotation completed for '$resolved' (backup=$(backup_name 1))."
    exit 0
}

main "$@"
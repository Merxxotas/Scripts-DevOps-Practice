#!/bin/bash
# ==============================================================================
# Script Name: cleanup_logs.sh
# Description: Enterprise-grade log cleanup utility with retention policy,
#              safety guardrails, size filtering, dry-run simulation, and audit logging.
# ==============================================================================

set -euo pipefail

# ANSI color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_RESET='\033[0m'

# Default configuration
LOG_DIR=""
RETENTION_DAYS=30
FILE_PATTERN="*.log"
MIN_SIZE_MB=0
RECURSIVE=false
DRY_RUN=false
LOG_FILE=""
VERBOSE=false

# Metrics counters
TOTAL_SCANNED=0
ELIGIBLE_COUNT=0
DELETED_COUNT=0
FAILED_COUNT=0
TOTAL_RECLAIMED_BYTES=0

# Prints usage and help message
show_help() {
    cat <<EOF
Log Cleanup Utility (Bash)
Usage: $0 -d <directory> [OPTIONS]

Required Arguments:
  -d <path>         Target directory containing log files to clean.

Optional Arguments:
  -t <days>         Retention threshold in days (default: 30).
  -p <pattern>      Filename glob matching pattern (default: "*.log").
  -m <mb>           Minimum file size threshold in Megabytes (default: 0).
  -r                Recursively scan child directories (default: flat scan).
  -n                Dry-run simulation mode (preview without deleting).
  -l <file>         Path to append persistent ISO-8601 audit logs.
  -v                Enable verbose per-file diagnostic output.
  -h                Show this help and usage documentation.

Examples:
  $0 -d /var/log/myapp -t 14 -n
  $0 -d /var/log/myapp -t 30 -p "*.log" -r -l /var/log/cleanup_audit.log
EOF
}

# Writes messages to console and optional logfile with ISO-8601 timestamp
log_message() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"

    if [[ -n "$LOG_FILE" ]]; then
        printf "%s [%s] %s\n" "$timestamp" "$level" "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Formats byte integers into human-readable strings
format_bytes() {
    local bytes="${1:-0}"
    if [[ "$bytes" -lt 1024 ]]; then
        printf "%d B" "$bytes"
    elif [[ "$bytes" -lt 1048576 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB", b / 1024 }'
    elif [[ "$bytes" -lt 1073741824 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b / 1048576 }'
    else
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
    fi
}

# Queries file modification time in epoch seconds (cross-platform Linux/macOS)
get_file_mtime() {
    local file="$1"
    # GNU stat
    stat -c %Y "$file" 2>/dev/null || \
    # BSD stat (macOS)
    stat -f %m "$file" 2>/dev/null || \
    # Fallback to date
    date -r "$file" +%s 2>/dev/null || echo 0
}

# Queries file size in bytes (cross-platform Linux/macOS)
get_file_size() {
    local file="$1"
    # GNU stat
    stat -c %s "$file" 2>/dev/null || \
    # BSD stat (macOS)
    stat -f %z "$file" 2>/dev/null || \
    # Fallback to wc
    wc -c < "$file" 2>/dev/null || echo 0
}

# Resolves canonical real path
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

# Validates path against critical system directory blacklist
validate_safety_guardrails() {
    local target="$1"
    local resolved
    resolved="$(get_realpath "$target")"

    # Normalize paths by removing trailing slash if not root
    local norm_target="$target"
    if [[ "$norm_target" != "/" ]]; then
        norm_target="${norm_target%/}"
    fi

    local norm_resolved="$resolved"
    if [[ "$norm_resolved" != "/" ]]; then
        norm_resolved="${norm_resolved%/}"
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
        "/var/run"
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
        if [[ "$norm_target" == "$protected" || "$norm_resolved" == "$protected" ]]; then
            printf "%bError: Safety violation! Target directory '%s' is a protected system root.%b\n" "$COLOR_RED" "$target" "$COLOR_RESET" >&2
            log_message "ERROR" "Execution blocked: Target directory '$target' is a protected system root."
            return 1
        fi
    done
    return 0
}

# Parses and validates command line arguments
parse_arguments() {
    while getopts "d:t:p:m:rnl:vh" opt; do
        case "$opt" in
            d) LOG_DIR="$OPTARG" ;;
            t)
                if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                    printf "%bError: Retention days must be a positive integer.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
                    exit 1
                fi
                RETENTION_DAYS="$OPTARG"
                ;;
            p) FILE_PATTERN="$OPTARG" ;;
            m)
                if ! [[ "$OPTARG" =~ ^[0-9]+(.[0-9]+)?$ ]]; then
                    printf "%bError: Minimum size must be a numeric value.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
                    exit 1
                fi
                MIN_SIZE_MB="$OPTARG"
                ;;
            r) RECURSIVE=true ;;
            n) DRY_RUN=true ;;
            l) LOG_FILE="$OPTARG" ;;
            v) VERBOSE=true ;;
            h) show_help; exit 0 ;;
            *) show_help; exit 1 ;;
        esac
    done

    if [[ -z "$LOG_DIR" ]]; then
        printf "%bError: Target directory (-d) is required.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        show_help
        exit 1
    fi
}

# Main execution entrypoint
main() {
    parse_arguments "$@"

    if [[ ! -d "$LOG_DIR" ]]; then
        printf "%bError: Target directory '%s' does not exist.%b\n" "$COLOR_RED" "$LOG_DIR" "$COLOR_RESET" >&2
        log_message "ERROR" "Target directory does not exist: $LOG_DIR"
        exit 1
    fi

    if ! validate_safety_guardrails "$LOG_DIR"; then
        exit 1
    fi

    local resolved_dir
    resolved_dir="$(get_realpath "$LOG_DIR")"

    # Setup audit log header
    if [[ -n "$LOG_FILE" ]]; then
        local log_dir_parent
        log_dir_parent="$(dirname "$LOG_FILE")"
        if [[ ! -d "$log_dir_parent" ]]; then
            mkdir -p "$log_dir_parent" 2>/dev/null || true
        fi
    fi

    log_message "INFO" "Log cleanup initiated for '$resolved_dir' (Retention: ${RETENTION_DAYS}d, Pattern: '$FILE_PATTERN', Recursive: $RECURSIVE, DryRun: $DRY_RUN, MinSizeMB: $MIN_SIZE_MB)"

    local mode_label
    if [[ "$DRY_RUN" = true ]]; then
        mode_label="$(printf "%bDRY RUN (Simulation)%b" "$COLOR_YELLOW" "$COLOR_RESET")"
    else
        mode_label="$(printf "%bLIVE (Deletions Active)%b" "$COLOR_GREEN" "$COLOR_RESET")"
    fi

    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                DevOps Log Cleanup Utility                  %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Target Directory : %b%s%b\n" "$COLOR_CYAN" "$resolved_dir" "$COLOR_RESET"
    printf "Retention Policy : %bOlder than %s days%b\n" "$COLOR_YELLOW" "$RETENTION_DAYS" "$COLOR_RESET"
    printf "Matching Pattern : %b%s%b\n" "$COLOR_CYAN" "$FILE_PATTERN" "$COLOR_RESET"
    printf "Min Size Filter  : %b%s MB%b\n" "$COLOR_CYAN" "$MIN_SIZE_MB" "$COLOR_RESET"
    printf "Recursive Scan   : %b%s%b\n" "$COLOR_CYAN" "$RECURSIVE" "$COLOR_RESET"
    printf "Execution Mode   : %b\n" "$mode_label"
    if [[ -n "$LOG_FILE" ]]; then
        printf "Audit Log File   : %b%s%b\n" "$COLOR_CYAN" "$LOG_FILE" "$COLOR_RESET"
    fi
    printf "\n%bScanning target files...%b\n" "$COLOR_BLUE" "$COLOR_RESET"

    local current_epoch
    current_epoch="$(date +%s)"
    local cutoff_seconds
    cutoff_seconds=$(( RETENTION_DAYS * 86400 ))
    local cutoff_epoch
    cutoff_epoch=$(( current_epoch - cutoff_seconds ))

    local min_size_bytes
    min_size_bytes=$(awk -v m="$MIN_SIZE_MB" 'BEGIN { printf "%.0f", m * 1048576 }')

    # Construct find arguments
    local -a find_cmd=("find" "$LOG_DIR")
    if [[ "$RECURSIVE" = false ]]; then
        find_cmd+=("-maxdepth" "1")
    fi
    find_cmd+=("-type" "f" "-name" "$FILE_PATTERN")

    # Read files safely via null delimiter
    while IFS= read -r -d '' file_path; do
        ((TOTAL_SCANNED++)) || true

        local file_mtime
        file_mtime="$(get_file_mtime "$file_path")"
        local file_size
        file_size="$(get_file_size "$file_path")"

        # Check age threshold
        if [[ "$file_mtime" -le "$cutoff_epoch" ]]; then
            # Check minimum size threshold
            if [[ "$file_size" -ge "$min_size_bytes" ]]; then
                ((ELIGIBLE_COUNT++)) || true
                TOTAL_RECLAIMED_BYTES=$(( TOTAL_RECLAIMED_BYTES + file_size ))

                local formatted_size
                formatted_size="$(format_bytes "$file_size")"
                local age_days
                age_days=$(( (current_epoch - file_mtime) / 86400 ))

                if [[ "$DRY_RUN" = true ]]; then
                    printf "%b[DRY RUN]%b Would delete: %s (%s, %d days old)\n" "$COLOR_YELLOW" "$COLOR_RESET" "$file_path" "$formatted_size" "$age_days"
                    log_message "INFO" "[DRY RUN] Would delete: $file_path (Size: $formatted_size, Age: ${age_days}d)"
                    ((DELETED_COUNT++)) || true
                else
                    if rm -f "$file_path" 2>/dev/null; then
                        printf "%b✓ Deleted:%b %s (%s, %d days old)\n" "$COLOR_GREEN" "$COLOR_RESET" "$file_path" "$formatted_size" "$age_days"
                        log_message "INFO" "DELETED: $file_path (Size: $formatted_size, Age: ${age_days}d)"
                        ((DELETED_COUNT++)) || true
                    else
                        printf "%b✗ Failed to delete:%b %s\n" "$COLOR_RED" "$COLOR_RESET" "$file_path" >&2
                        log_message "ERROR" "FAILED to delete: $file_path"
                        ((FAILED_COUNT++)) || true
                    fi
                fi
            elif [[ "$VERBOSE" = true ]]; then
                printf "%b[SKIP - SIZE]%b %s is below minimum size threshold (%s < %s MB)\n" "$COLOR_CYAN" "$COLOR_RESET" "$file_path" "$(format_bytes "$file_size")" "$MIN_SIZE_MB"
            fi
        elif [[ "$VERBOSE" = true ]]; then
            local file_age
            file_age=$(( (current_epoch - file_mtime) / 86400 ))
            printf "%b[SKIP - AGE]%b %s is within retention period (%d days <= %d days)\n" "$COLOR_CYAN" "$COLOR_RESET" "$file_path" "$file_age" "$RETENTION_DAYS"
        fi
    done < <("${find_cmd[@]}" -print0 2>/dev/null)

    local total_space_formatted
    total_space_formatted="$(format_bytes "$TOTAL_RECLAIMED_BYTES")"

    printf "\n%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Total Files Scanned : %b%d%b\n" "$COLOR_BOLD" "$TOTAL_SCANNED" "$COLOR_RESET"
    printf "Eligible for Purge  : %b%d%b\n" "$COLOR_BOLD" "$ELIGIBLE_COUNT" "$COLOR_RESET"
    printf "Files Processed     : %b%d%b\n" "$COLOR_GREEN" "$DELETED_COUNT" "$COLOR_RESET"
    printf "Failed Deletions    : %b%d%b\n" "$COLOR_RED" "$FAILED_COUNT" "$COLOR_RESET"
    printf "Storage Reclaimed   : %b%b%s%b\n" "$COLOR_BOLD" "$COLOR_GREEN" "$total_space_formatted" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"

    log_message "INFO" "Cleanup completed: Scanned=$TOTAL_SCANNED, Eligible=$ELIGIBLE_COUNT, Processed=$DELETED_COUNT, Failed=$FAILED_COUNT, Reclaimed=$total_space_formatted"

    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        exit 2
    fi

    exit 0
}

main "$@"

#!/bin/bash
# ==============================================================================
# Script Name: kill_high_cpu.sh
# Description: Find and kill high-CPU processes.
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

# Resolve external helpers (avoid shell builtins like `kill`)
PS_CMD="$(type -P ps 2>/dev/null || echo ps)"
KILL_CMD="$(type -P kill 2>/dev/null || echo kill)"

# Default configuration
THRESHOLD="50.0"
AUTO_KILL=false
FORCE=false
DRY_RUN=false
AUDIT_LOG=""
VERBOSE=false

# Metrics / state
CANDIDATE_COUNT=0
KILLED_COUNT=0
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

is_number() {
    [[ "${1:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

show_help() {
    cat <<EOF
Find and Kill High-CPU Processes Utility (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -t, --threshold <n>   CPU % above which a process is a candidate (default: 50.0).
      --auto-kill        Kill all candidates without prompting.
      --force            Use SIGKILL instead of SIGTERM.
      --dry-run          Preview candidates, no signaling.
      --audit-log <file> Append ISO-8601 audit log entries.
  -v, --verbose         Enable diagnostic output.
  -h, --help            Show this help and usage documentation.

Examples:
  $0
  $0 -t 80 --auto-kill
  $0 --dry-run
  $0 -t 90 --auto-kill --force
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

is_guarded_pid() {
    local pid="$1"
    local comm="$2"
    if [[ "$pid" == "0" || "$pid" == "1" ]]; then
        return 0
    fi
    if [[ "$pid" == "$$" || "$pid" == "$PPID" ]]; then
        return 0
    fi
    # kernel threads: comm in brackets
    if [[ "$comm" == \[*\] ]]; then
        return 0
    fi
    return 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--threshold)
                require_value "$1" "$#"
                THRESHOLD="$2"
                shift 2
                ;;
            --auto-kill)
                AUTO_KILL=true
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

    if ! is_number "$THRESHOLD"; then
        printf "%bError: Threshold must be a non-negative number.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    # non-negative check
    if awk "BEGIN{exit !($THRESHOLD >= 0)}"; then
        :
    else
        printf "%bError: Threshold must be a non-negative number.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
}

# Candidate discovery: prints "PID PCPU COMM" lines
discover_candidates() {
    ${PS_CMD} -eo pid=,ppid=,pcpu=,comm= 2>/dev/null | while IFS=$' \t' read -r pid ppid pcpu comm; do
        [[ -z "$pid" ]] && continue
        # guardrails
        if is_guarded_pid "$pid" "$comm"; then
            continue
        fi
        # numeric pid check
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        # threshold compare
        if awk "BEGIN{exit !($pcpu > $THRESHOLD)}"; then
            printf "%s %s %s\n" "$pid" "$pcpu" "$comm"
        fi
    done
}

main() {
    parse_arguments "$@"

    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b            DevOps High-CPU Killer Utility                 %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Threshold        : %b%s%%%b\n" "$COLOR_CYAN" "$THRESHOLD" "$COLOR_RESET"
    printf "Auto-Kill        : %b%s%b\n" "$COLOR_CYAN" "$AUTO_KILL" "$COLOR_RESET"
    printf "Force (SIGKILL)  : %b%s%b\n" "$COLOR_CYAN" "$FORCE" "$COLOR_RESET"
    if [[ -n "$AUDIT_LOG" ]]; then
        printf "Audit Log        : %b%s%b\n" "$COLOR_CYAN" "$AUDIT_LOG" "$COLOR_RESET"
    fi
    printf "\n"

    # Discover candidates into a temp file
    local tmpfile
    tmpfile="$(mktemp)"
    discover_candidates > "$tmpfile"

    CANDIDATE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
    done < "$tmpfile"

    if [[ "$CANDIDATE_COUNT" -eq 0 ]]; then
        printf "%bNo processes exceeding %s%% CPU.%b\n" "$COLOR_GREEN" "$THRESHOLD" "$COLOR_RESET"
        log_message "INFO" "No high-CPU processes found (threshold=$THRESHOLD)."
        rm -f "$tmpfile"
        exit 0
    fi

    printf "%bFound %d candidate(s).%b\n\n" "$COLOR_YELLOW" "$CANDIDATE_COUNT" "$COLOR_RESET"

    # Dry-run
    if [[ "$DRY_RUN" == true ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            IFS=' ' read -r pid pcpu comm <<< "$line"
            printf "%b[DRY RUN]%b Would kill PID %s (%s) at %s%% CPU\n" \
                "$COLOR_YELLOW" "$COLOR_RESET" "$pid" "$comm" "$pcpu"
        done < "$tmpfile"
        log_message "INFO" "[DRY RUN] $CANDIDATE_COUNT candidate(s) (threshold=$THRESHOLD)."
        rm -f "$tmpfile"
        exit 0
    fi

    # Action
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS=' ' read -r pid pcpu comm <<< "$line"
        printf "%bHigh CPU detected:%b\n" "$COLOR_RED" "$COLOR_RESET"
        printf "  Command : %b%s%b\n" "$COLOR_YELLOW" "$comm" "$COLOR_RESET"
        printf "  PID     : %b%s%b\n" "$COLOR_CYAN" "$pid" "$COLOR_RESET"
        printf "  CPU     : %b%s%%%b\n" "$COLOR_RED" "$pcpu" "$COLOR_RESET"

        local do_kill=false
        if [[ "$AUTO_KILL" == true ]]; then
            do_kill=true
        else
            local choice
            printf "Kill this process? (y/n): "
            read -r choice || choice="n"
            case "$choice" in
                y|Y) do_kill=true ;;
                *) do_kill=false ;;
            esac
        fi

        if [[ "$do_kill" == true ]]; then
            local signal="TERM"
            [[ "$FORCE" == true ]] && signal="KILL"
            if [[ "$FORCE" == true ]]; then
                if ${KILL_CMD} -9 "$pid" 2>/dev/null; then
                    printf "%b✓ Process %s killed (SIGKILL).%b\n" "$COLOR_GREEN" "$pid" "$COLOR_RESET"
                    KILLED_COUNT=$((KILLED_COUNT + 1))
                    log_message "INFO" "Killed PID $pid ($comm) SIGKILL."
                else
                    printf "%b✗ Failed to kill process %s.%b\n" "$COLOR_RED" "$pid" "$COLOR_RESET" >&2
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    log_message "ERROR" "Failed to kill PID $pid ($comm)."
                fi
            else
                if ${KILL_CMD} -TERM "$pid" 2>/dev/null; then
                    sleep 0.5
                    if ! ${KILL_CMD} -0 "$pid" 2>/dev/null; then
                        printf "%b✓ Process %s killed (SIGTERM).%b\n" "$COLOR_GREEN" "$pid" "$COLOR_RESET"
                        KILLED_COUNT=$((KILLED_COUNT + 1))
                        log_message "INFO" "Killed PID $pid ($comm) SIGTERM."
                    else
                        printf "%b✗ Process %s still running after SIGTERM.%b\n" "$COLOR_RED" "$pid" "$COLOR_RESET" >&2
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                        log_message "ERROR" "PID $pid ($comm) still running after SIGTERM."
                    fi
                else
                    printf "%b✗ Failed to kill process %s.%b\n" "$COLOR_RED" "$pid" "$COLOR_RESET" >&2
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    log_message "ERROR" "Failed to kill PID $pid ($comm)."
                fi
            fi
        else
            printf "%bSkipped.%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
        fi
        printf "\n"
    done < "$tmpfile"

    rm -f "$tmpfile"

    # Summary
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Threshold        : %b%s%%%b\n" "$COLOR_BOLD" "$THRESHOLD" "$COLOR_RESET"
    printf "Candidates       : %b%d%b\n" "$COLOR_BOLD" "$CANDIDATE_COUNT" "$COLOR_RESET"
    printf "Killed           : %b%d%b\n" "$COLOR_GREEN" "$KILLED_COUNT" "$COLOR_RESET"
    printf "Failed           : %b%d%b\n" "$COLOR_RED" "$FAILED_COUNT" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"

    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        log_message "ERROR" "Completed with failures (killed=$KILLED_COUNT, failed=$FAILED_COUNT)."
        exit 2
    fi
    log_message "INFO" "Completed (killed=$KILLED_COUNT, candidates=$CANDIDATE_COUNT)."
    exit 0
}

main "$@"

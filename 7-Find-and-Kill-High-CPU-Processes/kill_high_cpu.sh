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
OUTPUT_MODE="human"
JSON_OUTPUT=false
CSV_OUTPUT=false
CAND_PIDS=()
CAND_PCPUS=()
CAND_COMMS=()
CAND_ACTIONS=()
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
      --json            Output result as JSON.
      --csv             Output result as CSV.
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
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --csv)
                CSV_OUTPUT=true
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
}

# Candidate discovery: prints "PID PCPU COMM" lines
discover_candidates() {
    ${PS_CMD} -eo pid=,ppid=,pcpu=,comm= 2>/dev/null | while IFS=$' \t' read -r pid _ pcpu comm; do
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

    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b            DevOps High-CPU Killer Utility                 %b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "Threshold        : %b%s%%%b\n" "$COLOR_CYAN" "$THRESHOLD" "$COLOR_RESET"
        printf "Auto-Kill        : %b%s%b\n" "$COLOR_CYAN" "$AUTO_KILL" "$COLOR_RESET"
        if [[ "$VERBOSE" == true ]]; then
            printf "%b[VERBOSE]%b threshold=%s auto_kill=%s force=%s dry_run=%s\n" "$COLOR_CYAN" "$COLOR_RESET" "$THRESHOLD" "$AUTO_KILL" "$FORCE" "$DRY_RUN"
        fi
        printf "Force (SIGKILL)  : %b%s%b\n" "$COLOR_CYAN" "$FORCE" "$COLOR_RESET"
        if [[ -n "$AUDIT_LOG" ]]; then
            printf "Audit Log        : %b%s%b\n" "$COLOR_CYAN" "$AUDIT_LOG" "$COLOR_RESET"
        fi
        printf "\n"
    fi

    # Discover candidates into a temp file
    local tmpfile
    tmpfile="$(mktemp)"
    discover_candidates > "$tmpfile"

    CANDIDATE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
        IFS=' ' read -r _pid _pcpu _comm <<< "$line"
        CAND_PIDS+=("$_pid")
        CAND_PCPUS+=("$_pcpu")
        CAND_COMMS+=("$_comm")
    done < "$tmpfile"

    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf "%bFound %d candidate(s).%b\n\n" "$COLOR_YELLOW" "$CANDIDATE_COUNT" "$COLOR_RESET"
    fi

    # Dry-run
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$CANDIDATE_COUNT" -eq 0 ]]; then
            if [[ "$OUTPUT_MODE" == "human" ]]; then
                printf "%b[DRY RUN]%b No candidates to kill.\n" "$COLOR_YELLOW" "$COLOR_RESET"
            fi
            log_message "INFO" "[DRY RUN] No candidates (threshold=$THRESHOLD)."
            if [[ "$OUTPUT_MODE" == "json" ]]; then
                printf '{\n  "threshold": %s,\n  "candidates": [],\n  "killed": 0,\n  "failed": 0,\n  "outcome": "dry-run"\n}\n' "$THRESHOLD"
            elif [[ "$OUTPUT_MODE" == "csv" ]]; then
                printf 'pid,pcpu,comm,action\n'
            fi
            rm -f "$tmpfile"
            exit 0
        fi
        if [[ "$OUTPUT_MODE" == "human" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                IFS=' ' read -r pid pcpu comm <<< "$line"
                printf "%b[DRY RUN]%b Would kill PID %s (%s) at %s%% CPU\n" \
                    "$COLOR_YELLOW" "$COLOR_RESET" "$pid" "$comm" "$pcpu"
            done < "$tmpfile"
        fi
        log_message "INFO" "[DRY RUN] $CANDIDATE_COUNT candidate(s) (threshold=$THRESHOLD)."
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            local cands=""
            local i
            for ((i=0; i<${#CAND_PIDS[@]}; i++)); do
                if [[ -n "$cands" ]]; then cands="${cands}, "; fi
                cands="${cands}{\"pid\": ${CAND_PIDS[$i]}, \"pcpu\": ${CAND_PCPUS[$i]}, \"comm\": \"${CAND_COMMS[$i]}\", \"action\": \"would-kill\"}"
            done
            printf '{\n  "threshold": %s,\n  "candidates": [%s],\n  "killed": 0,\n  "failed": 0,\n  "outcome": "dry-run"\n}\n' "$THRESHOLD" "$cands"
        elif [[ "$OUTPUT_MODE" == "csv" ]]; then
            printf 'pid,pcpu,comm,action\n'
            local i
            for ((i=0; i<${#CAND_PIDS[@]}; i++)); do
                printf '%s,%s,"%s","would-kill"\n' "${CAND_PIDS[$i]}" "${CAND_PCPUS[$i]}" "${CAND_COMMS[$i]}"
            done
        fi
        rm -f "$tmpfile"
        exit 0
    fi

    if [[ "$CANDIDATE_COUNT" -eq 0 ]]; then
        if [[ "$OUTPUT_MODE" == "human" ]]; then
            printf "%bNo processes exceeding %s%% CPU.%b\n" "$COLOR_GREEN" "$THRESHOLD" "$COLOR_RESET"
        fi
        log_message "INFO" "No high-CPU processes found (threshold=$THRESHOLD)."
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            printf '{\n  "threshold": %s,\n  "candidates": [],\n  "killed": 0,\n  "failed": 0,\n  "outcome": "none"\n}\n' "$THRESHOLD"
        elif [[ "$OUTPUT_MODE" == "csv" ]]; then
            printf 'pid,pcpu,comm,action\n'
        fi
        rm -f "$tmpfile"
        exit 0
    fi

    # Action
    local idx=0
    for ((idx=0; idx<CANDIDATE_COUNT; idx++)); do
        pid="${CAND_PIDS[$idx]}"
        pcpu="${CAND_PCPUS[$idx]}"
        comm="${CAND_COMMS[$idx]}"
        if [[ "$OUTPUT_MODE" == "human" ]]; then
            printf "%bHigh CPU detected:%b\n" "$COLOR_RED" "$COLOR_RESET"
            printf "  Command : %b%s%b\n" "$COLOR_YELLOW" "$comm" "$COLOR_RESET"
            printf "  PID     : %b%s%b\n" "$COLOR_CYAN" "$pid" "$COLOR_RESET"
            printf "  CPU     : %b%s%%%b\n" "$COLOR_RED" "$pcpu" "$COLOR_RESET"
        fi

        local do_kill=false
        if [[ "$AUTO_KILL" == true ]]; then
            do_kill=true
        else
            local choice="n"
            if [[ "$OUTPUT_MODE" == "human" ]]; then
                printf "Kill this process? (y/n): "
                read -r choice || choice="n"
            fi
            case "$choice" in
                y|Y) do_kill=true ;;
                *) do_kill=false ;;
            esac
        fi

        local action="skipped"
        if [[ "$do_kill" == true ]]; then
            if [[ "$FORCE" == true ]]; then
                if ${KILL_CMD} -9 "$pid" 2>/dev/null; then
                    if [[ "$OUTPUT_MODE" == "human" ]]; then
                        printf "%b✓ Process %s killed (SIGKILL).%b\n" "$COLOR_GREEN" "$pid" "$COLOR_RESET"
                    fi
                    KILLED_COUNT=$((KILLED_COUNT + 1))
                    action="killed"
                    log_message "INFO" "Killed PID $pid ($comm) SIGKILL."
                else
                    if [[ "$OUTPUT_MODE" == "human" ]]; then
                        printf "%b✗ Failed to kill process %s.%b\n" "$COLOR_RED" "$pid" "$COLOR_RESET" >&2
                    fi
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    action="failed"
                    log_message "ERROR" "Failed to kill PID $pid ($comm)."
                fi
            else
                if ${KILL_CMD} -TERM "$pid" 2>/dev/null; then
                    sleep 0.5
                    if ! ${KILL_CMD} -0 "$pid" 2>/dev/null; then
                        if [[ "$OUTPUT_MODE" == "human" ]]; then
                            printf "%b✓ Process %s killed (SIGTERM).%b\n" "$COLOR_GREEN" "$pid" "$COLOR_RESET"
                        fi
                        KILLED_COUNT=$((KILLED_COUNT + 1))
                        action="killed"
                        log_message "INFO" "Killed PID $pid ($comm) SIGTERM."
                    else
                        if [[ "$OUTPUT_MODE" == "human" ]]; then
                            printf "%b✗ Process %s still running after SIGTERM.%b\n" "$COLOR_RED" "$pid" "$COLOR_RESET" >&2
                        fi
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                        action="failed"
                        log_message "ERROR" "PID $pid ($comm) still running after SIGTERM."
                    fi
                else
                    if [[ "$OUTPUT_MODE" == "human" ]]; then
                        printf "%b✗ Failed to kill process %s.%b\n" "$COLOR_RED" "$pid" "$COLOR_RESET" >&2
                    fi
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    action="failed"
                    log_message "ERROR" "Failed to kill PID $pid ($comm)."
                fi
            fi
        else
            if [[ "$OUTPUT_MODE" == "human" ]]; then
                printf "%bSkipped.%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
            fi
        fi
        CAND_ACTIONS+=("$action")
        if [[ "$OUTPUT_MODE" == "human" ]]; then
            printf "\n"
        fi
    done

    rm -f "$tmpfile"

    # Summary
    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "Threshold        : %b%s%%%b\n" "$COLOR_BOLD" "$THRESHOLD" "$COLOR_RESET"
        printf "Candidates       : %b%d%b\n" "$COLOR_BOLD" "$CANDIDATE_COUNT" "$COLOR_RESET"
        printf "Killed           : %b%d%b\n" "$COLOR_GREEN" "$KILLED_COUNT" "$COLOR_RESET"
        printf "Failed           : %b%d%b\n" "$COLOR_RED" "$FAILED_COUNT" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    fi

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local cands=""
        local i
        for ((i=0; i<CANDIDATE_COUNT; i++)); do
            if [[ -n "$cands" ]]; then cands="${cands}, "; fi
            cands="${cands}{\"pid\": ${CAND_PIDS[$i]}, \"pcpu\": ${CAND_PCPUS[$i]}, \"comm\": \"${CAND_COMMS[$i]}\", \"action\": \"${CAND_ACTIONS[$i]}\"}"
        done
        local outcome="completed"
        if [[ "$FAILED_COUNT" -gt 0 ]]; then
            outcome="partial"
        fi
        printf '{\n  "threshold": %s,\n  "candidates": [%s],\n  "killed": %s,\n  "failed": %s,\n  "outcome": "%s"\n}\n' "$THRESHOLD" "$cands" "$KILLED_COUNT" "$FAILED_COUNT" "$outcome"
    elif [[ "$OUTPUT_MODE" == "csv" ]]; then
        printf 'pid,pcpu,comm,action\n'
        local i
        for ((i=0; i<CANDIDATE_COUNT; i++)); do
            printf '%s,%s,"%s","%s"\n' "${CAND_PIDS[$i]}" "${CAND_PCPUS[$i]}" "${CAND_COMMS[$i]}" "${CAND_ACTIONS[$i]}"
        done
    fi

    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        log_message "ERROR" "Completed with failures (killed=$KILLED_COUNT, failed=$FAILED_COUNT)."
        exit 2
    fi
    log_message "INFO" "Completed (killed=$KILLED_COUNT, candidates=$CANDIDATE_COUNT)."
    exit 0
}

main "$@"

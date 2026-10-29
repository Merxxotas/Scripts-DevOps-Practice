#!/usr/bin/env bash
#
# k8s_monitor.sh — Kubernetes Pod Monitor and Restart
#
# Lists pods matching a namespace and label selector and, when a pod's restart
# count exceeds a threshold, deletes it so the owning controller recreates it.
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Color constants
# ---------------------------------------------------------------------------
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RED='\033[31m'
readonly C_GREEN='\033[32m'
readonly C_YELLOW='\033[33m'
readonly C_BLUE='\033[34m'
readonly C_CYAN='\033[36m'

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_NAMESPACE="default"
DEFAULT_LABEL="app=web"
DEFAULT_THRESHOLD=3

NAMESPACE="$DEFAULT_NAMESPACE"
LABEL="$DEFAULT_LABEL"
THRESHOLD="$DEFAULT_THRESHOLD"
FORCE=false
DRY_RUN=false
AUDIT_LOG=""
VERBOSE=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '%b\n' "$*"; }
err() { printf '%b\n' "${C_RED}$*${C_RESET}" >&2; }
vlog() { if $VERBOSE; then printf '%b\n' "${C_DIM}$*${C_RESET}"; fi; }

usage() {
    cat <<'EOF'
Usage: k8s_monitor.sh [options]

Kubernetes Pod Monitor and Restart - monitor pods and restart (delete) those whose
restart count exceeds a threshold.

Options:
  -n, --namespace <NS>        Kubernetes namespace (default: default)
  -l, --label <SELECTOR>      Label selector (default: app=web)
  -r, --restart-threshold <N> Restart count above which a pod is deleted (default: 3)
      --force                 Hard delete (--grace-period=0 --force)
      --dry-run               List pods + which would be deleted, no deletion
      --audit-log <PATH>      Append an ISO-8601 audit line per run
  -v, --verbose               Diagnostic output
  -h, --help                  Show this help and exit

Exit codes:
  0  Success (including no pods / no deletions) or dry-run
  1  Configuration or safety violation (bad input, kubectl missing)
  2  Partial failure (a delete failed)
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--namespace)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                NAMESPACE="$2"; shift 2 ;;
            -l|--label)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                LABEL="$2"; shift 2 ;;
            -r|--restart-threshold)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                THRESHOLD="$2"; shift 2 ;;
            --force)
                FORCE=true; shift ;;
            --dry-run)
                DRY_RUN=true; shift ;;
            --audit-log)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                AUDIT_LOG="$2"; shift 2 ;;
            -v|--verbose)
                VERBOSE=true; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                err "Unknown option: $1"; usage >&2; exit 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
validate() {
    if [[ -z "$NAMESPACE" ]] || [[ ! "$NAMESPACE" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
        err "Invalid namespace: must be a non-empty DNS label"
        exit 1
    fi
    if [[ -z "$LABEL" ]]; then
        err "Invalid label selector: must be non-empty"
        exit 1
    fi
    if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]]; then
        err "Invalid restart threshold: must be a non-negative integer"
        exit 1
    fi
    if ! command -v kubectl >/dev/null 2>&1; then
        err "kubectl not found on PATH"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Audit log (best-effort)
# ---------------------------------------------------------------------------
write_audit() {
    local pods="$1" deleted="$2" outcome="$3"
    [[ -z "$AUDIT_LOG" ]] && return 0
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '%s namespace=%s label=%s threshold=%s pods=%s deleted=%s outcome=%s\n' \
        "$ts" "$NAMESPACE" "$LABEL" "$THRESHOLD" "$pods" "$deleted" "$outcome" \
        >>"$AUDIT_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Sum restarts (comma-separated list)
# ---------------------------------------------------------------------------
sum_restarts() {
    local list="$1" total=0 n
    IFS=',' read -ra parts <<<"$list"
    for n in "${parts[@]}"; do
        n="${n//[!0-9]/}"
        [[ -z "$n" ]] && n=0
        total=$((total + n))
    done
    printf '%d' "$total"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate

    log "${C_BOLD}${C_BLUE}=== Kubernetes Pod Monitor ===${C_RESET}"
    log "  ${C_DIM}Namespace:${C_RESET} ${C_CYAN}${NAMESPACE}${C_RESET}"
    log "  ${C_DIM}Selector:${C_RESET}  ${C_YELLOW}${LABEL}${C_RESET}"
    log "  ${C_DIM}Threshold:${C_RESET} ${C_YELLOW}${THRESHOLD}${C_RESET}"
    if $FORCE; then
        log "  ${C_DIM}Delete:${C_RESET}   ${C_RED}hard (--force)${C_RESET}"
    else
        log "  ${C_DIM}Delete:${C_RESET}   ${C_GREEN}graceful${C_RESET}"
    fi

    vlog "Querying pods..."
    local raw
    raw="$(kubectl get pods -n "$NAMESPACE" -l "$LABEL" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .status.containerStatuses[*]}{.restartCount}{","}{end}{"\n"}{end}' \
        2>/dev/null)" || raw=""
    vlog "raw: $raw"

    # Parse into arrays
    local -a names=() phases=() restarts=()
    local line name phase rlist rcount
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r name phase rlist <<<"$line"
        rcount="$(sum_restarts "${rlist:-0}")"
        names+=("$name")
        phases+=("$phase")
        restarts+=("$rcount")
    done <<<"$raw"

    local pod_count="${#names[@]}"
    log ""
    if [[ "$pod_count" -eq 0 ]]; then
        log "${C_YELLOW}No pods found matching criteria.${C_RESET}"
        write_audit "0" "0" "no-pods"
        exit 0
    fi
    log "${C_DIM}Found ${pod_count} pod(s).${C_RESET}"

    if $DRY_RUN; then
        log ""
        log "${C_BOLD}Dry run — no deletions.${C_RESET}"
        local i
        for ((i=0; i<pod_count; i++)); do
            log "  ${C_CYAN}${names[$i]}${C_RESET}  phase=${phases[$i]}  restarts=${restarts[$i]}"
            if (( restarts[i] > THRESHOLD )); then
                log "    ${C_RED}-> would delete${C_RESET}"
            else
                log "    ${C_GREEN}-> keep${C_RESET}"
            fi
        done
        write_audit "$pod_count" "0" "dry-run"
        exit 0
    fi

    # Act
    local deleted=0 failed=0 i
    log ""
    log "${C_BOLD}Result${C_RESET}"
    for ((i=0; i<pod_count; i++)); do
        log "  ${C_CYAN}${names[$i]}${C_RESET}"
        log "    ${C_DIM}Phase:${C_RESET}    ${phases[$i]}"
        log "    ${C_DIM}Restarts:${C_RESET} ${restarts[$i]}"
        if (( restarts[i] > THRESHOLD )); then
            vlog "Deleting ${names[$i]}..."
            local del_ok=false
            if $FORCE; then
                if kubectl delete pod "${names[$i]}" -n "$NAMESPACE" --grace-period=0 --force >/dev/null 2>&1; then
                    del_ok=true
                fi
            else
                if kubectl delete pod "${names[$i]}" -n "$NAMESPACE" >/dev/null 2>&1; then
                    del_ok=true
                fi
            fi
            if $del_ok; then
                log "    ${C_RED}-> deleted${C_RESET}"
                deleted=$((deleted + 1))
            else
                log "    ${C_RED}-> delete FAILED${C_RESET}"
                failed=$((failed + 1))
            fi
        else
            log "    ${C_GREEN}-> kept (below threshold)${C_RESET}"
        fi
    done

    log ""
    log "${C_DIM}Pods: ${pod_count}  Deleted: ${deleted}  Failed: ${failed}${C_RESET}"

    local outcome exit_code
    if [[ "$failed" -gt 0 ]]; then
        outcome="partial-failure"; exit_code=2
        log "${C_RED}Partial failure.${C_RESET}"
    else
        outcome="success"; exit_code=0
        log "${C_GREEN}Monitoring check completed.${C_RESET}"
    fi

    write_audit "$pod_count" "$deleted" "$outcome"
    exit "$exit_code"
}

main "$@"

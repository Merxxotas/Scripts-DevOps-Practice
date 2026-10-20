#!/usr/bin/env bash
#
# Cross-Platform System Resource Monitor - Sorted by RAM with Summary
# Supports: Linux (GNU), Alpine Linux (BusyBox), macOS (BSD)
# Version: 1.1.0
#
# Usage: 
#   ./system_monitor.sh --export ./myfile.json
#   ./system_monitor.sh --export "/path/to/logs/"  (auto-generates filename)
#   ./system_monitor.sh --watch --export "/path/to/logs/" --json
#

# ============================================================================
# STRICT MODE - Catch errors early
# ============================================================================
set -euo pipefail
IFS=$'\n\t'

# Error handler
cleanup_on_error() {
    local line=$1
    local status=$2
    echo -e "${RED}ÃƒÂ¢Ã…â€œÃ¢â‚¬â€ Error on line ${line}: Command exited with status ${status}${NC}" >&2
    exit 1
}
trap 'cleanup_on_error ${LINENO} $?' ERR

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly VERSION="1.3.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Color codes
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[37m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Thresholds and limits
TOP_PROCESSES=100
CPU_THRESHOLD=80
MEM_THRESHOLD=80

# OS Detection
OS=$(uname -s)

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================
LOG_LEVEL="${LOG_LEVEL:-INFO}"
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    if [[ ${LOG_LEVELS[$level]:-1} -ge ${LOG_LEVELS[$LOG_LEVEL]:-1} ]]; then
        echo -e "[$timestamp] [$level] $msg" >&2
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Safe calculation using awk (no external bc dependency)
calc() {
    awk "BEGIN {printf \"%.2f\", $1}"
}

# Compare two numbers - returns 0 (true) if $1 > $2
greater_than() {
    awk "BEGIN {exit !($1 > $2)}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate numeric input
validate_positive_number() {
    local value="$1"
    local name="$2"
    if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log ERROR "Invalid $name: '$value' (must be a positive number)"
        exit 1
    fi
}

# Validate integer range
validate_int_range() {
    local value="$1"
    local name="$2"
    local min="${3:-1}"
    local max="${4:-9999}"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt "$min" ]] || [[ "$value" -gt "$max" ]]; then
        log ERROR "Invalid $name: '$value' (must be integer between $min and $max)"
        exit 1
    fi
}

get_cpu_usage() {
    case "$OS" in
        Linux)
            if [[ -f /proc/stat ]]; then
                local stat_line=$(grep '^cpu ' /proc/stat)
                local user=$(echo $stat_line | awk '{print $2}')
                local nice=$(echo $stat_line | awk '{print $3}')
                local system=$(echo $stat_line | awk '{print $4}')
                local idle=$(echo $stat_line | awk '{print $5}')
                local iowait=$(echo $stat_line | awk '{print $6}')
                local total=$((user + nice + system + idle + iowait))
                if [[ $total -gt 0 ]]; then
                    calc "100 * ($total - $idle - $iowait) / $total"
                    return
                fi
            fi
            local top_output=$(top -bn1 2>/dev/null | grep -E "^%?Cpu")
            if [[ -n "$top_output" ]]; then
                local idle=$(echo "$top_output" | sed -n 's/.*, *\([0-9.]*\)%* id.*/\1/p')
                if [[ -n "$idle" ]]; then
                    calc "100 - $idle"
                    return
                fi
            fi
            ;;
        Darwin)
            local top_output=$(top -l1 2>/dev/null | grep "CPU usage")
            if [[ -n "$top_output" ]]; then
                local idle=$(echo "$top_output" | sed -n 's/.*, *\([0-9.]*\)%* idle.*/\1/p')
                if [[ -n "$idle" ]]; then
                    calc "100 - $idle"
                    return
                fi
            fi
            ;;
    esac
    echo "N/A"
}

get_memory_usage() {
    case "$OS" in
        Linux)
            if command -v free &> /dev/null; then
                free | awk '/Mem:/ {printf "%.2f", $3/$2 * 100.0}'
                return
            fi
            if [[ -f /proc/meminfo ]]; then
                awk '/MemTotal/{t=$2}/MemAvailable/{a=$2} END {printf "%.2f", (t-a)/t * 100}' /proc/meminfo
                return
            fi
            ;;
        Darwin)
            local vm_stats=$(vm_stat 2>/dev/null)
            if [[ -n "$vm_stats" ]]; then
                local pages_free=$(echo "$vm_stats" | grep "Pages free" | awk '{gsub(/\./,""); print $3}')
                local pages_active=$(echo "$vm_stats" | grep "Pages active" | awk '{gsub(/\./,""); print $3}')
                local pages_inactive=$(echo "$vm_stats" | grep "Pages inactive" | awk '{gsub(/\./,""); print $3}')
                local pages_wired=$(echo "$vm_stats" | grep "Pages wired down" | awk '{gsub(/\./,""); print $4}')
                local pages_speculative=$(echo "$vm_stats" | grep "Pages speculative" | awk '{gsub(/\./,""); print $3}')
                pages_speculative=${pages_speculative:-0}
                local used=$((pages_active + pages_inactive + pages_speculative + pages_wired))
                local total=$((used + pages_free))
                if [[ $total -gt 0 ]]; then
                    calc "$used * 100 / $total"
                    return
                fi
            fi
            ;;
    esac
    echo "N/A"
}

# ============================================================================
# DISK AND STORAGE FUNCTIONS
# ============================================================================

# Disk usage thresholds
DISK_THRESHOLD_WARNING=70
DISK_THRESHOLD_CRITICAL=90

get_disk_usage() {
    # Returns: mount_point|total_gb|used_gb|free_gb|percent_used
    case "$OS" in
        Linux|Darwin)
            if command_exists df; then
                df -h 2>/dev/null | grep -E '^/dev/' | awk '{
                    gsub(/%/, "", $5)
                    print $6 "|" $2 "|" $3 "|" $4 "|" $5
                }'
            fi
            ;;
    esac
}

get_disk_usage_json() {
    # Returns JSON array of disk info
    local first=1
    get_disk_usage | while IFS='|' read -r mount total used free percent; do
        [[ -z "$mount" ]] && continue
        [[ $first -eq 0 ]] && echo ","
        first=0
        printf '    {"mount_point": "%s", "total": "%s", "used": "%s", "free": "%s", "percent_used": %s}' \
            "$mount" "$total" "$used" "$free" "$percent"
    done
}

get_disk_io_stats() {
    # Linux only - reads /proc/diskstats
    # Returns: device|reads_completed|writes_completed|read_sectors|write_sectors
    if [[ -f /proc/diskstats ]]; then
        grep -E '\b(sda|nvme0n1|vda|xvda|hda)\b' /proc/diskstats 2>/dev/null | awk '{
            device = $3
            reads = $6
            writes = $10
            read_sectors = $7
            write_sectors = $11
            print device "|" reads "|" writes "|" read_sectors "|" write_sectors
        }'
    fi
}

get_disk_io_json() {
    # Returns JSON array of disk I/O info
    local first=1
    get_disk_io_stats | while IFS='|' read -r device reads writes read_sectors write_sectors; do
        [[ -z "$device" ]] && continue
        [[ $first -eq 0 ]] && echo ","
        first=0
        printf '    {"device": "%s", "reads_completed": %s, "writes_completed": %s, "read_sectors": %s, "write_sectors": %s}' \
            "$device" "$reads" "$writes" "$read_sectors" "$write_sectors"
    done
}

show_disk_section() {
    # Show disk usage with color coding
    echo -e "\n${YELLOW}Disk Usage:${NC}"
    
    local has_disks=0
    get_disk_usage | while IFS='|' read -r mount total used free percent; do
        [[ -z "$mount" ]] && continue
        has_disks=1
        
        # Determine color based on usage
        local color="$GREEN"
        if [[ "$percent" -gt "$DISK_THRESHOLD_CRITICAL" ]]; then
            color="$RED"
        elif [[ "$percent" -gt "$DISK_THRESHOLD_WARNING" ]]; then
            color="$YELLOW"
        fi
        
        printf "${color}%-15s %8s used / %8s total (%3s%%)${NC}\n" "$mount" "$used" "$total" "$percent"
    done
    
    # Show I/O stats if available (Linux only)
    if [[ -f /proc/diskstats ]]; then
        echo -e "\n${YELLOW}Disk I/O Statistics:${NC}"
        get_disk_io_stats | while IFS='|' read -r device reads writes read_sectors write_sectors; do
            [[ -z "$device" ]] && continue
            printf "${CYAN}%-10s${NC} Reads: %10s  Writes: %10s  (Sectors - Read: %12s, Write: %12s)\n" \
                "$device" "$reads" "$writes" "$read_sectors" "$write_sectors"
        done
    fi
}

# ============================================================================
# PROCESS KILL/RESTART FUNCTIONS
# ============================================================================

# Log file for kill/restart actions
readonly KILL_LOG_DIR="${KILL_LOG_DIR:-/tmp}"
readonly KILL_LOG_FILE="$KILL_LOG_DIR/system_monitor_kill.log"

# Initialize kill log
init_kill_log() {
    if [[ ! -f "$KILL_LOG_FILE" ]]; then
        touch "$KILL_LOG_FILE" 2>/dev/null || log WARN "Cannot create kill log at $KILL_LOG_FILE"
    fi
}

# Log kill/restart action
log_kill_action() {
    local action="$1"
    local target="$2"
    local result="$3"
    local details="${4:-}"
    local timestamp
    timestamp=$(date -Iseconds)
    echo "[$timestamp] [$action] PID/Name: $target | Result: $result | $details" >> "$KILL_LOG_FILE" 2>/dev/null
}

# Kill process by PID
kill_process_by_pid() {
    local pid="$1"
    local signal="${2:-TERM}"  # Default to SIGTERM (graceful)
    
    # Validate PID is numeric
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        log ERROR "Invalid PID: '$pid' (must be numeric)"
        return 1
    fi
    
    # Check if process exists
    if ! kill -0 "$pid" 2>/dev/null; then
        log ERROR "Process $pid does not exist or cannot be signaled"
        return 1
    fi
    
    # Get process info before killing
    local proc_info
    proc_info=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
    
    log INFO "Sending SIG$signal to process $pid ($proc_info)..."
    
    if kill -"$signal" "$pid" 2>/dev/null; then
        # Wait a moment and check if process is gone
        sleep 0.5
        if ! kill -0 "$pid" 2>/dev/null; then
            log_kill_action "KILL" "$pid" "SUCCESS" "Process: $proc_info, Signal: SIG$signal"
            log INFO "âœ“ Process $pid ($proc_info) terminated successfully"
            return 0
        else
            # Process still running, try SIGKILL
            log WARN "Process $pid still running, trying SIGKILL..."
            if kill -9 "$pid" 2>/dev/null; then
                log_kill_action "KILL" "$pid" "SUCCESS" "Process: $proc_info, Signal: SIGKILL (forced)"
                log INFO "âœ“ Process $pid ($proc_info) killed forcefully"
                return 0
            fi
        fi
    fi
    
    log_kill_action "KILL" "$pid" "FAILED" "Process: $proc_info"
    log ERROR "âœ— Failed to kill process $pid"
    return 1
}

# Kill process by name
kill_process_by_name() {
    local name="$1"
    local signal="${2:-TERM}"
    local killed=0
    
    # Find PIDs matching the name
    local pids
    pids=$(pgrep -x "$name" 2>/dev/null || pgrep "$name" 2>/dev/null)
    
    if [[ -z "$pids" ]]; then
        log ERROR "No processes found matching: '$name'"
        return 1
    fi
    
    log INFO "Found processes matching '$name':"
    echo "$pids" | while read -r pid; do
        ps -p "$pid" -o pid,comm,pcpu,pmem 2>/dev/null | tail -1
    done
    
    # Kill each matching process
    echo "$pids" | while read -r pid; do
        kill_process_by_pid "$pid" "$signal"
        ((killed++))
    done
    
    return 0
}

# Restart process (kill then restart)
restart_process() {
    local target="$1"  # Can be PID or name
    local restart_cmd="$2"  # Command to restart (optional)
    
    # Determine if target is PID or name
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # It's a PID, get the command before killing
        local proc_cmd
        proc_cmd=$(ps -p "$target" -o cmd= 2>/dev/null)
        local proc_name
        proc_name=$(ps -p "$target" -o comm= 2>/dev/null)
        
        if [[ -z "$proc_cmd" ]]; then
            log ERROR "Process $target not found"
            return 1
        fi
        
        # Kill the process
        if kill_process_by_pid "$target"; then
            # Restart
            if [[ -n "$restart_cmd" ]]; then
                log INFO "Restarting with command: $restart_cmd"
                nohup bash -c "$restart_cmd" >/dev/null 2>&1 &
                local new_pid=$!
                log_kill_action "RESTART" "$target" "SUCCESS" "New PID: $new_pid, Command: $restart_cmd"
                log INFO "âœ“ Process restarted with new PID: $new_pid"
            elif [[ -n "$proc_cmd" ]]; then
                log INFO "Restarting with original command: $proc_cmd"
                nohup bash -c "$proc_cmd" >/dev/null 2>&1 &
                local new_pid=$!
                log_kill_action "RESTART" "$target" "SUCCESS" "New PID: $new_pid, Original: $proc_name"
                log INFO "âœ“ Process restarted with new PID: $new_pid"
            fi
            return 0
        fi
    else
        # It's a process name
        log INFO "Restarting process by name: $target"
        
        # Get the command line of the first matching process
        local pid
        pid=$(pgrep -x "$target" | head -1)
        if [[ -n "$pid" ]]; then
            local proc_cmd
            proc_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null)
            
            # Kill all matching processes
            kill_process_by_name "$target"
            
            # Restart
            if [[ -n "$restart_cmd" ]]; then
                log INFO "Restarting with command: $restart_cmd"
                nohup bash -c "$restart_cmd" >/dev/null 2>&1 &
                local new_pid=$!
                log_kill_action "RESTART" "$target" "SUCCESS" "New PID: $new_pid"
                log INFO "âœ“ Process restarted with new PID: $new_pid"
            elif [[ -n "$proc_cmd" ]]; then
                log INFO "Restarting with captured command"
                nohup bash -c "$proc_cmd" >/dev/null 2>&1 &
                local new_pid=$!
                log_kill_action "RESTART" "$target" "SUCCESS" "New PID: $new_pid"
                log INFO "âœ“ Process restarted with new PID: $new_pid"
            fi
            return 0
        else
            log ERROR "No process found with name: $target"
            return 1
        fi
    fi
    
    return 1
}

# Show kill log
show_kill_log() {
    if [[ -f "$KILL_LOG_FILE" ]]; then
        echo -e "\n${YELLOW}Recent Kill/Restart Actions:${NC}"
        tail -10 "$KILL_LOG_FILE" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    else
        log WARN "No kill log found at $KILL_LOG_FILE"
    fi
}

get_process_data() {
    ps aux 2>/dev/null | grep -v '^USER' | sort -k6,6nr | head -n $TOP_PROCESSES | awk '{
        proc = $11
        gsub(/^.+\//, "", proc)
        printf "%s|%s|%s|%s\n", proc, $2, $3, $6
    }'
}

get_aggregated_data() {
    ps -eo comm,rss 2>/dev/null | tail -n +2 | awk '
    {
        proc = $1
        gsub(/^.+\//, "", proc)
        total_rss[proc] += $2
        count[proc]++
    }
    END {
        for (proc in total_rss) {
            printf "%s|%.2f|%d\n", proc, total_rss[proc]/1024, count[proc]
        }
    }' | sort -t'|' -k2,2nr
}

output_json() {
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    local timestamp=$(date -Iseconds)
    
    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"os\": \"$OS\","
    echo "  \"cpu_percent\": $cpu,"
    echo "  \"memory_percent\": $mem,"
    echo "  \"disk_usage\": ["
    get_disk_usage_json
    echo ""
    echo "  ],"
    echo "  \"disk_io\": ["
    get_disk_io_json
    echo ""
    echo "  ],"
    echo "  \"top_processes\": ["
    
    local first=1
    get_process_data | while IFS='|' read -r name pid cpu_pct rss; do
        [[ -z "$name" ]] && continue
        rss_mb=$((rss / 1024))
        [[ $first -eq 0 ]] && echo ","
        first=0
        printf "    {\"name\": \"%s\", \"pid\": %s, \"cpu_percent\": %s, \"ram_mb\": %s}" "$name" "$pid" "$cpu_pct" "$rss_mb"
    done
    echo ""
    echo "  ],"
    echo "  \"aggregated_totals\": ["
    
    first=1
    get_aggregated_data | while IFS='|' read -r name total_ram count; do
        [[ -z "$name" ]] && continue
        [[ $first -eq 0 ]] && echo ","
        first=0
        printf "    {\"name\": \"%s\", \"total_ram_mb\": %.2f, \"instances\": %s}" "$name" "$total_ram" "$count"
    done
    echo ""
    echo "  ]"
    echo "}"
}

output_csv() {
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    local timestamp=$(date -Iseconds)
    
    echo "timestamp,os,metric_type,name,pid,cpu_percent,ram_mb,instances,mount_point,device,percent_used"
    
    echo "$timestamp,$OS,system,system,,cpu,$cpu,,,,,"
    echo "$timestamp,$OS,system,system,,memory,$mem,,,,,"
    
    # Add disk usage rows
    get_disk_usage | while IFS='|' read -r mount total used free percent; do
        [[ -z "$mount" ]] && continue
        echo "$timestamp,$OS,disk_usage,disk,,,,,$mount,,$percent"
    done
    
    # Add disk I/O rows (Linux only)
    get_disk_io_stats | while IFS='|' read -r device reads writes read_sectors write_sectors; do
        [[ -z "$device" ]] && continue
        echo "$timestamp,$OS,disk_io,$device,,,,,,$device,"
    done
    
    get_process_data | while IFS='|' read -r name pid cpu_pct rss; do
        [[ -z "$name" ]] && continue
        rss_mb=$((rss / 1024))
        echo "$timestamp,$OS,process,$name,$pid,$cpu_pct,$rss_mb,1,,,"
    done
    
    get_aggregated_data | while IFS='|' read -r name total_ram count; do
        [[ -z "$name" ]] && continue
        echo "$timestamp,$OS,aggregate,$name,0,0,${count},,,,"
    done
}

show_monitor() {
    echo -e "${BLUE}=== System Resource Monitor ===${NC}"
    echo -e "${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${YELLOW}OS: $OS${NC}\n"

    CPU_USAGE=$(get_cpu_usage)
    MEM_USAGE=$(get_memory_usage)

    echo -e "CPU Usage: \c"
    if [[ "$CPU_USAGE" == "N/A" ]]; then
        echo -e "${YELLOW}Unable to detect${NC}"
    elif greater_than "$CPU_USAGE" "$CPU_THRESHOLD"; then
        echo -e "${RED}${CPU_USAGE}% (HIGH)${NC}"
    else
        echo -e "${GREEN}${CPU_USAGE}%${NC}"
    fi

    echo -e "Memory Usage: \c"
    if [[ "$MEM_USAGE" == "N/A" ]]; then
        echo -e "${YELLOW}Unable to detect${NC}"
    elif greater_than "$MEM_USAGE" "$MEM_THRESHOLD"; then
        echo -e "${RED}${MEM_USAGE}% (HIGH)${NC}"
    else
        echo -e "${GREEN}${MEM_USAGE}%${NC}"
    fi
    
    # Show disk section
    show_disk_section

    echo -e "\n${YELLOW}Top $TOP_PROCESSES Processes (Sorted by RAM Usage):${NC}"
    printf "${CYAN}%-22s %-10s %-12s %-12s${NC}\n" "PROCESS" "PID" "CPU(%)" "RAM(MB)"
    printf "${CYAN}%s${NC}\n" "------------------------------------------------------"

    get_process_data | while IFS='|' read -r proc_name pid cpu rss; do
        [[ -z "$pid" ]] && continue
        
        rss_mb=$((rss / 1024))
        proc_name=$(printf "%-22s" "${proc_name:0:22}")
        pid_str=$(printf "%-10s" "$pid")
        cpu_str=$(printf "%-12s" "${cpu}%")
        mem_str=$(printf "%-12s" "${rss_mb}MB")
        
        if [[ $rss_mb -gt 500 ]]; then
            echo -e "${RED}$proc_name $pid_str $cpu_str $mem_str${NC}"
        else
            echo -e "$proc_name $pid_str $cpu_str $mem_str"
        fi
    done

    echo -e "\n${YELLOW}Total Usage by Process (Aggregated RAM):${NC}"
    printf "${CYAN}%s${NC}\n" "----------------------------------------"

    temp_file=$(mktemp)
    get_aggregated_data > "$temp_file"

    max_ram=$(head -1 "$temp_file" | cut -d'|' -f2)
    
    while IFS='|' read -r proc ram inst_count; do
        [[ -z "$proc" ]] && continue
        
        # Use awk for float comparison (avoids bc dependency)
        if [[ "$ram" == "$max_ram" ]] || awk "BEGIN {exit !($ram >= $max_ram * 0.9)}"; then
            color="$RED"
        elif awk "BEGIN {exit !($ram > $max_ram * 0.6)}"; then
            color="$YELLOW"
        elif awk "BEGIN {exit !($ram > $max_ram * 0.3)}"; then
            color="$GREEN"
        elif awk "BEGIN {exit !($ram > $max_ram * 0.1)}"; then
            color="$CYAN"
        else
            color="$WHITE"
        fi
        
        echo -e "${color}$proc${NC}: ${ram}MB ($inst_count instances)"
    done < "$temp_file"

    rm -f "$temp_file"
}

# Generate timestamped filename
generate_filename() {
    local ext=$1
    echo "system_monitor_$(date +%Y%m%d_%H%M%S).$ext"
}

# Main argument parsing
WATCH_MODE=0
INTERVAL=2
EXPORT_PATH=""
OUTPUT_FORMAT="display"
KILL_TARGET=""
KILL_SIGNAL="TERM"
RESTART_TARGET=""
RESTART_CMD=""
SHOW_KILL_LOG=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --watch|-w)
            WATCH_MODE=1
            if [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                INTERVAL="$2"
                # Validate interval range (0.1s to 300s)
                if awk "BEGIN {exit !($INTERVAL < 0.1)}"; then
                    log ERROR "Interval must be at least 0.1 seconds"
                    exit 1
                fi
                if awk "BEGIN {exit !($INTERVAL > 300)}"; then
                    log ERROR "Interval must be at most 300 seconds (5 minutes)"
                    exit 1
                fi
                shift
            fi
            ;;
        --json|-j)
            OUTPUT_FORMAT="json"
            ;;
        --csv|-c)
            OUTPUT_FORMAT="csv"
            ;;
        --export|-e)
            if [[ -n "$2" ]]; then
                EXPORT_PATH="$2"
                shift
            else
                echo "Error: --export requires a path argument" >&2
                exit 1
            fi
            ;;
        --kill|-k)
            if [[ -n "$2" ]]; then
                KILL_TARGET="$2"
                shift
            else
                echo "Error: --kill requires a PID or process name" >&2
                exit 1
            fi
            ;;
        --kill-signal|-s)
            if [[ -n "$2" ]]; then
                KILL_SIGNAL="$2"
                shift
            else
                echo "Error: --kill-signal requires a signal name" >&2
                exit 1
            fi
            ;;
        --restart|-r)
            if [[ -n "$2" ]]; then
                RESTART_TARGET="$2"
                shift
            else
                echo "Error: --restart requires a PID or process name" >&2
                exit 1
            fi
            ;;
        --restart-cmd)
            if [[ -n "$2" ]]; then
                RESTART_CMD="$2"
                shift
            else
                echo "Error: --restart-cmd requires a command string" >&2
                exit 1
            fi
            ;;
        --kill-log)
            SHOW_KILL_LOG=1
            ;;
        --version|-v)
            echo "System Resource Monitor v$VERSION"
            echo "OS: $OS"
            exit 0
            ;;
        --help|-h)
            cat << EOF
System Resource Monitor v$VERSION
Usage: $SCRIPT_NAME [OPTIONS]

Display Options:
  -w, --watch [seconds]  Enable watch mode (default: 2s, range: 0.1-300)
  -j, --json             Output JSON to stdout
  -c, --csv              Output CSV to stdout
  -h, --help             Display this help and exit
  -v, --version          Display version information and exit

Process Management Options:
  -k, --kill <pid|name>  Kill process by PID or name
  -s, --kill-signal <sig> Signal to use (TERM, KILL, HUP, default: TERM)
  -r, --restart <pid|name> Restart process by PID or name
      --restart-cmd <cmd> Command to use for restart (optional)
      --kill-log           Show recent kill/restart actions

Export Options:
  -e, --export <path>    Export to file (path can be file or directory)
                         If directory: auto-generates filename with timestamp
                         If no --json/--csv specified, format detected from extension

Environment Variables:
  LOG_LEVEL              Set logging level (DEBUG, INFO, WARN, ERROR)
                         Default: INFO
  KILL_LOG_DIR           Directory for kill/restart log
                         Default: /tmp

Examples:
  $SCRIPT_NAME                              # Standard display mode
  $SCRIPT_NAME --export ./report.json       # Export JSON to file
  $SCRIPT_NAME --export /logs/ --csv        # Export CSV to directory
  $SCRIPT_NAME --watch 5 --export ./logs/   # Continuous monitoring
  $SCRIPT_NAME --kill 1234                  # Kill process PID 1234
  $SCRIPT_NAME --kill firefox --kill-signal TERM
  $SCRIPT_NAME --restart 1234               # Restart process PID 1234
  $SCRIPT_NAME --restart nginx --restart-cmd "nginx -c /etc/nginx.conf"

Exit Codes:
  0                      Success
  1                      Error (invalid arguments, system error)
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Initialize kill log
init_kill_log

# Handle kill/restart operations (executed before monitoring)
if [[ $SHOW_KILL_LOG -eq 1 ]]; then
    show_kill_log
    exit 0
fi

if [[ -n "$RESTART_TARGET" ]]; then
    restart_process "$RESTART_TARGET" "$RESTART_CMD"
    exit $?
fi

if [[ -n "$KILL_TARGET" ]]; then
    if [[ "$KILL_TARGET" =~ ^[0-9]+$ ]]; then
        kill_process_by_pid "$KILL_TARGET" "$KILL_SIGNAL"
    else
        kill_process_by_name "$KILL_TARGET" "$KILL_SIGNAL"
    fi
    exit $?
fi

# Handle export path logic
if [[ -n "$EXPORT_PATH" ]]; then
    # Check if it's a directory
    if [[ -d "$EXPORT_PATH" ]]; then
        # Generate filename based on format
        if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
            filename=$(generate_filename "csv")
        else
            filename=$(generate_filename "json")
        fi
        EXPORT_PATH="${EXPORT_PATH%/}/$filename"
        echo -e "${CYAN}Export directory provided. Will save as: $EXPORT_PATH${NC}"
    fi
    
    # Auto-detect format from extension if not explicitly specified
    if [[ "$OUTPUT_FORMAT" == "display" ]]; then
        if [[ "$EXPORT_PATH" == *.csv ]]; then
            OUTPUT_FORMAT="csv"
        elif [[ "$EXPORT_PATH" == *.json ]]; then
            OUTPUT_FORMAT="json"
        else
            # Default to json if no extension hint
            OUTPUT_FORMAT="json"
            EXPORT_PATH="${EXPORT_PATH}.json"
        fi
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$EXPORT_PATH")"
fi

# Execution logic
if [[ "$OUTPUT_FORMAT" == "json" ]] && [[ $WATCH_MODE -eq 0 ]]; then
    if [[ -n "$EXPORT_PATH" ]]; then
        output_json > "$EXPORT_PATH"
        echo -e "${GREEN}ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Exported JSON to: $EXPORT_PATH${NC}"
    else
        output_json
    fi
    exit 0
fi

if [[ "$OUTPUT_FORMAT" == "csv" ]] && [[ $WATCH_MODE -eq 0 ]]; then
    if [[ -n "$EXPORT_PATH" ]]; then
        output_csv > "$EXPORT_PATH"
        echo -e "${GREEN}ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Exported CSV to: $EXPORT_PATH${NC}"
    else
        output_csv
    fi
    exit 0
fi

# Watch mode cleanup handler
cleanup_watch() {
    echo -e "\n${GREEN}Watch mode stopped.${NC}"
    # Close JSON array if needed
    if [[ -n "${EXPORT_PATH:-}" ]] && [[ "$OUTPUT_FORMAT" == "json" ]] && [[ -f "$EXPORT_PATH" ]]; then
        echo "]" >> "$EXPORT_PATH"
        echo -e "${CYAN}JSON array closed in: $EXPORT_PATH${NC}"
    fi
    exit 0
}

if [[ $WATCH_MODE -eq 1 ]]; then
    trap cleanup_watch INT TERM
    
    echo -e "${GREEN}Starting watch mode (refresh every ${INTERVAL}s).${NC}"
    [[ -n "$EXPORT_PATH" ]] && echo -e "${CYAN}Logging to: $EXPORT_PATH${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit.${NC}\n"
    sleep 1
    
    # Initialize JSON array file if exporting JSON
    if [[ -n "$EXPORT_PATH" ]] && [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "[" > "$EXPORT_PATH"
    fi
    
    first_run=true
    
    while true; do
        clear
        show_monitor
        
        if [[ -n "$EXPORT_PATH" ]]; then
            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                # Append with comma for JSON array
                [[ "$first_run" == "false" ]] && echo "," >> "$EXPORT_PATH"
                output_json >> "$EXPORT_PATH"
            else
                # CSV append
                if [[ "$first_run" == "true" ]]; then
                    output_csv > "$EXPORT_PATH"
                else
                    output_csv | tail -n +2 >> "$EXPORT_PATH"
                fi
            fi
            echo -e "\n${CYAN}[Logged to: $(basename "$EXPORT_PATH")]${NC}"
        fi
        
        first_run=false
        
        echo -e "\n${CYAN}Last update: $(date '+%H:%M:%S') | Next refresh in ${INTERVAL}s${NC} ${YELLOW}(Ctrl+C to quit)${NC}"
        sleep "$INTERVAL"
    done
else
    show_monitor
    if [[ -n "$EXPORT_PATH" ]]; then
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            output_json > "$EXPORT_PATH"
        else
            output_csv > "$EXPORT_PATH"
        fi
        echo -e "\n${GREEN}ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Exported to: $EXPORT_PATH${NC}"
    fi
fi

exit 0
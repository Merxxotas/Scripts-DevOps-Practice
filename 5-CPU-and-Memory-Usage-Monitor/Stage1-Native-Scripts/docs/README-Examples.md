# Real-World Usage Examples

> Practical examples for common system monitoring scenarios.

---

## Scenario Index

| Scenario | Description | Commands |
|----------|-------------|----------|
| [Server Health Check](#server-health-check) | Quick diagnostic | 2 min |
| [Load Test Monitoring](#load-test-monitoring) | Watch during tests | 5 min |
| [Memory Leak Detection](#memory-leak-detection) | Identify leaks | 15 min |
| [Disk Space Alert](#disk-space-alert) | Monitor storage | 5 min |
| [Process Troubleshooting](#process-troubleshooting) | Debug runaway process | 10 min |
| [Daily Reporting](#daily-reporting) | Automated reports | 20 min setup |
| [NOC Dashboard](#noc-dashboard) | Wall display | 30 min setup |
| [CI/CD Integration](#cicd-integration) | Pipeline checks | 15 min setup |

---

## Server Health Check

**Goal:** Quickly check if a server is healthy

```bash
#!/bin/bash
# health-check.sh

OUTPUT=$(./system_monitor.sh --json)
CPU=$(echo "$OUTPUT" | jq '.cpu.percent')
MEM=$(echo "$OUTPUT" | jq '.memory.percent')

echo "=== Server Health Check ==="
echo "CPU: ${CPU}%"
echo "Memory: ${MEM}%"

if (( $(echo "$CPU < 70 && $MEM < 80" | bc -l) )); then
    echo " Server is healthy"
    exit 0
else
    echo " Server under stress"
    exit 1
fi
```

**Usage:**
```bash
./health-check.sh
# === Server Health Check ===
# CPU: 45%
# Memory: 60%
# ✅ Server is healthy
```

---

## Load Test Monitoring

**Goal:** Monitor system during load testing

```bash
# Terminal 1: Start monitoring
./system_monitor.sh --watch 2 --json --export ./load-test/

# Terminal 2: Run your load test
ab -n 10000 -c 100 http://localhost:8080/
# or
k6 run load-test.js
# or
jmeter -n -t test-plan.jmx
```

**After test - Analyze:**
```bash
# Find peak CPU during test
jq -s 'max_by(.cpu.percent)' ./load-test/*.json

# Find peak memory
jq -s 'max_by(.memory.percent)' ./load-test/*.json

# Calculate averages
jq -s 'map(.cpu.percent) | add / length' ./load-test/*.json
```

---

## Memory Leak Detection

**Goal:** Identify if an application has a memory leak

```bash
# Monitor specific process over time
PID=$(pgrep firefox)

for i in {1..60}; do
    ps -p $PID -o pid,vsz,rss,comm | tail -1 | tee -a memory-log.txt
    sleep 60
done

# Analyze - if RSS consistently grows, there's a leak
awk '{print $3}' memory-log.txt | gnuplot -p -e "plot '<cat' with lines"
```

**Using the monitor:**
```bash
# Watch Firefox specifically
./system_monitor.sh --watch 60 | grep firefox | tee firefox-memory.log

# After some time, check growth
grep "firefox" firefox-memory.log | awk '{print $4}' | sort -n
```

---

## Disk Space Alert

**Goal:** Alert when disk space is low

```bash
#!/bin/bash
# disk-alert.sh

THRESHOLD=90
OUTPUT=$(./system_monitor.sh --json)
DISK_USAGE=$(echo "$OUTPUT" | jq '.disk[0].percent')

if [ "$DISK_USAGE" -gt "$THRESHOLD" ]; then
    echo "ALERT: Disk usage is ${DISK_USAGE}%" | \
        mail -s "Disk Space Alert" admin@example.com
fi
```

**Cron job:**
```bash
# Check every hour
0 * * * * /path/to/disk-alert.sh
```

---

## Process Troubleshooting

**Goal:** Debug a runaway process

```bash
# Step 1: Identify the culprit
./system_monitor.sh
# Look for process with high CPU or memory

# Step 2: Get detailed info
PID=1234
ps -fp $PID
lsof -p $PID  # What files is it using?
strace -p $PID  # What system calls? (Linux)

# Step 3: Check logs
journalctl -u servicename  # For systemd services
tail -f /var/log/app.log

# Step 4: If needed, kill and restart
./system_monitor.sh --restart $PID
```

---

## Daily Reporting

**Goal:** Generate daily system reports

```bash
#!/bin/bash
# daily-report.sh

DATE=$(date +%Y-%m-%d)
REPORT_DIR="/var/reports/system-monitor"
mkdir -p "$REPORT_DIR"

# Collect data throughout the day
./system_monitor.sh --watch 300 --json --export "$REPORT_DIR/$DATE/"

# Generate summary at end of day
{
    echo "=== Daily System Report - $DATE ==="
    echo ""
    echo "Peak CPU:"
    jq -s 'max_by(.cpu.percent) | {time: .timestamp, cpu: .cpu.percent}' \
        "$REPORT_DIR/$DATE/"*.json
    
    echo ""
    echo "Peak Memory:"
    jq -s 'max_by(.memory.percent) | {time: .timestamp, memory: .memory.percent}' \
        "$REPORT_DIR/$DATE/"*.json
    
    echo ""
    echo "Average Values:"
    jq -s '{
        avg_cpu: (map(.cpu.percent) | add / length),
        avg_memory: (map(.memory.percent) | add / length)
    }' "$REPORT_DIR/$DATE/"*.json
    
} > "$REPORT_DIR/summary-$DATE.txt"

# Email report
mail -s "Daily System Report - $DATE" admin@example.com \
    < "$REPORT_DIR/summary-$DATE.txt"
```

**Run daily:**
```bash
# Add to crontab
0 0 * * * /path/to/daily-report.sh &
0 23 * * * pkill -f "system_monitor.sh --watch"
```

---

## NOC Dashboard

**Goal:** Create a wall-mounted display for operations center

```bash
#!/bin/bash
# noc-dashboard.sh

# Full-screen terminal with large fonts
# Run on a Raspberry Pi connected to TV

clear
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           NETWORK OPERATIONS CENTER                        ║"
echo "║           $(date '+%Y-%m-%d %H:%M:%S')                              ║"
echo "╚════════════════════════════════════════════════════════════╝"

./system_monitor.sh --watch 5
```

**Systemd service for auto-start:**
```bash
sudo tee /etc/systemd/system/noc-dashboard.service > /dev/null <<EOF
[Unit]
Description=NOC Dashboard
After=graphical.target

[Service]
Type=simple
User=pi
Environment=TERM=xterm-256color
ExecStart=/usr/bin/xterm -fullscreen -fa 'Monospace' -fs 24 -e /home/pi/noc-dashboard.sh
Restart=always

[Install]
WantedBy=graphical.target
EOF

sudo systemctl enable noc-dashboard
```

---

## CI/CD Integration

**Goal:** Monitor system health during CI/CD pipelines

### GitHub Actions

```yaml
# .github/workflows/monitor.yml
name: System Monitor

on: [push, pull_request]

jobs:
  monitor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run System Monitor
        run: |
          ./system_monitor.sh --json --export ./metrics/
      
      - name: Check Thresholds
        run: |
          CPU=$(jq '.cpu.percent' ./metrics/*.json)
          if (( $(echo "$CPU > 80" | bc -l) )); then
            echo "CPU usage too high: ${CPU}%"
            exit 1
          fi
      
      - name: Upload Metrics
        uses: actions/upload-artifact@v3
        with:
          name: system-metrics
          path: ./metrics/
```

### GitLab CI

```yaml
# .gitlab-ci.yml
monitor:
  stage: test
  script:
    - ./system_monitor.sh --json --export ./metrics/
    - |
      CPU=$(jq '.cpu.percent' ./metrics/*.json)
      if (( $(echo "$CPU > 80" | bc -l) )); then
        echo "High CPU usage detected"
        exit 1
      fi
  artifacts:
    paths:
      - ./metrics/
```

---

## Quick Reference Card

```bash
# One-liners for common tasks

# Quick health check
./system_monitor.sh --json | jq '{cpu: .cpu.percent, mem: .memory.percent}'

# Log to file every minute
./system_monitor.sh --watch 60 --json --export ./logs/

# Check disk before large operation
./system_monitor.sh --disk | grep -E "(9[0-9]|100)%" && echo "WARNING: Disk nearly full!"

# Kill runaway process
./system_monitor.sh --kill $(pgrep -f "runaway-process")

# Restart service
./system_monitor.sh --restart $(pgrep nginx)
```

---

## Related Documentation

- [Installation Guide](README-Installation.md)
- [Basic Monitoring](README-Basic-Monitoring.md)
- [Watch Mode](README-Watch-Mode.md)
- [Kill Process](README-Kill-Process.md)
- [Process Restart](README-Process-Restart.md)
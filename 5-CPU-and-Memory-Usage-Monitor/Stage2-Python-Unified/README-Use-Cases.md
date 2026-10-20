# Stage 2: Use Cases and Examples

> Detailed instructions for common monitoring scenarios using the Python implementation.

---

## Use Case Index

| Use Case | Description | Complexity |
|----------|-------------|------------|
| [Basic System Check](#use-case-1-basic-system-check) | Quick one-time monitoring | Beginner |
| [Continuous Monitoring](#use-case-2-continuous-monitoring) | Background data collection | Beginner |
| [JSON Export for API](#use-case-3-json-export-for-api) | Structured data for automation | Beginner |
| [CSV Analysis](#use-case-4-csv-analysis) | Spreadsheet-compatible export | Beginner |
| [Process Management](#use-case-5-process-management) | Kill and restart processes | Intermediate |
| [Integration with Monitoring](#use-case-6-integration-with-monitoring) | Datadog, Prometheus, etc. | Intermediate |
| [Automated Alerting](#use-case-7-automated-alerting) | Slack/email notifications | Intermediate |
| [Load Test Monitoring](#use-case-8-load-test-monitoring) | Performance testing | Intermediate |
| [Custom Exporter](#use-case-9-custom-exporter) | Write your own output format | Advanced |

---

## Use Case 1: Basic System Check

**Goal:** Get a quick snapshot of system health

### Command

```bash
# Run once with default display output
uv run -m system_monitor

# Or after installation
system-monitor
```

### Expected Output

```
╔════════════════════════════════════════════════════════════╗
║     System Resource Monitor v2.0.0                         ║
╚════════════════════════════════════════════════════════════╝

Timestamp: 2026-01-15 10:30:00
Hostname: myserver
Platform: Linux-5.15-x86_64

┌─────────────────────────────────────────┐
│ CPU Usage                               │
│ [████████████░░░░░░░░░░░░░░░░░░]  35%   │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Memory Usage                            │
│ [████████░░░░░░░░░░░░░░░░░░░░░░]  28%   │
└─────────────────────────────────────────┘

Top Processes (by RAM):
PID     Name            CPU%    RAM(MB)
1234    firefox         12.5    512.0
5678    python          8.2     256.0
9012    vscode          5.1     423.0
```

### Interpretation

| Metric | Value | Status | Action |
|--------|-------|--------|--------|
| CPU | 35% | Normal | None needed |
| Memory | 28% | Normal | None needed |

---

## Use Case 2: Continuous Monitoring

**Goal:** Monitor system over time with periodic snapshots

### Command

```bash
# Watch mode with 5-second intervals
uv run -m system_monitor --watch --interval 5

# With export to directory (auto-filenames)
mkdir -p ./logs
uv run -m system_monitor --watch --interval 10 --format json --export ./logs/
```

### Output Files

```
logs/
├── system-monitor-20260115-103000.json
├── system-monitor-20260115-103010.json
├── system-monitor-20260115-103020.json
└── ...
```

### Stop Monitoring

Press `Ctrl+C` to gracefully stop watch mode.

---

## Use Case 3: JSON Export for API

**Goal:** Export data in JSON format for programmatic use

### Command

```bash
# Export single snapshot to JSON
uv run -m system_monitor --format json --export ./report.json

# Pretty-print with jq
uv run -m system_monitor --format json | jq .
```

### JSON Structure

```json
{
  "timestamp": "2026-01-15T10:30:00",
  "hostname": "myserver",
  "platform": "Linux-5.15-x86_64",
  "version": "2.0.0",
  "cpu": {
    "percent": 35.2,
    "count": 8,
    "frequency_mhz": 2400
  },
  "memory": {
    "percent": 28.5,
    "total_gb": 16.0,
    "available_gb": 11.4
  },
  "disk": [
    {
      "mount": "/",
      "total_gb": 500.0,
      "used_gb": 350.0,
      "free_gb": 150.0,
      "percent": 70
    }
  ],
  "processes": [
    {
      "pid": 1234,
      "name": "firefox",
      "cpu_percent": 12.5,
      "memory_mb": 512.0,
      "status": "running"
    }
  ]
}
```

### Using in Scripts

```bash
#!/bin/bash
# api-integration.sh

# Get system stats
DATA=$(uv run -m system_monitor --format json)
CPU=$(echo "$DATA" | jq -r '.cpu.percent')
MEM=$(echo "$DATA" | jq -r '.memory.percent')

# Send to API
curl -X POST https://monitoring.example.com/api/metrics \
  -H "Content-Type: application/json" \
  -d "$DATA"
```

---

## Use Case 4: CSV Analysis

**Goal:** Export data for analysis in Excel or pandas

### Command

```bash
# Export to CSV
uv run -m system_monitor --format csv --export ./report.csv

# In watch mode (good for time-series analysis)
uv run -m system_monitor --watch --interval 60 --format csv --export ./logs/
```

### CSV Format

```csv
timestamp,hostname,cpu_percent,memory_percent,disk_percent
2026-01-15T10:30:00,myserver,35.2,28.5,70
```

### Analysis with Python Pandas

```python
import pandas as pd
import glob

# Read all CSV files
df = pd.concat([pd.read_csv(f) for f in glob.glob('logs/*.csv')])

# Calculate statistics
print(df.describe())

# Find peak usage
print(f"Peak CPU: {df['cpu_percent'].max()}%")
print(f"Peak Memory: {df['memory_percent'].max()}%")

# Plot trends
df.plot(x='timestamp', y=['cpu_percent', 'memory_percent'])
```

### Opening in Excel

1. Open Excel
2. Data → Get Data → From File → From Text/CSV
3. Select your `.csv` file
4. Excel auto-detects columns and data types

---

## Use Case 5: Process Management

**Goal:** Kill or restart processes consuming too many resources

### List Running Processes

```bash
# Shows top processes by default
uv run -m system_monitor
```

### Kill a Process

```bash
# Kill by PID
uv run -m system_monitor kill 1234

# Kill by name
uv run -m system_monitor kill firefox

# Force kill (SIGKILL)
uv run -m system_monitor kill 1234 --force
```

### Restart a Process

```bash
# Restart by PID (auto-detects command)
uv run -m system_monitor restart 1234

# Restart by name
uv run -m system_monitor restart nginx

# Restart with custom command
uv run -m system_monitor restart nginx \
  --command "nginx -c /etc/nginx/custom.conf"
```

### View Kill Log

```bash
# Show recent kill/restart operations
uv run -m system_monitor kill-log

# Show last 10 entries
uv run -m system_monitor kill-log --limit 10
```

---

## Use Case 6: Integration with Monitoring Systems

**Goal:** Send metrics to external monitoring platforms

### Datadog Integration

```python
# datadog_integration.py
from datadog import initialize, api
import json
import subprocess

# Initialize Datadog
options = {
    'api_key': 'YOUR_API_KEY',
    'app_key': 'YOUR_APP_KEY'
}
initialize(**options)

# Get metrics from system monitor
result = subprocess.run(
    ['uv', 'run', '-m', 'system_monitor', '--format', 'json'],
    capture_output=True, text=True
)
data = json.loads(result.stdout)

# Send to Datadog
api.Metric.send([
    {
        'metric': 'system.cpu.usage',
        'points': data['cpu']['percent'],
        'tags': ['env:production', 'host:' + data['hostname']]
    },
    {
        'metric': 'system.memory.usage',
        'points': data['memory']['percent'],
        'tags': ['env:production', 'host:' + data['hostname']]
    }
])
```

### Prometheus Exporter

```python
# prometheus_exporter.py
from prometheus_client import start_http_server, Gauge
import subprocess
import json
import time

# Create metrics
cpu_gauge = Gauge('system_cpu_percent', 'CPU usage percentage')
memory_gauge = Gauge('system_memory_percent', 'Memory usage percentage')

# Start HTTP server
start_http_server(8000)

while True:
    # Get metrics
    result = subprocess.run(
        ['uv', 'run', '-m', 'system_monitor', '--format', 'json'],
        capture_output=True, text=True
    )
    data = json.loads(result.stdout)
    
    # Update gauges
    cpu_gauge.set(data['cpu']['percent'])
    memory_gauge.set(data['memory']['percent'])
    
    time.sleep(15)
```

---

## Use Case 7: Automated Alerting

**Goal:** Send alerts when thresholds are exceeded

### Slack Alert Script

```python
#!/usr/bin/env python3
# slack_alert.py
import subprocess
import json
import requests
import sys

SLACK_WEBHOOK = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
CPU_THRESHOLD = 90
MEM_THRESHOLD = 90

def get_metrics():
    result = subprocess.run(
        ['uv', 'run', '-m', 'system_monitor', '--format', 'json'],
        capture_output=True, text=True
    )
    return json.loads(result.stdout)

def send_alert(message):
    requests.post(SLACK_WEBHOOK, json={"text": message})

def main():
    data = get_metrics()
    cpu = data['cpu']['percent']
    mem = data['memory']['percent']
    hostname = data['hostname']
    
    alerts = []
    if cpu > CPU_THRESHOLD:
        alerts.append(f"🚨 HIGH CPU: {cpu}% on {hostname}")
    if mem > MEM_THRESHOLD:
        alerts.append(f"🚨 HIGH MEMORY: {mem}% on {hostname}")
    
    if alerts:
        send_alert("\n".join(alerts))
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

### Cron Setup

```bash
# Check every 5 minutes
*/5 * * * * /usr/bin/python3 /path/to/slack_alert.py
```

---

## Use Case 8: Load Test Monitoring

**Goal:** Monitor system performance during load testing

### Setup

```bash
# Terminal 1: Start monitoring
mkdir -p ./load-test-results
uv run -m system_monitor \
  --watch \
  --interval 2 \
  --format json \
  --export ./load-test-results/

# Terminal 2: Run load test
k6 run --duration 5m --vus 100 load-test.js
```

### Analysis

```python
# analyze_load_test.py
import json
import glob
import pandas as pd

# Load all data points
files = glob.glob('load-test-results/*.json')
data = [json.load(open(f)) for f in files]
df = pd.DataFrame([{
    'timestamp': d['timestamp'],
    'cpu': d['cpu']['percent'],
    'memory': d['memory']['percent']
} for d in data])

# Generate report
print("=== Load Test Analysis ===")
print(f"Duration: {len(df)} data points")
print(f"Avg CPU: {df['cpu'].mean():.1f}%")
print(f"Peak CPU: {df['cpu'].max():.1f}%")
print(f"Avg Memory: {df['memory'].mean():.1f}%")
print(f"Peak Memory: {df['memory'].max():.1f}%")

# Save summary
df.describe().to_csv('load-test-summary.csv')
```

---

## Use Case 9: Custom Exporter

**Goal:** Create your own output format

### Custom Exporter Example

```python
# custom_exporter.py
from system_monitor import SystemMonitor
from system_monitor.models import SystemSnapshot
import xml.etree.ElementTree as ET

def export_to_xml(snapshot: SystemSnapshot) -> str:
    """Export to XML format for legacy system integration."""
    root = ET.Element("system")
    ET.SubElement(root, "timestamp").text = snapshot.timestamp.isoformat()
    ET.SubElement(root, "hostname").text = snapshot.hostname
    
    cpu = ET.SubElement(root, "cpu")
    ET.SubElement(cpu, "percent").text = str(snapshot.cpu_percent)
    
    memory = ET.SubElement(root, "memory")
    ET.SubElement(memory, "percent").text = str(snapshot.memory_percent)
    
    return ET.tostring(root, encoding='unicode')

def main():
    monitor = SystemMonitor()
    snapshot = monitor.get_snapshot()
    print(export_to_xml(snapshot))

if __name__ == "__main__":
    main()
```

### Run Custom Exporter

```bash
uv run --with lxml python custom_exporter.py
```

---

## Additional Resources

- [Main README](README.md) - Installation and basic usage
- [Stage 1: Native Scripts](../Stage1-Native-Scripts/) - Shell script implementation
- [Stage 3: Containerization](../Stage3-Containerization/) - Docker deployment
- [Stage 4: CI/CD Pipeline](../Stage4-CI-CD-Pipeline/) - Automated testing
# Export Formats - JSON and CSV

> Export system monitoring data in structured formats for integration, logging, and analysis.

---

## Export Format Overview

| Format | Best For | File Extension | Human Readable |
|--------|----------|----------------|----------------|
| **JSON** | APIs, log aggregation, automation | `.json` | (structured) |
| **CSV** | Spreadsheets, data analysis, reporting | `.csv` | Yes |
| **Display** | Interactive monitoring | Terminal | Yes |

---

## JSON Export

JSON format is ideal for:
- Feeding data to monitoring systems
- Log aggregation (ELK Stack, Splunk)
- API responses
- Automated processing

### Bash

```bash
# Export to stdout
./system_monitor.sh --json

# Sample Output:
# {
#   "timestamp": "2026-01-15T10:30:00",
#   "version": "1.3.0",
#   "system": {
#     "hostname": "server01",
#     "os": "Linux",
#     "platform": "x86_64"
#   },
#   "cpu": {
#     "percent": 45.2,
#     "status": "normal"
#   },
#   "memory": {
#     "percent": 60.5,
#     "total_mb": 16384,
#     "used_mb": 9912,
#     "status": "normal"
#   },
#   "disk": [
#     {
#       "mount": "/",
#       "total": "500G",
#       "used": "350G",
#       "free": "150G",
#       "percent": 70
#     }
#   ],
#   "top_processes": [
#     {
#       "pid": 1234,
#       "name": "firefox",
#       "cpu_percent": 12.5,
#       "memory_mb": 512.3
#     }
#   ]
# }

# Export to file
./system_monitor.sh --json --export ./report.json

# Export to directory (auto-generated filename)
./system_monitor.sh --json --export ./logs/
# Creates: ./logs/system-monitor-20260115-103000.json
```

### PowerShell

```powershell
# Export to stdout
.\system_monitor.ps1 -Format Json

# Export to file
.\system_monitor.ps1 -Format Json -ExportPath .\report.json

# Export to directory
.\system_monitor.ps1 -Format Json -ExportPath .\logs\
```

### Pretty-Printing JSON

```bash
# Make JSON human-readable with jq
./system_monitor.sh --json | jq .

# Or save then format
./system_monitor.sh --json --export /tmp/raw.json
cat /tmp/raw.json | jq . > /tmp/pretty.json
```

---

## CSV Export

CSV format is ideal for:
- Importing into Excel or Google Sheets
- Data analysis with pandas/R
- Simple text processing
- Sharing with non-technical users

### Bash

```bash
# Export to stdout
./system_monitor.sh --csv

# Sample Output:
# timestamp,hostname,cpu_percent,memory_percent
# 2026-01-15T10:30:00,server01,45.2,60.5
#
# top_pid,top_name,top_cpu,top_memory
# 1234,firefox,12.5,512.3
# 5678,code,8.2,423.1

# Export to file
./system_monitor.sh --csv --export ./report.csv
```

### PowerShell

```powershell
# Export to stdout
.\system_monitor.ps1 -Format Csv

# Export to file
.\system_monitor.ps1 -Format Csv -ExportPath .\report.csv
```

### Opening CSV in Excel

```powershell
# Generate and open immediately
.\system_monitor.ps1 -Format Csv -ExportPath .\report.csv
Invoke-Item .\report.csv  # Opens in default app (Excel)
```

---

## Export to Directory

When exporting to a directory, the script auto-generates filenames:

```bash
# Bash - directory export
./system_monitor.sh --json --export ./logs/
# Creates: ./logs/system-monitor-20260115-103000.json

# PowerShell - directory export
.\system_monitor.ps1 -Format Json -ExportPath .\logs\
# Creates: .\logs\system-monitor-20260115-103000.json
```

**Filename Format:** `system-monitor-YYYYMMDD-HHMMSS.<ext>`

---

## Combining Export with Watch Mode

Export data continuously at intervals:

### Bash

```bash
# Export JSON every 5 seconds to directory
./system_monitor.sh --watch 5 --json --export ./logs/

# Creates files:
# ./logs/system-monitor-20260115-103000.json
# ./logs/system-monitor-20260115-103005.json
# ./logs/system-monitor-20260115-103010.json
# ...

# Press Ctrl+C to stop
```

### PowerShell

```powershell
# Export CSV every 10 seconds
.\system_monitor.ps1 -Watch -RefreshSeconds 10 -Format Csv -ExportPath .\logs\
```

---

## Processing Exported Data

### Analyze JSON with jq

```bash
# Extract just CPU values from all files
for f in ./logs/*.json; do
    jq '.cpu.percent' "$f"
done

# Find peak CPU usage
jq -s 'max_by(.cpu.percent) | {timestamp, cpu: .cpu.percent}' ./logs/*.json
```

### Analyze CSV with Python

```python
import pandas as pd

# Read all CSV files
import glob
df = pd.concat([pd.read_csv(f) for f in glob.glob('logs/*.csv')])

# Calculate statistics
print(df['cpu_percent'].describe())
print(f"Peak CPU: {df['cpu_percent'].max()}%")
print(f"Peak Memory: {df['memory_percent'].max()}%")

# Plot trends
df.plot(x='timestamp', y=['cpu_percent', 'memory_percent'])
```

### Import to Excel

1. Open Excel
2. Data → Get Data → From File → From Text/CSV
3. Select your `.csv` file
4. Excel will auto-detect columns
5. Create charts and pivot tables

---

## Integration Examples

### Send to Elasticsearch

```bash
# Export and send to ELK stack
./system_monitor.sh --json | curl -X POST \
    "http://elasticsearch:9200/metrics/_doc" \
    -H 'Content-Type: application/json' \
    -d @-
```

### Send to Slack

```bash
# Export and notify if CPU > 90%
CPU=$(./system_monitor.sh --json | jq '.cpu.percent')
if (( $(echo "$CPU > 90" | bc -l) )); then
    MESSAGE="High CPU Alert: ${CPU}%"
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$MESSAGE\"}" \
        $SLACK_WEBHOOK_URL
fi
```

### Ingest to Splunk

```bash
# Configure Splunk forwarder to monitor the logs directory
# Splunk will auto-parse JSON files
./system_monitor.sh --watch 60 --json --export /var/log/system-monitor/
```

---

## Related Documentation

- [Watch Mode (Continuous Monitoring)](README-Watch-Mode.md)
- [Basic Monitoring](README-Basic-Monitoring.md)
- [Disk Usage Monitoring](README-Disk-Usage.md)
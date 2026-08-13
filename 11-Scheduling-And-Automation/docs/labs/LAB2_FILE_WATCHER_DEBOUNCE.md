# Lab 2: File Watcher & Smart Debouncing 🧪

In this hands-on lab, you will configure EventOps to monitor a filesystem path for modifications and observe how EventOps's 2-second debouncing cooldown prevents rapid-fire OS file events from causing script execution storms.

---

## 🎯 Objectives
- Configure a `file_change` rule in `rules.json`.
- Monitor file modification events.
- Perform rapid-fire file writes to observe debouncing in action.
- Verify that only debounced events trigger shell actions.

---

## 🛠️ Step-by-Step Instructions

### Step 1: Prepare Test Directory & Configuration

Create a lab directory:
```bash
mkdir -p lab2_workspace
cd lab2_workspace
touch watched_config.ini
```

Create `rules.json`:
```json
{
  "rules": [
    {
      "name": "Auto Config Reloader",
      "type": "file_change",
      "watch_path": "watched_config.ini",
      "action": "echo '[RELOAD] Config reloaded at $(date)' >> reload.log"
    }
  ]
}
```

---

### Step 2: Start the EventOps Daemon

#### Running Python Daemon:
```bash
python3 /path/to/11-Scheduling-And-Automation/EventOps/eventops.py start --config rules.json
```

#### Running Go Daemon:
```bash
go run /path/to/11-Scheduling-And-Automation/EventOps-Go/main.go start --config rules.json
```

---

### Step 3: Simulate Rapid-Fire OS File Modification Events

In a second terminal window, perform 5 rapid file modifications within a single second:

```bash
for i in {1..5}; do
  echo "setting_$i=true" >> watched_config.ini
  sleep 0.1
done
```

---

### Step 4: Verify Debouncing Log Output

Inspect `eventops.log`:

```text
[2026-08-12 15:10:00] [INFO] [FileWatcher] File change detected on '/path/to/watched_config.ini'. Triggering rule 'Auto Config Reloader'
[2026-08-12 15:10:00] [INFO] [Executor] Executing action [Auto Config Reloader]: echo '[RELOAD] Config reloaded at $(date)' >> reload.log
[2026-08-12 15:10:00] [DEBUG] [FileWatcher] Debounced file change event for rule 'Auto Config Reloader' (0.10s < 2.00s cooldown)
[2026-08-12 15:10:00] [DEBUG] [FileWatcher] Debounced file change event for rule 'Auto Config Reloader' (0.20s < 2.00s cooldown)
[2026-08-12 15:10:00] [DEBUG] [FileWatcher] Debounced file change event for rule 'Auto Config Reloader' (0.30s < 2.00s cooldown)
[2026-08-12 15:10:00] [DEBUG] [FileWatcher] Debounced file change event for rule 'Auto Config Reloader' (0.40s < 2.00s cooldown)
```

Check `reload.log`:
```bash
cat reload.log
```
Notice that despite 5 rapid modification events, the action executed **exactly once**!

---

### Step 5: Verify Execution After Cooldown Expiry

Wait 2.5 seconds, then perform another file edit:

```bash
sleep 2.5
echo "final_setting=enabled" >> watched_config.ini
```

Check `reload.log` again:
```bash
cat reload.log
```
Notice a second entry has been appended because the 2-second cooldown expired!

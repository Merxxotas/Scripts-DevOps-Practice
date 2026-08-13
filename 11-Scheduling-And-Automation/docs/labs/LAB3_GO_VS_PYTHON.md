# Lab 3: Benchmarking & Comparing Python vs Go EventOps Daemons 🧪

In this hands-on lab, you will compile the standalone Go binary, launch both Python and Go daemons side-by-side, and measure their relative resource utilization, startup times, and execution performance.

---

## 🎯 Objectives
- Compile the Go standalone binary (`eventops`).
- Measure binary size and startup speed.
- Compare memory footprint (RSS) under idle and active load.
- Evaluate single-binary portability vs Python virtualenv deployment.

---

## 🛠️ Step-by-Step Instructions

### Step 1: Build Standalone Go Executable

Navigate to `EventOps-Go` and compile a stripped release binary:

```bash
cd /path/to/11-Scheduling-And-Automation/EventOps-Go
go build -ldflags="-s -w" -o eventops main.go
```

Inspect the output binary size:
```bash
ls -lh eventops
```
*(Typical binary size is ~8-12 MB containing the entire standalone runtime and HTTP server).*

---

### Step 2: Compare Memory Footprint (RSS)

Start both daemons in background processes on different HTTP ports:

#### Launch Python Daemon (Port 8081):
```bash
python3 /path/to/11-Scheduling-And-Automation/EventOps/eventops.py start --port 8081 &
PY_PID=$!
```

#### Launch Go Daemon (Port 8082):
```bash
./eventops start --port 8082 &
GO_PID=$!
```

#### Measure Resident Set Size (RSS Memory):
```bash
ps -o pid,user,rss,command -p $PY_PID $GO_PID
```

**Expected Comparison Output:**
```text
  PID USER       RSS COMMAND
12345 user     28640 python3 .../eventops.py start --port 8081
12346 user      5420 ./eventops start --port 8082
```
*Go uses ~80% less RAM than Python for the same daemon workload.*

---

### Step 3: Compare Startup Speed

Measure startup time using the `time` utility:

#### Python Startup Benchmark:
```bash
time python3 /path/to/11-Scheduling-And-Automation/EventOps/eventops.py --help
```

#### Go Startup Benchmark:
```bash
time ./eventops --help
```

---

### Step 4: Cleanup Benchmark Processes

Terminate background test daemons:
```bash
kill $PY_PID $GO_PID
```

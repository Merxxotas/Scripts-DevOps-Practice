# Stage 3: Docker Use Cases

> Complete guide for deploying the System Monitor with Docker in various scenarios.

---

## Use Case Index

| Use Case | Description | Complexity |
|----------|-------------|------------|
| [One-Time System Check](#use-case-1-one-time-system-check) | Quick diagnostic with container | Beginner |
| [Continuous Background Monitoring](#use-case-2-continuous-background-monitoring) | Long-running monitoring | Beginner |
| [Log Aggregation Setup](#use-case-3-log-aggregation-setup) | Centralized logging | Intermediate |
| [Production Deployment](#use-case-4-production-deployment) | Secure, resource-limited deployment | Intermediate |
| [Multi-Node Monitoring](#use-case-5-multi-node-monitoring) | Monitor multiple servers | Intermediate |
| [Kubernetes Deployment](#use-case-6-kubernetes-deployment) | K8s pods and sidecars | Advanced |
| [Custom Image Build](#use-case-7-custom-image-build) | Extend the base image | Advanced |

---

## Use Case 1: One-Time System Check

**Goal:** Run a quick system check using Docker without installing anything

### Command

```bash
# Basic run - shows help
docker run --rm system-monitor:latest

# Run once and display results
docker run --rm system-monitor:latest --format display

# Run and save JSON output
docker run --rm \
  -v "$(pwd)/logs:/app/logs" \
  system-monitor:latest \
  --format json \
  --export /app/logs/check-$(date +%Y%m%d-%H%M%S).json
```

### Windows PowerShell

```powershell
# One-time check with JSON output
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
docker run --rm `
  -v "${PWD}/logs:/app/logs" `
  system-monitor:latest `
  --format json `
  --export "/app/logs/check-$timestamp.json"
```

### What This Does

1. Downloads the image (first time only)
2. Runs the container
3. Executes the monitoring command
4. Saves output to local `logs/` directory
5. Removes the container (`--rm`)

---

## Use Case 2: Continuous Background Monitoring

**Goal:** Run continuous monitoring in a background container

### Basic Background Run

```bash
# Run in detached mode
docker run -d \
  --name sysmon-watch \
  --restart unless-stopped \
  -v "$(pwd)/logs:/app/logs" \
  system-monitor:latest \
  --watch \
  --interval 60 \
  --format json \
  --export /app/logs/

# Check status
docker ps

# View logs
docker logs -f sysmon-watch

# Stop monitoring
docker stop sysmon-watch
docker rm sysmon-watch
```

### Using Docker Compose

```bash
# Start with watch profile
docker-compose --profile watch up -d

# Check logs
docker-compose logs -f monitor-watch

# Stop
docker-compose --profile watch down
```

### Log Rotation

Prevent logs from filling disk:

```bash
#!/bin/bash
# log-cleanup.sh

# Run weekly via cron
find ./logs -name "*.json" -mtime +7 -delete
find ./logs -name "*.csv" -mtime +7 -delete
```

---

## Use Case 3: Log Aggregation Setup

**Goal:** Collect logs from multiple containers and forward to ELK/Loki

### Filebeat Sidecar Pattern

```yaml
# docker-compose.logging.yml
version: "3.8"

services:
  monitor:
    image: system-monitor:latest
    volumes:
      - monitor-logs:/app/logs
    command: ["--watch", "--interval", "60", "--format", "json", "--export", "/app/logs/"]
    networks:
      - monitoring

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.11.0
    volumes:
      - monitor-logs:/logs:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    depends_on:
      - monitor
    networks:
      - monitoring

volumes:
  monitor-logs:

networks:
  monitoring:
```

### Filebeat Configuration

```yaml
# filebeat.yml
filebeat.inputs:
- type: log
  paths:
    - /logs/*.json
  json.keys_under_root: true
  json.add_error_key: true

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "system-monitor-%{+yyyy.MM.dd}"
```

### Fluentd Alternative

```yaml
# docker-compose.fluentd.yml
services:
  monitor:
    image: system-monitor:latest
    volumes:
      - monitor-logs:/app/logs
    command: ["--watch", "--interval", "60", "--format", "json", "--export", "/app/logs/"]

  fluentd:
    image: fluent/fluentd:v1.16
    volumes:
      - monitor-logs:/logs:ro
      - ./fluent.conf:/fluentd/etc/fluent.conf:ro
```

---

## Use Case 4: Production Deployment

**Goal:** Deploy securely with resource limits and monitoring

### Production docker-compose.yml

```yaml
version: "3.8"

services:
  monitor:
    image: system-monitor:latest
    read_only: true
    user: "1000:1000"
    cap_drop:
      - ALL
    cap_add:
      - SYS_PTRACE
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 128M
        reservations:
          cpus: '0.1'
          memory: 64M
    volumes:
      - type: bind
        source: ./logs
        target: /app/logs
      - type: tmpfs
        target: /tmp
        tmpfs:
          size: 50M
    environment:
      - LOG_LEVEL=INFO
    command: ["--watch", "--interval", "300", "--format", "json", "--export", "/app/logs/"]
    healthcheck:
      test: ["CMD", "python", "-c", "import psutil; psutil.cpu_percent()"]
      interval: 60s
      timeout: 5s
      retries: 3
      start_period: 10s
    restart: unless-stopped
```

### Security Hardening Explained

| Setting | Purpose |
|---------|---------|
| `read_only: true` | Prevents container from modifying its filesystem |
| `user: "1000:1000"` | Runs as non-root user |
| `cap_drop: ALL` | Removes all Linux capabilities |
| `cap_add: SYS_PTRACE` | Adds back only process monitoring capability |
| `no-new-privileges:true` | Prevents privilege escalation |
| `deploy.resources` | Limits CPU and memory usage |

---

## Use Case 5: Multi-Node Monitoring

**Goal:** Monitor multiple servers from a central location

### Docker Swarm Stack

```yaml
# stack.yml
version: "3.8"

services:
  monitor:
    image: system-monitor:latest
    deploy:
      mode: global  # Run on every node
      resources:
        limits:
          cpus: '0.2'
          memory: 64M
    volumes:
      - /var/log/monitor:/app/logs
    command: ["--watch", "--interval", "60", "--format", "json", "--export", "/app/logs/"]
```

### Deploy to Swarm

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c stack.yml monitoring

# Check on all nodes
docker service ps monitoring_monitor
```

### Remote Monitoring with SSH

```bash
# Monitor remote server via SSH tunnel
ssh -L 2375:localhost:2375 user@remote-server

DOCKER_HOST=tcp://localhost:2375 docker run \
  --rm \
  system-monitor:latest
```

---

## Use Case 6: Kubernetes Deployment

**Goal:** Deploy as a DaemonSet or sidecar in Kubernetes

### DaemonSet (Monitor All Nodes)

```yaml
# k8s-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: system-monitor
spec:
  selector:
    matchLabels:
      app: system-monitor
  template:
    metadata:
      labels:
        app: system-monitor
    spec:
      containers:
      - name: monitor
        image: system-monitor:latest
        command:
          - python
          - -m
          - system_monitor
          - --watch
          - --interval
          - "60"
          - --format
          - json
          - --export
          - /logs/
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
        volumeMounts:
        - name: logs
          mountPath: /logs
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
      volumes:
      - name: logs
        hostPath:
          path: /var/log/system-monitor
          type: DirectoryOrCreate
```

### Sidecar Pattern

```yaml
# k8s-sidecar.yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-monitoring
spec:
  containers:
  - name: main-app
    image: myapp:latest
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
  - name: monitor
    image: system-monitor:latest
    command:
      - python
      - -m
      - system_monitor
      - --watch
      - --interval
      - "30"
    resources:
      limits:
        cpu: 50m
        memory: 64Mi
```

### Deploy to Kubernetes

```bash
# Apply DaemonSet
kubectl apply -f k8s-daemonset.yaml

# Check pods on all nodes
kubectl get pods -l app=system-monitor -o wide

# View logs from specific node
kubectl logs system-monitor-abc123
```

---

## Use Case 7: Custom Image Build

**Goal:** Extend the base image with custom functionality

### Custom Dockerfile

```dockerfile
# Dockerfile.custom
FROM system-monitor:latest

USER root

# Install additional tools
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Add custom scripts
COPY custom-exporter.py /app/
COPY alert-webhook.sh /app/

# Make scripts executable
RUN chmod +x /app/*.sh /app/*.py

USER appuser

# Default to custom command
ENTRYPOINT ["python", "-m", "system_monitor"]
CMD ["--help"]
```

### Build and Run

```bash
# Build custom image
docker build -f Dockerfile.custom -t mycompany/system-monitor:v1.0 .

# Run with custom functionality
docker run mycompany/system-monitor:v1.0 \
  sh -c "python -m system_monitor --format json | jq '.cpu.percent'"
```

### Multi-Stage Custom Build

```dockerfile
# Dockerfile.multi-stage
# Stage 1: Builder
FROM python:3.11 AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Custom runtime
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.local /home/appuser/.local
COPY src/ /app/

USER appuser

ENTRYPOINT ["python", "-m", "system_monitor"]
```

---

## Monitoring the Monitor

### Container Health Checks

```bash
# Check container health
docker inspect --format='{{.State.Health.Status}}' sysmon-watch

# View health check logs
docker inspect --format='{{json .State.Health}}' sysmon-watch | jq
```

### Resource Usage

```bash
# Check container resource usage
docker stats sysmon-watch

# Output:
# CONTAINER ID   NAME          CPU %   MEM USAGE / LIMIT   MEM %   NET I/O   BLOCK I/O   PIDS
# abc123def456   sysmon-watch  0.05%   32MiB / 128MiB      25%     1kB/0B    0B/0B       5
```

---

## Additional Resources

- [Main README](README.md) - Basic Docker usage
- [Stage 1: Native Scripts](../Stage1-Native-Scripts/) - Shell scripts
- [Stage 2: Python Unified](../Stage2-Python-Unified/) - Python implementation
- [Stage 4: CI/CD Pipeline](../Stage4-CI-CD-Pipeline/) - Automated builds
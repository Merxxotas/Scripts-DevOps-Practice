# Stage 3: Containerization - Docker Guide

> **Containerized System Resource Monitor** - Run anywhere with Docker!

---

## 🤔 What is Docker? (Beginner's Explanation)

Think of Docker like a **shipping container** for software:

- **Shipping Container**: A standard box that can hold anything (clothes, electronics, food) and be moved anywhere (ship, truck, train)
- **Docker Container**: A standard "box" that holds your application + everything it needs (code, runtime, libraries) and runs anywhere (your laptop, cloud server, Raspberry Pi)

### Why Use Docker?

| Problem | Docker Solution |
|---------|-----------------|
| "Works on my machine" | Same environment everywhere |
| Installing dependencies is hard | Everything is pre-packaged |
| Multiple apps conflict | Each app is isolated in its own container |
| Scaling is complex | Just run more containers |

---

## 📋 Prerequisites

### Install Docker

**Windows:**
1. Download Docker Desktop: https://www.docker.com/products/docker-desktop
2. Run the installer
3. Restart your computer
4. Open Docker Desktop (whale icon in system tray)

**macOS:**
```bash
# Using Homebrew
brew install --cask docker

# Or download from: https://www.docker.com/products/docker-desktop
```

**Linux (Ubuntu/Debian):**
```bash
# Install Docker
sudo apt-get update
sudo apt-get install docker.io docker-compose

# Add your user to docker group (run without sudo)
sudo usermod -aG docker $USER
# Log out and back in for this to take effect
```

### Verify Installation

```bash
# Check Docker is installed
docker --version
# Should show: Docker version 24.x.x or higher

# Check Docker Compose
docker-compose --version
# Should show: Docker Compose version v2.x.x or higher
```

---

## 🚀 Quick Start (5 Minutes)

### 1. Navigate to This Directory

```bash
cd Stage3-Containerization
```

### 2. Build the Docker Image

```bash
# Build the image (this may take 2-3 minutes the first time)
docker build -t system-monitor:latest .

# Explanation:
# docker build    - Command to build an image
# -t              - Tag (name) for the image
# system-monitor  - Image name
# :latest         - Version tag
# .               - Build context (current directory)
```

### 3. Run the Container

```bash
# Basic run - show help
docker run system-monitor:latest

# Run with JSON output
docker run system-monitor:latest --format json

# Run with volume to save logs
docker run -v "$(pwd)/logs:/app/logs" system-monitor:latest --export /app/logs/output.json
```

**Windows PowerShell:**
```powershell
docker run -v "${PWD}/logs:/app/logs" system-monitor:latest --export /app/logs/output.json
```

---

## 📖 Understanding Docker Commands

### Basic Docker Commands

| Command | What It Does | Example |
|---------|--------------|---------|
| `docker build` | Creates an image from Dockerfile | `docker build -t myapp .` |
| `docker run` | Starts a container from an image | `docker run myapp` |
| `docker ps` | Lists running containers | `docker ps` |
| `docker stop` | Stops a running container | `docker stop container_name` |
| `docker rm` | Removes a stopped container | `docker rm container_name` |
| `docker images` | Lists downloaded images | `docker images` |
| `docker rmi` | Removes an image | `docker rmi myapp` |

### Understanding the Output

```bash
$ docker ps
CONTAINER ID   IMAGE                  COMMAND                  CREATED          STATUS          PORTS     NAMES
abc123def456   system-monitor:latest  "python -m system_m…"   5 minutes ago    Up 5 minutes              sysmon-once
```

- **CONTAINER ID**: Unique ID for this running instance
- **IMAGE**: Which image this container came from
- **STATUS**: "Up" means running, "Exited" means stopped
- **NAMES**: Human-readable name for the container

---

## 🎯 Common Use Cases

### Use Case 1: One-Time System Check

Check your system once and save results:

```bash
# Create logs directory
mkdir -p logs

# Run once and save JSON output
docker run --rm \
  -v "$(pwd)/logs:/app/logs" \
  system-monitor:latest \
  --format json \
  --export /app/logs/system-check.json

# View the results
cat logs/system-check.json | jq
```

**What this does:**
- `--rm`: Automatically remove container after it exits (keeps system clean)
- `-v`: Mount local `logs` folder to container's `/app/logs`
- Saves monitoring data to your local `logs/system-check.json`

### Use Case 2: Continuous Monitoring (Background)

Monitor your system continuously:

```bash
# Run in background with watch mode
docker run -d \
  --name sysmon-watch \
  -v "$(pwd)/logs:/app/logs" \
  system-monitor:latest \
  --watch \
  --interval 10 \
  --export /app/logs/continuous.json

# Check it's running
docker ps

# View logs in real-time
tail -f logs/continuous.json

# Stop monitoring
docker stop sysmon-watch

# Clean up
docker rm sysmon-watch
```

**Flags explained:**
- `-d`: Detached mode (runs in background)
- `--name`: Give the container a name for easy reference
- `-v`: Mount volume for persistent logs
- `--watch`: Continuous monitoring mode

### Use Case 3: Process Kill from Container

Kill a process on your host system from inside the container:

```bash
# WARNING: Requires special permissions
# Kill process with PID 1234
docker run --rm \
  --pid=host \
  --privileged \
  system-monitor:latest \
  kill 1234

# Explanation:
# --pid=host      - Share host's process namespace (see host processes)
# --privileged    - Grant extended privileges (needed for kill)
```

> ⚠️ **Security Warning**: `--privileged` gives the container full access to your system. Only use when necessary.

### Use Case 4: Development/Testing

Run tests inside a container:

```bash
# Run unit tests
docker run --rm \
  -v "$(pwd)/tests:/app/tests:ro" \
  -v "$(pwd)/pyproject.toml:/app/pyproject.toml:ro" \
  system-monitor:latest \
  sh -c "pip install pytest pytest-cov && pytest tests/ -v"
```

---

## 🐳 Docker Compose (Easier Way)

Docker Compose manages multiple containers with a configuration file.

### Why Use Compose?

Instead of long `docker run` commands:
```bash
docker run -d --name sysmon -v "$(pwd)/logs:/app/logs" --restart unless-stopped system-monitor:latest --watch --interval 10
```

Just use:
```bash
docker-compose up -d
```

### Available Profiles

| Profile | Use Case | Command |
|---------|----------|---------|
| (default) | One-time execution | `docker-compose up monitor-once` |
| `dev` | Development with live code | `docker-compose --profile dev up` |
| `prod` | Production with resource limits | `docker-compose --profile prod up` |
| `watch` | Continuous monitoring | `docker-compose --profile watch up -d` |
| `test` | Run unit tests | `docker-compose --profile test up` |

### Profile Examples

#### Development Mode (with live code changes)

```bash
# Start development container
docker-compose --profile dev up

# Edit src/system_monitor/cli.py on your host
# Changes are immediately reflected in the container

# Stop when done
Ctrl+C
```

#### Production Mode (resource limits + security)

```bash
# Start production container
docker-compose --profile prod up -d

# Check it's running
docker-compose ps

# View logs
docker-compose logs -f monitor-prod

# Stop
docker-compose --profile prod down
```

#### Continuous Monitoring

```bash
# Start watch mode in background
docker-compose --profile watch up -d

# Check logs
docker-compose logs -f monitor-watch

# Stop after 1 hour
sleep 3600 && docker-compose --profile watch down
```

---

## 🔧 Advanced Configuration

### Environment Variables

You can customize behavior with environment variables:

```bash
# Set log level
docker run -e LOG_LEVEL=DEBUG system-monitor:latest

# Set custom kill log location
docker run -e KILL_LOG_DIR=/tmp system-monitor:latest
```

### Resource Limits

Limit container resources:

```bash
# Limit CPU and memory
docker run \
  --cpus="0.5" \
  --memory="128m" \
  --memory-swap="128m" \
  system-monitor:latest
```

### Networking

Run on a specific network:

```bash
# Create custom network
docker network create monitoring

# Run container on that network
docker run --network monitoring system-monitor:latest
```

---

## 🐛 Troubleshooting

### Issue: "Cannot connect to the Docker daemon"

**Cause**: Docker service is not running

**Solution**:
```bash
# Start Docker Desktop (Windows/macOS)
# Or on Linux:
sudo systemctl start docker
```

### Issue: "Permission denied" when accessing logs

**Cause**: Volume mount permissions

**Solution**:
```bash
# Create logs directory with correct permissions
mkdir -p logs
chmod 777 logs  # Less secure but works for testing

# Or run container as your user
docker run --user $(id -u):$(id -g) -v "$(pwd)/logs:/app/logs" system-monitor:latest
```

### Issue: Container exits immediately

**Cause**: Default command shows help and exits

**Solution**:
```bash
# Use a long-running command
docker run system-monitor:latest --watch

# Or check logs
docker logs <container_id>
```

### Issue: "Image not found" or build fails

**Solution**:
```bash
# Force rebuild
docker build --no-cache -t system-monitor:latest .

# Clean up old images
docker system prune -a
```

---

## 📊 Comparing: Native vs Docker

| Feature | Native Python | Docker |
|---------|---------------|--------|
| Installation | Install Python, UV, dependencies | Just install Docker |
| Dependencies | Managed by UV/pip | Pre-packaged in image |
| Isolation | Shared with host | Completely isolated |
| Portability | Python must be installed | Runs anywhere with Docker |
| Resource control | Limited | CPU/memory limits built-in |
| Startup time | Fast (seconds) | Slower (image download) |

---

## 🎓 Docker Concepts You Should Know

### Image vs Container

- **Image**: Blueprint/template (like a class in programming)
- **Container**: Running instance (like an object in programming)

```bash
# Create image (once)
docker build -t system-monitor .

# Create many containers from one image
docker run system-monitor  # Container 1
docker run system-monitor  # Container 2
docker run system-monitor  # Container 3
```

### Layers and Caching

Docker images are built in layers. If you change something, only that layer and after are rebuilt:

```dockerfile
# Layer 1: Base image (cached)
FROM python:3.11-alpine

# Layer 2: Install dependencies (cached if requirements don't change)
RUN pip install click psutil

# Layer 3: Copy code (rebuilt when code changes)
COPY src/ ./src/
```

### Volumes (Persistent Storage)

Containers are ephemeral (temporary). Volumes persist data:

```bash
# Without volume - data lost when container stops
docker run system-monitor:latest --export /app/data.json
# File is gone when container stops

# With volume - data persists
docker run -v "$(pwd)/logs:/app/logs" system-monitor:latest --export /app/logs/data.json
# File remains in ./logs/ on your host
```

---

## 🔒 Security Best Practices

### 1. Run as Non-Root User

The Dockerfile already does this:
```dockerfile
USER monitor  # Not root!
```

### 2. Read-Only Filesystem

Production service uses read-only root:
```yaml
read_only: true
```

### 3. Minimal Capabilities

Drop all capabilities, add only what's needed:
```yaml
cap_drop:
  - ALL
cap_add:
  - SYS_PTRACE  # Only for process monitoring
```

### 4. Resource Limits

Always set limits to prevent container from consuming all resources:
```yaml
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 128M
```

---

## 📚 Useful Commands Cheat Sheet

```bash
# Build and run
docker build -t sysmon . && docker run sysmon

# Interactive shell in container
docker run -it --entrypoint sh sysmon

# Copy file from container
docker cp container_id:/app/logs/output.json ./

# View container resource usage
docker stats

# Clean up everything (careful!)
docker system prune -a --volumes

# View image layers
docker history sysmon

# Save image to file
docker save sysmon > sysmon.tar

# Load image from file
docker load < sysmon.tar
```

---

## 🚀 Next Steps

### Push to Docker Hub

```bash
# Tag with your username
docker tag system-monitor:latest yourusername/system-monitor:v2.0.0

# Login
docker login

# Push
docker push yourusername/system-monitor:v2.0.0
```

### Deploy to Cloud

**AWS ECS:**
```bash
# Push to ECR and deploy to ECS
# (Requires AWS CLI setup)
```

**Google Cloud Run:**
```bash
# Deploy directly from image
gcloud run deploy sysmon --image gcr.io/project/sysmon
```

**Kubernetes:**
```bash
# Deploy to K8s cluster
kubectl apply -f k8s-deployment.yaml
```

---

**Version**: 2.0.0  
**Base Image**: python:3.11-alpine  
**Image Size**: ~60MB (compressed)  
**License**: MIT

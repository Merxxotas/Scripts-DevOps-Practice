# Cross-Platform System Resource Monitor

> **4-Stage DevOps Capstone Project** - From native shell scripts to production CI/CD pipelines.

---

## Project Overview

This repository demonstrates a complete DevOps journey through four evolutionary stages:

| Stage | Technology | Purpose | Status |
|-------|------------|---------|--------|
| **Stage 1** | Bash + PowerShell | Native system monitoring | Complete |
| **Stage 2** | Python 3.9+ | Type-safe unified implementation | Complete |
| **Stage 3** | Docker | Containerized deployment | Complete |
| **Stage 4** | GitHub Actions | Automated CI/CD pipelines | Complete |

---

##  Quick Start

Choose your preferred deployment method:

### Option 1: Native Scripts (No Dependencies)

```bash
# Linux/macOS/WSL
cd Stage1-Native-Scripts
./system_monitor.sh --watch 5

# Windows (PowerShell)
cd Stage1-Native-Scripts
.\system_monitor.ps1 -Watch -RefreshSeconds 5
```

### Option 2: Python Package (Modern)

```bash
cd Stage2-Python-Unified
uv run -m system_monitor --watch --interval 5
```

### Option 3: Docker Container (Production)

```bash
cd Stage3-Containerization
docker compose --profile prod up -d
```

### Option 4: Automated CI/CD

Push to `main` branch triggers automated testing and Docker image publishing.

---

## Repository Structure

```
5-CPU-and-Memory-Usage-Monitor/
├── Stage1-Native-Scripts/           # Bash & PowerShell implementations
│   ├── system_monitor.sh            # Bash script (v1.3.0)
│   ├── system_monitor.ps1           # PowerShell script (v1.3.0)
│   ├── PSScriptAnalyzerSettings.psd1
│   ├── docs/                        # Usage guides per topic
│   └── README.md
├── Stage2-Python-Unified/           # Python implementation
│   ├── src/system_monitor/          # Package source
│   ├── tests/                       # pytest suite
│   ├── pyproject.toml
│   ├── README.md
│   └── README-Use-Cases.md
├── Stage3-Containerization/         # Docker deployment
│   ├── Dockerfile                   # Multi-stage build, non-root runtime
│   ├── docker-compose.yml           # Deployment profiles
│   ├── .dockerignore
│   ├── src/system_monitor/          # Same package as Stage 2
│   ├── README.md
│   └── README-Use-Cases.md
├── Stage4-CI-CD-Pipeline/           # CI/CD documentation
│   ├── README.md                    # How the root workflow is wired
│   └── setup.sh
├── tests/                           # Stage 1 suites (Bash and PowerShell)
├── docs/                            # ARCHITECTURE_COMPARISON, SCENARIOS, labs
├── README.md
├── SPECS.md                         # Module contract and architecture decisions
├── ROADMAP.md
├── CODESTYLE.md
└── .gitignore
```

The repository CI for this module lives at the repository root in
`.github/workflows/ci-cpu-monitor.yml`; it is not duplicated here.

---

## Features by Stage

### Stage 1: Native Scripts
- CPU, Memory, Disk monitoring
- JSON/CSV export
- Watch mode (continuous)
- Process kill/restart
- Audit logging
- Cross-platform (Linux, macOS, Windows)

**Documentation:** [Stage1-Native-Scripts/](Stage1-Native-Scripts/)

### Stage 2: Python Unified
- Type hints throughout
- Click CLI framework
- psutil integration
- Comprehensive pytest suite
- UV package manager support
- API-friendly JSON output

**Documentation:** [Stage2-Python-Unified/](Stage2-Python-Unified/)

### Stage 3: Containerization
- Multi-stage Docker build
- 5 Compose profiles (dev, prod, watch, test, one-shot)
- Security hardening (non-root, read-only, capabilities)
- Multi-arch support (amd64, arm64, armv7)
- Health checks
- ~60MB final image

**Documentation:** [Stage3-Containerization/](Stage3-Containerization/)

### Stage 4: CI/CD Pipeline
- 3 GitHub Actions workflows
- Multi-OS testing (Ubuntu, macOS, Windows)
- Multi-Python version matrix (3.9-3.12)
- Trivy security scanning
- Automated Docker Hub publishing
- Release automation on version tags

**Documentation:** [Stage4-CI-CD-Pipeline/](Stage4-CI-CD-Pipeline/)

---

## Documentation Guide

| If you want to... | Read this |
|-------------------|-----------|
| **Get started quickly** | [Stage1-Native-Scripts/docs/README-Installation.md](Stage1-Native-Scripts/docs/README-Installation.md) |
| **Learn basic monitoring** | [Stage1-Native-Scripts/docs/README-Basic-Monitoring.md](Stage1-Native-Scripts/docs/README-Basic-Monitoring.md) |
| **Export data (JSON/CSV)** | [Stage1-Native-Scripts/docs/README-Export-Formats.md](Stage1-Native-Scripts/docs/README-Export-Formats.md) |
| **Set up continuous monitoring** | [Stage1-Native-Scripts/docs/README-Watch-Mode.md](Stage1-Native-Scripts/docs/README-Watch-Mode.md) |
| **Kill or restart processes** | [Stage1-Native-Scripts/docs/README-Kill-Process.md](Stage1-Native-Scripts/docs/README-Kill-Process.md) |
| **See real-world examples** | [Stage1-Native-Scripts/docs/README-Examples.md](Stage1-Native-Scripts/docs/README-Examples.md) |
| **Use Python implementation** | [Stage2-Python-Unified/README.md](Stage2-Python-Unified/README.md) |
| **Python use cases** | [Stage2-Python-Unified/README-Use-Cases.md](Stage2-Python-Unified/README-Use-Cases.md) |
| **Deploy with Docker** | [Stage3-Containerization/README.md](Stage3-Containerization/README.md) |
| **Docker scenarios** | [Stage3-Containerization/README-Use-Cases.md](Stage3-Containerization/README-Use-Cases.md) |
| **Set up CI/CD** | [Stage4-CI-CD-Pipeline/README.md](Stage4-CI-CD-Pipeline/README.md) |
| **Module contract and ADRs** | [SPECS.md](SPECS.md) |

---

## 🛠️ Requirements

| Stage | Requirements |
|-------|--------------|
| Stage 1 | Bash 4.0+ OR PowerShell 5.1+ |
| Stage 2 | Python 3.9+, UV (recommended) |
| Stage 3 | Docker 24+, Docker Compose 2+ |
| Stage 4 | GitHub account, Docker Hub (optional) |

---

## Project Statistics

| Metric | Value |
|--------|-------|
| Total Source Files | 25+ |
| Lines of Code | ~6,200 |
| Test Coverage | ~700 lines |
| Documentation | ~60KB across 10+ files |
| Languages | Bash, PowerShell, Python |
| Supported Platforms | Linux, macOS, Windows |
| Container Architectures | amd64, arm64, armv7 |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

The CI/CD pipeline will automatically test your changes.

---

## 📝 License

This project is part of a DevOps learning curriculum. See individual files for license information.

---

## 🔗 Quick Links

- [Stage 1: Native Scripts →](Stage1-Native-Scripts/)
- [Stage 2: Python Unified →](Stage2-Python-Unified/)
- [Stage 3: Containerization →](Stage3-Containerization/)
- [Stage 4: CI/CD Pipeline →](Stage4-CI-CD-Pipeline/)
- [Module contract and ADRs (SPECS.md) →](SPECS.md)

---

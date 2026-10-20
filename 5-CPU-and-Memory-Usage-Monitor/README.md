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
.gitignore/                          # Git ignore rules (empty folder for user configuration)
├── Stage1-Native-Scripts/           # Bash & PowerShell implementations
│   ├── system_monitor.sh            # Main Bash script (v1.3.0)
│   ├── system_monitor.ps1           # PowerShell script (v1.3.0)
│   ├── docs/                        # Detailed documentation
│   │   ├── README-Installation.md
│   │   ├── README-Basic-Monitoring.md
│   │   ├── README-Disk-Usage.md
│   │   ├── README-Export-Formats.md
│   │   ├── README-Watch-Mode.md
│   │   ├── README-Kill-Process.md
│   │   ├── README-Process-Restart.md
│   │   └── README-Examples.md
│   ├── New-Addittions/              # Additional capabilities
│   └── logs/                        # Default log directory
├── Stage2-Python-Unified/           # Python implementation
│   ├── src/system_monitor/          # Source code (~1,800 lines)
│   ├── tests/                       # pytest suite (~700 lines)
│   ├── pyproject.toml               # UV/pip configuration
│   ├── README.md
│   └── README-Use-Cases.md          # Detailed use cases
├── Stage3-Containerization/         # Docker deployment
│   ├── Dockerfile                   # Multi-stage build (~60MB final)
│   ├── docker-compose.yml           # 5 deployment profiles
│   ├── .dockerignore
│   ├── README.md
│   └── README-Use-Cases.md          # Docker scenarios
├── Stage4-CI-CD-Pipeline/           # GitHub Actions
│   ├── .github/workflows/           # 3 workflow files
│   │   ├── ci-cd-pipeline.yml       # Main pipeline
│   │   ├── pr-validation.yml        # PR checks
│   │   └── release.yml              # Release automation
│   ├── README.md
│   └── README-Pipelines.md          # Pipeline documentation
└── AGENTS.md                        # Technical reference
```

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
| **Understand pipelines** | [Stage4-CI-CD-Pipeline/README-Pipelines.md](Stage4-CI-CD-Pipeline/README-Pipelines.md) |
| **Technical deep dive** | [AGENTS.md](AGENTS.md) |

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
- [Technical Reference (AGENTS.md) →](AGENTS.md)

---

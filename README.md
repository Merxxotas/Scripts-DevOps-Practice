# DevOps Automation Scripts Repository 🛠️

Welcome to the central repository for all our DevOps bash, PowerShell, and Python automation scripts. 

This is a **monorepo**. While all scripts live together in this single Git repository, each folder represents an independent project or utility with its own isolated ecosystem.

## 🗂️ Directory Structure

- `1-Disk-Usage-Monitoring-with-Email-Alert`
- `2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)`
- `3-Automated-Database-Backup-with-Timestamp`
- `4-Service-Monitor-And-Auto-Restart`
- `5-CPU-and-Memory-Usage-Monitor`
- `6-Website-Availability-(HTTP-Health-Check)`
- `7-Find-and-Kill-High-CPU-Processes`
- `8-Log-Rotation-and-Compression`
- `9-Automated-Git-Deployment`
- `10-Kubernetes-Pod-Monitor-and-Restart`
- `11-Scheduling-And-Automation` *(Home to EventOps)*

## 🔄 CI/CD Philosophy (GitHub Actions)

Because this is a monorepo, **CI/CD pipelines are strictly segregated by folder**. 
There is no "global" build. Instead, each script/project has its own dedicated GitHub Actions workflow file in `.github/workflows/`. 

Pipelines use `paths` filters to trigger *only* when code inside that specific script's folder is modified. For example, modifying a file in `11-Scheduling-And-Automation/EventOps/` will only trigger the `ci-eventops.yml` pipeline, leaving the rest of the repository untouched.

## 📜 License
This entire repository is open source and available under the [MIT License](LICENSE).

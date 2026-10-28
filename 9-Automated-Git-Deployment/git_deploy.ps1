<#
.SYNOPSIS
    Automated Git Deployment.

.DESCRIPTION
    Deploys the latest version of an application from a Git repository:
    pre-deployment backup, fetch, pull when behind, post-deployment tasks.
    Exit codes:
      0  success (up-to-date or deployed)
      1  configuration or safety violation
      2  partial failure
#>

param(
    [string]$AppDir = "C:\inetpub\wwwroot\myapp",
    [string]$RepoUrl = "https://github.com/company/myapp.git",
    [string]$Branch = "main",
    [string]$BackupDir = "C:\Backups\Deployments",
    [switch]$SkipBackup,
    [switch]$SkipPostDeploy,
    [string]$Service = "IIS",
    [switch]$DryRun,
    [string]$AuditLog = "",
    [switch]$Verbose,
    [switch]$Help
)

$ErrorActionPreference = "Continue"

$Colors = @{
    Red    = "`e[31m"
    Green  = "`e[32m"
    Yellow = "`e[33m"
    Blue   = "`e[34m"
    Cyan   = "`e[36m"
    Bold   = "`e[1m"
    Reset  = "`e[0m"
}

$Script:Deployed = $false
$Script:FailedCount = 0

function Write-AuditLog {
    param([string]$Level = "INFO", [string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($AuditLog)) {
        $Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        try {
            $LogParent = [System.IO.Path]::GetDirectoryName($AuditLog)
            if (-not [string]::IsNullOrEmpty($LogParent) -and -not (Test-Path -LiteralPath $LogParent)) {
                New-Item -ItemType Directory -Path $LogParent -Force | Out-Null
            }
            Add-Content -LiteralPath $AuditLog -Value "$Timestamp [$Level] $Message" -ErrorAction SilentlyContinue
        } catch { $null = $_ }
    }
}

function Show-Help {
    Write-Host "Automated Git Deployment Utility (PowerShell)"
    Write-Host "Usage: .\git_deploy.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Optional Arguments:"
    Write-Host "  -AppDir <path>        Application directory (default: C:\inetpub\wwwroot\myapp)."
    Write-Host "  -RepoUrl <url>        Repository URL."
    Write-Host "  -Branch <name>        Branch to deploy (default: main)."
    Write-Host "  -BackupDir <path>     Backup directory (default: C:\Backups\Deployments)."
    Write-Host "  -SkipBackup           Skip pre-deploy backup."
    Write-Host "  -SkipPostDeploy       Skip npm install and service restart."
    Write-Host "  -Service <name>       Service to restart (default: IIS)."
    Write-Host "  -DryRun               Preview only."
    Write-Host "  -AuditLog <file>      Append ISO-8601 audit log entries."
    Write-Host "  -Verbose              Enable diagnostic output."
    Write-Host "  -Help                 Show this help and usage documentation."
}

function Test-ProtectedPath {
    param([string]$Path)
    $protected = @("C:\", "C:\Windows", "C:\Program Files", "/", "/etc", "/var", "/tmp", "/home", "/usr", "/bin")
    $parent = ""
    try { $parent = [System.IO.Path]::GetDirectoryName($Path) } catch { $parent = "" }
    if ([string]::IsNullOrEmpty($parent)) { $parent = $Path }
    $norm = $parent.TrimEnd('\', '/')
    if ($norm -eq "") { $norm = "/" }
    foreach ($p in $protected) {
        $pp = $p.TrimEnd('\', '/')
        if ($pp -eq "") { $pp = "/" }
        if ($norm -eq $pp) { return $true }
    }
    return $false
}

function Test-ValidBranch {
    param([string]$Name)
    return ($Name -match '^[a-zA-Z0-9._/-]+$')
}

if ($Help) { Show-Help; exit 0 }

# Validation
if ([string]::IsNullOrWhiteSpace($AppDir)) { Write-Host "$($Colors.Red)Error: App directory is required.$($Colors.Reset)"; exit 1 }
if ([string]::IsNullOrWhiteSpace($Branch)) { Write-Host "$($Colors.Red)Error: Branch is required.$($Colors.Reset)"; exit 1 }
if (-not (Test-ValidBranch $Branch)) { Write-Host "$($Colors.Red)Error: Invalid branch name '$Branch'.$($Colors.Reset)"; exit 1 }
if (Test-ProtectedPath $AppDir) { Write-Host "$($Colors.Red)Error: App directory '$AppDir' is in a protected system directory.$($Colors.Reset)"; exit 1 }
if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) { Write-Host "$($Colors.Red)Error: App directory '$AppDir' does not exist or is not a directory.$($Colors.Reset)"; exit 1 }
if (Test-ProtectedPath $BackupDir) { Write-Host "$($Colors.Red)Error: Backup directory '$BackupDir' is in a protected system directory.$($Colors.Reset)"; exit 1 }

# Header
Write-Host "============================================================" -ForegroundColor Blue
Write-Host "            DevOps Git Deployment Utility                  " -ForegroundColor Blue
Write-Host "============================================================" -ForegroundColor Blue
Write-Host "App Directory    : $($Colors.Cyan)$AppDir$($Colors.Reset)"
Write-Host "Repository       : $($Colors.Cyan)$RepoUrl$($Colors.Reset)"
Write-Host "Branch           : $($Colors.Cyan)$Branch$($Colors.Reset)"
Write-Host "Backup Directory : $($Colors.Cyan)$BackupDir$($Colors.Reset)"
Write-Host "Skip Backup      : $($Colors.Cyan)$SkipBackup$($Colors.Reset)"
Write-Host "Skip Post-Deploy : $($Colors.Cyan)$SkipPostDeploy$($Colors.Reset)"
if (-not [string]::IsNullOrWhiteSpace($AuditLog)) {
    Write-Host "Audit Log        : $($Colors.Cyan)$AuditLog$($Colors.Reset)"
}
Write-Host ""

# Dry-run
if ($DryRun) {
    Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would deploy '$AppDir' from $RepoUrl ($Branch)."
    if (-not $SkipBackup) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would create backup in $BackupDir." }
    Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would git fetch origin $Branch."
    Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would git pull origin $Branch if behind."
    if (-not $SkipPostDeploy) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would run post-deploy (npm install if package.json; restart $Service)." }
    Write-AuditLog -Level "INFO" -Message "[DRY RUN] Deploy planned for '$AppDir'."
    exit 0
}

Set-Location -LiteralPath $AppDir

# Backup
if (-not $SkipBackup) {
    Write-Host "$($Colors.Yellow)Creating backup...$($Colors.Reset)" -ForegroundColor Yellow
    $Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $BackupFile = Join-Path $BackupDir "backup_$Timestamp.zip"
    try {
        if (-not (Test-Path -LiteralPath $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }
        Compress-Archive -Path "$AppDir\*" -DestinationPath $BackupFile -Force -ErrorAction Stop
        Write-Host "$($Colors.Green)✓ Backup created: $BackupFile$($Colors.Reset)" -ForegroundColor Green
        Write-AuditLog -Level "INFO" -Message "Backup created: $BackupFile"
    } catch {
        Write-Host "$($Colors.Red)✗ Backup failed: $($_.Exception.Message)$($Colors.Reset)" -ForegroundColor Red
        $Script:FailedCount++
        Write-AuditLog -Level "ERROR" -Message "Backup failed."
    }
}

# Fetch
Write-Host ""
Write-Host "$($Colors.Yellow)Fetching updates...$($Colors.Reset)" -ForegroundColor Yellow
$fetchOk = $true
try {
    & git fetch origin $Branch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $fetchOk = $false }
} catch { $fetchOk = $false }

if (-not $fetchOk) {
    Write-Host "$($Colors.Red)✗ Git fetch failed.$($Colors.Reset)" -ForegroundColor Red
    $Script:FailedCount++
    Write-AuditLog -Level "ERROR" -Message "Git fetch failed."
}

$localRev = ""
$remoteRev = ""
try { $localRev = (& git rev-parse HEAD 2>$null).Trim() } catch { $localRev = "" }
try { $remoteRev = (& git rev-parse "origin/$Branch" 2>$null).Trim() } catch { $remoteRev = "" }

if (-not [string]::IsNullOrWhiteSpace($localRev) -and $localRev -eq $remoteRev) {
    Write-Host "$($Colors.Green)✓ Already up to date$($Colors.Reset)" -ForegroundColor Green
    Write-AuditLog -Level "INFO" -Message "Already up to date ($AppDir)."
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "                    Execution Summary                       " -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "App Directory    : $($Colors.Bold)$AppDir$($Colors.Reset)"
    Write-Host "Result           : $($Colors.Green)already up to date$($Colors.Reset)"
    Write-Host "Failed Steps     : $($Colors.Red)$($Script:FailedCount)$($Colors.Reset)"
    Write-Host "============================================================" -ForegroundColor Blue
    if ($Script:FailedCount -gt 0) { exit 2 }
    exit 0
}

Write-Host "$($Colors.Yellow)Changes detected. Deploying...$($Colors.Reset)" -ForegroundColor Yellow

# Pull
$pullOk = $false
try {
    & git pull origin $Branch
    if ($LASTEXITCODE -eq 0) { $pullOk = $true }
} catch { $pullOk = $false }

if ($pullOk) {
    Write-Host "$($Colors.Green)✓ Code updated$($Colors.Reset)" -ForegroundColor Green
    $Script:Deployed = $true
    Write-AuditLog -Level "INFO" -Message "Code updated ($AppDir)."

    if (-not $SkipPostDeploy) {
        Write-Host ""
        Write-Host "$($Colors.Yellow)Running post-deployment tasks...$($Colors.Reset)" -ForegroundColor Yellow
        if (Test-Path -LiteralPath "package.json") {
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                try {
                    & npm install
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "$($Colors.Green)✓ Dependencies installed$($Colors.Reset)" -ForegroundColor Green
                    } else {
                        Write-Host "$($Colors.Red)✗ npm install failed.$($Colors.Reset)" -ForegroundColor Red
                        $Script:FailedCount++
                        Write-AuditLog -Level "ERROR" -Message "npm install failed."
                    }
                } catch {
                    Write-Host "$($Colors.Red)✗ npm install failed: $($_.Exception.Message)$($Colors.Reset)" -ForegroundColor Red
                    $Script:FailedCount++
                    Write-AuditLog -Level "ERROR" -Message "npm install failed."
                }
            } else {
                Write-Host "$($Colors.Yellow)⚠ npm not found, skipping.$($Colors.Reset)" -ForegroundColor Yellow
            }
        }
        # Service restart
        if (Get-Command "iisreset" -ErrorAction SilentlyContinue) {
            try {
                & iisreset /restart 2>&1 | Out-Null
                Write-Host "$($Colors.Green)✓ Service $Service restarted$($Colors.Reset)" -ForegroundColor Green
            } catch {
                Write-Host "$($Colors.Red)✗ Service restart failed.$($Colors.Reset)" -ForegroundColor Red
                $Script:FailedCount++
                Write-AuditLog -Level "ERROR" -Message "Service restart failed ($Service)."
            }
        } else {
            Write-Host "$($Colors.Yellow)⚠ iisreset not found, skipping service restart.$($Colors.Reset)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "$($Colors.Red)✗ Git pull failed$($Colors.Reset)" -ForegroundColor Red
    $Script:FailedCount++
    Write-AuditLog -Level "ERROR" -Message "Git pull failed ($AppDir)."
}

# Summary
Write-Host ""
Write-Host "============================================================" -ForegroundColor Blue
Write-Host "                    Execution Summary                       " -ForegroundColor Blue
Write-Host "============================================================" -ForegroundColor Blue
Write-Host "App Directory    : $($Colors.Bold)$AppDir$($Colors.Reset)"
$ResultText = if ($Script:Deployed) { "deployed" } else { "failed" }
Write-Host "Result           : $($Colors.Bold)$ResultText$($Colors.Reset)"
Write-Host "Failed Steps     : $($Colors.Red)$($Script:FailedCount)$($Colors.Reset)"
Write-Host "============================================================" -ForegroundColor Blue

if ($Script:FailedCount -gt 0) {
    Write-AuditLog -Level "ERROR" -Message "Completed with failures (failed=$($Script:FailedCount))."
    exit 2
}
Write-AuditLog -Level "INFO" -Message "Deployment completed ($AppDir)."
exit 0
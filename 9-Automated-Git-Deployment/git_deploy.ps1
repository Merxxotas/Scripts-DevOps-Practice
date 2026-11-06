<#
.SYNOPSIS
    Automated Git Deployment.

.DESCRIPTION
    Deploys the latest version of an application from a Git repository:
    verified pre-deployment backup (created AND checked before any fetch;
    failure aborts the run), fetch, pull when behind, and automatic rollback
    to the pre-deploy revision if the pull fails (disable with -NoRollback).
    Post-deployment tasks run only on a successful pull.
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
    [switch]$NoRollback,
    [string]$Service = "IIS",
    [switch]$DryRun,
    [string]$AuditLog = "",
    [switch]$Json,
    [switch]$Csv,
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
$Script:RolledBack = $false

# Output mode
$outputMode = "human"
if ($Json -and $Csv) { Write-Host "$($Colors.Red)Error: Cannot use -Json and -Csv together.$($Colors.Reset)" -ForegroundColor Red; exit 1 }
if ($Json) { $outputMode = "json" } elseif ($Csv) { $outputMode = "csv" }
$humanMode = ($outputMode -eq "human")

# Strip embedded credentials (user[:pass]@) from a repo URL for display/logs.
# git@host:path carries no secret (the user is the literal "git") and is left as-is.
function Get-ScrubbedRepoUrl {
    param([string]$Url)
    $m = [regex]::Match($Url, '^([a-zA-Z][a-zA-Z0-9+.-]*://)([^/@]*@)?(.*)$')
    if ($m.Success) { return $m.Groups[1].Value + $m.Groups[3].Value }
    return $Url
}

# Normalize a repo URL for identity comparison: lowercase, strip credentials,
# map git@host:path onto host/path, drop scheme, trailing slashes and .git.
function Get-NormalizedRepoUrl {
    param([string]$Url)
    $u = (Get-ScrubbedRepoUrl $Url).ToLower()
    $m = [regex]::Match($u, '^git@([^:]+):(.+)$')
    if ($m.Success) {
        $u = "$($m.Groups[1].Value)/$($m.Groups[2].Value)"
    } else {
        $idx = $u.IndexOf('://')
        if ($idx -ge 0) { $u = $u.Substring($idx + 3) }
    }
    $u = $u.TrimEnd('/')
    if ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }
    return $u
}

# Create a backup zip with .NET ZipArchive. Compress-Archive is NOT usable:
# on PowerShell 7 (Unix) it cannot add hidden dotfiles at all (verified
# 2026-11-06), and it cannot represent an empty tree as a valid archive.
function New-DeployBackup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$SourceRoot, [string]$DestinationPath)
    if (-not $PSCmdlet.ShouldProcess($DestinationPath, "Create deployment backup")) { return }
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch { $null = $_ }
    if (Test-Path -LiteralPath $DestinationPath) { Remove-Item -LiteralPath $DestinationPath -Force }
    $srcRoot = $SourceRoot.TrimEnd('\', '/')
    $zip = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force)) {
            $rel = $file.FullName.Substring($srcRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $es = $entry.Open()
            $fs = [System.IO.File]::OpenRead($file.FullName)
            try { $fs.CopyTo($es) } finally { $fs.Dispose(); $es.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }
}

# Verify a backup archive entry-by-entry: same file set as the source tree and
# matching SHA-256 per entry. Works on empty archives. Never extracts to disk.
function Test-BackupArchive {
    param([string]$ZipPath, [string]$SourceRoot)
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch { $null = $_ }
    $srcRoot = $SourceRoot.TrimEnd('\', '/')
    $srcMap = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($srcRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $srcMap[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $dstMap = @{}
        foreach ($entry in $zip.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) { continue } # directory entry
            $rel = ($entry.FullName -replace '\\', '/').TrimStart('/')
            $s = $entry.Open()
            try { $dstMap[$rel] = (Get-FileHash -InputStream $s -Algorithm SHA256).Hash } finally { $s.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }
    if ($srcMap.Count -ne $dstMap.Count) { return $false }
    foreach ($key in $srcMap.Keys) {
        if (-not $dstMap.ContainsKey($key) -or $dstMap[$key] -ne $srcMap[$key]) { return $false }
    }
    return $true
}

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
    Write-Host "  -RepoUrl <url>        Repository URL. If passed, aborts when the configured origin differs (normalized comparison)."
    Write-Host "  -Branch <name>        Branch to deploy (default: main)."
    Write-Host "  -BackupDir <path>     Backup directory (default: C:\Backups\Deployments)."
    Write-Host "  -SkipBackup           Skip pre-deploy backup."
    Write-Host "  -SkipPostDeploy       Skip npm install and service restart."
    Write-Host "  -NoRollback           Do not roll back to the pre-deploy revision if the pull fails."
    Write-Host "  -Service <name>       Service to restart (default: IIS)."
    Write-Host "  -DryRun               Preview only."
    Write-Host "  -AuditLog <file>      Append ISO-8601 audit log entries."
    Write-Host "  -Json                 Output result as JSON."
    Write-Host "  -Csv                  Output result as CSV."
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

# Repo pre-flight (before any banner or mutation): the app dir must be a git
# work tree, and an explicitly passed -RepoUrl must match origin.
& git -C $AppDir rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "$($Colors.Red)Error: App directory '$AppDir' is not a git repository.$($Colors.Reset)" -ForegroundColor Red; exit 1 }
$originUrl = (& git -C $AppDir remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0) { $originUrl = "" } else { $originUrl = "$originUrl".Trim() }
if ($PSBoundParameters.ContainsKey('RepoUrl')) {
    if ([string]::IsNullOrWhiteSpace($originUrl)) { Write-Host "$($Colors.Red)Error: -RepoUrl was provided but no 'origin' remote is configured in '$AppDir'.$($Colors.Reset)" -ForegroundColor Red; exit 1 }
    $want = Get-ScrubbedRepoUrl $RepoUrl
    $have = Get-ScrubbedRepoUrl $originUrl
    if ((Get-NormalizedRepoUrl $want) -ne (Get-NormalizedRepoUrl $have)) { Write-Host "$($Colors.Red)Error: -RepoUrl does not match the configured origin ($want vs $have).$($Colors.Reset)" -ForegroundColor Red; exit 1 }
    $RepoUrl = $want
} elseif (-not [string]::IsNullOrWhiteSpace($originUrl)) {
    $RepoUrl = Get-ScrubbedRepoUrl $originUrl
}

# Header
if ($humanMode) {
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
}

# Dry-run
if ($DryRun) {
    if ($humanMode) {
        Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would deploy '$AppDir' from $RepoUrl ($Branch)."
        if (-not $SkipBackup) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would create backup in $BackupDir." }
        Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would git fetch origin $Branch."
        Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would git pull origin $Branch if behind."
        if ($NoRollback) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Rollback disabled (-NoRollback)." }
        else { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would roll back to the pre-deploy revision if the pull fails (disable with -NoRollback)." }
        if (-not $SkipPostDeploy) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would run post-deploy (npm install if package.json; restart $Service)." }
    }
    Write-AuditLog -Level "INFO" -Message "[DRY RUN] Deploy planned for '$AppDir'."
    if ($outputMode -eq "json") {
        Write-Host "{"
        Write-Host "  `"app_dir`": `"$AppDir`","
        Write-Host "  `"repo_url`": `"$RepoUrl`","
        Write-Host "  `"branch`": `"$Branch`","
        Write-Host "  `"result`": `"dry-run`","
        Write-Host "  `"failed`": 0"
        Write-Host "}"
    } elseif ($outputMode -eq "csv") {
        Write-Host "app_dir,repo_url,branch,result,failed"
        Write-Host "`"$AppDir`",`"$RepoUrl`",`"$Branch`",`"dry-run`",0"
    }
    exit 0
}

Set-Location -LiteralPath $AppDir

# Backup (created AND verified BEFORE any fetch; failure aborts the deploy)
if (-not $SkipBackup) {
    if ($humanMode) { Write-Host "$($Colors.Yellow)Creating backup...$($Colors.Reset)" -ForegroundColor Yellow }
    $Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $BackupFile = Join-Path $BackupDir "backup_$Timestamp.zip"
    $backupOk = $true
    $backupError = ""
    try {
        if (Test-Path -LiteralPath $BackupDir) {
            if (-not (Test-Path -LiteralPath $BackupDir -PathType Container)) {
                throw "Backup directory path exists and is not a directory: $BackupDir"
            }
        } else {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }
        New-DeployBackup -SourceRoot $AppDir -DestinationPath $BackupFile
        if (-not (Test-BackupArchive -ZipPath $BackupFile -SourceRoot $AppDir)) {
            throw "Backup verification failed: archive contents do not match the app directory."
        }
        if ($humanMode) { Write-Host "$($Colors.Green)✓ Backup created and verified: $BackupFile$($Colors.Reset)" -ForegroundColor Green }
        Write-AuditLog -Level "INFO" -Message "Backup created: $BackupFile"
        Write-AuditLog -Level "INFO" -Message "Backup verified: $BackupFile"
    } catch {
        $backupOk = $false
        $backupError = $_.Exception.Message
    }
    if (-not $backupOk) {
        if ($humanMode) {
            if ($backupError) { Write-Host "$($Colors.Red)✗ Backup failed: $backupError$($Colors.Reset)" -ForegroundColor Red }
            Write-Host "$($Colors.Red)✗ Backup failed.$($Colors.Reset)" -ForegroundColor Red
            Write-Host "$($Colors.Red)Deploy aborted: backup failed.$($Colors.Reset)" -ForegroundColor Red
        }
        Write-AuditLog -Level "ERROR" -Message "Backup failed."
        if ($outputMode -eq "json") {
            Write-Host "{"
            Write-Host "  `"app_dir`": `"$AppDir`","
            Write-Host "  `"repo_url`": `"$RepoUrl`","
            Write-Host "  `"branch`": `"$Branch`","
            Write-Host "  `"result`": `"failed`","
            Write-Host "  `"failed`": 1"
            Write-Host "}"
        } elseif ($outputMode -eq "csv") {
            Write-Host "app_dir,repo_url,branch,result,failed"
            Write-Host "`"$AppDir`",`"$RepoUrl`",`"$Branch`",`"failed`",1"
        }
        exit 2
    }
}

# Fetch
if ($humanMode) { Write-Host ""; Write-Host "$($Colors.Yellow)Fetching updates...$($Colors.Reset)" -ForegroundColor Yellow }
$fetchOk = $true
try {
    & git fetch origin $Branch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $fetchOk = $false }
} catch { $fetchOk = $false }

if (-not $fetchOk) {
    if ($humanMode) { Write-Host "$($Colors.Red)✗ Git fetch failed.$($Colors.Reset)" -ForegroundColor Red }
    $Script:FailedCount++
    Write-AuditLog -Level "ERROR" -Message "Git fetch failed."
}

$localRev = ""
$remoteRev = ""
try { $localRev = (& git rev-parse HEAD 2>$null).Trim() } catch { $localRev = "" }
try { $remoteRev = (& git rev-parse "origin/$Branch" 2>$null).Trim() } catch { $remoteRev = "" }

if (-not [string]::IsNullOrWhiteSpace($localRev) -and $localRev -eq $remoteRev) {
    if ($humanMode) { Write-Host "$($Colors.Green)✓ Already up to date$($Colors.Reset)" -ForegroundColor Green }
    Write-AuditLog -Level "INFO" -Message "Already up to date ($AppDir)."
    if ($humanMode) {
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Blue
        Write-Host "                    Execution Summary                       " -ForegroundColor Blue
        Write-Host "============================================================" -ForegroundColor Blue
        Write-Host "App Directory    : $($Colors.Bold)$AppDir$($Colors.Reset)"
        Write-Host "Result           : $($Colors.Green)already up to date$($Colors.Reset)"
        Write-Host "Failed Steps     : $($Colors.Red)$($Script:FailedCount)$($Colors.Reset)"
        Write-Host "============================================================" -ForegroundColor Blue
    }
    if ($outputMode -eq "json") {
        Write-Host "{"
        Write-Host "  `"app_dir`": `"$AppDir`","
        Write-Host "  `"repo_url`": `"$RepoUrl`","
        Write-Host "  `"branch`": `"$Branch`","
        Write-Host "  `"result`": `"up-to-date`","
        Write-Host "  `"failed`": $($Script:FailedCount)"
        Write-Host "}"
    } elseif ($outputMode -eq "csv") {
        Write-Host "app_dir,repo_url,branch,result,failed"
        Write-Host "`"$AppDir`",`"$RepoUrl`",`"$Branch`",`"up-to-date`",$($Script:FailedCount)"
    }
    if ($Script:FailedCount -gt 0) { exit 2 }
    exit 0
}

if ($humanMode) { Write-Host "$($Colors.Yellow)Changes detected. Deploying...$($Colors.Reset)" -ForegroundColor Yellow }

# Pull
$pullOk = $false
try {
    & git pull origin $Branch
    if ($LASTEXITCODE -eq 0) { $pullOk = $true }
} catch { $pullOk = $false }

if ($pullOk) {
    if ($humanMode) { Write-Host "$($Colors.Green)✓ Code updated$($Colors.Reset)" -ForegroundColor Green }
    $Script:Deployed = $true
    Write-AuditLog -Level "INFO" -Message "Code updated ($AppDir)."

    if (-not $SkipPostDeploy) {
        if ($humanMode) { Write-Host ""; Write-Host "$($Colors.Yellow)Running post-deployment tasks...$($Colors.Reset)" -ForegroundColor Yellow }
        if (Test-Path -LiteralPath "package.json") {
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                try {
                    & npm install
                    if ($LASTEXITCODE -eq 0) {
                        if ($humanMode) { Write-Host "$($Colors.Green)✓ Dependencies installed$($Colors.Reset)" -ForegroundColor Green }
                    } else {
                        if ($humanMode) { Write-Host "$($Colors.Red)✗ npm install failed.$($Colors.Reset)" -ForegroundColor Red }
                        $Script:FailedCount++
                        Write-AuditLog -Level "ERROR" -Message "npm install failed."
                    }
                } catch {
                    if ($humanMode) { Write-Host "$($Colors.Red)✗ npm install failed: $($_.Exception.Message)$($Colors.Reset)" -ForegroundColor Red }
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
                if ($humanMode) { Write-Host "$($Colors.Green)✓ Service $Service restarted$($Colors.Reset)" -ForegroundColor Green }
            } catch {
                if ($humanMode) { Write-Host "$($Colors.Red)✗ Service restart failed.$($Colors.Reset)" -ForegroundColor Red }
                $Script:FailedCount++
                Write-AuditLog -Level "ERROR" -Message "Service restart failed ($Service)."
            }
        } else {
            Write-Host "$($Colors.Yellow)⚠ iisreset not found, skipping service restart.$($Colors.Reset)" -ForegroundColor Yellow
        }
    }
} else {
    if ($humanMode) { Write-Host "$($Colors.Red)✗ Git pull failed$($Colors.Reset)" -ForegroundColor Red }
    $Script:FailedCount++
    Write-AuditLog -Level "ERROR" -Message "Git pull failed ($AppDir)."
    if ($NoRollback) {
        if ($humanMode) { Write-Host "$($Colors.Yellow)⚠ Rollback disabled (-NoRollback); working tree left as-is.$($Colors.Reset)" -ForegroundColor Yellow }
        Write-AuditLog -Level "INFO" -Message "Rollback disabled (-NoRollback); tree left as-is ($AppDir)."
    } elseif (-not [string]::IsNullOrWhiteSpace($localRev)) {
        & git -C $AppDir reset --hard $localRev 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $Script:RolledBack = $true
            if ($humanMode) { Write-Host "$($Colors.Yellow)Rolled back to $localRev (files restored; service NOT restarted).$($Colors.Reset)" -ForegroundColor Yellow }
            Write-AuditLog -Level "INFO" -Message "Rolled back to $localRev ($AppDir)."
        } else {
            if ($humanMode) { Write-Host "$($Colors.Red)✗ Rollback failed.$($Colors.Reset)" -ForegroundColor Red }
            Write-AuditLog -Level "ERROR" -Message "Rollback failed ($AppDir)."
        }
    } else {
        if ($humanMode) { Write-Host "$($Colors.Yellow)⚠ Rollback skipped: pre-deploy revision unknown.$($Colors.Reset)" -ForegroundColor Yellow }
        Write-AuditLog -Level "ERROR" -Message "Rollback skipped: pre-deploy revision unknown ($AppDir)."
    }
}

# Summary
$ResultText = if ($Script:RolledBack) { "rolled-back" } elseif ($Script:Deployed) { "deployed" } else { "failed" }
if ($humanMode) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "                    Execution Summary                       " -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "App Directory    : $($Colors.Bold)$AppDir$($Colors.Reset)"
    Write-Host "Result           : $($Colors.Bold)$ResultText$($Colors.Reset)"
    Write-Host "Failed Steps     : $($Colors.Red)$($Script:FailedCount)$($Colors.Reset)"
    Write-Host "============================================================" -ForegroundColor Blue
}
if ($outputMode -eq "json") {
    Write-Host "{"
    Write-Host "  `"app_dir`": `"$AppDir`","
    Write-Host "  `"repo_url`": `"$RepoUrl`","
    Write-Host "  `"branch`": `"$Branch`","
    Write-Host "  `"result`": `"$ResultText`","
    Write-Host "  `"failed`": $($Script:FailedCount)"
    Write-Host "}"
} elseif ($outputMode -eq "csv") {
    Write-Host "app_dir,repo_url,branch,result,failed"
    Write-Host "`"$AppDir`",`"$RepoUrl`",`"$Branch`",`"$ResultText`",$($Script:FailedCount)"
}

if ($Script:FailedCount -gt 0) {
    Write-AuditLog -Level "ERROR" -Message "Completed with failures (failed=$($Script:FailedCount))."
    exit 2
}
Write-AuditLog -Level "INFO" -Message "Deployment completed ($AppDir)."
exit 0

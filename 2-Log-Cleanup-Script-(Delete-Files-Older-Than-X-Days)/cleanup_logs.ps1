#Requires -Version 5.1
<#
.SYNOPSIS
    Enterprise-grade log cleanup and retention utility.

.DESCRIPTION
    Scans, filters, and purges stale log files based on retention days, file glob patterns,
    and size thresholds with safety guardrails against critical directory purging.

.PARAMETER LogDirectory
    Target directory path containing the log files to clean.

.PARAMETER Days
    Retention threshold in days. Files modified older than X days are purged (Default: 30).

.PARAMETER Pattern
    Filename glob matching pattern (Default: "*.log").

.PARAMETER MinSizeMB
    Minimum file size threshold in Megabytes to qualify for cleanup (Default: 0).

.PARAMETER Recursive
    Switch to enable deep traversal through child directories.

.PARAMETER DryRun
    Simulation switch to preview operations and projected storage savings without deleting.

.PARAMETER LogFile
    Optional file path to persist ISO-8601 audit records.

.EXAMPLE
    .\cleanup_logs.ps1 -LogDirectory "C:\Logs\App" -Days 14 -DryRun

.EXAMPLE
    .\cleanup_logs.ps1 -LogDirectory "C:\Logs\App" -Days 30 -Pattern "*.log" -Recursive -MinSizeMB 5.0 -LogFile "C:\Logs\audit.log"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Target directory path to clean.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 36500)]
    [int]$Days = 30,

    [Parameter(Mandatory = $false)]
    [string]$Pattern = "*.log",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 1048576)]
    [double]$MinSizeMB = 0.0,

    [Parameter(Mandatory = $false)]
    [switch]$Recursive,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ANSI Color mapping
$Colors = @{
    Red    = "$([char]27)[0;31m"
    Green  = "$([char]27)[0;32m"
    Yellow = "$([char]27)[1;33m"
    Blue   = "$([char]27)[0;34m"
    Cyan   = "$([char]27)[0;36m"
    Bold   = "$([char]27)[1m"
    Reset  = "$([char]27)[0m"
}

# Metrics counters
$Script:TotalScanned = 0
$Script:EligibleCount = 0
$Script:DeletedCount = 0
$Script:FailedCount = 0
$Script:TotalReclaimedBytes = [long]0

# Logs structured messages to persistent logfile
function Write-AuditLog {
    param(
        [string]$Level = "INFO",
        [string]$Message
    )

    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        $Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $LogEntry = "$Timestamp [$Level] $Message"
        try {
            $LogParent = [System.IO.Path]::GetDirectoryName($LogFile)
            if (-not [string]::IsNullOrEmpty($LogParent) -and -not (Test-Path -LiteralPath $LogParent)) {
                New-Item -ItemType Directory -Path $LogParent -Force | Out-Null
            }
            Add-Content -LiteralPath $LogFile -Value $LogEntry -ErrorAction SilentlyContinue
        } catch {
            # Non-blocking logging failure
        }
    }
}

# Formats byte integers into human-readable strings
function Format-ByteSize {
    param([long]$Bytes)

    if ($Bytes -lt 1KB) {
        return "$Bytes B"
    } elseif ($Bytes -lt 1MB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } elseif ($Bytes -lt 1GB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } else {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
}

# Validates path against critical system root directories
function Test-SafetyGuardrails {
    param([string]$Path)

    try {
        $ResolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        $ResolvedPath = [System.IO.Path]::GetFullPath($Path)
    }

    $Blacklist = @(
        "C:\",
        "C:\Windows",
        "C:\Windows\System32",
        "C:\Program Files",
        "C:\Program Files (x86)",
        "C:\Users",
        "C:\ProgramData",
        "/",
        "/bin",
        "/sbin",
        "/usr",
        "/usr/bin",
        "/etc",
        "/dev",
        "/proc",
        "/sys",
        "/boot",
        "/root",
        "/var",
        "/home",
        "/private",
        "/private/etc",
        "/private/var",
        "/private/tmp"
    )

    $NormalizedTarget = $Path.TrimEnd('\', '/')
    $NormalizedResolved = $ResolvedPath.TrimEnd('\', '/')

    foreach ($Blocked in $Blacklist) {
        $NormalizedBlocked = $Blocked.TrimEnd('\', '/')
        if ([string]::Equals($NormalizedTarget, $NormalizedBlocked, [System.StringComparison]::OrdinalIgnoreCase) -or 
            [string]::Equals($NormalizedResolved, $NormalizedBlocked, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "$($Colors.Red)Error: Safety violation! Target directory '$Path' is a protected system root.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Execution blocked: Target directory '$Path' is a protected system root."
            return $false
        }
    }

    return $true
}

# Main script orchestration
function Invoke-LogCleanup {
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        Write-Host "$($Colors.Red)Error: Target directory '$LogDirectory' does not exist or is not a directory.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Target directory does not exist: $LogDirectory"
        exit 1
    }

    if (-not (Test-SafetyGuardrails -Path $LogDirectory)) {
        exit 1
    }

    $ResolvedDir = (Resolve-Path -LiteralPath $LogDirectory).ProviderPath
    $NormalizedRootDir = $ResolvedDir.TrimEnd('\', '/')
    $CutoffDate = (Get-Date).AddDays(-$Days)
    $MinSizeBytes = [long]($MinSizeMB * 1MB)

    Write-AuditLog -Level "INFO" -Message "Log cleanup initiated for '$ResolvedDir' (Retention: ${Days}d, Pattern: '$Pattern', Recursive: $Recursive, DryRun: $DryRun, MinSizeMB: $MinSizeMB)"

    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)                DevOps Log Cleanup Utility                  $($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "Target Directory : $($Colors.Cyan)$ResolvedDir$($Colors.Reset)"
    Write-Host "Retention Policy : $($Colors.Yellow)Older than $Days days$($Colors.Reset)"
    Write-Host "Matching Pattern : $($Colors.Cyan)$Pattern$($Colors.Reset)"
    Write-Host "Min Size Filter  : $($Colors.Cyan)$MinSizeMB MB$($Colors.Reset)"
    Write-Host "Recursive Scan   : $($Colors.Cyan)$Recursive$($Colors.Reset)"
    $ModeText = if ($DryRun) { "$($Colors.Yellow)DRY RUN (Simulation)$($Colors.Reset)" } else { "$($Colors.Green)LIVE (Deletions Active)$($Colors.Reset)" }
    Write-Host "Execution Mode   : $ModeText"
    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        Write-Host "Audit Log File   : $($Colors.Cyan)$LogFile$($Colors.Reset)"
    }
    Write-Host "`n$($Colors.Blue)Scanning target files...$($Colors.Reset)"

    if ($Recursive) {
        $Files = Get-ChildItem -LiteralPath $ResolvedDir -Filter $Pattern -File -Force -Recurse -ErrorAction SilentlyContinue
    } else {
        $Files = Get-ChildItem -LiteralPath $ResolvedDir -Filter $Pattern -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Directory.FullName.TrimEnd('\', '/') -eq $NormalizedRootDir
            }
    }

    foreach ($File in $Files) {
        $Script:TotalScanned++
        
        if ($File.LastWriteTime -le $CutoffDate) {
            if ($File.Length -ge $MinSizeBytes) {
                $Script:EligibleCount++
                $Script:TotalReclaimedBytes += $File.Length

                $FormattedSize = Format-ByteSize -Bytes $File.Length
                $AgeDays = [int]((Get-Date) - $File.LastWriteTime).TotalDays

                if ($DryRun) {
                    Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would delete: $($File.FullName) ($FormattedSize, $AgeDays days old)"
                    Write-AuditLog -Level "INFO" -Message "[DRY RUN] Would delete: $($File.FullName) (Size: $FormattedSize, Age: ${AgeDays}d)"
                    $Script:DeletedCount++
                } else {
                    try {
                        Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
                        Write-Host "$($Colors.Green)✓ Deleted:$($Colors.Reset) $($File.FullName) ($FormattedSize, $AgeDays days old)"
                        Write-AuditLog -Level "INFO" -Message "DELETED: $($File.FullName) (Size: $FormattedSize, Age: ${AgeDays}d)"
                        $Script:DeletedCount++
                    } catch {
                        Write-Host "$($Colors.Red)✗ Failed to delete:$($Colors.Reset) $($File.FullName) - $($_.Exception.Message)"
                        Write-AuditLog -Level "ERROR" -Message "FAILED to delete: $($File.FullName) - $($_.Exception.Message)"
                        $Script:FailedCount++
                    }
                }
            } elseif ($PSBoundParameters.ContainsKey('Verbose') -and $Verbose) {
                Write-Host "$($Colors.Cyan)[SKIP - SIZE]$($Colors.Reset) $($File.FullName) is below minimum size threshold"
            }
        } elseif ($PSBoundParameters.ContainsKey('Verbose') -and $Verbose) {
            Write-Host "$($Colors.Cyan)[SKIP - AGE]$($Colors.Reset) $($File.FullName) is within retention period"
        }
    }

    $TotalSpaceFormatted = Format-ByteSize -Bytes $Script:TotalReclaimedBytes

    Write-Host "`n$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)                    Execution Summary                       $($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "Total Files Scanned : $($Colors.Bold)$Script:TotalScanned$($Colors.Reset)"
    Write-Host "Eligible for Purge  : $($Colors.Bold)$Script:EligibleCount$($Colors.Reset)"
    Write-Host "Files Processed     : $($Colors.Green)$Script:DeletedCount$($Colors.Reset)"
    Write-Host "Failed Deletions    : $($Colors.Red)$Script:FailedCount$($Colors.Reset)"
    Write-Host "Storage Reclaimed   : $($Colors.Bold)$($Colors.Green)$TotalSpaceFormatted$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"

    Write-AuditLog -Level "INFO" -Message "Cleanup completed: Scanned=$Script:TotalScanned, Eligible=$Script:EligibleCount, Processed=$Script:DeletedCount, Failed=$Script:FailedCount, Reclaimed=$TotalSpaceFormatted"

    if ($Script:FailedCount -gt 0) {
        exit 2
    }

    exit 0
}

Invoke-LogCleanup

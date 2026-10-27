<#
.SYNOPSIS
    Log Rotation and Compression.

.DESCRIPTION
    Rotates a single log file when it grows beyond a size threshold: shifts
    existing rotated backups, compresses the current log into the first backup
    slot, truncates the active log, and prunes backups older than the retention
    count. Supports gzip (Bash) / zip (PowerShell). Exit codes:
      0  success (rotation performed, no-op, or dry-run)
      1  configuration or safety violation
      2  partial failure (rename, compression, truncation or prune step failed)
#>

param(
    [string]$LogFile = "C:\Logs\application.log",
    [ValidateRange(0, 1048576)]
    [int]$MaxSizeMB = 10,
    [ValidateRange(1, 1048576)]
    [int]$BackupCount = 5,
    [switch]$Compress,
    [switch]$NoCompress,
    [switch]$Force,
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

$Script:Rotated = $false
$Script:FailedCount = 0

function Write-AuditLog {
    param(
        [string]$Level = "INFO",
        [string]$Message
    )

    if (-not [string]::IsNullOrWhiteSpace($AuditLog)) {
        $Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $LogEntry = "$Timestamp [$Level] $Message"
        try {
            $LogParent = [System.IO.Path]::GetDirectoryName($AuditLog)
            if (-not [string]::IsNullOrEmpty($LogParent) -and -not (Test-Path -LiteralPath $LogParent)) {
                New-Item -ItemType Directory -Path $LogParent -Force | Out-Null
            }
            Add-Content -LiteralPath $AuditLog -Value $LogEntry -ErrorAction SilentlyContinue
        } catch {
            $null = $_
        }
    }
}

function Show-Help {
    Write-Host "Log Rotation and Compression Utility (PowerShell)"
    Write-Host "Usage: .\log_rotate.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Optional Arguments:"
    Write-Host "  -LogFile <path>       Target log file (default: C:\Logs\application.log)."
    Write-Host "  -MaxSizeMB <n>        Rotation threshold in megabytes (default: 10)."
    Write-Host "  -BackupCount <n>      Number of rotated backups to retain (default: 5)."
    Write-Host "  -Compress             Compress the rotated backup (default)."
    Write-Host "  -NoCompress           Keep the rotated backup raw (no compression)."
    Write-Host "  -Force                Rotate regardless of file size."
    Write-Host "  -DryRun               Preview actions without touching anything."
    Write-Host "  -AuditLog <file>      Append ISO-8601 audit log entries."
    Write-Host "  -Verbose              Enable diagnostic output."
    Write-Host "  -Help                 Show this help and usage documentation."
}

function Get-FileSize {
    param([string]$Path)
    try {
        return (Get-Item -LiteralPath $Path).Length
    } catch {
        return 0
    }
}

function Test-SafetyGuardrail {
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
        "/tmp",
        "/home",
        "/private",
        "/private/etc",
        "/private/var",
        "/private/tmp",
        "/Library",
        "/System",
        "/Applications",
        "/Volumes"
    )

    $Parent = [System.IO.Path]::GetDirectoryName($ResolvedPath)
    if ([string]::IsNullOrEmpty($Parent)) { $Parent = $ResolvedPath }

    $NormalizedParent = $Parent.TrimEnd('\', '/')

    foreach ($Blocked in $Blacklist) {
        $NormalizedBlocked = $Blocked.TrimEnd('\', '/')
        if ([string]::Equals($NormalizedParent, $NormalizedBlocked, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "$($Colors.Red)Error: Safety violation! Log file '$Path' is in a protected system directory.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Execution blocked: log file '$Path' in protected directory '$Parent'."
            return $false
        }
    }

    return $true
}

function Get-BackupName {
    param([int]$Index)
    $DoCompress = if ($NoCompress) { $false } else { $true }
    if ($Compress) { $DoCompress = $true }
    if ($NoCompress) { $DoCompress = $false }
    if ($DoCompress) {
        return "$LogFile.$Index.zip"
    } else {
        return "$LogFile.$Index"
    }
}

function Invoke-LogRotate {
    if ($Help) {
        Show-Help
        exit 0
    }

    # Compression flag resolution: default on unless -NoCompress
    $Script:DoCompress = $true
    if ($NoCompress) { $Script:DoCompress = $false }
    if ($Compress) { $Script:DoCompress = $true }

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        Write-Host "$($Colors.Red)Error: Log file path is required.$($Colors.Reset)"
        exit 1
    }

    if (-not (Test-Path -LiteralPath $LogFile)) {
        Write-Host "$($Colors.Red)Error: Log file '$LogFile' does not exist.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Log file does not exist: $LogFile"
        exit 1
    }
    $Item = Get-Item -LiteralPath $LogFile
    if ($Item.PSIsContainer) {
        Write-Host "$($Colors.Red)Error: Log file '$LogFile' is a directory.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Log file is a directory: $LogFile"
        exit 1
    }

    if (-not (Test-SafetyGuardrail -Path $LogFile)) {
        exit 1
    }

    $FileSize = Get-FileSize -Path $LogFile
    $MaxSizeBytes = [long]$MaxSizeMB * 1048576

    $Resolved = $LogFile
    try { $Resolved = (Resolve-Path -LiteralPath $LogFile).ProviderPath } catch { $null = $_ }

    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)            DevOps Log Rotation Utility                    $($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "Log File         : $($Colors.Cyan)$Resolved$($Colors.Reset)"
    Write-Host "Current Size     : $($Colors.Cyan)$FileSize bytes$($Colors.Reset)"
    Write-Host "Max Size         : $($Colors.Cyan)$MaxSizeMB MB ($MaxSizeBytes bytes)$($Colors.Reset)"
    Write-Host "Backup Count     : $($Colors.Cyan)$BackupCount$($Colors.Reset)"
    Write-Host "Compression      : $($Colors.Cyan)$Script:DoCompress$($Colors.Reset)"
    if (-not [string]::IsNullOrWhiteSpace($AuditLog)) {
        Write-Host "Audit Log        : $($Colors.Cyan)$AuditLog$($Colors.Reset)"
    }
    Write-Host ""

    $NeedRotate = $false
    if ($Force) { $NeedRotate = $true }
    elseif ($FileSize -gt $MaxSizeBytes) { $NeedRotate = $true }

    if (-not $NeedRotate) {
        Write-Host "$($Colors.Green)No rotation needed (size $FileSize <= threshold $MaxSizeBytes).$($Colors.Reset)"
        Write-AuditLog -Level "INFO" -Message "No rotation needed for '$Resolved' (size=$FileSize, threshold=$MaxSizeBytes)."
        exit 0
    }

    if ($DryRun) {
        Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Rotation planned for '$Resolved':"
        for ($i = $BackupCount; $i -ge 1; $i--) {
            $src = Get-BackupName -Index $i
            $dst = Get-BackupName -Index ($i + 1)
            if (Test-Path -LiteralPath $src) {
                Write-Host "  $($Colors.Yellow)[DRY RUN]$($Colors.Reset) would move $src -> $dst"
            }
        }
        $slot1 = Get-BackupName -Index 1
        Write-Host "  $($Colors.Yellow)[DRY RUN]$($Colors.Reset) would copy $LogFile -> $slot1"
        if ($Script:DoCompress) {
            Write-Host "  $($Colors.Yellow)[DRY RUN]$($Colors.Reset) would compress $LogFile -> $slot1"
        }
        Write-Host "  $($Colors.Yellow)[DRY RUN]$($Colors.Reset) would truncate $LogFile"
        $pruneIdx = $BackupCount + 1
        $pruneName = Get-BackupName -Index $pruneIdx
        if (Test-Path -LiteralPath $pruneName) {
            Write-Host "  $($Colors.Yellow)[DRY RUN]$($Colors.Reset) would remove $pruneName"
        }
        Write-AuditLog -Level "INFO" -Message "[DRY RUN] Rotation planned for '$Resolved'."
        exit 0
    }

    Write-Host "$($Colors.Yellow)Rotating...$($Colors.Reset)"

    # Shift existing backups from highest down
    for ($i = $BackupCount; $i -ge 1; $i--) {
        $src = Get-BackupName -Index $i
        $dst = Get-BackupName -Index ($i + 1)
        if (Test-Path -LiteralPath $src) {
            if ($Verbose) { Write-Host "  shifting $src -> $dst" }
            try {
                Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
            } catch {
                Write-Host "$($Colors.Red)✗ Failed to move $src -> $dst$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "Failed to move $src -> $dst"
                $Script:FailedCount++
            }
        }
    }

    $slot1 = Get-BackupName -Index 1
    $rawSlot = "$LogFile.1"

    if ($Verbose) { Write-Host "  copying $LogFile -> $rawSlot" }
    try {
        Copy-Item -LiteralPath $LogFile -Destination $rawSlot -Force -ErrorAction Stop
    } catch {
        Write-Host "$($Colors.Red)✗ Failed to copy $LogFile -> $rawSlot$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Failed to copy $LogFile -> $rawSlot"
        $Script:FailedCount++
    }

    if ($Script:FailedCount -eq 0) {
        if ($Script:DoCompress) {
            if ($Verbose) { Write-Host "  compressing $rawSlot -> $slot1" }
            try {
                Compress-Archive -LiteralPath $rawSlot -DestinationPath $slot1 -Force -ErrorAction Stop
                Remove-Item -LiteralPath $rawSlot -Force -ErrorAction SilentlyContinue
                Write-Host "$($Colors.Green)✓ Rotated to $slot1$($Colors.Reset)"
                $Script:Rotated = $true
            } catch {
                Write-Host "$($Colors.Red)✗ Compression failed for $rawSlot$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "Compression failed for $rawSlot"
                $Script:FailedCount++
            }
        } else {
            # rawSlot already correct name? rename to slot1 if different
            if ($rawSlot -ne $slot1) {
                try {
                    Move-Item -LiteralPath $rawSlot -Destination $slot1 -Force -ErrorAction Stop
                } catch {
                    Write-Host "$($Colors.Red)✗ Failed to move $rawSlot -> $slot1$($Colors.Reset)"
                    $Script:FailedCount++
                }
            }
            Write-Host "$($Colors.Green)✓ Rotated to $slot1$($Colors.Reset)"
            $Script:Rotated = $true
        }
    }

    # Truncate current log
    if ($Script:FailedCount -eq 0) {
        if ($Verbose) { Write-Host "  truncating $LogFile" }
        try {
            Clear-Content -LiteralPath $LogFile -ErrorAction Stop
        } catch {
            Write-Host "$($Colors.Red)✗ Failed to truncate $LogFile$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Failed to truncate $LogFile"
            $Script:FailedCount++
        }
    }

    # Prune beyond backup count
    $pruneIdx = $BackupCount + 1
    $pruneName = Get-BackupName -Index $pruneIdx
    if (Test-Path -LiteralPath $pruneName) {
        if ($Verbose) { Write-Host "  pruning $pruneName" }
        try {
            Remove-Item -LiteralPath $pruneName -Force -ErrorAction Stop
            Write-Host "$($Colors.Yellow)✓ Removed old backup $pruneName$($Colors.Reset)"
        } catch {
            Write-Host "$($Colors.Red)✗ Failed to remove $pruneName$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Failed to remove $pruneName"
            $Script:FailedCount++
        }
    }

    Write-Host ""
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)                    Execution Summary                       $($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "Log File         : $($Colors.Bold)$Resolved$($Colors.Reset)"
    Write-Host "Rotated          : $($Colors.Bold)$Script:Rotated$($Colors.Reset)"
    Write-Host "Backup Count     : $($Colors.Bold)$BackupCount$($Colors.Reset)"
    Write-Host "Failed Steps     : $($Colors.Red)$Script:FailedCount$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"

    if ($Script:FailedCount -gt 0) {
        Write-AuditLog -Level "ERROR" -Message "Rotation completed with failures for '$Resolved' (failed=$Script:FailedCount)."
        exit 2
    }

    Write-AuditLog -Level "INFO" -Message "Rotation completed for '$Resolved' (backup=$slot1)."
    exit 0
}

Invoke-LogRotate
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
    [switch]$Help,
    [switch]$Json,
    [switch]$Csv
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
$Script:OutputMode = "human"

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
    Write-Host "  -Json                 Output result as JSON."
    Write-Host "  -Csv                  Output result as CSV."
}

function Get-FileSize {
    param([string]$Path)
    try {
        return (Get-Item -LiteralPath $Path).Length
    } catch {
        return 0
    }
}

# Canonicalize a path the way realpath(1) does: absolute, normalized, with
# every symlink in the path resolved (bounded hops against ELOOP cycles).
# Resolve-Path does NOT resolve OS symlinks, so it is not a substitute.
# The final component is left unresolved: directory resolution is what the
# safety guard needs, and file opens follow links anyway.
function Get-RealPath {
    param([string]$Path)

    $current = [System.IO.Path]::GetFullPath($Path)

    for ($hop = 0; $hop -lt 40; $hop++) {
        $current = [System.IO.Path]::GetFullPath($current)
        $root = [System.IO.Path]::GetPathRoot($current)
        $relative = $current.Substring($root.Length)
        $parts = @($relative -split '[/\\]' | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $acc = $root
        $expanded = $false

        for ($i = 0; $i -lt $parts.Count; $i++) {
            $candidate = Join-Path $acc $parts[$i]
            $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
            $target = $null
            if ($null -ne $item) { $target = $item.LinkTarget }
            if (-not [string]::IsNullOrEmpty($target)) {
                $expandedBase = if ([System.IO.Path]::IsPathRooted($target)) {
                    [System.IO.Path]::GetFullPath($target)
                } else {
                    [System.IO.Path]::GetFullPath((Join-Path $acc $target))
                }
                $current = $expandedBase
                for ($j = $i + 1; $j -lt $parts.Count; $j++) {
                    $current = Join-Path $current $parts[$j]
                }
                $expanded = $true
                break
            }
            $acc = $candidate
        }

        if (-not $expanded) { return [System.IO.Path]::GetFullPath($acc) }
    }

    return $current
}

# Two classes of protection, checked against BOTH the given path's parent
# and the fully resolved path's parent (module 2 port):
#   1. Full-tree roots (this root and everything under it) — system-owned
#      trees where rotation is never legitimate.
#   2. Exact-match roots — these roots themselves are protected, but their
#      children are the tool's legitimate targets (e.g. C:\Logs\App).
function Test-SafetyGuardrail {
    param([string]$Path)

    $ResolvedPath = Get-RealPath -Path $Path

    function ConvertTo-GuardPath {
        param([string]$p)
        $n = $p.TrimEnd('\', '/') -replace '\\', '/'
        if ([string]::IsNullOrEmpty($n)) { return '/' }
        $n = $n.TrimEnd('/')
        if ($n -match '^[A-Za-z]:$') { return "$n/" }
        return $n
    }

    # System-owned trees: refuse the root itself and every subtree below it.
    # Drive roots ("C:/") are exact-only; handled by the exact-match list.
    $FullTreeRoots = @(
        "/bin",
        "/sbin",
        "/usr",
        "/usr/bin",
        "/usr/sbin",
        "/etc",
        "/dev",
        "/proc",
        "/sys",
        "/boot",
        "/root",
        "/private/etc",
        "C:/Windows"
    )

    # Roots whose children are legitimate log directories.
    $ExactOnlyRoots = @(
        "/",
        "/var",
        "/var/run",
        "/var/log",
        "/tmp",
        "/home",
        "/private",
        "/private/var",
        "/private/tmp",
        "/Library",
        "/System",
        "/Applications",
        "/Volumes",
        "C:/",
        "C:/Program Files",
        "C:/Program Files (x86)",
        "C:/ProgramData",
        "C:/Users"
    )

    $UserProfile = [Environment]::GetFolderPath("UserProfile")
    if ([string]::IsNullOrEmpty($UserProfile)) { $UserProfile = $HOME }
    if (-not [string]::IsNullOrEmpty($UserProfile)) {
        $ExactOnlyRoots += (ConvertTo-GuardPath $UserProfile)
        # Also refuse the canonical home: a symlinked HOME must not smuggle
        # the guard past its own exact-match root (bash has this arm).
        $ExactOnlyRoots += (ConvertTo-GuardPath (Get-RealPath -Path $UserProfile))
    }
    if (-not [string]::IsNullOrEmpty($HOME)) {
        $ExactOnlyRoots += (ConvertTo-GuardPath $HOME)
        $ExactOnlyRoots += (ConvertTo-GuardPath (Get-RealPath -Path $HOME))
    }

    $InputParent = [System.IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrEmpty($InputParent)) { $InputParent = $Path }
    $ResolvedParent = [System.IO.Path]::GetDirectoryName($ResolvedPath)
    if ([string]::IsNullOrEmpty($ResolvedParent)) { $ResolvedParent = $ResolvedPath }

    foreach ($Candidate in @((ConvertTo-GuardPath $InputParent), (ConvertTo-GuardPath $ResolvedParent))) {
        if ([string]::IsNullOrEmpty($Candidate)) { continue }

        foreach ($Root in $FullTreeRoots) {
            if ([string]::Equals($Candidate, $Root, [System.StringComparison]::OrdinalIgnoreCase) -or
                $Candidate.StartsWith($Root + "/", [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "$($Colors.Red)Error: Safety violation! Log file '$Path' is inside the protected system tree '$Root'.$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "Execution blocked: log file '$Path' is inside the protected system tree '$Root'."
                return $false
            }
        }

        foreach ($Root in $ExactOnlyRoots) {
            if ([string]::Equals($Candidate, $Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "$($Colors.Red)Error: Safety violation! Log file '$Path' is a protected system root.$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "Execution blocked: log file '$Path' is a protected system root '$Root'."
                return $false
            }
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

    if ($Json -and $Csv) {
        Write-Host "$($Colors.Red)Error: Cannot use -Json and -Csv together.$($Colors.Reset)"
        exit 1
    }
    if ($Json) { $Script:OutputMode = "json" }
    elseif ($Csv) { $Script:OutputMode = "csv" }
    else { $Script:OutputMode = "human" }

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

    $Resolved = Get-RealPath -Path $LogFile

    if ($Script:OutputMode -eq "human") {
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
    }

    $NeedRotate = $false
    if ($Force) { $NeedRotate = $true }
    elseif ($FileSize -gt $MaxSizeBytes) { $NeedRotate = $true }

    if (-not $NeedRotate) {
        if ($Script:OutputMode -eq "human") {
            Write-Host "$($Colors.Green)No rotation needed (size $FileSize <= threshold $MaxSizeBytes).$($Colors.Reset)"
        }
        Write-AuditLog -Level "INFO" -Message "No rotation needed for '$Resolved' (size=$FileSize, threshold=$MaxSizeBytes)."
        if ($Script:OutputMode -eq "json") {
            $compress = if ($Script:DoCompress) { "true" } else { "false" }
            Write-Host "{`n  `"log_file`": `"$Resolved`",`n  `"current_size_bytes`": $FileSize,`n  `"max_size_bytes`": $MaxSizeBytes,`n  `"backup_count`": $BackupCount,`n  `"compress`": $compress,`n  `"rotated`": false,`n  `"failed_steps`": 0,`n  `"outcome`": `"no-rotation-needed`"`n}"
        } elseif ($Script:OutputMode -eq "csv") {
            $compress = if ($Script:DoCompress) { "true" } else { "false" }
            Write-Host "log_file,current_size_bytes,max_size_bytes,backup_count,compress,rotated,failed_steps,outcome"
            Write-Host "`"$Resolved`",$FileSize,$MaxSizeBytes,$BackupCount,$compress,false,0,`"no-rotation-needed`""
        }
        exit 0
    }

    if ($DryRun) {
        if ($Script:OutputMode -eq "human") {
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
        }
        Write-AuditLog -Level "INFO" -Message "[DRY RUN] Rotation planned for '$Resolved'."
        if ($Script:OutputMode -eq "json") {
            $compress = if ($Script:DoCompress) { "true" } else { "false" }
            Write-Host "{`n  `"log_file`": `"$Resolved`",`n  `"current_size_bytes`": $FileSize,`n  `"max_size_bytes`": $MaxSizeBytes,`n  `"backup_count`": $BackupCount,`n  `"compress`": $compress,`n  `"rotated`": false,`n  `"failed_steps`": 0,`n  `"outcome`": `"dry-run`"`n}"
        } elseif ($Script:OutputMode -eq "csv") {
            $compress = if ($Script:DoCompress) { "true" } else { "false" }
            Write-Host "log_file,current_size_bytes,max_size_bytes,backup_count,compress,rotated,failed_steps,outcome"
            Write-Host "`"$Resolved`",$FileSize,$MaxSizeBytes,$BackupCount,$compress,false,0,`"dry-run`""
        }
        exit 0
    }

    if ($Script:OutputMode -eq "human") { Write-Host "$($Colors.Yellow)Rotating...$($Colors.Reset)" }

    # Shift existing backups from highest down
    for ($i = $BackupCount; $i -ge 1; $i--) {
        $src = Get-BackupName -Index $i
        $dst = Get-BackupName -Index ($i + 1)
        if (Test-Path -LiteralPath $src) {
            if ($Verbose -and $Script:OutputMode -eq "human") { Write-Host "  shifting $src -> $dst" }
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

    if ($Verbose -and $Script:OutputMode -eq "human") { Write-Host "  copying $LogFile -> $rawSlot" }
    $CopyOk = $false
    $HashOriginal = $null
    try {
        Copy-Item -LiteralPath $LogFile -Destination $rawSlot -Force -ErrorAction Stop
        $CopyOk = $true
    } catch {
        Write-Host "$($Colors.Red)✗ Failed to copy $LogFile -> $rawSlot$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Failed to copy $LogFile -> $rawSlot"
        $Script:FailedCount++
    }

    # A backup that does not match the original is worse than none: never
    # truncate a log we cannot restore byte-for-byte.
    if ($CopyOk) {
        try {
            $HashOriginal = (Get-FileHash -LiteralPath $LogFile -Algorithm SHA256).Hash
            $HashCopy = (Get-FileHash -LiteralPath $rawSlot -Algorithm SHA256).Hash
        } catch {
            $HashOriginal = $null
            $HashCopy = $null
        }
        if ([string]::IsNullOrEmpty($HashOriginal) -or ($HashOriginal -ne $HashCopy)) {
            Write-Host "$($Colors.Red)✗ Backup copy '$rawSlot' does not match '$LogFile'; refusing to truncate.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Backup copy $rawSlot failed hash comparison against $LogFile; truncation refused."
            $Script:FailedCount++
            $CopyOk = $false
        }
    }

    if ($Script:FailedCount -eq 0) {
        if ($Script:DoCompress) {
            if ($Verbose -and $Script:OutputMode -eq "human") { Write-Host "  compressing $rawSlot -> $slot1" }
            $VerifyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("log_rotate_verify_" + [System.Guid]::NewGuid().ToString("N"))
            try {
                Compress-Archive -LiteralPath $rawSlot -DestinationPath $slot1 -Force -ErrorAction Stop
                New-Item -ItemType Directory -Path $VerifyDir -Force | Out-Null
                Expand-Archive -LiteralPath $slot1 -DestinationPath $VerifyDir -Force -ErrorAction Stop
                $Extracted = Get-ChildItem -LiteralPath $VerifyDir -File | Select-Object -First 1
                $HashZip = $null
                if ($null -ne $Extracted) {
                    $HashZip = (Get-FileHash -LiteralPath $Extracted.FullName -Algorithm SHA256).Hash
                }
                if (-not [string]::IsNullOrEmpty($HashZip) -and $HashZip -eq $HashOriginal) {
                    Remove-Item -LiteralPath $rawSlot -Force -ErrorAction SilentlyContinue
                    if ($Script:OutputMode -eq "human") { Write-Host "$($Colors.Green)✓ Rotated to $slot1$($Colors.Reset)" }
                    $Script:Rotated = $true
                } else {
                    Write-Host "$($Colors.Red)✗ Compressed backup '$slot1' failed integrity verification; refusing to truncate.$($Colors.Reset)"
                    Write-AuditLog -Level "ERROR" -Message "Compressed backup $slot1 failed integrity verification; truncation refused."
                    # Keep both artifacts for inspection; do not truncate.
                    $Script:FailedCount++
                }
            } catch {
                Write-Host "$($Colors.Red)✗ Compressed backup '$slot1' failed integrity verification; refusing to truncate.$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "Compressed backup $slot1 failed verification: $($_.Exception.Message); truncation refused."
                $Script:FailedCount++
            } finally {
                Remove-Item -LiteralPath $VerifyDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            # rawSlot already equals slot1 in no-compress mode and is hash-verified.
            if ($rawSlot -ne $slot1) {
                try {
                    Move-Item -LiteralPath $rawSlot -Destination $slot1 -Force -ErrorAction Stop
                } catch {
                    Write-Host "$($Colors.Red)✗ Failed to move $rawSlot -> $slot1$($Colors.Reset)"
                    Write-AuditLog -Level "ERROR" -Message "Failed to move $rawSlot -> $slot1"
                    $Script:FailedCount++
                }
            }
            if ($Script:FailedCount -eq 0) {
                # rawSlot (now the artifact) is hash-verified against the original.
                if ($Script:OutputMode -eq "human") { Write-Host "$($Colors.Green)✓ Rotated to $slot1$($Colors.Reset)" }
                $Script:Rotated = $true
            }
        }
    }

    # Truncate current log
    if ($Script:FailedCount -eq 0) {
        if ($Verbose -and $Script:OutputMode -eq "human") { Write-Host "  truncating $LogFile" }
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
        if ($Verbose -and $Script:OutputMode -eq "human") { Write-Host "  pruning $pruneName" }
        try {
            Remove-Item -LiteralPath $pruneName -Force -ErrorAction Stop
            if ($Script:OutputMode -eq "human") { Write-Host "$($Colors.Yellow)✓ Removed old backup $pruneName$($Colors.Reset)" }
        } catch {
            Write-Host "$($Colors.Red)✗ Failed to remove $pruneName$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Failed to remove $pruneName"
            $Script:FailedCount++
        }
    }

    $CurrentSize = Get-FileSize -Path $LogFile
    if ($Script:OutputMode -eq "human") {
        Write-Host ""
        Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
        Write-Host "$($Colors.Blue)$($Colors.Bold)                    Execution Summary                       $($Colors.Reset)"
        Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
        Write-Host "Log File         : $($Colors.Bold)$Resolved$($Colors.Reset)"
        Write-Host "Rotated          : $($Colors.Bold)$Script:Rotated$($Colors.Reset)"
        Write-Host "Backup Count     : $($Colors.Bold)$BackupCount$($Colors.Reset)"
        Write-Host "Failed Steps     : $($Colors.Red)$Script:FailedCount$($Colors.Reset)"
        Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    }

    if ($Script:OutputMode -eq "json") {
        $compress = if ($Script:DoCompress) { "true" } else { "false" }
        $rotated = if ($Script:Rotated) { "true" } else { "false" }
        $outcome = if ($Script:FailedCount -gt 0) { "failed" } else { "rotated" }
        Write-Host "{`n  `"log_file`": `"$Resolved`",`n  `"current_size_bytes`": $CurrentSize,`n  `"max_size_bytes`": $MaxSizeBytes,`n  `"backup_count`": $BackupCount,`n  `"compress`": $compress,`n  `"rotated`": $rotated,`n  `"failed_steps`": $($Script:FailedCount),`n  `"outcome`": `"$outcome`"`n}"
    } elseif ($Script:OutputMode -eq "csv") {
        $compress = if ($Script:DoCompress) { "true" } else { "false" }
        $rotated = if ($Script:Rotated) { "true" } else { "false" }
        $outcome = if ($Script:FailedCount -gt 0) { "failed" } else { "rotated" }
        Write-Host "log_file,current_size_bytes,max_size_bytes,backup_count,compress,rotated,failed_steps,outcome"
        Write-Host "`"$Resolved`",$CurrentSize,$MaxSizeBytes,$BackupCount,$compress,$rotated,$($Script:FailedCount),`"$outcome`""
    }

    if ($Script:FailedCount -gt 0) {
        Write-AuditLog -Level "ERROR" -Message "Rotation completed with failures for '$Resolved' (failed=$Script:FailedCount)."
        exit 2
    }

    Write-AuditLog -Level "INFO" -Message "Rotation completed for '$Resolved' (backup=$slot1)."
    exit 0
}

Invoke-LogRotate
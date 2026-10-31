<#
.SYNOPSIS
    Find and Kill High-CPU Processes.
.DESCRIPTION
    Lists processes whose CPU usage exceeds a threshold and, on confirmation
    (or automatically), terminates them.
#>
param(
    [ValidateRange(0, 1048576)]
    [double]$CpuThreshold = 50.0,
    [switch]$AutoKill,
    [switch]$Force,
    [switch]$DryRun,
    [string]$AuditLog = "",
    [switch]$Json,
    [switch]$Csv,
    [switch]$Verbose,
    [switch]$Help
)
$ErrorActionPreference = "Continue"
$Colors = @{ Red="`e[31m"; Green="`e[32m"; Yellow="`e[33m"; Blue="`e[34m"; Cyan="`e[36m"; Bold="`e[1m"; Reset="`e[0m" }
$Script:KilledCount = 0
$Script:FailedCount = 0
$outputMode = "human"
if ($Json -and $Csv) { Write-Host "$($Colors.Red)Error: Cannot use -Json and -Csv together.$($Colors.Reset)" -ForegroundColor Red; exit 1 }
if ($Json) { $outputMode = "json" } elseif ($Csv) { $outputMode = "csv" }
$humanMode = ($outputMode -eq "human")

function Write-AuditLog {
    param([string]$Level="INFO",[string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($AuditLog)) {
        $Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        try {
            $LogParent = [System.IO.Path]::GetDirectoryName($AuditLog)
            if (-not [string]::IsNullOrEmpty($LogParent) -and -not (Test-Path -LiteralPath $LogParent)) { New-Item -ItemType Directory -Path $LogParent -Force | Out-Null }
            Add-Content -LiteralPath $AuditLog -Value "$Timestamp [$Level] $Message" -ErrorAction SilentlyContinue
        } catch { $null = $_ }
    }
}
function Show-Help {
    Write-Host "Find and Kill High-CPU Processes Utility (PowerShell)"
    Write-Host "Usage: .\kill_high_cpu.ps1 [OPTIONS]"
    Write-Host "  -CpuThreshold <n>  CPU % threshold (default 50.0)"
    Write-Host "  -AutoKill          Kill all candidates without prompting."
    Write-Host "  -Force             Use Stop-Process -Force."
    Write-Host "  -DryRun            Preview candidates."
    Write-Host "  -AuditLog <file>   Audit log path."
    Write-Host "  -Json              Output JSON."
    Write-Host "  -Csv               Output CSV."
    Write-Host "  -Verbose           Verbose."
    Write-Host "  -Help              Help."
}
function Test-GuardedPid {
    param([int]$Id)
    if ($Id -le 1) { return $true }
    if ($Id -eq $PID) { return $true }
    try { $parent=(Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId; if ($Id -eq $parent) { return $true } } catch { $null=$_ }
    return $false
}
function Get-Candidates {
    $now = Get-Date; $list = @()
    try { $procs = Get-Process -ErrorAction Stop } catch { $procs = @() }
    foreach ($p in $procs) {
        if (Test-GuardedPid -Id $p.Id) { continue }
        if ([string]::IsNullOrWhiteSpace($p.ProcessName)) { continue }
        $cpuPercent = 0.0
        try { if ($p.StartTime -ne $null) { $elapsed = ($now - $p.StartTime).TotalSeconds; if ($elapsed -gt 0) { $cpuPercent = [math]::Round(($p.CPU / $elapsed) * 100, 2) } } } catch { $cpuPercent = 0.0 }
        if ($cpuPercent -gt $CpuThreshold) { $list += [pscustomobject]@{ Id=$p.Id; ProcessName=$p.ProcessName; CpuPercent=$cpuPercent } }
    }
    return $list
}
if ($Help) { Show-Help; exit 0 }
if ($humanMode) {
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "            DevOps High-CPU Killer Utility                 " -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "Threshold        : $($Colors.Cyan)$CpuThreshold%$($Colors.Reset)"
    Write-Host "Auto-Kill        : $($Colors.Cyan)$AutoKill$($Colors.Reset)"
    Write-Host "Force            : $($Colors.Cyan)$Force$($Colors.Reset)"
    if (-not [string]::IsNullOrWhiteSpace($AuditLog)) { Write-Host "Audit Log        : $($Colors.Cyan)$AuditLog$($Colors.Reset)" }
    Write-Host ""
}
$candidates = Get-Candidates
$candidateCount = $candidates.Count
if ($humanMode) { Write-Host "$($Colors.Yellow)Found $candidateCount candidate(s).$($Colors.Reset)" -ForegroundColor Yellow; Write-Host "" }
if ($DryRun) {
    if ($candidateCount -eq 0) {
        if ($humanMode) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) No candidates to kill." }
        Write-AuditLog -Level "INFO" -Message "[DRY RUN] No candidates (threshold=$CpuThreshold)."
        if ($outputMode -eq "json") { Write-Host "{`n  `"threshold`": $CpuThreshold,`n  `"candidates`": [],`n  `"killed`": 0,`n  `"failed`": 0,`n  `"outcome`": `"dry-run`"`n}" }
        elseif ($outputMode -eq "csv") { Write-Host "pid,pcpu,comm,action" }
        exit 0
    }
    if ($humanMode) { foreach ($c in $candidates) { Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would kill PID $($c.Id) ($($c.ProcessName)) at $($c.CpuPercent)% CPU" } }
    Write-AuditLog -Level "INFO" -Message "[DRY RUN] $candidateCount candidate(s) (threshold=$CpuThreshold)."
    if ($outputMode -eq "json") {
        $jsonCands = @(); foreach ($c in $candidates) { $jsonCands += "{`"pid`": $($c.Id), `"pcpu`": $($c.CpuPercent), `"comm`": `"$($c.ProcessName)`", `"action`": `"would-kill`"}" }
        $candStr = $jsonCands -join ", "
        Write-Host "{`n  `"threshold`": $CpuThreshold,`n  `"candidates`": [$candStr],`n  `"killed`": 0,`n  `"failed`": 0,`n  `"outcome`": `"dry-run`"`n}"
    } elseif ($outputMode -eq "csv") {
        Write-Host "pid,pcpu,comm,action"
        foreach ($c in $candidates) { Write-Host "$($c.Id),$($c.CpuPercent),`"$($c.ProcessName)`",`"would-kill`"" }
    }
    exit 0
}
if ($candidateCount -eq 0) {
    if ($humanMode) { Write-Host "$($Colors.Green)No processes exceeding $CpuThreshold% CPU.$($Colors.Reset)" -ForegroundColor Green }
    Write-AuditLog -Level "INFO" -Message "No high-CPU processes found (threshold=$CpuThreshold)."
    if ($outputMode -eq "json") { Write-Host "{`n  `"threshold`": $CpuThreshold,`n  `"candidates`": [],`n  `"killed`": 0,`n  `"failed`": 0,`n  `"outcome`": `"none`"`n}" }
    elseif ($outputMode -eq "csv") { Write-Host "pid,pcpu,comm,action" }
    exit 0
}
$actions = @()
foreach ($c in $candidates) {
    if ($humanMode) {
        Write-Host "$($Colors.Red)High CPU detected:$($Colors.Reset)" -ForegroundColor Red
        Write-Host "  Command : $($Colors.Yellow)$($c.ProcessName)$($Colors.Reset)"
        Write-Host "  PID     : $($Colors.Cyan)$($c.Id)$($Colors.Reset)"
        Write-Host "  CPU     : $($Colors.Red)$($c.CpuPercent)%$($Colors.Reset)"
    }
    $doKill = $false
    if ($AutoKill) { $doKill = $true } else {
        $choice = "n"
        if ($humanMode) { $choice = Read-Host "Kill this process? (y/n)" }
        if ($choice -eq 'y' -or $choice -eq 'Y') { $doKill = $true }
    }
    $action = "skipped"
    if ($doKill) {
        try {
            if ($Force) { Stop-Process -Id $c.Id -Force -ErrorAction Stop } else { Stop-Process -Id $c.Id -ErrorAction Stop }
            if ($humanMode) { Write-Host "$($Colors.Green)✓ Process $($c.Id) killed.$($Colors.Reset)" -ForegroundColor Green }
            $Script:KilledCount++
            $action = "killed"
            Write-AuditLog -Level "INFO" -Message "Killed PID $($c.Id) ($($c.ProcessName))."
        } catch {
            if ($humanMode) { Write-Host "$($Colors.Red)✗ Failed to kill process $($c.Id): $($_.Exception.Message)$($Colors.Reset)" -ForegroundColor Red }
            $Script:FailedCount++
            $action = "failed"
            Write-AuditLog -Level "ERROR" -Message "Failed to kill PID $($c.Id) ($($c.ProcessName)): $($_.Exception.Message)"
        }
    } else {
        if ($humanMode) { Write-Host "$($Colors.Yellow)Skipped.$($Colors.Reset)" -ForegroundColor Yellow }
    }
    $actions += $action
    if ($humanMode) { Write-Host "" }
}
if ($humanMode) {
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "                    Execution Summary                       " -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "Threshold        : $($Colors.Bold)$CpuThreshold%$($Colors.Reset)"
    Write-Host "Candidates       : $($Colors.Bold)$candidateCount$($Colors.Reset)"
    Write-Host "Killed           : $($Colors.Green)$($Script:KilledCount)$($Colors.Reset)"
    Write-Host "Failed           : $($Colors.Red)$($Script:FailedCount)$($Colors.Reset)"
    Write-Host "============================================================" -ForegroundColor Blue
}
if ($outputMode -eq "json") {
    $jsonCands = @(); $i = 0
    foreach ($c in $candidates) {
        $jsonCands += "{`"pid`": $($c.Id), `"pcpu`": $($c.CpuPercent), `"comm`": `"$($c.ProcessName)`", `"action`": `"$($actions[$i])`"}"
        $i++
    }
    $candStr = $jsonCands -join ", "
    $outcome = "completed"; if ($Script:FailedCount -gt 0) { $outcome = "partial" }
    Write-Host "{`n  `"threshold`": $CpuThreshold,`n  `"candidates`": [$candStr],`n  `"killed`": $($Script:KilledCount),`n  `"failed`": $($Script:FailedCount),`n  `"outcome`": `"$outcome`"`n}"
} elseif ($outputMode -eq "csv") {
    Write-Host "pid,pcpu,comm,action"
    $i = 0
    foreach ($c in $candidates) {
        Write-Host "$($c.Id),$($c.CpuPercent),`"$($c.ProcessName)`",`"$($actions[$i])`""
        $i++
    }
}
if ($Script:FailedCount -gt 0) { Write-AuditLog -Level "ERROR" -Message "Completed with failures (killed=$($Script:KilledCount), failed=$($Script:FailedCount))."; exit 2 }
Write-AuditLog -Level "INFO" -Message "Completed (killed=$($Script:KilledCount), candidates=$candidateCount)."
exit 0

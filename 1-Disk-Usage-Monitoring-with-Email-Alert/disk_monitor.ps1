#Requires -Version 7.0
<#
.SYNOPSIS
    Disk usage monitor with threshold alerting.

.DESCRIPTION
    Measures the usage of a mounted filesystem and hands an alert to the host
    mail agent when the usage crosses a threshold. The module holds no
    credentials and opens no socket of its own: it composes the alert and
    hands it to a mail agent that the host already provides.

    The measurement source is the POSIX df output on Linux and macOS, and the
    native volume API on Windows. Both report the capacity as a percentage.

.PARAMETER Partition
    Mount point to watch. Defaults to the root of the current drive on Windows
    and to "/" elsewhere.

.PARAMETER Threshold
    Alert when the usage is strictly greater than this percentage (Default: 80).

.PARAMETER DryRun
    Report the alert without handing it to the mail agent.

.PARAMETER Notify
    Notification backend, either "none" or "mail" (Default: mail).

.PARAMETER To
    Alert recipient. Defaults to the DISK_MONITOR_TO environment variable.

.PARAMETER MailCommand
    Mail agent to hand the alert to. Defaults to the
    DISK_MONITOR_MAIL_COMMAND environment variable.

.PARAMETER LogFile
    Path to append ISO-8601 audit records.

.PARAMETER Help
    Show the help and usage documentation.

.EXAMPLE
    .\disk_monitor.ps1 -Partition C:\ -Threshold 80 -To ops@example.com

.EXAMPLE
    .\disk_monitor.ps1 -Partition /home -Threshold 90 -DryRun -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Partition = "",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Threshold = 80,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateSet("none", "mail")]
    [string]$Notify = "mail",

    [Parameter(Mandatory = $false)]
    [string]$To = "",

    [Parameter(Mandatory = $false)]
    [string]$MailCommand = "",

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "",

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# The verbose flag is a common parameter, so it is captured here in the script
# scope. Inside a function $PSBoundParameters would describe the function's
# own parameters, not the script's, and the flag would never be seen.
$script:VerboseEnabled = $PSBoundParameters.ContainsKey('Verbose') -and $Verbose

# The measurement command and the mail agent are external programs, so
# $LASTEXITCODE carries their status. It is initialised here so the strict
# mode never trips over it before the first external call.
$global:LASTEXITCODE = 0

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

# Prints usage and help message
function Show-Help {
    Write-Host @"
Disk Usage Monitor (PowerShell)
Usage: $PSCommandPath [OPTIONS]

Optional Arguments:
  -Partition <path>        Mount point to watch (default: / on Unix, the system drive on Windows).
  -Threshold <percent>     Alert when usage is strictly greater (default: 80).
  -DryRun                  Report the alert without handing it to the mail agent.
  -Notify <none|mail>      Notification backend (default: mail).
  -To <address>            Alert recipient (default: `$DISK_MONITOR_TO).
  -MailCommand <cmd>       Mail agent to hand the alert to.
  -LogFile <file>          Path to append ISO-8601 audit records.
  -Verbose                 Enable diagnostic output.
  -Help                    Show this help and usage documentation.

Exit Codes:
  0  The check completed; the alert was delivered, not needed, or suppressed.
  1  Configuration or safety error (bad flag, threshold, partition, recipient,
     or mail agent).
  2  Partial failure (the usage could not be read, or the alert could not be
     handed to the mail agent).

Examples:
  $PSCommandPath -Partition / -Threshold 80 -To ops@example.com
  $PSCommandPath -Partition /home -Threshold 90 -DryRun -Verbose
"@
}

# Writes a message to the error stream without touching the error pipeline
function Write-ErrorLine {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
}

# Writes a message to the audit log with an ISO-8601 timestamp
function Write-AuditLog {
    param(
        [string]$Level = "INFO",
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        return
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $entry = "$timestamp [$Level] $Message"

    try {
        $parent = [System.IO.Path]::GetDirectoryName($LogFile)
        if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value $entry -ErrorAction SilentlyContinue
    } catch {
        # A failing audit log must never break the measurement.
    }
}

# Reads the usage percentage from the POSIX df output.
# The capacity is taken from the second-to-last field, because that is the
# only position that is stable across GNU and macOS, and a mount point
# containing spaces cannot shift it.
function Read-PosixUsage {
    param(
        [string]$Path,
        [string]$Command
    )

    $output = $null
    try {
        $output = & $Command -P $Path 2>$null
    } catch {
        return $null
    }

    if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
        return $null
    }

    $lines = @($output)
    if ($lines.Count -lt 2) {
        return $null
    }

    $fields = $lines[1].Trim() -split '\s+'
    if ($fields.Count -lt 2) {
        return $null
    }

    $capacity = $fields[$fields.Count - 2].TrimEnd('%')
    if ($capacity -notmatch '^\d+$') {
        return $null
    }

    return [int]$capacity
}

# Reads the usage percentage of a Windows volume
function Get-WindowsVolumeUsage {
    param([string]$Path)

    $root = [System.IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = "$env:SystemDrive\"
    }
    $deviceId = $root.TrimEnd('\')

    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -eq $deviceId }

    if ($null -eq $disk -or $null -eq $disk.Size -or $disk.Size -le 0) {
        return $null
    }

    $used = $disk.Size - $disk.FreeSpace
    return [int][math]::Round(($used / $disk.Size) * 100)
}

# Reads the usage percentage of the watched partition, or $null when the
# measurement failed. A forced value short-circuits the measurement.
function Get-DiskUsagePercent {
    param(
        [string]$Path,
        [string]$Command
    )

    if (-not [string]::IsNullOrWhiteSpace($env:DISK_MONITOR_USAGE_OVERRIDE)) {
        return [int]$env:DISK_MONITOR_USAGE_OVERRIDE
    }

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        return (Read-PosixUsage -Path $Path -Command $Command)
    }

    return (Get-WindowsVolumeUsage -Path $Path)
}

# Resolves the mail agent that receives the alert. The contract is:
#   <mail-command> -s <subject> <recipient>   with the body on stdin.
# The candidate list covers the agents that honour that contract.
function Resolve-MailCommand {
    param([string]$Override)

    $candidate = $Override
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:DISK_MONITOR_MAIL_COMMAND
    }

    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        $resolved = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $resolved.Source
        }
        return $null
    }

    foreach ($name in @("mail", "msmtp")) {
        $resolved = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $resolved.Source
        }
    }

    return $null
}

# Hands the alert to the resolved mail agent
function Send-Alert {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$Command,
        [string]$Recipient
    )

    try {
        $Body | & $Command -s $Subject $Recipient 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# Main script orchestration
function Invoke-DiskMonitor {
    if ($Help) {
        Show-Help
        exit 0
    }

    $resolvedPartition = $Partition
    if ([string]::IsNullOrWhiteSpace($resolvedPartition)) {
        if ($IsWindows) {
            $resolvedPartition = "$env:SystemDrive\"
        } else {
            $resolvedPartition = "/"
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPartition -PathType Container)) {
        Write-ErrorLine "$($Colors.Red)Error: Partition '$resolvedPartition' does not exist.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Partition does not exist: '$resolvedPartition'."
        exit 1
    }

    $usageOverride = $env:DISK_MONITOR_USAGE_OVERRIDE
    if (-not [string]::IsNullOrWhiteSpace($usageOverride)) {
        $parsedOverride = 0
        $isNumeric = [int]::TryParse($usageOverride, [ref]$parsedOverride)
        if (-not $isNumeric -or $parsedOverride -lt 0 -or $parsedOverride -gt 100) {
            Write-ErrorLine "$($Colors.Red)Error: DISK_MONITOR_USAGE_OVERRIDE must be an integer between 0 and 100.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Invalid usage override: '$usageOverride'."
            exit 1
        }
    }

    $usageCommand = ""
    $commandOverride = $env:DISK_MONITOR_USAGE_COMMAND
    if (-not [string]::IsNullOrWhiteSpace($commandOverride)) {
        $resolvedCommand = Get-Command $commandOverride -ErrorAction SilentlyContinue
        if ($null -eq $resolvedCommand) {
            Write-ErrorLine "$($Colors.Red)Error: Measurement command '$commandOverride' was not found.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Measurement command not found: '$commandOverride'."
            exit 1
        }
        $usageCommand = $resolvedCommand.Source
    } elseif (-not $IsWindows) {
        $resolvedCommand = Get-Command "df" -ErrorAction SilentlyContinue
        if ($null -eq $resolvedCommand) {
            Write-ErrorLine "$($Colors.Red)Error: Measurement command 'df' was not found.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Measurement command not found: 'df'."
            exit 1
        }
        $usageCommand = $resolvedCommand.Source
    }

    $recipient = $To
    if ([string]::IsNullOrWhiteSpace($recipient)) {
        $recipient = $env:DISK_MONITOR_TO
    }

    $mailCommand = ""
    if ($Notify -eq "mail") {
        if ([string]::IsNullOrWhiteSpace($recipient)) {
            Write-ErrorLine "$($Colors.Red)Error: No recipient. Use -To, or set DISK_MONITOR_TO.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "No alert recipient configured."
            exit 1
        }

        $mailCommand = Resolve-MailCommand -Override $MailCommand
        if ($null -eq $mailCommand) {
            Write-ErrorLine "$($Colors.Red)Error: No mail agent found. Install one, or set -MailCommand or DISK_MONITOR_MAIL_COMMAND.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "No mail agent could be resolved."
            exit 1
        }
    }

    $usedPercent = Get-DiskUsagePercent -Path $resolvedPartition -Command $usageCommand
    if ($null -eq $usedPercent) {
        Write-ErrorLine "$($Colors.Red)Error: Could not read the disk usage of '$resolvedPartition'.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Could not read the disk usage of '$resolvedPartition'."
        exit 2
    }

    $usageSource = "measured"
    if (-not [string]::IsNullOrWhiteSpace($env:DISK_MONITOR_USAGE_OVERRIDE)) {
        $usageSource = "overridden"
    }

    $modeLabel = if ($DryRun) { "$($Colors.Yellow)DRY RUN (Simulation)$($Colors.Reset)" } else { "$($Colors.Green)LIVE (Alerts Active)$($Colors.Reset)" }

    $mailLabel = $mailCommand
    if ([string]::IsNullOrWhiteSpace($mailLabel)) {
        $mailLabel = "(not resolved: notification disabled)"
    }

    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)                DevOps Disk Usage Monitor                  $($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "Partition         : $($Colors.Cyan)$resolvedPartition$($Colors.Reset)"
    Write-Host "Usage             : $($Colors.Bold)$usedPercent%$($Colors.Reset) ($usageSource)"
    Write-Host "Threshold         : $($Colors.Yellow)$Threshold%$($Colors.Reset)"
    Write-Host "Mail Agent        : $($Colors.Cyan)$mailLabel$($Colors.Reset)"
    if ($Notify -eq "mail") {
        Write-Host "Recipient         : $($Colors.Cyan)$recipient$($Colors.Reset)"
    }
    Write-Host "Execution Mode    : $modeLabel"
    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        Write-Host "Audit Log File    : $($Colors.Cyan)$LogFile$($Colors.Reset)"
    }

    if ($script:VerboseEnabled) {
        Write-Host "$($Colors.Blue)Diagnostics        : $($Colors.Reset)mail agent '$mailLabel', recipient '$recipient', dry-run '$DryRun'$($Colors.Reset)"
    }
    if ($usedPercent -gt $Threshold) {
        Write-Host "$($Colors.Red)WARNING: Disk usage exceeds the threshold.$($Colors.Reset)"

        $hostName = if ($IsWindows) { $env:COMPUTERNAME } else { (hostname 2>$null) }
        if ([string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = "unknown-host"
        }

        $subject = "Disk Alert: $resolvedPartition at $usedPercent%"
        $body = @(
            "Disk usage on $hostName is at $usedPercent% (threshold: $Threshold%)."
            ""
            "Partition : $resolvedPartition"
            "Usage    : $usedPercent%"
            "Threshold: $Threshold%"
            "Time     : $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        ) -join "`n"

        if ($DryRun) {
            Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would send an alert to $recipient"
            Write-AuditLog -Level "INFO" -Message "[DRY RUN] Would send an alert to $recipient (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
        } elseif ($Notify -eq "mail") {
            if (Send-Alert -Subject $subject -Body $body -Command $mailCommand -Recipient $recipient) {
                Write-Host "$($Colors.Green)Alert sent to $recipient$($Colors.Reset)"
                Write-AuditLog -Level "INFO" -Message "ALERT SENT to $recipient (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
            } else {
                Write-ErrorLine "$($Colors.Red)Error: The alert could not be handed to the mail agent.$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "FAILED to hand the alert to the mail agent (Usage: ${usedPercent}%, Source: $usageSource)"
                exit 2
            }
        } else {
            Write-Host "$($Colors.Cyan)Alert suppressed by -Notify none.$($Colors.Reset)"
            Write-AuditLog -Level "INFO" -Message "Alert suppressed by -Notify none (Usage: ${usedPercent}%, Source: $usageSource)"
        }
    } else {
        Write-Host "$($Colors.Green)Disk usage is within the threshold.$($Colors.Reset)"
        Write-AuditLog -Level "INFO" -Message "Usage within threshold (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
    }

    exit 0
}

Invoke-DiskMonitor

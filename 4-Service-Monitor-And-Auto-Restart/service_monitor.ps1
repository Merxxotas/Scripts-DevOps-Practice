<#
.SYNOPSIS
    Service Monitor and Auto-Restart.

.DESCRIPTION
    Checks whether a named service is running and, when it is down, attempts to
    restart it up to a configurable number of times with a configurable delay.
    Exit codes:
      0  success (running, restarted, or dry-run)
      1  configuration or safety violation
      2  partial failure (restart failed after retries)
#>

param(
    [string]$ServiceName = "w3svc",
    [ValidateRange(1, 1048576)]
    [int]$MaxRetries = 3,
    [ValidateRange(0, 1048576)]
    [int]$RetryDelaySeconds = 5,
    [switch]$DryRun,
    [string]$AuditLog = "",
    [switch]$Verbose,
    [switch]$Json,
    [switch]$Csv,
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

$Script:RetriesUsed = 0

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
    Write-Host "Service Monitor and Auto-Restart Utility (PowerShell)"
    Write-Host "Usage: .\service_monitor.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Optional Arguments:"
    Write-Host "  -ServiceName <name>    Target service name (default: w3svc)."
    Write-Host "  -MaxRetries <n>        Restart attempts when down (default: 3)."
    Write-Host "  -RetryDelaySeconds <n> Seconds between attempts (default: 5)."
    Write-Host "  -DryRun                Preview actions without touching the service."
    Write-Host "  -AuditLog <file>       Append ISO-8601 audit log entries."
    Write-Host "  -Json                  Output result as JSON."
    Write-Host "  -Csv                   Output result as CSV."
    Write-Host "  -Verbose               Enable diagnostic output."
    Write-Host "  -Help                  Show this help and usage documentation."
}

function Test-ValidServiceName {
    param([string]$Name)
    return ($Name -match '^[a-zA-Z0-9_.-]+$')
}

function Get-ServiceObject {
    param([string]$Name)
    try {
        return (Get-Service -Name $Name -ErrorAction Stop)
    } catch {
        return $null
    }
}

if ($Help) {
    Show-Help
    exit 0
}

# Output mode
$outputMode = "human"
if ($Json -and $Csv) {
    Write-Host "$($Colors.Red)Error: Cannot use -Json and -Csv together.$($Colors.Reset)" -ForegroundColor Red
    exit 1
}
if ($Json) { $outputMode = "json" }
elseif ($Csv) { $outputMode = "csv" }
$humanMode = ($outputMode -eq "human")

# Validation
if ([string]::IsNullOrWhiteSpace($ServiceName)) {
    Write-Host "$($Colors.Red)Error: Service name is required.$($Colors.Reset)" -ForegroundColor Red
    exit 1
}
if (-not (Test-ValidServiceName $ServiceName)) {
    Write-Host "$($Colors.Red)Error: Invalid service name '$ServiceName'.$($Colors.Reset)" -ForegroundColor Red
    Write-AuditLog -Level "ERROR" -Message "Invalid service name: $ServiceName"
    exit 1
}

# Header
if ($humanMode) {
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "            DevOps Service Monitor Utility                 " -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "Service          : $($Colors.Cyan)$ServiceName$($Colors.Reset)"
    Write-Host "Max Retries      : $($Colors.Cyan)$MaxRetries$($Colors.Reset)"
    Write-Host "Retry Delay      : $($Colors.Cyan)$RetryDelaySeconds s$($Colors.Reset)"
    if (-not [string]::IsNullOrWhiteSpace($AuditLog)) {
        Write-Host "Audit Log        : $($Colors.Cyan)$AuditLog$($Colors.Reset)"
    }
    Write-Host ""
}

$Service = Get-ServiceObject -Name $ServiceName
if ($null -eq $Service) {
    Write-Host "$($Colors.Red)Error: Service '$ServiceName' is not installed or not found.$($Colors.Reset)" -ForegroundColor Red
    Write-AuditLog -Level "ERROR" -Message "Service not found: $ServiceName"
    exit 1
}

if ($Service.Status -eq 'Running') {
    if ($DryRun) {
        if ($humanMode) {
            Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Service '$ServiceName' is running; no restart planned."
        }
        Write-AuditLog -Level "INFO" -Message "[DRY RUN] No restart needed for '$ServiceName'."
        if ($outputMode -eq "json") {
            $jsonLines = @()
            $jsonLines += "{"
            $jsonLines += "  `"service`": `"$ServiceName`","
            $jsonLines += "  `"max_retries`": $MaxRetries,"
            $jsonLines += "  `"retry_delay`": $RetryDelaySeconds,"
            $jsonLines += "  `"retries_used`": 0,"
            $jsonLines += "  `"outcome`": `"dry-run`""
            $jsonLines += "}"
            foreach ($jl in $jsonLines) { Write-Host $jl }
        } elseif ($outputMode -eq "csv") {
            Write-Host "service,max_retries,retry_delay,retries_used,outcome"
            Write-Host "`"$ServiceName`",$MaxRetries,$RetryDelaySeconds,0,`"dry-run`""
        }
        exit 0
    }
    if ($humanMode) {
        Write-Host "$($Colors.Green)✓ Service '$ServiceName' is running.$($Colors.Reset)" -ForegroundColor Green
    }
    Write-AuditLog -Level "INFO" -Message "Service '$ServiceName' is running."
    if ($outputMode -eq "json") {
        $jsonLines = @()
        $jsonLines += "{"
        $jsonLines += "  `"service`": `"$ServiceName`","
        $jsonLines += "  `"max_retries`": $MaxRetries,"
        $jsonLines += "  `"retry_delay`": $RetryDelaySeconds,"
        $jsonLines += "  `"retries_used`": 0,"
        $jsonLines += "  `"outcome`": `"running`""
        $jsonLines += "}"
        foreach ($jl in $jsonLines) { Write-Host $jl }
    } elseif ($outputMode -eq "csv") {
        Write-Host "service,max_retries,retry_delay,retries_used,outcome"
        Write-Host "`"$ServiceName`",$MaxRetries,$RetryDelaySeconds,0,`"running`""
    }
    exit 0
}

if ($humanMode) {
    Write-Host "$($Colors.Red)✗ Service '$ServiceName' is not running.$($Colors.Reset)" -ForegroundColor Red
}

if ($DryRun) {
    if ($humanMode) {
        Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would restart '$ServiceName' up to $MaxRetries time(s), waiting $RetryDelaySeconds s between attempts."
    }
    Write-AuditLog -Level "INFO" -Message "[DRY RUN] Restart planned for '$ServiceName'."
    if ($outputMode -eq "json") {
        $jsonLines = @()
        $jsonLines += "{"
        $jsonLines += "  `"service`": `"$ServiceName`","
        $jsonLines += "  `"max_retries`": $MaxRetries,"
        $jsonLines += "  `"retry_delay`": $RetryDelaySeconds,"
        $jsonLines += "  `"retries_used`": 0,"
        $jsonLines += "  `"outcome`": `"dry-run`""
        $jsonLines += "}"
        foreach ($jl in $jsonLines) { Write-Host $jl }
    } elseif ($outputMode -eq "csv") {
        Write-Host "service,max_retries,retry_delay,retries_used,outcome"
        Write-Host "`"$ServiceName`",$MaxRetries,$RetryDelaySeconds,0,`"dry-run`""
    }
    exit 0
}

if ($humanMode) {
    Write-Host "$($Colors.Yellow)Attempting to restart...$($Colors.Reset)" -ForegroundColor Yellow
}

for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    if ($Verbose -and $humanMode) {
        Write-Host "  attempt $attempt/$($MaxRetries): restarting $ServiceName"
    }
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds 2
        $Service.Refresh()
        if ($Service.Status -eq 'Running') {
            if ($humanMode) {
                Write-Host "$($Colors.Green)✓ Service '$ServiceName' restarted successfully.$($Colors.Reset)" -ForegroundColor Green
            }
            try {
                Write-EventLog -LogName Application -Source "ServiceMonitor" -EventId 1001 -EntryType Information -Message "Service $ServiceName was restarted" -ErrorAction SilentlyContinue
            } catch {
                $null = $_
            }
            $Script:RetriesUsed = $attempt
            Write-AuditLog -Level "INFO" -Message "Service '$ServiceName' restarted after $attempt attempt(s)."
            if ($humanMode) {
                Write-Host ""
                Write-Host "============================================================" -ForegroundColor Blue
                Write-Host "                    Execution Summary                       " -ForegroundColor Blue
                Write-Host "============================================================" -ForegroundColor Blue
                Write-Host "Service          : $($Colors.Bold)$ServiceName$($Colors.Reset)"
                Write-Host "Result           : $($Colors.Green)restarted$($Colors.Reset)"
                Write-Host "Retries Used     : $($Colors.Bold)$($Script:RetriesUsed)$($Colors.Reset)"
                Write-Host "Failed Steps     : $($Colors.Red)0$($Colors.Reset)"
                Write-Host "============================================================" -ForegroundColor Blue
            }
            if ($outputMode -eq "json") {
                $jsonLines = @()
                $jsonLines += "{"
                $jsonLines += "  `"service`": `"$ServiceName`","
                $jsonLines += "  `"max_retries`": $MaxRetries,"
                $jsonLines += "  `"retry_delay`": $RetryDelaySeconds,"
                $jsonLines += "  `"retries_used`": $($Script:RetriesUsed),"
                $jsonLines += "  `"outcome`": `"restarted`""
                $jsonLines += "}"
                foreach ($jl in $jsonLines) { Write-Host $jl }
            } elseif ($outputMode -eq "csv") {
                Write-Host "service,max_retries,retry_delay,retries_used,outcome"
                Write-Host "`"$ServiceName`",$MaxRetries,$RetryDelaySeconds,$($Script:RetriesUsed),`"restarted`""
            }
            exit 0
        }
    } catch {
        $Script:RetriesUsed = $attempt
        if ($humanMode) {
            Write-Host "$($Colors.Red)✗ Restart attempt $attempt/$MaxRetries failed.$($Colors.Reset)" -ForegroundColor Red
        }
        Write-AuditLog -Level "ERROR" -Message "Restart attempt $attempt/$MaxRetries failed for '$ServiceName'."
        if ($attempt -lt $MaxRetries) {
            if ($Verbose -and $humanMode) {
                Write-Host "  waiting $RetryDelaySeconds s before next attempt"
            }
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

if ($humanMode) {
    Write-Host "$($Colors.Red)✗ Failed to restart service '$ServiceName' after $MaxRetries attempt(s).$($Colors.Reset)" -ForegroundColor Red
}
Write-AuditLog -Level "ERROR" -Message "Failed to restart '$ServiceName' after $MaxRetries attempt(s)."
if ($humanMode) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "                    Execution Summary                       " -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "Service          : $($Colors.Bold)$ServiceName$($Colors.Reset)"
    Write-Host "Result           : $($Colors.Red)failed$($Colors.Reset)"
    Write-Host "Retries Used     : $($Colors.Bold)$($Script:RetriesUsed)$($Colors.Reset)"
    Write-Host "Failed Steps     : $($Colors.Red)1$($Colors.Reset)"
    Write-Host "============================================================" -ForegroundColor Blue
}
if ($outputMode -eq "json") {
    $jsonLines = @()
    $jsonLines += "{"
    $jsonLines += "  `"service`": `"$ServiceName`","
    $jsonLines += "  `"max_retries`": $MaxRetries,"
    $jsonLines += "  `"retry_delay`": $RetryDelaySeconds,"
    $jsonLines += "  `"retries_used`": $($Script:RetriesUsed),"
    $jsonLines += "  `"outcome`": `"failed`""
    $jsonLines += "}"
    foreach ($jl in $jsonLines) { Write-Host $jl }
} elseif ($outputMode -eq "csv") {
    Write-Host "service,max_retries,retry_delay,retries_used,outcome"
    Write-Host "`"$ServiceName`",$MaxRetries,$RetryDelaySeconds,$($Script:RetriesUsed),`"failed`""
}
exit 2

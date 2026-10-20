<#
.SYNOPSIS
    Cross-Platform System Resource Monitor with Process Kill/Restart Capability
.DESCRIPTION
    Monitors CPU, Memory, Disk, and Processes with display, watch mode, export options,
    and process management (kill/restart) capabilities.
.PARAMETER Watch
    Enable continuous refresh mode
.PARAMETER RefreshSeconds
    Refresh interval (default: 2)
.PARAMETER Format
    Output format: Display, Json, or Csv
.PARAMETER ExportPath
    Export file path or directory. If directory, auto-generates timestamped filename.
.PARAMETER TopProcesses
    Number of top processes (default: 100)
.PARAMETER Kill
    Kill process by PID or name
.PARAMETER KillMethod
    Kill method: Graceful, Terminate, or Kill (default: Graceful)
.PARAMETER Restart
    Restart process by PID or name
.PARAMETER RestartCommand
    Command to use for restart (optional)
.PARAMETER KillLog
    Show recent kill/restart actions
.PARAMETER Version
    Display the version information and exit
.EXAMPLE
    .\system_monitor.ps1 -ExportPath "C:\logs\server1.json"
.EXAMPLE
    .\system_monitor.ps1 -ExportPath "C:\logs\" -Format Csv
    (Saves as: system_monitor_20240312_143022.csv)
.EXAMPLE
    .\system_monitor.ps1 -Watch -ExportPath "C:\logs\" -RefreshSeconds 5
.EXAMPLE
    .\system_monitor.ps1 -Kill 1234
    Kill process with PID 1234
.EXAMPLE
    .\system_monitor.ps1 -Kill notepad -KillMethod Graceful
.EXAMPLE
    .\system_monitor.ps1 -Restart 1234
    Restart process with PID 1234
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(1, 1000)]
    [int]$TopProcesses = 100,
    
    [ValidateRange(1, 100)]
    [int]$CpuThreshold = 80,
    
    [ValidateRange(1, 100)]
    [int]$MemThreshold = 80,
    
    [switch]$Watch,
    
    [ValidateRange(0, 300)]
    [int]$RefreshSeconds = 2,
    
    [ValidateSet("Display", "Json", "Csv")]
    [string]$Format = "Display",
    
    [string]$ExportPath,
    
    # Process Kill/Restart parameters
    [string]$Kill,
    
    [ValidateSet("Graceful", "Terminate", "Kill")]
    [string]$KillMethod = "Graceful",
    
    [string]$Restart,
    
    [string]$RestartCommand,
    
    [switch]$KillLog,
    
    [switch]$Version
)

# ============================================================================
# STRICT ERROR HANDLING
# ============================================================================
$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# Whether the caller asked for a confirmation prompt. The script's own
# $Confirm variable is not a usable boolean, so the bound parameters are
# inspected instead.
$ConfirmRequested = $PSBoundParameters.ContainsKey("Confirm")

# The JSON and CSV output always uses dot decimals, whatever the host
# culture is. Under a culture such as es-CO or de-DE the decimal
# separator is a comma, which breaks CSV parsing and produces output
# that differs from the Bash implementation.
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

# Script metadata
$script:ScriptVersion = "1.3.0"
$script:ScriptName = $MyInvocation.MyCommand.Name

$ESC = [char]27
$RED = "$ESC[0;31m"
$YELLOW = "$ESC[1;33m"
$GREEN = "$ESC[0;32m"
$CYAN = "$ESC[0;36m"
$WHITE = "$ESC[37m"
$BLUE = "$ESC[0;34m"
$NC = "$ESC[0m"

$OS = "Unknown"
if ($PSVersionTable.PSVersion.Major -eq 5) {
    $OS = "Windows"
} elseif ($PSVersionTable.PSVersion.Major -ge 6) {
    if ($IsWindows) { $OS = "Windows" }
    elseif ($IsLinux) { $OS = "Linux" }
    elseif ($IsMacOS) { $OS = "Darwin" }
}

function Get-CpuUsage {
    switch ($OS) {
        "Windows" {
            try {
                $counter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
                return [math]::Round($counter.CounterSamples.CookedValue, 2)
            } catch { return $null }
        }
        "Linux" {
            if (Test-Path /proc/stat) {
                $stat1 = (Get-Content /proc/stat)[0]
                $parts1 = $stat1 -split '\s+'
                $user1 = [long]$parts1[1]; $nice1 = [long]$parts1[2]
                $system1 = [long]$parts1[3]; $idle1 = [long]$parts1[4]
                $iowait1 = [long]$parts1[5]
                $total1 = $user1 + $nice1 + $system1 + $idle1 + $iowait1
                
                Start-Sleep -Milliseconds 500
                
                $stat2 = (Get-Content /proc/stat)[0]
                $parts2 = $stat2 -split '\s+'
                $user2 = [long]$parts2[1]; $nice2 = [long]$parts2[2]
                $system2 = [long]$parts2[3]; $idle2 = [long]$parts2[4]
                $iowait2 = [long]$parts2[5]
                $total2 = $user2 + $nice2 + $system2 + $idle2 + $iowait2
                
                $totalDiff = $total2 - $total1
                $idleDiff = ($idle2 - $idle1) + ($iowait2 - $iowait1)
                
                if ($totalDiff -gt 0) {
                    return [math]::Round(100 * ($totalDiff - $idleDiff) / $totalDiff, 2)
                }
            }
            return $null
        }
        "Darwin" {
            $topOutput = & top -l1 2>$null | Select-String "CPU usage"
            if ($topOutput) {
                $match = [regex]::Match($topOutput, '([\d.]+)%\s*idle')
                if ($match.Success) {
                    return [math]::Round(100 - [double]$match.Groups[1].Value, 2)
                }
            }
            return $null
        }
    }
}

function Get-MemoryUsage {
    switch ($OS) {
        "Windows" {
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $total = $os.TotalVisibleMemorySize
                $free = $os.FreePhysicalMemory
                return [math]::Round(($total - $free) / $total * 100, 2)
            } catch { return $null }
        }
        "Linux" {
            if (Get-Command free -ErrorAction SilentlyContinue) {
                $output = & free | & grep Mem
                if ($output) {
                    $parts = $output -split '\s+'
                    return [math]::Round([decimal]$parts[2] / [decimal]$parts[1] * 100, 2)
                }
            }
            if (Test-Path /proc/meminfo) {
                $meminfo = Get-Content /proc/meminfo
                $totalLine = $meminfo | Select-String "MemTotal"
                $availLine = $meminfo | Select-String "MemAvailable"
                if ($totalLine -and $availLine) {
                    $total = [decimal]($totalLine -split '\s+')[1]
                    $available = [decimal]($availLine -split '\s+')[1]
                    return [math]::Round(($total - $available) / $total * 100, 2)
                }
            }
            return $null
        }
        "Darwin" {
            $vmStats = & vm_stat 2>$null
            if ($vmStats) {
                $parse = {
                    param($line, $idx)
                    if ($line) {
                        return [long](($line -split '\s+')[$idx] -replace '\.', '')
                    }
                    return 0
                }
                $pagesFree = & $parse ($vmStats | Select-String "Pages free") 2
                $pagesActive = & $parse ($vmStats | Select-String "Pages active") 2
                $pagesInactive = & $parse ($vmStats | Select-String "Pages inactive") 2
                $pagesWired = & $parse ($vmStats | Select-String "Pages wired down") 3
                $pagesSpec = & $parse ($vmStats | Select-String "Pages speculative") 2
                
                $used = $pagesActive + $pagesInactive + $pagesSpec + $pagesWired
                $total = $used + $pagesFree
                if ($total -gt 0) { return [math]::Round($used / $total * 100, 2) }
            }
            return $null
        }
    }
}

# ============================================================================
# DISK AND STORAGE FUNCTIONS
# ============================================================================

$DiskThresholdWarning = 70
$DiskThresholdCritical = 90

function Get-DiskUsage {
    $disks = @()
    switch ($OS) {
        "Windows" {
            try {
                Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
                    $percent = if ($_.Size -gt 0) { 
                        [math]::Round(($_.Size - $_.FreeSpace) / $_.Size * 100, 1) 
                    } else { 0 }
                    $disks += [PSCustomObject]@{
                        mount_point = $_.DeviceID
                        total_gb = [math]::Round($_.Size / 1GB, 2)
                        used_gb = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
                        free_gb = [math]::Round($_.FreeSpace / 1GB, 2)
                        percent_used = $percent
                    }
                }
            } catch {
                Write-Verbose "Could not retrieve disk usage: $_"
            }
        }
        "Linux" {
            if (Get-Command df -ErrorAction SilentlyContinue) {
                & df -h 2>$null | Select-String '^/dev/' | ForEach-Object {
                    $parts = $_ -split '\s+'
                    if ($parts.Count -ge 6) {
                        $percent = ($parts[4] -replace '%', '')
                        $disks += [PSCustomObject]@{
                            mount_point = $parts[5]
                            total = $parts[1]
                            used = $parts[2]
                            free = $parts[3]
                            percent_used = [int]$percent
                        }
                    }
                }
            }
        }
    }
    return $disks
}

function Get-DiskColor {
    param([int]$Percent)
    if ($Percent -gt $DiskThresholdCritical) { return $RED }
    if ($Percent -gt $DiskThresholdWarning) { return $YELLOW }
    return $GREEN
}

function Show-DiskSection {
    $disks = Get-DiskUsage
    if ($disks) {
        Write-Host "`n${YELLOW}Disk Usage:${NC}"
        foreach ($disk in $disks) {
            $color = Get-DiskColor -Percent $disk.PercentUsed
            Write-Host ("{0}{1,-10} {2,8}GB used / {3,8}GB total ({4,5}%){5}" -f 
                $color, $disk.MountPoint, $disk.UsedGB, $disk.TotalGB, $disk.PercentUsed, $NC)
        }
    }
}

function Get-DiskIoStat {
    # Windows disk I/O counters (optional - may require elevated privileges)
    $ioStats = @()
    if ($OS -eq "Windows") {
        try {
            Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | Where-Object { $_.Name -ne '_Total' } | ForEach-Object {
                $ioStats += [PSCustomObject]@{
                    device = $_.Name
                    reads_per_sec = $_.DiskReadsPerSec
                    writes_per_sec = $_.DiskWritesPerSec
                    read_bytes_per_sec = $_.DiskReadBytesPerSec
                    write_bytes_per_sec = $_.DiskWriteBytesPerSec
                }
            }
        } catch {
            Write-Verbose "Could not retrieve disk I/O stats: $_"
        }
    }
    return $ioStats
}

function Show-DiskIoSection {
    $ioStats = Get-DiskIoStat
    if ($ioStats) {
        Write-Host "`n${YELLOW}Disk I/O Statistics:${NC}"
        foreach ($stat in $ioStats) {
            Write-Host ("{0}{1,-10}{2} Reads/sec: {3,8}  Writes/sec: {4,8}" -f 
                $CYAN, $stat.Device, $NC, $stat.ReadsPerSec, $stat.WritesPerSec)
        }
    }
}

function Get-ProcessData {
    $data = @()
    if ($OS -eq "Windows") {
        $processes = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First $TopProcesses
        $cpuMap = @{}
        try {
            Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | ForEach-Object {
                if ($_.IDProcess -and $null -ne $_.PercentProcessorTime) {
                    $cpuMap[$_.IDProcess] = $_.PercentProcessorTime
                }
            }
        } catch {
            # The performance counter class is not available on every
            # Windows host. The process list is still reported, with a
            # CPU usage of zero for each entry.
            Write-Verbose "Win32_PerfFormattedData_PerfProc_Process is unavailable - reporting 0% CPU per process"
        }
        
        foreach ($proc in $processes) {
            $cpuVal = $cpuMap[$proc.Id]
            if ($null -eq $cpuVal) { $cpuVal = 0.0 }
            $data += [PSCustomObject]@{
                name = $proc.ProcessName
                pid = $proc.Id
                cpu_percent = [decimal]$cpuVal
                ram_mb = [math]::Round($proc.WorkingSet / 1MB, 2)
            }
        }
    } else {
        $data = & ps aux 2>$null | Select-Object -Skip 1 | ForEach-Object {
            $line = $_ -replace '^\s+', ''
            $parts = $line -split '\s+', 11
            if ($parts.Count -ge 11) {
                $name = ($parts[10] -split ' ')[0] -replace '^.*/', ''
                [PSCustomObject]@{
                    name = $name
                    pid = $parts[1]
                    cpu_percent = [decimal]$parts[2]
                    ram_mb = [math]::Round([long]$parts[5] / 1024, 2)
                }
            }
        } | Sort-Object ram_mb -Descending | Select-Object -First $TopProcesses
    }
    return $data
}

function Get-AggregatedData {
    $agg = @{}
    if ($OS -eq "Windows") {
        Get-Process | Group-Object ProcessName | ForEach-Object {
            $totalRam = ($_.Group | Measure-Object WorkingSet -Sum).Sum / 1MB
            $agg[$_.Name] = @{
                total_ram_mb = [math]::Round($totalRam, 2)
                instances = $_.Count
            }
        }
    } else {
        & ps -eo comm,rss 2>$null | Select-Object -Skip 1 | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^(\S+)\s+(\d+)$') {
                $comm = $matches[1] -replace '^.*/', ''
                $rss = [long]$matches[2]
                if ($agg.ContainsKey($comm)) {
                    $agg[$comm].total_ram_mb += ($rss / 1024)
                    $agg[$comm].instances++
                } else {
                    $agg[$comm] = @{ total_ram_mb = [math]::Round($rss / 1024, 2); instances = 1 }
                }
            }
        }
    }
    return $agg.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{ name = $_.Key; total_ram_mb = $_.Value.total_ram_mb; instances = $_.Value.instances }
    } | Sort-Object total_ram_mb -Descending
}

# ============================================================================
# PROCESS KILL/RESTART FUNCTIONS
# ============================================================================

# The kill log lands in the platform temporary directory. $env:TEMP only
# exists on Windows, and $env:TMPDIR only on Unix, so the .NET temp path
# is the final fallback. The Bash implementation defaults to /tmp.
$KillLogDir = @(
    $env:KILL_LOG_DIR
    $env:TEMP
    $env:TMPDIR
    [System.IO.Path]::GetTempPath()
) | Where-Object { $_ } | Select-Object -First 1
$KillLogFile = Join-Path $KillLogDir "system_monitor_kill.log"

function Initialize-KillLog {
    if (-not (Test-Path $KillLogFile)) {
        try {
            New-Item -ItemType File -Path $KillLogFile -Force | Out-Null
        } catch {
            Write-Warning "Cannot create kill log at $KillLogFile"
        }
    }
}

function Write-KillLog {
    param($Action, $Target, $Result, $Details = "")
    $timestamp = Get-Date -Format "o"
    $logEntry = "[$timestamp] [$Action] Target: $Target | Result: $Result | $Details"
    try {
        Add-Content -Path $KillLogFile -Value $logEntry
    } catch {
        Write-Verbose "Could not write to kill log"
    }
}

function Stop-ProcessById {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId,
        
        [ValidateSet("Terminate", "Kill", "Graceful")]
        [string]$Method = "Graceful"
    )
    
    # Check if process exists
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        $procName = $proc.ProcessName
        $procPath = $proc.Path
    } catch {
        # The Bash implementation reports a missing PID as a failure, so the
        # exit codes stay the same across both native implementations.
        Write-Error "Process $ProcessId does not exist or cannot be signaled"
        return $false
    }
    
    if (-not $PSCmdlet.ShouldProcess("Process $ProcessId ($procName)", "Stop")) {
        return $true
    }

    Write-Host "${CYAN}Attempting to stop process $ProcessId ($procName) using $Method method...${NC}"
    
    $success = $false
    
    switch ($Method) {
        "Graceful" {
            # Try graceful first, then force
            try {
                Stop-Process -Id $ProcessId -Force:$false -ErrorAction Stop -Confirm:$false
                Start-Sleep -Milliseconds 500
                # Check if still running
                try {
                    $null = Get-Process -Id $ProcessId -ErrorAction Stop
                    # Still running, force kill
                    Write-Warning "Process still running, forcing termination..."
                    Stop-Process -Id $ProcessId -Force -ErrorAction Stop -Confirm:$false
                } catch {
                    # Process is gone, which is what we want
                    $success = $true
                }
            } catch {
                try {
                    Stop-Process -Id $ProcessId -Force -ErrorAction Stop -Confirm:$false
                    $success = $true
                } catch {
                    Write-Error "Failed to stop process: $_"
                }
            }
        }
        "Terminate" {
            try {
                Stop-Process -Id $ProcessId -Force:$false -ErrorAction Stop -Confirm:$false
                $success = $true
            } catch {
                Write-Error "Failed to terminate process: $_"
            }
        }
        "Kill" {
            try {
                Stop-Process -Id $ProcessId -Force -ErrorAction Stop -Confirm:$false
                $success = $true
            } catch {
                Write-Error "Failed to kill process: $_"
            }
        }
    }
    
    if ($success) {
        Write-KillLog -Action "KILL" -Target $ProcessId -Result "SUCCESS" -Details "Process: $procName, Method: $Method, Path: $procPath"
        Write-Host "${GREEN}✓ Process $ProcessId ($procName) stopped successfully${NC}"
        return $true
    } else {
        Write-KillLog -Action "KILL" -Target $ProcessId -Result "FAILED" -Details "Process: $procName, Method: $Method"
        Write-Error "✗ Failed to stop process $ProcessId"
        return $false
    }
}

function Stop-ProcessByName {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName,
        
        [ValidateSet("Terminate", "Kill", "Graceful")]
        [string]$Method = "Graceful"
    )
    
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    
    if (-not $processes) {
        Write-Error "No processes found with name: '$ProcessName'"
        return $false
    }
    
    Write-Host "${CYAN}Found $($processes.Count) process(es) matching '$ProcessName':${NC}"
    $processes | Select-Object Id, ProcessName, CPU, WorkingSet | Format-Table -AutoSize
    
    if (-not $PSCmdlet.ShouldProcess("$($processes.Count) process(es) matching '$ProcessName'", "Stop")) {
        return $true
    }

    $allSuccess = $true
    foreach ($proc in $processes) {
        # Check if process still exists before trying to kill
        try {
            $null = Get-Process -Id $proc.Id -ErrorAction Stop
        } catch {
            Write-Verbose "Process $($proc.Id) already exited - skipping"
            continue
        }
        
        if (-not (Stop-ProcessById -ProcessId $proc.Id -Method $Method -WhatIf:([bool]$WhatIfPreference) -Confirm:([bool]$ConfirmRequested))) {
            $allSuccess = $false
        }
    }
    
    return $allSuccess
}

function Restart-ProcessTarget {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$Target,  # Can be PID or name
        
        [string]$RestartCommand,  # Optional command to restart
        
        [ValidateSet("Terminate", "Kill", "Graceful")]
        [string]$Method = "Graceful"
    )
    
    $processInfo = $null
    
    # Determine if target is PID or name
    if ($Target -match '^\d+$') {
        $procId = [int]$Target
        try {
            $proc = Get-Process -Id $procId -ErrorAction Stop
            $processInfo = @{
                Id = $proc.Id
                Name = $proc.ProcessName
                Path = $proc.Path
                CommandLine = $proc.Path  # Simplified for Windows
            }
        } catch {
            Write-Error "Process with ID $Target not found"
            return $false
        }
    } else {
        $procs = Get-Process -Name $Target -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($procs) {
            $processInfo = @{
                Id = $procs.Id
                Name = $procs.ProcessName
                Path = $procs.Path
                CommandLine = $procs.Path
            }
        } else {
            Write-Error "No process found with name: $Target"
            return $false
        }
    }
    
    if (-not $PSCmdlet.ShouldProcess("Target '$Target'", "Restart")) {
        return $true
    }

    Write-Host "${CYAN}Restarting process $($processInfo.Name) (PID: $($processInfo.Id))...${NC}"
    
    # Capture restart command
    $commandToRun = if ($RestartCommand) { $RestartCommand } else { $processInfo.Path }
    
    # Stop the process
    if (Stop-ProcessById -ProcessId $processInfo.Id -Method $Method) {
        # Wait a moment
        Start-Sleep -Seconds 1
        
        # Restart
        try {
            Write-Host "${CYAN}Starting process with: $commandToRun${NC}"
            $newProc = Start-Process -FilePath $commandToRun -PassThru -WindowStyle Normal
            Write-KillLog -Action "RESTART" -Target $Target -Result "SUCCESS" -Details "New PID: $($newProc.Id), Command: $commandToRun"
            Write-Host "${GREEN}✓ Process restarted successfully with new PID: $($newProc.Id)${NC}"
            return $true
        } catch {
            Write-KillLog -Action "RESTART" -Target $Target -Result "FAILED" -Details "Command: $commandToRun, Error: $_"
            Write-Error "Failed to restart process: $_"
            return $false
        }
    }
    
    return $false
}

function Show-KillLog {
    if (Test-Path $KillLogFile) {
        Write-Host "`n${YELLOW}Recent Kill/Restart Actions:${NC}"
        Get-Content $KillLogFile -Tail 10 | ForEach-Object {
            Write-Host "  $_"
        }
    } else {
        Write-Warning "No kill log found at $KillLogFile"
    }
}

function Export-MonitorData {
    param($Path, $Format)
    
    $cpu = Get-CpuUsage
    $mem = Get-MemoryUsage
    $processes = Get-ProcessData
    $aggregated = Get-AggregatedData
    $disks = Get-DiskUsage
    $diskIo = Get-DiskIoStat
    
    $data = [PSCustomObject]@{
        timestamp = Get-Date -Format "o"
        os = $OS

        cpu_percent = $cpu

        memory_percent = $mem

        disk_usage = $disks

        disk_io = $diskIo

        top_processes = $processes | Select-Object -First 10
        aggregated_totals = $aggregated

    }
    
    if ($Format -eq "Json") {
        $data | ConvertTo-Json -Depth 3 | Out-File $Path
    } else {
        $csvData = @()
        $csvData += [PSCustomObject]@{
            timestamp = $data.timestamp; os = $OS; metric_type = "system"
            name = "system"; pid = ""; cpu_percent = $cpu; ram_mb = ""; instances = ""
            mount_point = ""; device = ""; percent_used = ""
        }
        # Add disk usage rows
        $disks | ForEach-Object {
            $csvData += [PSCustomObject]@{
                timestamp = $data.timestamp; os = $OS; metric_type = "disk_usage"
                name = "disk"; pid = ""; cpu_percent = ""; ram_mb = ""; instances = ""
                mount_point = $_.mount_point; device = ""; percent_used = $_.percent_used
            }
        }
        $processes | Select-Object -First 10 | ForEach-Object {
            $csvData += [PSCustomObject]@{
                timestamp = $data.timestamp; os = $OS; metric_type = "process"
                name = $_.name; pid = $_.pid; cpu_percent = $_.cpu_percent
                ram_mb = $_.ram_mb; instances = 1; mount_point = ""; device = ""; percent_used = ""
            }
        }
        $aggregated | ForEach-Object {
            $csvData += [PSCustomObject]@{
                timestamp = $data.timestamp; os = $OS; metric_type = "aggregate"
                name = $_.name; pid = ""; cpu_percent = ""
                ram_mb = $_.total_ram_mb; instances = $_.instances; mount_point = ""; device = ""; percent_used = ""
            }
        }
        $csvData | Export-Csv $Path -NoTypeInformation
    }
}

function Show-Display {
    $cpu = Get-CpuUsage
    $mem = Get-MemoryUsage
    
    Write-Host "$BLUE=== System Resource Monitor ===$NC"
    Write-Host "$CYAN$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')$NC"
    Write-Host "$YELLOW OS: $OS$NC`n"

    Write-Host "CPU Usage: " -NoNewline
    if ($null -eq $cpu) { Write-Host "${YELLOW}Unable to detect${NC}" }
    elseif ($cpu -gt $CpuThreshold) { Write-Host "${RED}${cpu}% (HIGH)${NC}" }
    else { Write-Host "${GREEN}${cpu}%${NC}" }

    Write-Host "Memory Usage: " -NoNewline
    if ($null -eq $mem) { Write-Host "${YELLOW}Unable to detect${NC}" }
    elseif ($mem -gt $MemThreshold) { Write-Host "${RED}${mem}% (HIGH)${NC}" }
    else { Write-Host "${GREEN}${mem}%${NC}" }
    
    # Show disk section
    Show-DiskSection
    Show-DiskIoSection

    Write-Host "`n${YELLOW}Top $TopProcesses Processes (Sorted by RAM Usage):${NC}"
    Write-Host ("{0}{1,-22} {2,-10} {3,-12} {4,-12}{5}" -f $CYAN, "PROCESS", "PID", "CPU(%)", "RAM(MB)", $NC)
    Write-Host ("{0}{1}{2}" -f $CYAN, ("-" * 62), $NC)

    $procs = Get-ProcessData
    foreach ($p in $procs) {
        $name = $p.Name.Substring(0, [Math]::Min(22, $p.Name.Length)).PadRight(22)
        $procPid = $p.PID.ToString().PadRight(10)
        $cpu = "$($p.CpuPercent)%".PadRight(12)
        $ram = "$($p.RamMB) MB".PadRight(12)
        
        if ($p.RamMB -gt 500) { Write-Host "${RED}${name} ${procPid} ${cpu} ${ram}${NC}" }
        else { Write-Host "${name} ${procPid} ${cpu} ${ram}" }
    }
    
    Write-Host "`n${YELLOW}Total Usage by Process (Aggregated RAM):${NC}"
    Write-Host ("{0}{1}{2}" -f $CYAN, ("-" * 42), $NC)
    
    $agg = Get-AggregatedData
    if ($agg) {
        $maxRam = $agg[0].TotalRamMB
        foreach ($item in $agg) {
            $color = $WHITE
            if ($item.TotalRamMB -ge $maxRam * 0.9) { $color = $RED }
            elseif ($item.TotalRamMB -gt $maxRam * 0.6) { $color = $YELLOW }
            elseif ($item.TotalRamMB -gt $maxRam * 0.3) { $color = $GREEN }
            elseif ($item.TotalRamMB -gt $maxRam * 0.1) { $color = $CYAN }
            Write-Host ("{0}{1}{2}: {3}MB ({4} instances)" -f $color, $item.Name, $NC, $item.TotalRamMB, $item.Instances)
        }
    }
}

# Handle ExportPath logic
if ($ExportPath) {
    # Check if it's a directory
    if (Test-Path $ExportPath -PathType Container) {
        # Generate timestamped filename
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        if ($Format -eq "Csv" -or ($Format -eq "Display" -and $ExportPath -match '\.csv$')) {
            $filename = "system_monitor_$timestamp.csv"
            $Format = "Csv"
        } else {
            $filename = "system_monitor_$timestamp.json"
            $Format = "Json"
        }
        $ExportPath = Join-Path $ExportPath $filename
        Write-Host "${CYAN}Export directory provided. Will save as: $filename${NC}" -ForegroundColor Cyan
    } else {
        # It's a file path - ensure directory exists
        $dir = Split-Path $ExportPath -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        
        # Auto-detect format from extension if not specified
        if ($Format -eq "Display") {
            if ($ExportPath -match '\.csv$') { $Format = "Csv" }
            else { $Format = "Json" }
        }
    }
}

if ($Version) {
    Write-Host "System Resource Monitor v$($script:ScriptVersion)"
    exit 0
}

# Initialize kill log
Initialize-KillLog

# Handle kill/restart operations (executed before monitoring)
if ($KillLog) {
    Show-KillLog
    exit 0
}

if ($Restart) {
    $success = Restart-ProcessTarget -Target $Restart -RestartCommand $RestartCommand -Method $KillMethod -WhatIf:([bool]$WhatIfPreference) -Confirm:([bool]$ConfirmRequested)
    exit ([int](-not $success))
}

if ($Kill) {
    $success = $false
    if ($Kill -match '^\d+$') {
        $success = Stop-ProcessById -ProcessId ([int]$Kill) -Method $KillMethod -WhatIf:([bool]$WhatIfPreference) -Confirm:([bool]$ConfirmRequested)
    } else {
        $success = Stop-ProcessByName -ProcessName $Kill -Method $KillMethod -WhatIf:([bool]$WhatIfPreference) -Confirm:([bool]$ConfirmRequested)
    }
    exit ([int](-not $success))
}

# Execution modes
if ($Format -eq "Json" -and -not $Watch) {
    if ($ExportPath) {
        Export-MonitorData -Path $ExportPath -Format "Json"
        Write-Host "${GREEN}✓ Exported JSON to: $ExportPath${NC}" -ForegroundColor Green
    } else {
        $cpu = Get-CpuUsage; $mem = Get-MemoryUsage
        $data = [PSCustomObject]@{
            timestamp = Get-Date -Format "o"
            os = $OS
            cpu_percent = $cpu
            memory_percent = $mem
            disk_usage = (Get-DiskUsage)
            disk_io = (Get-DiskIoStat)
            top_processes = (Get-ProcessData | Select-Object -First 10)
            aggregated_totals = (Get-AggregatedData)
        }
        $data | ConvertTo-Json -Depth 3
    }
    exit
}

if ($Format -eq "Csv" -and -not $Watch) {
    if (-not $ExportPath) {
        Write-Error "CSV format requires -ExportPath parameter"
        exit 1
    }
    Export-MonitorData -Path $ExportPath -Format "Csv"
    Write-Host "${GREEN}✓ Exported CSV to: $ExportPath${NC}" -ForegroundColor Green
    exit
}

if ($Watch) {
    Write-Host "${GREEN}Starting watch mode (refresh every ${RefreshSeconds}s).${NC}" -ForegroundColor Green
    if ($ExportPath) {
        Write-Host "${CYAN}Logging to: $ExportPath${NC}" -ForegroundColor Cyan
        if ($Format -eq "Json") { "[" | Out-File $ExportPath }
    }
    Write-Host "${YELLOW}Press Ctrl+C to exit.${NC}" -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    
    $first = $true
    try {
        while ($true) {
            Clear-Host
            Show-Display
            
            if ($ExportPath) {
                if ($Format -eq "Json") {
                    if (-not $first) { Add-Content $ExportPath "," }
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    Export-MonitorData -Path $tempFile -Format "Json"
                    $content = Get-Content $tempFile -Raw
                    Add-Content $ExportPath $content.Trim()
                    Remove-Item $tempFile
                } else {
                    if ($first) {
                        Export-MonitorData -Path $ExportPath -Format "Csv"
                    } else {
                        $procs = Get-ProcessData
                        $agg = Get-AggregatedData
                        $cpu = Get-CpuUsage; $mem = Get-MemoryUsage
                        $csvLines = @()
                        $csvLines += [PSCustomObject]@{
                            Timestamp = Get-Date -Format "o"; OS = $OS; MetricType = "system"
                            Name = "system"; PID = ""; CpuPercent = $cpu; RamMB = ""; Instances = ""
                        }
                        $procs | Select-Object -First 10 | ForEach-Object {
                            $csvLines += [PSCustomObject]@{
                                Timestamp = Get-Date -Format "o"; OS = $OS; MetricType = "process"
                                Name = $_.Name; PID = $_.PID; CpuPercent = $_.CpuPercent
                                RamMB = $_.RamMB; Instances = 1
                            }
                        }
                        $agg | ForEach-Object {
                            $csvLines += [PSCustomObject]@{
                                Timestamp = Get-Date -Format "o"; OS = $OS; MetricType = "aggregate"
                                Name = $_.Name; PID = ""; CpuPercent = ""
                                RamMB = $_.TotalRamMB; Instances = $_.Instances
                            }
                        }
                        $csvLines | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File $ExportPath -Append
                    }
                }
                Write-Host "`n${CYAN}[Logged: $(Split-Path $ExportPath -Leaf)]${NC}" -ForegroundColor Cyan
            }
            
            $first = $false
            Write-Host "`n${CYAN}Last update: $(Get-Date -Format 'HH:mm:ss') | Next refresh in ${RefreshSeconds}s${NC} ${YELLOW}(Ctrl+C to quit)${NC}"
            Start-Sleep -Seconds $RefreshSeconds
        }
    } catch {
        # Properly close JSON array on exit
        if ($ExportPath -and $Format -eq "Json") { 
            Add-Content $ExportPath "]" 
            Write-Host "${CYAN}JSON array closed in: $ExportPath${NC}" -ForegroundColor Cyan
        }
        Write-Host "`n${GREEN}✓ Watch mode stopped${NC}" -ForegroundColor Green
        if ($ExportPath) { Write-Host "${CYAN}Final log: $ExportPath${NC}" -ForegroundColor Cyan }
    }
} else {
    Show-Display
    if ($ExportPath) {
        Export-MonitorData -Path $ExportPath -Format $(if ($Format -eq "Display") { "Json" } else { $Format })
        Write-Host "`n${GREEN}✓ Exported to: $ExportPath${NC}" -ForegroundColor Green
    }
}

# Explicit exit with success code
exit 0
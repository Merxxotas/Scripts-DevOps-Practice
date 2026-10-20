#Requires -Version 5.1
<#
.SYNOPSIS
    Integration tests for the Stage 1 native PowerShell implementation.
.DESCRIPTION
    Exercises the public interface only: the command-line parameters, the
    exit codes and the files the script emits. Every test is deterministic:
    the filesystem is isolated under a temporary directory and nothing depends
    on the host's disk layout, its running processes or its culture.

    The suite mirrors test_system_monitor.sh so both native implementations
    are held to the same contract.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = $PSScriptRoot
$ModuleDir = Split-Path -Parent $ScriptDir
$MonitorScript = Join-Path $ModuleDir "Stage1-Native-Scripts/system_monitor.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_ps1_monitor_" + [System.Guid]::NewGuid().ToString("N"))
$PwshPath = Join-Path $PSHOME ("pwsh" + [System.IO.Path]::GetExtension($PSHOME))

$Global:PassedCount = 0
$Global:FailedCount = 0

function Setup-TestEnv {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null
}

function Teardown-TestEnv {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($Expected -eq $Actual) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $Global:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected: '$Expected', Got: '$Actual')"
        $Global:FailedCount++
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Haystack,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($Haystack -like "*$Needle*") {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $Global:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected to contain: '$Needle')"
        $Global:FailedCount++
    }
}

# Runs the monitor script in a child process and returns its exit code.
function Invoke-Monitor {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & $PwshPath -NoProfile -File $MonitorScript @Arguments 2>&1
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output    = ($output | Out-String)
    }
}

# ------------------------------------------------------------------------------
# Test 1: The version output succeeds and names the tool
# ------------------------------------------------------------------------------
function Test-VersionOutput {
    $result = Invoke-Monitor @("-Version")
    Assert-Equal 0 $result.ExitCode "Test 1a: -Version exits with code 0"
    Assert-Contains $result.Output "System Resource Monitor" "Test 1b: -Version names the tool"
}

# ------------------------------------------------------------------------------
# Test 2: An unknown parameter is rejected
# ------------------------------------------------------------------------------
function Test-UnknownParameter {
    $result = Invoke-Monitor @("-DefinitelyNotAParameter")
    Assert-Contains $result.Output "DefinitelyNotAParameter" "Test 2a: an unknown parameter is reported"
    Assert-Equal 1 $result.ExitCode "Test 2b: an unknown parameter exits with code 1"
}

# ------------------------------------------------------------------------------
# Test 3: The refresh interval is validated against its documented range
# ------------------------------------------------------------------------------
function Test-IntervalValidation {
    $result = Invoke-Monitor @("-RefreshSeconds", "500")
    Assert-Contains $result.Output "RefreshSeconds" "Test 3a: an out-of-range interval is reported"
    Assert-Equal 1 $result.ExitCode "Test 3b: an out-of-range interval exits with code 1"
}

# ------------------------------------------------------------------------------
# Test 4: The JSON output is valid and carries the documented contract
# ------------------------------------------------------------------------------
function Test-JsonOutput {
    $jsonFile = Join-Path $TestSandbox "report.json"

    $result = Invoke-Monitor @("-Format", "Json", "-ExportPath", $jsonFile)
    Assert-Equal 0 $result.ExitCode "Test 4a: -Format Json -ExportPath exits with code 0"

    if (-not (Test-Path -LiteralPath $jsonFile)) {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 4b: the export file was not created"
        $Global:FailedCount++
        return
    }
    Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 4b: -Format Json -ExportPath creates the file"
    $Global:PassedCount++

    $expectedKeys = "aggregated_totals,cpu_percent,disk_io,disk_usage,memory_percent,os,timestamp,top_processes"
    $actualKeys = ""
    try {
        $parsed = Get-Content -LiteralPath $jsonFile -Raw | ConvertFrom-Json
        $actualKeys = ($parsed.PSObject.Properties.Name | Sort-Object) -join ","
    } catch {
        $actualKeys = "PARSE_ERROR"
    }
    Assert-Equal $expectedKeys $actualKeys "Test 4c: the JSON document carries the documented top-level keys"
}

# ------------------------------------------------------------------------------
# Test 5: The CSV output carries the documented header
# ------------------------------------------------------------------------------
function Test-CsvOutput {
    $csvFile = Join-Path $TestSandbox "report.csv"

    $result = Invoke-Monitor @("-Format", "Csv", "-ExportPath", $csvFile)
    Assert-Equal 0 $result.ExitCode "Test 5a: -Format Csv -ExportPath exits with code 0"

    $header = ""
    if (Test-Path -LiteralPath $csvFile) {
        # Export-Csv quotes every field, so the raw header is split on the
        # quoted separator before the quotes are stripped.
        $rawHeader = Get-Content -LiteralPath $csvFile -TotalCount 1
        $header = (($rawHeader -split '","') | ForEach-Object { $_.Trim('"') }) -join ","
    }
    Assert-Equal `
        "timestamp,os,metric_type,name,pid,cpu_percent,ram_mb,instances,mount_point,device,percent_used" `
        $header `
        "Test 5b: the CSV header matches the documented column order"
}

# ------------------------------------------------------------------------------
# Test 6: Exporting to a directory produces a timestamped file
# ------------------------------------------------------------------------------
function Test-ExportToDirectory {
    $exportDir = Join-Path $TestSandbox "exports"
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null

    $result = Invoke-Monitor @("-Format", "Json", "-ExportPath", "$exportDir\")
    Assert-Equal 0 $result.ExitCode "Test 6a: -ExportPath to a directory exits with code 0"

    $created = @(Get-ChildItem -LiteralPath $exportDir -Filter "system_monitor_*.json" -ErrorAction SilentlyContinue).Count
    Assert-Equal 1 $created "Test 6b: -ExportPath to a directory creates one timestamped file"
}

# ------------------------------------------------------------------------------
# Test 7: Killing a process that does not exist fails cleanly
# ------------------------------------------------------------------------------
function Test-KillMissingProcess {
    $result = Invoke-Monitor @("-Kill", "999999999")
    Assert-Equal 1 $result.ExitCode "Test 7: killing a missing PID exits with code 1"
}

# ------------------------------------------------------------------------------
# Test 8: The output does not depend on the host culture
# ------------------------------------------------------------------------------
function Test-CultureIndependence {
    $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("es-CO")
        $jsonFile = Join-Path $TestSandbox "culture.json"

        $result = Invoke-Monitor @("-Format", "Json", "-ExportPath", $jsonFile)
        Assert-Equal 0 $result.ExitCode "Test 8a: the script succeeds under a comma-decimal culture"

        $parsed = "invalid"
        try {
            $null = Get-Content -LiteralPath $jsonFile -Raw | ConvertFrom-Json
            $parsed = "valid"
        } catch {
            $parsed = "invalid"
        }
        Assert-Equal "valid" $parsed "Test 8b: the JSON output is valid under a comma-decimal culture"
    } finally {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
    }
}

# ------------------------------------------------------------------------------
# Run the suite
# ------------------------------------------------------------------------------
Setup-TestEnv

Test-VersionOutput
Test-UnknownParameter
Test-IntervalValidation
Test-JsonOutput
Test-CsvOutput
Test-ExportToDirectory
Test-KillMissingProcess
Test-CultureIndependence

Teardown-TestEnv

Write-Host ""
Write-Host "=============================================="
Write-Host "Tests Passed: $Global:PassedCount"
Write-Host "Tests Failed: $Global:FailedCount"
Write-Host "=============================================="

if ($Global:FailedCount -gt 0) {
    exit 1
}
exit 0

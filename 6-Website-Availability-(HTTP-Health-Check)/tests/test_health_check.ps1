# Test Suite: test_health_check.ps1

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HcScript = Join-Path (Split-Path -Parent $ScriptDir) "health_check.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_health_check_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Invoke-Hc {
    param([string[]]$ScriptArgs, [string]$MockResponse = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $psi.FileName = "powershell"
    }
    $psi.Arguments = "-NoProfile -File `"$HcScript`" " + ($ScriptArgs -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    if ($MockResponse -ne "") {
        $psi.EnvironmentVariables["HEALTH_CHECK_MOCK_RESPONSE"] = $MockResponse
    } else {
        $psi.EnvironmentVariables.Remove("HEALTH_CHECK_MOCK_RESPONSE") | Out-Null
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $script:LastStdout = $proc.StandardOutput.ReadToEnd()
    $script:LastStderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $script:LastExitCode = $proc.ExitCode
    if ($script:LastStderr) {
        Write-Host "STDERR: $($script:LastStderr)" -ForegroundColor DarkYellow
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -eq $Actual) {
        Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (expected '$Expected', got '$Actual')" -ForegroundColor Red; $script:FailedCount++
    }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -like "*$Needle*") {
        Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (missing '$Needle')" -ForegroundColor Red; $script:FailedCount++
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (file missing: $Path)" -ForegroundColor Red; $script:FailedCount++
    }
}

# Test 1: help
Invoke-Hc -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Contains $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: help long form (also -h not supported, use -Help). Test --help not a PS param; skip.

# Test 3: invalid URL scheme
Invoke-Hc -ScriptArgs @("-Url", "ftp://example.com")
Assert-Equal 1 $script:LastExitCode "Test 3: bad scheme exits 1"

# Test 4: missing scheme
Invoke-Hc -ScriptArgs @("-Url", "example.com")
Assert-Equal 1 $script:LastExitCode "Test 4: no scheme exits 1"

# Test 5: invalid timeout (zero)
Invoke-Hc -ScriptArgs @("-TimeoutSec", "0")
Assert-Equal 1 $script:LastExitCode "Test 5: zero timeout exits 1"

# Test 6: invalid timeout (negative)
Invoke-Hc -ScriptArgs @("-TimeoutSec", "-5")
Assert-Equal 1 $script:LastExitCode "Test 6: negative timeout exits 1"

# Test 7: invalid expected code (too low)
Invoke-Hc -ScriptArgs @("-ExpectedCode", "99")
Assert-Equal 1 $script:LastExitCode "Test 7: expected code 99 exits 1"

# Test 8: invalid expected code (too high)
Invoke-Hc -ScriptArgs @("-ExpectedCode", "600")
Assert-Equal 1 $script:LastExitCode "Test 8: expected code 600 exits 1"

# Test 9: dry-run exits 0
Invoke-Hc -ScriptArgs @("-DryRun") -MockResponse "000|0.000|0"
Assert-Equal 0 $script:LastExitCode "Test 9a: dry-run exits 0"
Assert-Contains $script:LastStdout "Dry run" "Test 9b: dry-run label"

# Test 10: healthy (status matches) via mock
Invoke-Hc -ScriptArgs @("-Url", "https://example.com", "-ExpectedCode", "200") -MockResponse "200|0.123|1024"
Assert-Equal 0 $script:LastExitCode "Test 10a: healthy exits 0"
Assert-Contains $script:LastStdout "200 OK" "Test 10b: status 200 OK"
Assert-Contains $script:LastStdout "Healthy" "Test 10c: Healthy label"

# Test 11: mismatch (500 vs 200) -> exit 2
Invoke-Hc -ScriptArgs @("-Url", "https://example.com", "-ExpectedCode", "200") -MockResponse "500|0.500|256"
Assert-Equal 2 $script:LastExitCode "Test 11a: mismatch exits 2"
Assert-Contains $script:LastStdout "500" "Test 11b: shows 500"
Assert-Contains $script:LastStdout "Unhealthy" "Test 11c: Unhealthy label"

# Test 12: connection failure (FAIL) -> exit 2
Invoke-Hc -ScriptArgs @("-Url", "https://example.com") -MockResponse "FAIL"
Assert-Equal 2 $script:LastExitCode "Test 12a: connection failure exits 2"
Assert-Contains $script:LastStdout "CONNECTION FAILED" "Test 12b: connection failed label"

# Test 13: custom expected code (204)
Invoke-Hc -ScriptArgs @("-ExpectedCode", "204") -MockResponse "204|0.050|0"
Assert-Equal 0 $script:LastExitCode "Test 13: 204 matches expected 204"

# Test 14: audit log written
$audit = Join-Path $TestSandbox "audit.log"
Invoke-Hc -ScriptArgs @("-AuditLog", $audit) -MockResponse "200|0.100|512"
Assert-Equal 0 $script:LastExitCode "Test 14a: audit run exits 0"
Assert-FileExists $audit "Test 14b: audit file created"
$auditContent = Get-Content -Raw -LiteralPath $audit
Assert-Contains $auditContent "outcome=healthy" "Test 14c: audit outcome healthy"

# Test 15: audit log dry-run
$audit2 = Join-Path $TestSandbox "audit2.log"
Invoke-Hc -ScriptArgs @("-DryRun", "-AuditLog", $audit2) -MockResponse "000|0.000|0"
Assert-Equal 0 $script:LastExitCode "Test 15a: audit dry-run exits 0"
Assert-FileExists $audit2 "Test 15b: audit file created on dry-run"
$auditContent2 = Get-Content -Raw -LiteralPath $audit2
Assert-Contains $auditContent2 "outcome=dry-run" "Test 15c: audit outcome dry-run"

# Test 16: verbose prints diagnostic
Invoke-Hc -ScriptArgs @("-Verbose") -MockResponse "200|0.100|512"
Assert-Equal 0 $script:LastExitCode "Test 16a: verbose exits 0"
Assert-Contains $script:LastStdout "Performing GET" "Test 16b: verbose diagnostic"

# Test 17: response time and size shown
Invoke-Hc -ScriptArgs @() -MockResponse "200|0.456|2048"
Assert-Contains $script:LastStdout "0.456s" "Test 17a: response time shown"
Assert-Contains $script:LastStdout "2048 bytes" "Test 17b: size shown"

# Test 18: SSL check prints expiry line (mock mode skips real openssl; line still printed if -SslCheck)
Invoke-Hc -ScriptArgs @("-SslCheck", "-Url", "https://example.com") -MockResponse "200|0.100|512"
Assert-Equal 0 $script:LastExitCode "Test 18a: ssl-check exits 0"
Assert-Contains $script:LastStdout "SSL expiry" "Test 18b: SSL expiry line"

# ---------- summary ----------
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

Remove-Item -Recurse -Force $TestSandbox -ErrorAction SilentlyContinue

if ($script:FailedCount -gt 0) { exit 1 }
exit 0

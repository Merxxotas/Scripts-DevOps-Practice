# Test Suite: test_k8s_monitor.ps1

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$K8sScript = Join-Path (Split-Path -Parent $ScriptDir) "k8s_monitor.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_k8s_monitor_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Invoke-K8s {
    param([string[]]$ScriptArgs, [string]$MockPods = "", [string]$MockDeleteExit = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $psi.FileName = "powershell"
    }
    $psi.Arguments = "-NoProfile -File `"$K8sScript`" " + ($ScriptArgs -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    if ($MockPods -ne "") {
        $psi.EnvironmentVariables["K8S_MONITOR_MOCK_PODS"] = $MockPods
    } else {
        $psi.EnvironmentVariables.Remove("K8S_MONITOR_MOCK_PODS") | Out-Null
    }
    if ($MockDeleteExit -ne "") {
        $psi.EnvironmentVariables["K8S_MONITOR_MOCK_DELETE_EXIT"] = $MockDeleteExit
    } else {
        $psi.EnvironmentVariables.Remove("K8S_MONITOR_MOCK_DELETE_EXIT") | Out-Null
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
Invoke-K8s -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Contains $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: invalid namespace (empty)
Invoke-K8s -ScriptArgs @("-Namespace", "")
Assert-Equal 1 $script:LastExitCode "Test 2: empty namespace exits 1"

# Test 3: invalid namespace (bad chars)
Invoke-K8s -ScriptArgs @("-Namespace", "Bad!Name")
Assert-Equal 1 $script:LastExitCode "Test 3: bad namespace exits 1"

# Test 4: invalid label (empty)
Invoke-K8s -ScriptArgs @("-LabelSelector", "")
Assert-Equal 1 $script:LastExitCode "Test 4: empty label exits 1"

# Test 5: invalid threshold (negative)
Invoke-K8s -ScriptArgs @("-RestartThreshold", "-1")
Assert-Equal 1 $script:LastExitCode "Test 5: negative threshold exits 1"

# Test 6: kubectl missing (no mock) -> exit 1 unless kubectl installed; skip if kubectl present
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Host "[SKIP] Test 6: kubectl present, skipping missing test" -ForegroundColor Yellow
} else {
    Invoke-K8s -ScriptArgs @()
    Assert-Equal 1 $script:LastExitCode "Test 6: kubectl missing exits 1"
}

# Test 7: dry-run exits 0, no deletion
$mockPods = "pod-a|Running|5,`npod-b|Running|1,"
Invoke-K8s -ScriptArgs @("-DryRun") -MockPods $mockPods
Assert-Equal 0 $script:LastExitCode "Test 7a: dry-run exits 0"
Assert-Contains $script:LastStdout "Dry run" "Test 7b: dry-run label"
Assert-Contains $script:LastStdout "would delete" "Test 7c: would delete shown"

# Test 8: no pods found -> exit 0
Invoke-K8s -ScriptArgs @() -MockPods ""
Assert-Equal 0 $script:LastExitCode "Test 8a: no pods exits 0"
Assert-Contains $script:LastStdout "No pods found" "Test 8b: no pods message"

# Test 9: healthy (below threshold) -> exit 0
$mockPods = "pod-a|Running|1,`npod-b|Running|2,"
Invoke-K8s -ScriptArgs @("-RestartThreshold", "3") -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 9a: below threshold exits 0"
Assert-Contains $script:LastStdout "kept (below threshold)" "Test 9b: kept message"

# Test 10: threshold exceeded -> delete, exit 0
$mockPods = "pod-a|Running|5,`npod-b|Running|1,"
Invoke-K8s -ScriptArgs @("-RestartThreshold", "3") -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 10a: delete success exits 0"
Assert-Contains $script:LastStdout "-> deleted" "Test 10b: deleted message"
Assert-Contains $script:LastStdout "Deleted: 1" "Test 10c: deleted count"

# Test 11: multi-container restart sum (3+2=5 > 3 -> delete)
$mockPods = "pod-a|Running|3,2,"
Invoke-K8s -ScriptArgs @("-RestartThreshold", "3") -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 11a: multi-container sum exits 0"
Assert-Contains $script:LastStdout "-> deleted" "Test 11b: deleted (sum 5 > 3)"

# Test 12: delete failure -> exit 2
$mockPods = "pod-a|Running|5,"
Invoke-K8s -ScriptArgs @() -MockPods $mockPods -MockDeleteExit "1"
Assert-Equal 2 $script:LastExitCode "Test 12a: delete failure exits 2"
Assert-Contains $script:LastStdout "delete FAILED" "Test 12b: failed message"

# Test 13: audit log
$audit = Join-Path $TestSandbox "audit.log"
$mockPods = "pod-a|Running|5,"
Invoke-K8s -ScriptArgs @("-AuditLog", $audit) -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 13a: audit run exits 0"
Assert-FileExists $audit "Test 13b: audit file created"
$auditContent = Get-Content -Raw -LiteralPath $audit
Assert-Contains $auditContent "outcome=success" "Test 13c: audit outcome success"

# Test 14: audit log dry-run
$audit2 = Join-Path $TestSandbox "audit2.log"
$mockPods = "pod-a|Running|5,"
Invoke-K8s -ScriptArgs @("-DryRun", "-AuditLog", $audit2) -MockPods $mockPods
Assert-Equal 0 $script:LastExitCode "Test 14a: audit dry-run exits 0"
Assert-FileExists $audit2 "Test 14b: audit file created on dry-run"
$auditContent2 = Get-Content -Raw -LiteralPath $audit2
Assert-Contains $auditContent2 "outcome=dry-run" "Test 14c: audit outcome dry-run"

# Test 15: force flag
$mockPods = "pod-a|Running|5,"
Invoke-K8s -ScriptArgs @("-Force") -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 15a: force run exits 0"
Assert-Contains $script:LastStdout "hard (--force)" "Test 15b: force label"

# Test 16: verbose prints diagnostic
$mockPods = "pod-a|Running|5,"
Invoke-K8s -ScriptArgs @("-Verbose") -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 16a: verbose exits 0"
Assert-Contains $script:LastStdout "Querying pods" "Test 16b: verbose diagnostic"

# Test 17: custom namespace/selector
$mockPods = "pod-a|Running|5,"
Invoke-K8s -ScriptArgs @("-Namespace", "kube-system", "-LabelSelector", "app=api", "-RestartThreshold", "2") -MockPods $mockPods -MockDeleteExit "0"
Assert-Equal 0 $script:LastExitCode "Test 17: custom flags exit 0"

# ---------- summary ----------
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

Remove-Item -Recurse -Force $TestSandbox -ErrorAction SilentlyContinue

if ($script:FailedCount -gt 0) { exit 1 }
exit 0

<#
.SYNOPSIS
    Kubernetes Pod Monitor and Restart

.DESCRIPTION
    Lists pods matching a namespace and label selector and, when a pod's restart
    count exceeds a threshold, deletes it so the owning controller recreates it.
#>

param(
    [string]$Namespace = "default",
    [string]$LabelSelector = "app=web",
    [int]$RestartThreshold = 3,
    [switch]$Force,
    [switch]$DryRun,
    [string]$AuditLog = "",
    [switch]$Verbose,
    [switch]$Help
)

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
$CReset   = "`e[0m"
$CBold    = "`e[1m"
$CDim     = "`e[2m"
$CRed     = "`e[31m"
$CGreen   = "`e[32m"
$CYellow  = "`e[33m"
$CBlue    = "`e[34m"
$CCyan    = "`e[36m"
$CMagenta = "`e[35m"

function Write-Err {
    param([string]$Message)
    Write-Host "$CRed$Message$CReset"
}

function Write-VerboseLog {
    param([string]$Message)
    if ($Verbose) { Write-Host "$CDim$Message$CReset" }
}

function Show-Usage {
    @"
Usage: k8s_monitor.ps1 [options]

Kubernetes Pod Monitor and Restart - monitor pods and restart (delete) those whose
restart count exceeds a threshold.

Options:
  -Namespace <NS>           Kubernetes namespace (default: default)
  -LabelSelector <SELECTOR> Label selector (default: app=web)
  -RestartThreshold <N>     Restart count above which a pod is deleted (default: 3)
  -Force                    Hard delete (--grace-period=0 --force)
  -DryRun                   List pods + which would be deleted, no deletion
  -AuditLog <PATH>          Append an ISO-8601 audit line per run
  -Verbose                  Diagnostic output
  -Help                     Show this help and exit

Exit codes:
  0  Success (including no pods / no deletions) or dry-run
  1  Configuration or safety violation (bad input, kubectl missing)
  2  Partial failure (a delete failed)
"@
}

if ($Help) {
    Show-Usage
    exit 0
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Namespace) -or $Namespace -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*$') {
    Write-Err "Invalid namespace: must be a non-empty DNS label"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($LabelSelector)) {
    Write-Err "Invalid label selector: must be non-empty"
    exit 1
}
if ($RestartThreshold -lt 0) {
    Write-Err "Invalid restart threshold: must be a non-negative integer"
    exit 1
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue) -and -not $env:K8S_MONITOR_MOCK_PODS) {
    Write-Err "kubectl not found on PATH"
    exit 1
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
Write-Host "$CBold$CBlue=== Kubernetes Pod Monitor ===$CReset"
Write-Host ("  {0}Namespace:{1} {2}{3}{4}" -f $CDim, $CReset, $CCyan, $Namespace, $CReset)
Write-Host ("  {0}Selector:{1}  {2}{3}{4}" -f $CDim, $CReset, $CYellow, $LabelSelector, $CReset)
Write-Host ("  {0}Threshold:{1} {2}{3}{4}" -f $CDim, $CReset, $CYellow, $RestartThreshold, $CReset)
if ($Force) {
    Write-Host ("  {0}Delete:{1}   {2}hard (--force){3}" -f $CDim, $CReset, $CRed, $CReset)
} else {
    Write-Host ("  {0}Delete:{1}   {2}graceful{3}" -f $CDim, $CReset, $CGreen, $CReset)
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------
Write-VerboseLog "Querying pods..."

$raw = ""
if ($env:K8S_MONITOR_MOCK_PODS) {
    $raw = $env:K8S_MONITOR_MOCK_PODS
} else {
    try {
        $raw = (kubectl get pods -n $Namespace -l $LabelSelector -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .status.containerStatuses[*]}{.restartCount}{","}{end}{"\n"}{end}' 2>$null)
    } catch {
        $raw = ""
    }
}
Write-VerboseLog "raw: $raw"

$names = @()
$phases = @()
$restarts = @()

foreach ($line in ($raw -split "`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '\|', 3
    if ($parts.Count -lt 2) { continue }
    $name = $parts[0]
    $phase = $parts[1]
    $rlist = if ($parts.Count -ge 3) { $parts[2] } else { "0" }
    # sum restarts
    $total = 0
    foreach ($n in ($rlist -split ',')) {
        $n = $n -replace '[^0-9]', ''
        if ($n -eq '') { $n = '0' }
        $total += [int]$n
    }
    $names += $name
    $phases += $phase
    $restarts += $total
}

$podCount = $names.Count

Write-Host ""
if ($podCount -eq 0) {
    Write-Host "$($CYellow)No pods found matching criteria.$($CReset)"
    if ($AuditLog) {
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        "$ts namespace=$Namespace label=$LabelSelector threshold=$RestartThreshold pods=0 deleted=0 outcome=no-pods" | Out-File -FilePath $AuditLog -Append -Encoding utf8 -ErrorAction SilentlyContinue
    }
    exit 0
}
Write-Host "$($CDim)Found $podCount pod(s).$($CReset)"

# ---------------------------------------------------------------------------
# Dry-run
# ---------------------------------------------------------------------------
if ($DryRun) {
    Write-Host ""
    Write-Host "$($CBold)Dry run - no deletions.$($CReset)"
    for ($i = 0; $i -lt $podCount; $i++) {
        Write-Host ("  {0}  phase={1}  restarts={2}" -f $names[$i], $phases[$i], $restarts[$i])
        if ($restarts[$i] -gt $RestartThreshold) {
            Write-Host "    $($CRed)-> would delete$($CReset)"
        } else {
            Write-Host "    $($CGreen)-> keep$($CReset)"
        }
    }
    if ($AuditLog) {
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        "$ts namespace=$Namespace label=$LabelSelector threshold=$RestartThreshold pods=$podCount deleted=0 outcome=dry-run" | Out-File -FilePath $AuditLog -Append -Encoding utf8 -ErrorAction SilentlyContinue
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Action
# ---------------------------------------------------------------------------
$deleted = 0
$failed = 0

Write-Host ""
Write-Host "$($CBold)Result$($CReset)"
for ($i = 0; $i -lt $podCount; $i++) {
    Write-Host "  $CCyan$($names[$i])$CReset"
    Write-Host ("    {0}Phase:{1}    {2}" -f $CDim, $CReset, $phases[$i])
    Write-Host ("    {0}Restarts:{1} {2}" -f $CDim, $CReset, $restarts[$i])
    if ($restarts[$i] -gt $RestartThreshold) {
        Write-VerboseLog "Deleting $($names[$i])..."
        $deleteOk = $true
        if ($env:K8S_MONITOR_MOCK_DELETE_EXIT) {
            if ($env:K8S_MONITOR_MOCK_DELETE_EXIT -ne "0") { $deleteOk = $false }
        } else {
            $deleteArgs = @("delete", "pod", $names[$i], "-n", $Namespace)
            if ($Force) { $deleteArgs += @("--grace-period=0", "--force") }
            & kubectl @deleteArgs 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $deleteOk = $false }
        }
        if ($deleteOk) {
            Write-Host "    $($CRed)-> deleted$($CReset)"
            $deleted++
        } else {
            Write-Host "    $($CRed)-> delete FAILED$($CReset)"
            $failed++
        }
    } else {
        Write-Host "    $CGreen" + "-> kept (below threshold)" + "$CReset"
    }
}

Write-Host ""
Write-Host ("{0}Pods: {1}  Deleted: {2}  Failed: {3}{4}" -f $CDim, $podCount, $deleted, $failed, $CReset)

$outcome = "success"
$exitCode = 0
if ($failed -gt 0) {
    $outcome = "partial-failure"
    $exitCode = 2
    Write-Host "$($CRed)Partial failure.$($CReset)"
} else {
    Write-Host "$($CGreen)Monitoring check completed.$($CReset)"
}

if ($AuditLog) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    "$ts namespace=$Namespace label=$LabelSelector threshold=$RestartThreshold pods=$podCount deleted=$deleted outcome=$outcome" | Out-File -FilePath $AuditLog -Append -Encoding utf8 -ErrorAction SilentlyContinue
}

exit $exitCode

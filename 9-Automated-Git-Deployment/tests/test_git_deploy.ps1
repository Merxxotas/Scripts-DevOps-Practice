# Test Suite: test_git_deploy.ps1
# Uses real git repositories under a per-run GUID sandbox (hermetic, offline).

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployScript = Join-Path (Split-Path -Parent $ScriptDir) "git_deploy.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_git_deploy_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null
$AppDir = Join-Path $TestSandbox "appdir"
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

# Host git config must not leak into the tests (e.g. core.autocrlf=true on
# Git for Windows rewrites line endings on checkout/add and dirties clones).
$emptyGitConfig = Join-Path $TestSandbox "gitconfig-empty"
New-Item -ItemType File -Path $emptyGitConfig -Force | Out-Null
$env:GIT_CONFIG_NOSYSTEM = "1"
$env:GIT_CONFIG_GLOBAL = $emptyGitConfig
$env:GIT_CONFIG_COUNT = "1"
$env:GIT_CONFIG_KEY_0 = "core.autocrlf"
$env:GIT_CONFIG_VALUE_0 = "false"

# AppDir doubles as a git work tree by default (deploy pre-flight requires one).
& git init -b main $AppDir -q | Out-Null

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Invoke-Deploy {
    param([string[]]$ScriptArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { $psi.FileName = "powershell" }
    $psi.Arguments = "-NoProfile -File `"$DeployScript`" " + ($ScriptArgs -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $script:LastStdout = $proc.StandardOutput.ReadToEnd()
    $script:LastStderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $script:LastExitCode = $proc.ExitCode
    if ($script:LastStderr) { Write-Host "STDERR: $($script:LastStderr)" -ForegroundColor DarkYellow }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -eq $Actual) { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (expected '$Expected', got '$Actual')" -ForegroundColor Red; $script:FailedCount++ }
}

function Assert-Match {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -like "*$Needle*") { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (missing '$Needle')" -ForegroundColor Red; $script:FailedCount++ }
}

function Assert-NotMatch {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -notlike "*$Needle*") { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (unexpected '$Needle' present)" -ForegroundColor Red; $script:FailedCount++ }
}

function Assert-Path {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (file missing: $Path)" -ForegroundColor Red; $script:FailedCount++ }
}

# Creates a bare "remote" with one commit (file.txt = v1), a Seed clone, and an
# AppDir clone. Returns paths. All git identity is passed per-command (-c).
function New-TestRepo {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Name)
    if (-not $PSCmdlet.ShouldProcess($Name, "Create test repositories")) { return $null }
    $root = Join-Path $TestSandbox $Name
    $remote = Join-Path $root "remote.git"
    $seed = Join-Path $root "seed"
    $app = Join-Path $root "app"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    & git init --bare -b main $remote -q | Out-Null
    & git clone -q $remote $seed | Out-Null
    "v1" | Set-Content -LiteralPath (Join-Path $seed "file.txt")
    & git -C $seed add file.txt | Out-Null
    & git -C $seed -c user.name=Test -c user.email=test@example.com commit -q -m "init" | Out-Null
    & git -C $seed push -q origin HEAD:main | Out-Null
    & git clone -q $remote $app | Out-Null
    return @{ Remote = $remote; Seed = $seed; App = $app }
}

function Set-OriginUrl {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Repo, [string]$Url)
    if (-not $PSCmdlet.ShouldProcess("$Repo -> $Url", "set git origin URL")) { return }
    & git -C $Repo remote remove origin 2>$null | Out-Null
    & git -C $Repo remote add origin $Url | Out-Null
}

function Set-GitIdentity {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Repo)
    if (-not $PSCmdlet.ShouldProcess($Repo, "set git identity")) { return }
    # local config: immune to host global config (tests isolate GIT_CONFIG_GLOBAL)
    & git -C $Repo config pull.rebase false | Out-Null
    & git -C $Repo config user.name Test | Out-Null
    & git -C $Repo config user.email test@example.com | Out-Null
}

function Get-HeadRev {
    param([string]$Repo)
    return (& git -C $Repo rev-parse HEAD).Trim()
}

function Get-StatusPorcelain {
    param([string]$Repo)
    return ((& git -C $Repo status --porcelain) -join "`n")
}

# Test 1: help
Invoke-Deploy -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Match $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: missing app dir
Invoke-Deploy -ScriptArgs @("-AppDir", (Join-Path $TestSandbox "nope"))
Assert-Equal 1 $script:LastExitCode "Test 2: missing app dir exits 1"

# Test 3: protected app dir
Invoke-Deploy -ScriptArgs @("-AppDir", "C:\")
Assert-Equal 1 $script:LastExitCode "Test 3: protected app dir exits 1"

# Test 4: invalid branch
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-Branch", "bad@branch")
Assert-Equal 1 $script:LastExitCode "Test 4: invalid branch exits 1"

# Test 5: dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun")
Assert-Equal 0 $script:LastExitCode "Test 5a: dry-run exits 0"
Assert-Match $script:LastStdout "DRY RUN" "Test 5b: dry-run label"

# Test 6: audit log with dry-run
$audit = Join-Path $TestSandbox "audit.log"
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-AuditLog", $audit)
Assert-Equal 0 $script:LastExitCode "Test 6a: audit dry-run exits 0"
Assert-Path $audit "Test 6b: audit file created"

# Test 7: verbose dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-Verbose")
Assert-Equal 0 $script:LastExitCode "Test 7: verbose dry-run exits 0"

# Test 8: skip-backup dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-SkipBackup")
Assert-Equal 0 $script:LastExitCode "Test 8: skip-backup dry-run exits 0"

# Test 9: skip-post-deploy dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-SkipPostDeploy")
Assert-Equal 0 $script:LastExitCode "Test 9: skip-post-deploy dry-run exits 0"

# Test 10: dry-run mentions rollback behavior
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun")
Assert-Match $script:LastStdout "roll back" "Test 10: dry-run mentions rollback"

# ---------- failure-safety: backup gate, rollback, repo-url verify ----------

# Test 11: up-to-date exits 0
$repos = New-TestRepo -Name "t11"
$backupDir = Join-Path $TestSandbox "backups11"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy")
Assert-Equal 0 $script:LastExitCode "Test 11a: up-to-date exits 0"
Assert-Match $script:LastStdout "Already up to date" "Test 11b: up-to-date message"

# Test 12: deploy fast-forwards to the remote head
$repos = New-TestRepo -Name "t12"
"v2" | Set-Content -LiteralPath (Join-Path $repos.Seed "file.txt")
& git -C $repos.Seed add file.txt | Out-Null
& git -C $repos.Seed -c user.name=Test -c user.email=test@example.com commit -q -m "v2" | Out-Null
& git -C $repos.Seed push -q origin HEAD:main | Out-Null
$preDeploy = Get-HeadRev -Repo $repos.App
$backupDir = Join-Path $TestSandbox "backups12"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy")
$postDeploy = Get-HeadRev -Repo $repos.App
Assert-Equal 0 $script:LastExitCode "Test 12a: deploy exits 0"
if ($preDeploy -ne $postDeploy) { Write-Host "[PASS] Test 12b: HEAD advanced" -ForegroundColor Green; $script:PassedCount++ }
else { Write-Host "[FAIL] Test 12b: HEAD did not advance" -ForegroundColor Red; $script:FailedCount++ }

# Test 13: backup gate - unwritable BackupDir aborts BEFORE any fetch/deploy
$repos = New-TestRepo -Name "t13"
"v2" | Set-Content -LiteralPath (Join-Path $repos.Seed "file.txt")
& git -C $repos.Seed add file.txt | Out-Null
& git -C $repos.Seed -c user.name=Test -c user.email=test@example.com commit -q -m "v2" | Out-Null
& git -C $repos.Seed push -q origin HEAD:main | Out-Null
$preDeploy = Get-HeadRev -Repo $repos.App
$blockingFile = Join-Path $TestSandbox "t13-blocker"
"not a directory" | Set-Content -LiteralPath $blockingFile
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $blockingFile, "-SkipPostDeploy")
Assert-Equal 2 $script:LastExitCode "Test 13a: backup failure exits 2"
Assert-Match $script:LastStdout "aborted" "Test 13b: deploy aborted message"
Assert-Equal $preDeploy (Get-HeadRev -Repo $repos.App) "Test 13c: app HEAD untouched"

# Test 14: dotfiles are included in the backup archive; visible files too
$repos = New-TestRepo -Name "t14"
"secret" | Set-Content -LiteralPath (Join-Path $repos.App ".env")
"plain" | Set-Content -LiteralPath (Join-Path $repos.App "visible.txt")
$backupDir = Join-Path $TestSandbox "backups14"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy")
Assert-Equal 0 $script:LastExitCode "Test 14a: run exits 0"
$zip = Get-ChildItem -LiteralPath $backupDir -Filter "backup_*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $zip) { Write-Host "[FAIL] Test 14b: backup zip not found" -ForegroundColor Red; $script:FailedCount++ }
else {
    $extract = Join-Path $TestSandbox "t14-extract"
    try {
        Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extract -Force
        if ((Test-Path -LiteralPath (Join-Path $extract ".env")) -and (Test-Path -LiteralPath (Join-Path $extract "visible.txt"))) {
            Write-Host "[PASS] Test 14b: backup contains dotfiles and visible files" -ForegroundColor Green; $script:PassedCount++
        } else {
            Write-Host "[FAIL] Test 14b: backup missing entries" -ForegroundColor Red; $script:FailedCount++
        }
    } finally { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue }
}

# Test 15: pull failure rolls back to the pre-deploy revision (automatic)
$repos = New-TestRepo -Name "t15"
Set-GitIdentity -Repo $repos.App
"local change" | Set-Content -LiteralPath (Join-Path $repos.App "file.txt")
& git -C $repos.App add file.txt | Out-Null
& git -C $repos.App -c user.name=Test -c user.email=test@example.com commit -q -m "local" | Out-Null
"remote change" | Set-Content -LiteralPath (Join-Path $repos.Seed "file.txt")
& git -C $repos.Seed add file.txt | Out-Null
& git -C $repos.Seed -c user.name=Test -c user.email=test@example.com commit -q -m "remote" | Out-Null
& git -C $repos.Seed push -q origin HEAD:main | Out-Null
$preDeploy = Get-HeadRev -Repo $repos.App
$backupDir = Join-Path $TestSandbox "backups15"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy")
Assert-Equal 2 $script:LastExitCode "Test 15a: pull failure exits 2"
Assert-Match $script:LastStdout "Rolled back" "Test 15b: rollback message printed"
Assert-Equal $preDeploy (Get-HeadRev -Repo $repos.App) "Test 15c: HEAD restored to pre-deploy rev"
Assert-Equal "" (Get-StatusPorcelain -Repo $repos.App) "Test 15d: working tree clean after rollback"

# Test 16: -NoRollback leaves the conflicted tree in place
$repos = New-TestRepo -Name "t16"
Set-GitIdentity -Repo $repos.App
"local change" | Set-Content -LiteralPath (Join-Path $repos.App "file.txt")
& git -C $repos.App add file.txt | Out-Null
& git -C $repos.App -c user.name=Test -c user.email=test@example.com commit -q -m "local" | Out-Null
"remote change" | Set-Content -LiteralPath (Join-Path $repos.Seed "file.txt")
& git -C $repos.Seed add file.txt | Out-Null
& git -C $repos.Seed -c user.name=Test -c user.email=test@example.com commit -q -m "remote" | Out-Null
& git -C $repos.Seed push -q origin HEAD:main | Out-Null
$preDeploy = Get-HeadRev -Repo $repos.App
$backupDir = Join-Path $TestSandbox "backups16"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy", "-NoRollback")
Assert-Equal 2 $script:LastExitCode "Test 16a: pull failure exits 2"
Assert-Match $script:LastStdout "Rollback disabled" "Test 16b: rollback disabled message"
if ((Get-StatusPorcelain -Repo $repos.App) -ne "") { Write-Host "[PASS] Test 16c: conflicted tree left in place" -ForegroundColor Green; $script:PassedCount++ }
else { Write-Host "[FAIL] Test 16c: tree unexpectedly clean" -ForegroundColor Red; $script:FailedCount++ }

# Test 17: explicit -RepoUrl matches a git@ origin against an https URL (cross-form)
Set-OriginUrl -Repo $AppDir -Url "https://github.com/acme/widgets.git"
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-RepoUrl", "git@github.com:acme/widgets.git", "-DryRun")
Assert-Equal 0 $script:LastExitCode "Test 17: cross-form origin match proceeds"

# Test 18: explicit -RepoUrl mismatch aborts with exit 1
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-RepoUrl", "https://github.com/evil/other.git", "-DryRun")
Assert-Equal 1 $script:LastExitCode "Test 18a: origin mismatch exits 1"
Assert-Match ($script:LastStdout + $script:LastStderr) "does not match" "Test 18b: mismatch message"

# Test 19: origin credentials are not leaked in the mismatch error
Set-OriginUrl -Repo $AppDir -Url "https://secret-token@github.com/acme/widgets.git"
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-RepoUrl", "https://github.com/evil/other.git", "-DryRun")
Assert-NotMatch ($script:LastStdout + $script:LastStderr) "secret-token" "Test 19: credentials not leaked"
Set-OriginUrl -Repo $AppDir -Url "https://github.com/acme/widgets.git"

# Test 20: without -RepoUrl, output reports the actual origin
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-Json")
Assert-Match $script:LastStdout '"repo_url": "https://github.com/acme/widgets.git"' "Test 20: JSON reports actual origin"

# Test 21: not a git repository -> exit 1 with clear message
$plainDir = Join-Path $TestSandbox "plain"
New-Item -ItemType Directory -Path $plainDir -Force | Out-Null
Invoke-Deploy -ScriptArgs @("-AppDir", $plainDir)
Assert-Equal 1 $script:LastExitCode "Test 21a: not a git repo exits 1"
Assert-Match ($script:LastStdout + $script:LastStderr) "not a git repository" "Test 21b: clear not-a-repo message"

# Test 22: rollback is audited
$repos = New-TestRepo -Name "t22"
Set-GitIdentity -Repo $repos.App
"local change" | Set-Content -LiteralPath (Join-Path $repos.App "file.txt")
& git -C $repos.App add file.txt | Out-Null
& git -C $repos.App -c user.name=Test -c user.email=test@example.com commit -q -m "local" | Out-Null
"remote change" | Set-Content -LiteralPath (Join-Path $repos.Seed "file.txt")
& git -C $repos.Seed add file.txt | Out-Null
& git -C $repos.Seed -c user.name=Test -c user.email=test@example.com commit -q -m "remote" | Out-Null
& git -C $repos.Seed push -q origin HEAD:main | Out-Null
$backupDir = Join-Path $TestSandbox "backups22"
$audit22 = Join-Path $TestSandbox "audit22.log"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy", "-AuditLog", $audit22)
Assert-Match (Get-Content -LiteralPath $audit22 -Raw) "Rolled back" "Test 22: audit records rollback"

# Test 23: JSON result is rolled-back on pull failure
$repos = New-TestRepo -Name "t23"
Set-GitIdentity -Repo $repos.App
"local change" | Set-Content -LiteralPath (Join-Path $repos.App "file.txt")
& git -C $repos.App add file.txt | Out-Null
& git -C $repos.App -c user.name=Test -c user.email=test@example.com commit -q -m "local" | Out-Null
"remote change" | Set-Content -LiteralPath (Join-Path $repos.Seed "file.txt")
& git -C $repos.Seed add file.txt | Out-Null
& git -C $repos.Seed -c user.name=Test -c user.email=test@example.com commit -q -m "remote" | Out-Null
& git -C $repos.Seed push -q origin HEAD:main | Out-Null
$backupDir = Join-Path $TestSandbox "backups23"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipPostDeploy", "-Json")
Assert-Match $script:LastStdout '"result": "rolled-back"' "Test 23: JSON result rolled-back"

# Test 24: -SkipBackup creates no archive
$repos = New-TestRepo -Name "t24"
$backupDir = Join-Path $TestSandbox "backups24"
Invoke-Deploy -ScriptArgs @("-AppDir", $repos.App, "-BackupDir", $backupDir, "-SkipBackup", "-SkipPostDeploy")
$zips = Get-ChildItem -LiteralPath $backupDir -Filter "backup_*.zip" -ErrorAction SilentlyContinue
Assert-Equal 0 @($zips).Count "Test 24: no backup with -SkipBackup"

# Test 25: explicit -RepoUrl with credentials and a MATCHING origin does not leak them
Set-OriginUrl -Repo $AppDir -Url "https://secret-token@github.com/acme/widgets.git"
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-RepoUrl", "https://secret-token@github.com/acme/widgets.git", "-DryRun", "-Json")
Assert-Equal 0 $script:LastExitCode "Test 25a: matching origin proceeds"
Assert-NotMatch ($script:LastStdout + $script:LastStderr) "secret-token" "Test 25b: credentials not leaked"
Set-OriginUrl -Repo $AppDir -Url "https://github.com/acme/widgets.git"

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

Remove-Item -Recurse -Force $TestSandbox -ErrorAction SilentlyContinue

if ($script:FailedCount -gt 0) { exit 1 }
exit 0

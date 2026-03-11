# =============================================================================
# OpenClaw / Clawdbot Uninstaller — Windows (PowerShell)
# Run in PowerShell as normal user (no admin required)
# Usage: .\uninstall-windows.ps1 [-KeepConfig | -Purge]
#   -KeepConfig   Skip deleting config directories (keep your data)
#   -Purge        Delete config dirs immediately, no backup
#
# NOTE: If running inside WSL2, use uninstall-linux.sh instead.
# =============================================================================

param(
    [switch]$KeepConfig,
    [switch]$Purge
)

if ($KeepConfig -and $Purge) {
    Write-Host "Error: -KeepConfig and -Purge are mutually exclusive." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Continue"

function Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err     { param($msg) Write-Host "[ERR]   $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  OpenClaw Uninstaller — Windows        " -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""

# ── Step 1: Stop & remove scheduled tasks ────────────────────────────────────
Info "Step 1/5  Stopping scheduled tasks..."
$taskPatterns = @("openclaw", "clawdbot", "moltbot")
$foundTask = $false
foreach ($pattern in $taskPatterns) {
    $tasks = Get-ScheduledTask -TaskName "*$pattern*" -ErrorAction SilentlyContinue
    foreach ($task in $tasks) {
        $foundTask = $true
        Stop-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Success "Removed scheduled task: $($task.TaskName)"
    }
}
if (-not $foundTask) { Info "No scheduled tasks found — skipping." }

# ── Step 2: Kill remaining processes ─────────────────────────────────────────
Info "Step 2/5  Killing any remaining gateway processes..."
$killed = $false
$processPatterns = @("openclaw", "clawdbot")
foreach ($pattern in $processPatterns) {
    $procs = Get-Process -Name "*$pattern*" -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Success "Killed process: $($proc.Name) (PID $($proc.Id))"
        $killed = $true
    }
}
# Also check node processes running openclaw/clawdbot scripts
$nodeProcs = Get-WmiObject Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "openclaw|clawdbot" }
foreach ($proc in $nodeProcs) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    Success "Killed node process (PID $($proc.ProcessId))"
    $killed = $true
}
if (-not $killed) { Info "No running gateway processes found." }

# ── Step 3: Uninstall npm packages ───────────────────────────────────────────
Info "Step 3/5  Uninstalling npm global packages..."
$packages = @("openclaw", "clawdbot", "moltbot")
foreach ($pkg in $packages) {
    $installed = npm list -g --depth=0 2>$null | Select-String $pkg
    if ($installed) {
        npm uninstall -g $pkg 2>$null
        Success "Uninstalled npm package: $pkg"
    } else {
        Info "npm package not found: $pkg — skipping."
    }
}

# ── Step 4: Remove config directories ────────────────────────────────────────
if ($KeepConfig) {
    Warn "Step 4/5  -KeepConfig set, skipping config directory removal."
} elseif ($Purge) {
    Warn "Step 4/5  -Purge set, deleting config directories WITHOUT backup..."
    foreach ($dir in @("$env:USERPROFILE\.openclaw","$env:USERPROFILE\.clawdbot","$env:USERPROFILE\.moltbot")) {
        if (Test-Path $dir) {
            Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
            Success "Purged: $dir"
        }
    }
} else {
    Info "Step 4/5  Backing up and removing config directories..."
    $backupDate = Get-Date -Format "yyyyMMdd_HHmmss"
    foreach ($dir in @("$env:USERPROFILE\.openclaw","$env:USERPROFILE\.clawdbot","$env:USERPROFILE\.moltbot")) {
        if (Test-Path $dir) {
            $backup = "${dir}-backup-${backupDate}"
            Copy-Item -Recurse -Path $dir -Destination $backup -ErrorAction SilentlyContinue
            Success "Backed up: $dir → $backup"
            Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
            Success "Removed:   $dir"
        }
    }
}

# ── Step 5: Clean up PATH / environment remnants ─────────────────────────────
Info "Step 5/5  Checking user PATH for openclaw entries..."
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -match "openclaw|clawdbot") {
    $cleanPath = ($userPath -split ";" | Where-Object { $_ -notmatch "openclaw|clawdbot" }) -join ";"
    [System.Environment]::SetEnvironmentVariable("PATH", $cleanPath, "User")
    Success "Removed openclaw/clawdbot entries from user PATH."
} else {
    Info "No openclaw/clawdbot entries in user PATH — skipping."
}

# ── Verification ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  Verification                          " -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

$allOk = $true

$npmCheck = npm list -g --depth=0 2>$null | Select-String -Pattern "openclaw|clawd|moltbot"
if ($npmCheck) {
    Err "npm packages still present"
    $allOk = $false
} else {
    Success "npm packages removed"
}

$configDirs = @("$env:USERPROFILE\.openclaw", "$env:USERPROFILE\.clawdbot", "$env:USERPROFILE\.moltbot")
foreach ($dir in $configDirs) {
    if (Test-Path $dir) {
        Err "Config dir still exists: $dir"
        $allOk = $false
    } else {
        Success "Config dir removed: $dir"
    }
}

$remainingTasks = Get-ScheduledTask -TaskName "*openclaw*" -ErrorAction SilentlyContinue
if ($remainingTasks) {
    Err "Scheduled tasks still present"
    $allOk = $false
} else {
    Success "No scheduled tasks remaining"
}

$remainingProcs = Get-Process -Name "*openclaw*","*clawdbot*" -ErrorAction SilentlyContinue
if ($remainingProcs) {
    Err "Gateway processes still running"
    $allOk = $false
} else {
    Success "No gateway processes running"
}

Write-Host ""
if ($allOk) {
    Write-Host "✅  OpenClaw fully removed from this machine." -ForegroundColor Green
} else {
    Write-Host "⚠️   Some items could not be removed — see errors above." -ForegroundColor Red
    exit 1
}

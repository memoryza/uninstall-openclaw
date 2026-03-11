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

# ── Step 1: Stop & remove ALL scheduled tasks ────────────────────────────────
# Covers: gateway + node daemon, default + profile variants
# Sources: constants.js
#   GATEWAY: "Clawdbot Gateway"  (default)
#            "Clawdbot Gateway (<profile>)" (multi-profile)
#   NODE:    "Clawdbot Node"
#   openclaw variants: "Openclaw Gateway", "Openclaw Node"
#   moltbot: "Moltbot Gateway"
Info "Step 1/5  Stopping scheduled tasks..."
$foundTask = $false

# Patterns to match task names (wildcards)
$taskPatterns = @(
    "*clawdbot*",
    "*openclaw*",
    "*moltbot*",
    "Clawdbot Gateway*",
    "Clawdbot Node*",
    "Openclaw Gateway*",
    "Openclaw Node*",
    "Moltbot Gateway*"
)

$removedTasks = @{}
foreach ($pattern in $taskPatterns) {
    $tasks = Get-ScheduledTask -TaskName $pattern -ErrorAction SilentlyContinue
    foreach ($task in $tasks) {
        if ($removedTasks.ContainsKey($task.TaskName)) { continue }
        $removedTasks[$task.TaskName] = $true
        $foundTask = $true
        Stop-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Success "Removed scheduled task: $($task.TaskName)"
    }
}
if (-not $foundTask) { Info "No scheduled tasks found — skipping." }

# ── Step 2: Kill remaining processes ─────────────────────────────────────────
Info "Step 2/5  Killing any remaining processes..."
$killed = $false

# Kill by process name
foreach ($pattern in @("*openclaw*", "*clawdbot*")) {
    foreach ($proc in (Get-Process -Name $pattern -ErrorAction SilentlyContinue)) {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Success "Killed process: $($proc.Name) (PID $($proc.Id))"
        $killed = $true
    }
}

# Kill node.exe processes running openclaw/clawdbot scripts
$nodeProcs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "openclaw|clawdbot" }
foreach ($proc in $nodeProcs) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    Success "Killed node process (PID $($proc.ProcessId))"
    $killed = $true
}

if (-not $killed) { Info "No running processes found." }

# ── Step 3: Uninstall npm packages ───────────────────────────────────────────
Info "Step 3/5  Uninstalling npm global packages..."
foreach ($pkg in @("openclaw", "clawdbot", "moltbot")) {
    if (npm list -g --depth=0 2>$null | Select-String $pkg) {
        npm uninstall -g $pkg 2>$null
        Success "Uninstalled npm package: $pkg"
    } else {
        Info "Not found: $pkg — skipping."
    }
}

# ── Step 4: Remove config / state directories ─────────────────────────────────
# Default: %USERPROFILE%\.clawdbot  (CLAWDBOT_STATE_DIR overrides this)
$stateDir = $env:CLAWDBOT_STATE_DIR
$dirsToRemove = @(
    "$env:USERPROFILE\.openclaw",
    "$env:USERPROFILE\.clawdbot",
    "$env:USERPROFILE\.moltbot"
)
if ($stateDir -and $stateDir -ne "$env:USERPROFILE\.clawdbot") {
    $dirsToRemove += $stateDir
}

if ($KeepConfig) {
    Warn "Step 4/5  -KeepConfig set, skipping config directory removal."
} elseif ($Purge) {
    Warn "Step 4/5  -Purge: deleting config directories WITHOUT backup..."
    foreach ($dir in $dirsToRemove) {
        if (Test-Path $dir) {
            Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
            Success "Purged: $dir"
        }
    }
} else {
    Info "Step 4/5  Backing up and removing config directories..."
    $backupDate = Get-Date -Format "yyyyMMdd_HHmmss"
    foreach ($dir in $dirsToRemove) {
        if (Test-Path $dir) {
            $backup = "${dir}-backup-${backupDate}"
            Copy-Item -Recurse -Path $dir -Destination $backup -ErrorAction SilentlyContinue
            Success "Backed up: $dir → $backup"
            Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
            Success "Removed:   $dir"
        }
    }
}

# ── Step 5: Clean up PATH + temp files ───────────────────────────────────────
Info "Step 5/5  Cleaning up PATH and temp files..."

# User PATH
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -match "openclaw|clawdbot") {
    $cleanPath = ($userPath -split ";" | Where-Object { $_ -notmatch "openclaw|clawdbot" }) -join ";"
    [System.Environment]::SetEnvironmentVariable("PATH", $cleanPath, "User")
    Success "Removed openclaw/clawdbot entries from user PATH."
} else {
    Info "No openclaw/clawdbot entries in user PATH — skipping."
}

# Temp log files
foreach ($pattern in @("clawdbot*.log", "openclaw*.log")) {
    foreach ($f in (Get-ChildItem -Path $env:TEMP -Filter $pattern -ErrorAction SilentlyContinue)) {
        Remove-Item -Force -Path $f.FullName -ErrorAction SilentlyContinue
        Success "Removed temp file: $($f.FullName)"
    }
}

# ── Verification ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  Verification                          " -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

$allOk = $true

if (npm list -g --depth=0 2>$null | Select-String "openclaw|clawd|moltbot") {
    Err "npm packages still present"; $allOk = $false
} else { Success "npm packages removed" }

foreach ($dir in @("$env:USERPROFILE\.openclaw", "$env:USERPROFILE\.clawdbot", "$env:USERPROFILE\.moltbot")) {
    if (Test-Path $dir) { Err "Config dir still exists: $dir"; $allOk = $false }
    else { Success "Config dir removed: $dir" }
}

$remainingTasks = Get-ScheduledTask -TaskName "*clawdbot*" -ErrorAction SilentlyContinue
$remainingTasks += Get-ScheduledTask -TaskName "*openclaw*" -ErrorAction SilentlyContinue
if ($remainingTasks) {
    foreach ($t in $remainingTasks) { Err "Scheduled task still present: $($t.TaskName)" }
    $allOk = $false
} else { Success "No scheduled tasks remaining" }

$remainingProcs = Get-Process -Name "*openclaw*","*clawdbot*" -ErrorAction SilentlyContinue
if ($remainingProcs) { Err "Processes still running"; $allOk = $false }
else { Success "No processes running" }

Write-Host ""
if ($allOk) {
    Write-Host "✅  OpenClaw fully removed from this machine." -ForegroundColor Green
} else {
    Write-Host "⚠️   Some items could not be removed — see errors above." -ForegroundColor Red
    exit 1
}

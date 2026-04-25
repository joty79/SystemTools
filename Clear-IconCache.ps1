#requires -version 7.0
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Rebuilds the Windows icon cache, thumbnail cache, and UWP AppIconCache.

.DESCRIPTION
    Kills all shell processes that hold locks on cache files (Explorer, SearchHost,
    ShellExperienceHost, StartMenuExperienceHost, etc.), deletes all cache databases,
    then lets Windows auto-restart the shell cleanly.

    This is MORE thorough than BleachBit's "Windows Explorer > Thumbnails" cleaner,
    which only handles thumbcache*.db and does NOT touch icon cache or AppIconCache.

    Cache types cleaned:
      - Icon cache     : %LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache*.db
      - Classic cache  : %LOCALAPPDATA%\IconCache.db
      - Thumb cache    : %LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache*.db
      - AppIconCache   : (Start Menu / Windows Search UWP app icons)
      - StartMenu Temp : ShellExperienceHost TempState

.PARAMETER Thumbnails
    Also delete thumbnail cache files (thumbcache*.db). Off by default because
    thumbnail rebuild can be slow on large photo libraries.

.PARAMETER NoPause
    Skip the "Press Enter to close" prompt at the end.

.EXAMPLE
    # Rebuild icon cache only
    .\Clear-IconCache.ps1

.EXAMPLE
    # Rebuild both icon AND thumbnail cache
    .\Clear-IconCache.ps1 -Thumbnails

.NOTES
    Author  : SystemTools
    Date    : 2026-04-25
    Requires: Admin rights (to kill system processes and delete protected cache files)
#>
[CmdletBinding()]
param(
    [switch]$Thumbnails,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Paths ──────────────────────────────────────────────────────────────────
$CacheDir      = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
$ClassicCache  = "$env:LOCALAPPDATA\IconCache.db"
$AppIconCache  = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\AppIconCache"
$StartMenuTemp = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\TempState"

# ─── Phase 1: Kill shell processes ──────────────────────────────────────────
Write-Host ''
Write-Host '=== Phase 1: Stopping shell processes ===' -ForegroundColor Cyan

$shellProcesses = @(
    'explorer'
    'SearchHost'
    'SearchUI'
    'StartMenuExperienceHost'
    'ShellExperienceHost'
    'TextInputHost'
)

foreach ($procName in $shellProcesses) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($procs) {
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
        Write-Host "  Killed: $procName" -ForegroundColor Yellow
    }
}

# Give processes time to fully release file handles
Start-Sleep -Seconds 3

# ─── Phase 2: Delete icon cache ─────────────────────────────────────────────
Write-Host ''
Write-Host '=== Phase 2: Deleting icon cache ===' -ForegroundColor Cyan

$totalDeleted = 0
$totalFailed  = 0

# Icon cache files
$iconFiles = @(Get-ChildItem "$CacheDir\iconcache*" -Force -ErrorAction SilentlyContinue)
foreach ($f in $iconFiles) {
    try {
        Remove-Item $f.FullName -Force -ErrorAction Stop
        Write-Host "  [OK] $($f.Name)" -ForegroundColor Green
        $totalDeleted++
    }
    catch {
        Write-Host "  [LOCKED] $($f.Name)" -ForegroundColor Red
        $totalFailed++
    }
}

# Classic IconCache.db
if (Test-Path $ClassicCache) {
    try {
        Remove-Item $ClassicCache -Force -ErrorAction Stop
        Write-Host "  [OK] IconCache.db" -ForegroundColor Green
        $totalDeleted++
    }
    catch {
        Write-Host "  [LOCKED] IconCache.db" -ForegroundColor Red
        $totalFailed++
    }
}

# ─── Phase 3: Delete thumbnail cache (optional) ─────────────────────────────
if ($Thumbnails) {
    Write-Host ''
    Write-Host '=== Phase 3: Deleting thumbnail cache ===' -ForegroundColor Cyan

    $thumbFiles = @(Get-ChildItem "$CacheDir\thumbcache*" -Force -ErrorAction SilentlyContinue)
    foreach ($f in $thumbFiles) {
        try {
            Remove-Item $f.FullName -Force -ErrorAction Stop
            $totalDeleted++
        }
        catch {
            $totalFailed++
        }
    }
    Write-Host "  Processed $($thumbFiles.Count) thumbcache files" -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host '=== Phase 3: Thumbnail cache SKIPPED (use -Thumbnails) ===' -ForegroundColor DarkGray
}

# ─── Phase 4: Delete AppIconCache (UWP/Start Menu icons) ────────────────────
Write-Host ''
Write-Host '=== Phase 4: Clearing UWP AppIconCache ===' -ForegroundColor Cyan

if (Test-Path $AppIconCache) {
    Remove-Item "$AppIconCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  AppIconCache cleared" -ForegroundColor Green
}
else {
    Write-Host "  AppIconCache not found (OK)" -ForegroundColor DarkGray
}

if (Test-Path $StartMenuTemp) {
    Remove-Item "$StartMenuTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  StartMenu TempState cleared" -ForegroundColor Green
}

# ─── Phase 5: Handle locked files ───────────────────────────────────────────
if ($totalFailed -gt 0) {
    Write-Host ''
    Write-Host "=== Phase 5: $totalFailed files still locked ===" -ForegroundColor Yellow
    Write-Host '  Scheduling boot-time deletion via RunOnce...' -ForegroundColor Yellow

    $cmdLine = "cmd.exe /c `"del /f /a /q `"$CacheDir\iconcache*`" & del /f /a /q `"$ClassicCache`"`""
    $runOncePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    Set-ItemProperty -Path $runOncePath -Name 'CleanIconCache' -Value $cmdLine -Type String
    Write-Host '  RunOnce registered — locked files will be deleted at next boot' -ForegroundColor Yellow
    Write-Host '  REBOOT REQUIRED for complete cleanup!' -ForegroundColor Red
}

# ─── Phase 6: Force icon refresh + restart shell ────────────────────────────
Write-Host ''
Write-Host '=== Phase 6: Refreshing icons ===' -ForegroundColor Cyan

# ie4uinit forces a system-wide icon refresh
& ie4uinit.exe -show 2>$null
Write-Host '  ie4uinit -show executed' -ForegroundColor Green

# Let Windows auto-restart Explorer via winlogon (no ghost process)
# Do NOT Start-Process explorer.exe — that creates a duplicate zombie
Start-Sleep -Milliseconds 500

# Check if Explorer auto-restarted
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$shellAlive = $false
do {
    Start-Sleep -Milliseconds 300
    $ep = Get-Process -Name explorer -ErrorAction SilentlyContinue
    if ($ep) { $shellAlive = $true }
} while (-not $shellAlive -and $sw.Elapsed.TotalSeconds -lt 8)

if ($shellAlive) {
    Write-Host '  Explorer auto-restarted (clean)' -ForegroundColor Green
}
else {
    # Fallback: start it manually if winlogon didn't
    Start-Process explorer.exe
    Write-Host '  Explorer started manually' -ForegroundColor Yellow
}

# ─── Summary ────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
Write-Host "  Deleted: $totalDeleted files" -ForegroundColor Green
if ($totalFailed -gt 0) {
    Write-Host "  Locked:  $totalFailed files (scheduled for boot-time deletion)" -ForegroundColor Yellow
    Write-Host '  >> REBOOT to complete the cleanup <<' -ForegroundColor Red
}
else {
    Write-Host '  All cache files cleared successfully!' -ForegroundColor Green
}

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

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

.PARAMETER DiagnoseUwpPngIcons
    Print diagnostics for the known UWP/Search generic PNG icon issue without
    changing registry keys or deleting cache files.

.PARAMETER FixUwpPngIcons
    Remove third-party .png thumbnail shell extension registrations that can
    make UWP/MSIX app icons appear as generic PNG file-type icons in Start
    Menu Search. Cache cleanup still runs afterward.

.PARAMETER ResetPngUserChoice
    Also remove the current user's .png UserChoice association. Use only when
    it points to stale/broken image viewer ProgIDs; Windows will ask for a new
    default PNG app later.

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
    [switch]$DiagnoseUwpPngIcons,
    [switch]$FixUwpPngIcons,
    [switch]$ResetPngUserChoice,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Paths ──────────────────────────────────────────────────────────────────
$CacheDir      = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
$ClassicCache  = "$env:LOCALAPPDATA\IconCache.db"
$AppIconCache  = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\AppIconCache"
$StartMenuTemp = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\TempState"

function Get-RegistryDefaultValue {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    try {
        return (Get-ItemProperty -LiteralPath $LiteralPath -ErrorAction Stop).'(default)'
    }
    catch {
        return $null
    }
}

function Get-PngShellExtensionRows {
    $scanRoots = @(
        [pscustomobject]@{
            Label = 'HKCU'
            Path = 'Registry::HKEY_CURRENT_USER\Software\Classes\.png\shellex'
            Writable = $true
        }
        [pscustomobject]@{
            Label = 'HKLM'
            Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\.png\shellex'
            Writable = $true
        }
        [pscustomobject]@{
            Label = 'HKCR merged'
            Path = 'Registry::HKEY_CLASSES_ROOT\.png\shellex'
            Writable = $false
        }
    )

    foreach ($scanRoot in $scanRoots) {
        if (-not (Test-Path -LiteralPath $scanRoot.Path)) { continue }

        Get-ChildItem -LiteralPath $scanRoot.Path -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $clsid = Get-RegistryDefaultValue -LiteralPath $_.PSPath
            $handlerName = if ($clsid) {
                Get-RegistryDefaultValue -LiteralPath "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid"
            }
            else {
                $null
            }

            [pscustomobject]@{
                Root = $scanRoot.Label
                Path = $_.Name
                PSPath = $_.PSPath
                KeyName = $_.PSChildName
                Clsid = $clsid
                Handler = $handlerName
                Writable = $scanRoot.Writable
            }
        }
    }
}

function Show-UwpPngIconDiagnostics {
    Write-Host ''
    Write-Host '=== UWP/Search PNG icon diagnostics ===' -ForegroundColor Cyan

    $hkcrPngDefault = Get-RegistryDefaultValue -LiteralPath 'Registry::HKEY_CLASSES_ROOT\.png'
    $hkcuPngDefault = Get-RegistryDefaultValue -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\.png'
    $userChoice = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.png\UserChoice' -ErrorAction SilentlyContinue
    $userChoiceProgId = if ($userChoice -and ($userChoice.PSObject.Properties.Name -contains 'ProgId')) { $userChoice.ProgId } else { $null }
    $shellExtensionRows = @(Get-PngShellExtensionRows)

    Write-Host ("  HKCR .png default    : {0}" -f $(if ($hkcrPngDefault) { $hkcrPngDefault } else { '<empty>' }))
    Write-Host ("  HKCU .png default    : {0}" -f $(if ($hkcuPngDefault) { $hkcuPngDefault } else { '<empty>' }))
    Write-Host ("  UserChoice ProgId    : {0}" -f $(if ($userChoiceProgId) { $userChoiceProgId } else { '<none>' }))

    if ($shellExtensionRows.Count -gt 0) {
        Write-Host '  .png shell extensions:' -ForegroundColor Yellow
        foreach ($row in $shellExtensionRows) {
            $handler = if ($row.Handler) { $row.Handler } else { '<unknown handler>' }
            Write-Host ("    [{0}] {1} -> {2}" -f $row.Root, $row.KeyName, $handler) -ForegroundColor Yellow
        }
    }
    else {
        Write-Host '  .png shell extensions: none' -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $AppIconCache) {
        $appIconFiles = @(Get-ChildItem -LiteralPath $AppIconCache -Recurse -File -ErrorAction SilentlyContinue)
        $sameSizeGroups = @($appIconFiles | Group-Object Length | Sort-Object Count -Descending | Select-Object -First 3)
        Write-Host ("  Search AppIconCache  : {0} files" -f $appIconFiles.Count)
        foreach ($group in $sameSizeGroups) {
            Write-Host ("    Size {0}: {1} files" -f $group.Name, $group.Count) -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host '  Search AppIconCache  : not found' -ForegroundColor DarkGray
    }

    $wSearch = Get-Service -Name WSearch -ErrorAction SilentlyContinue
    if ($wSearch) {
        Write-Host ("  Windows Search       : {0} / {1}" -f $wSearch.Status, $wSearch.StartType)
    }

    if ($shellExtensionRows.Count -gt 0) {
        Write-Host '  Verdict              : .png shell extensions are present; use -FixUwpPngIcons if UWP Search icons show PNG file icons.' -ForegroundColor Yellow
    }
    elseif ($userChoiceProgId -and $userChoiceProgId -notin @('pngfile', 'AppX43hnxtbyyps62jhe9sqpdzxn1790zetc')) {
        Write-Host '  Verdict              : no .png shell extensions found; stale UserChoice may still be worth resetting manually.' -ForegroundColor Yellow
    }
    else {
        Write-Host '  Verdict              : no obvious registry trigger found.' -ForegroundColor Green
    }
}

function Remove-PngShellExtensions {
    $writableRows = @(Get-PngShellExtensionRows | Where-Object { $_.Writable })

    Write-Host ''
    Write-Host '=== Removing .png shell extensions ===' -ForegroundColor Cyan

    if ($writableRows.Count -eq 0) {
        Write-Host '  No writable .png shell extension keys found.' -ForegroundColor Green
        return
    }

    foreach ($row in $writableRows) {
        $regExePath = $row.Path -replace '^HKEY_CURRENT_USER\\', 'HKCU\' -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\'
        try {
            Remove-Item -LiteralPath $row.PSPath -Recurse -Force -ErrorAction Stop
            Write-Host ("  [OK] Removed [{0}] {1}" -f $row.Root, $row.KeyName) -ForegroundColor Green
        }
        catch {
            & reg.exe delete $regExePath /f *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("  [OK] Removed [{0}] {1} via reg.exe fallback" -f $row.Root, $row.KeyName) -ForegroundColor Green
            }
            else {
                Write-Host ("  [FAILED] {0}: {1}" -f $row.Path, $_.Exception.Message) -ForegroundColor Red
            }
        }
    }
}

function Remove-PngUserChoice {
    $userChoicePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.png\UserChoice'

    Write-Host ''
    Write-Host '=== Resetting .png UserChoice ===' -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $userChoicePath)) {
        Write-Host '  No .png UserChoice key found.' -ForegroundColor DarkGray
        return
    }

    try {
        Remove-Item -LiteralPath $userChoicePath -Recurse -Force -ErrorAction Stop
        Write-Host '  [OK] Removed .png UserChoice. Pick your preferred PNG default app next time Windows asks.' -ForegroundColor Green
    }
    catch {
        Write-Host ("  [FAILED] Could not remove .png UserChoice: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host '  This key can be ACL-protected. Re-run from an elevated terminal if needed.' -ForegroundColor Yellow
    }
}

if ($DiagnoseUwpPngIcons -and -not $FixUwpPngIcons -and -not $ResetPngUserChoice) {
    Show-UwpPngIconDiagnostics
    if (-not $NoPause) {
        Write-Host ''
        Read-Host 'Press Enter to close'
    }
    return
}

if ($DiagnoseUwpPngIcons -or $FixUwpPngIcons -or $ResetPngUserChoice) {
    Show-UwpPngIconDiagnostics
}

if ($FixUwpPngIcons) {
    Remove-PngShellExtensions
}

if ($ResetPngUserChoice) {
    Remove-PngUserChoice
}

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
$iconFiles = @(Get-ChildItem "$CacheDir\iconcache*" -File -Force -ErrorAction SilentlyContinue)
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

if ($FixUwpPngIcons -or $DiagnoseUwpPngIcons) {
    Write-Host ''
    Write-Host '=== UWP/Search icon redraw note ===' -ForegroundColor Cyan
    Write-Host '  If only some Start Search app icons refresh immediately, force a visual redraw:' -ForegroundColor Yellow
    Write-Host '  Settings > System > Display > Scale: change 125% -> 100%, wait a few seconds, then change back.' -ForegroundColor Yellow
    Write-Host '  A reboot should also complete the locked-cache cleanup and redraw path.' -ForegroundColor Yellow
}

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

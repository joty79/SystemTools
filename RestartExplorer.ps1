#requires -version 7.0
[CmdletBinding()]
param(
    [string]$TargetPath = (Get-Location).Path,
    [switch]$ReopenFolder,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ExplorerPathArgument {
    param([string]$PathToUse)

    if ([string]::IsNullOrWhiteSpace($PathToUse)) { return '' }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($PathToUse)
    }
    catch {
        return ''
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        return ''
    }

    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if ($fullPath.TrimEnd('\') -ieq $desktopPath.TrimEnd('\')) {
        return ''
    }

    return $fullPath
}

function Restart-Explorer {
    param(
        [string]$PathToUse,
        [bool]$ShouldReopenFolder
    )

    # Resolve target path before killing Explorer
    $resolvedPath = ''
    if ($ShouldReopenFolder) {
        $resolvedPath = Resolve-ExplorerPathArgument -PathToUse $PathToUse
    }

    Write-Host ''
    Write-Host 'Stopping Explorer...' -ForegroundColor Yellow

    $runningExplorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    foreach ($process in $runningExplorer) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
        }
    }

    try {
        Wait-Process -Name explorer -Timeout 5 -ErrorAction SilentlyContinue
    }
    catch {
    }

    # Do NOT Start-Process explorer.exe — Windows auto-restarts the shell via winlogon.
    # Any Start-Process here would create a SECOND explorer.exe (the zombie).

    if (-not $ShouldReopenFolder -or [string]::IsNullOrEmpty($resolvedPath)) {
        Start-Sleep -Milliseconds 500
        Write-Host 'Explorer restarted (auto). No folder window was reopened.' -ForegroundColor Green
        return
    }

    # --- Tier 2: Wait for shell auto-restart, then reopen folder via COM ---
    Write-Host 'Waiting for shell auto-restart...' -ForegroundColor DarkGray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $shellAlive = $false
    do {
        Start-Sleep -Milliseconds 300
        $ep = Get-Process -Name explorer -ErrorAction SilentlyContinue
        if ($ep) { $shellAlive = $true }
    } while (-not $shellAlive -and $sw.Elapsed.TotalSeconds -lt 10)

    if (-not $shellAlive) {
        Write-Host 'Shell did not auto-restart within timeout. Skipping folder reopen.' -ForegroundColor Red
        return
    }

    # Extra stabilization — let the shell finish initializing desktop/taskbar
    Start-Sleep -Seconds 2

    Write-Host "Reopening folder: $resolvedPath" -ForegroundColor Cyan
    try {
        # COM Shell.Application.Open reuses the existing shell process in many configs,
        # instead of spawning a brand-new explorer.exe like Start-Process would.
        $shell = New-Object -ComObject Shell.Application
        $shell.Open($resolvedPath)
        Write-Host 'Folder reopened via Shell.Application COM.' -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to reopen folder: $_" -ForegroundColor Red
    }
}

Restart-Explorer -PathToUse $TargetPath -ShouldReopenFolder $ReopenFolder.IsPresent

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

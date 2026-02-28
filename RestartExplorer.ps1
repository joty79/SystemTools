#requires -version 7.0
[CmdletBinding()]
param(
    [string]$TargetPath = (Get-Location).Path,
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
    param([string]$PathToUse)

    Write-Host ''
    Write-Host 'Restarting Explorer...' -ForegroundColor Yellow

    foreach ($process in (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
        }
        catch {
        }
    }

    Start-Sleep -Milliseconds 500

    $pathArg = Resolve-ExplorerPathArgument -PathToUse $PathToUse
    if ([string]::IsNullOrWhiteSpace($pathArg)) {
        Start-Process -FilePath 'explorer.exe'
        Write-Host 'Explorer restarted.' -ForegroundColor Green
        return
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList $pathArg
    Write-Host "Explorer restarted at: $pathArg" -ForegroundColor Green
}

Restart-Explorer -PathToUse $TargetPath

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

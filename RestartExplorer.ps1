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

    Start-Sleep -Milliseconds 500
    Write-Host 'Explorer stopped. No folder window was reopened.' -ForegroundColor Green
}

Restart-Explorer -PathToUse $TargetPath

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Menu','Status','UpdateAll','UpdateTool')]
    [string]$Action = 'Menu',
    [string]$ToolName = '',
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Tools = @(
    [pscustomobject]@{ Name = 'SystemTools'; Label = 'SystemTools'; Repo = 'joty79/SystemTools'; InstallFolder = 'SystemToolsContext' },
    [pscustomobject]@{ Name = 'TakeOwnership'; Label = 'Take Ownership'; Repo = 'joty79/TakeOwnership'; InstallFolder = 'TakeOwnershipContext' },
    [pscustomobject]@{ Name = 'WhoIsUsingThis'; Label = 'Who is using this?'; Repo = 'joty79/WhoIsUsingThis'; InstallFolder = 'WhoIsUsingThisContext' },
    [pscustomobject]@{ Name = 'WinAppManager'; Label = 'WinAppManager'; Repo = 'joty79/WinAppManager'; InstallFolder = 'WinAppManager' },
    [pscustomobject]@{ Name = 'SystemCleanup'; Label = 'Windows Update Cleanup'; Repo = 'joty79/SystemCleanup'; InstallFolder = 'SystemCleanupContext' },
    [pscustomobject]@{ Name = 'Firewall'; Label = 'Firewall Rules'; Repo = 'joty79/Firewall'; InstallFolder = 'FirewallContext' }
)

function Write-Title {
    try { Clear-Host } catch { Write-Host '' }
    Write-Host 'SystemTools Manager' -ForegroundColor Cyan
    Write-Host 'Tool update center for the System Tools context menu' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-ShortCommit([AllowEmptyString()][string]$Commit) {
    if ([string]::IsNullOrWhiteSpace($Commit)) { return '-' }
    if ($Commit.Length -le 7) { return $Commit }
    return $Commit.Substring(0, 7)
}

function Get-RemoteCommit([string]$Repo) {
    try {
        $remote = & git.exe ls-remote "https://github.com/$Repo.git" 'refs/heads/master' 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $null }
        return (($remote -split '\s+')[0]).Trim()
    }
    catch {
        return $null
    }
}

function Get-ToolState($Tool) {
    $installPath = Join-Path $env:LOCALAPPDATA $Tool.InstallFolder
    $installerPath = Join-Path $installPath 'Install.ps1'
    $metaPath = Join-Path $installPath 'state\install-meta.json'
    $meta = $null
    if (Test-Path -LiteralPath $metaPath) {
        try { $meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json } catch { $meta = $null }
    }

    $localCommit = if ($meta -and $meta.PSObject.Properties['github_commit']) { [string]$meta.github_commit } else { '' }
    $remoteCommit = Get-RemoteCommit -Repo $Tool.Repo
    $status = if (-not (Test-Path -LiteralPath $installerPath)) {
        'Not installed'
    }
    elseif ([string]::IsNullOrWhiteSpace($remoteCommit)) {
        'Check failed'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($localCommit) -and $localCommit -eq $remoteCommit) {
        'Up to date'
    }
    else {
        'Update available'
    }

    [pscustomobject]@{
        Name = $Tool.Name
        Label = $Tool.Label
        Repo = $Tool.Repo
        InstallPath = $installPath
        InstallerPath = $installerPath
        Installed = (Test-Path -LiteralPath $installerPath)
        Version = if ($meta -and $meta.PSObject.Properties['app_version']) { [string]$meta.app_version } else { '-' }
        LocalCommit = $localCommit
        RemoteCommit = $remoteCommit
        Status = $status
    }
}

function Get-AllToolStates {
    foreach ($tool in $Script:Tools) { Get-ToolState -Tool $tool }
}

function Show-Status {
    Write-Title
    $states = @(Get-AllToolStates)
    $rows = foreach ($state in $states) {
        [pscustomobject]@{
            Tool = $state.Label
            Status = $state.Status
            Version = $state.Version
            Local = Get-ShortCommit $state.LocalCommit
            Remote = Get-ShortCommit $state.RemoteCommit
        }
    }
    $rows | Format-Table -AutoSize
}

function Invoke-ToolUpdate([string]$Name) {
    $tool = $Script:Tools | Where-Object { $_.Name -eq $Name -or $_.Label -eq $Name } | Select-Object -First 1
    if (-not $tool) { throw "Unknown tool: $Name" }

    $state = Get-ToolState -Tool $tool
    if (-not $state.Installed) {
        Write-Host "Skipping $($tool.Label): not installed." -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host "Updating $($tool.Label)..." -ForegroundColor Cyan
    & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $state.InstallerPath -Action UpdateGitHub -Force -NoExplorerRestart
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$($tool.Label) update failed with exit code $LASTEXITCODE." -ForegroundColor Red
        return
    }
    Write-Host "$($tool.Label) update completed." -ForegroundColor Green
}

function Invoke-UpdateAll {
    Write-Title
    foreach ($tool in $Script:Tools) {
        Invoke-ToolUpdate -Name $tool.Name
    }

    $refresh = Join-Path $env:LOCALAPPDATA 'SystemToolsContext\RefreshShell.ps1'
    if (Test-Path -LiteralPath $refresh) {
        & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $refresh -NoPause
    }
}

function Show-Menu {
    do {
        Show-Status
        Write-Host ''
        Write-Host '[1] Update all installed tools'
        for ($i = 0; $i -lt $Script:Tools.Count; $i++) {
            Write-Host ("[{0}] Update {1}" -f ($i + 2), $Script:Tools[$i].Label)
        }
        Write-Host '[R] Refresh status'
        Write-Host '[Q] Quit'
        Write-Host ''

        $choice = Read-Host 'Choose an action'
        if ($null -eq $choice) { return }
        $choice = $choice.Trim()

        if ($choice -eq '1') {
            Invoke-UpdateAll
            if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
            continue
        }

        if ($choice -match '^\d+$') {
            $index = [int]$choice - 2
            if ($index -ge 0 -and $index -lt $Script:Tools.Count) {
                Invoke-ToolUpdate -Name $Script:Tools[$index].Name
                if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
            }
            continue
        }
    } while ($choice -notmatch '^(q|quit|exit)$')
}

switch ($Action) {
    'Status' { Show-Status }
    'UpdateAll' { Invoke-UpdateAll }
    'UpdateTool' { Invoke-ToolUpdate -Name $ToolName }
    'Menu' { Show-Menu }
}

if (-not $NoPause -and $Action -ne 'Menu') {
    Write-Host ''
    Read-Host 'Press Enter to close' | Out-Null
}

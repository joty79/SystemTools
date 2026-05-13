#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Menu','Status','InstallAll','InstallTool','RepairAll','RepairTool','UpdateAll','UpdateTool','VerifyMenu')]
    [string]$Action = 'Menu',
    [AllowEmptyString()]
    [string]$ToolName = '',
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:FamilyConfigPath = Join-Path $PSScriptRoot '.assets\systemtools-family.json'

function Get-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $value = $Object.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function Get-ListProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-ObjectProperty -Object $Object -Name $Name -Default @()
    if ($null -eq $value) { return @() }
    return @($value)
}

function Expand-PathToken {
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $expanded = $expanded.Replace('{USERPROFILE}', $env:USERPROFILE)
    $expanded = $expanded.Replace('{LOCALAPPDATA}', $env:LOCALAPPDATA)
    return $expanded
}

function New-DefaultFamilyConfig {
    [pscustomobject]@{
        schema_version = 1
        tools = @(
            [pscustomobject]@{ name = 'SystemTools'; label = 'SystemTools host'; repo = 'joty79/SystemTools'; branch = 'master'; install_folder = 'SystemToolsContext'; repo_folder = 'SystemTools'; role = 'host'; order = 10; verify_registry_keys = @('HKCU\Software\Classes\Directory\shell\SystemTools\shell\Explorer\shell\ToolManager') },
            [pscustomobject]@{ name = 'TakeOwnership'; label = 'Take Ownership'; repo = 'joty79/TakeOwnership'; branch = 'master'; install_folder = 'TakeOwnershipContext'; repo_folder = 'TakeOwnership'; role = 'child'; order = 20; verify_registry_keys = @('HKCU\Software\Classes\Directory\shell\SystemTools\shell\Explorer\shell\TakeOwnership') },
            [pscustomobject]@{ name = 'WhoIsUsingThis'; label = 'Who is using this?'; repo = 'joty79/WhoIsUsingThis'; branch = 'master'; install_folder = 'WhoIsUsingThisContext'; repo_folder = 'WhoIsUsingThis'; role = 'child'; order = 30; verify_registry_keys = @('HKCU\Software\Classes\Directory\shell\SystemTools\shell\Explorer\shell\WhoIsUsingThis') },
            [pscustomobject]@{ name = 'WinAppManager'; label = 'WinAppManager'; repo = 'joty79/WinAppManager'; branch = 'master'; install_folder = 'WinAppManager'; repo_folder = 'WinAppManager'; role = 'child'; order = 40; verify_registry_keys = @('HKCU\Software\Classes\Directory\shell\SystemTools\shell\AppsWindows\shell\WinAppManager') },
            [pscustomobject]@{ name = 'SystemCleanup'; label = 'Windows Update Cleanup'; repo = 'joty79/SystemCleanup'; branch = 'master'; install_folder = 'SystemCleanupContext'; repo_folder = 'SystemCleanup'; role = 'child'; order = 50; verify_registry_keys = @('HKCU\Software\Classes\Directory\Background\shell\SystemTools\shell\AppsWindows\shell\SystemCleanup') },
            [pscustomobject]@{ name = 'Firewall'; label = 'Firewall Rules'; repo = 'joty79/Firewall'; branch = 'master'; install_folder = 'FirewallContext'; repo_folder = 'Firewall'; role = 'child'; order = 60; verify_registry_keys = @('HKCU\Software\Classes\exefile\shell\SystemTools\shell\AppsWindows\shell\FirewallManager') }
        )
    }
}

function ConvertTo-ToolDefinition {
    param([Parameter(Mandatory)]$Item)

    $repo = [string](Get-ObjectProperty -Object $Item -Name 'repo' -Default '')
    $repoFolder = [string](Get-ObjectProperty -Object $Item -Name 'repo_folder' -Default '')
    if ([string]::IsNullOrWhiteSpace($repoFolder) -and $repo -match '/([^/]+)$') {
        $repoFolder = $Matches[1]
    }

    [pscustomobject]@{
        Name = [string](Get-ObjectProperty -Object $Item -Name 'name' -Default $repoFolder)
        Label = [string](Get-ObjectProperty -Object $Item -Name 'label' -Default $repoFolder)
        Repo = $repo
        Branch = [string](Get-ObjectProperty -Object $Item -Name 'branch' -Default 'master')
        InstallFolder = [string](Get-ObjectProperty -Object $Item -Name 'install_folder' -Default $repoFolder)
        RepoFolder = $repoFolder
        Role = [string](Get-ObjectProperty -Object $Item -Name 'role' -Default 'child')
        Order = [int](Get-ObjectProperty -Object $Item -Name 'order' -Default 999)
        LocalPaths = @(Get-ListProperty -Object $Item -Name 'local_paths')
        VerifyRegistryKeys = @(Get-ListProperty -Object $Item -Name 'verify_registry_keys')
    }
}

function Get-FamilyTools {
    $config = $null
    if (Test-Path -LiteralPath $Script:FamilyConfigPath) {
        try {
            $config = Get-Content -Raw -LiteralPath $Script:FamilyConfigPath | ConvertFrom-Json
        }
        catch {
            Write-Host "Family config could not be read. Using built-in defaults." -ForegroundColor Yellow
            $config = $null
        }
    }

    if ($null -eq $config) { $config = New-DefaultFamilyConfig }

    @($config.tools) |
        ForEach-Object { ConvertTo-ToolDefinition -Item $_ } |
        Sort-Object Order, Label
}

$Script:Tools = @(Get-FamilyTools)

function Write-Title {
    try { Clear-Host } catch { Write-Host '' }
    Write-Host 'SystemTools Manager' -ForegroundColor Cyan
    Write-Host 'Install, repair, and update the System Tools context-menu family' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-ShortCommit([AllowEmptyString()][string]$Commit) {
    if ([string]::IsNullOrWhiteSpace($Commit)) { return '-' }
    if ($Commit.Length -le 7) { return $Commit }
    return $Commit.Substring(0, 7)
}

function Get-RemoteCommit([string]$Repo, [string]$Branch) {
    try {
        $remote = & git.exe ls-remote "https://github.com/$Repo.git" "refs/heads/$Branch" 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $null }
        return (($remote -split '\s+')[0]).Trim()
    }
    catch {
        return $null
    }
}

function Convert-RegistryPathForRegExe {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.StartsWith('HKCU\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKEY_CURRENT_USER\' + $Path.Substring(5)
    }
    if ($Path.StartsWith('HKCR\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKEY_CLASSES_ROOT\' + $Path.Substring(5)
    }
    return $Path
}

function Test-RegistryKeyExists {
    param([Parameter(Mandatory)][string]$Path)

    $nativePath = Convert-RegistryPathForRegExe -Path $Path
    & reg.exe query $nativePath *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-RegistryMenuState {
    param($Tool)

    $keys = @($Tool.VerifyRegistryKeys)
    if ($keys.Count -eq 0) { return 'Not checked' }

    $present = 0
    foreach ($key in $keys) {
        if (Test-RegistryKeyExists -Path $key) { $present++ }
    }

    if ($present -eq $keys.Count) { return 'OK' }
    if ($present -eq 0) { return 'Missing' }
    return 'Partial'
}

function Get-ToolState {
    param([Parameter(Mandatory)]$Tool)

    $installPath = Join-Path $env:LOCALAPPDATA $Tool.InstallFolder
    $installerPath = Join-Path $installPath 'Install.ps1'
    $metaPath = Join-Path $installPath 'state\install-meta.json'
    $meta = $null
    if (Test-Path -LiteralPath $metaPath) {
        try { $meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json } catch { $meta = $null }
    }

    $localCommit = if ($meta -and $meta.PSObject.Properties.Name -contains 'github_commit') { [string]$meta.github_commit } else { '' }
    $remoteCommit = Get-RemoteCommit -Repo $Tool.Repo -Branch $Tool.Branch
    $installed = Test-Path -LiteralPath $installerPath
    $menuState = Get-RegistryMenuState -Tool $Tool

    $status = if (-not $installed) {
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
        Branch = $Tool.Branch
        InstallPath = $installPath
        InstallerPath = $installerPath
        Installed = $installed
        Version = if ($meta -and $meta.PSObject.Properties.Name -contains 'app_version') { [string]$meta.app_version } else { '-' }
        LocalCommit = $localCommit
        RemoteCommit = $remoteCommit
        Menu = $menuState
        Status = $status
    }
}

function Get-AllToolStates {
    foreach ($tool in $Script:Tools) { Get-ToolState -Tool $tool }
}

function Get-RepoSearchRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    $defaultScripts = Join-Path $env:USERPROFILE 'scripts'
    $roots.Add($defaultScripts)

    $rootsConfig = Join-Path $env:USERPROFILE '.codex\REPO_ROOTS.psd1'
    if (Test-Path -LiteralPath $rootsConfig) {
        try {
            $data = Import-PowerShellDataFile -LiteralPath $rootsConfig
            foreach ($root in @($data.SearchRoots)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$root)) { $roots.Add([string]$root) }
            }
        }
        catch {
            Write-Host "Repo roots config could not be read: $rootsConfig" -ForegroundColor Yellow
        }
    }

    $roots |
        ForEach-Object { Expand-PathToken -Path $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } |
        Select-Object -Unique
}

function Resolve-ToolRepoPath {
    param([Parameter(Mandatory)]$Tool)

    foreach ($candidate in @($Tool.LocalPaths)) {
        $path = Expand-PathToken -Path ([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath (Join-Path $path 'Install.ps1'))) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    foreach ($root in Get-RepoSearchRoots) {
        $candidate = Join-Path $root $Tool.RepoFolder
        if (Test-Path -LiteralPath (Join-Path $candidate 'Install.ps1')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Get-ToolByName {
    param([Parameter(Mandatory)][string]$Name)

    $tool = $Script:Tools |
        Where-Object { $_.Name -eq $Name -or $_.Label -eq $Name -or $_.RepoFolder -eq $Name } |
        Select-Object -First 1

    if (-not $tool) { throw "Unknown tool: $Name" }
    return $tool
}

function Show-Status {
    Write-Title
    $rows = foreach ($state in @(Get-AllToolStates)) {
        [pscustomobject]@{
            Tool = $state.Label
            Installed = if ($state.Installed) { 'Yes' } else { 'No' }
            Menu = $state.Menu
            Status = $state.Status
            Version = $state.Version
            Local = Get-ShortCommit $state.LocalCommit
            Remote = Get-ShortCommit $state.RemoteCommit
        }
    }
    $rows | Format-Table -AutoSize
}

function Invoke-Installer {
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            Write-Host $line.ToString() -ForegroundColor Red
        }
        else {
            Write-Host ([string]$line)
        }
    }
    return [int]$exitCode
}

function Invoke-ToolUpdate {
    param([Parameter(Mandatory)][string]$Name)

    $tool = Get-ToolByName -Name $Name
    $state = Get-ToolState -Tool $tool
    if (-not $state.Installed) {
        Write-Host "Skipping $($tool.Label): not installed." -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host "Updating $($tool.Label) from GitHub..." -ForegroundColor Cyan
    $exitCode = Invoke-Installer -InstallerPath $state.InstallerPath -Arguments @('-Action', 'UpdateGitHub', '-GitHubRef', $tool.Branch, '-Force', '-NoExplorerRestart')
    if ($exitCode -ne 0) {
        Write-Host "$($tool.Label) update failed with exit code $exitCode." -ForegroundColor Red
        return
    }
    Write-Host "$($tool.Label) update completed." -ForegroundColor Green
}

function Invoke-ToolGitCloneInstall {
    param(
        [Parameter(Mandatory)]$Tool,
        [Parameter(Mandatory)][string]$Mode
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("SystemToolsManager-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $repoUrl = "https://github.com/$($Tool.Repo).git"
        Write-Host "Local repo not found. Cloning $repoUrl ($($Tool.Branch))..." -ForegroundColor DarkCyan
        & git.exe clone --depth 1 --branch $Tool.Branch $repoUrl $tempRoot
        if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }

        $installerPath = Join-Path $tempRoot 'Install.ps1'
        if (-not (Test-Path -LiteralPath $installerPath)) { throw "Downloaded package has no Install.ps1" }

        $exitCode = Invoke-Installer -InstallerPath $installerPath -Arguments @('-Action', $Mode, '-PackageSource', 'Local', '-SourcePath', $tempRoot, '-Force', '-NoExplorerRestart')
        if ($exitCode -ne 0) { throw "Installer failed with exit code $exitCode" }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ToolInstallOrRepair {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Repair
    )

    $tool = Get-ToolByName -Name $Name
    $state = Get-ToolState -Tool $tool
    $sourceRoot = Resolve-ToolRepoPath -Tool $tool
    $mode = if ($state.Installed) { 'Update' } else { 'Install' }

    Write-Host ''
    $verb = if ($Repair) { 'Repairing' } elseif ($state.Installed) { 'Refreshing' } else { 'Installing' }
    Write-Host "$verb $($tool.Label)..." -ForegroundColor Cyan

    if ($sourceRoot) {
        $installerPath = Join-Path $sourceRoot 'Install.ps1'
        Write-Host "Source: $sourceRoot" -ForegroundColor DarkGray
        $exitCode = Invoke-Installer -InstallerPath $installerPath -Arguments @('-Action', $mode, '-PackageSource', 'Local', '-SourcePath', $sourceRoot, '-Force', '-NoExplorerRestart')
        if ($exitCode -ne 0) {
            Write-Host "$($tool.Label) install/repair failed with exit code $exitCode." -ForegroundColor Red
            return
        }
    }
    else {
        try {
            Invoke-ToolGitCloneInstall -Tool $tool -Mode $mode
        }
        catch {
            Write-Host "$($tool.Label) install/repair failed: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    Write-Host "$($tool.Label) install/repair completed." -ForegroundColor Green
}

function Invoke-InstallAll {
    Write-Title
    foreach ($tool in ($Script:Tools | Sort-Object { if ($_.Role -eq 'host') { 0 } else { 1 } }, Order)) {
        Invoke-ToolInstallOrRepair -Name $tool.Name
    }
    Invoke-RefreshShell
}

function Invoke-RepairAll {
    Write-Title
    foreach ($tool in ($Script:Tools | Sort-Object { if ($_.Role -eq 'host') { 0 } else { 1 } }, Order)) {
        Invoke-ToolInstallOrRepair -Name $tool.Name -Repair
    }
    Invoke-RefreshShell
}

function Invoke-UpdateAll {
    Write-Title
    foreach ($tool in ($Script:Tools | Sort-Object { if ($_.Role -eq 'host') { 1 } else { 0 } }, Order)) {
        Invoke-ToolUpdate -Name $tool.Name
    }
    Invoke-RefreshShell
}

function Invoke-RefreshShell {
    $refresh = Join-Path $env:LOCALAPPDATA 'SystemToolsContext\RefreshShell.ps1'
    if (Test-Path -LiteralPath $refresh) {
        & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $refresh -NoPause
    }
}

function Invoke-VerifyMenu {
    Write-Title
    $failed = 0
    foreach ($tool in $Script:Tools) {
        $state = Get-RegistryMenuState -Tool $tool
        $color = switch ($state) {
            'OK' { 'Green' }
            'Not checked' { 'DarkGray' }
            default { 'Red' }
        }
        Write-Host ("{0,-28} {1}" -f $tool.Label, $state) -ForegroundColor $color
        if ($state -notin @('OK', 'Not checked')) { $failed++ }
    }

    Write-Host ''
    if ($failed -eq 0) {
        Write-Host 'Context menu verification passed.' -ForegroundColor Green
    }
    else {
        Write-Host "$failed tool menu check(s) need install/repair." -ForegroundColor Yellow
    }
}

function Read-ToolChoice {
    param([Parameter(Mandatory)][string]$Prompt)

    Write-Host ''
    for ($i = 0; $i -lt $Script:Tools.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Script:Tools[$i].Label)
    }
    Write-Host '[Q] Cancel'
    Write-Host ''

    $choice = Read-Host $Prompt
    if ($null -eq $choice) { return $null }
    $choice = $choice.Trim()
    if ($choice -match '^(q|quit|exit)$') { return $null }
    if ($choice -match '^\d+$') {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $Script:Tools.Count) { return $Script:Tools[$index] }
    }

    Write-Host 'Invalid selection.' -ForegroundColor Yellow
    return $null
}

function Show-Menu {
    do {
        Show-Status
        Write-Host ''
        Write-Host '[1] Install / repair all tools'
        Write-Host '[2] Update all installed tools'
        Write-Host '[3] Install / repair selected tool'
        Write-Host '[4] Update selected tool'
        Write-Host '[5] Verify context menu entries'
        Write-Host '[R] Refresh status'
        Write-Host '[Q] Quit'
        Write-Host ''

        $choice = Read-Host 'Choose an action'
        if ($null -eq $choice) { return }
        $choice = $choice.Trim()

        switch -Regex ($choice) {
            '^1$' {
                Invoke-InstallAll
                if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
                continue
            }
            '^2$' {
                Invoke-UpdateAll
                if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
                continue
            }
            '^3$' {
                $tool = Read-ToolChoice -Prompt 'Install / repair which tool?'
                if ($tool) { Invoke-ToolInstallOrRepair -Name $tool.Name -Repair }
                if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
                continue
            }
            '^4$' {
                $tool = Read-ToolChoice -Prompt 'Update which tool?'
                if ($tool) { Invoke-ToolUpdate -Name $tool.Name }
                if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
                continue
            }
            '^5$' {
                Invoke-VerifyMenu
                if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
                continue
            }
            '^(r|refresh)$' { continue }
        }
    } while ($choice -notmatch '^(q|quit|exit)$')
}

switch ($Action) {
    'Status' { Show-Status }
    'InstallAll' { Invoke-InstallAll }
    'InstallTool' { Invoke-ToolInstallOrRepair -Name $ToolName }
    'RepairAll' { Invoke-RepairAll }
    'RepairTool' { Invoke-ToolInstallOrRepair -Name $ToolName -Repair }
    'UpdateAll' { Invoke-UpdateAll }
    'UpdateTool' { Invoke-ToolUpdate -Name $ToolName }
    'VerifyMenu' { Invoke-VerifyMenu }
    'Menu' { Show-Menu }
}

if (-not $NoPause -and $Action -ne 'Menu') {
    Write-Host ''
    Read-Host 'Press Enter to close' | Out-Null
}

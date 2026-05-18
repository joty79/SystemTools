#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Menu','Status','InstallAll','InstallTool','RepairAll','RepairTool','UpdateAll','UpdateTool','VerifyMenu','InspectTool','Surfaces','MenuEntries','MenuStructure','Budgets')]
    [string]$Action = 'Menu',
    [AllowEmptyString()]
    [string]$ToolName = '',
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_E = [char]27
$_C = @{
    H1      = "$_E[38;2;90;180;240m"
    H2      = "$_E[38;2;140;160;180m"
    OK      = "$_E[38;2;46;204;113m"
    Warn    = "$_E[38;2;241;196;15m"
    Fail    = "$_E[38;2;231;76;60m"
    Info    = "$_E[38;2;52;152;219m"
    Gold    = "$_E[38;2;243;156;18m"
    White   = "$_E[38;2;220;225;230m"
    Dim     = "$_E[38;2;100;110;120m"
    Accent  = "$_E[38;2;155;89;182m"
    SelBg   = "$_E[48;2;40;80;120m"
    SelFg   = "$_E[38;2;255;255;255m"
    Bold    = "$_E[1m"
    Reset   = "$_E[0m"
    EraseLn = "$_E[K"
}

$Script:FamilyConfigPath = Join-Path $PSScriptRoot '.assets\systemtools-family.json'
$Script:LastManagerNavigationKey = ''
$Script:LastManagerNavigationAt = [DateTime]::MinValue
$Script:LastManagerWindowWidth = 0
$Script:LastManagerWindowHeight = 0
$Script:ManagerMenuSnapshot = $null
$Script:LastManagerOperationSucceeded = $true
$Script:ManagerExitRequested = $false
$Script:ManagerReviewTabStartupPath = ''

function Get-BlueprintModulePath {
    $candidates = @(
        (Join-Path $env:USERPROFILE '.codex\tools\PS_UI_Blueprint.psm1'),
        'C:\Users\joty79\.codex\tools\PS_UI_Blueprint.psm1'
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    return ''
}

function Import-ManagerUi {
    if (Get-Command -Name Invoke-ArrowMenu -ErrorAction SilentlyContinue) { return $true }

    $blueprintPath = Get-BlueprintModulePath
    if ([string]::IsNullOrWhiteSpace($blueprintPath)) { return $false }

    Import-Module $blueprintPath -Force -DisableNameChecking
    return $true
}

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
            [pscustomobject]@{ name = 'Firewall'; label = 'Firewall Rules'; repo = 'joty79/Firewall'; branch = 'master'; install_folder = 'FirewallContext'; repo_folder = 'Firewall'; role = 'child'; order = 60; verify_registry_keys = @('HKCU\Software\Classes\*\shell\SystemTools\shell\Windows\shell\FirewallRules') }
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
        Scope = [string](Get-ObjectProperty -Object $Item -Name 'scope' -Default 'SystemTools')
        Order = [int](Get-ObjectProperty -Object $Item -Name 'order' -Default 999)
        LocalPaths = @(Get-ListProperty -Object $Item -Name 'local_paths')
        WorkspaceMarkerFiles = @(Get-ListProperty -Object $Item -Name 'workspace_marker_files')
        Surfaces = @(Get-ListProperty -Object $Item -Name 'surfaces')
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
    Write-Host 'Windows Tools Manager' -ForegroundColor Cyan
    Write-Host 'Monitor, repair, and update managed Windows context-menu tools' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-ShortCommit([AllowEmptyString()][string]$Commit) {
    if ([string]::IsNullOrWhiteSpace($Commit)) { return '-' }
    if ($Commit.Length -le 7) { return $Commit }
    return $Commit.Substring(0, 7)
}

function Get-RemoteCommit([string]$Repo, [string]$Branch) {
    if ([string]::IsNullOrWhiteSpace($Repo)) { return $null }

    try {
        $remote = & git.exe ls-remote "https://github.com/$Repo.git" "refs/heads/$Branch" 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $null }
        return (($remote -split '\s+')[0]).Trim()
    }
    catch {
        return $null
    }
}

function Get-GitValue {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    try {
        $output = & git.exe -C $RepoPath @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        return ([string]($output | Select-Object -First 1)).Trim()
    }
    catch {
        return ''
    }
}

function Get-WorkspaceState {
    param([Parameter(Mandatory)]$Tool)

    $repoPath = Resolve-ToolRepoPath -Tool $Tool
    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        return [pscustomobject]@{
            Path = ''
            Commit = ''
            IsDirty = $false
            Summary = 'No workspace'
        }
    }

    $isGitRepo = Get-GitValue -RepoPath $repoPath -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($isGitRepo -ne 'true') {
        return [pscustomobject]@{
            Path = $repoPath
            Commit = ''
            IsDirty = $false
            Summary = 'No git'
        }
    }

    $commit = Get-GitValue -RepoPath $repoPath -Arguments @('rev-parse', 'HEAD')
    $dirtyOutput = Get-GitValue -RepoPath $repoPath -Arguments @('status', '--porcelain')
    $isDirty = -not [string]::IsNullOrWhiteSpace($dirtyOutput)

    [pscustomobject]@{
        Path = $repoPath
        Commit = $commit
        IsDirty = $isDirty
        Summary = if ($isDirty) { 'Dirty' } else { 'Clean' }
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

function Get-RegistrySubKeyCount {
    param([Parameter(Mandatory)][string]$Path)

    $nativePath = Convert-RegistryPathForRegExe -Path $Path
    $output = & reg.exe query $nativePath 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $prefix = $nativePath.TrimEnd('\') + '\'
    $children = @($output |
        ForEach-Object { [string]$_ } |
        Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object {
            $child = $_.Substring($prefix.Length)
            if ($child -and $child -notmatch '\\') { $child }
        } |
        Select-Object -Unique)

    return $children.Count
}

function Convert-RegistryPathForProvider {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.StartsWith('HKCU\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKCU:\' + $Path.Substring(5)
    }
    if ($Path.StartsWith('HKCR\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'Registry::HKEY_CLASSES_ROOT\' + $Path.Substring(5)
    }
    return $Path
}

function Get-RegistryChildEntries {
    param([Parameter(Mandatory)][string]$Path)

    $providerPath = Convert-RegistryPathForProvider -Path $Path
    if (-not (Test-Path -LiteralPath $providerPath)) { return @() }

    foreach ($child in (Get-ChildItem -LiteralPath $providerPath | Sort-Object PSChildName)) {
        $item = Get-Item -LiteralPath $child.PSPath
        $props = Get-ItemProperty -LiteralPath $child.PSPath
        $label = if ($props.PSObject.Properties.Name -contains 'MUIVerb' -and -not [string]::IsNullOrWhiteSpace([string]$props.MUIVerb)) {
            [string]$props.MUIVerb
        }
        else {
            $defaultValue = [string]$item.GetValue('')
            if (-not [string]::IsNullOrWhiteSpace($defaultValue)) { $defaultValue } else { [string]$child.PSChildName }
        }

        $shellPath = Join-Path $child.PSPath 'shell'
        $childCount = if (Test-Path -LiteralPath $shellPath) { @(Get-ChildItem -LiteralPath $shellPath).Count } else { 0 }
        [pscustomobject]@{
            Key = [string]$child.PSChildName
            Label = $label
            Items = $childCount
            IsSubmenu = $childCount -gt 0
            Visibility = if ($props.PSObject.Properties.Name -contains 'Extended') { 'Shift only' } else { 'Normal' }
        }
    }
}

function Get-SystemToolsMenuTargets {
    $targets = @(
        [pscustomobject]@{ Label = 'Desktop / empty folder space'; Path = 'HKCU\Software\Classes\Directory\Background\shell\SystemTools\shell'; Also = 'DesktopBackground uses the same layout here' },
        [pscustomobject]@{ Label = 'Folder'; Path = 'HKCU\Software\Classes\Directory\shell\SystemTools\shell'; Also = '' },
        [pscustomobject]@{ Label = 'File'; Path = 'HKCU\Software\Classes\*\shell\SystemTools\shell'; Also = '' }
    )

    foreach ($target in $targets) {
        [pscustomobject]@{
            Label = $target.Label
            Path = $target.Path
            Note = $target.Also
            Children = @(Get-RegistryChildEntries -Path $target.Path)
        }
    }
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

    $hasInstallFolder = -not [string]::IsNullOrWhiteSpace([string]$Tool.InstallFolder)
    $installPath = if ($hasInstallFolder) { Join-Path $env:LOCALAPPDATA $Tool.InstallFolder } else { '' }
    $installerPath = if ($hasInstallFolder) { Join-Path $installPath 'Install.ps1' } else { '' }
    $metaPath = if ($hasInstallFolder) { Join-Path $installPath 'state\install-meta.json' } else { '' }
    $meta = $null
    if (-not [string]::IsNullOrWhiteSpace($metaPath) -and (Test-Path -LiteralPath $metaPath)) {
        try { $meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json } catch { $meta = $null }
    }

    $localCommit = if ($meta -and $meta.PSObject.Properties.Name -contains 'github_commit') { [string]$meta.github_commit } else { '' }
    $installedSourceDirty = if ($meta -and $meta.PSObject.Properties.Name -contains 'source_dirty') { [bool]$meta.source_dirty } else { $false }
    $remoteCommit = Get-RemoteCommit -Repo $Tool.Repo -Branch $Tool.Branch
    $workspace = Get-WorkspaceState -Tool $Tool
    $menuState = Get-RegistryMenuState -Tool $Tool
    $installed = if ($hasInstallFolder) { Test-Path -LiteralPath $installerPath } else { $menuState -eq 'OK' }

    $status = if (-not $hasInstallFolder) {
        if ($menuState -eq 'OK') { 'Monitored' } else { 'Menu issue' }
    }
    elseif (-not $installed) {
        'Not installed'
    }
    elseif ([string]::IsNullOrWhiteSpace($remoteCommit)) {
        'Check failed'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($localCommit) -and $localCommit -eq $remoteCommit) {
        'Up to date'
    }
    elseif ($installedSourceDirty) {
        'Dirty-source install'
    }
    else {
        'Installed behind'
    }

    $workspaceStatus = if ([string]::IsNullOrWhiteSpace($workspace.Commit)) {
        $workspace.Summary
    }
    elseif ([string]::IsNullOrWhiteSpace($remoteCommit)) {
        $workspace.Summary
    }
    elseif ($workspace.Commit -eq $remoteCommit) {
        if ($workspace.IsDirty) { 'Current + dirty' } else { 'Current' }
    }
    else {
        if ($workspace.IsDirty) { 'Different + dirty' } else { 'Different' }
    }

    [pscustomobject]@{
        Name = $Tool.Name
        Label = $Tool.Label
        Repo = $Tool.Repo
        Branch = $Tool.Branch
        Role = $Tool.Role
        Scope = $Tool.Scope
        InstallPath = $installPath
        InstallerPath = $installerPath
        InstallMetaPath = $metaPath
        Installed = $installed
        Version = if ($meta -and $meta.PSObject.Properties.Name -contains 'app_version') { [string]$meta.app_version } else { '-' }
        PackageSource = if ($meta -and $meta.PSObject.Properties.Name -contains 'package_source') { [string]$meta.package_source } else { '-' }
        SourcePath = if ($meta -and $meta.PSObject.Properties.Name -contains 'source_path') { [string]$meta.source_path } else { '-' }
        LastAction = if ($meta -and $meta.PSObject.Properties.Name -contains 'last_action') { [string]$meta.last_action } else { '-' }
        InstalledUtc = if ($meta -and $meta.PSObject.Properties.Name -contains 'installed_utc') { [string]$meta.installed_utc } else { '-' }
        InstalledCommit = $localCommit
        InstalledSourceDirty = $installedSourceDirty
        WorkspacePath = $workspace.Path
        WorkspaceCommit = $workspace.Commit
        WorkspaceStatus = $workspaceStatus
        RemoteCommit = $remoteCommit
        HasInstaller = $hasInstallFolder
        Menu = $menuState
        Status = $status
    }
}

function Get-AllToolStates {
    foreach ($tool in $Script:Tools) { Get-ToolState -Tool $tool }
}

function Get-StatusRows {
    param([object[]]$States = $null)

    if ($null -eq $States) { $States = @(Get-AllToolStates) }
    foreach ($state in @($States)) {
        [pscustomobject]@{
            Tool = $state.Label
            Scope = $state.Scope
            Installed = if ($state.Installed) { 'Yes' } else { 'No' }
            Menu = $state.Menu
            Status = $state.Status
            Ver = $state.Version
            Inst = Get-ShortCommit $state.InstalledCommit
            Work = if ($state.WorkspaceStatus -match 'dirty') { (Get-ShortCommit $state.WorkspaceCommit) + '*' } else { Get-ShortCommit $state.WorkspaceCommit }
            WorkState = $state.WorkspaceStatus
            Remote = Get-ShortCommit $state.RemoteCommit
        }
    }
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

    $markerFiles = @($Tool.WorkspaceMarkerFiles)
    if ($markerFiles.Count -eq 0) { $markerFiles = @('Install.ps1') }

    foreach ($candidate in @($Tool.LocalPaths)) {
        $path = Expand-PathToken -Path ([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            foreach ($marker in $markerFiles) {
                if (Test-Path -LiteralPath (Join-Path $path $marker)) {
                    return (Resolve-Path -LiteralPath $path).Path
                }
            }
        }
    }

    foreach ($root in Get-RepoSearchRoots) {
        $candidate = Join-Path $root $Tool.RepoFolder
        if (Test-Path -LiteralPath $candidate) {
            foreach ($marker in $markerFiles) {
                if (Test-Path -LiteralPath (Join-Path $candidate $marker)) {
                    return (Resolve-Path -LiteralPath $candidate).Path
                }
            }
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
    $rows = @(Get-StatusRows)
    $rows | Format-Table -AutoSize
    Write-Host 'Inst = installed metadata commit; Work = workspace HEAD (* dirty); Remote = GitHub branch HEAD.' -ForegroundColor DarkGray
    Write-Host 'Monitored = host-owned or registry-only surface; Dirty-source install = installed from uncommitted workspace changes.' -ForegroundColor DarkGray
}

function Write-DetailLine {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Value = '',
        [string]$Color = 'Gray'
    )

    Write-Host ("{0,-18}: " -f $Name) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Show-ToolInspection {
    param([Parameter(Mandatory)][string]$Name)

    $tool = Get-ToolByName -Name $Name
    $state = Get-ToolState -Tool $tool
    Show-ToolInspectionState -State $state
}

function Show-ToolInspectionState {
    param([Parameter(Mandatory)]$State)

    $state = $State
    Write-Title
    Write-Host "Status details: $($state.Label)" -ForegroundColor Cyan
    Write-Host ''

    Write-Host 'Installed copy' -ForegroundColor Green
    Write-DetailLine -Name 'Installed' -Value $(if ($state.Installed) { 'Yes' } else { 'No' })
    Write-DetailLine -Name 'Scope' -Value $state.Scope
    Write-DetailLine -Name 'Role' -Value $state.Role
    Write-DetailLine -Name 'Has installer' -Value ([string]$state.HasInstaller)
    Write-DetailLine -Name 'Path' -Value $state.InstallPath
    Write-DetailLine -Name 'Version' -Value $state.Version
    Write-DetailLine -Name 'Metadata commit' -Value (Get-ShortCommit $state.InstalledCommit)
    Write-DetailLine -Name 'Source dirty' -Value $([string]$state.InstalledSourceDirty) -Color $(if ($state.InstalledSourceDirty) { 'Yellow' } else { 'Gray' })
    Write-DetailLine -Name 'Package source' -Value $state.PackageSource
    Write-DetailLine -Name 'Source path' -Value $state.SourcePath
    Write-DetailLine -Name 'Last action' -Value $state.LastAction
    Write-DetailLine -Name 'Installed UTC' -Value $state.InstalledUtc

    Write-Host ''
    Write-Host 'Workspace and remote' -ForegroundColor Green
    Write-DetailLine -Name 'Workspace path' -Value $state.WorkspacePath
    Write-DetailLine -Name 'Workspace commit' -Value (Get-ShortCommit $state.WorkspaceCommit)
    Write-DetailLine -Name 'Workspace state' -Value $state.WorkspaceStatus -Color $(if ($state.WorkspaceStatus -match 'dirty') { 'Yellow' } else { 'Gray' })
    Write-DetailLine -Name 'Remote commit' -Value (Get-ShortCommit $state.RemoteCommit)
    Write-DetailLine -Name 'Menu state' -Value $state.Menu -Color $(if ($state.Menu -eq 'OK') { 'Green' } else { 'Yellow' })
    Write-DetailLine -Name 'Overall status' -Value $state.Status -Color $(if ($state.Status -eq 'Up to date') { 'Green' } elseif ($state.Status -eq 'Dirty-source install') { 'Yellow' } else { 'Gray' })

    Write-Host ''
    Write-Host 'Meaning' -ForegroundColor Green
    if (-not $state.Installed) {
        Write-Host 'This tool is not installed, or its expected monitored menu entries are missing.' -ForegroundColor Gray
    }
    elseif (-not $state.HasInstaller) {
        Write-Host 'This is a monitored surface without its own installed package. The manager checks its registry/menu presence but will not update it as a standalone installed app.' -ForegroundColor Gray
    }
    elseif ($state.Status -eq 'Up to date') {
        Write-Host 'The installed metadata commit matches the latest GitHub commit.' -ForegroundColor Gray
    }
    elseif ($state.Status -eq 'Dirty-source install') {
        Write-Host 'This was installed from a workspace that had uncommitted changes. The installed files may already include later content, but the metadata still points at the last clean commit available during that install.' -ForegroundColor Yellow
        Write-Host 'This screen is read-only. It does not repair metadata, reinstall files, or update from GitHub.' -ForegroundColor DarkGray
    }
    elseif ($state.Status -eq 'Installed behind') {
        Write-Host 'The installed metadata commit is older than the latest GitHub commit, and the install was not marked as dirty-source. Update selected tool would refresh the installed copy.' -ForegroundColor Gray
    }
    elseif ($state.Status -eq 'Check failed') {
        Write-Host 'The installed copy exists, but the remote GitHub commit check failed. Avoid treating cached or partial status as proof that the tool is current.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Review the fields above before choosing an install, repair, or update action.' -ForegroundColor Gray
    }
}

function Get-ToolSurfaces {
    foreach ($tool in $Script:Tools) {
        foreach ($surface in @($tool.Surfaces)) {
            $rootKey = [string](Get-ObjectProperty -Object $surface -Name 'root_key' -Default '')
            $shellKey = if ([string]::IsNullOrWhiteSpace($rootKey)) { '' } else { "$rootKey\shell" }
            $childCount = if ([string]::IsNullOrWhiteSpace($shellKey)) { $null } else { Get-RegistrySubKeyCount -Path $shellKey }

            [pscustomobject]@{
                Tool = $tool.Label
                Scope = $tool.Scope
                Surface = [string](Get-ObjectProperty -Object $surface -Name 'name' -Default '')
                Kind = [string](Get-ObjectProperty -Object $surface -Name 'kind' -Default '')
                Visibility = [string](Get-ObjectProperty -Object $surface -Name 'visibility' -Default 'normal')
                BudgetGroup = [string](Get-ObjectProperty -Object $surface -Name 'budget_group' -Default '')
                RootKey = $rootKey
                ChildCount = $childCount
            }
        }
    }
}

function Show-Surfaces {
    Write-Title
    $statusRows = @(Get-StatusRows)
    if ($statusRows.Count -gt 0) {
        Write-Host 'Managed tools summary' -ForegroundColor Cyan
        $statusRows | Select-Object Tool, Scope, Installed, Menu, Status, Ver, Inst, Work, WorkState, Remote | Format-Table -AutoSize
        Write-Host 'Inst = installed metadata commit; Work = workspace HEAD (* dirty); Remote = GitHub branch HEAD.' -ForegroundColor DarkGray
        Write-Host ''
    }

    Write-Host 'Menu entries' -ForegroundColor Cyan
    $rows = foreach ($surface in @(Get-ToolSurfaces)) {
        [pscustomobject]@{
            Tool = $surface.Tool
            Scope = $surface.Scope
            Entry = $surface.Surface
            Visibility = $surface.Visibility
            Items = if ($null -eq $surface.ChildCount) { '-' } else { [string]$surface.ChildCount }
            Group = $surface.BudgetGroup
        }
    }

    if ($rows.Count -eq 0) {
        Write-Host 'No menu entries are defined.' -ForegroundColor Yellow
        return
    }

    $rows | Format-Table -AutoSize
    Write-Host 'Menu entries may live inside System Tools or as separate top-level context menus.' -ForegroundColor DarkGray
}

function Show-Budgets {
    param([object[]]$Surfaces = $null)

    Write-Title
    if ($null -eq $Surfaces) { $Surfaces = @(Get-ToolSurfaces) }
    $surfaces = @($Surfaces | Where-Object { -not [string]::IsNullOrWhiteSpace($_.BudgetGroup) })
    if ($surfaces.Count -eq 0) {
        Write-Host 'No budget groups are defined.' -ForegroundColor Yellow
        return
    }

    $rows = foreach ($group in ($surfaces | Group-Object BudgetGroup)) {
        $measure = $group.Group | Where-Object { $null -ne $_.ChildCount } | Measure-Object -Property ChildCount -Maximum
        $max = try { $measure.Maximum } catch { $null }
        $count = if ($null -eq $max) { 0 } else { [int]$max }
        $remaining = 16 - $count
        $status = if ($count -gt 16) { 'Over limit' } elseif ($count -ge 14) { 'Near limit' } else { 'OK' }
        [pscustomobject]@{
            BudgetGroup = $group.Name
            VisibleItems = $count
            Remaining = $remaining
            Status = $status
            Tools = (($group.Group | ForEach-Object { $_.Tool }) | Select-Object -Unique) -join ', '
        }
    }

    $rows | Sort-Object Status, BudgetGroup | Format-Table -AutoSize
    Write-Host 'Static Explorer cascades have a verified 16 visible item limit per popup level. Separators do not count.' -ForegroundColor DarkGray
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

function Start-ManagerRelaunch {
    $scriptPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { Join-Path $PSScriptRoot 'SystemToolsManager.ps1' }
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Host "Manager relaunch skipped: script not found at $scriptPath" -ForegroundColor Yellow
        return $false
    }

    $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -ne $wtCommand) {
        Start-Process -FilePath $wtCommand.Source -ArgumentList @(
            '-w', 'new',
            'nt',
            '--title', 'SystemTools-Manager',
            'pwsh.exe',
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $scriptPath
        ) | Out-Null
        return $true
    }

    Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath
    ) | Out-Null
    return $true
}

function Invoke-ToolUpdate {
    param([Parameter(Mandatory)][string]$Name)

    $Script:LastManagerOperationSucceeded = $false
    $tool = Get-ToolByName -Name $Name
    $state = Get-ToolState -Tool $tool
    if (-not $state.HasInstaller) {
        Write-Host "Skipping $($tool.Label): monitored surface without an installed package." -ForegroundColor Yellow
        return
    }
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
    $Script:LastManagerOperationSucceeded = $true
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

    $Script:LastManagerOperationSucceeded = $false
    $tool = Get-ToolByName -Name $Name
    $state = Get-ToolState -Tool $tool
    if (-not $state.HasInstaller) {
        Write-Host "$($tool.Label) is a monitored surface without an installed package." -ForegroundColor Yellow
        return
    }
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
    $Script:LastManagerOperationSucceeded = $true
}

function Invoke-InstallAll {
    Write-Title
    $allOk = $true
    foreach ($tool in ($Script:Tools | Sort-Object { if ($_.Role -eq 'host') { 0 } else { 1 } }, Order)) {
        $state = Get-ToolState -Tool $tool
        if (-not $state.HasInstaller) { continue }
        Invoke-ToolInstallOrRepair -Name $tool.Name
        if (-not $Script:LastManagerOperationSucceeded) { $allOk = $false }
    }
    Invoke-RefreshShell
    $Script:LastManagerOperationSucceeded = $allOk
}

function Invoke-RepairAll {
    Write-Title
    $allOk = $true
    foreach ($tool in ($Script:Tools | Sort-Object { if ($_.Role -eq 'host') { 0 } else { 1 } }, Order)) {
        $state = Get-ToolState -Tool $tool
        if (-not $state.HasInstaller) { continue }
        Invoke-ToolInstallOrRepair -Name $tool.Name -Repair
        if (-not $Script:LastManagerOperationSucceeded) { $allOk = $false }
    }
    Invoke-RefreshShell
    $Script:LastManagerOperationSucceeded = $allOk
}

function Invoke-UpdateAll {
    Write-Title
    $allOk = $true
    foreach ($tool in ($Script:Tools | Sort-Object { if ($_.Role -eq 'host') { 1 } else { 0 } }, Order)) {
        $state = Get-ToolState -Tool $tool
        if (-not $state.HasInstaller -or -not $state.Installed) { continue }
        Invoke-ToolUpdate -Name $tool.Name
        if (-not $Script:LastManagerOperationSucceeded) { $allOk = $false }
    }
    Invoke-RefreshShell
    $Script:LastManagerOperationSucceeded = $allOk
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

    return Read-ManagerToolSelection -Prompt $Prompt
}

function New-ManagerMenuSnapshot {
    $states = @(Get-AllToolStates)
    $rows = @(Get-StatusRows -States $states)
    $surfaces = @(Get-ToolSurfaces)
    $systemToolsMenus = @(Get-SystemToolsMenuTargets)
    $attention = @($rows | Where-Object { $_.Menu -ne 'OK' -or $_.Status -notin @('Up to date', 'Monitored', 'Dirty-source install') })
    $dirty = @($rows | Where-Object { $_.Status -eq 'Dirty-source install' })
    $installed = @($rows | Where-Object { $_.Installed -eq 'Yes' })
    $menuOk = @($rows | Where-Object { $_.Menu -eq 'OK' })
    $currentWorkspace = @($rows | Where-Object { $_.WorkState -in @('Current', 'Current + dirty', 'No git') })
    $standalone = @($rows | Where-Object { $_.Scope -eq 'Standalone' })
    $systemTools = @($rows | Where-Object { $_.Scope -eq 'SystemTools' })
    $statusText = ($rows | Format-Table -AutoSize | Out-String -Width 220).TrimEnd()
    $topIssues = @($attention | Select-Object -First 3 | ForEach-Object { '{0}: {1}' -f $_.Tool, $_.Status })

    [pscustomobject]@{
        States = $states
        Rows = $rows
        Surfaces = $surfaces
        SystemToolsMenus = $systemToolsMenus
        StatusText = $statusText
        TotalCount = $rows.Count
        InstalledCount = $installed.Count
        MenuOkCount = $menuOk.Count
        WorkspaceCurrentCount = $currentWorkspace.Count
        StandaloneCount = $standalone.Count
        SystemToolsCount = $systemTools.Count
        AttentionCount = $attention.Count
        DirtySourceCount = $dirty.Count
        IssueSummary = if ($topIssues.Count -gt 0) { $topIssues -join '; ' } else { 'none' }
        CheckedAt = Get-Date
    }
}

function Get-ManagerUiWidth {
    try {
        $windowWidth = [int]$Host.UI.RawUI.WindowSize.Width
        if ($windowWidth -le 0) { return 80 }
        return [Math]::Max(40, [Math]::Min(100, $windowWidth - 2))
    }
    catch { 80 }
}

function Get-ManagerWindowSize {
    try {
        [pscustomobject]@{
            Width = [Math]::Max(40, [int]$Host.UI.RawUI.WindowSize.Width)
            Height = [Math]::Max(10, [int]$Host.UI.RawUI.WindowSize.Height)
        }
    }
    catch {
        [pscustomobject]@{ Width = 100; Height = 30 }
    }
}

function Lock-ManagerViewportToWindow {
    try {
        $windowSize = $Host.UI.RawUI.WindowSize
        if ($Host.UI.RawUI.BufferSize.Height -ne $windowSize.Height) {
            $Host.UI.RawUI.BufferSize = $windowSize
        }
    }
    catch {}
}

function Test-ManagerWindowResized {
    $size = Get-ManagerWindowSize
    if ($size.Width -ne $Script:LastManagerWindowWidth -or $size.Height -ne $Script:LastManagerWindowHeight) {
        $Script:LastManagerWindowWidth = $size.Width
        $Script:LastManagerWindowHeight = $size.Height
        return $true
    }

    return $false
}

function Begin-ManagerSyncRender {
    try { [Console]::Write("$_E[?2026h") } catch {}
}

function End-ManagerSyncRender {
    try { [Console]::Write("$_E[?2026l") } catch {}
}

function Invoke-ManagerFrame {
    param([Parameter(Mandatory)][scriptblock]$Render)

    Lock-ManagerViewportToWindow
    Begin-ManagerSyncRender
    try {
        try { Clear-Host } catch {}
        & $Render
        Write-Host "$_E[J" -NoNewline
    }
    finally {
        End-ManagerSyncRender
    }
}

function Limit-ManagerText {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][int]$Width
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($Width -le 0) { return '' }
    if ($text.Length -le $Width) { return $text }
    if ($Width -eq 1) { return $text.Substring(0, 1) }
    return $text.Substring(0, $Width - 1) + '~'
}

function Get-ManagerAppVersion {
    $metadataPath = Join-Path $PSScriptRoot 'app-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { return '1.0.0' }

    try {
        $metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
        if ($metadata.PSObject.Properties.Name -contains 'version' -and -not [string]::IsNullOrWhiteSpace([string]$metadata.version)) {
            return [string]$metadata.version
        }
    }
    catch {}

    return '1.0.0'
}

function Write-ManagerBanner {
    param(
        [string]$StatusLabel = 'Snapshot pending',
        [string]$StatusColor = $_C.Dim
    )

    $width = Get-ManagerUiWidth
    $innerWidth = [Math]::Max(1, $width - 2)
    $border = [string]::new([char]0x2550, ($width - 2))
    $titleText = Limit-ManagerText -Value " Windows Tools Manager v$(Get-ManagerAppVersion)" -Width $innerWidth
    $subText = Limit-ManagerText -Value ' Tools + Menu Structure + Updates' -Width $innerWidth
    $statusText = Limit-ManagerText -Value " Status : $StatusLabel" -Width $innerWidth
    $titlePad = [Math]::Max(0, $innerWidth - $titleText.Length)
    $subPad = [Math]::Max(0, $innerWidth - $subText.Length)
    $statusPad = [Math]::Max(0, $innerWidth - $statusText.Length)

    Write-Host ''
    Write-Host "$($_C.H1)$([char]0x2554)$border$([char]0x2557)$($_C.Reset)"
    Write-Host "$($_C.H1)$([char]0x2551)$($_C.Bold)$($_C.White)$titleText$($_C.Reset)$(' ' * $titlePad)$($_C.H1)$([char]0x2551)$($_C.Reset)"
    Write-Host "$($_C.H1)$([char]0x2551)$($_C.Dim)$subText$($_C.Reset)$(' ' * $subPad)$($_C.H1)$([char]0x2551)$($_C.Reset)"
    Write-Host "$($_C.H1)$([char]0x2551)$StatusColor$statusText$($_C.Reset)$(' ' * $statusPad)$($_C.H1)$([char]0x2551)$($_C.Reset)"
    Write-Host "$($_C.H1)$([char]0x255A)$border$([char]0x255D)$($_C.Reset)"
    Write-Host ''
}

function Write-ManagerSection {
    param(
        [string]$Title,
        [string]$Icon = [string][char]0x25C6
    )

    $width = Get-ManagerUiWidth
    $prefix = if ($Icon) { " $Icon $Title " } else { " $Title " }
    $remaining = [Math]::Max(0, $width - $prefix.Length - 1)
    $line = [string]::new([char]0x2500, $remaining)

    Write-Host ''
    Write-Host "$($_C.H1)$prefix$($_C.Dim)$line$($_C.Reset)"
}

function Show-ManagerLoading {
    Invoke-ManagerFrame {
        Write-ManagerBanner -StatusLabel 'Reading current status' -StatusColor $_C.Warn
        Write-Host "  $($_C.Dim)Checking installed metadata, registry entries, workspaces, and GitHub branch heads...$($_C.Reset)$($_C.EraseLn)"
    }
}

function Write-ManagerMenuHeader {
    param([Parameter(Mandatory)]$Snapshot)

    $statusLabel = if ($Snapshot.AttentionCount -eq 0) { 'All monitored menu checks OK' } else { "$($Snapshot.AttentionCount) item(s) need attention" }
    $statusColor = if ($Snapshot.AttentionCount -eq 0) { $_C.OK } else { $_C.Warn }
    Write-ManagerBanner -StatusLabel $statusLabel -StatusColor $statusColor

    Write-ManagerSection -Title 'Summary'
    Write-Host "  $($_C.H2)Managed:$($_C.Reset) $($_C.White)$($Snapshot.TotalCount)$($_C.Reset) | $($_C.H2)Installed:$($_C.Reset) $($_C.White)$($Snapshot.InstalledCount)$($_C.Reset) | $($_C.H2)Menu OK:$($_C.Reset) $($_C.OK)$($Snapshot.MenuOkCount)$($_C.Reset) | $($_C.H2)Standalone:$($_C.Reset) $($_C.Info)$($Snapshot.StandaloneCount)$($_C.Reset)$($_C.EraseLn)"
    Write-Host "  $($_C.H2)SystemTools:$($_C.Reset) $($_C.White)$($Snapshot.SystemToolsCount)$($_C.Reset) | $($_C.H2)Workspace current:$($_C.Reset) $($_C.OK)$($Snapshot.WorkspaceCurrentCount)$($_C.Reset)/$($Snapshot.TotalCount) | $($_C.H2)Dirty-source installs:$($_C.Reset) $($_C.Warn)$($Snapshot.DirtySourceCount)$($_C.Reset)$($_C.EraseLn)"
    Write-Host "  $($_C.H2)Checked:$($_C.Reset) $($_C.Dim)$('{0:HH:mm:ss}' -f $Snapshot.CheckedAt)$($_C.Reset) | $($_C.H2)Issues:$($_C.Reset) $($_C.Dim)$($Snapshot.IssueSummary)$($_C.Reset)$($_C.EraseLn)"
    Write-Host "  $($_C.Dim)Open Tools Summary for update/install shortcuts. Arrow keys do not rescan registry or git state.$($_C.Reset)$($_C.EraseLn)"
}

function Read-ManagerKey {
    try {
        while (-not [Console]::KeyAvailable) {
            if (Test-ManagerWindowResized) {
                return [pscustomobject]@{
                    Key = 'ResizeEvent'
                    KeyChar = [char]0
                    VirtualKeyCode = 0
                }
            }

            Start-Sleep -Milliseconds 40
        }
    }
    catch {}

    $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $keyChar = [char]0
    if ($keyInfo.PSObject.Properties['KeyChar']) {
        $keyChar = [char]$keyInfo.KeyChar
    }
    elseif ($keyInfo.PSObject.Properties['Character']) {
        $keyChar = [char]$keyInfo.Character
    }

    $keyName = if ($keyInfo.PSObject.Properties['Key']) {
        [string]$keyInfo.Key
    }
    elseif ($keyInfo.PSObject.Properties['VirtualKeyCode']) {
        try { [string][System.Enum]::ToObject([System.ConsoleKey], [int]$keyInfo.VirtualKeyCode) } catch { [string]$keyInfo.VirtualKeyCode }
    }
    else {
        ''
    }

    [pscustomobject]@{
        Key = $keyName
        KeyChar = $keyChar
        VirtualKeyCode = if ($keyInfo.PSObject.Properties['VirtualKeyCode']) { [int]$keyInfo.VirtualKeyCode } else { $null }
        ControlKeyState = if ($keyInfo.PSObject.Properties['ControlKeyState']) { [string]$keyInfo.ControlKeyState } else { '' }
    }
}

function Reset-ManagerNavigationRepeat {
    $Script:LastManagerNavigationKey = ''
    $Script:LastManagerNavigationAt = [DateTime]::MinValue
}

function Get-ManagerNavigationDirection {
    param([Parameter(Mandatory)]$Key)

    if ([string]$Key.Key -eq 'UpArrow' -or $Key.VirtualKeyCode -eq 38) { return 'Up' }
    if ([string]$Key.Key -eq 'DownArrow' -or $Key.VirtualKeyCode -eq 40) { return 'Down' }
    return ''
}

function Test-ManagerNavigationRepeat {
    param([Parameter(Mandatory)][string]$Direction)

    $now = Get-Date
    $elapsed = ($now - $Script:LastManagerNavigationAt).TotalMilliseconds
    if ($Script:LastManagerNavigationKey -eq $Direction -and $elapsed -lt 120) {
        $Script:LastManagerNavigationAt = $now
        return $true
    }

    $Script:LastManagerNavigationKey = $Direction
    $Script:LastManagerNavigationAt = $now
    return $false
}

function Move-ManagerSelection {
    param(
        [Parameter(Mandatory)][int]$Selected,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][ValidateSet('Up','Down')][string]$Direction
    )

    if ($Count -le 0) { return 0 }
    if ($Direction -eq 'Up') {
        if ($Selected -gt 0) { return ($Selected - 1) }
        return ($Count - 1)
    }

    if ($Selected -lt ($Count - 1)) { return ($Selected + 1) }
    return 0
}

function Write-ManagerShortcutSegments {
    param(
        [Parameter(Mandatory)][object[]]$Segments,
        [Parameter(Mandatory)][int]$Width
    )

    $plain = ($Segments | ForEach-Object { [string]$_.Text }) -join ''
    if ($plain.Length -gt $Width) {
        $remaining = $Width
        Write-Host '  ' -NoNewline
        foreach ($segment in $Segments) {
            if ($remaining -le 0) { break }
            $text = Limit-ManagerText -Value $segment.Text -Width $remaining
            Write-Host "$($segment.Color)$text$($_C.Reset)" -NoNewline
            $remaining -= $text.Length
        }
        Write-Host "$($_C.EraseLn)"
        return
    }

    Write-Host '  ' -NoNewline
    foreach ($segment in $Segments) {
        Write-Host "$($segment.Color)$($segment.Text)$($_C.Reset)" -NoNewline
    }
    Write-Host "$($_C.EraseLn)"
}

function New-ManagerShortcutSegment {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Color
    )

    [pscustomobject]@{ Text = $Text; Color = $Color }
}

function Write-ManagerNavFooter {
    param(
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Main','Picker','Back')][string]$Mode = 'Main'
    )

    $segments = @(
        New-ManagerShortcutSegment -Text "$([char]0x2191)$([char]0x2193)" -Color $_C.White
        New-ManagerShortcutSegment -Text ' navigate    ' -Color $_C.Dim
        New-ManagerShortcutSegment -Text 'Enter' -Color $_C.OK
        New-ManagerShortcutSegment -Text ' = select    ' -Color $_C.Dim
    )

    if ($Mode -eq 'Main') {
        $segments += @(
            New-ManagerShortcutSegment -Text '1/2/Q' -Color $_C.White
            New-ManagerShortcutSegment -Text ' = shortcut    ' -Color $_C.Dim
            New-ManagerShortcutSegment -Text 'Esc' -Color $_C.Fail
            New-ManagerShortcutSegment -Text ' = exit' -Color $_C.Dim
        )
    }
    elseif ($Mode -eq 'Picker') {
        $segments += @(
            New-ManagerShortcutSegment -Text 'Esc' -Color $_C.Fail
            New-ManagerShortcutSegment -Text ' = cancel' -Color $_C.Dim
        )
    }
    else {
        $segments = @(
            New-ManagerShortcutSegment -Text 'Enter' -Color $_C.OK
            New-ManagerShortcutSegment -Text ' / ' -Color $_C.Dim
            New-ManagerShortcutSegment -Text 'Esc' -Color $_C.Fail
            New-ManagerShortcutSegment -Text ' = back' -Color $_C.Dim
        )
    }

    Write-ManagerShortcutSegments -Segments $segments -Width ([Math]::Max(1, $Width - 3))
}

function Write-ManagerMenuBlock {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][int]$Selected,
        [Parameter(Mandatory)][int]$Top
    )

    try { $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = $Top } } catch {}
    $width = (Get-ManagerWindowSize).Width

    Write-ManagerSection -Title 'Main Menu'

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        $label = Limit-ManagerText -Value $item.Label -Width ([Math]::Max(1, $width - 8))
        $ansi = if (-not [string]::IsNullOrWhiteSpace([string]$item.Color)) { [string]$item.Color } else { $_C.White }
        if ($i -eq $Selected) {
            Write-Host "$($_C.SelBg)$($_C.SelFg)$($_C.Bold)  $([char]0x276F) $label $($_C.Reset)$($_C.EraseLn)"
        }
        else {
            Write-Host "    $ansi$label$($_C.Reset)$($_C.EraseLn)"
        }
    }

    Write-Host "$_E[K"
    Write-ManagerNavFooter -Width $width -Mode Main
    Write-Host "$_E[J" -NoNewline
}

function Write-ManagerToolSelectionBlock {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][int]$Selected,
        [Parameter(Mandatory)][int]$Top,
        [Parameter(Mandatory)][string]$Prompt
    )

    try { $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = $Top } } catch {}
    $width = (Get-ManagerWindowSize).Width

    Write-ManagerSection -Title $Prompt -Icon ''

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $label = Limit-ManagerText -Value $Items[$i].Label -Width ([Math]::Max(1, $width - 8))
        if ($i -eq $Selected) {
            Write-Host "$($_C.SelBg)$($_C.SelFg)$($_C.Bold)  $([char]0x276F) $label $($_C.Reset)$($_C.EraseLn)"
        }
        else {
            Write-Host "    $($_C.Dim)$label$($_C.Reset)$($_C.EraseLn)"
        }
    }

    Write-Host "$_E[K"
    Write-ManagerNavFooter -Width $width -Mode Picker
    Write-Host "$_E[J" -NoNewline
}

function Wait-ManagerBackKey {
    param([string]$Hint = 'Esc = back')

    Write-Host ''
    Write-Host "  $($_C.Dim)$Hint$($_C.Reset)"
    while ($true) {
        $key = Read-ManagerKey
        if ([string]$key.Key -eq 'Escape' -or $key.VirtualKeyCode -eq 27) { return }
        if ([string]$key.Key -eq 'Enter' -or $key.VirtualKeyCode -eq 13) { return }
    }
}

function Invoke-ManagerExternalAction {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [switch]$NoPause,
        [switch]$RelaunchManagerAfter
    )

    $Script:LastManagerOperationSucceeded = $false
    Restore-TuiHost
    try {
        & $Operation
        if (-not $NoPause) { Read-Host 'Press Enter to continue' | Out-Null }
    }
    finally {
        Initialize-TuiHost
    }

    if ($RelaunchManagerAfter -and $Script:LastManagerOperationSucceeded) {
        if (Start-ManagerRelaunch) {
            $Script:ManagerExitRequested = $true
            return
        }
    }

    Show-ManagerLoading
    $Script:ManagerMenuSnapshot = New-ManagerMenuSnapshot
}

function Get-ManagerRowColor {
    param([Parameter(Mandatory)]$Row)

    if ($Row.Status -eq 'Up to date' -or $Row.Status -eq 'Monitored') { return $_C.OK }
    if ($Row.Status -eq 'Dirty-source install') { return $_C.Warn }
    if ($Row.Menu -ne 'OK' -or $Row.Status -match 'failed|behind|missing|not installed') { return $_C.Fail }
    return $_C.White
}

function Format-ManagerCell {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Left','Right')][string]$Align = 'Left'
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($text.Length -gt $Width) {
        if ($Width -le 1) { return $text.Substring(0, $Width) }
        $text = $text.Substring(0, $Width - 1) + '~'
    }

    if ($Align -eq 'Right') {
        return $text.PadLeft($Width)
    }

    return $text.PadRight($Width)
}

function Get-ManagerWorkStateColor {
    param([AllowEmptyString()][string]$WorkState)

    switch -Regex ($WorkState) {
        '^Current$' { return $_C.OK }
        'dirty' { return $_C.Warn }
        '^Different' { return $_C.Warn }
        'No workspace|No git' { return $_C.Fail }
        default { return $_C.Dim }
    }
}

function Test-ManagerNeedsGitReview {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Row
    )

    if ([string]::IsNullOrWhiteSpace([string]$State.WorkspacePath)) { return $false }
    if (-not (Test-Path -LiteralPath $State.WorkspacePath -PathType Container)) { return $false }
    if ($Row.WorkState -match 'dirty') { return $true }
    if ($Row.WorkState -eq 'Different') { return $true }
    if ($Row.Status -eq 'Dirty-source install') { return $true }
    return $false
}

function Get-ManagerActionGuidance {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Row
    )

    $recommendation = 'No action needed'
    $reason = 'Installed copy, menu state, workspace, and remote look aligned.'
    $gitNote = 'Git: clean/current.'
    $color = $_C.OK

    if (-not $State.HasInstaller) {
        if ($Row.Menu -eq 'OK') {
            $recommendation = 'No installer action'
            $reason = 'This is a monitored registry/menu surface, not a standalone package.'
            $gitNote = 'Git: not applicable for this monitored surface.'
            $color = $_C.Dim
        }
        else {
            $recommendation = 'Repair host/menu owner'
            $reason = 'The monitored menu entry is missing or partial; repair the owning package.'
            $gitNote = 'Git: not applicable until the menu owner is repaired.'
            $color = $_C.Fail
        }
    }
    elseif (-not $State.Installed) {
        $recommendation = 'Press I to install/repair selected'
        $reason = 'The package is not installed or its expected installer is missing.'
        $gitNote = if ($Row.WorkState -eq 'No workspace') { 'Install will clone/use package source; local workspace is missing.' } else { 'Install uses local checkout when available.' }
        $color = $_C.Fail
    }
    elseif ($Row.Menu -ne 'OK') {
        $recommendation = 'Press I to repair selected'
        $reason = 'Installed files exist, but expected context-menu registry entries are not OK.'
        $gitNote = 'Repair uses local checkout when available; inspect dirty workspace first.'
        $color = $_C.Warn
    }
    elseif ($Row.Status -eq 'Installed behind') {
        $recommendation = 'Press U to update selected'
        $reason = 'Installed metadata is behind the latest GitHub branch commit.'
        $gitNote = 'Update uses GitHub/latest and does not touch local workspace files.'
        $color = $_C.Warn
    }
    elseif ($Row.Status -eq 'Dirty-source install') {
        $recommendation = 'Press Enter to review local source'
        $reason = 'Installed files came from uncommitted local changes; metadata may not describe the exact files.'
        $gitNote = 'Enter opens a WT pane. Run git status -sb; git diff --stat; then commit/push or reinstall clean.'
        $color = $_C.Warn
    }
    elseif ($Row.WorkState -match 'dirty') {
        $recommendation = 'Press Enter to review dirty workspace'
        $reason = 'Installed copy is current, but local checkout has uncommitted changes.'
        $gitNote = 'Enter opens a WT pane. I installs dirty local files; U installs GitHub/latest.'
        $color = $_C.Warn
    }
    elseif ($Row.WorkState -eq 'Different') {
        $recommendation = 'Press Enter to review workspace drift'
        $reason = 'Local checkout commit differs from the latest GitHub branch commit.'
        $gitNote = "Enter opens a WT pane. Run git fetch --prune; git status -sb; git log --oneline --left-right 'HEAD...@{u}'"
        $color = $_C.Warn
    }
    elseif ($Row.WorkState -eq 'No workspace') {
        $recommendation = 'Optional: restore local repo'
        $reason = 'Installed package can still update from GitHub, but local repair/edit source is missing.'
        $gitNote = 'Clone the repo if you want local repair/install from source.'
        $color = $_C.Fail
    }
    elseif ($Row.WorkState -eq 'No git') {
        $recommendation = 'No git automation'
        $reason = 'This workspace is not a Git repo; update/repair depends on package ownership.'
        $gitNote = 'Git: unavailable for this workspace.'
        $color = $_C.Fail
    }

    [pscustomobject]@{
        Recommendation = $recommendation
        Reason = $reason
        GitNote = $gitNote
        Color = $color
    }
}

function Write-ManagerActionsNeeded {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][int]$Width
    )

    $guidance = Get-ManagerActionGuidance -State $State -Row $Row
    Write-ManagerSection -Title 'Actions Needed'
    $lineWidth = [Math]::Max(1, $Width - 3)
    Write-Host "  $($_C.H2)Selected:$($_C.Reset) $($_C.White)$(Limit-ManagerText -Value $Row.Tool -Width ([Math]::Max(1, $lineWidth - 10)))$($_C.Reset)$($_C.EraseLn)"
    Write-Host "  $($_C.H2)Best next:$($_C.Reset) $($guidance.Color)$(Limit-ManagerText -Value $guidance.Recommendation -Width ([Math]::Max(1, $lineWidth - 12)))$($_C.Reset)$($_C.EraseLn)"
    Write-Host "  $($_C.Dim)$(Limit-ManagerText -Value $guidance.Reason -Width $lineWidth)$($_C.Reset)$($_C.EraseLn)"
    Write-Host "  $($_C.Dim)$(Limit-ManagerText -Value $guidance.GitNote -Width $lineWidth)$($_C.Reset)$($_C.EraseLn)"
}

function New-ManagerSingleQuotedLiteral {
    param([AllowEmptyString()][string]$Value)

    return "'$($Value.Replace("'", "''"))'"
}

function Close-ManagerWorkspaceReviewTab {
    if (-not [string]::IsNullOrWhiteSpace($Script:ManagerReviewTabStartupPath)) {
        Remove-Item -LiteralPath $Script:ManagerReviewTabStartupPath -Force -ErrorAction SilentlyContinue
    }

    $Script:ManagerReviewTabStartupPath = ''
}

function New-ManagerWorkspaceReviewStartupScript {
    param(
        [Parameter(Mandatory)][string]$WorkspaceLiteral,
        [Parameter(Mandatory)][string]$ToolLiteral
    )

    $template = @'
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath __WORKSPACE_LITERAL__
Write-Host ''
Write-Host 'Git review: ' -NoNewline -ForegroundColor Cyan
Write-Host __TOOL_LITERAL__ -ForegroundColor White
Write-Host 'Workspace: ' -NoNewline -ForegroundColor DarkGray
Write-Host (Get-Location).Path -ForegroundColor Green
Write-Host ''
Write-Host 'Suggested first commands:' -ForegroundColor Yellow
Write-Host '  git status -sb' -ForegroundColor Gray
Write-Host '  git diff --stat' -ForegroundColor Gray
Write-Host '  git fetch --prune' -ForegroundColor Gray
Write-Host "  git log --oneline --left-right 'HEAD...@{u}'" -ForegroundColor Gray
Write-Host ''
Write-Host 'Pane controls:' -ForegroundColor Yellow
Write-Host '  Close this review pane by typing ' -NoNewline -ForegroundColor Green
Write-Host 'exit' -NoNewline -ForegroundColor DarkYellow
Write-Host ' or pressing ' -NoNewline -ForegroundColor Green
Write-Host 'Ctrl+Shift+W' -NoNewline -ForegroundColor DarkYellow
Write-Host '.' -ForegroundColor Green
Write-Host ''
git status -sb
'@

    return $template.Replace('__WORKSPACE_LITERAL__', $WorkspaceLiteral).
        Replace('__TOOL_LITERAL__', $ToolLiteral)
}

function New-ManagerWorkspaceReviewWtArguments {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$WorkspacePath,
        [Parameter(Mandatory)][string]$StartupPath,
        [switch]$UseSplitPane
    )

    $prefix = if ($UseSplitPane) {
        @('-w', '0', 'split-pane', '-V')
    }
    else {
        @('-w', '0', 'new-tab')
    }

    return @(
        $prefix
        '--title'
        $Title
        '--startingDirectory'
        $WorkspacePath
        'pwsh.exe'
        '-NoExit'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $StartupPath
    )
}

function Start-ManagerWorkspaceReviewTab {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Row
    )

    if (-not (Test-ManagerNeedsGitReview -State $State -Row $Row)) {
        return $false
    }

    Close-ManagerWorkspaceReviewTab

    $reviewRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemToolsManager'
    New-Item -ItemType Directory -Path $reviewRoot -Force | Out-Null
    $token = [guid]::NewGuid().ToString('N')
    $startupPath = Join-Path $reviewRoot "review-start-$token.ps1"
    $workspacePath = (Resolve-Path -LiteralPath $State.WorkspacePath).Path
    $toolLabel = [string]$Row.Tool
    $tabName = [regex]::Replace($toolLabel, '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($tabName)) { $tabName = 'Workspace' }
    $tabTitle = "GitReview-$tabName"

    $workspaceLiteral = New-ManagerSingleQuotedLiteral -Value $workspacePath
    $toolLiteral = New-ManagerSingleQuotedLiteral -Value $toolLabel
    $startup = New-ManagerWorkspaceReviewStartupScript -WorkspaceLiteral $workspaceLiteral -ToolLiteral $toolLiteral

    Set-Content -LiteralPath $startupPath -Value $startup -Encoding UTF8 -Force
    $Script:ManagerReviewTabStartupPath = $startupPath

    $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -ne $wtCommand) {
        $wtArgs = New-ManagerWorkspaceReviewWtArguments -Title $tabTitle -WorkspacePath $workspacePath -StartupPath $startupPath -UseSplitPane:($null -ne $env:WT_SESSION)
        Start-Process -FilePath $wtCommand.Source -ArgumentList $wtArgs | Out-Null
        return $true
    }

    Start-Process -FilePath 'pwsh.exe' -WorkingDirectory $workspacePath -ArgumentList @(
        '-NoExit',
        '-ExecutionPolicy', 'Bypass',
        '-File', $startupPath
    ) | Out-Null
    return $true
}

function Get-ManagerToolsSummaryColumns {
    param([Parameter(Mandatory)][int]$ConsoleWidth)

    if ($ConsoleWidth -ge 136) {
        return @(
            [pscustomobject]@{ Key = 'Tool'; Header = 'Tool'; Width = 28 }
            [pscustomobject]@{ Key = 'Scope'; Header = 'Scope'; Width = 12 }
            [pscustomobject]@{ Key = 'Installed'; Header = 'In'; Width = 3 }
            [pscustomobject]@{ Key = 'Menu'; Header = 'Menu'; Width = 7 }
            [pscustomobject]@{ Key = 'Status'; Header = 'Status'; Width = 16 }
            [pscustomobject]@{ Key = 'Ver'; Header = 'Ver'; Width = 7 }
            [pscustomobject]@{ Key = 'Inst'; Header = 'Inst'; Width = 8 }
            [pscustomobject]@{ Key = 'Work'; Header = 'Work'; Width = 8 }
            [pscustomobject]@{ Key = 'WorkState'; Header = 'WorkState'; Width = 16 }
            [pscustomobject]@{ Key = 'Remote'; Header = 'Remote'; Width = 8 }
        )
    }

    if ($ConsoleWidth -ge 112) {
        return @(
            [pscustomobject]@{ Key = 'Tool'; Header = 'Tool'; Width = 28 }
            [pscustomobject]@{ Key = 'Scope'; Header = 'Scope'; Width = 12 }
            [pscustomobject]@{ Key = 'Installed'; Header = 'In'; Width = 3 }
            [pscustomobject]@{ Key = 'Menu'; Header = 'Menu'; Width = 4 }
            [pscustomobject]@{ Key = 'Status'; Header = 'Status'; Width = 16 }
            [pscustomobject]@{ Key = 'Ver'; Header = 'Ver'; Width = 7 }
            [pscustomobject]@{ Key = 'WorkState'; Header = 'WorkState'; Width = 16 }
            [pscustomobject]@{ Key = 'Remote'; Header = 'Remote'; Width = 8 }
        )
    }

    if ($ConsoleWidth -ge 86) {
        return @(
            [pscustomobject]@{ Key = 'Tool'; Header = 'Tool'; Width = 24 }
            [pscustomobject]@{ Key = 'Scope'; Header = 'Scope'; Width = 11 }
            [pscustomobject]@{ Key = 'Status'; Header = 'Status'; Width = 14 }
            [pscustomobject]@{ Key = 'Ver'; Header = 'Ver'; Width = 7 }
            [pscustomobject]@{ Key = 'WorkState'; Header = 'WorkState'; Width = 12 }
        )
    }

    if ($ConsoleWidth -ge 60) {
        return @(
            [pscustomobject]@{ Key = 'Tool'; Header = 'Tool'; Width = 24 }
            [pscustomobject]@{ Key = 'Status'; Header = 'Status'; Width = 14 }
            [pscustomobject]@{ Key = 'WorkState'; Header = 'WorkState'; Width = 12 }
        )
    }

    $toolWidth = [Math]::Max(12, [Math]::Min(22, $ConsoleWidth - 22))
    $statusWidth = [Math]::Max(8, $ConsoleWidth - $toolWidth - 6)
    return @(
        [pscustomobject]@{ Key = 'Tool'; Header = 'Tool'; Width = $toolWidth }
        [pscustomobject]@{ Key = 'Status'; Header = 'Status'; Width = $statusWidth }
    )
}

function Get-ManagerToolsSummaryValue {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$Key
    )

    switch ($Key) {
        'Tool' { return $Row.Tool }
        'Scope' { return $Row.Scope }
        'Installed' { return $Row.Installed }
        'Menu' { return $Row.Menu }
        'Status' { return $Row.Status }
        'Ver' { return $Row.Ver }
        'Inst' { return $Row.Inst }
        'Work' { return $Row.Work }
        'WorkState' { return $Row.WorkState }
        'Remote' { return $Row.Remote }
        default { return '' }
    }
}

function New-ManagerToolsSummaryLine {
    param(
        [Parameter(Mandatory)][object[]]$Columns,
        $Row = $null,
        [switch]$Header,
        [switch]$Separator,
        [switch]$ColorizeWorkState
    )

    $cells = foreach ($column in $Columns) {
        $value = if ($Separator) {
            [string]::new([char]0x002D, [Math]::Min([int]$column.Width, [Math]::Max(2, ([string]$column.Header).Length)))
        }
        elseif ($Header) {
            $column.Header
        }
        else {
            Get-ManagerToolsSummaryValue -Row $Row -Key $column.Key
        }

        $cell = Format-ManagerCell -Value $value -Width ([int]$column.Width)
        if ($ColorizeWorkState -and -not $Header -and -not $Separator -and $column.Key -eq 'WorkState') {
            "$(Get-ManagerWorkStateColor -WorkState ([string]$value))$cell$($_C.Reset)$((Get-ManagerRowColor -Row $Row))"
        }
        else {
            $cell
        }
    }

    return '  ' + ($cells -join '  ')
}

function Write-ManagerShortcutFooter {
    param([Parameter(Mandatory)][int]$Width)

    $wide = $Width -ge 92
    $actions = if ($wide) {
        @(
            [pscustomobject]@{ Key = 'U'; Text = ' update selected   ' }
            [pscustomobject]@{ Key = '^U'; Text = ' update all   ' }
            [pscustomobject]@{ Key = 'I'; Text = ' install/repair selected   ' }
            [pscustomobject]@{ Key = '^I'; Text = ' install/repair all   ' }
            [pscustomobject]@{ Key = 'R'; Text = ' refresh' }
        )
    }
    elseif ($Width -ge 64) {
        @(
            [pscustomobject]@{ Key = 'U'; Text = ' update   ' }
            [pscustomobject]@{ Key = '^U'; Text = ' all   ' }
            [pscustomobject]@{ Key = 'I'; Text = ' repair   ' }
            [pscustomobject]@{ Key = '^I'; Text = ' repair all   ' }
            [pscustomobject]@{ Key = 'R'; Text = ' refresh' }
        )
    }
    else {
        @(
            [pscustomobject]@{ Key = 'U'; Text = ' upd   ' }
            [pscustomobject]@{ Key = '^U'; Text = ' all   ' }
            [pscustomobject]@{ Key = 'I'; Text = ' rep   ' }
            [pscustomobject]@{ Key = '^I'; Text = ' all   ' }
            [pscustomobject]@{ Key = 'R'; Text = ' ref' }
        )
    }

    $actionSegments = foreach ($action in $actions) {
        New-ManagerShortcutSegment -Text $action.Key -Color $_C.Warn
        New-ManagerShortcutSegment -Text $action.Text -Color $_C.Dim
    }

    Write-ManagerShortcutSegments -Segments @($actionSegments) -Width ([Math]::Max(1, $Width - 3))
    Write-ManagerShortcutSegments -Segments @(
        New-ManagerShortcutSegment -Text "$([char]0x2191)$([char]0x2193)" -Color $_C.White
        New-ManagerShortcutSegment -Text ' move   ' -Color $_C.Dim
        New-ManagerShortcutSegment -Text 'Enter' -Color $_C.OK
        New-ManagerShortcutSegment -Text ' = git review   ' -Color $_C.Dim
        New-ManagerShortcutSegment -Text 'Esc' -Color $_C.Fail
        New-ManagerShortcutSegment -Text ' = back' -Color $_C.Dim
    ) -Width ([Math]::Max(1, $Width - 3))
}

function Write-ToolsSummaryBlock {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][object[]]$States,
        [Parameter(Mandatory)][int]$Selected,
        [Parameter(Mandatory)][int]$Top
    )

    $size = Get-ManagerWindowSize
    try { $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = $Top } } catch {}
    if ($Selected -ge 0 -and $Selected -lt $Rows.Count -and $Selected -lt $States.Count) {
        Write-ManagerActionsNeeded -State $States[$Selected] -Row $Rows[$Selected] -Width $size.Width
    }
    Write-ManagerSection -Title 'Tools Summary'
    $columns = @(Get-ManagerToolsSummaryColumns -ConsoleWidth $size.Width)
    $isCompact = $columns.Count -le 3
    if ($size.Width -lt 136) {
        Write-Host "  $($_C.Dim)Compact view for $($size.Width)-column terminal. Maximize or widen WT to see all commit columns.$($_C.Reset)$($_C.EraseLn)"
    }
    Write-Host (New-ManagerToolsSummaryLine -Columns $columns -Header) -ForegroundColor Green
    Write-Host (New-ManagerToolsSummaryLine -Columns $columns -Separator) -ForegroundColor Green

    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $row = $Rows[$i]
        $text = New-ManagerToolsSummaryLine -Columns $columns -Row $row
        if ($i -eq $Selected) {
            Write-Host "$($_C.SelBg)$($_C.SelFg)$($_C.Bold)$text$($_C.Reset)$($_C.EraseLn)"
        }
        else {
            $text = New-ManagerToolsSummaryLine -Columns $columns -Row $row -ColorizeWorkState
            Write-Host "$((Get-ManagerRowColor -Row $row))$text$($_C.Reset)$($_C.EraseLn)"
        }

        if ($isCompact) {
            $detail = "    scope $($row.Scope) | menu $($row.Menu) | ver $($row.Ver) | work $($row.Work) | remote $($row.Remote)"
            $detail = Limit-ManagerText -Value $detail -Width ([Math]::Max(1, $size.Width - 1))
            Write-Host "$($_C.Dim)$detail$($_C.Reset)$($_C.EraseLn)"
        }
    }

    Write-Host ''
    $legend = if ($size.Width -ge 100) {
        'Inst = installed commit; Work = workspace HEAD (* dirty); Remote = GitHub branch HEAD.'
    }
    else {
        'Wide view adds Inst/Work/Remote commit columns.'
    }
    Write-Host "  $($_C.Dim)$(Limit-ManagerText -Value $legend -Width ([Math]::Max(1, $size.Width - 3)))$($_C.Reset)$($_C.EraseLn)"
    Write-ManagerShortcutFooter -Width $size.Width
    Write-Host "$_E[J" -NoNewline
}

function Show-ToolsSummary {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [switch]$NoPause
    )

    $rows = @($Snapshot.Rows)
    if ($rows.Count -eq 0) { return }

    $selected = 0
    try { [Console]::CursorVisible = $false } catch {}
    Reset-ManagerNavigationRepeat

    try {
        while ($true) {
            Invoke-ManagerFrame {
                Write-ManagerBanner -StatusLabel 'Cached snapshot' -StatusColor $_C.Info
                try { $frameTop = $Host.UI.RawUI.CursorPosition.Y } catch { $frameTop = 0 }
                Write-ToolsSummaryBlock -Rows $rows -States @($Snapshot.States) -Selected $selected -Top $frameTop
            }

            $key = Read-ManagerKey
            if ([string]$key.Key -eq 'ResizeEvent') { continue }

            $direction = Get-ManagerNavigationDirection -Key $key
            if (-not [string]::IsNullOrWhiteSpace($direction)) {
                if (-not (Test-ManagerNavigationRepeat -Direction $direction)) {
                    $selected = Move-ManagerSelection -Selected $selected -Count $rows.Count -Direction $direction
                }
                continue
            }

            Reset-ManagerNavigationRepeat

            if ([string]$key.Key -eq 'Escape' -or $key.VirtualKeyCode -eq 27) {
                Close-ManagerWorkspaceReviewTab
                $Script:ManagerMenuSnapshot = $Snapshot
                return
            }
            if ([string]$key.Key -eq 'Enter' -or $key.VirtualKeyCode -eq 13) {
                [void](Start-ManagerWorkspaceReviewTab -State $Snapshot.States[$selected] -Row $rows[$selected])
                continue
            }

            $charCode = [int][char]$key.KeyChar
            $char = ([string]$key.KeyChar).ToUpperInvariant()
            $hasCtrl = ([string]$key.ControlKeyState) -match 'Ctrl'
            if ($charCode -eq 21 -or ($hasCtrl -and [string]$key.Key -eq 'U')) {
                Invoke-ManagerExternalAction -NoPause:$NoPause -RelaunchManagerAfter -Operation { Invoke-UpdateAll }
                if ($Script:ManagerExitRequested) { return }
                $Snapshot = $Script:ManagerMenuSnapshot
                $rows = @($Snapshot.Rows)
                $selected = [Math]::Min($selected, [Math]::Max(0, $rows.Count - 1))
                continue
            }
            if ($charCode -eq 9 -or ($hasCtrl -and [string]$key.Key -eq 'I')) {
                Invoke-ManagerExternalAction -NoPause:$NoPause -RelaunchManagerAfter -Operation { Invoke-InstallAll }
                if ($Script:ManagerExitRequested) { return }
                $Snapshot = $Script:ManagerMenuSnapshot
                $rows = @($Snapshot.Rows)
                $selected = [Math]::Min($selected, [Math]::Max(0, $rows.Count - 1))
                continue
            }
            if ($char -eq 'U') {
                $toolName = [string]$Snapshot.States[$selected].Name
                $isSelfAction = $toolName -eq 'SystemTools'
                Invoke-ManagerExternalAction -NoPause:$NoPause -RelaunchManagerAfter:$isSelfAction -Operation { Invoke-ToolUpdate -Name $toolName }
                if ($Script:ManagerExitRequested) { return }
                $Snapshot = $Script:ManagerMenuSnapshot
                $rows = @($Snapshot.Rows)
                $selected = [Math]::Min($selected, [Math]::Max(0, $rows.Count - 1))
                continue
            }
            if ($char -eq 'I') {
                $toolName = [string]$Snapshot.States[$selected].Name
                $isSelfAction = $toolName -eq 'SystemTools'
                Invoke-ManagerExternalAction -NoPause:$NoPause -RelaunchManagerAfter:$isSelfAction -Operation { Invoke-ToolInstallOrRepair -Name $toolName -Repair }
                if ($Script:ManagerExitRequested) { return }
                $Snapshot = $Script:ManagerMenuSnapshot
                $rows = @($Snapshot.Rows)
                $selected = [Math]::Min($selected, [Math]::Max(0, $rows.Count - 1))
                continue
            }
            if ($char -eq 'R') {
                Show-ManagerLoading
                $Snapshot = New-ManagerMenuSnapshot
                $rows = @($Snapshot.Rows)
                $selected = [Math]::Min($selected, [Math]::Max(0, $rows.Count - 1))
                continue
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

function Get-MenuBudgetRows {
    param([Parameter(Mandatory)][object[]]$Surfaces)

    foreach ($group in (@($Surfaces) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.BudgetGroup) } | Group-Object BudgetGroup | Sort-Object Name)) {
        $isRootGroup = $group.Name -like '*.Root'
        $measure = $group.Group | Where-Object { $null -ne $_.ChildCount } | Measure-Object -Property ChildCount -Maximum
        $max = try { $measure.Maximum } catch { $null }
        $count = if ($isRootGroup) { @($group.Group).Count } elseif ($null -eq $max) { 0 } else { [int]$max }
        $remaining = 16 - $count
        $status = if ($isRootGroup) { 'Tracked' } elseif ($count -gt 16) { 'Over limit' } elseif ($count -ge 14) { 'Near limit' } else { 'OK' }
        [pscustomobject]@{
            Group = $group.Name
            Used = $count
            Free = $remaining
            Status = $status
            IsRootGroup = $isRootGroup
            Entries = @($group.Group)
        }
    }
}

function Get-ManagedEntriesForGroups {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string[]]$Groups
    )

    $candidates = @($Snapshot.Surfaces | Where-Object { $_.BudgetGroup -in $Groups })

    foreach ($toolGroup in ($candidates | Group-Object Tool | Sort-Object Name)) {
        $entry = @($toolGroup.Group | Sort-Object @{
            Expression = {
                $index = [Array]::IndexOf($Groups, [string]$_.BudgetGroup)
                if ($index -ge 0) { $index }
                else { 2 }
            }
        }, Surface | Select-Object -First 1)
        if ($entry.Count -eq 0) { continue }
        [pscustomobject]@{
            Tool = $entry[0].Tool
            Entry = $entry[0].Surface
            Group = $entry[0].BudgetGroup
            Visibility = $entry[0].Visibility
            Items = $entry[0].ChildCount
            Scope = $entry[0].Scope
        }
    }
}

function Get-ManagerToolDisplayName {
    param([AllowEmptyString()][string]$Tool)

    if ($Tool -eq 'SystemTools host') { return 'System Tools' }
    return $Tool
}

function Write-MenuTargetSection {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Entries,
        [string]$Note = ''
    )

    if ($Entries.Count -eq 0) { return }

    Write-Host "  $($_C.H2)$Title$($_C.Reset)  $($_C.OK)$($Entries.Count) monitored$($_C.Reset)"
    if (-not [string]::IsNullOrWhiteSpace($Note)) {
        Write-Host "    $($_C.Dim)$Note$($_C.Reset)"
    }

    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        $connector = if ($i -eq ($Entries.Count - 1)) { [string][char]0x2514 } else { [string][char]0x251C }
        $visibility = if ($entry.Visibility -eq 'shift_only') { 'Shift only' } else { 'Normal' }
        $items = if ($null -eq $entry.Items) { '-' } else { [string]$entry.Items }
        $displayTool = Get-ManagerToolDisplayName -Tool $entry.Tool
        Write-Host "    $($_C.Dim)$connector$([char]0x2500)$($_C.Reset) $($_C.Gold)$displayTool$($_C.Reset) $($_C.Dim)| Visibility: $visibility | Items: $items$($_C.Reset)"
    }
    Write-Host ''
}

function Get-MenuPopupBudget {
    param([int]$Count)

    $status = if ($Count -gt 16) { 'Over limit' } elseif ($Count -ge 14) { 'Near limit' } else { 'OK' }
    [pscustomobject]@{
        Count = $Count
        Status = $status
        Remaining = 16 - $Count
    }
}

function Write-MenuStructureContent {
    param([Parameter(Mandatory)]$Snapshot)

    Write-ManagerBanner -StatusLabel 'Cached snapshot' -StatusColor $_C.Info
    Write-ManagerSection -Title 'Menu Structure'

    $groups = @(Get-MenuBudgetRows -Surfaces $Snapshot.Surfaces)
    if ($groups.Count -eq 0) {
        Write-Host '  No menu entries are defined.' -ForegroundColor Yellow
        return
    }

    Write-MenuTargetSection -Title 'Right-click on Desktop / empty folder space' -Entries @(Get-ManagedEntriesForGroups -Snapshot $Snapshot -Groups @('DesktopBackground.Root', 'Directory.Background.Root')) -Note 'Explorer shows both desktop-only entries and folder-background entries here.'
    Write-MenuTargetSection -Title 'Right-click on a folder' -Entries @(Get-ManagedEntriesForGroups -Snapshot $Snapshot -Groups @('Directory.Folder.Root', 'SystemTools.Root'))
    Write-MenuTargetSection -Title 'Right-click on a PNG file' -Entries @(Get-ManagedEntriesForGroups -Snapshot $Snapshot -Groups @('PngFile.Root', 'File.Root'))

    Write-Host "  $($_C.H2)Inside System Tools$($_C.Reset)"
    foreach ($menu in @($Snapshot.SystemToolsMenus)) {
        $children = @($menu.Children)
        if ($children.Count -eq 0) { continue }
        $rootBudget = Get-MenuPopupBudget -Count $children.Count
        $rootColor = if ($rootBudget.Status -eq 'OK') { $_C.OK } elseif ($rootBudget.Status -eq 'Near limit') { $_C.Warn } else { $_C.Fail }
        $rootRemainingText = if ($rootBudget.Remaining -lt 0) { "$([Math]::Abs($rootBudget.Remaining)) over" } else { "$($rootBudget.Remaining) free" }
        Write-Host "    $($_C.Gold)$($menu.Label)$($_C.Reset)  $rootColor$($rootBudget.Status)$($_C.Reset)  $($_C.Dim)(root popup $($rootBudget.Count)/16, $rootRemainingText)$($_C.Reset)"
        if (-not [string]::IsNullOrWhiteSpace([string]$menu.Note)) {
            Write-Host "      $($_C.Dim)$($menu.Note)$($_C.Reset)"
        }
        for ($i = 0; $i -lt $children.Count; $i++) {
            $child = $children[$i]
            $connector = if ($i -eq ($children.Count - 1)) { [string][char]0x2514 } else { [string][char]0x251C }
            $label = [string]$child.Label
            if ($child.IsSubmenu) {
                $childBudget = Get-MenuPopupBudget -Count ([int]$child.Items)
                $childColor = if ($childBudget.Status -eq 'OK') { $_C.OK } elseif ($childBudget.Status -eq 'Near limit') { $_C.Warn } else { $_C.Fail }
                $childRemainingText = if ($childBudget.Remaining -lt 0) { "$([Math]::Abs($childBudget.Remaining)) over" } else { "$($childBudget.Remaining) free" }
                Write-Host "      $($_C.Dim)$connector$([char]0x2500)$($_C.Reset) $($_C.Gold)$label$($_C.Reset) $childColor$($childBudget.Status)$($_C.Reset) $($_C.Dim)(submenu popup $($childBudget.Count)/16, $childRemainingText)$($_C.Reset)"
            }
            else {
                Write-Host "      $($_C.Dim)$connector$([char]0x2500)$($_C.Reset) $($_C.Gold)$label$($_C.Reset) $($_C.Dim)- direct item$($_C.Reset)"
            }
        }
        Write-Host ''
    }

    Write-Host "  $($_C.Dim)Each popup has its own 16-item limit. Root popup counts branches/direct items; each submenu counts its own items.$($_C.Reset)"
    Write-Host "  $($_C.Dim)Separators are free. A 4-item test submenu under desktop System Tools rendered normally because each popup stayed under 16.$($_C.Reset)"
    Write-Host "  $($_C.Dim)Menu OK means the expected registry entry exists. Shift only means the entry appears only with Shift + right-click.$($_C.Reset)"
}

function Show-MenuStructure {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [switch]$NoWait
    )

    if ($NoWait) {
        try { Clear-Host } catch {}
        Write-MenuStructureContent -Snapshot $Snapshot
        return
    }

    try { [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            Invoke-ManagerFrame {
                Write-MenuStructureContent -Snapshot $Snapshot
                $size = Get-ManagerWindowSize
                Write-Host ''
                Write-ManagerNavFooter -Width $size.Width -Mode Back
            }

            $key = Read-ManagerKey
            if ([string]$key.Key -eq 'ResizeEvent') { continue }
            if ([string]$key.Key -eq 'Escape' -or $key.VirtualKeyCode -eq 27) { return }
            if ([string]$key.Key -eq 'Enter' -or $key.VirtualKeyCode -eq 13) { return }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

function Show-MenuEntries {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [switch]$NoWait
    )
    Show-MenuStructure -Snapshot $Snapshot -NoWait:$NoWait
}

function Read-ManagerToolSelection {
    param([Parameter(Mandatory)][string]$Prompt)

    $items = @($Script:Tools)
    if ($items.Count -eq 0) { return $null }

    $selected = 0
    try { [Console]::CursorVisible = $false } catch {}
    Reset-ManagerNavigationRepeat

    try {
        while ($true) {
            Invoke-ManagerFrame {
                Write-ManagerBanner -StatusLabel 'Select tool' -StatusColor $_C.Info
                try { $menuTop = $Host.UI.RawUI.CursorPosition.Y } catch { $menuTop = 0 }
                Write-ManagerToolSelectionBlock -Items $items -Selected $selected -Top $menuTop -Prompt $Prompt
            }

            $key = Read-ManagerKey
            if ([string]$key.Key -eq 'ResizeEvent') { continue }

            $direction = Get-ManagerNavigationDirection -Key $key
            if (-not [string]::IsNullOrWhiteSpace($direction)) {
                if (-not (Test-ManagerNavigationRepeat -Direction $direction)) {
                    $selected = Move-ManagerSelection -Selected $selected -Count $items.Count -Direction $direction
                }
                continue
            }

            Reset-ManagerNavigationRepeat

            if ([string]$key.Key -eq 'Enter' -or $key.VirtualKeyCode -eq 13) { return $items[$selected] }
            if ([string]$key.Key -eq 'Escape' -or $key.VirtualKeyCode -eq 27) { return $null }

            $char = ([string]$key.KeyChar).ToUpperInvariant()
            if ($char -match '^[1-9]$') {
                $index = [int]$char - 1
                if ($index -ge 0 -and $index -lt $items.Count) { return $items[$index] }
            }
            if ($char -eq 'Q') { return $null }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

function Read-ManagerMenuSelection {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)]$Snapshot
    )

    $selected = 0
    try { [Console]::CursorVisible = $false } catch {}
    Reset-ManagerNavigationRepeat

    try {
        while ($true) {
            Invoke-ManagerFrame {
                Write-ManagerMenuHeader -Snapshot $Snapshot
                try { $menuTop = $Host.UI.RawUI.CursorPosition.Y } catch { $menuTop = 0 }
                Write-ManagerMenuBlock -Items $Items -Selected $selected -Top $menuTop
            }

            $key = Read-ManagerKey
            $direction = Get-ManagerNavigationDirection -Key $key
            if (-not [string]::IsNullOrWhiteSpace($direction)) {
                if (-not (Test-ManagerNavigationRepeat -Direction $direction)) {
                    $selected = Move-ManagerSelection -Selected $selected -Count $Items.Count -Direction $direction
                }
                continue
            }

            Reset-ManagerNavigationRepeat

            switch ([string]$key.Key) {
                'Enter' { return $Items[$selected].Action }
                'Escape' { return 'Quit' }
                'ResizeEvent' { continue }
            }

            if ($key.VirtualKeyCode -eq 13) { return $Items[$selected].Action }
            if ($key.VirtualKeyCode -eq 27) { return 'Quit' }

            $char = ([string]$key.KeyChar).ToUpperInvariant()
            if (-not [string]::IsNullOrWhiteSpace($char)) {
                $match = $Items | Where-Object { ([string]$_.Key).ToUpperInvariant() -eq $char } | Select-Object -First 1
                if ($match) { return $match.Action }
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

function Show-Menu {
    if (-not (Import-ManagerUi)) {
        throw 'PS_UI_Blueprint.psm1 was not found under .codex\tools. Install/restore the canonical blueprint first.'
    }

    Initialize-TuiHost
    try {
        Show-ManagerLoading
        $snapshot = New-ManagerMenuSnapshot

        :menuLoop do {
            $items = @(
                [pscustomobject]@{ Key = '1'; Label = 'Tools Summary'; Action = 'ToolsSummary'; Color = $_C.Info },
                [pscustomobject]@{ Key = '2'; Label = 'Menu Structure'; Action = 'MenuStructure'; Color = $_C.OK },
                [pscustomobject]@{ Key = 'Q'; Label = 'Exit'; Action = 'Quit'; Color = $_C.Dim }
            )

            $choice = Read-ManagerMenuSelection -Items $items -Snapshot $snapshot

            switch ($choice) {
                'ToolsSummary' {
                    $Script:ManagerMenuSnapshot = $snapshot
                    Show-ToolsSummary -Snapshot $snapshot -NoPause:$NoPause
                    if ($Script:ManagerExitRequested) { return }
                    if ($Script:ManagerMenuSnapshot) { $snapshot = $Script:ManagerMenuSnapshot }
                    continue menuLoop
                }
                'MenuStructure' {
                    Show-MenuStructure -Snapshot $snapshot
                    continue menuLoop
                }
                'Quit' { return }
            }
        } while ($true)
    }
    finally {
        Restore-TuiHost
    }
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
    'InspectTool' { Show-ToolInspection -Name $ToolName }
    'Surfaces' { Show-Surfaces }
    'MenuEntries' { Show-MenuStructure -Snapshot (New-ManagerMenuSnapshot) -NoWait }
    'MenuStructure' { Show-MenuStructure -Snapshot (New-ManagerMenuSnapshot) -NoWait }
    'Budgets' { Show-Budgets }
    'Menu' { Show-Menu }
}

if (-not $NoPause -and $Action -ne 'Menu') {
    Write-Host ''
    Read-Host 'Press Enter to close' | Out-Null
}

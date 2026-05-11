#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Status', 'Add', 'Remove', 'Toggle', 'EnvView', 'EnvExport')]
    [string]$Action = 'Menu',

    [ValidateSet('User', 'Machine')]
    [string]$Scope = 'User',

    [string]$TargetPath = (Get-Location).Path,

    [string]$OutputDirectory = (Get-Location).Path,

    [ValidateSet('Txt', 'Md', 'Both')]
    [string]$ExportFormat = 'Both',

    [switch]$SkipWtBootstrap,

    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_E = [char]27
$_C = @{
    H2    = "$_E[38;2;140;160;180m"
    OK    = "$_E[38;2;46;204;113m"
    Warn  = "$_E[38;2;241;196;15m"
    Fail  = "$_E[38;2;231;76;60m"
    Info  = "$_E[38;2;52;152;219m"
    White = "$_E[38;2;220;225;230m"
    Dim   = "$_E[38;2;100;110;120m"
    Reset = "$_E[0m"
}

$UserRegKey = 'HKCU:\Environment'
$MachineRegKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'

$script:SystemToolsRootPath = $PSScriptRoot
$script:SystemToolsAppName = 'SystemTools'
$script:SystemToolsAppVersion = '1.0.0'
$script:SystemToolsGitHubRepo = 'joty79/SystemTools'
$script:SystemToolsMetadataPath = Join-Path $script:SystemToolsRootPath 'app-metadata.json'
$script:SystemToolsStatePath = Join-Path $script:SystemToolsRootPath 'state'
$script:SystemToolsInstallMetaPath = Join-Path $script:SystemToolsStatePath 'install-meta.json'
$script:SystemToolsUpdateStatusCachePath = Join-Path $script:SystemToolsStatePath 'app-update-status.json'
$script:SystemToolsUpdateStatusCacheTtlMinutes = 30
$script:SystemToolsUpdateStatus = $null

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

function Import-SystemToolsUi {
    $blueprintPath = Get-BlueprintModulePath
    if ([string]::IsNullOrWhiteSpace($blueprintPath)) {
        return $false
    }

    Import-Module $blueprintPath -Force -DisableNameChecking
    return $true
}

function New-SystemToolsUpdateStatus {
    param(
        [string]$LocalVersion = $script:SystemToolsAppVersion,
        [AllowEmptyString()][string]$LatestVersion = '',
        [AllowEmptyString()][string]$LocalCommit = '',
        [AllowEmptyString()][string]$LatestCommit = '',
        [AllowEmptyString()][string]$SourceKind = 'Unknown',
        [bool]$HasLocalChanges = $false,
        [AllowEmptyString()][string]$Repo = $script:SystemToolsGitHubRepo,
        [AllowEmptyString()][string]$Branch = '',
        [ValidateSet('Unknown', 'UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified', 'Error')]
        [string]$Status = 'Unknown',
        [string]$Message = 'Update status has not been checked yet.',
        [AllowEmptyString()][string]$CheckedAt = '',
        [AllowEmptyString()][string]$RemoteCommit = '',
        [AllowEmptyString()][string]$Error = ''
    )

    if ([string]::IsNullOrWhiteSpace($LatestCommit) -and -not [string]::IsNullOrWhiteSpace($RemoteCommit)) {
        $LatestCommit = $RemoteCommit
    }

    [pscustomobject]@{
        LocalVersion  = $LocalVersion
        LatestVersion = $LatestVersion
        LocalCommit   = $LocalCommit
        LatestCommit  = $LatestCommit
        SourceKind    = $SourceKind
        HasLocalChanges = $HasLocalChanges
        Repo          = $Repo
        Branch        = $Branch
        Status        = $Status
        IsKnown       = ($Status -in @('UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified'))
        IsUpToDate    = ($Status -eq 'UpToDate')
        Message       = $Message
        CheckedAt     = $CheckedAt
        RemoteCommit  = $LatestCommit
        Error         = $Error
    }
}

function Initialize-SystemToolsAppMetadata {
    $script:SystemToolsUpdateStatus = New-SystemToolsUpdateStatus
    if (-not (Test-Path -LiteralPath $script:SystemToolsMetadataPath -PathType Leaf)) {
        return
    }

    try {
        $metadata = Get-Content -LiteralPath $script:SystemToolsMetadataPath -Raw | ConvertFrom-Json
        $nameProperty = $metadata.PSObject.Properties['app_name']
        if ($null -ne $nameProperty -and -not [string]::IsNullOrWhiteSpace([string]$nameProperty.Value)) {
            $script:SystemToolsAppName = [string]$nameProperty.Value
        }

        $versionProperty = $metadata.PSObject.Properties['version']
        if ($null -ne $versionProperty -and -not [string]::IsNullOrWhiteSpace([string]$versionProperty.Value)) {
            $script:SystemToolsAppVersion = [string]$versionProperty.Value
        }

        $repoProperty = $metadata.PSObject.Properties['github_repo']
        if ($null -ne $repoProperty -and -not [string]::IsNullOrWhiteSpace([string]$repoProperty.Value)) {
            $script:SystemToolsGitHubRepo = [string]$repoProperty.Value
        }

        $script:SystemToolsUpdateStatus = New-SystemToolsUpdateStatus -LocalVersion $script:SystemToolsAppVersion -Repo $script:SystemToolsGitHubRepo
    }
    catch {
        $script:SystemToolsUpdateStatus = New-SystemToolsUpdateStatus -Status 'Error' -Message 'Could not read local app metadata.' -Error $_.Exception.Message
    }
}

function ConvertTo-SystemToolsVersion {
    param([AllowEmptyString()][string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) { return $null }
    try { return [version]$VersionText }
    catch { return $null }
}

function Get-SystemToolsOptionalPropertyValue {
    param(
        [object]$InputObject,
        [string]$PropertyName,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Get-SystemToolsShortCommit {
    param([AllowEmptyString()][string]$Commit)

    if ([string]::IsNullOrWhiteSpace($Commit)) { return '' }
    $normalizedCommit = $Commit.Trim()
    if ($normalizedCommit.Length -le 7) { return $normalizedCommit }
    return $normalizedCommit.Substring(0, 7)
}

function Get-SystemToolsCurrentSourceInfo {
    $result = [ordered]@{
        Commit          = ''
        SourceKind      = 'Unknown'
        HasLocalChanges = $false
    }

    if (Test-Path -LiteralPath $script:SystemToolsInstallMetaPath -PathType Leaf) {
        try {
            $installMeta = Get-Content -LiteralPath $script:SystemToolsInstallMetaPath -Raw | ConvertFrom-Json
            $commit = [string](Get-SystemToolsOptionalPropertyValue -InputObject $installMeta -PropertyName 'github_commit' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($commit)) {
                $result.Commit = $commit.Trim()
                $result.SourceKind = 'Installed'
                $dirty = Get-SystemToolsOptionalPropertyValue -InputObject $installMeta -PropertyName 'source_dirty' -DefaultValue $false
                $result.HasLocalChanges = [bool]$dirty
                return [pscustomobject]$result
            }
        }
        catch {
        }
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        try {
            $inside = (& git.exe -C $script:SystemToolsRootPath rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
            if ($inside -eq 'true') {
                $commit = (& git.exe -C $script:SystemToolsRootPath rev-parse HEAD 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($commit)) {
                    $dirty = (& git.exe -C $script:SystemToolsRootPath status --porcelain 2>$null | Out-String).Trim()
                    $result.Commit = $commit
                    $result.SourceKind = 'Workspace'
                    $result.HasLocalChanges = (-not [string]::IsNullOrWhiteSpace($dirty))
                    return [pscustomobject]$result
                }
            }
        }
        catch {
        }
    }

    $result.SourceKind = 'Portable'
    return [pscustomobject]$result
}

function Test-SystemToolsLocalGitCommitContainsRemoteCommit {
    param(
        [AllowEmptyString()][string]$RemoteCommit,
        [AllowEmptyString()][string]$LocalCommit
    )

    if (
        [string]::IsNullOrWhiteSpace($RemoteCommit) -or
        [string]::IsNullOrWhiteSpace($LocalCommit) -or
        -not (Get-Command git.exe -ErrorAction SilentlyContinue)
    ) {
        return $false
    }

    try {
        & git.exe -C $script:SystemToolsRootPath merge-base --is-ancestor $RemoteCommit $LocalCommit 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Read-SystemToolsUpdateStatusCache {
    param([switch]$AllowStale)

    if (-not (Test-Path -LiteralPath $script:SystemToolsUpdateStatusCachePath -PathType Leaf)) {
        return $null
    }

    try {
        $cache = Get-Content -LiteralPath $script:SystemToolsUpdateStatusCachePath -Raw | ConvertFrom-Json
        if (-not $AllowStale) {
            $checkedAtText = [string](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'CheckedAt' -DefaultValue '')
            $checkedAt = [datetime]::MinValue
            if ([string]::IsNullOrWhiteSpace($checkedAtText) -or -not [datetime]::TryParse($checkedAtText, [ref]$checkedAt)) {
                return $null
            }

            if (((Get-Date) - $checkedAt).TotalMinutes -gt $script:SystemToolsUpdateStatusCacheTtlMinutes) {
                return $null
            }
        }

        $cachedStatusName = [string](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'Status' -DefaultValue '')
        if (-not $AllowStale -and $cachedStatusName -eq 'UpToDate') {
            return $null
        }

        $localCommit = [string](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'LocalCommit' -DefaultValue '')
        $latestCommit = [string](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'LatestCommit' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($latestCommit)) {
            $latestCommit = [string](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'RemoteCommit' -DefaultValue '')
        }
        $sourceKind = [string](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'SourceKind' -DefaultValue 'Unknown')
        $hasLocalChanges = [bool](Get-SystemToolsOptionalPropertyValue -InputObject $cache -PropertyName 'HasLocalChanges' -DefaultValue $false)
        $currentSourceInfo = Get-SystemToolsCurrentSourceInfo

        if ([string]$cache.LocalVersion -ne [string]$script:SystemToolsAppVersion) {
            return $null
        }
        if ([string]$currentSourceInfo.SourceKind -ne $sourceKind) {
            return $null
        }
        if ([bool]$currentSourceInfo.HasLocalChanges -ne $hasLocalChanges) {
            return $null
        }
        if (
            -not [string]::IsNullOrWhiteSpace([string]$currentSourceInfo.Commit) -and
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            [string]$currentSourceInfo.Commit -ne $localCommit
        ) {
            return $null
        }

        return (New-SystemToolsUpdateStatus `
            -LocalVersion ([string]$cache.LocalVersion) `
            -LatestVersion ([string]$cache.LatestVersion) `
            -LocalCommit $localCommit `
            -LatestCommit $latestCommit `
            -SourceKind $sourceKind `
            -HasLocalChanges $hasLocalChanges `
            -Repo ([string]$cache.Repo) `
            -Branch ([string]$cache.Branch) `
            -Status ([string]$cache.Status) `
            -Message ([string]$cache.Message) `
            -CheckedAt ([string]$cache.CheckedAt) `
            -Error ([string]$cache.Error))
    }
    catch {
        return $null
    }
}

function Write-SystemToolsUpdateStatusCache {
    param([Parameter(Mandatory)]$Status)

    try {
        if (-not (Test-Path -LiteralPath $script:SystemToolsStatePath -PathType Container)) {
            New-Item -Path $script:SystemToolsStatePath -ItemType Directory -Force | Out-Null
        }
        $Status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:SystemToolsUpdateStatusCachePath -Encoding UTF8
    }
    catch {
    }
}

function Get-SystemToolsGitHubApiHeaders {
    $headers = @{
        'User-Agent' = "$($script:SystemToolsAppName)/$($script:SystemToolsAppVersion)"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }

    return $headers
}

function ConvertTo-SystemToolsGitHubRepoSlugFromRemoteUrl {
    param([AllowEmptyString()][string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return '' }
    $match = [regex]::Match($RemoteUrl.Trim(), 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/#?]+?)(?:\.git)?(?:[/#?].*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }
    return ('{0}/{1}' -f $match.Groups['owner'].Value, $match.Groups['repo'].Value).ToLowerInvariant()
}

function Get-SystemToolsGitRemoteTarget {
    param([AllowEmptyString()][string]$Repo = $script:SystemToolsGitHubRepo)

    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        return ''
    }

    $expectedRepo = $Repo.Trim().ToLowerInvariant()
    try {
        $inside = (& git.exe -C $script:SystemToolsRootPath rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
        if ($inside -eq 'true') {
            foreach ($remoteName in @(& git.exe -C $script:SystemToolsRootPath remote 2>$null)) {
                $name = [string]$remoteName
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $remoteUrl = (& git.exe -C $script:SystemToolsRootPath remote get-url $name 2>$null | Out-String).Trim()
                if ((ConvertTo-SystemToolsGitHubRepoSlugFromRemoteUrl -RemoteUrl $remoteUrl) -eq $expectedRepo) {
                    return $name.Trim()
                }
            }
        }
    }
    catch {
    }

    return ("https://github.com/{0}.git" -f $Repo.Trim())
}

function Resolve-RemoteSystemToolsCommit {
    param(
        [AllowEmptyString()][string]$Repo = $script:SystemToolsGitHubRepo,
        [AllowEmptyString()][string]$Ref = ''
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Ref)) { return '' }

    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $commit = (& gh.exe api "repos/$Repo/commits/$Ref" --jq '.sha' 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit }
        }
        catch {
        }
    }

    try {
        $commitInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/commits/{1}" -f $Repo, $Ref) -Headers (Get-SystemToolsGitHubApiHeaders) -TimeoutSec 5 -ErrorAction Stop
        $commit = [string]$commitInfo.sha
        if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit }
    }
    catch {
    }

    $gitRemoteTarget = Get-SystemToolsGitRemoteTarget -Repo $Repo
    if (-not [string]::IsNullOrWhiteSpace($gitRemoteTarget) -and (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        foreach ($candidateRef in @("refs/heads/$Ref", $Ref)) {
            try {
                $remoteLine = (& git.exe -C $script:SystemToolsRootPath ls-remote $gitRemoteTarget $candidateRef 2>$null | Select-Object -First 1 | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($remoteLine)) {
                    $commit = ($remoteLine -split '\s+')[0]
                    if (-not [string]::IsNullOrWhiteSpace($commit)) { return $commit }
                }
            }
            catch {
            }
        }
    }

    return ''
}

function Get-RemoteSystemToolsMetadata {
    if ([string]::IsNullOrWhiteSpace($script:SystemToolsGitHubRepo)) { return $null }

    $defaultBranch = ''
    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $repoJson = (& gh.exe api "repos/$($script:SystemToolsGitHubRepo)" 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($repoJson)) {
                $repoInfo = $repoJson | ConvertFrom-Json
                $defaultBranch = [string]$repoInfo.default_branch
            }
        }
        catch {
        }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
            $repoInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}" -f $script:SystemToolsGitHubRepo) -Headers (Get-SystemToolsGitHubApiHeaders) -TimeoutSec 5 -ErrorAction Stop
            $defaultBranch = [string]$repoInfo.default_branch
        }
    }
    catch {
    }

    $branchCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($defaultBranch, 'master', 'main')) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $branchCandidates.Contains($candidate)) {
            $branchCandidates.Add($candidate)
        }
    }

    foreach ($branch in $branchCandidates) {
        if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
            try {
                $content = (& gh.exe api "repos/$($script:SystemToolsGitHubRepo)/contents/app-metadata.json?ref=$branch" --jq '.content' 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($content)) {
                    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($content -replace '\s', '')))
                    $metadata = $json | ConvertFrom-Json
                    return [pscustomobject]@{
                        Metadata = $metadata
                        Repo     = $script:SystemToolsGitHubRepo
                        Branch   = $branch
                        Commit   = (Resolve-RemoteSystemToolsCommit -Repo $script:SystemToolsGitHubRepo -Ref $branch)
                    }
                }
            }
            catch {
            }
        }

        $rawUri = "https://raw.githubusercontent.com/$($script:SystemToolsGitHubRepo)/$branch/app-metadata.json"
        try {
            $metadata = Invoke-RestMethod -Uri $rawUri -Method Get -Headers (Get-SystemToolsGitHubApiHeaders) -TimeoutSec 8
            if ($null -ne $metadata) {
                return [pscustomobject]@{
                    Metadata = $metadata
                    Repo     = $script:SystemToolsGitHubRepo
                    Branch   = $branch
                    Commit   = (Resolve-RemoteSystemToolsCommit -Repo $script:SystemToolsGitHubRepo -Ref $branch)
                }
            }
        }
        catch {
        }
    }

    $gitRemoteTarget = Get-SystemToolsGitRemoteTarget -Repo $script:SystemToolsGitHubRepo
    if (-not [string]::IsNullOrWhiteSpace($gitRemoteTarget) -and (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        foreach ($branch in $branchCandidates) {
            try {
                $remoteLine = (& git.exe -C $script:SystemToolsRootPath ls-remote $gitRemoteTarget "refs/heads/$branch" 2>$null | Select-Object -First 1 | Out-String).Trim()
                if ([string]::IsNullOrWhiteSpace($remoteLine)) { continue }
                $latestCommit = ($remoteLine -split '\s+')[0]
                $metadata = $null

                try {
                    $inside = (& git.exe -C $script:SystemToolsRootPath rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
                    if ($inside -eq 'true') {
                        $metadataJson = (& git.exe -C $script:SystemToolsRootPath show "$($latestCommit):app-metadata.json" 2>$null | Out-String).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($metadataJson)) {
                            $metadata = $metadataJson | ConvertFrom-Json
                        }
                    }
                }
                catch {
                }

                if ($null -eq $metadata) {
                    $tempRoot = Join-Path $env:TEMP ("SystemTools_update_metadata_{0}" -f [guid]::NewGuid().ToString('N'))
                    try {
                        & git.exe clone --quiet --depth 1 --branch $branch $gitRemoteTarget $tempRoot 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            $metadataPath = Join-Path $tempRoot 'app-metadata.json'
                            if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
                                $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
                            }
                        }
                    }
                    catch {
                    }
                    finally {
                        if (Test-Path -LiteralPath $tempRoot) {
                            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                if ($null -eq $metadata) {
                    $metadata = [pscustomobject]@{ version = '' }
                }

                return [pscustomobject]@{
                    Metadata = $metadata
                    Repo     = $script:SystemToolsGitHubRepo
                    Branch   = $branch
                    Commit   = $latestCommit
                }
            }
            catch {
            }
        }
    }

    return $null
}

function Get-SystemToolsInstalledCommitInfo {
    $result = [ordered]@{
        GitHubCommit = ''
        GitHubRef    = ''
        PackageSource = ''
        SourceDirty  = $false
    }

    if (-not (Test-Path -LiteralPath $script:SystemToolsInstallMetaPath -PathType Leaf)) {
        return [pscustomobject]$result
    }

    try {
        $installMeta = Get-Content -LiteralPath $script:SystemToolsInstallMetaPath -Raw | ConvertFrom-Json
        foreach ($item in @(
            @{ Name = 'github_commit'; Target = 'GitHubCommit' },
            @{ Name = 'github_ref'; Target = 'GitHubRef' },
            @{ Name = 'package_source'; Target = 'PackageSource' }
        )) {
            $property = $installMeta.PSObject.Properties[$item.Name]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $result[$item.Target] = [string]$property.Value
            }
        }

        $dirtyProperty = $installMeta.PSObject.Properties['source_dirty']
        if ($null -ne $dirtyProperty) {
            $result.SourceDirty = [bool]$dirtyProperty.Value
        }
    }
    catch {
    }

    return [pscustomobject]$result
}

function Get-RemoteSystemToolsCommit {
    param(
        [AllowEmptyString()][string]$Repo = $script:SystemToolsGitHubRepo,
        [AllowEmptyString()][string]$Ref = 'master'
    )

    if ([string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Ref)) { return '' }

    if (Get-Command gh.exe -ErrorAction SilentlyContinue) {
        try {
            $sha = (& gh.exe api "repos/$Repo/commits/$Ref" --jq '.sha' 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($sha)) { return $sha }
        }
        catch {
        }
    }

    try {
        $uri = "https://api.github.com/repos/$Repo/commits/$Ref"
        $commitInfo = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ 'User-Agent' = "$($script:SystemToolsAppName)/$($script:SystemToolsAppVersion)" } -TimeoutSec 8
        if ($null -ne $commitInfo -and -not [string]::IsNullOrWhiteSpace([string]$commitInfo.sha)) {
            return [string]$commitInfo.sha
        }
    }
    catch {
    }

    return ''
}

function Resolve-SystemToolsUpdateStatus {
    param([switch]$ForceRefresh)

    if (-not $ForceRefresh) {
        $cachedStatus = Read-SystemToolsUpdateStatusCache
        if ($null -ne $cachedStatus) {
            $script:SystemToolsUpdateStatus = $cachedStatus
            return $script:SystemToolsUpdateStatus
        }
    }

    $staleCachedStatus = Read-SystemToolsUpdateStatusCache -AllowStale
    $remoteInfo = Get-RemoteSystemToolsMetadata
    if ($null -eq $remoteInfo) {
        if ($null -ne $staleCachedStatus -and [string]$staleCachedStatus.Status -ne 'UpToDate') {
            $staleCachedStatus.Message = 'Using cached update status because the latest version could not be reached.'
            $script:SystemToolsUpdateStatus = $staleCachedStatus
            return $script:SystemToolsUpdateStatus
        }

        $script:SystemToolsUpdateStatus = New-SystemToolsUpdateStatus -LocalVersion $script:SystemToolsAppVersion -Repo $script:SystemToolsGitHubRepo -Status 'Error' -Message 'Could not reach GitHub to check the latest version.' -CheckedAt ((Get-Date).ToString('s'))
        return $script:SystemToolsUpdateStatus
    }

    $latestVersionProperty = $remoteInfo.Metadata.PSObject.Properties['version']
    $latestVersion = if ($null -ne $latestVersionProperty) { [string]$latestVersionProperty.Value } else { '' }
    $localVersionObject = ConvertTo-SystemToolsVersion -VersionText $script:SystemToolsAppVersion
    $remoteVersionObject = ConvertTo-SystemToolsVersion -VersionText $latestVersion
    $statusName = 'Unknown'
    $statusMessage = 'Update status is unavailable.'
    $sourceInfo = Get-SystemToolsCurrentSourceInfo
    $localCommit = [string]$sourceInfo.Commit
    $latestCommit = [string]$remoteInfo.Commit
    if ([string]::IsNullOrWhiteSpace($latestCommit)) {
        $latestCommit = Resolve-RemoteSystemToolsCommit -Repo ([string]$remoteInfo.Repo) -Ref ([string]$remoteInfo.Branch)
    }
    $sourceKind = [string]$sourceInfo.SourceKind
    $hasLocalChanges = [bool]$sourceInfo.HasLocalChanges

    if ($sourceKind -eq 'Workspace' -and $hasLocalChanges) {
        $statusName = 'WorkspaceModified'
        $statusMessage = "This workspace has unpublished local changes. Local metadata is v$script:SystemToolsAppVersion at HEAD $(Get-SystemToolsShortCommit -Commit $localCommit); latest GitHub $($remoteInfo.Branch) is v$latestVersion at $(Get-SystemToolsShortCommit -Commit $latestCommit)."
    }
    elseif ($sourceKind -eq 'Workspace' -and $localCommit -ne $latestCommit -and (Test-SystemToolsLocalGitCommitContainsRemoteCommit -RemoteCommit $latestCommit -LocalCommit $localCommit)) {
        $statusName = 'LocalAhead'
        $statusMessage = "This workspace has local commits not yet published to GitHub $($remoteInfo.Branch). Latest published commit is $(Get-SystemToolsShortCommit -Commit $latestCommit); local HEAD is $(Get-SystemToolsShortCommit -Commit $localCommit)."
    }
    elseif ($null -ne $localVersionObject -and $null -ne $remoteVersionObject) {
        if ($localVersionObject -lt $remoteVersionObject) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion."
        }
        elseif ($localVersionObject -gt $remoteVersionObject) {
            $statusName = 'LocalAhead'
            $statusMessage = "Local version v$script:SystemToolsAppVersion is newer than the latest GitHub $($remoteInfo.Branch) version v$latestVersion."
        }
        elseif (
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            -not [string]::IsNullOrWhiteSpace($latestCommit) -and
            $localCommit -ne $latestCommit
        ) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion has commit $(Get-SystemToolsShortCommit -Commit $latestCommit); local is $(Get-SystemToolsShortCommit -Commit $localCommit)."
        }
        else {
            $statusName = 'UpToDate'
            $commitLabel = Get-SystemToolsShortCommit -Commit $latestCommit
            $statusMessage = if ([string]::IsNullOrWhiteSpace($commitLabel)) { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion." } else { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion ($commitLabel)." }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($latestVersion) -and $latestVersion -eq $script:SystemToolsAppVersion) {
        if (
            -not [string]::IsNullOrWhiteSpace($localCommit) -and
            -not [string]::IsNullOrWhiteSpace($latestCommit) -and
            $localCommit -ne $latestCommit
        ) {
            $statusName = 'UpdateAvailable'
            $statusMessage = "Update available from GitHub $($remoteInfo.Branch): v$latestVersion has commit $(Get-SystemToolsShortCommit -Commit $latestCommit); local is $(Get-SystemToolsShortCommit -Commit $localCommit)."
        }
        else {
            $statusName = 'UpToDate'
            $commitLabel = Get-SystemToolsShortCommit -Commit $latestCommit
            $statusMessage = if ([string]::IsNullOrWhiteSpace($commitLabel)) { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion." } else { "App is up to date with GitHub $($remoteInfo.Branch) at v$latestVersion ($commitLabel)." }
        }
    }

    $script:SystemToolsUpdateStatus = New-SystemToolsUpdateStatus `
        -LocalVersion $script:SystemToolsAppVersion `
        -LatestVersion $latestVersion `
        -LocalCommit $localCommit `
        -LatestCommit $latestCommit `
        -SourceKind $sourceKind `
        -HasLocalChanges $hasLocalChanges `
        -Repo ([string]$remoteInfo.Repo) `
        -Branch ([string]$remoteInfo.Branch) `
        -Status $statusName `
        -Message $statusMessage `
        -CheckedAt ((Get-Date).ToString('s'))

    Write-SystemToolsUpdateStatusCache -Status $script:SystemToolsUpdateStatus
    return $script:SystemToolsUpdateStatus
}

function Get-SystemToolsUpdateStatusPresentation {
    if ($null -eq $script:SystemToolsUpdateStatus) {
        $script:SystemToolsUpdateStatus = New-SystemToolsUpdateStatus
    }

    $label = 'Status unavailable'
    $color = $_C.Dim
    switch ([string]$script:SystemToolsUpdateStatus.Status) {
        'UpToDate' {
            $label = 'Up to date'
            $color = $_C.OK
        }
        'UpdateAvailable' {
            $label = if ([string]::IsNullOrWhiteSpace([string]$script:SystemToolsUpdateStatus.LatestVersion)) { 'Update available' } else { "Update available ($($script:SystemToolsUpdateStatus.LatestVersion))" }
            $color = $_C.Warn
        }
        'LocalAhead' {
            $label = 'Local version ahead'
            $color = $_C.Info
        }
        'WorkspaceModified' {
            $label = 'Workspace has local changes'
            $color = $_C.Info
        }
        'Error' {
            $label = 'Update check failed'
            $color = $_C.Fail
        }
    }

    [pscustomobject]@{
        Label         = $label
        Color         = $color
        LatestVersion = [string]$script:SystemToolsUpdateStatus.LatestVersion
        LocalVersion  = [string]$script:SystemToolsUpdateStatus.LocalVersion
        Repo          = [string]$script:SystemToolsUpdateStatus.Repo
        Branch        = [string]$script:SystemToolsUpdateStatus.Branch
        Message       = [string]$script:SystemToolsUpdateStatus.Message
        CheckedAt     = [string]$script:SystemToolsUpdateStatus.CheckedAt
        LocalCommit   = [string]$script:SystemToolsUpdateStatus.LocalCommit
        LatestCommit  = [string]$script:SystemToolsUpdateStatus.LatestCommit
        RemoteCommit  = [string]$script:SystemToolsUpdateStatus.LatestCommit
        SourceKind    = [string]$script:SystemToolsUpdateStatus.SourceKind
        HasLocalChanges = [bool]$script:SystemToolsUpdateStatus.HasLocalChanges
        Status        = [string]$script:SystemToolsUpdateStatus.Status
    }
}

function Get-RegPathKey {
    param([Parameter(Mandatory)][string]$CurrentScope)
    if ($CurrentScope -eq 'Machine') { return $MachineRegKey }
    return $UserRegKey
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AdminForMachine {
    param([Parameter(Mandatory)][string]$CurrentScope)
    if ($CurrentScope -ne 'Machine') { return }

    if (-not (Test-IsAdministrator)) {
        throw 'Machine PATH change requires Administrator privileges.'
    }
}

function Normalize-PathToken {
    param([Parameter(Mandatory)][string]$Value)

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return '' }

    try {
        $full = [System.IO.Path]::GetFullPath($trimmed)
        return $full.TrimEnd('\\')
    }
    catch {
        return $trimmed.TrimEnd('\\')
    }
}

function Get-PathEntries {
    param([Parameter(Mandatory)][string]$CurrentScope)

    $raw = [Environment]::GetEnvironmentVariable('Path', $CurrentScope)
    if ($null -eq $raw) { $raw = '' }

    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in ($raw -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $items.Add($entry.Trim())
    }

    # Return list as a single object (no PowerShell enumeration to fixed-size array).
    return ,$items
}

function Save-PathEntries {
    param(
        [Parameter(Mandatory)][string]$CurrentScope,
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Entries
    )

    $regKey = Get-RegPathKey -CurrentScope $CurrentScope
    $newPath = ($Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'

    Set-ItemProperty -Path $regKey -Name Path -Type ExpandString -Value $newPath
    [Environment]::SetEnvironmentVariable('Path', $newPath, $CurrentScope)
}

function Contains-Path {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Entries,
        [Parameter(Mandatory)][string]$Needle
    )

    $n = Normalize-PathToken -Value $Needle
    foreach ($entry in $Entries) {
        if ((Normalize-PathToken -Value $entry) -ieq $n) { return $true }
    }
    return $false
}

function Add-PathEntry {
    param(
        [Parameter(Mandatory)][string]$CurrentScope,
        [Parameter(Mandatory)][string]$PathToAdd,
        [switch]$Quiet
    )

    $entries = Get-PathEntries -CurrentScope $CurrentScope
    if (Contains-Path -Entries $entries -Needle $PathToAdd) {
        if (-not $Quiet) {
            Write-Host "Already present in $CurrentScope PATH: $PathToAdd" -ForegroundColor Yellow
        }
        return
    }

    $entries.Add($PathToAdd)
    Save-PathEntries -CurrentScope $CurrentScope -Entries $entries
    if (-not $Quiet) {
        Write-Host "Added to $CurrentScope PATH: $PathToAdd" -ForegroundColor Green
    }
}

function Remove-PathEntry {
    param(
        [Parameter(Mandatory)][string]$CurrentScope,
        [Parameter(Mandatory)][string]$PathToRemove,
        [switch]$Quiet
    )

    $entries = Get-PathEntries -CurrentScope $CurrentScope
    $needle = Normalize-PathToken -Value $PathToRemove

    $newEntries = [System.Collections.Generic.List[string]]::new()
    $removed = $false

    foreach ($entry in $entries) {
        if ((Normalize-PathToken -Value $entry) -ieq $needle) {
            $removed = $true
            continue
        }
        $newEntries.Add($entry)
    }

    if (-not $removed) {
        if (-not $Quiet) {
            Write-Host "Not found in $CurrentScope PATH: $PathToRemove" -ForegroundColor Yellow
        }
        return
    }

    Save-PathEntries -CurrentScope $CurrentScope -Entries $newEntries
    if (-not $Quiet) {
        Write-Host "Removed from $CurrentScope PATH: $PathToRemove" -ForegroundColor Green
    }
}

function Broadcast-EnvironmentChange {
    if (-not ('NativeEnvBroadcast' -as [Type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeEnvBroadcast {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        IntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out IntPtr lpdwResult);
}
"@
    }

    $HWND_BROADCAST = [IntPtr]0xFFFF
    $WM_SETTINGCHANGE = 0x001A
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [IntPtr]::Zero

    [void][NativeEnvBroadcast]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [IntPtr]::Zero,
        'Environment',
        $SMTO_ABORTIFHUNG,
        150,
        [ref]$result
    )
}

function Get-PathStatus {
    param([Parameter(Mandatory)][string]$PathToCheck)

    $userEntries = Get-PathEntries -CurrentScope 'User'
    $machineEntries = Get-PathEntries -CurrentScope 'Machine'

    [pscustomobject]@{
        InUser = Contains-Path -Entries $userEntries -Needle $PathToCheck
        InMachine = Contains-Path -Entries $machineEntries -Needle $PathToCheck
    }
}

function Get-ScopeEnvironmentData {
    param([Parameter(Mandatory)][ValidateSet('User', 'Machine')] [string]$CurrentScope)

    $rawMap = [System.Environment]::GetEnvironmentVariables($CurrentScope)
    $variables = @()
    foreach ($key in ($rawMap.Keys | Sort-Object)) {
        if ($key -eq 'Path') { continue }
        $variables += [pscustomobject]@{
            Name  = [string]$key
            Value = [string]$rawMap[$key]
        }
    }

    $rawPath = [System.Environment]::GetEnvironmentVariable('Path', $CurrentScope)
    if ($null -eq $rawPath) { $rawPath = '' }

    $paths = @()
    foreach ($entry in ($rawPath -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $paths += $entry.Trim()
    }

    [pscustomobject]@{
        Scope     = $CurrentScope
        Variables = $variables
        Paths     = $paths
    }
}

function Write-Separator {
    param(
        [string]$Text = '',
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Host ('─' * 56) -ForegroundColor $Color
        return
    }

    Write-Host ('─' * 56) -ForegroundColor $Color
    Write-Host $Text -ForegroundColor $Color
    Write-Host ('─' * 56) -ForegroundColor $Color
}

function Wait-ForEnvPaneCloseKey {

    Write-Host ''
    Write-Host 'Press 3 to close this snapshot pane.' -ForegroundColor Yellow

    while ($true) {
        try {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if (($key.Character -eq '3') -or ($key.VirtualKeyCode -eq 51)) {
                break
            }
        }
        catch {
            break
        }
    }
}

function Show-Status {
    param([Parameter(Mandatory)][string]$PathToCheck)

    $status = Get-PathStatus -PathToCheck $PathToCheck
    Write-Host ''
    Write-Separator -Text '📌 PATH Membership Status' -Color DarkCyan
    Write-Host "Target: $PathToCheck" -ForegroundColor Cyan

    $userBadge = if ($status.InUser) { '✅ YES' } else { '❌ NO' }
    $machineBadge = if ($status.InMachine) { '✅ YES' } else { '❌ NO' }

    Write-Host "User PATH:    $userBadge" -ForegroundColor Yellow
    Write-Host "Machine PATH: $machineBadge" -ForegroundColor Yellow
}

function Show-EnvironmentSnapshot {
    param([Parameter(Mandatory)][string]$PathToHighlight)

    $userData = Get-ScopeEnvironmentData -CurrentScope 'User'
    $machineData = Get-ScopeEnvironmentData -CurrentScope 'Machine'

    Write-Host ''
    Write-Separator -Text '🌿 Environment Snapshot (Terminal View)' -Color DarkGreen
    Show-Status -PathToCheck $PathToHighlight

    Write-Host ''
    Write-Separator -Text ('👤 User Variables ({0})' -f $userData.Variables.Count) -Color Green
    foreach ($row in $userData.Variables) {
        Write-Host ("  {0} = {1}" -f $row.Name, $row.Value) -ForegroundColor Gray
    }
    if ($userData.Variables.Count -eq 0) {
        Write-Host '  (No user variables found)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Separator -Text ('📂 User PATH Entries ({0})' -f $userData.Paths.Count) -Color Green
    $idx = 1
    foreach ($p in $userData.Paths) {
        $highlight = (Normalize-PathToken -Value $p) -ieq (Normalize-PathToken -Value $PathToHighlight)
        if ($highlight) {
            Write-Host ("  [{0,2}] ⭐ {1}" -f $idx, $p) -ForegroundColor Yellow
        }
        else {
            Write-Host ("  [{0,2}] {1}" -f $idx, $p) -ForegroundColor Gray
        }
        $idx++
    }
    if ($userData.Paths.Count -eq 0) {
        Write-Host '  (No user PATH entries found)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Separator -Text ('🖥  Machine Variables ({0})' -f $machineData.Variables.Count) -Color Magenta
    foreach ($row in $machineData.Variables) {
        Write-Host ("  {0} = {1}" -f $row.Name, $row.Value) -ForegroundColor Gray
    }
    if ($machineData.Variables.Count -eq 0) {
        Write-Host '  (No machine variables found)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Separator -Text ('📂 Machine PATH Entries ({0})' -f $machineData.Paths.Count) -Color Magenta
    $idx = 1
    foreach ($p in $machineData.Paths) {
        $highlight = (Normalize-PathToken -Value $p) -ieq (Normalize-PathToken -Value $PathToHighlight)
        if ($highlight) {
            Write-Host ("  [{0,2}] ⭐ {1}" -f $idx, $p) -ForegroundColor Yellow
        }
        else {
            Write-Host ("  [{0,2}] {1}" -f $idx, $p) -ForegroundColor Gray
        }
        $idx++
    }
    if ($machineData.Paths.Count -eq 0) {
        Write-Host '  (No machine PATH entries found)' -ForegroundColor DarkGray
    }
}

function Export-EnvironmentSnapshot {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][ValidateSet('Txt', 'Md', 'Both')] [string]$Format
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        [void](New-Item -ItemType Directory -Path $Directory -Force)
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $txtFile = Join-Path $Directory ("Env-Readable-{0}.txt" -f $stamp)
    $mdFile = Join-Path $Directory ("Env-Readable-{0}.md" -f $stamp)

    $systemData = Get-ScopeEnvironmentData -CurrentScope 'Machine'
    $userData = Get-ScopeEnvironmentData -CurrentScope 'User'

    if ($Format -in @('Txt', 'Both')) {
        $txt = @()
        $txt += 'Environment Variables Snapshot'
        $txt += ('Created: ' + $timestamp)
        $txt += ''
        $txt += '=== SYSTEM VARIABLES ==='
        foreach ($row in $systemData.Variables) {
            $txt += ($row.Name + '=' + $row.Value)
        }

        $txt += ''
        $txt += '--- SYSTEM PATH ---'
        foreach ($p in $systemData.Paths) {
            $txt += ('  ' + $p)
        }

        $txt += ''
        $txt += '=== USER VARIABLES ==='
        foreach ($row in $userData.Variables) {
            $txt += ($row.Name + '=' + $row.Value)
        }

        $txt += ''
        $txt += '--- USER PATH ---'
        foreach ($p in $userData.Paths) {
            $txt += ('  ' + $p)
        }

        $txt | Out-File -Encoding UTF8 -FilePath $txtFile
        Write-Host "Saved TXT: $txtFile" -ForegroundColor Green
    }

    if ($Format -in @('Md', 'Both')) {
        $md = @()
        $md += '# 🌱 Environment Variables Snapshot'
        $md += ''
        $md += '> Read-only documentation of Windows environment variables'
        $md += ''
        $md += ('**Created:** `' + $timestamp + '`')
        $md += ''
        $md += '---'
        $md += ''
        $md += '## 🖥 System Variables'
        $md += ''
        $md += '| Variable | Value |'
        $md += '|---------|-------|'
        foreach ($row in $systemData.Variables) {
            $safe = $row.Value -replace '\|', '\|'
            $md += ('| ' + $row.Name + ' | `' + $safe + '` |')
        }

        $md += ''
        $md += '### 📂 System PATH'
        $md += ''
        foreach ($p in $systemData.Paths) {
            $md += ('- `' + $p + '`')
        }

        $md += ''
        $md += '---'
        $md += ''
        $md += '## 👤 User Variables'
        $md += ''
        $md += '| Variable | Value |'
        $md += '|---------|-------|'
        foreach ($row in $userData.Variables) {
            $safe = $row.Value -replace '\|', '\|'
            $md += ('| ' + $row.Name + ' | `' + $safe + '` |')
        }

        $md += ''
        $md += '### 📂 User PATH'
        $md += ''
        foreach ($p in $userData.Paths) {
            $md += ('- `' + $p + '`')
        }

        $md += ''
        $md += '---'
        $md += ''
        $md += '📝 _Generated automatically. Safe for backup, diff and documentation._'

        $md | Out-File -Encoding UTF8BOM -FilePath $mdFile
        Write-Host "Saved MD:  $mdFile" -ForegroundColor Green
    }
}

function Invoke-ElevatedMachineAction {
    param(
        [Parameter(Mandatory)][ValidateSet('Add', 'Remove', 'Toggle')] [string]$RequestedAction,
        [Parameter(Mandatory)][string]$PathToUse
    )

    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCmd) { $pwshCmd.Source } else { Join-Path $PSHOME 'pwsh.exe' }

    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Action', $RequestedAction,
        '-Scope', 'Machine',
        '-TargetPath', $PathToUse,
        '-NoPause'
    )

    Start-Process -FilePath $pwshExe -Verb RunAs -ArgumentList $argList -Wait
}

function Invoke-PathAction {
    param(
        [Parameter(Mandatory)][ValidateSet('Status', 'Add', 'Remove', 'Toggle')] [string]$RequestedAction,
        [Parameter(Mandatory)][string]$RequestedScope,
        [Parameter(Mandatory)][string]$PathToUse,
        [switch]$SkipStatusOutput,
        [switch]$Quiet
    )

    switch ($RequestedAction) {
        'Status' {
            Show-Status -PathToCheck $PathToUse
        }
        'Add' {
            Assert-AdminForMachine -CurrentScope $RequestedScope
            Add-PathEntry -CurrentScope $RequestedScope -PathToAdd $PathToUse -Quiet:$Quiet
            Broadcast-EnvironmentChange
            if (-not $SkipStatusOutput) {
                Show-Status -PathToCheck $PathToUse
            }
        }
        'Remove' {
            Assert-AdminForMachine -CurrentScope $RequestedScope
            Remove-PathEntry -CurrentScope $RequestedScope -PathToRemove $PathToUse -Quiet:$Quiet
            Broadcast-EnvironmentChange
            if (-not $SkipStatusOutput) {
                Show-Status -PathToCheck $PathToUse
            }
        }
        'Toggle' {
            Assert-AdminForMachine -CurrentScope $RequestedScope
            $entries = Get-PathEntries -CurrentScope $RequestedScope
            if (Contains-Path -Entries $entries -Needle $PathToUse) {
                Remove-PathEntry -CurrentScope $RequestedScope -PathToRemove $PathToUse -Quiet:$Quiet
            }
            else {
                Add-PathEntry -CurrentScope $RequestedScope -PathToAdd $PathToUse -Quiet:$Quiet
            }
            Broadcast-EnvironmentChange
            if (-not $SkipStatusOutput) {
                Show-Status -PathToCheck $PathToUse
            }
        }
    }
}

function Ensure-MenuHostInWindowsTerminal {
    param([Parameter(Mandatory)][string]$PathToUse)

    if ($SkipWtBootstrap -or $env:WT_SESSION) { return $true }

    $wtCmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -eq $wtCmd) {
        Write-Host 'wt.exe not found. Continuing in current PowerShell host.' -ForegroundColor Yellow
        return $true
    }

    $argList = @(
        '-w', '0',
        'new-tab',
        '--title', 'System-Tools-PATH',
        'pwsh.exe',
        '-NoExit',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Action', 'Menu',
        '-TargetPath', $PathToUse,
        '-SkipWtBootstrap',
        '-NoPause'
    )

    Start-Process -FilePath $wtCmd.Source -ArgumentList $argList | Out-Null
    return $false
}

function Ensure-MenuElevation {
    param([Parameter(Mandatory)][string]$PathToUse)

    if (Test-IsAdministrator) { return $true }

    $wtCmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCmd) { $pwshCmd.Source } else { Join-Path $PSHOME 'pwsh.exe' }

    Write-Host 'Requesting admin elevation for full PATH control...' -ForegroundColor Yellow
    try {
        if ($null -ne $wtCmd) {
            $wtArgs = @(
                '-w', '0',
                'new-tab',
                '--title', 'System-Tools-PATH-Admin',
                'pwsh.exe',
                '-NoExit',
                '-ExecutionPolicy', 'Bypass',
                '-File', $PSCommandPath,
                '-Action', 'Menu',
                '-TargetPath', $PathToUse,
                '-SkipWtBootstrap',
                '-NoPause'
            )
            Start-Process -FilePath $wtCmd.Source -Verb RunAs -ArgumentList $wtArgs | Out-Null
        }
        else {
            $argList = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', $PSCommandPath,
                '-Action', 'Menu',
                '-TargetPath', $PathToUse,
                '-SkipWtBootstrap',
                '-NoPause'
            )
            Start-Process -FilePath $pwshExe -Verb RunAs -ArgumentList $argList | Out-Null
        }
        return $false
    }
    catch {
        Write-Host 'Elevation canceled. Continuing in standard mode.' -ForegroundColor Yellow
        return $true
    }
}

function Open-EnvSnapshotPane {
    param([Parameter(Mandatory)][string]$PathToUse)

    # WT supports split panes; outside WT we show inline.
    if (-not $env:WT_SESSION) {
        Show-EnvironmentSnapshot -PathToHighlight $PathToUse
        return
    }

    $argList = @(
        '-w', '0',
        'split-pane',
        '-V',
        '--title', 'ENV-Snapshot',
        'pwsh.exe',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Action', 'EnvView',
        '-TargetPath', $PathToUse,
        '-NoPause'
    )

    Start-Process -FilePath 'wt.exe' -ArgumentList $argList | Out-Null
}

function Invoke-MenuPathToggle {
    param(
        [Parameter(Mandatory)][ValidateSet('User', 'Machine')] [string]$CurrentScope,
        [Parameter(Mandatory)][string]$PathToUse
    )

    $entries = Get-PathEntries -CurrentScope $CurrentScope
    $wasPresent = Contains-Path -Entries $entries -Needle $PathToUse

    Invoke-PathAction -RequestedAction 'Toggle' -RequestedScope $CurrentScope -PathToUse $PathToUse -SkipStatusOutput -Quiet

    if ($wasPresent) {
        return "Removed from $CurrentScope PATH: $PathToUse"
    }

    return "Added to $CurrentScope PATH: $PathToUse"
}

function Get-SystemToolsInstallerAction {
    if (Test-Path -LiteralPath (Join-Path $script:SystemToolsRootPath '.git') -PathType Container) {
        return 'GitFastForward'
    }

    $installMetaPath = Join-Path $script:SystemToolsRootPath 'state\install-meta.json'
    if (Test-Path -LiteralPath $installMetaPath -PathType Leaf) {
        try {
            $installMeta = Get-Content -LiteralPath $installMetaPath -Raw | ConvertFrom-Json
            $installPathProperty = $installMeta.PSObject.Properties['install_path']
            if ($null -ne $installPathProperty -and -not [string]::IsNullOrWhiteSpace([string]$installPathProperty.Value)) {
                $recordedPath = [System.IO.Path]::GetFullPath([string]$installPathProperty.Value).TrimEnd('\')
                $rootPath = [System.IO.Path]::GetFullPath($script:SystemToolsRootPath).TrimEnd('\')
                if ($recordedPath -ieq $rootPath) {
                    return 'UpdateGitHub'
                }
            }
        }
        catch {
        }
    }

    $defaultInstallPath = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SystemToolsContext')).TrimEnd('\')
    $currentRootPath = [System.IO.Path]::GetFullPath($script:SystemToolsRootPath).TrimEnd('\')
    if ($currentRootPath -ieq $defaultInstallPath) {
        return 'UpdateGitHub'
    }

    return 'DownloadLatest'
}

function Get-SystemToolsGitBranch {
    try {
        $branch = (& git.exe -C $script:SystemToolsRootPath branch --show-current 2>$null | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($branch)) { return $branch }
    }
    catch {
    }

    try {
        $branch = (& git.exe -C $script:SystemToolsRootPath rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
        if ($branch -ne 'HEAD') { return $branch }
    }
    catch {
    }

    return ''
}

function Invoke-SystemToolsGitFastForwardUpdate {
    $recentLines = [System.Collections.Generic.List[string]]::new()
    function Add-RecentLine {
        param([AllowEmptyString()][string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
        [void]$recentLines.Add($Line)
        while ($recentLines.Count -gt 12) {
            $recentLines.RemoveAt(0)
        }
    }

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Add-RecentLine 'git.exe was not found in PATH.'
        return [pscustomobject]@{ Success = $false; Message = 'Git update failed: git.exe was not found.'; Lines = @($recentLines); ExitCode = 9001 }
    }

    try {
        $inside = (& git.exe -C $script:SystemToolsRootPath rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim()
        if ($inside -ne 'true') {
            Add-RecentLine 'This folder is not a git working copy.'
            return [pscustomobject]@{ Success = $false; Message = 'Git update failed: this folder is not a git working copy.'; Lines = @($recentLines); ExitCode = 9002 }
        }

        $dirty = (& git.exe -C $script:SystemToolsRootPath status --porcelain 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($dirty)) {
            Add-RecentLine 'Working copy has local changes. Fast-forward update refused.'
            Add-RecentLine 'Commit, stash, or discard local changes before updating this repo copy.'
            return [pscustomobject]@{ Success = $false; Message = 'Git update refused because the workspace is dirty.'; Lines = @($recentLines); ExitCode = 3 }
        }

        $branch = Get-SystemToolsGitBranch
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Add-RecentLine 'Could not determine the current git branch.'
            return [pscustomobject]@{ Success = $false; Message = 'Git update failed: current branch is unknown.'; Lines = @($recentLines); ExitCode = 9003 }
        }

        Add-RecentLine ("Fetching origin/{0}..." -f $branch)
        $fetchText = (& git.exe -C $script:SystemToolsRootPath fetch --prune origin $branch 2>&1 | Out-String).Trim()
        foreach ($line in ($fetchText -split "`r?`n")) { Add-RecentLine $line }
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Success = $false; Message = "Git fetch failed with exit code $LASTEXITCODE."; Lines = @($recentLines); ExitCode = $LASTEXITCODE }
        }

        $localHead = (& git.exe -C $script:SystemToolsRootPath rev-parse HEAD 2>&1 | Out-String).Trim()
        $remoteHead = (& git.exe -C $script:SystemToolsRootPath rev-parse "origin/$branch" 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($localHead) -and $localHead -eq $remoteHead) {
            Add-RecentLine ("Already up to date with origin/{0}." -f $branch)
            return [pscustomobject]@{ Success = $true; Message = 'Git working copy is already up to date.'; Lines = @($recentLines); ExitCode = 0 }
        }

        Add-RecentLine ("Fast-forwarding to origin/{0}..." -f $branch)
        $mergeText = (& git.exe -C $script:SystemToolsRootPath merge --ff-only "origin/$branch" 2>&1 | Out-String).Trim()
        foreach ($line in ($mergeText -split "`r?`n")) { Add-RecentLine $line }
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            Success = ($exitCode -eq 0)
            Message = if ($exitCode -eq 0) { 'Git working copy updated with fast-forward.' } else { "Git fast-forward failed with exit code $exitCode." }
            Lines   = @($recentLines)
            ExitCode = $exitCode
        }
    }
    catch {
        Add-RecentLine ("Git update failed: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ Success = $false; Message = 'Git update failed.'; Lines = @($recentLines); ExitCode = 9999 }
    }
}

function Invoke-SystemToolsInPlaceUpdate {
    $installerPath = Join-Path $script:SystemToolsRootPath 'Install.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        return [pscustomobject]@{
            Success = $false
            Message = 'Install.ps1 was not found next to this script.'
            Lines   = @()
        }
    }

    $action = Get-SystemToolsInstallerAction
    if ($action -eq 'GitFastForward') {
        Clear-Host
        Write-UiBanner -Title "$script:SystemToolsAppName v$script:SystemToolsAppVersion" -Subtitle 'Updating app'
        Write-Host "  $($_C.H2)Action:$($_C.Reset) $($_C.White)git fetch + fast-forward$($_C.Reset)"
        Write-Host "  $($_C.H2)Status:$($_C.Reset) $($_C.Info)Checking workspace...$($_C.Reset)"
        Write-Host ''
        return Invoke-SystemToolsGitFastForwardUpdate
    }

    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwshCommand -or -not (Test-Path -LiteralPath $pwshCommand.Source -PathType Leaf)) {
        return [pscustomobject]@{
            Success = $false
            Message = 'pwsh.exe was not found.'
            Lines   = @()
        }
    }

    $stdoutPath = Join-Path $env:TEMP ("SystemTools_updater_out_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path $env:TEMP ("SystemTools_updater_err_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $installerLogPath = Join-Path $script:SystemToolsRootPath 'logs\installer.log'
    $installerArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath,
        '-Action', $action,
        '-Force'
    )

    if ($action -eq 'UpdateGitHub') {
        $installerArgs += '-NoExplorerRestart'
    }
    if ($action -eq 'DownloadLatest') {
        $installerArgs += '-NoSelfRelaunch'
    }

    try {
        $process = Start-Process -FilePath $pwshCommand.Source -ArgumentList $installerArgs -WorkingDirectory $script:SystemToolsRootPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = "Could not start updater: $($_.Exception.Message)"
            Lines   = @()
        }
    }

    try {
        while (-not $process.HasExited) {
            Clear-Host
            Write-UiBanner -Title "$script:SystemToolsAppName v$script:SystemToolsAppVersion" -Subtitle 'Updating app'
            Write-Host "  $($_C.H2)Action:$($_C.Reset) $($_C.White)$action$($_C.Reset)"
            Write-Host "  $($_C.H2)Status:$($_C.Reset) $($_C.Info)Updating...$($_C.Reset)"
            Write-Host ''
            foreach ($line in @(Get-RecentTextLines -Path $installerLogPath -TailCount 8)) {
                Write-Host "  $($_C.Dim)$line$($_C.Reset)"
            }
            Start-Sleep -Milliseconds 300
        }

        $process.Refresh()
        $recentLines = @((Get-RecentTextLines -Path $installerLogPath -TailCount 8) + (Get-RecentTextLines -Path $stderrPath -TailCount 4))
        $exitCode = [int]$process.ExitCode
        return [pscustomobject]@{
            Success = ($exitCode -eq 0)
            Message = if ($exitCode -eq 0) { 'Update completed. Reopen PATH Manager to use the refreshed app.' } else { "Update failed with exit code $exitCode." }
            Lines   = $recentLines
        }
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            try {
                if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
            }
        }
    }
}

function Get-RecentTextLines {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TailCount = 8
    )

    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return @(Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction Stop)
        }
    }
    catch {
    }

    return @()
}

function Show-SystemToolsUpdateMenu {
    $options = @(
        'Run update now',
        'Refresh update status',
        'Back'
    )

    while ($true) {
        $status = Get-SystemToolsUpdateStatusPresentation
        $action = Get-SystemToolsInstallerAction
        $targetLabel = switch ($action) {
            'GitFastForward' { 'Git repo working copy' }
            'DownloadLatest' { 'Portable working copy' }
            default { 'Installed app copy' }
        }
        $methodLabel = switch ($action) {
            'GitFastForward' { 'Git fetch + fast-forward only' }
            'DownloadLatest' { 'Download latest into this folder' }
            default { 'Installer/GitHub in-place update' }
        }
        $latestLabel = if ([string]::IsNullOrWhiteSpace($status.LatestVersion)) { '--' } else { $status.LatestVersion }
        $branchLabel = if ([string]::IsNullOrWhiteSpace($status.Branch)) { '--' } else { $status.Branch }
        $checkedAtLabel = if ([string]::IsNullOrWhiteSpace($status.CheckedAt)) { '--' } else { $status.CheckedAt.Replace('T', ' ') }
        $localCommitLabel = if ([string]::IsNullOrWhiteSpace($status.LocalCommit)) { '--' } else { $status.LocalCommit.Substring(0, [Math]::Min(7, $status.LocalCommit.Length)) }
        $remoteCommitLabel = if ([string]::IsNullOrWhiteSpace($status.LatestCommit)) { '--' } else { $status.LatestCommit.Substring(0, [Math]::Min(7, $status.LatestCommit.Length)) }
        $sourceLabel = if ($status.HasLocalChanges) { "$($status.SourceKind) + local changes" } else { $status.SourceKind }

        $headerBlock = {
            Write-UiBanner -Title "$script:SystemToolsAppName v$script:SystemToolsAppVersion" -Subtitle 'PATH Manager'
            Write-Host "  $($_C.H2)Current version:$($_C.Reset) $($_C.Info)$script:SystemToolsAppVersion$($_C.Reset)"
            Write-Host "  $($_C.H2)Latest version :$($_C.Reset) $($_C.Info)$latestLabel$($_C.Reset)"
            Write-Host "  $($_C.H2)Update        :$($_C.Reset) $($status.Color)$($status.Label)$($_C.Reset)"
            Write-Host "  $($_C.H2)Status        :$($_C.Reset) $($_C.Info)$($status.Status)$($_C.Reset)"
            Write-Host "  $($_C.H2)Source        :$($_C.Reset) $($_C.Info)$sourceLabel$($_C.Reset)"
            Write-Host "  $($_C.H2)Repo / branch :$($_C.Reset) $($_C.Info)$($status.Repo)$($_C.Reset) $($_C.Dim)|$($_C.Reset) $($_C.Info)$branchLabel$($_C.Reset)"
            Write-Host "  $($_C.H2)Commits       :$($_C.Reset) $($_C.Info)$localCommitLabel$($_C.Reset) $($_C.Dim)->$($_C.Reset) $($_C.Info)$remoteCommitLabel$($_C.Reset)"
            Write-Host "  $($_C.H2)Target        :$($_C.Reset) $($_C.Info)$targetLabel$($_C.Reset)"
            Write-Host "  $($_C.H2)Method        :$($_C.Reset) $($_C.Info)$methodLabel$($_C.Reset)"
            Write-Host "  $($_C.H2)Last check    :$($_C.Reset) $($_C.Dim)$checkedAtLabel$($_C.Reset)"
            if (-not [string]::IsNullOrWhiteSpace($status.Message)) {
                Write-Host "  $($_C.H2)Message       :$($_C.Reset) $($_C.Dim)$($status.Message)$($_C.Reset)"
            }
            Write-Host ''
        }

        $choice = Invoke-ArrowMenu -Items $options -Title 'Update App' -HeaderBlock $headerBlock
        if ($null -eq $choice -or $choice -eq 'Back') { return }

        switch ($choice) {
            'Refresh update status' {
                [void](Resolve-SystemToolsUpdateStatus -ForceRefresh)
            }
            'Run update now' {
                $result = Invoke-SystemToolsInPlaceUpdate
                Clear-Host
                Write-UiBanner -Title "$script:SystemToolsAppName v$script:SystemToolsAppVersion" -Subtitle 'Update result'
                $tone = if ($result.Success) { $_C.OK } else { $_C.Fail }
                Write-Host "  $tone$($result.Message)$($_C.Reset)"
                Write-Host ''
                foreach ($line in @($result.Lines)) {
                    Write-Host "  $($_C.Dim)$line$($_C.Reset)"
                }
                Write-Host ''
                Read-Host "$($_C.Dim)Press Enter to return to menu...$($_C.Reset)" | Out-Null
                [void](Resolve-SystemToolsUpdateStatus -ForceRefresh)
            }
        }
    }
}

function Show-Menu {
    param([Parameter(Mandatory)][string]$PathToUse)

    $hasUi = Import-SystemToolsUi
    if (-not $hasUi) {
        throw 'PS_UI_Blueprint.psm1 was not found under .codex\tools. Install/restore the canonical blueprint first.'
    }

    Initialize-SystemToolsAppMetadata
    [void](Resolve-SystemToolsUpdateStatus)

    Initialize-TuiHost
    try {
        $options = @(
            'Toggle User PATH',
            'Toggle Machine PATH (Admin)',
            'Open ENV snapshot pane',
            'Export ENV snapshot (MD)',
            'Update app',
            'Exit'
        )
        $lastMessage = ''
        $lastTone = 'Info'

        while ($true) {
            $status = Get-PathStatus -PathToCheck $PathToUse
            $sessionMode = if (Test-IsAdministrator) { 'Admin' } else { 'Standard User' }
            $userBadge = if ($status.InUser) { 'YES' } else { 'NO' }
            $machineBadge = if ($status.InMachine) { 'YES' } else { 'NO' }
            $updateStatus = Get-SystemToolsUpdateStatusPresentation
            $sourceLabel = if ($updateStatus.HasLocalChanges) { "$($updateStatus.SourceKind) + local changes" } else { $updateStatus.SourceKind }
            $localCommitLabel = if ([string]::IsNullOrWhiteSpace($updateStatus.LocalCommit)) { '--' } else { $updateStatus.LocalCommit.Substring(0, [Math]::Min(7, $updateStatus.LocalCommit.Length)) }
            $latestCommitLabel = if ([string]::IsNullOrWhiteSpace($updateStatus.LatestCommit)) { '--' } else { $updateStatus.LatestCommit.Substring(0, [Math]::Min(7, $updateStatus.LatestCommit.Length)) }

            $headerBlock = {
                Write-UiBanner -Title "$script:SystemToolsAppName v$script:SystemToolsAppVersion" -Subtitle 'Resize-safe PATH and environment control'
                Write-Host "  $($_C.H2)Update        : $($updateStatus.Color)$($updateStatus.Label)$($_C.Reset)"
                Write-Host "  $($_C.H2)Version       : $($_C.Info)$($updateStatus.LocalVersion)$($_C.Reset) $($_C.Dim)->$($_C.Reset) $($_C.Info)$(if ([string]::IsNullOrWhiteSpace($updateStatus.LatestVersion)) { '--' } else { $updateStatus.LatestVersion })$($_C.Reset)"
                Write-Host "  $($_C.H2)Commits       : $($_C.Info)$localCommitLabel$($_C.Reset) $($_C.Dim)->$($_C.Reset) $($_C.Info)$latestCommitLabel$($_C.Reset)"
                Write-Host "  $($_C.H2)Source        : $($_C.Info)$sourceLabel$($_C.Reset)"
                Write-Host "  $($_C.H2)Target Folder : $($_C.Info)$PathToUse$($_C.Reset)"
                Write-Host "  $($_C.H2)Session Mode  : $($_C.Info)$sessionMode$($_C.Reset)"
                Write-Host "  $($_C.H2)User PATH     : $(if ($status.InUser) { $_C.OK } else { $_C.Fail })$userBadge$($_C.Reset)"
                Write-Host "  $($_C.H2)Machine PATH  : $(if ($status.InMachine) { $_C.OK } else { $_C.Fail })$machineBadge$($_C.Reset)"
                if (-not [string]::IsNullOrWhiteSpace($lastMessage)) {
                    $tone = if ($lastTone -eq 'Error') { $_C.Fail } elseif ($lastTone -eq 'Warn') { $_C.Warn } else { $_C.OK }
                    Write-Host "  $($_C.H2)Last Action   : $tone$lastMessage$($_C.Reset)"
                }
                Write-Host ''
            }

            $choice = Invoke-ArrowMenu -Items $options -Title 'Choose Action' -HeaderBlock $headerBlock
            if ($null -eq $choice -or $choice -eq 'Exit') { break }

            try {
                switch ($choice) {
                    'Toggle User PATH' {
                        $lastMessage = Invoke-MenuPathToggle -CurrentScope 'User' -PathToUse $PathToUse
                        $lastTone = 'Info'
                        continue
                    }
                    'Toggle Machine PATH (Admin)' {
                        if (Test-IsAdministrator) {
                            $lastMessage = Invoke-MenuPathToggle -CurrentScope 'Machine' -PathToUse $PathToUse
                            $lastTone = 'Info'
                        }
                        else {
                            Invoke-ElevatedMachineAction -RequestedAction 'Toggle' -PathToUse $PathToUse
                            $lastMessage = "Machine PATH toggle completed in elevated helper: $PathToUse"
                            $lastTone = 'Info'
                        }
                        continue
                    }
                    'Open ENV snapshot pane' {
                        Open-EnvSnapshotPane -PathToUse $PathToUse
                        $lastMessage = 'Opened ENV snapshot pane.'
                        $lastTone = 'Info'
                        continue
                    }
                    'Export ENV snapshot (MD)' {
                        Clear-Host
                        $desktop = [Environment]::GetFolderPath('Desktop')
                        $exportDir = Read-Host "Export directory (blank = $desktop)"
                        if ([string]::IsNullOrWhiteSpace($exportDir)) { $exportDir = $desktop }
                        Export-EnvironmentSnapshot -Directory $exportDir -Format 'Md'
                        $lastMessage = "Exported ENV snapshot to: $exportDir"
                        $lastTone = 'Info'
                        Write-Host ''
                        Read-Host "$($_C.Dim)Press Enter to return to menu...$($_C.Reset)" | Out-Null
                    }
                    'Update app' {
                        Show-SystemToolsUpdateMenu
                        continue
                    }
                }
            }
            catch {
                $lastMessage = $_.Exception.Message
                $lastTone = 'Error'
            }
        }
    }
    finally {
        Restore-TuiHost
    }
}

$TargetPath = [System.IO.Path]::GetFullPath($TargetPath)

switch ($Action) {
    'Menu' {
        if (Ensure-MenuElevation -PathToUse $TargetPath) {
            if (Ensure-MenuHostInWindowsTerminal -PathToUse $TargetPath) {
                Show-Menu -PathToUse $TargetPath
            }
        }
    }
    'Status' {
        Invoke-PathAction -RequestedAction 'Status' -RequestedScope $Scope -PathToUse $TargetPath
    }
    'Add' {
        Invoke-PathAction -RequestedAction 'Add' -RequestedScope $Scope -PathToUse $TargetPath
    }
    'Remove' {
        Invoke-PathAction -RequestedAction 'Remove' -RequestedScope $Scope -PathToUse $TargetPath
    }
    'Toggle' {
        Invoke-PathAction -RequestedAction 'Toggle' -RequestedScope $Scope -PathToUse $TargetPath
    }
    'EnvView' {
        Show-EnvironmentSnapshot -PathToHighlight $TargetPath
        Wait-ForEnvPaneCloseKey
    }
    'EnvExport' {
        Export-EnvironmentSnapshot -Directory $OutputDirectory -Format $ExportFormat
    }
}

if (($Action -notin @('Menu', 'EnvView')) -and (-not $NoPause)) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

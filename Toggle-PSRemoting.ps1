#requires -version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_E = [char]27
$_C = @{
    H2    = "$_E[38;2;140;160;180m"
    OK    = "$_E[38;2;46;204;113m"
    Warn  = "$_E[38;2;241;196;15m"
    Fail  = "$_E[38;2;231;76;60m"
    Info  = "$_E[38;2;52;152;219m"
    Dim   = "$_E[38;2;100;110;120m"
    Reset = "$_E[0m"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath
    ) | Out-Null
}

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

function Get-TrustedHostsValue {
    try {
        return [string](Get-Item -Path WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
    }
    catch {
        return ''
    }
}

function Get-TrustedHostsList {
    $rawValue = Get-TrustedHostsValue
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return @()
    }

    return @(
        $rawValue -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Get-WinRmState {
    $service = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    $trustedHosts = Get-TrustedHostsValue

    [pscustomobject]@{
        ServiceStatus = if ($service) { [string]$service.Status } else { 'Missing' }
        StartupType = if ($service) { [string]$service.StartType } else { 'Unknown' }
        TrustedHosts = $trustedHosts
        RefreshedAt = Get-Date
    }
}

function Show-StatusBlock {
    param([Parameter(Mandatory)]$State)

    $serviceColor = if ($state.ServiceStatus -eq 'Running') { $_C.OK } else { $_C.Fail }
    $startupColor = if ($state.StartupType -eq 'Automatic') { $_C.Warn } else { $_C.Dim }
    $trustedHostsLabel = if ([string]::IsNullOrWhiteSpace($state.TrustedHosts)) { 'None (empty)' } else { $state.TrustedHosts }
    $trustedHostsColor = if ([string]::IsNullOrWhiteSpace($state.TrustedHosts)) { $_C.Dim } else { $_C.Info }

    Write-Host "  $($_C.H2)Service Status : $serviceColor$($state.ServiceStatus)$($_C.Reset)"
    Write-Host "  $($_C.H2)Startup Type   : $startupColor$($state.StartupType)$($_C.Reset)"
    Write-Host "  $($_C.H2)TrustedHosts   : $trustedHostsColor$trustedHostsLabel$($_C.Reset)"
    Write-Host "  $($_C.H2)Updated        : $($_C.Dim)$($state.RefreshedAt.ToString('HH:mm:ss'))$($_C.Reset)"
    Write-Host ''
}

function Pause-ForMenu {
    Write-Host ''
    Read-Host "$($_C.Dim)Press Enter to return to menu...$($_C.Reset)" | Out-Null
}

function Invoke-EnableRemoting {
    Write-UiSection -Title 'Enable PSRemoting' -Icon '>'
    try {
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Write-Host ''
        Write-Host "$($_C.OK)PSRemoting enabled successfully.$($_C.Reset)"
    }
    catch {
        Write-Host ''
        Write-Host "$($_C.Fail)Failed to enable PSRemoting: $($_.Exception.Message)$($_C.Reset)"
    }
}

function Invoke-DisableRemoting {
    Write-UiSection -Title 'Disable PSRemoting' -Icon '>'
    try {
        Write-Host '  Stopping WinRM service...' -ForegroundColor DarkGray
        Stop-Service -Name WinRM -ErrorAction SilentlyContinue
        Write-Host '  Setting WinRM startup to Disabled...' -ForegroundColor DarkGray
        Set-Service -Name WinRM -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host '  Disabling WinRM firewall rules...' -ForegroundColor DarkGray
        Disable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue | Out-Null
        Write-Host ''
        Write-Host "$($_C.OK)PSRemoting disabled successfully.$($_C.Reset)"
    }
    catch {
        Write-Host ''
        Write-Host "$($_C.Fail)Failed to disable PSRemoting: $($_.Exception.Message)$($_C.Reset)"
    }
}

function Invoke-AddTrustedHost {
    Write-UiSection -Title 'Add TrustedHost' -Icon '>'
    $existing = Get-TrustedHostsList
    $existingLabel = if ($existing.Count -gt 0) { $existing -join ', ' } else { 'None (empty)' }
    Write-Host "  Current TrustedHosts: $existingLabel" -ForegroundColor Gray

    $newHost = (Read-Host '  Enter hostname or IP (blank = cancel)').Trim()
    if ([string]::IsNullOrWhiteSpace($newHost)) {
        Write-Host ''
        Write-Host "$($_C.Warn)Canceled.$($_C.Reset)"
        return
    }

    if ($existing -icontains $newHost) {
        Write-Host ''
        Write-Host "$($_C.Warn)TrustedHost already exists: $newHost$($_C.Reset)"
        return
    }

    try {
        $updated = @($existing + $newHost)
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value ($updated -join ',') -Force
        Write-Host ''
        Write-Host "$($_C.OK)TrustedHost added: $newHost$($_C.Reset)"
    }
    catch {
        Write-Host ''
        Write-Host "$($_C.Fail)Failed to update TrustedHosts: $($_.Exception.Message)$($_C.Reset)"
    }
}

function Invoke-ClearTrustedHosts {
    Write-UiSection -Title 'Clear TrustedHosts' -Icon '>'
    try {
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value '' -Force
        Write-Host ''
        Write-Host "$($_C.OK)TrustedHosts cleared successfully.$($_C.Reset)"
    }
    catch {
        Write-Host ''
        Write-Host "$($_C.Fail)Failed to clear TrustedHosts: $($_.Exception.Message)$($_C.Reset)"
    }
}

if (-not (Test-IsAdministrator)) {
    Start-ElevatedSelf
    exit
}

$blueprintPath = Get-BlueprintModulePath
if ([string]::IsNullOrWhiteSpace($blueprintPath)) {
    throw 'PS_UI_Blueprint.psm1 was not found under .codex\tools. Install/restore the canonical blueprint first.'
}

Import-Module $blueprintPath -Force -DisableNameChecking
Initialize-TuiHost

$options = @(
    'Enable PSRemoting',
    'Disable PSRemoting',
    'Add TrustedHost',
    'Clear TrustedHosts',
    'Exit'
)

try {
    while ($true) {
        $state = Get-WinRmState
        $headerBlock = {
            Write-UiBanner -Title 'WinRM / PSRemoting Manager' -Subtitle 'Resize-safe WinRM and TrustedHosts control'
            Show-StatusBlock -State $state
        }

        $choice = Invoke-ArrowMenu -Items $options -Title 'Select Action' -HeaderBlock $headerBlock
        if ($null -eq $choice -or $choice -eq 'Exit') {
            break
        }

        Clear-Host
        switch ($choice) {
            'Enable PSRemoting' { Invoke-EnableRemoting }
            'Disable PSRemoting' { Invoke-DisableRemoting }
            'Add TrustedHost' { Invoke-AddTrustedHost }
            'Clear TrustedHosts' { Invoke-ClearTrustedHosts }
        }

        Pause-ForMenu
    }
}
finally {
    Restore-TuiHost
}

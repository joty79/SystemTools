#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Status')]
    [string]$Action = 'Install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseKey = 'HKCU\Software\Classes\Directory\shell\SystemTools'
$legacyKeys = @(
    'HKCR\Directory\shell\SystemTools',
    'HKCU\Software\Classes\Directory\shell\SystemTools'
)

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$toolScript = Join-Path $scriptRoot 'AddDelPath.ps1'

if (-not (Test-Path -LiteralPath $toolScript)) {
    throw "Missing required script: $toolScript"
}

function Reg-Run([string[]]$RegArgs, [switch]$IgnoreNotFound, [switch]$IgnoreAccessDenied) {
    $out = & reg.exe @RegArgs 2>&1
    if ($LASTEXITCODE -eq 0) { return $out }

    $text = ($out | Out-String).Trim().ToLowerInvariant()
    if ($IgnoreNotFound -and $text -match 'unable to find the specified registry key or value') { return $null }
    if ($IgnoreAccessDenied -and $text -match 'access is denied') { return $null }

    throw "reg.exe failed: reg $($RegArgs -join ' ')`n$($out | Out-String)"
}

function Add-Value([string]$Key, [string]$Name, [string]$Type, [AllowEmptyString()][string]$Data) {
    $value = if ($Type -eq 'REG_DWORD') { if ([string]::IsNullOrWhiteSpace($Data)) { '0' } else { $Data } } else { if ($Data -eq '') { '""' } else { $Data } }
    $args = @('add', $Key)
    if ($Name -eq '(default)') { $args += '/ve' } else { $args += @('/v', $Name) }
    $args += @('/t', $Type, '/d', $value, '/f')
    Reg-Run -RegArgs $args | Out-Null
}

function Remove-Key([string]$Key) {
    Reg-Run -RegArgs @('delete', $Key, '/f') -IgnoreNotFound -IgnoreAccessDenied | Out-Null
}

function Install-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }

    Add-Value -Key $baseKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'
    Add-Value -Key $baseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-73'

    $statusKey = "$baseKey\shell\PathStatus"
    Add-Value -Key $statusKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Folder PATH Status (User/Machine)'
    Add-Value -Key $statusKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-5302'
    Add-Value -Key "$statusKey\command" -Name '(default)' -Type 'REG_SZ' -Data "pwsh.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$toolScript`" -Action Status -TargetPath `"%1`""

    $toggleUserKey = "$baseKey\shell\PathToggleUser"
    Add-Value -Key $toggleUserKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Toggle Folder in User PATH'
    Add-Value -Key $toggleUserKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-5302'
    Add-Value -Key "$toggleUserKey\command" -Name '(default)' -Type 'REG_SZ' -Data "pwsh.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$toolScript`" -Action Toggle -Scope User -TargetPath `"%1`""

    Write-Host 'System Tools folder context menu installed.' -ForegroundColor Green
}

function Uninstall-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }
    Write-Host 'System Tools folder context menu removed.' -ForegroundColor Green
}

function Show-Status {
    $q = Reg-Run -RegArgs @('query', $baseKey) -IgnoreNotFound
    if ($null -eq $q) {
        Write-Host 'System Tools menu: NOT INSTALLED' -ForegroundColor Yellow
    }
    else {
        Write-Host 'System Tools menu: INSTALLED' -ForegroundColor Green
    }
}

switch ($Action) {
    'Install' { Install-Menu }
    'Uninstall' { Uninstall-Menu }
    'Status' { Show-Status }
}

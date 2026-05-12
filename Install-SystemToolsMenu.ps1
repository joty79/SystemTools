#requires -version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Status')]
    [string]$Action = 'Install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fileBaseKey = 'HKCU\Software\Classes\*\shell\SystemTools'
$directoryBaseKey = 'HKCU\Software\Classes\Directory\shell\SystemTools'
$backgroundBaseKey = 'HKCU\Software\Classes\Directory\Background\shell\SystemTools'
$desktopBaseKey = 'HKCU\Software\Classes\DesktopBackground\Shell\SystemTools'
$exeBaseKey = 'HKCU\Software\Classes\exefile\shell\SystemTools'
$legacyKeys = @(
    'HKCR\*\shell\SystemTools',
    'HKCU\Software\Classes\*\shell\SystemTools',
    'HKCR\Directory\shell\SystemTools',
    'HKCU\Software\Classes\Directory\shell\SystemTools',
    'HKCR\Directory\Background\shell\SystemTools',
    'HKCU\Software\Classes\Directory\Background\shell\SystemTools',
    'HKCR\DesktopBackground\Shell\SystemTools',
    'HKCU\Software\Classes\DesktopBackground\Shell\SystemTools',
    'HKCR\exefile\shell\SystemTools',
    'HKCU\Software\Classes\exefile\shell\SystemTools'
)

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$iconsDir = Join-Path $scriptRoot '.assets\icons'
$requiredFiles = @(
    'AddDelPath.ps1',
    'RestartExplorer.ps1',
    'RefreshShell.ps1',
    'Clear-IconCache.ps1',
    'Launch-SystemToolsMenu.vbs',
    'Launch-RestartExplorer.vbs',
    'Launch-RefreshShell.vbs',
    'Launch-ClearIconCache.vbs'
)

foreach ($file in $requiredFiles) {
    $path = Join-Path $scriptRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $path"
    }
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
    $value = if ($Type -eq 'REG_DWORD') { if ([string]::IsNullOrWhiteSpace($Data)) { '0' } else { $Data } } else { $Data }
    $regArgs = @('add', $Key)
    if ($Name -eq '(default)') { $regArgs += '/ve' } else { $regArgs += @('/v', $Name) }
    $regArgs += @('/t', $Type, '/d', $value, '/f')
    Reg-Run -RegArgs $regArgs | Out-Null
}

function Remove-Key([string]$Key) {
    Reg-Run -RegArgs @('delete', $Key, '/f') -IgnoreNotFound -IgnoreAccessDenied | Out-Null
}

function Add-RootMenu([string]$BaseKey, [switch]$Desktop) {
    Add-Value -Key $BaseKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'
    Add-Value -Key $BaseKey -Name 'SubCommands' -Type 'REG_SZ' -Data ''
    Add-Value -Key $BaseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-109'
    if ($Desktop) { Add-Value -Key $BaseKey -Name 'Position' -Type 'REG_SZ' -Data 'Bottom' }
}

function Add-ToolMenu([string]$ToolKey, [string]$Label, [string]$Icon, [string]$Command, [switch]$Separator) {
    Add-Value -Key $ToolKey -Name 'MUIVerb' -Type 'REG_SZ' -Data $Label
    Add-Value -Key $ToolKey -Name 'Icon' -Type 'REG_SZ' -Data $Icon
    if ($Separator) { Add-Value -Key $ToolKey -Name 'CommandFlags' -Type 'REG_DWORD' -Data '32' }
    Add-Value -Key "$ToolKey\command" -Name '(default)' -Type 'REG_SZ' -Data $Command
}

function Add-ExplorerTools([string]$BaseKey, [string]$TargetToken) {
    Add-ToolMenu -ToolKey "$BaseKey\shell\01RefreshShell" -Label 'Refresh Shell' -Icon "$iconsDir\refresh_shell.ico" -Command "wscript.exe `"$scriptRoot\Launch-RefreshShell.vbs`""
    Add-ToolMenu -ToolKey "$BaseKey\shell\02RestartExplorer" -Label 'Restart Explorer' -Icon "$iconsDir\restart_explorer.ico" -Command "wscript.exe `"$scriptRoot\Launch-RestartExplorer.vbs`" `"$TargetToken`""
    Add-ToolMenu -ToolKey "$BaseKey\shell\03ClearIconCache" -Label 'Clear Icon Cache' -Icon "$iconsDir\Clear-IconCache.ico" -Command "wscript.exe `"$scriptRoot\Launch-ClearIconCache.vbs`""
}

function Add-PathManager([string]$BaseKey, [string]$TargetToken) {
    Add-ToolMenu -ToolKey "$BaseKey\shell\20PathManager" -Label 'Manage Folder PATH...' -Icon "$iconsDir\folder_to_path.ico" -Command "wscript.exe `"$scriptRoot\Launch-SystemToolsMenu.vbs`" `"$TargetToken`"" -Separator
}

function Install-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }

    Add-RootMenu -BaseKey $fileBaseKey

    Add-RootMenu -BaseKey $directoryBaseKey
    Add-ExplorerTools -BaseKey $directoryBaseKey -TargetToken '%1'
    Add-PathManager -BaseKey $directoryBaseKey -TargetToken '%1'

    Add-RootMenu -BaseKey $backgroundBaseKey
    Add-ExplorerTools -BaseKey $backgroundBaseKey -TargetToken '%V'
    Add-PathManager -BaseKey $backgroundBaseKey -TargetToken '%V'

    Add-RootMenu -BaseKey $desktopBaseKey -Desktop
    Add-ExplorerTools -BaseKey $desktopBaseKey -TargetToken '%V'

    Add-RootMenu -BaseKey $exeBaseKey

    Write-Host 'System Tools context menu installed.' -ForegroundColor Green
}

function Uninstall-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }
    Write-Host 'System Tools context menu removed.' -ForegroundColor Green
}

function Show-Status {
    $queries = @($fileBaseKey, $directoryBaseKey, $backgroundBaseKey, $desktopBaseKey, $exeBaseKey) | ForEach-Object {
        Reg-Run -RegArgs @('query', $_) -IgnoreNotFound
    }

    if (($queries | Where-Object { $null -ne $_ }).Count -eq 0) {
        Write-Host 'System Tools menu: NOT INSTALLED' -ForegroundColor Yellow
        return
    }

    Write-Host 'System Tools menu: INSTALLED' -ForegroundColor Green
}

switch ($Action) {
    'Install' { Install-Menu }
    'Uninstall' { Uninstall-Menu }
    'Status' { Show-Status }
}

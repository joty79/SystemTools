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
$legacyKeys = @(
    'HKCR\*\shell\SystemTools',
    'HKCU\Software\Classes\*\shell\SystemTools',
    'HKCR\Directory\shell\SystemTools',
    'HKCU\Software\Classes\Directory\shell\SystemTools',
    'HKCR\Directory\Background\shell\SystemTools',
    'HKCU\Software\Classes\Directory\Background\shell\SystemTools',
    'HKCR\DesktopBackground\Shell\SystemTools',
    'HKCU\Software\Classes\DesktopBackground\Shell\SystemTools'
)

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$iconsDir   = Join-Path $scriptRoot '.assets\icons'
$toolScript = Join-Path $scriptRoot 'AddDelPath.ps1'
$restartScript = Join-Path $scriptRoot 'RestartExplorer.ps1'
$refreshScript = Join-Path $scriptRoot 'RefreshShell.ps1'

if (-not (Test-Path -LiteralPath $toolScript)) {
    throw "Missing required script: $toolScript"
}

if (-not (Test-Path -LiteralPath $restartScript)) {
    throw "Missing required script: $restartScript"
}

if (-not (Test-Path -LiteralPath $refreshScript)) {
    throw "Missing required script: $refreshScript"
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

function Install-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }

    Add-Value -Key $fileBaseKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'
    Add-Value -Key $fileBaseKey -Name 'SubCommands' -Type 'REG_SZ' -Data ''
    Add-Value -Key $fileBaseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-109'

    Add-Value -Key $directoryBaseKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'
    Add-Value -Key $directoryBaseKey -Name 'SubCommands' -Type 'REG_SZ' -Data ''
    Add-Value -Key $directoryBaseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-109'

    $pathManagerKey = "$directoryBaseKey\shell\PathManager"
    Add-Value -Key $pathManagerKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Manage Folder PATH...'
    Add-Value -Key $pathManagerKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\folder_to_path.ico"
    Add-Value -Key "$pathManagerKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-SystemToolsMenu.vbs`" `"%1`""

    $restartExplorerKey = "$directoryBaseKey\shell\RestartExplorer"
    Add-Value -Key $restartExplorerKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Restart Explorer'
    Add-Value -Key $restartExplorerKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\restart_explorer.ico"
    Add-Value -Key "$restartExplorerKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-RestartExplorer.vbs`" `"%1`""

    $refreshShellKey = "$directoryBaseKey\shell\RefreshShell"
    Add-Value -Key $refreshShellKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Refresh Shell'
    Add-Value -Key $refreshShellKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\refresh_shell.ico"
    Add-Value -Key "$refreshShellKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-RefreshShell.vbs`""

    Add-Value -Key $backgroundBaseKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'
    Add-Value -Key $backgroundBaseKey -Name 'SubCommands' -Type 'REG_SZ' -Data ''
    Add-Value -Key $backgroundBaseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-109'

    $backgroundPathKey = "$backgroundBaseKey\shell\PathManager"
    Add-Value -Key $backgroundPathKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Manage Folder PATH...'
    Add-Value -Key $backgroundPathKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\folder_to_path.ico"
    Add-Value -Key "$backgroundPathKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-SystemToolsMenu.vbs`" `"%V`""

    $backgroundRestartKey = "$backgroundBaseKey\shell\RestartExplorer"
    Add-Value -Key $backgroundRestartKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Restart Explorer'
    Add-Value -Key $backgroundRestartKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\restart_explorer.ico"
    Add-Value -Key "$backgroundRestartKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-RestartExplorer.vbs`" `"%V`""

    $backgroundRefreshKey = "$backgroundBaseKey\shell\RefreshShell"
    Add-Value -Key $backgroundRefreshKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Refresh Shell'
    Add-Value -Key $backgroundRefreshKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\refresh_shell.ico"
    Add-Value -Key "$backgroundRefreshKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-RefreshShell.vbs`""

    Add-Value -Key $desktopBaseKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'
    Add-Value -Key $desktopBaseKey -Name 'SubCommands' -Type 'REG_SZ' -Data ''
    Add-Value -Key $desktopBaseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-109'

    $desktopRestartKey = "$desktopBaseKey\shell\RestartExplorer"
    Add-Value -Key $desktopRestartKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Restart Explorer'
    Add-Value -Key $desktopRestartKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\restart_explorer.ico"
    Add-Value -Key "$desktopRestartKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-RestartExplorer.vbs`" `"%V`""

    $desktopRefreshKey = "$desktopBaseKey\shell\RefreshShell"
    Add-Value -Key $desktopRefreshKey -Name 'MUIVerb' -Type 'REG_SZ' -Data 'Refresh Shell'
    Add-Value -Key $desktopRefreshKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\refresh_shell.ico"
    Add-Value -Key "$desktopRefreshKey\command" -Name '(default)' -Type 'REG_SZ' -Data "wscript.exe `"$scriptRoot\Launch-RefreshShell.vbs`""

    Write-Host 'System Tools folder context menu installed.' -ForegroundColor Green
}

function Uninstall-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }
    Write-Host 'System Tools folder context menu removed.' -ForegroundColor Green
}

function Show-Status {
    $directoryQuery = Reg-Run -RegArgs @('query', $directoryBaseKey) -IgnoreNotFound
    $backgroundQuery = Reg-Run -RegArgs @('query', $backgroundBaseKey) -IgnoreNotFound
    $desktopQuery = Reg-Run -RegArgs @('query', $desktopBaseKey) -IgnoreNotFound
    $fileQuery = Reg-Run -RegArgs @('query', $fileBaseKey) -IgnoreNotFound
    if ($null -eq $directoryQuery -and $null -eq $backgroundQuery -and $null -eq $desktopQuery -and $null -eq $fileQuery) {
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

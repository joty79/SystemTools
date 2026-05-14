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
    'HKCU\Software\Classes\DesktopBackground\Shell\SystemTools',
    'HKCR\exefile\shell\SystemTools',
    'HKCU\Software\Classes\exefile\shell\SystemTools',
    # Cleanup old standalone context menu entries
    'HKCU\Software\Classes\exefile\shell\FirewallManager',
    'HKCU\Software\Classes\Directory\shell\FirewallManager',
    'HKCR\DesktopBackground\Shell\killall',
    'HKCR\Directory\Background\shell\killall',
    'HKCR\DesktopBackground\Shell\SafeMode',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\NormalMode',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\SafeMode',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\RestartNow',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ShutdownNow',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\SleepNow',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\LogOffNow'
)

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$iconsDir = Join-Path $scriptRoot '.assets\icons'
$requiredFiles = @(
    'AddDelPath.ps1',
    'RestartExplorer.ps1',
    'RefreshShell.ps1',
    'Clear-IconCache.ps1',
    'SystemToolsManager.ps1',
    'KillAll.ps1',
    'SafeMode.ps1',
    'NormalMode.ps1',
    'Launch-SystemToolsMenu.vbs',
    'Launch-RestartExplorer.vbs',
    'Launch-RefreshShell.vbs',
    'Launch-ClearIconCache.vbs',
    'Launch-SystemToolsManager.vbs',
    'Launch-FirewallMenu.vbs',
    'KillAll_Silent.vbs',
    'Launch-SafeMode.vbs',
    'Launch-NormalMode.vbs'
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
    Add-Value -Key $BaseKey -Name 'SubCommands' -Type 'REG_SZ' -Data 'Explorer;PowerMenu;Windows;z_ToolManager'
    Add-Value -Key $BaseKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-109'
    if ($Desktop) { Add-Value -Key $BaseKey -Name 'Position' -Type 'REG_SZ' -Data 'Bottom' }
}

function Add-GroupMenu([string]$BaseKey, [string]$KeyName, [string]$Label, [string]$Icon) {
    $groupKey = "$BaseKey\shell\$KeyName"
    Add-Value -Key $groupKey -Name 'MUIVerb' -Type 'REG_SZ' -Data $Label
    Add-Value -Key $groupKey -Name 'SubCommands' -Type 'REG_SZ' -Data ''
    Add-Value -Key $groupKey -Name 'Icon' -Type 'REG_SZ' -Data $Icon
}

function Add-ToolMenu([string]$ToolKey, [string]$Label, [string]$Icon, [string]$Command, [string]$CommandFlags = '') {
    Add-Value -Key $ToolKey -Name 'MUIVerb' -Type 'REG_SZ' -Data $Label
    Add-Value -Key $ToolKey -Name 'Icon' -Type 'REG_SZ' -Data $Icon
    if (-not [string]::IsNullOrWhiteSpace($CommandFlags)) {
        Add-Value -Key $ToolKey -Name 'CommandFlags' -Type 'REG_DWORD' -Data $CommandFlags
    }
    Add-Value -Key "$ToolKey\command" -Name '(default)' -Type 'REG_SZ' -Data $Command
}

function Add-ExplorerGroup([string]$BaseKey) {
    Add-GroupMenu -BaseKey $BaseKey -KeyName 'Explorer' -Label 'Explorer' -Icon "$iconsDir\explorer.ico"
}

function Add-WindowsGroup([string]$BaseKey) {
    Add-GroupMenu -BaseKey $BaseKey -KeyName 'Windows' -Label 'Windows' -Icon "$iconsDir\windows.ico"
}

function Add-ExplorerTools([string]$BaseKey, [string]$TargetToken) {
    $explorerKey = "$BaseKey\shell\Explorer\shell"
    Add-ToolMenu -ToolKey "$explorerKey\RefreshShell" -Label 'Refresh Shell' -Icon "$iconsDir\refresh_shell.ico" -Command "wscript.exe `"$scriptRoot\Launch-RefreshShell.vbs`""
    Add-ToolMenu -ToolKey "$explorerKey\RestartExplorer" -Label 'Restart Explorer' -Icon "$iconsDir\restart_explorer.ico" -Command "wscript.exe `"$scriptRoot\Launch-RestartExplorer.vbs`" `"$TargetToken`""
    Add-ToolMenu -ToolKey "$explorerKey\ClearIconCache" -Label 'Clear Icon Cache' -Icon "$iconsDir\Clear-IconCache.ico" -Command "wscript.exe `"$scriptRoot\Launch-ClearIconCache.vbs`""
}

function Add-ToolManager([string]$BaseKey) {
    Add-ToolMenu -ToolKey "$BaseKey\shell\z_ToolManager" -Label 'Tool Manager / Updates' -Icon 'imageres.dll,-109' -Command "wscript.exe `"$scriptRoot\Launch-SystemToolsManager.vbs`"" -CommandFlags '0x00000020'
}

function Add-PathManager([string]$BaseKey, [string]$TargetToken) {
    $windowsKey = "$BaseKey\shell\Windows\shell\PathManager"
    Add-ToolMenu -ToolKey $windowsKey -Label 'Manage Folder PATH...' -Icon "$iconsDir\folder_to_path.ico" -Command "wscript.exe `"$scriptRoot\Launch-SystemToolsMenu.vbs`" `"$TargetToken`""
}

function Add-FirewallRules([string]$BaseKey, [string]$TargetToken) {
    $windowsKey = "$BaseKey\shell\Windows\shell\FirewallRules"
    if ([string]::IsNullOrWhiteSpace($TargetToken)) {
        # Desktop/Background with no specific target: open manager only
        Add-ToolMenu -ToolKey $windowsKey -Label 'Firewall Rules' -Icon "$iconsDir\firewall.ico" -Command "wscript.exe `"$scriptRoot\Launch-FirewallMenu.vbs`""
    } else {
        Add-ToolMenu -ToolKey $windowsKey -Label 'Firewall Rules' -Icon "$iconsDir\firewall.ico" -Command "wscript.exe `"$scriptRoot\Launch-FirewallMenu.vbs`" `"$TargetToken`""
    }
}

function Add-KillAll([string]$BaseKey) {
    $explorerKey = "$BaseKey\shell\Explorer\shell\KillAll"
    Add-ToolMenu -ToolKey $explorerKey -Label 'Kill All Windows' -Icon "$iconsDir\killall.ico" -Command "wscript.exe `"$scriptRoot\KillAll_Silent.vbs`""
}

function Add-SafeMode([string]$BaseKey) {
    $safeModeGroup = "$BaseKey\shell\PowerMenu"
    Add-GroupMenu -BaseKey $BaseKey -KeyName 'PowerMenu' -Label 'Power Options' -Icon 'shell32.dll,-216'
    Add-ToolMenu -ToolKey "$safeModeGroup\shell\BootSafe" -Label 'Boot in Safe Mode' -Icon "$iconsDir\safemode.ico" -Command "wscript.exe `"$scriptRoot\Launch-SafeMode.vbs`""
    Add-ToolMenu -ToolKey "$safeModeGroup\shell\BootNormal" -Label 'Boot in Normal Mode' -Icon 'imageres.dll,-5323' -Command "wscript.exe `"$scriptRoot\Launch-NormalMode.vbs`""
    Add-ToolMenu -ToolKey "$safeModeGroup\shell\Restart" -Label 'Restart' -Icon 'shell32.dll,-239' -Command 'shutdown.exe /r /t 0'
    Add-ToolMenu -ToolKey "$safeModeGroup\shell\Shutdown" -Label 'Shutdown' -Icon 'shell32.dll,-216' -Command 'shutdown.exe /s /t 0'
    Add-ToolMenu -ToolKey "$safeModeGroup\shell\LogOff" -Label 'Log Off' -Icon 'shell32.dll,-325' -Command 'shutdown.exe /l'
}

function Install-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }

    # File context (*)
    Add-RootMenu -BaseKey $fileBaseKey
    Add-WindowsGroup -BaseKey $fileBaseKey
    Add-FirewallRules -BaseKey $fileBaseKey -TargetToken '%1'
    Add-ToolManager -BaseKey $fileBaseKey

    # Folder context (Directory)
    Add-RootMenu -BaseKey $directoryBaseKey
    Add-ExplorerGroup -BaseKey $directoryBaseKey
    Add-ExplorerTools -BaseKey $directoryBaseKey -TargetToken '%1'
    Add-KillAll -BaseKey $directoryBaseKey
    Add-WindowsGroup -BaseKey $directoryBaseKey
    Add-PathManager -BaseKey $directoryBaseKey -TargetToken '%1'
    Add-FirewallRules -BaseKey $directoryBaseKey -TargetToken '%1'
    Add-ToolManager -BaseKey $directoryBaseKey

    # Background context (inside folders)
    Add-RootMenu -BaseKey $backgroundBaseKey
    Add-ExplorerGroup -BaseKey $backgroundBaseKey
    Add-ExplorerTools -BaseKey $backgroundBaseKey -TargetToken '%V'
    Add-KillAll -BaseKey $backgroundBaseKey
    Add-WindowsGroup -BaseKey $backgroundBaseKey
    Add-PathManager -BaseKey $backgroundBaseKey -TargetToken '%V'
    Add-FirewallRules -BaseKey $backgroundBaseKey -TargetToken ''
    Add-ToolManager -BaseKey $backgroundBaseKey

    # Desktop context
    Add-RootMenu -BaseKey $desktopBaseKey -Desktop
    Add-ExplorerGroup -BaseKey $desktopBaseKey
    Add-ExplorerTools -BaseKey $desktopBaseKey -TargetToken '%V'
    Add-KillAll -BaseKey $desktopBaseKey
    Add-WindowsGroup -BaseKey $desktopBaseKey
    Add-FirewallRules -BaseKey $desktopBaseKey -TargetToken ''
    Add-SafeMode -BaseKey $desktopBaseKey
    Add-ToolManager -BaseKey $desktopBaseKey

    Write-Host 'System Tools context menu installed.' -ForegroundColor Green
}

function Uninstall-Menu {
    foreach ($k in $legacyKeys) { Remove-Key -Key $k }
    Write-Host 'System Tools context menu removed.' -ForegroundColor Green
}

function Show-Status {
    $queries = @($fileBaseKey, $directoryBaseKey, $backgroundBaseKey, $desktopBaseKey) | ForEach-Object {
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

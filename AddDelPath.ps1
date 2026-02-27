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

    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$UserRegKey = 'HKCU:\Environment'
$MachineRegKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'

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
        [Parameter(Mandatory)][string]$PathToAdd
    )

    $entries = Get-PathEntries -CurrentScope $CurrentScope
    if (Contains-Path -Entries $entries -Needle $PathToAdd) {
        Write-Host "Already present in $CurrentScope PATH: $PathToAdd" -ForegroundColor Yellow
        return
    }

    $entries.Add($PathToAdd)
    Save-PathEntries -CurrentScope $CurrentScope -Entries $entries
    Write-Host "Added to $CurrentScope PATH: $PathToAdd" -ForegroundColor Green
}

function Remove-PathEntry {
    param(
        [Parameter(Mandatory)][string]$CurrentScope,
        [Parameter(Mandatory)][string]$PathToRemove
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
        Write-Host "Not found in $CurrentScope PATH: $PathToRemove" -ForegroundColor Yellow
        return
    }

    Save-PathEntries -CurrentScope $CurrentScope -Entries $newEntries
    Write-Host "Removed from $CurrentScope PATH: $PathToRemove" -ForegroundColor Green
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
        2000,
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
        [Parameter(Mandatory)][string]$PathToUse
    )

    switch ($RequestedAction) {
        'Status' {
            Show-Status -PathToCheck $PathToUse
        }
        'Add' {
            Assert-AdminForMachine -CurrentScope $RequestedScope
            Add-PathEntry -CurrentScope $RequestedScope -PathToAdd $PathToUse
            Broadcast-EnvironmentChange
            Show-Status -PathToCheck $PathToUse
        }
        'Remove' {
            Assert-AdminForMachine -CurrentScope $RequestedScope
            Remove-PathEntry -CurrentScope $RequestedScope -PathToRemove $PathToUse
            Broadcast-EnvironmentChange
            Show-Status -PathToCheck $PathToUse
        }
        'Toggle' {
            Assert-AdminForMachine -CurrentScope $RequestedScope
            $entries = Get-PathEntries -CurrentScope $RequestedScope
            if (Contains-Path -Entries $entries -Needle $PathToUse) {
                Remove-PathEntry -CurrentScope $RequestedScope -PathToRemove $PathToUse
            }
            else {
                Add-PathEntry -CurrentScope $RequestedScope -PathToAdd $PathToUse
            }
            Broadcast-EnvironmentChange
            Show-Status -PathToCheck $PathToUse
        }
    }
}

function Ensure-MenuElevation {
    param([Parameter(Mandatory)][string]$PathToUse)

    if (Test-IsAdministrator) { return $true }

    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCmd) { $pwshCmd.Source } else { Join-Path $PSHOME 'pwsh.exe' }

    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Action', 'Menu',
        '-TargetPath', $PathToUse,
        '-NoPause'
    )

    Write-Host 'Requesting admin elevation for full PATH control...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath $pwshExe -Verb RunAs -ArgumentList $argList | Out-Null
        return $false
    }
    catch {
        Write-Host 'Elevation canceled. Continuing in standard mode.' -ForegroundColor Yellow
        return $true
    }
}

function Open-EnvSnapshotPane {
    param([Parameter(Mandatory)][string]$PathToUse)

    # WT supports split panes; outside WT we show inline as fallback.
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
        '-NoExit',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Action', 'EnvView',
        '-TargetPath', $PathToUse
    )

    Start-Process -FilePath 'wt.exe' -ArgumentList $argList | Out-Null
}

function Show-Menu {
    param([Parameter(Mandatory)][string]$PathToUse)

    while ($true) {
        Clear-Host
        $status = Get-PathStatus -PathToCheck $PathToUse

        Write-Host ''
        Write-Separator -Text '⚙️  System Tools - PATH Manager' -Color DarkCyan
        Write-Host "📁 Target Folder : $PathToUse" -ForegroundColor Cyan
        Write-Host ('🛡  Session Mode  : ' + ($(if (Test-IsAdministrator) { 'Admin' } else { 'Standard User' }))) -ForegroundColor Cyan
        Write-Host ('👤 User PATH     : ' + ($(if ($status.InUser) { '✅ YES' } else { '❌ NO' }))) -ForegroundColor Yellow
        Write-Host ('🖥  Machine PATH  : ' + ($(if ($status.InMachine) { '✅ YES' } else { '❌ NO' }))) -ForegroundColor Yellow
        Write-Host ''
        Write-Host '[1] 🔁 Toggle User PATH' -ForegroundColor Green
        Write-Host '[2] 🔁 Toggle Machine PATH (Admin)' -ForegroundColor Magenta
        Write-Host '[3] 🔍 Show PATH status' -ForegroundColor Cyan
        Write-Host '[4] 🌿 Show full ENV snapshot (split pane in WT)' -ForegroundColor Cyan
        Write-Host '[5] 💾 Export ENV snapshot (TXT + MD)' -ForegroundColor Cyan
        Write-Host '[0] Exit'
        Write-Host ''

        $choice = Read-Host 'Choose option'
        if ($choice -eq '0') { break }

        try {
            switch ($choice) {
                '1' { Invoke-PathAction -RequestedAction 'Toggle' -RequestedScope 'User' -PathToUse $PathToUse }
                '2' {
                    if (Test-IsAdministrator) {
                        Invoke-PathAction -RequestedAction 'Toggle' -RequestedScope 'Machine' -PathToUse $PathToUse
                    }
                    else {
                        Invoke-ElevatedMachineAction -RequestedAction 'Toggle' -PathToUse $PathToUse
                    }
                }
                '3' { Show-Status -PathToCheck $PathToUse }
                '4' { Open-EnvSnapshotPane -PathToUse $PathToUse }
                '5' {
                    $desktop = [Environment]::GetFolderPath('Desktop')
                    $exportDir = Read-Host "Export directory (blank = $desktop)"
                    if ([string]::IsNullOrWhiteSpace($exportDir)) { $exportDir = $desktop }
                    Export-EnvironmentSnapshot -Directory $exportDir -Format 'Both'
                }
                default { Write-Host 'Invalid option.' -ForegroundColor Yellow }
            }
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
        }

        Write-Host ''
        Read-Host 'Press Enter to continue'
    }
}

$TargetPath = [System.IO.Path]::GetFullPath($TargetPath)

switch ($Action) {
    'Menu' {
        if (Ensure-MenuElevation -PathToUse $TargetPath) {
            Show-Menu -PathToUse $TargetPath
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
    }
    'EnvExport' {
        Export-EnvironmentSnapshot -Directory $OutputDirectory -Format $ExportFormat
    }
}

if (($Action -ne 'Menu') -and (-not $NoPause)) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

#requires -version 7.0
[CmdletBinding()]
param(
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-NativeShellRefreshType {
    if ('NativeShellRefresh' -as [type]) { return }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeShellRefresh
{
    [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
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

function Invoke-ShellRefresh {
    Ensure-NativeShellRefreshType

    $SHCNE_ASSOCCHANGED = 0x08000000
    $SHCNF_IDLIST = 0x0000
    [NativeShellRefresh]::SHChangeNotify($SHCNE_ASSOCCHANGED, $SHCNF_IDLIST, [IntPtr]::Zero, [IntPtr]::Zero)

    $HWND_BROADCAST = [IntPtr]0xFFFF
    $WM_SETTINGCHANGE = 0x001A
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [IntPtr]::Zero

    [void][NativeShellRefresh]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [IntPtr]::Zero,
        'ShellState',
        $SMTO_ABORTIFHUNG,
        2000,
        [ref]$result
    )

    [void][NativeShellRefresh]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [IntPtr]::Zero,
        'Environment',
        $SMTO_ABORTIFHUNG,
        2000,
        [ref]$result
    )
}

Write-Host ''
Write-Host 'Refreshing Windows shell...' -ForegroundColor Yellow
Invoke-ShellRefresh
Write-Host 'Shell refresh signal sent.' -ForegroundColor Green

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}

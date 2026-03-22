#requires -version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Ensure Admin ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $pwsh = (Get-Command pwsh.exe).Source
    Start-Process $pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# --- Load Blueprint ---
$blueprintPath = 'D:\Users\joty79\.gemini\templates\PS_UI_Blueprint.psm1'
if (Test-Path $blueprintPath) {
    Import-Module $blueprintPath -Force
} else {
    Write-Warning "UI Blueprint not found at $blueprintPath"
    Start-Sleep 2
}

# --- Menu Loop ---
$options = @(
    "🟢 Enable PSRemoting (Force & Skip Public Network Check)",
    "🛑 Disable PSRemoting (Stop Service, Disable Startup, Close Firewall)",
    "➕ Add TrustedHost (Trust a new PC by Name or IP)",
    "🧹 Clear TrustedHosts (Revert trust changes)",
    "🚪 Exit"
)

while ($true) {
    $headerScript = {
        Write-UiBanner -Title "WinRM / PSRemoting Manager" -Subtitle "Safely toggle remote connections"
        
        # Check current status
        $svc = Get-Service WinRM -ErrorAction SilentlyContinue
        if ($svc) {
            $statusMsg = if ($svc.Status -eq 'Running') { "$($_C.OK)$($svc.Status)$($_C.Reset)" } else { "$($_C.Fail)$($svc.Status)$($_C.Reset)" }
            $startMsg  = if ($svc.StartType -eq 'Automatic') { "$($_C.Warn)$($svc.StartType)$($_C.Reset)" } else { "$($_C.Dim)$($svc.StartType)$($_C.Reset)" }
            
            # Read TrustedHosts
            try { 
                $th = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
            } catch { 
                $th = '' 
            }
            $thMsg = if (-not $th) { "$($_C.Dim)None (Empty)$($_C.Reset)" } else { "$($_C.Info)$th$($_C.Reset)" }

            Write-Host ""
            Write-Host "  $($_C.H2)Service Status : $statusMsg"
            Write-Host "  $($_C.H2)Startup Type   : $startMsg"
            Write-Host "  $($_C.H2)TrustedHosts   : $thMsg"
            Write-Host ""
        } else {
            Write-Host "  $($_C.Fail)WinRM service not found!$($_C.Reset)"
        }
    }

    $choice = Invoke-ArrowMenu -Items $options -Title "🛡️ Select Action" -HeaderBlock $headerScript
    
    if (-not $choice) { exit }

    Clear-Host
    if ($choice -match 'Enable') {
        Write-UiSection "Enabling PSRemoting..." -Icon '🟢'
        try {
            Enable-PSRemoting -Force -SkipNetworkProfileCheck
            Write-Host "`n$($_C.OK)✅ PSRemoting enabled successfully.$($_C.Reset)"
        } catch {
            Write-Host "`n$($_C.Fail)❌ Error: $_$($_C.Reset)"
        }
    }
    elseif ($choice -match 'Disable') {
        Write-UiSection "Disabling PSRemoting..." -Icon '🛑'
        try {
            Write-Host "Stopping WinRM service..." -ForegroundColor DarkGray
            Stop-Service WinRM -ErrorAction SilentlyContinue
            Write-Host "Setting WinRM startup to Disabled..." -ForegroundColor DarkGray
            Set-Service WinRM -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "Disabling WinRM Firewall Rules..." -ForegroundColor DarkGray
            Disable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue
            Write-Host "`n$($_C.OK)✅ PSRemoting disabled successfully.$($_C.Reset)"
        } catch {
            Write-Host "`n$($_C.Fail)❌ Error: $_$($_C.Reset)"
        }
    }
    elseif ($choice -match 'Add TrustedHost') {
        Write-UiSection "Add TrustedHost..." -Icon '➕'
        Write-Host "Current: $th" -ForegroundColor Gray
        $newHost = Read-Host "Type Hostname or IP (use * for all or leave blank to cancel)"
        if ($newHost) {
            try {
                $merged = if ($th) { "$th,$newHost" } else { $newHost }
                $out = & winrm set winrm/config/client "@`{TrustedHosts=`"$merged`"`}" 2>&1
                if ($LASTEXITCODE -ne 0) { throw $out }
                Write-Host "`n$($_C.OK)✅ Added to TrustedHosts.$($_C.Reset)"
            } catch {
                Write-Host "`n$($_C.Fail)❌ Error: $_$($_C.Reset)"
            }
        } else {
            Write-Host "`n$($_C.Warn)Canceled.$($_C.Reset)"
        }
    }
    elseif ($choice -match 'Clear TrustedHosts') {
        Write-UiSection "Clearing TrustedHosts..." -Icon '🧹'
        try {
            Clear-Item WSMan:\localhost\Client\TrustedHosts -Force -ErrorAction SilentlyContinue
            Write-Host "`n$($_C.OK)✅ TrustedHosts cleared successfully.$($_C.Reset)"
        } catch {
            Write-Host "`n$($_C.Fail)❌ Error: $_$($_C.Reset)"
        }
    }
    elseif ($choice -match 'Exit') {
        exit
    }

    Write-Host ""
    Read-Host "$($_C.Dim)Press Enter to return to menu...$($_C.Reset)"
}

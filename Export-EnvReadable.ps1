#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ComputerName = 'localhost',
    [pscredential]$Credential
)

$isLocal = ($ComputerName -eq 'localhost' -or $ComputerName -eq $env:COMPUTERNAME -or $ComputerName -eq '127.0.0.1')

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

$machineLabel = if ($isLocal) { $env:COMPUTERNAME } else { $ComputerName }

$desktopPath = [Environment]::GetFolderPath('Desktop')
$mdFile      = Join-Path $desktopPath "Env-Readable-$machineLabel-$stamp.md"

if ($isLocal) {
    $systemVars = [System.Environment]::GetEnvironmentVariables('Machine')
    $userVars   = [System.Environment]::GetEnvironmentVariables('User')
} else {
    Write-Host "🌍 Connecting to $ComputerName via PSRemoting..." -ForegroundColor Cyan
    $invokeArgs = @{
        ComputerName = $ComputerName
        ScriptBlock = {
            return @{
                Machine = [System.Environment]::GetEnvironmentVariables('Machine')
                User    = [System.Environment]::GetEnvironmentVariables('User')
            }
        }
        ErrorAction = 'Stop'
    }
    if ($Credential) { $invokeArgs.Credential = $Credential }

    try {
        $result = Invoke-Command @invokeArgs
        $systemVars = $result.Machine
        $userVars   = $result.User
        Write-Host "✅ Environment fetched successfully from $ComputerName." -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to fetch environment from $ComputerName" -ForegroundColor Red
        Write-Host $_ -ForegroundColor DarkRed
        exit
    }
}

# ---------- MARKDOWN ----------
$md = @()

$md += '# 🌱 Environment Variables Snapshot (' + $machineLabel + ')'
$md += ''
$md += '> Read-only documentation of Windows environment variables for ' + $machineLabel
$md += ''
$md += '**Created:** `' + $timestamp + '`'
$md += ''
$md += '---'
$md += ''

# ===== SYSTEM VARIABLES =====
$md += '## 🖥 System Variables'
$md += ''
$md += '| Variable | Value |'
$md += '|---------|-------|'

foreach ($key in ($systemVars.Keys | Sort-Object)) {
    if ($key -ne 'Path') {
        $value = [string]$systemVars[$key] -replace '\|', '\|'
        $md += '| ' + $key + ' | `' + $value + '` |'
    }
}

$md += ''
$md += '### 📂 System PATH'
$md += ''
foreach ($p in ($systemVars['Path'] -split ';')) {
    if ($p.Trim()) {
        $md += '- `' + $p.Trim() + '`'
    }
}

$md += ''
$md += '---'
$md += ''

# ===== USER VARIABLES =====
$md += '## 👤 User Variables'
$md += ''
$md += '| Variable | Value |'
$md += '|---------|-------|'

foreach ($key in ($userVars.Keys | Sort-Object)) {
    if ($key -ne 'Path') {
        $value = [string]$userVars[$key] -replace '\|', '\|'
        $md += '| ' + $key + ' | `' + $value + '` |'
    }
}

$md += ''
$md += '### 📂 User PATH'
$md += ''
foreach ($p in ($userVars['Path'] -split ';')) {
    if ($p.Trim()) {
        $md += '- `' + $p.Trim() + '`'
    }
}

$md += ''
$md += '---'
$md += ''
$md += '📝 _Generated automatically. Safe for backup, diff and documentation._'

$md | Out-File -Encoding UTF8BOM $mdFile

Write-Host "`n🎉 Export complete!" -ForegroundColor Cyan
Write-Host " 📔 MD  : $mdFile" -ForegroundColor Gray
Write-Host ''

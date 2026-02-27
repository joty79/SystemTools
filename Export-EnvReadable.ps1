$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

$txtFile = 'Env-Readable-' + $stamp + '.txt'
$mdFile  = 'Env-Readable-' + $stamp + '.md'

$systemVars = [System.Environment]::GetEnvironmentVariables('Machine')
$userVars   = [System.Environment]::GetEnvironmentVariables('User')

# ---------- TXT ----------
$txt = @()
$txt += 'Environment Variables Snapshot'
$txt += 'Created: ' + $timestamp
$txt += ''

$txt += '=== SYSTEM VARIABLES ==='
foreach ($key in ($systemVars.Keys | Sort-Object)) {
    if ($key -ne 'Path') {
        $txt += $key + '=' + $systemVars[$key]
    }
}

$txt += ''
$txt += '--- SYSTEM PATH ---'
foreach ($p in ($systemVars['Path'] -split ';')) {
    if ($p.Trim()) {
        $txt += '  ' + $p
    }
}

$txt += ''
$txt += '=== USER VARIABLES ==='
foreach ($key in ($userVars.Keys | Sort-Object)) {
    if ($key -ne 'Path') {
        $txt += $key + '=' + $userVars[$key]
    }
}

$txt += ''
$txt += '--- USER PATH ---'
foreach ($p in ($userVars['Path'] -split ';')) {
    if ($p.Trim()) {
        $txt += '  ' + $p
    }
}

$txt | Out-File -Encoding UTF8 $txtFile


# ---------- MARKDOWN ----------
$md = @()

$md += '# 🌱 Environment Variables Snapshot'
$md += ''
$md += '> Read-only documentation of Windows environment variables'
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
        $value = ($systemVars[$key] -replace '\|', '\|')
        $md += '| ' + $key + ' | `' + $value + '` |'
    }
}

$md += ''
$md += '### 📂 System PATH'
$md += ''
foreach ($p in ($systemVars['Path'] -split ';')) {
    if ($p.Trim()) {
        $md += '- `' + $p + '`'
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
        $value = ($userVars[$key] -replace '\|', '\|')
        $md += '| ' + $key + ' | `' + $value + '` |'
    }
}

$md += ''
$md += '### 📂 User PATH'
$md += ''
foreach ($p in ($userVars['Path'] -split ';')) {
    if ($p.Trim()) {
        $md += '- `' + $p + '`'
    }
}

$md += ''
$md += '---'
$md += ''
$md += '📝 _Generated automatically. Safe for backup, diff and documentation._'

$md | Out-File -Encoding UTF8BOM $mdFile


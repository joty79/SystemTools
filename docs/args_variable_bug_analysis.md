# 🔵 The `$args` Silent Killer — Post-Mortem Analysis

> [!CAUTION]
> Αυτό το bug **σπάει σιωπηλά** ολόκληρο το script χωρίς κανένα error message. Το PowerShell δεν πετάει exception, δεν δίνει warning — απλά **δεν κάνει τίποτα**.

---

## 🔵 Σύνοψη

| | |
|---|---|
| **Αρχείο** | [Install-SystemToolsMenu.ps1](file:///d:/Users/joty79/scripts/SystemTools/Install-SystemToolsMenu.ps1) |
| **Function** | `Add-Value` (γραμμή 51) |
| **Root Cause** | Χρήση `$args` ως custom variable μέσα σε function |
| **Αποτέλεσμα** | Κανένα registry key δεν γράφτηκε ποτέ — σιωπηλή αποτυχία |
| **Ημερομηνία** | 2026-03-02 |
| **Δευτερεύον bug** | Κενό `SubCommands` γραφόταν ως literal `""` αντί πραγματικά κενό string |

---

## 🔵 Τι Συνέβη

Το `Install-SystemToolsMenu.ps1` (`-Action Install`) **δεν έγραφε τίποτα** στο registry. Κανένα parent menu, κανένα submenu, κανένα icon, κανένα command. Σαν να μην έτρεξε ποτέ.

Αντίθετα, το `SystemToolsMenu.reg` (double-click import) δούλευε τέλεια.

---

## 🔵 Ο Ένοχος — `$args` Automatic Variable

### 🔸 Τι είναι το `$args`

Στο PowerShell, **`$args` είναι automatic variable** — μια ειδική μεταβλητή που διαχειρίζεται αυτόματα το runtime. Περιέχει τα unbound positional arguments που περνιούνται σε μια function ή script.

```powershell
function Test-Something {
    # Αυτό δεν δηλώνεται στο param() block,
    # αλλά μπορείς να καλέσεις: Test-Something "hello" "world"
    # και $args θα περιέχει @("hello", "world")
    Write-Host $args[0]  # hello
    Write-Host $args[1]  # world
}
```

### 🔸 Η Παγίδα

Όταν **γράψεις** `$args = @(...)` μέσα σε μια function, **ΔΕΝ δημιουργείς νέα μεταβλητή**. Το PowerShell:

1. Δέχεται το assignment **χωρίς error**
2. Αλλά στην πραγματικότητα **δεν διατηρεί** την τιμή σου — ή την αντικαθιστά αμέσως
3. Όταν αργότερα διαβάσεις `$args`, παίρνεις τα **automatic arguments** (πιθανώς κενό array)

> [!WARNING]
> Κανένα error. Κανένα warning. Κανένα σημάδι ότι κάτι πήγε στραβά. Αυτό είναι που το κάνει τόσο επικίνδυνο.

---

## 🔵 Ο Buggy Κώδικας

```powershell
function Add-Value([string]$Key, [string]$Name, [string]$Type, [AllowEmptyString()][string]$Data) {
    $value = if ($Type -eq 'REG_DWORD') { ... } else { if ($Data -eq '') { '""' } else { $Data } }

    # ⛔ BUG: $args είναι automatic variable!
    $args = @('add', $Key)
    if ($Name -eq '(default)') { $args += '/ve' } else { $args += @('/v', $Name) }
    $args += @('/t', $Type, '/d', $value, '/f')

    # ⛔ Αυτό ΔΕΝ περνάει τα σωστά arguments
    Reg-Run -RegArgs $args | Out-Null
}
```

### 🔸 Τι Συμβαίνει Βήμα-Βήμα

````carousel
```
ΒΗΜΑ 1: Η function καλείται
─────────────────────────────
Add-Value -Key 'HKCU\...\SystemTools' -Name 'MUIVerb' -Type 'REG_SZ' -Data 'System Tools'

→ Τα named parameters δεσμεύονται κανονικά ($Key, $Name, $Type, $Data)
→ $args automatic = @()  (κενό, γιατί δεν υπάρχουν unbound args)
```
<!-- slide -->
```
ΒΗΜΑ 2: Assignment σε $args
─────────────────────────────
$args = @('add', 'HKCU\...\SystemTools')

→ Φαινομενικά δουλεύει...
→ Αλλά το PS runtime μπορεί να αντικαταστήσει/αγνοήσει
   αυτήν την τιμή ανά πάσα στιγμή
```
<!-- slide -->
```
ΒΗΜΑ 3: Χρήση $args στο Reg-Run
─────────────────────────────
Reg-Run -RegArgs $args

→ $args = @()  ← κενό array!
→ reg.exe τρέχει ΧΩΡΙΣ arguments
→ reg.exe χωρίς arguments = δεν κάνει τίποτα ή πετάει
   usage help στο stderr
→ Η Reg-Run function τρώει το error γιατί χρησιμοποιεί 2>&1
```
<!-- slide -->
```
ΒΗΜΑ 4: Αποτέλεσμα
─────────────────────────────
→ Κανένα registry key δεν δημιουργείται
→ Κανένα error δεν εμφανίζεται στον χρήστη
→ Write-Host 'System Tools folder context menu installed.' ← ΨΕΜΑ
→ Ο χρήστης βλέπει "installed" αλλά δεν υπάρχει τίποτα
```
````

---

## 🔵 Δευτερεύον Bug — Κενό `SubCommands` Data

### 🔸 Τι Χρειάζεται

Για nested shell cascade, το `SubCommands` registry value πρέπει να είναι **πραγματικά κενό string** (`""`στο `.reg` format = empty data):

```reg
"SubCommands"=""    ← αυτό σημαίνει: data = (κενό string)
```

### 🔸 Τι Έγραφε ο Κώδικας

```powershell
# Στη γραμμή 52 (πριν το fix):
$value = ... else { if ($Data -eq '') { '""' } else { $Data } }
#                                         ^^^^
#                    Αυτό γράφει LITERAL δύο quote characters!
```

🔸 Δηλαδή στο registry catalog γραφόταν:

| Τι ήθελα | Τι γραφόταν |
|---|---|
| `SubCommands` = *(κενό)* | `SubCommands` = `""` (δύο quote chars) |

🔸 Τα Windows δεν αναγνωρίζουν `""` ως κενό — βλέπουν δύο quote characters ως data, και δεν ενεργοποιούν το nested shell cascade.

---

## 🔵 Το Fix

### 🔸 Fix 1: Μετονομασία `$args` → `$regArgs`

```diff
 function Add-Value([string]$Key, [string]$Name, [string]$Type, [AllowEmptyString()][string]$Data) {
-    $value = if ($Type -eq 'REG_DWORD') { ... } else { if ($Data -eq '') { '""' } else { $Data } }
-    $args = @('add', $Key)
-    if ($Name -eq '(default)') { $args += '/ve' } else { $args += @('/v', $Name) }
-    $args += @('/t', $Type, '/d', $value, '/f')
-    Reg-Run -RegArgs $args | Out-Null
+    $value = if ($Type -eq 'REG_DWORD') { ... } else { $Data }
+    $regArgs = @('add', $Key)
+    if ($Name -eq '(default)') { $regArgs += '/ve' } else { $regArgs += @('/v', $Name) }
+    $regArgs += @('/t', $Type, '/d', $value, '/f')
+    Reg-Run -RegArgs $regArgs | Out-Null
 }
```

### 🔸 Fix 2: Icons Sync

🔸 Τα submenu icons χρησιμοποιούσαν generic `imageres.dll` αντί τα custom `.ico` αρχεία:

```diff
+$iconsDir = Join-Path $scriptRoot '.assets\icons'

-    Add-Value -Key $statusKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-5302'
+    Add-Value -Key $statusKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\folder_to_path.ico"

-    Add-Value -Key $restartExplorerKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-5358'
+    Add-Value -Key $restartExplorerKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\restart_explorer.ico"

-    Add-Value -Key $refreshShellKey -Name 'Icon' -Type 'REG_SZ' -Data 'imageres.dll,-5308'
+    Add-Value -Key $refreshShellKey -Name 'Icon' -Type 'REG_SZ' -Data "$iconsDir\refresh_shell.ico"
```

---

## 🔵 Πλήρης Λίστα Automatic Variables — ΠΟΤΕ Μη Τις Χρησιμοποιείς

> [!IMPORTANT]
> Αυτές οι μεταβλητές είναι **reserved** από το PowerShell runtime. Αν τις χρησιμοποιήσεις ως custom variable names μέσα σε function/script, θα πάρεις **σιωπηλά λάθος αποτελέσματα**.

| Variable | Τι Περιέχει |
|---|---|
| **`$args`** | Unbound positional arguments |
| `$_` / `$PSItem` | Current pipeline object |
| `$input` | Pipeline input enumerator |
| `$this` | Current object (σε script properties/methods) |
| `$MyInvocation` | Invocation info |
| `$PSCmdlet` | Cmdlet object (σε advanced functions) |
| `$PSBoundParameters` | Explicitly bound parameters |
| `$Error` | Error collection |
| `$?` | Last command success status |
| `$LASTEXITCODE` | Last native command exit code |
| `$Matches` | Regex match results |
| `$foreach` | ForEach loop enumerator |
| `$switch` | Switch loop enumerator |

> [!TIP]
> **Κανόνας:** Πάντα χρησιμοποίησε descriptive names για arrays/collections μέσα σε functions:
> - `$regArgs` αντί `$args`
> - `$params` αντί `$args`
> - `$cmdArgs` αντί `$args`
> - `$inputData` αντί `$input`

---

## 🔵 Γιατί Δεν Πιάστηκε Νωρίτερα

1. **Set-StrictMode δεν το πιάνει** — Δεν είναι undeclared variable, είναι automatic
2. **Parser Validation δεν το πιάνει** — Δεν είναι syntax error
3. **PSScriptAnalyzer δεν προειδοποιεί πάντα** — Εξαρτάται από rule set
4. **Κανένα runtime error** — Η εντολή `reg.exe` τρέχει (με λάθος args), αλλά η `Reg-Run` wrapper function masking τα errors
5. **Η function εμφανίζει "installed"** — Ψευδής επιτυχία, γιατί `Write-Host` τρέχει πάντα

> [!WARNING]
> Ο **μόνος** τρόπος να πιάσεις αυτό το bug είναι:
> 1. Code review (γνωρίζοντας τον κανόνα)
> 2. Manual registry verification μετά το install
> 3. Φυσική δοκιμή right-click → μενού δεν εμφανίζεται

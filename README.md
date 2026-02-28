<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-PowerShell%207+-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 7+">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
</p>

<h1 align="center">🛠️ System Tools</h1>

<p align="center">
  <b>A collection of native Windows context-menu utilities built with PowerShell 7</b><br>
  <sub>Right-click any folder → <i>System Tools</i> → done.</sub>
</p>

---

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🔁 | **[Restart Explorer](#-restart-explorer)** | Kill & cleanly restart `explorer.exe` — reopens target folder without zombie processes |
| 📂 | **[PATH Manager](#-path-manager)** | Interactive toggle of any folder in/out of User or Machine `PATH` with live ENV snapshot |
| 🔄 | **[Refresh Shell](#-refresh-shell)** | Broadcast shell & environment refresh signals — no Explorer restart needed |

---

## 🔁 Restart Explorer

> Cleanly restart the Windows shell and automatically reopen the folder you were in.

### The Problem

Restarting Explorer from scripts usually causes one of these issues:
- `Start-Process explorer.exe` → creates a **zombie** second `explorer.exe` 🧟
- Opens an unwanted **Quick Access** window
- Requires manual folder navigation after restart

### The Solution

System Tools uses a **zero-zombie technique**:

```
Stop Explorer → Windows auto-restarts shell via winlogon
             → Wait for shell stabilization
             → Reopen folder via Shell.Application COM (reuses existing process)
```

The COM method asks the **already-running** shell to open a folder window, instead of spawning a brand-new `explorer.exe` process.

### Usage

**From context menu** — right-click any folder → *System Tools* → *Restart Explorer*

**From terminal:**

```powershell
# Clean restart only (no folder reopen)
.\RestartExplorer.ps1

# Restart + reopen target folder (COM-based, no zombie)
.\RestartExplorer.ps1 -TargetPath "C:\MyFolder" -ReopenFolder
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TargetPath` | `string` | Current directory | Folder to reopen after restart |
| `-ReopenFolder` | `switch` | Off | Enable COM-based folder reopen |
| `-NoPause` | `switch` | Off | Skip `Press Enter to close` prompt |

---

## 📂 PATH Manager

> Add, remove, or toggle any folder in the Windows `PATH` — with one right-click.

### Features

| Feature | Details |
|---------|---------|
| 🔁 **Toggle User PATH** | One-click add/remove of any folder |
| 🔁 **Toggle Machine PATH** | Auto-elevates to Admin via UAC |
| 🌿 **ENV Snapshot** | Live split-pane view of all environment variables in Windows Terminal |
| 💾 **Export** | Save full environment snapshot as Markdown documentation |
| 📡 **Broadcast** | Sends `WM_SETTINGCHANGE` so all apps pick up PATH changes instantly |

### Usage

**From context menu** — right-click any folder → *System Tools* → *Manage Folder PATH...*

Opens an interactive menu in Windows Terminal:

```
⚙️  System Tools - PATH Manager
────────────────────────────────────────────────────────
📁 Target Folder : D:\Users\joty79\scripts\SystemTools
🛡  Session Mode  : Admin
👤 User PATH     : ✅ YES
🖥  Machine PATH  : ❌ NO

[1] 🔁 Toggle User PATH
[2] 🔁 Toggle Machine PATH (Admin)
[3] 🌿 Toggle full ENV snapshot (split pane in WT)
[4] 💾 Export ENV snapshot (MD)
[0] Exit
```

**Direct CLI actions:**

```powershell
# Check if a folder is in PATH
.\AddDelPath.ps1 -Action Status -TargetPath "C:\MyFolder"

# Toggle folder in User PATH
.\AddDelPath.ps1 -Action Toggle -Scope User -TargetPath "C:\MyFolder"

# Toggle folder in Machine PATH (requires admin)
.\AddDelPath.ps1 -Action Toggle -Scope Machine -TargetPath "C:\MyFolder"

# Export full ENV snapshot to Markdown
.\AddDelPath.ps1 -Action EnvExport -ExportFormat Md
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Action` | `string` | `Menu` | `Menu` · `Status` · `Add` · `Remove` · `Toggle` · `EnvView` · `EnvExport` |
| `-Scope` | `string` | `User` | `User` or `Machine` |
| `-TargetPath` | `string` | Current directory | Target folder path |
| `-ExportFormat` | `string` | `Both` | `Txt` · `Md` · `Both` |
| `-NoPause` | `switch` | Off | Skip confirmation prompts |

---

## 🔄 Refresh Shell

> Notify Windows to refresh shell state and environment variables — without restarting Explorer.

### The Problem

After changes to the registry, context menus, file associations, or environment variables:
- New context menu entries don't appear until you restart Explorer
- Apps don't see updated PATH or env variables until restarted
- Full Explorer restart is overkill for a simple refresh

### The Solution

Refresh Shell sends **two native Windows broadcast signals** to force all apps to re-read their state:

```
SHChangeNotify(SHCNE_ASSOCCHANGED)  → Refreshes icons, associations, context menus
WM_SETTINGCHANGE "ShellState"       → Refreshes shell UI state
WM_SETTINGCHANGE "Environment"      → Refreshes environment variables (PATH, etc.)
```

No processes killed. No windows closed. Just signals.

### When To Use

| Scenario | Use Refresh Shell? |
|----------|-------------------|
| Added/removed a context menu entry | ✅ Yes |
| Changed a file association | ✅ Yes |
| Changed icon resources in registry | ✅ Yes |
| Installed a new shell extension | ✅ Yes |
| Changed PATH manually (outside AddDelPath) | ✅ Yes |
| Need full Explorer restart | ❌ Use Restart Explorer |

### Usage

**From context menu** — right-click any folder → *System Tools* → *Refresh Shell*

**From terminal:**

```powershell
# Refresh shell and environment
.\RefreshShell.ps1

# Silent (no pause)
.\RefreshShell.ps1 -NoPause
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-NoPause` | `switch` | Off | Skip `Press Enter to close` prompt |

---

## 📦 Installation

### Quick Setup (Registry)

```powershell
# Install the context menu
pwsh -NoProfile -File .\Install-SystemToolsMenu.ps1 -Action Install

# Check installation status
pwsh -NoProfile -File .\Install-SystemToolsMenu.ps1 -Action Status

# Uninstall
pwsh -NoProfile -File .\Install-SystemToolsMenu.ps1 -Action Uninstall
```

### Manual Setup (`.reg` file)

Double-click `SystemToolsMenu.reg` to import directly.

### Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 / 11 |
| **Shell** | PowerShell 7+ (`pwsh.exe`) |
| **Terminal** | Windows Terminal (recommended for split-pane ENV snapshot) |
| **Admin** | Required only for Machine PATH changes |

---

## 📁 Project Structure

```
SystemTools/
├── AddDelPath.ps1                # PATH Manager — interactive menu + CLI
├── RestartExplorer.ps1           # Restart Explorer — clean shell restart
├── RefreshShell.ps1              # Refresh Shell — broadcast refresh signals
├── Install-SystemToolsMenu.ps1   # Registry installer/uninstaller
├── SystemToolsMenu.reg           # Manual registry import (alternative)
├── Launch-SystemToolsMenu.vbs    # VBS launcher (no console flash)
├── Launch-RestartExplorer.vbs    # VBS launcher (no console flash)
├── Launch-RefreshShell.vbs       # VBS launcher (no console flash)
├── PROJECT_RULES.md              # Decision log & guardrails
└── README.md                     # You are here
```

---

## 🧠 Technical Notes

<details>
<summary><b>Why VBS launchers?</b></summary>

Context-menu entries that call `pwsh.exe` directly cause a brief console window flash before Windows Terminal opens. The `.vbs` launchers use `WScript.Shell.Run` with window style `0` (hidden) to eliminate this flash entirely.

</details>

<details>
<summary><b>Why COM instead of Start-Process for Explorer restart?</b></summary>

When Explorer is killed, Windows **automatically** restarts the shell process via `winlogon`. Any `Start-Process explorer.exe` creates a **second** `explorer.exe` — the "zombie". Using `Shell.Application` COM to reopen a folder reuses the existing shell process instead of spawning a new one.

</details>

<details>
<summary><b>How does PATH broadcast work?</b></summary>

After modifying PATH, the script calls `SendMessageTimeout` with `WM_SETTINGCHANGE` to notify all running applications that environment variables have changed. This means you don't need to restart apps to pick up PATH changes.

</details>

<details>
<summary><b>What's the difference between Refresh Shell and Restart Explorer?</b></summary>

**Refresh Shell** sends lightweight notification signals (`SHChangeNotify` + `WM_SETTINGCHANGE`) — no processes are killed or restarted. It's enough for context menu, association, and environment changes. **Restart Explorer** kills and restarts the entire `explorer.exe` process — needed when the shell itself is frozen or misbehaving.

</details>

---

<p align="center">
  <sub>Built with ☕ and PowerShell · No external dependencies · No admin needed (except Machine PATH)</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-PowerShell%207+-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 7+">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
</p>

<h1 align="center">🛠️ System Tools</h1>

<p align="center">
  <b>A collection of native Windows context-menu utilities built with PowerShell 7</b><br>
  <sub>Right-click any folder → <i>System Tools</i> → <i>Explorer</i> or <i>Windows</i>.</sub>
</p>

---

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🔁 | **[Restart Explorer](#-restart-explorer)** | Kill & cleanly restart `explorer.exe` — reopens target folder without zombie processes |
| 🧭 | **[Tool Manager / Updates](#-tool-manager--updates)** | One menu for monitoring, inspecting, repairing, and updating managed Windows tools |
| 🛡️ | **[PSRemoting Manager](#️-psremoting-manager)** | Interactive UI to safely manage WinRM and TrustedHosts |
| 📂 | **[PATH Manager](#-path-manager)** | Interactive toggle of any folder in/out of User or Machine `PATH` with live ENV snapshot |
| 🔄 | **[Refresh Shell](#-refresh-shell)** | Broadcast shell & environment refresh signals — no Explorer restart needed |
| 🧹 | **[Clear Icon Cache](#-clear-icon-cache)** | Rebuild icon, thumbnail, and UWP AppIconCache — fixes broken Start Menu icons |
| 🧩 | **Shared Windows Tools** | Firewall rules, PATH Manager, cleanup, ownership, lock-checking, and app management entries |

---

## 🧭 Context Menu Layout

`SystemTools` owns the shared parent menu and the two category folders. Companion repos install their own child entries under those categories, so small tools can stay separate while the right-click menu still feels like one toolbox.

```text
System Tools
├── Explorer
│   ├── Refresh Shell
│   ├── Restart Explorer
│   └── Clear Icon Cache
├── Windows
│   ├── Firewall Rules
│   ├── Manage Folder PATH...
│   ├── Windows Update Cleanup
│   ├── Take Ownership
│   ├── Who is using this?
│   └── WinAppManager
└── Tool Manager / Updates

Safe Mode Options
├── Boot in Normal Mode
└── Boot in Safe Mode

ContextLens
├── OCR image to TXT
├── OCR clipboard to TXT
├── Save clipboard image
└── Open ContextLens Manager
```

On single-file targets such as `.md`, `System Tools > Windows` is intentionally limited to file-safe tools: `Take Ownership` and `Who is using this?`.
Safe Mode is intentionally a separate top-level context menu while `SystemTools` stays under the Windows 10 static cascade limit.
`.exe` files can still keep their own top-level `Firewall Rules` entry outside `System Tools`.

Standalone tools such as `mklink` and `ContextLens`, plus top-level surfaces such as `Safe Mode Options`, stay outside the `System Tools` cascade when needed, but they are still monitored by the same manager.

---

## 🧭 Tool Manager / Updates

> Monitor, inspect, repair, and update the managed Windows tool family, including entries that live outside the shared `System Tools` menu.

### Usage

**From context menu** — right-click any file, folder, folder background, or desktop background → *System Tools* → *Tool Manager / Updates*

**From terminal:**

```powershell
.\SystemToolsManager.ps1
.\SystemToolsManager.ps1 -Action Status
.\SystemToolsManager.ps1 -Action RepairAll
.\SystemToolsManager.ps1 -Action UpdateAll
.\SystemToolsManager.ps1 -Action VerifyMenu
.\SystemToolsManager.ps1 -Action InspectTool -ToolName SystemCleanup
.\SystemToolsManager.ps1 -Action InspectTool -ToolName ContextLens
.\SystemToolsManager.ps1 -Action MenuStructure
.\SystemToolsManager.ps1 -Action Budgets
```

The manager reads `.assets\systemtools-family.json`, so the managed list can grow without rewriting the manager script. Its interactive menu follows the WinAppManager-style composition: a versioned bordered banner, compact summary, colored action list, cached status snapshot, and in-place arrow-menu repaint. For local repair/install it prefers the matching repo checkout discovered from `.codex\REPO_ROOTS.psd1`; for updates it uses each installed tool's generated `Install.ps1 -Action UpdateGitHub` path and compares `state\install-meta.json` commits against GitHub `master`. The `W` shortcut fast-forwards only the selected workspace, so a stale local checkout can be updated before any local-source repair.

The status table separates installed provenance from workspace state:

| Column | Meaning |
|--------|---------|
| `Inst` | Commit recorded in the installed copy's `state\install-meta.json` |
| `Work` | Current local repo checkout commit; `*` means that workspace is dirty |
| `Remote` | Latest GitHub branch commit |
| `Monitored` | Host-owned or registry-only surface with no standalone installer |
| `Dirty-source install` | The installed copy was created from an uncommitted workspace, so commit-only status may look behind even when installed files already include the later committed content |

| Action | What it does |
|--------|--------------|
| `InstallAll` / `RepairAll` | Runs each repo's generated installer from the local checkout when available |
| `UpdateAll` | Updates installed tools from GitHub through their generated installers |
| `Tools Summary` | Navigable installed/workspace/remote table with selected-row guidance; Enter opens a WT Git review pane when the selected workspace needs review |
| `Menu Structure` | Directory-tree style view grouped by human right-click targets, with monitored tools, entry visibility, menu verification, and per-popup 16-item budget status |

`Tools Summary` also shows an `Actions Needed` section for the selected row. It recommends the safest next step, such as `W` first when the local workspace is missing or behind GitHub, `U` for GitHub update/repair of the installed copy, `I` for local install/repair, workspace review, or no action. `U`, `W`, `I`, and `X` ask for immediate `Y/N` confirmation without requiring Enter; after `Y`, the manager auto-runs the next safe `Best next` steps for `U`, `W`, and `I` on that same tool until it reaches `No action needed`, an error, or manual review/cleanup guidance. `X` uninstalls only the selected installed tool and does not touch local workspace files. Selected-row actions refresh only that row afterward, keeping the manager responsive; use `R` when you want a full pool refresh. When a selected row needs Git review, `Enter` opens a vertical WT split pane in that tool's workspace with suggested first commands. The review pane is a normal shell; close it with `exit` or `Ctrl+Shift+W`.

When `WorkState` is `Current + dirty`, `Update` still uses the installed tool's GitHub update path and does not touch the local dirty workspace. `Install` / `Repair` uses the local checkout when available, so it will deploy the uncommitted workspace files and mark the installed metadata as a dirty-source install. When `WorkState` is `Different`, local install/repair is refused until `W` fast-forwards the workspace, preventing older checkout files from being reinstalled over newer GitHub builds. When `WorkState` is `No workspace`, `W` clones the repo to the configured local workspace path without changing installed files. If that destination already exists but is not a usable repo, the manager leaves it untouched and reports the expected marker file.

Dirty workspace guidance stays advisory. The manager can suggest `git status -sb`, `git diff --stat`, and upstream comparison commands, but it does not auto-commit, auto-rebase, or auto-push source repos.

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

**From context menu** — right-click any folder → *System Tools* → *Explorer* → *Restart Explorer*

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

## 🛡️ PSRemoting Manager

> Safely enable or disable Windows Remote Management (WinRM) and manage `TrustedHosts` interactively.

### The Problem

Managing PSRemoting via CLI parameters can be tedious and opaque, especially over public networks or when trying to configure `TrustedHosts` across workgroups without a domain controller. It is also easy to leave the WinRM service running unnecessarily.

### The Solution

Provides an interactive console UI block that allows you to safely:
- **Enable PSRemoting** (Forcing enablement while skipping public network profile restrictions).
- **Disable PSRemoting completely** (Stops the WinRM service, disables startup, and closes the Firewall rules).
- **Add TrustedHosts** (Safely append an IP/Hostname string to the existing value without breaking it).
- **Clear TrustedHosts** (Revert trust changes completely).

### Usage

**From terminal:**

```powershell
.\Toggle-PSRemoting.ps1
```

*(The script automatically prompts for UAC Elevation if not already running as Admin.)*

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
| ⬆️ **Update App** | Shows version, commit, source, and dirty-state status, then runs the safest InstallerCore-backed update path |
| 📡 **Broadcast** | Sends `WM_SETTINGCHANGE` so all apps pick up PATH changes instantly |

### Usage

**From context menu** — right-click any folder → *System Tools* → *Windows* → *Manage Folder PATH...*

Opens a resize-safe arrow menu in Windows Terminal:

```
╔════════════════════════════════════════════════════════╗
║ System Tools - PATH Manager                           ║
║ Resize-safe PATH and environment control              ║
╚════════════════════════════════════════════════════════╝

  Update        : Up to date
  Version       : 1.0.3 -> 1.0.3
  Commits       : 8ce4f90 -> 8ce4f90
  Source        : Workspace
  Target Folder : D:\Users\joty79\scripts\SystemTools
  Session Mode  : Admin
  User PATH     : YES
  Machine PATH  : NO

  > Toggle User PATH
    Toggle Machine PATH (Admin)
    Open ENV snapshot pane
    Export ENV snapshot (MD)
    Update app
    Exit
```

The `Update app` panel is commit-aware, not just version-aware:

| Source kind | Update method |
|-------------|---------------|
| Git repo working copy | `git fetch` plus `merge --ff-only`; dirty workspaces are refused |
| Installed copy | `Install.ps1 -Action UpdateGitHub`, comparing `state\install-meta.json` `github_commit` to the latest remote commit |
| Portable non-git copy | `Install.ps1 -Action DownloadLatest -NoSelfRelaunch` |

If a fresh remote check fails, a stale cached `Up to date` result is not reused.

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

**From context menu** — right-click any folder → *System Tools* → *Explorer* → *Refresh Shell*

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

## 🧹 Clear Icon Cache

> Rebuild the Windows icon cache, thumbnail cache, and UWP AppIconCache to fix broken or missing icons.

### The Problem

After installing/uninstalling apps (especially image viewers like IrfanView, ACDSee, or Icaros), or when third-party thumbnail handlers (Google Drive) interfere with `.png` shell extensions:
- UWP/Store app icons show as **generic PNG file type icons** in Start Menu and Search
- File Explorer thumbnails are stale or broken
- Context menu icons are wrong

### The Solution

Clear-IconCache kills **all shell processes** that lock cache files (not just Explorer — also SearchHost, ShellExperienceHost, StartMenuExperienceHost, TextInputHost), deletes all cache databases, and lets Windows auto-restart the shell cleanly.

```
Kill all shell processes → Delete iconcache*.db + thumbcache*.db + AppIconCache
                        → ie4uinit -show (force icon refresh)
                        → Winlogon auto-restarts Explorer (no zombie)
                        → If files locked: RunOnce boot-time deletion
```

### Why Not BleachBit?

| Feature | BleachBit | Clear-IconCache |
|---------|:---------:|:---------------:|
| Icon cache (`iconcache*.db`) | ❌ | ✅ |
| Thumbnail cache (`thumbcache*.db`) | ✅ | ✅ (with `-Thumbnails`) |
| UWP AppIconCache | ❌ | ✅ |
| StartMenu TempState | ❌ | ✅ |
| Kill ALL shell processes | ❌ (Explorer only) | ✅ |
| Locked file handling | ❌ | ✅ (RunOnce fallback) |
| Ghost process prevention | ❌ | ✅ (winlogon auto-restart) |

### Usage

**From context menu** — *Right-click a folder, folder background, or desktop background → System Tools → Explorer → Clear Icon Cache*

**From terminal (requires Admin):**

```powershell
# Rebuild icon cache only
gsudo pwsh -NoProfile -File .\Clear-IconCache.ps1

# Rebuild icon + thumbnail cache
gsudo pwsh -NoProfile -File .\Clear-IconCache.ps1 -Thumbnails

# Diagnose UWP/MSIX apps showing generic PNG icons in Start Search
gsudo pwsh -NoProfile -File .\Clear-IconCache.ps1 -DiagnoseUwpPngIcons

# Remove broken .png thumbnail handlers, then rebuild Search/UWP icon caches
gsudo pwsh -NoProfile -File .\Clear-IconCache.ps1 -FixUwpPngIcons

# Also reset a stale .png default-app UserChoice when needed
gsudo pwsh -NoProfile -File .\Clear-IconCache.ps1 -FixUwpPngIcons -ResetPngUserChoice

# Silent (no pause)
gsudo pwsh -NoProfile -File .\Clear-IconCache.ps1 -NoPause
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Thumbnails` | `switch` | Off | Also delete thumbnail cache (can be slow on large photo libraries) |
| `-DiagnoseUwpPngIcons` | `switch` | Off | Inspect `.png` file association, UserChoice, shell extensions, Search AppIconCache, and Windows Search status without changing anything |
| `-FixUwpPngIcons` | `switch` | Off | Remove third-party `.png\shellex` thumbnail handlers that can make UWP/MSIX icons render as generic PNG file-type icons in Start Search |
| `-ResetPngUserChoice` | `switch` | Off | Also remove the current user's `.png` UserChoice association; use only when it points to a stale or unwanted image viewer ProgID |
| `-NoPause` | `switch` | Off | Skip `Press Enter to close` prompt |

If only some Start Search app icons redraw immediately after `-FixUwpPngIcons`, use the same visual redraw trigger Windows responds to manually: Settings → System → Display → Scale, change 125% → 100%, wait a few seconds, then change back. A reboot should also complete locked-cache cleanup when the script reports RunOnce scheduling.

---

## 📦 Installation

### Recommended Installer

```powershell
# Interactive installer (Local / GitHub source)
pwsh -ExecutionPolicy Bypass -File .\Install.ps1

# Direct actions
pwsh -ExecutionPolicy Bypass -File .\Install.ps1 -Action Install
pwsh -ExecutionPolicy Bypass -File .\Install.ps1 -Action Update
pwsh -ExecutionPolicy Bypass -File .\Install.ps1 -Action Uninstall
```

This installs `SystemTools` under `%LOCALAPPDATA%\SystemToolsContext`, writes the shared `System Tools` parent menu plus the `Explorer` / `Windows` category folders, and patches the hidden VBS launchers to the deployed install path.

### Registry-Only Alternative

```powershell
# Install or repair only the registry menu from the current folder
pwsh -NoProfile -File .\Install-SystemToolsMenu.ps1 -Action Install

# Check registry status
pwsh -NoProfile -File .\Install-SystemToolsMenu.ps1 -Action Status
```

### Manual Setup (`.reg` file)

Double-click `SystemToolsMenu.reg` to import directly when using the repo working copy itself.

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
├── app-metadata.json             # App version and GitHub metadata for update checks
├── Install.ps1                   # Primary template-based installer
├── AddDelPath.ps1                # PATH Manager — interactive menu + CLI
├── SystemToolsManager.ps1        # Tool Manager / Updates — family updater
├── Export-EnvReadable.ps1        # Remote-capable ENV snapshot builder
├── Toggle-PSRemoting.ps1         # PSRemoting Manager — interactive WinRM UI
├── RestartExplorer.ps1           # Restart Explorer — clean shell restart
├── RefreshShell.ps1              # Refresh Shell — broadcast refresh signals
├── Clear-IconCache.ps1           # Clear Icon Cache — rebuild icon/thumb/UWP caches
├── .assets/systemtools-family.json # Tool Manager family registry/install config
├── Install-SystemToolsMenu.ps1   # Registry installer/uninstaller
├── SystemToolsMenu.reg           # Manual registry import (alternative)
├── Launch-SystemToolsMenu.vbs    # VBS launcher (no console flash)
├── Launch-SystemToolsManager.vbs # VBS launcher for Tool Manager / Updates
├── Launch-RestartExplorer.vbs    # VBS launcher (no console flash)
├── Launch-RefreshShell.vbs       # VBS launcher (no console flash)
├── Launch-ClearIconCache.vbs     # Elevated WT launcher for Clear Icon Cache
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

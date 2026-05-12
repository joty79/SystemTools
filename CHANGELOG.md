# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Tool Manager / Updates** (`SystemToolsManager.ps1`): Added a `System Tools > Explorer` context-menu entry that opens a Windows Terminal update center for the SystemTools tool family.
- **Structured System Tools Menu**: Added `Explorer` and `Apps & Windows` category folders under the shared `System Tools` context-menu parent so separately maintained tools can appear as one organized toolbox.
- **Clear Icon Cache** (`Clear-IconCache.ps1`): Comprehensive icon, thumbnail, and UWP AppIconCache rebuild script with `System Tools` context-menu integration on folder, folder background, and desktop background branches. Kills all shell processes (Explorer, SearchHost, ShellExperienceHost, StartMenuExperienceHost, TextInputHost) to release file locks, deletes all cache databases, uses `ie4uinit -show` for icon refresh, and schedules locked files for boot-time deletion via RunOnce. More thorough than BleachBit's thumbnail cleaner (which misses icon cache, AppIconCache, and locked file handling).
- **PSRemoting Manager** (`Toggle-PSRemoting.ps1`): Interactive UI to safely Enable/Disable WinRM, and manage `TrustedHosts` (Add or Clear).
- **Remote Environment Export**: `Export-EnvReadable.ps1` now supports fetching environment variables from a remote computer via PSRemoting/WinRM.
- **Template-Based Installer**: Added a new profile/template generation workflow for generating `Install.ps1` files.

### Changed
- **Version 1.0.7**: Bumped `app-metadata.json` for the new Tool Manager / Updates context-menu entry.
- **Version 1.0.6**: Restored the two-category `Explorer` / `Apps & Windows` submenu layout by request after temporarily flattening it.
- **Version 1.0.4**: Bumped `app-metadata.json` for the shared `Explorer` / `Apps & Windows` context-menu layout migration.
- **Context Menu Layout**: Moved built-in actions into `Explorer` (`Refresh Shell`, `Restart Explorer`, `Clear Icon Cache`) and `Apps & Windows` (`Manage Folder PATH...`). Companion tools now target matching nested child paths from their `InstallerCore` profiles.
- **Version 1.0.3**: Bumped `app-metadata.json` for the commit-aware `Update app` status migration.
- **PATH Manager Update Status**: Expanded update checks to show local/latest version, local/latest commit, source kind, dirty state, and status, while preventing stale cached `UpToDate` results from hiding failed fresh remote checks.
- **PATH Manager Update Flow**: Git repo working copies now update only through `git fetch` plus fast-forward and refuse dirty workspaces; installed copies compare `state\install-meta.json` `github_commit` against the latest remote commit; portable non-git copies continue to use `DownloadLatest -NoSelfRelaunch`.
- **Version 1.0.2**: Bumped `app-metadata.json` for the shipped Clear Icon Cache context-menu tool.
- **Version 1.0.1**: Bumped `app-metadata.json` so installed copies can detect the current PATH Manager update through the existing version-based update UI.
- **PATH Manager Update UI**: Added the InstallerCore-style `Update: ...` header status and `Update app` submenu inside the PATH Manager TUI.
- **PATH Manager Update Status**: Added commit-aware update checks for installed copies that have InstallerCore `state\install-meta.json` metadata, so same-version hotfix commits can still show as updateable.
- **PATH Manager UI**: Replaced the old numbered `Read-Host` PATH menu with the shared resize-safe arrow-menu UI from `.codex\tools\PS_UI_Blueprint.psm1`.
- **InstallerCore Alignment**: Regenerated `Install.ps1` from the current `InstallerCore` template so `SystemTools` now picks up the newer generated installer flow, including app metadata version resolution and self-relaunch controls for `DownloadLatest`.
- **Package Coverage**: Installer package manifests now include `app-metadata.json`, `Toggle-PSRemoting.ps1`, and `Export-EnvReadable.ps1`, so installed copies no longer miss the terminal-only tools documented in the repo.
- **PSRemoting UI Workflow**: `Toggle-PSRemoting.ps1` now loads the canonical `.codex\tools\PS_UI_Blueprint.psm1` path instead of the old `.gemini` template path, and the TrustedHosts actions now re-read live state before editing.

### Fixed
- **Context Menu WT Window Reuse**: The PATH Manager launcher now asks Windows Terminal for a new window instead of attaching a new tab to whichever admin WT window was already open.
- **UI Blueprint Import Flash**: Suppressed the transient `Import-Module` unapproved-verb warning when loading `PS_UI_Blueprint.psm1`, removing a two-frame startup message before the arrow UI renders.
- **Installer Prompt Crash**: Fixed generated `Install.ps1` crashing in non-interactive hosts when `Read-Host` returns `$null`; prompts now cancel cleanly unless `-Force` is supplied.
- **Installer Scripted Update Exit Code**: `Install.ps1 -NoExplorerRestart` now logs the intentional Explorer restart skip as informational, so scripted update verification does not fail solely because Explorer restart was suppressed.
- **PATH Manager StrictMode Crash**: Fixed `$_C` color palette lookup failing after importing the shared UI blueprint as a module. `AddDelPath.ps1` and `Toggle-PSRemoting.ps1` now define the small ANSI palette they use locally instead of depending on private module variables.
- **PSRemoting Manager Startup/Navigation Lag**: Removed the expensive firewall rule enumeration from the live redraw path and changed status rendering to snapshot once per menu screen instead of re-reading WinRM state on every arrow-key redraw.
- **SystemToolsMenu Installer**: Fixed a critical bug in `Install-SystemToolsMenu.ps1` where using the `$args` automatic variable caused silent failures during registry writing.
- **Menu Icons**: Synced context menu icons in `Install-SystemToolsMenu.ps1` to use the correct `.ico` files from `.assets\icons\` instead of generic `imageres.dll` fallback icons.
- **SubCommands Empty Data**: Fixed an issue where empty `SubCommands` was written as literal `""` instead of a true empty string during registry installation.

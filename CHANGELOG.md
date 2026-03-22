# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **PSRemoting Manager** (`Toggle-PSRemoting.ps1`): Interactive UI to safely Enable/Disable WinRM, and manage `TrustedHosts` (Add or Clear).
- **Remote Environment Export**: `Export-EnvReadable.ps1` now supports fetching environment variables from a remote computer via PSRemoting/WinRM.
- **Template-Based Installer**: Added a new profile/template generation workflow for generating `Install.ps1` files.

### Fixed
- **SystemToolsMenu Installer**: Fixed a critical bug in `Install-SystemToolsMenu.ps1` where using the `$args` automatic variable caused silent failures during registry writing.
- **Menu Icons**: Synced context menu icons in `Install-SystemToolsMenu.ps1` to use the correct `.ico` files from `.assets\icons\` instead of generic `imageres.dll` fallback icons.
- **SubCommands Empty Data**: Fixed an issue where empty `SubCommands` was written as literal `""` instead of a true empty string during registry installation.

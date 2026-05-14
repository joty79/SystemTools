# PROJECT_RULES - SystemTools

## Scope

- Repo: `D:\Users\joty79\scripts\SystemTools`
- Purpose: Build reusable context-menu utilities under a shared `System Tools` folder menu.

## Guardrails

- Use `HKCU\Software\Classes\Directory\shell\...` for folder context-menu entries.
- Keep menu structure nested via `shell\...` keys (no flat `SubCommands` split).
- For cleanup, remove both `HKCU\Software\Classes\...` and `HKCR\...` variants.
- For PATH edits, support both `User` and `Machine` scope and require admin for `Machine` writes.

## Decision Log

### Entry - 2026-02-27

- Date: 2026-02-27
- Problem: Need a scalable folder menu (`System Tools`) to host multiple scripts.
- Root cause: Existing single-script approach does not organize multiple utilities under one context node.
- Guardrail/rule: Create one parent folder menu and add script actions as child submenus; keep scripts standalone and reusable.
- Files affected: `AddDelPath.ps1`, `Install-SystemToolsMenu.ps1`.
- Validation/tests run: Parser validation on both scripts; status run for `AddDelPath.ps1`.

### Entry - 2026-02-27 (Interactive PATH UI)

- Date: 2026-02-27
- Problem: Context-menu actions closed too fast, so status/output was not readable.
- Root cause: Direct non-interactive command launches from Explorer were short-lived and split across multiple menu entries.
- Guardrail/rule: Use one submenu entry (`Manage Folder PATH...`) that opens `wt` and runs one unified `AddDelPath.ps1` interactive menu (User/Machine status + add/remove/toggle options).
- Files affected: `AddDelPath.ps1`, `SystemToolsMenu.reg`.
- Validation/tests run: PowerShell parser validation for `AddDelPath.ps1`; manual review of `SystemToolsMenu.reg` command path/quoting.

### Entry - 2026-02-27 (Pretty Menu + ENV Terminal View)

- Date: 2026-02-27
- Problem: PATH menu was functional but visually plain and did not provide full environment visibility in terminal.
- Root cause: Script only showed simple PATH status and did not expose machine/user environment variables in an interactive view.
- Guardrail/rule: Keep one unified `AddDelPath.ps1` as menu controller with colored/emoji UI, terminal ENV snapshot view, and optional TXT/MD export from the same script.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; `-Action Status` smoke test; `-Action EnvExport -ExportFormat Txt` smoke test.

### Entry - 2026-02-27 (WT Parallel ENV Pane)

- Date: 2026-02-27
- Problem: ENV snapshot view blocked the same pane, making side-by-side comparison harder.
- Root cause: Option `8` rendered ENV snapshot inline in the active pane.
- Guardrail/rule: In WT sessions (`WT_SESSION`), option `8` opens a vertical split pane via `wt split-pane -V` and runs `AddDelPath.ps1 -Action EnvView`; outside WT, fallback remains inline.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; review of split-pane argument list and action wiring.

### Entry - 2026-02-27 (WT Title Parsing Fix)

- Date: 2026-02-27
- Problem: `wt split-pane` failed with `0x80070002` and attempted to launch `Snapshot ...`.
- Root cause: `--title` value with space (`ENV Snapshot`) was tokenized into extra command token in this invocation path.
- Guardrail/rule: For `wt` command argument lists in script launches, prefer no-space titles (e.g. `ENV-Snapshot`) and avoid fragile commandline tokenization.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; manual inspection of updated `wt` argument list.

### Entry - 2026-02-27 (Toggle Crash + Menu Simplification)

- Date: 2026-02-27
- Problem: Option `Toggle User PATH` failed with `Collection was of a fixed size.` and menu had redundant Add/Remove actions.
- Root cause: `Get-PathEntries` returned a fixed-size collection wrapper; menu design duplicated behavior already covered by toggle.
- Guardrail/rule: For mutable PATH workflows, return a real mutable `List[string]`; keep interactive menu focused on `Toggle` actions and remove redundant Add/Remove entries.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation after edit.

### Entry - 2026-02-27 (List Enumeration Fix + Admin-First Menu)

- Date: 2026-02-27
- Problem: `Toggle` still threw `Collection was of a fixed size.` and users wanted admin-capable menu from startup.
- Root cause: Returning `List[string]` without no-enumeration wrapper made PowerShell unwrap it to fixed-size array at call site.
- Guardrail/rule: When returning mutable .NET collections from functions, return with no-enumeration (e.g. `return ,$list`); for this tool, relaunch `Menu` elevated by default and continue standard only if elevation is canceled.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; toggle add/remove smoke test on temp folder path.

### Entry - 2026-02-27 (pwsh Entry + WT Bootstrap)

- Date: 2026-02-27
- Problem: Desired launcher behavior was "run from PowerShell, then use WT host".
- Root cause: Context menu command invoked `wt.exe` directly instead of routing through the main `ps1` entrypoint.
- Guardrail/rule: Keep registry command as `pwsh.exe -File AddDelPath.ps1 -Action Menu`; bootstrap to WT from script (`Ensure-MenuHostInWindowsTerminal`) with loop-prevention switch (`-SkipWtBootstrap`).
- Files affected: `AddDelPath.ps1`, `SystemToolsMenu.reg`.
- Validation/tests run: PowerShell parser validation; manual verification of updated registry command and bootstrap wiring.

### Entry - 2026-02-27 (Single-Window Launch Order)

- Date: 2026-02-27
- Problem: Launch flow could open two windows at startup (non-admin WT then elevated WT).
- Root cause: Menu bootstrapped to WT before running elevation check.
- Guardrail/rule: For `Menu` action, run elevation check first and WT host bootstrap second (`Ensure-MenuElevation` -> `Ensure-MenuHostInWindowsTerminal`) to avoid duplicate startup windows.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; manual line-order verification in `switch ($Action)`.

### Entry - 2026-02-27 (No-Flash Context Launch via VBS)

- Date: 2026-02-27
- Problem: Context launch still showed a short-lived console window before WT opened.
- Root cause: Registry command invoked `pwsh.exe` directly, which created an intermediate visible console process.
- Guardrail/rule: For context-menu launch UX, use `wscript.exe` launcher (`Launch-SystemToolsMenu.vbs`) and call `wt.exe` with `runas` directly from VBS to avoid console flash.
- Files affected: `SystemToolsMenu.reg`, `Launch-SystemToolsMenu.vbs`.
- Validation/tests run: Parser validation on `AddDelPath.ps1`; manual verification of registry command and VBS launcher arguments.

### Entry - 2026-02-27 (Toggle UX Fast-Refresh)

- Date: 2026-02-27
- Problem: Toggle actions showed duplicate status block and required extra `Press Enter` even though main menu refresh already displays new state.
- Root cause: `Invoke-PathAction` always printed post-action status and menu loop always paused.
- Guardrail/rule: In menu toggle flows, call `Invoke-PathAction` with `-SkipStatusOutput` and skip pause, so UI returns directly to refreshed main menu.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification of toggle menu flow and pause gating.

### Entry - 2026-02-27 (Option 4 Pane Toggle)

- Date: 2026-02-27
- Problem: ENV snapshot pane opened with option `4` but required manual close via keyboard/window controls.
- Root cause: Snapshot pane had no control channel from main menu action.
- Guardrail/rule: Option `4` is now true toggle: first press writes active state + token and opens pane; second press flips state to close signal. `EnvView` pane waits on token/state file and exits automatically when toggle is pressed again.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; verification of state/token functions and option-4 control flow wiring.

### Entry - 2026-02-27 (Option 4 Close From Pane Focus)

- Date: 2026-02-27
- Problem: When focus moved to snapshot pane, pressing `4` in the pane did not close it and pane could drop to shell prompt after script exit.
- Root cause: Pane close signal only came from main menu option `4`; split-pane launch kept `-NoExit`, so script completion left interactive prompt.
- Guardrail/rule: In `EnvView`, accept key `4` directly via `RawUI.ReadKey` to set close signal; launch snapshot pane without `-NoExit` so pane closes when script exits.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification for key-read loop and split-pane launch args.

### Entry - 2026-02-27 (Menu Simplify: Remove Option 3 / No Pause on 4)

- Date: 2026-02-27
- Problem: `Show PATH status` was redundant with always-refreshed main menu, and option `4` still showed unnecessary pause flow.
- Root cause: Legacy menu item retained explicit status action; pane launch path still allowed post-action pause prompt.
- Guardrail/rule: Remove menu option `3`; keep option `4` as toggle-only action with no menu pause, label it explicitly as toggle, and force `EnvView` pane launches with `-NoPause`.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification of menu options and final pause condition.

### Entry - 2026-02-27 (Menu Reorder: ENV Toggle = 3)

- Date: 2026-02-27
- Problem: Menu numbering had a gap and ENV toggle needed to be key `3` with no extra confirmation flow.
- Root cause: Previous simplification removed old option `3` but kept ENV toggle on `4`.
- Guardrail/rule: Keep menu order contiguous (`1`,`2`,`3`,`4`), map ENV toggle to `3`, and keep no-pause behavior for this action; snapshot pane close hint/key must match (`Press 3`).
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification of labels, switch cases, and pane key handler.

### Entry - 2026-02-27 (No-Pause Reliability For Option 3)

- Date: 2026-02-27
- Problem: Main menu could still show `Press Enter to continue` after option `3` in some control paths.
- Root cause: Pause flag defaulted to true and depended on execution order inside case block.
- Guardrail/rule: Set pause behavior from choice preemptively (`$shouldPause = ($choice -ne '3')`) so option `3` is always no-pause.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification of pause assignment and option `3` branch.

### Entry - 2026-02-27 (Pause Policy Finalization)

- Date: 2026-02-27
- Problem: Option `3` behavior was still perceived inconsistent and snapshot pane could still show close prompt in some paths.
- Root cause: Mixed historical pause overrides for options `1`/`2` plus conditional end-of-script pause tied to token presence.
- Guardrail/rule: Keep main menu pause policy explicit: only option `3` is no-pause, others keep confirmation pause. For `EnvView` action, never show final `Press Enter to close` prompt.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification of case branches and final pause condition.

### Entry - 2026-02-27 (Simplify ENV Pane Control Model)

- Date: 2026-02-27
- Problem: Stateful pane-toggle logic became hard to reason about and still caused inconsistent user experience.
- Root cause: Added token/state-file coordination introduced unnecessary complexity for a simple open/close interaction.
- Guardrail/rule: Keep ENV snapshot control stateless: menu option `3` opens snapshot pane; inside pane, key `3` closes it; no state files/tokens for pane lifecycle.
- Files affected: `AddDelPath.ps1`.
- Validation/tests run: PowerShell parser validation; line-level verification that state/token references were removed.

### Entry - 2026-02-27 (Directory Background Support)

- Date: 2026-02-27
- Problem: `System Tools` menu was available on folder items but not when right-clicking folder background.
- Root cause: Registry integration only targeted `Directory\shell\SystemTools`.
- Guardrail/rule: Mirror menu under `Directory\Background\shell\SystemTools` and use `%V` in command for background path context; keep cleanup for both `HKCU\Software\Classes` and `HKCR` variants.
- Files affected: `SystemToolsMenu.reg`.
- Validation/tests run: Manual review of registry keys/commands and cleanup coverage.

### Entry - 2026-02-28 (Restart Explorer Port)

- Date: 2026-02-28
- Problem: Need a PowerShell version of `Restart Explorer` from `RightClickTools` as a reusable `System Tools` script.
- Root cause: Desired functionality existed only in external C# reference code, not as native `ps1` utility inside this repo.
- Guardrail/rule: Port small utilities one-at-a-time from reference projects; for `Restart Explorer`, keep it standalone, call shell refresh first, then restart `explorer.exe`, and reopen Explorer at target folder when valid.
- Files affected: `RestartExplorer.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation planned after script creation.

### Entry - 2026-02-28 (Restart Explorer = Pure Restart Only)

- Date: 2026-02-28
- Problem: Reference `RightClickTools` implementation bundled `RefreshShell()` before Explorer restart and could surface hidden/system files unexpectedly.
- Root cause: The external C# helper used a visibility-toggle refresh trick before killing and relaunching `explorer.exe`, which is riskier than needed for this repo's simpler restart action.
- Guardrail/rule: In `SystemTools`, `Restart Explorer` must be pure restart-only: no `RefreshShell`, no hidden/system visibility toggles, no Explorer view-state hacks. Preserve only optional reopen-at-target-folder behavior.
- Files affected: `RestartExplorer.ps1`, `Launch-RestartExplorer.vbs`, `SystemToolsMenu.reg`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `RestartExplorer.ps1`; manual review of registry/VBS command wiring.

### Entry - 2026-02-28 (Restart Explorer Wait-For-Exit)

- Date: 2026-02-28
- Problem: Immediate relaunch after per-process kill could race with Explorer shutdown and may contribute to transient extra Explorer instances during restart.
- Root cause: Relaunch happened after individual `Stop-Process` calls without first waiting for the full `explorer.exe` process set to disappear from the process table.
- Guardrail/rule: For Explorer relaunch, stop all current `explorer.exe` processes first, then wait on `Wait-Process -Name explorer` before starting the new instance.
- Files affected: `RestartExplorer.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `RestartExplorer.ps1`.

### Entry - 2026-02-28 (Delayed Folder Reopen After Shell Restart)

- Date: 2026-02-28
- Problem: Reopening the target folder immediately during Explorer restart may correlate with transient extra Explorer instances.
- Root cause: Folder-open request was launched as part of the same immediate relaunch step instead of after the primary shell had time to stabilize.
- Guardrail/rule: Resolve/save `TargetPath` first, restart the base shell with plain `explorer.exe`, wait briefly, then reopen the saved folder path as a second step.
- Files affected: `RestartExplorer.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `RestartExplorer.ps1`.

### Entry - 2026-02-28 (No Quick Access / No Target Reopen)

- Date: 2026-02-28
- Problem: Any scripted Explorer relaunch path still opened a `Quick Access` window and target-folder reopen correlated with transient zombie Explorer behavior.
- Root cause: `Start-Process explorer.exe` opens a File Explorer window, and a second folder-open launch adds another Explorer activation path.
- Guardrail/rule: For the default `Restart Explorer` utility, do not script any Explorer relaunch or target-folder reopen. Keep it as Explorer stop-only to avoid `Quick Access` and extra folder windows.
- Files affected: `RestartExplorer.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `RestartExplorer.ps1`.

### Entry - 2026-02-28 (COM-Based Folder Reopen — Zombie Fix)

- Date: 2026-02-28
- Problem: `Start-Process explorer.exe` after kill always created a second/zombie Explorer process because Windows auto-restarts the shell via `winlogon`, making any scripted `Start-Process` redundant and additive.
- Root cause: Windows auto-respawns the shell `explorer.exe` after termination. `Start-Process explorer.exe` (with or without path) creates a SECOND process on top of the auto-respawned one. This second process is the "zombie".
- Guardrail/rule: Never use `Start-Process explorer.exe` to restart the shell. Instead: (1) kill Explorer, (2) wait for Windows auto-restart via polling loop, (3) wait 2s for shell stabilization, (4) reopen folder via `Shell.Application` COM (`New-Object -ComObject Shell.Application; $shell.Open($path)`). The COM method reuses the existing shell process and does not spawn an extra `explorer.exe`. Use `-ReopenFolder` switch as opt-in.
- Files affected: `RestartExplorer.ps1`, `Launch-RestartExplorer.vbs`, `PROJECT_RULES.md`.
- Validation/tests run: Manual context-menu test confirmed: 1 `explorer.exe` process, folder reopened, zero zombie processes.

### TODO

- Reuse the COM-based Explorer folder-reopen flow in future installer/template workflows so context-menu install/update actions can restart Explorer without losing the user's current folder context.

### Entry - 2026-02-28 (Refresh Shell = Notify Only)

- Date: 2026-02-28
- Problem: Need a `Refresh Shell` utility without the risky hidden/system visibility toggle trick used by the external `RightClickTools` reference.
- Root cause: The reference implementation bundled shell notification with temporary Explorer visibility-state changes, which is more invasive than desired for this repo.
- Guardrail/rule: Keep `Refresh Shell` minimal: send shell refresh notifications only (`SHChangeNotify` + `WM_SETTINGCHANGE` broadcast) with no Explorer restart, no hidden/system file toggles, and no icon-cache rebuild behavior.
- Files affected: `RefreshShell.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `RefreshShell.ps1`.

### Entry - 2026-02-28 (Refresh Shell Menu Wiring)

- Date: 2026-02-28
- Problem: `Refresh Shell` existed as a standalone script but was not accessible from the `System Tools` folder/background context menu.
- Root cause: Registry menu wiring and installer sync only exposed PATH Manager and Restart Explorer entries.
- Guardrail/rule: Every standalone `SystemTools` utility intended for manual use should get the same menu integration pattern: hidden VBS launcher plus mirrored `Directory\shell` and `Directory\Background\shell` entries.
- Files affected: `Launch-RefreshShell.vbs`, `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `Install-SystemToolsMenu.ps1`; manual review of registry command wiring.

### Entry - 2026-03-02 (SystemTools owns all shared submenu parents)

- Date: 2026-03-02
- Problem: Child tool repos (`WhoIsUsingThis`, `TakeOwnership`) kept breaking the shared `System Tools` cascade when they tried to create or patch parent keys themselves.
- Root cause: `SystemTools` only owned `Directory\shell` and `Directory\Background\shell` parents, while file-branch integrations were forced to invent their own `*\shell\SystemTools` parent definitions.
- Guardrail/rule: `SystemTools` is the sole owner of shared parent keys on all supported branches (`*\shell`, `Directory\shell`, `Directory\Background\shell`). Parent keys must be nested-shell cascades with `MUIVerb` + `Icon` only; do not use empty `SubCommands` values for this shared menu.
- Files affected: `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `Install-SystemToolsMenu.ps1`; static review of file/folder/background parent coverage.

### Entry - 2026-02-28 (PATH Menu Exit Should Close WT Tab)

- Date: 2026-02-28
- Problem: Choosing `0` in `AddDelPath.ps1` exited the menu but left an interactive `pwsh` prompt open in Windows Terminal.
- Root cause: WT launch paths used `pwsh.exe -NoExit`, so script termination dropped the user into a shell instead of closing the tab.
- Guardrail/rule: For menu-style WT launchers that should fully exit on option `0`, do not use `-NoExit` in VBS bootstrap or internal WT relaunch/elevation paths.
- Files affected: `Launch-SystemToolsMenu.vbs`, `AddDelPath.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `AddDelPath.ps1`; manual code-path review of WT launch arguments.

### Entry - 2026-02-28 (PATH Menu Exit Should Hand Off To Interactive pwsh)

- Date: 2026-02-28
- Problem: Closing the PATH menu with option `0` should leave the user in interactive `pwsh` with their normal shell/profile experience, not close Windows Terminal entirely.
- Root cause: Removing `-NoExit` closed the WT tab/window, and `-NoProfile` prevented normal interactive `pwsh` experience (`oh-my-posh`, prompt customizations, etc.) after menu exit.
- Guardrail/rule: For the PATH Manager menu host only, use `pwsh.exe -NoExit` and allow the normal profile to load so option `0` hands off to an interactive `pwsh` session instead of closing WT.
- Files affected: `Launch-SystemToolsMenu.vbs`, `AddDelPath.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `AddDelPath.ps1`; manual review of WT launch arguments.

### Entry - 2026-03-02 ($args Automatic Variable Bug in Add-Value)

- Date: 2026-03-02
- Problem: `Install-SystemToolsMenu.ps1` `-Action Install` silently produced broken/empty registry entries; `.reg` file import worked fine.
- Root cause: `Add-Value` function used `$args` as a local variable name to build `reg.exe` arguments. `$args` is a PowerShell automatic variable and is silently overwritten by the runtime inside functions, so the constructed argument array was never passed to `reg.exe`. Secondary issue: empty `SubCommands` data was written as literal `""` (two quote characters) instead of actual empty string.
- Guardrail/rule: Never use `$args` as a custom variable inside functions (guardrail #17). For `reg.exe` argument arrays, use `$regArgs` or similar.
- Files affected: `Install-SystemToolsMenu.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation; `-Action Status` smoke test.

### Entry - 2026-03-02 (Host Installer Must Respect Known-Good .reg Behavior)

- Date: 2026-03-02
- Problem: `SystemToolsMenu.reg` reliably produced the working cascade menu, while `Install-SystemToolsMenu.ps1` still produced divergent or broken host behavior during repeated submenu integration work.
- Root cause: The PowerShell installer was treated as equivalent to the `.reg` artifact even though sensitive shell values such as empty `SubCommands` require byte-accurate write behavior and explicit verification. Fixing one scripting bug (`$args`) was not enough to prove equivalence.
- Guardrail/rule: For the shared `System Tools` host menu, treat `SystemToolsMenu.reg` as the canonical source of truth until the PowerShell installer is proven byte-equivalent by readback verification. For sensitive registry writes, require explicit readback validation after install.
- Files affected: `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Behavioral comparison against `.reg` import; review of `Install-SystemToolsMenu.ps1` vs `SystemToolsMenu.reg`.

### Entry - 2026-03-02 (Installer Synced To Canonical Host .reg)

- Date: 2026-03-02
- Problem: `Install-SystemToolsMenu.ps1` created extra folder submenu verbs (`PathStatus`, `PathToggleUser`) and missed the canonical `PathManager` verb defined in `SystemToolsMenu.reg`.
- Root cause: The installer had drifted from the `.reg` source of truth and was maintaining its own menu structure instead of mirroring the canonical host definition.
- Guardrail/rule: `SystemToolsMenu.reg` remains the canonical host definition. `Install-SystemToolsMenu.ps1` must create the same key/value structure, and install-time cleanup of the parent `SystemTools` keys is relied on to remove any old extra child verbs before re-applying the canonical set.
- Files affected: `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `PROJECT_RULES.md`.
- Validation/tests run: Static diff of `.reg` keys vs installer-created keys; PowerShell parser validation after sync.

### Entry - 2026-03-02 (Desktop background host support for shared System Tools)

- Date: 2026-03-02
- Problem: `SystemCleanup` needed to move under the shared `System Tools` submenu while keeping its natural surface on desktop background right-click.
- Root cause: `SystemTools` only owned `*\shell`, `Directory\shell`, and `Directory\Background\shell`, so there was no shared host parent for `DesktopBackground\Shell`.
- Guardrail/rule: `SystemTools` owns the shared submenu parent on desktop background too: `HKCU\Software\Classes\DesktopBackground\Shell\SystemTools`. Keep `Restart Explorer` and `Refresh Shell` as built-in desktop-background children so the host is not empty.
- Files affected: `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of canonical `.reg` and installer sync; parser validation on `Install-SystemToolsMenu.ps1`.

### Entry - 2026-03-02 (Desktop background order is controlled separately)

- Date: 2026-03-02
- Problem: `System Tools` appeared at a reasonable place on folder and folder-background menus but too high on the desktop background context menu.
- Root cause: `DesktopBackground\Shell` ordering is not controlled by `MUIVerb`; it needs its own ordering hint. The desktop branch can drift from folder/background ordering even when the visible label is identical.
- Guardrail/rule: For the desktop background host only, set `Position="Bottom"` on `HKCU\Software\Classes\DesktopBackground\Shell\SystemTools`. Do not assume `MUIVerb` affects order.
- Files affected: `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Static review of desktop host branch; parser validation on `Install-SystemToolsMenu.ps1`.

### Entry - 2026-03-09 (Template installer for host repo)

- Date: 2026-03-09
- Problem: `SystemTools` needed the same reusable `Install.ps1` flow as the other tool repos, but the repo only had the bespoke `Install-SystemToolsMenu.ps1` registry installer and VBS launchers hardcoded to the dev repo path.
- Root cause: The host repo had not yet been onboarded into `InstallerCore`, and the launchers assumed `D:\Users\joty79\scripts\SystemTools` instead of a deployed install root.
- Guardrail/rule: Keep `Install.ps1` generated from `InstallerCore` as the primary installer for `SystemTools`. The generated install must deploy the built-in tools/assets, recreate the canonical host menu from `SystemToolsMenu.reg`, and patch the three VBS launchers to the deployed `{InstallRoot}`. Keep `Install-SystemToolsMenu.ps1` as a repo-local/manual registry helper, not as the primary install entrypoint.
- Files affected: `Install.ps1`, `README.md`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from `InstallerCore`; PowerShell parser validation passed on `Install.ps1`.

### Entry - 2026-04-18 (Installer manifest must include terminal-only tools + canonical UI blueprint)

- Date: 2026-04-18
- Problem: The repo contained `Toggle-PSRemoting.ps1` and `Export-EnvReadable.ps1`, but generated installs did not deploy them, and `Toggle-PSRemoting.ps1` still depended on an old `.gemini` UI blueprint path.
- Root cause: The `InstallerCore` profile/package lists drifted behind the repo contents, and the PSRemoting UI script had not been brought forward to the shared `.codex` PowerShell UI workflow.
- Guardrail/rule: Keep the `SystemTools` installer manifest aligned with the full repo-delivered toolset, including terminal-only scripts that are not wired into the context menu. `Toggle-PSRemoting.ps1` must use the canonical `.codex\tools\PS_UI_Blueprint.psm1` path resolution flow instead of any legacy external template path.
- Files affected: `Install.ps1`, `Toggle-PSRemoting.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from `InstallerCore`; `Parser::ParseFile` passed for `Install.ps1`, `Toggle-PSRemoting.ps1`, `Install-SystemToolsMenu.ps1`, `AddDelPath.ps1`, `RestartExplorer.ps1`, `RefreshShell.ps1`, and `Export-EnvReadable.ps1`.

### Entry - 2026-04-22 (Visible UI update must reach the installed context-menu copy)

- Date: 2026-04-22
- Problem: The repo had UI updates, but the visible context-menu PATH Manager still looked unchanged, and `Toggle-PSRemoting.ps1` felt slow.
- Root cause: `AddDelPath.ps1` still used the old numbered `Read-Host` menu, so the primary context-menu UI had not actually been moved to the shared blueprint. `Toggle-PSRemoting.ps1` also queried firewall/WinRM status inside the redraw path, so arrow-menu refreshes could repeat slow system queries.
- Guardrail/rule: For visible context-menu UI work, update the installed-context entrypoint (`AddDelPath.ps1`) and then run a local `Install.ps1 -Action Update` or explicitly tell the user the installed copy has not changed. Keep expensive system queries out of `Invoke-ArrowMenu` header redraw blocks; snapshot state once per menu screen.
- Files affected: `AddDelPath.ps1`, `Toggle-PSRemoting.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: `Parser::ParseFile` passed for core scripts; local update install ran with `-NoExplorerRestart`; readback confirmed installed `AddDelPath.ps1` contains `Invoke-ArrowMenu` and registry PathManager commands point to `C:\Users\joty79\AppData\Local\SystemToolsContext`.

### Entry - 2026-04-22 (Imported UI module variables are not script globals)

- Date: 2026-04-22
- Problem: PATH Manager opened the new banner, then crashed with `The variable '$_C' cannot be retrieved because it has not been set`.
- Root cause: `AddDelPath.ps1` and `Toggle-PSRemoting.ps1` referenced the shared blueprint module's private `$_C` color table from script-defined header/action blocks. Under `Set-StrictMode`, imported module variables are not script globals, so the header block failed at runtime.
- Guardrail/rule: Scripts may call exported UI functions from `PS_UI_Blueprint.psm1`, but any color constants used directly by the script must be defined in that script or passed explicitly. Do not rely on private variables from imported modules.
- Files affected: `AddDelPath.ps1`, `Toggle-PSRemoting.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: `Parser::ParseFile` passed for core scripts; local update install ran with `-NoExplorerRestart`; readback confirmed installed `AddDelPath.ps1` and `Toggle-PSRemoting.ps1` define local `$_C` palettes.

### Entry - 2026-04-22 (Generated installer prompts must handle non-interactive null)

- Date: 2026-04-22
- Problem: Running `Install.ps1 -Action Update -NoExplorerRestart` from Codex crashed at `Confirm` with `You cannot call a method on a null-valued expression`.
- Root cause: In this non-interactive host, `Read-Host` returned `$null`, and the generated installer called `.Trim()` on it. After adding `-Force`, the update completed but returned non-zero because `-NoExplorerRestart` was logged as a warning.
- Guardrail/rule: Generated installer confirmation helpers must treat `$null` prompt responses as cancellation. Use `-Force` for non-interactive install/update verification when the prompt should be accepted. Treat intentional `-NoExplorerRestart` skips as informational, not warning/failure state. Keep this fix in `InstallerCore\templates\Install.Template.ps1`, then regenerate `SystemTools\Install.ps1`; do not leave this as a downstream-only edit.
- Files affected: `Install.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\templates\Install.Template.ps1`.
- Validation/tests run: `Parser::ParseFile` passed for core scripts; `SystemTools\Install.ps1` regenerated from `InstallerCore`; `Install.ps1 -Action Update -NoExplorerRestart -Force` completed with exit code `0`; readback confirmed installed `AddDelPath.ps1`, `Toggle-PSRemoting.ps1`, `Install.ps1`, and `app-metadata.json` match repo hashes.

### Entry - 2026-04-22 (Suppress shared UI blueprint import warning)

- Date: 2026-04-22
- Problem: The PATH Manager window displayed a very brief warning that imported commands from `PS_UI_Blueprint.psm1` use unapproved verbs.
- Root cause: `Import-Module` emits name-checking warnings for functions such as `Begin-SyncRender` and `End-SyncRender` before the TUI clears/redraws the screen, so the message was visible only for a couple of frames.
- Guardrail/rule: When importing the shared PowerShell UI blueprint from user-facing TUI entrypoints, use `Import-Module -DisableNameChecking` unless/until the blueprint function names are globally renamed.
- Files affected: `AddDelPath.ps1`, `Toggle-PSRemoting.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: `Parser::ParseFile` passed for `AddDelPath.ps1`, `Toggle-PSRemoting.ps1`, and `Install.ps1`; direct `Import-Module -DisableNameChecking` and `AddDelPath.ps1 -Action Status -NoPause` checks produced no import warning; `Install.ps1 -Action Update -NoExplorerRestart -Force` completed with exit code `0`; installed file hash readback matched repo files.

### Entry - 2026-04-22 (Context launcher should not attach to existing WT tabs)

- Date: 2026-04-22
- Problem: After running the installer in Windows Terminal, launching PATH Manager from the context menu opened beside the installer as another tab in the same admin WT window.
- Root cause: `Launch-SystemToolsMenu.vbs` invoked Windows Terminal with `-w 0 nt`, which targets the existing/current WT window when one is available.
- Guardrail/rule: Explorer context-menu launchers should use `wt -w new nt` when the desired UX is a fresh tool window independent from any installer/dev terminal that happens to be open.
- Files affected: `Launch-SystemToolsMenu.vbs`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for core scripts; `Install.ps1 -Action Update -NoExplorerRestart -Force` completed with exit code `0`; installed launcher readback confirmed `scriptPath` points to `C:\Users\joty79\AppData\Local\SystemToolsContext\AddDelPath.ps1` and `wtArgs` uses `-w new nt`.

### Entry - 2026-04-22 (Expose InstallerCore update flow inside PATH Manager)

- Date: 2026-04-22
- Problem: The generated `Install.ps1` had InstallerCore update/download-latest functionality, but the visible PATH Manager TUI did not show the `Update: ...` header status or `Update app` submenu that newer apps expose.
- Root cause: The host menu opens `AddDelPath.ps1`, and that TUI had not adopted the app metadata/update-status pattern from `WinAppManager`.
- Guardrail/rule: Keep app update visibility inside the primary TUI, not as a separate Explorer context-menu verb. The PATH Manager should read `app-metadata.json`, show `Update: <status>` in the header, and include an `Update app` submenu that runs the generated installer flow.
- Files affected: `AddDelPath.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for core scripts; installed update completed with exit code `0`; installed `AddDelPath.ps1` readback confirmed `Update app` and update-status functions are deployed; `reg.exe query` confirmed the mistaken `UpdateSystemTools` context-menu verb is absent.

### Entry - 2026-04-22 (Update status must not rely on version only)

- Date: 2026-04-22
- Problem: A pushed hotfix changed `AddDelPath.ps1`, but installed copies still showed `Up to date` because `app-metadata.json` stayed at `1.0.0`.
- Root cause: The PATH Manager update UI compared only local/remote app versions and did not know which Git commit the installed copy came from.
- Guardrail/rule: Bump `app-metadata.json` for shipped user-facing changes. Also use InstallerCore `state\install-meta.json` commit metadata when present so same-version remote commits can show as `Update available`.
- Files affected: `app-metadata.json`, `AddDelPath.ps1`, `Install.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for core scripts; `app-metadata.json` and `InstallerCore\profiles\SystemTools.json` parsed as JSON; `AddDelPath.ps1 -Action Status -NoPause` smoke test passed; update-status function probe returned `LocalAhead` before the `1.0.1` push because remote still had `1.0.0`.

### Entry - 2026-04-25 (Clear-IconCache.ps1 — New Tool)

- Date: 2026-04-25
- Problem: UWP/Store app icons (Microsoft Store, Settings, etc.) showed a generic PNG file type icon instead of their real logos in Start Menu and Search.
- Root cause: Multi-layer issue — (1) Icaros ExtractImage handler registered on `.png\shellex`, (2) Google DriveFS Thumbnail Provider on `.png\shellex`, (3) orphaned ACDSee Pro 2.5 UserChoice file association (program uninstalled but registry remained), (4) stale icon cache. The Windows shell treated UWP app icon assets (.png files) as regular files and showed the file-type icon instead of rendering the image content.
- Guardrail/rule: When UWP icons break, the fix is REGISTRY (remove shellex entries + orphaned UserChoice), NOT cache. Cache rebuild alone is useless if the registry still points to wrong handlers. After registry fix, a display scaling toggle or reboot triggers the visual refresh. Lock `.png\shellex` with Deny CreateSubKey ACL to prevent future breakage by Google Drive. The context-menu entry must use `.assets\icons\Clear-IconCache.ico`.
- Files affected: `Clear-IconCache.ps1` (NEW), `Launch-ClearIconCache.vbs` (NEW), `.assets\icons\Clear-IconCache.ico` (NEW), `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed for touched/core PowerShell scripts; `app-metadata.json` and `InstallerCore\profiles\SystemTools.json` parsed as JSON; local-source installer update completed with exit code `0`; installed file hash readback passed for `Install.ps1`, `Clear-IconCache.ps1`, `.assets\icons\Clear-IconCache.ico`, `Install-SystemToolsMenu.ps1`, and `app-metadata.json`; patched installed `Launch-ClearIconCache.vbs` points to `%LOCALAPPDATA%\SystemToolsContext\Clear-IconCache.ps1`; registry readback passed for folder, folder-background, and desktop-background `ClearIconCache` command/icon values. BleachBit source comparison confirmed our script is more comprehensive (covers icon cache, AppIconCache, StartMenu TempState, locked file handling — BleachBit only covers thumbcache).

### Entry - 2026-05-11 (Commit-aware Update App migration)

- Date: 2026-05-11
- Problem: The PATH Manager `Update app` status needed the same InstallerCore contract behavior as `SystemCleanup`, including commit/source awareness and safe repo-copy updates.
- Root cause: The previous implementation had partial commit awareness for installed copies but still cached `UpToDate`, did not expose source/dirty state, and treated repo working copies like portable download targets.
- Guardrail/rule: Use the `WT TUI` adapter for `SystemTools`. `Update app` must show local/latest version, local/latest commit, source kind, dirty state, status, and recent output. Installed copies compare `state\install-meta.json` `github_commit` against the latest remote commit. Git repo working copies update only with `git fetch` plus fast-forward and refuse dirty workspaces. Portable non-git copies may use `DownloadLatest -NoSelfRelaunch`. Stale cached `UpToDate` must not be reused when a fresh remote check fails.
- Files affected: `AddDelPath.ps1`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for touched/core PowerShell scripts; update-status probe returned `WorkspaceModified` with local/latest version, commit, source, and dirty state; synthetic cached `UpToDate` was rejected; git fast-forward update probe refused dirty workspace; regenerated `Install.ps1` from `InstallerCore`; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed successfully; installed file hash/readback passed for deployed core files; installed status probe read `state\install-meta.json` and reported `SourceKind=Installed`.

### Entry - 2026-05-12 (System Tools category menu host)

- Date: 2026-05-12
- Problem: The shared `System Tools` context menu had become visually flat and hard to expand because host tools and child repos all wrote direct children under the same parent key.
- Root cause: The early menu model optimized for a few scripts, but the toolbox evolved into multiple separate repos that still needed to feel like one menu.
- Guardrail/rule: Keep `SystemTools` as the only owner of the shared parent and category folders. Built-in host tools live under `Explorer` or `Apps & Windows`; child repos install only their nested child verbs under those category folders. Keep old flat child paths in cleanup lists until installed machines have migrated.
- Files affected: `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`, and companion child profiles.
- Validation/tests run: Profile JSON parse validation passed; generated installers parser-validated; local-source updates completed for `SystemTools`, `TakeOwnership`, `WhoIsUsingThis`, `WinAppManager`, `SystemCleanup`, and `Firewall`; HKCU registry readback confirmed new category keys and representative child commands; old flat HKCU child keys confirmed removed; `RefreshShell.ps1 -NoPause` completed.

### Entry - 2026-05-12 (Ask before changing visible layout model)

- Date: 2026-05-12
- Problem: The visible menu was temporarily flattened without first confirming the layout change, even though the user wanted to keep evaluating the two-category submenu despite border artifacts.
- Root cause: I treated a visual concern as permission to choose a different information architecture.
- Guardrail/rule: For visible context-menu layout changes, distinguish bug fixes from structure changes. Do not switch between nested categories and flat ordered children without explicit user confirmation.
- Files affected: `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Pending reinstall/readback after restoring category layout.

### Entry - 2026-05-12 (Tool Manager under Explorer submenu)

- Date: 2026-05-12
- Problem: The toolbox needs a non-coder-friendly way to check/update the growing set of separate context-menu repos without hunting through each repo.
- Root cause: Keeping tools separate improves maintenance, but update visibility was spread across individual apps/installers.
- Guardrail/rule: Keep `Tool Manager / Updates` as a direct child of the first `System Tools > Explorer` submenu. It may orchestrate generated installers, but must not replace the individual tool repos or change the visible menu layout without confirmation.
- Files affected: `SystemToolsManager.ps1`, `Launch-SystemToolsManager.vbs`, `SystemToolsMenu.reg`, `Install-SystemToolsMenu.ps1`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`, `Install-SystemToolsMenu.ps1`, and generated `Install.ps1`; `InstallerCore` profile JSON parsed; `scripts\Sync-InstallerCore.ps1 -VerifyOnly` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; HKCU registry readback confirmed `Tool Manager / Updates` under file, folder, folder-background, and desktop `Explorer` branches; installed manager `-Action Status -NoPause` completed.

### Entry - 2026-05-13 (Family manager install/repair and parent-preserving host updates)

- Date: 2026-05-13
- Problem: Updating the `SystemTools` host could remove child tool entries, and non-coder install/repair workflows still required visiting each separate repo.
- Root cause: The generated host profile deleted the shared parent `SystemTools` registry trees before rewriting host entries, which also removed child-owned subkeys. The manager also had a hardcoded update-only tool list.
- Guardrail/rule: `SystemTools` host installers must preserve shared parent trees and clean only host-owned legacy child keys. `SystemToolsManager.ps1` reads `.assets\systemtools-family.json`, supports install/repair/update/verify for all family tools, and must not change the visible two-category layout without explicit confirmation.
- Files affected: `SystemToolsManager.ps1`, `.assets\systemtools-family.json`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`, generated `Install.ps1`, and `Install-SystemToolsMenu.ps1`; family config and InstallerCore profile parsed as JSON; `InstallerCore\scripts\Sync-InstallerCore.ps1 -VerifyOnly` passed; local-source host update completed; installed manager `RepairAll` completed for SystemTools, TakeOwnership, WhoIsUsingThis, WinAppManager, SystemCleanup, and Firewall; a second host update completed; installed manager `VerifyMenu` passed for all expected child entries.

### Entry - 2026-05-14 (Windows Utilities category and top-level Tool Manager)

- Date: 2026-05-14
- Problem: The `Explorer` submenu name felt too narrow once it contained ownership and lock-inspection child tools, and `Tool Manager / Updates` was buried one submenu too deep.
- Root cause: The first category split grouped shell/file utilities under `Explorer`, but the user-facing menu evolved beyond Explorer-only actions.
- Guardrail/rule: Use `Windows Utilities` as the first category name for `Refresh Shell`, `Restart Explorer`, `Clear Icon Cache`, `Take Ownership`, and `Who is using this?`. Keep `Tool Manager / Updates` as a direct child of `System Tools`, not inside a category.
- Files affected: `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `.assets\systemtools-family.json`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`, and companion `TakeOwnership` / `WhoIsUsingThis` installers.
- Validation/tests run: Parser validation passed for generated and repo-local installers; profile/family JSON parsed; live local-source install/update and registry readback planned in this change set.

### Entry - 2026-05-14 (Corrected Windows category and bottom manager)

- Date: 2026-05-14
- Problem: The previous menu correction renamed the wrong category: `Explorer` was changed to `Windows Utilities`, while the intended request was to rename `Apps & Windows` to `Windows` and move ownership/lock tools there.
- Root cause: The visual instruction was interpreted from the earlier proposed layout instead of the latest explicit user correction.
- Guardrail/rule: Keep `Explorer` for shell actions only (`Refresh Shell`, `Restart Explorer`, `Clear Icon Cache`). Use `Windows` for app/Windows/file utilities (`Manage Folder PATH...`, `Take Ownership`, `Who is using this?`, `WinAppManager`, `Windows Update Cleanup`, `Firewall Rules`). Keep `Tool Manager / Updates` as the last direct child under `System Tools`, using lexical key `z_ToolManager` plus `CommandFlags=0x20` for separator-before behavior.
- Files affected: `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `.assets\systemtools-family.json`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`, and companion child profiles/installers.
- Validation/tests run: Pending parser validation, local-source installs, manager `VerifyMenu`, and HKCU registry readback after regeneration.

### Entry - 2026-05-14 (Single-file menu and Firewall top-level correction)

- Date: 2026-05-14
- Problem: Right-clicking a single file such as `.md` showed an `Explorer` submenu, and `.exe` Firewall was incorrectly grouped inside `System Tools`.
- Root cause: The host wildcard branch reused the folder category layout even though file targets only need file-safe tools.
- Guardrail/rule: On single-file targets, `System Tools` should expose `Windows` for file-safe child tools (`Take Ownership`, `Who is using this?`) plus the bottom `Tool Manager / Updates`. Do not create `Explorer` for `*\shell\SystemTools`. Firewall stays as a separate top-level `.exe` context-menu entry.
- Files affected: `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `.assets\systemtools-family.json`, `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`, `D:\Users\joty79\scripts\InstallerCore\profiles\Firewall.json`.
- Validation/tests run: Pending parser validation, local-source installs, manager `VerifyMenu`, and HKCU registry readback.

### Entry - 2026-05-14 (Wildcard cleanup must not hit folder surfaces)

- Date: 2026-05-14
- Problem: The single-file cleanup removed the `Explorer` submenu not only from `*\shell\SystemTools`, but also from folder, folder-background, and desktop context-menu surfaces.
- Root cause: A wildcard-style path match was used while editing the generated profile, so the literal `*` branch was treated too broadly.
- Guardrail/rule: When changing wildcard file context-menu behavior, use exact/literal branch checks. `*\shell\SystemTools` gets only `Windows` + `z_ToolManager`; `Directory`, `Directory\Background`, and `DesktopBackground` keep `Explorer`, `Windows`, and `z_ToolManager`.
- Files affected: `Install.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed; local-source update completed; `reg.exe` readback confirmed file/folder/background/desktop/exe surface children and representative child keys; manager `VerifyMenu` passed.

### Entry - 2026-05-14 (SafeMode belongs in generated host profile)

- Date: 2026-05-14
- Problem: `Power Options` / Safe Mode could appear after a hand-run menu script but was not reliably produced by the generated `Install.ps1` / InstallerCore profile path.
- Root cause: `Install-SystemToolsMenu.ps1` had `Add-SafeMode`, while `InstallerCore\profiles\SystemTools.json` and the generated installer registry values did not model the desktop-background `PowerMenu`.
- Guardrail/rule: Desktop-background Safe Mode actions belong in the generated `SystemTools` host profile as `HKCU\Software\Classes\DesktopBackground\Shell\SystemTools\shell\PowerMenu`. Keep it a direct desktop-only child of `System Tools`, and include the original SafeMode actions: `Boot in Safe Mode`, `Boot in Normal Mode`, `Restart`, `Shutdown`, `Sleep`, and `Log Off`.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `.assets\systemtools-family.json`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed for touched SystemTools scripts; JSON validation passed for app metadata, family config, and InstallerCore profile; InstallerCore `Sync-InstallerCore.ps1 -VerifyOnly` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; `SystemToolsManager.ps1 -Action VerifyMenu -NoPause` passed; HKCU registry readback confirmed `PowerMenu` with Safe/Normal/Restart/Shutdown/Sleep/Log Off commands.

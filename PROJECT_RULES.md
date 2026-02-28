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

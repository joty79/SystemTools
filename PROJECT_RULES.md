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

### Entry - 2026-05-24 (WhoIsUsingThis host artifact icon alignment)

- Date: 2026-05-24
- Problem: `WhoIsUsingThis` context-menu icon values were split between `imageres.dll,-102`, the old installed `WhoIsUsingThis.ico`, and the requested `Documents\Icons\whoisusingthis.ico` artwork.
- Root cause: The child InstallerCore profile had not imported the newer artwork, and the host `SystemToolsMenu.reg` still carried stale fallback/old installed icon values.
- Guardrail/rule: Host registry artifacts should mirror child-owned icon filenames after downstream regeneration. For `WhoIsUsingThis`, use the installed `assets\icons\whoisusingthis-custom.ico` copy that was imported from the requested Documents icon.
- Files affected: `SystemToolsMenu.reg`, `CHANGELOG.md`, `PROJECT_RULES.md`, downstream `WhoIsUsingThis`, `D:\Users\joty79\scripts\InstallerCore\profiles\WhoIsUsingThis.json`.
- Validation/tests run: Downstream local-source update completed; HKCU readback confirmed all four active `WhoIsUsingThis` icon values point to installed `assets\icons\whoisusingthis-custom.ico`; imported icon hash matched the requested Documents icon.

### Entry - 2026-05-23 (Clear Icon Cache owns UWP Search PNG icon repair)

- Date: 2026-05-23
- Problem: UWP/MSIX apps such as Codex, Calculator, and Microsoft Store showed the same generic PNG file-type icon only in Start Menu Search.
- Root cause: Windows Search cached package PNG logo assets after `.png` registry state was polluted by a third-party thumbnail handler. The culprit was `DriveFS Thumbnail Provider` under the real `HKCU\Software\Classes\.png\shellex` branch; `Remove-Item` failed with `Requested registry access is not allowed` even elevated, while `reg.exe delete` succeeded.
- Guardrail/rule: Keep this repair in `Clear-IconCache.ps1`, not `RefreshShell.ps1`, because the fix requires registry diagnostics/remediation plus Search AppIconCache rebuild. For `.png\shellex` removal, scan real HKCU/HKLM branches, show diagnostics first, and use `reg.exe delete` as a fallback when the PowerShell registry provider refuses deletion. If only some Start Search app icons redraw immediately, treat the display-scale toggle as a redraw trigger, not as the root fix; document it as the manual no-reboot fallback.
- Files affected: `Clear-IconCache.ps1`, `README.md`, `CHANGELOG.md`, `app-metadata.json`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `Clear-IconCache.ps1`; elevated `-DiagnoseUwpPngIcons` reproduced `DriveFS Thumbnail Provider`; elevated `-FixUwpPngIcons` cleared Search AppIconCache but PowerShell provider deletion failed; direct elevated `reg.exe delete` removed the HKCU `.png\shellex` handler; script updated with `reg.exe` fallback; elevated diagnostic then showed `.png shell extensions: none`. Codex icon redrew immediately, while Calculator needed the display-scale 125% -> 100% -> 125% redraw trigger. Five iconcache database files remained locked and were scheduled through RunOnce, so reboot is still required for complete cache cleanup.

### Entry - 2026-05-21 (Shortcut footer stays compact and grouped)

- Date: 2026-05-21
- Problem: The `Tools Summary` footer became visually noisy at wider terminal widths, and related shortcuts such as `U`/`^U` and `I`/`^I` were separated enough to slow scanning.
- Root cause: The footer used separate wide/medium/narrow text layouts and one shared shortcut-key color for all actions.
- Guardrail/rule: Keep `Tools Summary` action shortcuts in a single compact layout at every width. Group selected/all pairs together (`U`, `^U`; `I`, `^I`) and color shortcut keys by action family so the line remains scannable.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; static footer order/color smoke confirmed compact order `U`, `^U`, `W`, `I`, `^I`, `X`, `R` and distinct key colors; `git diff --check` passed.

### Entry - 2026-05-21 (Selected uninstall is explicit and non-chained)

- Date: 2026-05-21
- Problem: The manager could install, repair, update, and update workspaces from `Tools Summary`, but uninstall still required leaving the selected-row workflow.
- Root cause: There was no selected-row uninstall shortcut or manager wrapper around each tool's generated `Install.ps1 -Action Uninstall` path.
- Guardrail/rule: `X` in `Tools Summary` may uninstall only the selected installed tool after immediate `Y/N` confirmation. Treat uninstall as a terminal explicit action: refresh the selected row afterward, but do not auto-follow additional recommendations and do not modify local workspace files.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; static `X` uninstall handler smoke confirmed selected shortcut, helper, CLI action, and no auto-follow; non-destructive `UninstallTool -ToolName SafeModeOptions -NoPause` smoke completed without uninstalling anything; `git diff --check` passed.

### Entry - 2026-05-21 (Selected remediation chains can auto-follow safe next steps)

- Date: 2026-05-21
- Problem: Fixing one tool could require repeated manual `W`, `U`, and `I` selections even though each completed action made the next safe `Best next` action obvious for the same selected row.
- Root cause: The manager treated every selected action as an isolated command. It refreshed the selected row after an action but did not continue through the safe remediation sequence.
- Guardrail/rule: After the user confirms the initial selected `U`, `W`, or `I`, the manager may auto-follow safe next recommendations for that same tool only when the recommendation maps to `W`, `U`, or `I`. Stop automatically at `No action needed`, failed actions, max-step guard, or any manual/user-review recommendation such as `Enter`.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; synthetic auto remediation chain smoke completed `W -> U -> I -> No action needed`; synthetic manual-stop smoke confirmed dirty/manual review guidance does not auto-run actions; `git diff --check` passed.

### Entry - 2026-05-21 (Clone should explain existing unusable folders)

- Date: 2026-05-21
- Problem: Pressing `W` for a missing workspace could report only `clone destination already exists but is not a usable workspace`, which did not explain whether that was dangerous or how to proceed.
- Root cause: The clone path guard treated any existing destination as a hard stop, even when the directory was empty, and did not print the expected workspace marker files.
- Guardrail/rule: `W` may clone into an existing empty destination folder. If the destination is non-empty but does not contain the configured workspace marker, leave it untouched and print the path, expected marker, and a clear next step to rename/empty/replace the folder.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; existing empty folder clone smoke cloned `joty79/WhoIsUsingThis` into a pre-created empty temp folder and found `Install.ps1`; existing non-empty unusable folder smoke refused clone without modifying the placeholder file; static message smoke confirmed expected-marker and recovery hint text; `git diff --check` passed.

### Entry - 2026-05-20 (Selected actions should refresh only selected row)

- Date: 2026-05-20
- Problem: After every selected `U`, `W`, or `I` action, the manager rescanned every monitored tool, which made single-tool fixes feel slow. Missing workspaces also required the user to clone repos manually before `W` was useful.
- Root cause: `Invoke-ManagerExternalAction` always rebuilt `New-ManagerMenuSnapshot`, and `Invoke-ToolWorkspaceUpdate` skipped `No workspace` instead of resolving a clone destination from `local_paths` or repo roots.
- Guardrail/rule: Selected-row actions should update only the selected tool state/row and recompute summary counters from the existing snapshot. Keep full pool refresh for `R`, all-tools actions, and fallback cases. `W` should clone the configured GitHub repo into the resolved local workspace path when no usable workspace exists.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; synthetic targeted row refresh smoke confirmed only one selected `Get-ToolState` call and refreshed row values; missing-workspace clone smoke cloned `joty79/WhoIsUsingThis` into a temp folder and found `Install.ps1`; `git diff --check` passed.

### Entry - 2026-05-20 (Stale workspaces must not feed local repair)

- Date: 2026-05-20
- Problem: In the VM, tools with `WorkState = Different` could still offer or accept `I` local install/repair, which can reinstall older workspace files and reintroduce old context-menu layout such as the legacy `AppsWindows` category.
- Root cause: Guidance treated installed/menu repair as more urgent than workspace drift, and `Invoke-ToolInstallOrRepair` trusted any resolved local workspace. A prompt string also used `$source?`, which PowerShell parsed as variable `$source?` instead of `$source` plus a literal question mark.
- Guardrail/rule: For tools with a local workspace at a different commit than GitHub, recommend `W` before local repair. Refuse `I` local install/repair while the workspace is `Different` or `Different + dirty`; use `U` for GitHub installed-copy repair/update instead. Use `${variable}` when punctuation immediately follows a PowerShell variable in an expandable string.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; synthetic guidance smoke confirmed `Different` workspace recommends `W` first; prompt smoke confirmed `${source}?` renders correctly; synthetic stale-workspace local repair smoke refused `I` before invoking any installer; temporary HKCU legacy `AppsWindows` key cleanup smoke passed; `git diff --check` passed.

### Entry - 2026-05-20 (ConsoleKeyInfo does not expose VirtualKeyCode)

- Date: 2026-05-20
- Problem: The new `Y/N` confirmation prompt in `v1.0.50` crashed when the user pressed `N`, reporting that property `VirtualKeyCode` could not be found.
- Root cause: The prompt used raw `[Console]::ReadKey($true)`, which returns `System.ConsoleKeyInfo`; unlike the manager's normalized `Read-ManagerKey` object, `ConsoleKeyInfo` has `Key`, `KeyChar`, and modifiers, but no `VirtualKeyCode`.
- Guardrail/rule: Do not mix raw `[Console]::ReadKey()` results with `Read-ManagerKey` property expectations. If a helper reads raw `ConsoleKeyInfo`, test only `Key`, `KeyChar`, or `Modifiers`, or normalize it first.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed; static confirmation-helper smoke confirmed `Confirm-ManagerAction` no longer references `VirtualKeyCode`; `git diff --check` passed.

### Entry - 2026-05-20 (Manager must separate GitHub update, workspace update, and local repair)

- Date: 2026-05-20
- Problem: In an older VM install, `Tools Summary` could recommend `I` for a tool whose menu was missing while the local workspace was behind GitHub. Pressing `I` would repair from the stale local checkout, while a later status refresh crashed in registry child enumeration under StrictMode.
- Root cause: Menu repair guidance outranked installed/workspace drift, the manager had no direct workspace-only update shortcut, action hotkeys ran without an immediate confirmation step, and registry property checks used direct `.PSObject.Properties.Name` access that can fail for some registry provider shapes under StrictMode.
- Guardrail/rule: Keep `U` as installed-copy GitHub update/repair, `W` as workspace-only fast-forward, and `I` as local-source install/repair. If workspace state is `Different`, recommend `U` or `W` before local repair. `U`, `W`, and `I` must ask for immediate `Y/N` confirmation without requiring Enter. Registry/property checks in manager status paths should use a safe property helper instead of direct `.Properties.Name` access.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; read-only `Status` smoke completed without registry/property crash; `MenuStructure` smoke completed without registry/property crash; `UpdateWorkspaceTool -ToolName SystemTools -NoPause` safely refused the dirty current workspace without changing installed files; synthetic guidance smoke for `Installed behind` + missing menu + different workspace recommended `U` before local repair; `git diff --check` passed.

### Entry - 2026-05-18 (Installed-behind must outrank stale dirty-source metadata)

- Date: 2026-05-18
- Problem: After committing/pushing from VS Code, `SystemTools host` showed `Dirty-source install` even though installed commit was behind the now-current workspace/remote commit.
- Root cause: Status precedence checked `source_dirty=true` before falling through to `Installed behind`, so stale dirty-source metadata hid the more actionable update state.
- Guardrail/rule: Installed commit comparison owns update status. If installed metadata commit differs from GitHub remote, show `Installed behind` regardless of `source_dirty`; show `Dirty-source install` only when installed commit equals remote but metadata still says the install came from dirty local source.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; targeted status precedence smoke confirmed dirty-source metadata plus behind installed commit resolves to `Installed behind`; source `Status` smoke showed `SystemTools host` as `Installed behind` for installed `46471e5` vs remote `183c824`; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.49`.

### Entry - 2026-05-18 (Dirty-source install guidance should change after source becomes clean)

- Date: 2026-05-18
- Problem: `SystemTools host` could show `Dirty-source install` while workspace and remote were already clean/current, but the guidance still suggested opening Git review first.
- Root cause: `Actions Needed` treated every dirty-source install the same, even after the source had been committed/pushed and the only remaining issue was stale dirty-source install metadata.
- Guardrail/rule: If `Status` is `Dirty-source install` and `WorkState` is exactly `Current`, recommend `U` to refresh from GitHub/latest and clear dirty-source metadata. Keep Git review first only when the workspace is still dirty, different, missing, or otherwise unresolved.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; targeted guidance smoke confirmed `Dirty-source install` + `Current` recommends `Press U to refresh clean install`; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.48`.

### Entry - 2026-05-18 (Git review pane close hint should be concise and scannable)

- Date: 2026-05-18
- Problem: The review pane included an `Esc works in the manager pane only` hint that was not useful from the review pane and made the close guidance harder to scan.
- Root cause: The pane tried to explain cross-pane key scope instead of showing the actionable close methods.
- Guardrail/rule: For WT review panes, show only actionable pane-local close guidance. Keep the sentence green, and highlight the actual commands/keys (`exit`, `Ctrl+Shift+W`) with the warning/orange color.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; generated review pane parser smoke confirmed the `Esc` hint is gone and `exit` / `Ctrl+Shift+W` use `DarkYellow`; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.47`.

### Entry - 2026-05-18 (Review panes should not be force-killed from manager Esc)

- Date: 2026-05-18
- Problem: Leaving the manager with `Esc` after opening a Git review split pane caused the review pane to show `[process exited with code 4294967295 (0xffffffff)]`.
- Root cause: The manager created a hidden helper process that watched for an `Esc` close signal and then force-killed the interactive review pane's parent PowerShell process. Windows Terminal kept the pane visible as a terminated shell, which is noisier than leaving a normal prompt.
- Guardrail/rule: Do not force-kill interactive WT review panes from another pane. Treat them as normal shells and show explicit close guidance: type `exit` or press `Ctrl+Shift+W`. `Esc` remains a manager-pane navigation key only.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; generated review pane parser smoke confirmed no `Stop-Process` force-kill remains and the `exit` / `Ctrl+Shift+W` close hint is present; source `Status` smoke passed; `.gitattributes` added for repo line-ending policy; touched text files normalized to LF; `git diff --check` passed without LF/CRLF warnings; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.46`.

### Entry - 2026-05-18 (SystemTools repo pins line endings with gitattributes)

- Date: 2026-05-18
- Problem: Git commands repeatedly warned that touched `.md`, `.ps1`, and `.json` files would have LF replaced by CRLF because the machine-level Git config has `core.autocrlf=true`.
- Root cause: The repo had no `.gitattributes`, so global Git line-ending conversion policy controlled the working tree and produced noisy warnings on every diff/status-like check after edits.
- Guardrail/rule: Keep repo-owned text sources normalized through `.gitattributes`: scripts/docs/json use LF, while Windows launcher/integration files such as `.cmd`, `.bat`, `.reg`, and `.vbs` stay CRLF. After changing this policy, normalize touched text files and verify with `git ls-files --eol` plus `git diff --check`.
- Files affected: `.gitattributes`, `CHANGELOG.md`, `PROJECT_RULES.md`, `README.md`, `SystemToolsManager.ps1`, `app-metadata.json`.
- Validation/tests run: `git ls-files --eol` showed touched files as `w/lf attr/text eol=lf`; `git diff --check` passed without LF/CRLF warnings.

### Entry - 2026-05-18 (PowerShell Git upstream refs must be quoted in suggested commands)

- Date: 2026-05-18
- Problem: The Git review pane suggested `git log --oneline --left-right HEAD...@{u}`, which failed from PowerShell with an ambiguous revision error after `@{u}` was misparsed.
- Root cause: `@{...}` has special syntax meaning in PowerShell, so unquoted Git reflog/upstream refs are not safe in displayed commands that users copy or type into pwsh.
- Guardrail/rule: Any suggested Git command shown in PowerShell UI that contains `@{u}`, `@{upstream}`, or similar reflog syntax must quote the revision, for example `git log --oneline --left-right 'HEAD...@{u}'`.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; generated review startup script parser/quote smoke confirmed the displayed upstream comparison is `git log --oneline --left-right 'HEAD...@{u}'`; real `git log --oneline --left-right 'HEAD...@{u}'` ran successfully in PowerShell; source `Status` smoke passed; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.45`.

### Entry - 2026-05-18 (Git review should use WT split pane when launched from manager)

- Date: 2026-05-18
- Problem: `Enter` Git review opened in a separate WT tab instead of the side-by-side pane style already used by `SystemCleanup`.
- Root cause: The manager used `wt new-tab` unconditionally when `wt.exe` was available, instead of checking whether the current process was already hosted inside Windows Terminal.
- Guardrail/rule: Manager-adjacent review/runtime surfaces should use `wt -w 0 split-pane -V` when `$env:WT_SESSION` is present, so the current menu remains visible beside the work pane. Use `new-tab` or a standalone PowerShell fallback only outside WT.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; targeted WT argument smoke confirmed `split-pane -V` for WT-hosted review and `new-tab` fallback outside WT; generated review startup script parser smoke passed; source `Status` smoke passed; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.44`. Live WT split-pane keypress behavior still needs visual confirmation.

### Entry - 2026-05-18 (Generated PowerShell review tab scripts must be literal templates)

- Date: 2026-05-18
- Problem: Pressing `Enter` on a dirty/different `Tools Summary` row crashed before opening the Git review tab with `The variable '$parent' cannot be retrieved because it has not been set.`
- Root cause: The review-tab startup script was built with an expandable here-string that contained intended-literal helper script lines with `$parent`, `$ParentPid`, and `$SignalPath`; `Set-StrictMode -Version Latest` expanded those variables in the manager process before launch.
- Guardrail/rule: Generated PowerShell scripts that contain their own `$` variables must use single-quoted/literal templates with explicit placeholders, and should be parser-validated as generated text before shipping.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for source and installed `SystemToolsManager.ps1`; generated review startup script parser smoke passed for source and installed manager; dirty-row Git review predicate smoke passed; source and installed `Status` smokes passed; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.43`. Live WT Enter/Esc tab behavior still needs visual confirmation.

### Entry - 2026-05-18 (Manager Enter opens selected workspace git review tab)

- Date: 2026-05-18
- Problem: Dirty/different workspaces still required leaving the manager to manually open the right repo before inspecting Git state.
- Root cause: `Actions Needed` could advise Git review, but `Enter` in `Tools Summary` did not create an actionable review surface.
- Guardrail/rule: For selected tools that need Git review and have a workspace path, `Enter` opens a new WT tab in that workspace with suggested first commands. Keep review tabs advisory-only and close the active helper-backed tab when `Esc` leaves `Tools Summary`.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for source and installed `SystemToolsManager.ps1`; source and installed `Status` smokes passed; targeted Git review logic smoke passed; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.42`. Live WT Enter/Esc tab behavior still needs visual confirmation.

### Entry - 2026-05-18 (Manager selected-row action guidance)

- Date: 2026-05-18
- Problem: `Tools Summary` showed state but did not tell the user what to do next for the selected tool, especially when dirty workspaces made update/install choices risky.
- Root cause: The interactive action hub had shortcuts but no per-selection decision guidance, and dirty Git states require context-sensitive human review rather than blind automation.
- Guardrail/rule: Show a selected-row `Actions Needed` section above `Tools Summary` with the best next action and a short Git/workspace note. Keep Git recovery advisory-only: suggest inspection commands and safe direction, but do not auto-commit, auto-rebase, or auto-push dirty source repos.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for source and installed `SystemToolsManager.ps1`; source and installed `Status` smokes passed; targeted `Actions Needed` render smoke passed across compact and wide widths; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed metadata showed version `1.0.41`.

### Entry - 2026-05-18 (Manager WorkState color semantics)

- Date: 2026-05-18
- Problem: `Tools Summary` showed `Current`, `Current + dirty`, `No workspace`, and `No git` in the same row color, making workspace risk hard to scan.
- Root cause: The interactive table colored whole rows by overall status/menu state but did not color the `WorkState` cell by workspace meaning.
- Guardrail/rule: Color `WorkState` semantically without disturbing the selected-row highlight: green for `Current`, yellow for dirty/different states, red for missing workspace/git states, and dim for unknown fallback.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for source and installed `SystemToolsManager.ps1`; source `Status` smoke passed; targeted `Tools Summary` color render smoke passed across compact and wide widths; `git diff --check` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; installed `Status` smoke showed version `1.0.40`.

### Entry - 2026-05-18 (Manager footer must avoid positional shortcut arrays)

- Date: 2026-05-18
- Problem: `Tools Summary` could crash after compact/resized WT redraws with `Index was outside the bounds of the array` in `Write-ManagerShortcutFooter`.
- Root cause: Footer shortcut definitions used nested positional arrays and then accessed `$action[0]` / `$action[1]`, which is too fragile under PowerShell enumeration/shape changes in the TUI redraw path.
- Guardrail/rule: Use object-based shortcut segment definitions (`Key`, `Text`) for interactive manager footers. Do not rely on positional nested arrays for width-sensitive redraw UI.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for source and installed `SystemToolsManager.ps1`; read-only `Status` and `MenuStructure` smokes passed; targeted footer width smoke passed for compact and wide widths; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed.

### Entry - 2026-05-18 (Manager shortcut footer color semantics)

- Date: 2026-05-18
- Problem: Footer shortcuts were hard to scan because the key and its description used the same color, and main-menu refresh duplicated the `Tools Summary` refresh hotkey.
- Root cause: The manager rendered shortcut help as one dim string instead of semantic key/description segments, and `Refresh status snapshot` remained as a main-menu item after `Tools Summary` became the action hub.
- Guardrail/rule: In interactive TUI footers, render the actual key in a stronger semantic color and the description in dim text. Use white arrows for navigation, green `Enter`, red `Esc`, and keep refresh as a footer hotkey in `Tools Summary` rather than a main-menu action.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; read-only `Status` and `MenuStructure` smokes passed; `git diff --check` passed. Interactive footer colors still need live WT visual confirmation.

### Entry - 2026-05-18 (Manager self-update must relaunch)

- Date: 2026-05-18
- Problem: Updating or repairing `SystemTools` from inside `SystemToolsManager.ps1` can replace the manager files while the old manager process is still running.
- Root cause: `SystemToolsManager.ps1` is part of the `SystemTools` package, so refreshing the host package differs from refreshing child tools; the active PowerShell process keeps the old script in memory until it exits.
- Guardrail/rule: If `Tools Summary` successfully updates or installs/repairs the `SystemTools` host, start a fresh WT manager process and exit the old interactive menu. Child tool updates can refresh the snapshot without relaunching the manager.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; read-only `Status`, `Budgets`, and `MenuStructure` smokes passed; `git diff --check` passed. Self-update relaunch was code-reviewed but not executed because it intentionally starts a new WT manager process after install/update.

### Entry - 2026-05-18 (Tools Summary is the manager action hub)

- Date: 2026-05-18
- Problem: Update/install actions were only available from the main menu, forcing extra navigation away from the status table where the selected tool context is already visible.
- Root cause: `Tools Summary` was still read-only and used Enter for a separate details page even though the table already includes the key install/workspace/remote status fields.
- Guardrail/rule: Keep `Tools Summary` as the primary action surface: arrow keys select a row, `U` updates the selected tool, `Ctrl+U` updates all installed tools, `I` installs/repairs the selected tool, `Ctrl+I` installs/repairs all tools, and `R` refreshes the cached snapshot. The footer must show these shortcuts with width-safe text.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; read-only `Status`, `Budgets`, and `MenuStructure` smokes passed; `git diff --check` passed. Action shortcuts were not pressed during automated validation because they intentionally run install/update operations.

### Entry - 2026-05-18 (Manager TUI uses immediate-mode redraw)

- Date: 2026-05-18
- Problem: The `Tools Summary` screen still corrupted after minimize/maximize or repeated WT resizing even after responsive columns were added.
- Root cause: The menu loop used blocking key reads and partial repaint, so mouse-driven resize events were not handled until the next keypress and old scrollback/wrapped lines could reappear.
- Guardrail/rule: Interactive manager screens should use WT synchronized output, full-frame redraw on each navigation/resize frame, resize polling while waiting for keys, and `BufferSize.Height = WindowSize.Height` when possible. Avoid alternate screen for this PowerShell/ConPTY path because it can desync window-size reporting.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; read-only `Status`, `Budgets`, and `MenuStructure` smokes passed; `git diff --check` passed. Interactive WT resize still needs live user verification.

### Entry - 2026-05-18 (Manager Tools Summary must be width-safe)

- Date: 2026-05-18
- Problem: Resizing Windows Terminal broke the `Tools Summary` screen: wide rows wrapped in narrow windows, then arrow-key repaint drew a second table over stale wrapped lines.
- Root cause: The interactive renderer used a fixed wide table and partial repaint with a cached cursor top, without detecting terminal resize or switching layouts when the current width could not fit all columns.
- Guardrail/rule: `SystemToolsManager.ps1` interactive tables must be responsive to `RawUI.WindowSize`: never print visible lines wider than the current terminal, switch to reduced/compact columns below wide-table thresholds, and full-clear/redraw after any terminal width/height change.
- Files affected: `SystemToolsManager.ps1`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; read-only `Status`, `Budgets`, and `MenuStructure` smokes passed. Interactive resize behavior still needs real WT verification by user.

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
- Guardrail/rule: Desktop-background Safe Mode actions belong in the generated `SystemTools` host profile as flat commands under `HKCU\Software\Classes\DesktopBackground\Shell\SystemTools\shell\Windows\shell\z10_BootSafe` through `z15_LogOff`. Keep them flat because Explorer did not render direct `PowerMenu`, direct `SafeModeOptions`, or nested `Windows\shell\SafeModeOptions` cascades despite correct registry readback. Include the original SafeMode actions: `Boot in Safe Mode`, `Boot in Normal Mode`, `Restart`, `Shutdown`, `Sleep`, and `Log Off`, and clean the earlier cascade keys.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `.assets\systemtools-family.json`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed for touched SystemTools scripts; JSON validation passed for family config and InstallerCore profile; InstallerCore `Sync-InstallerCore.ps1 -VerifyOnly` passed; local-source `Install.ps1 -Action Update -PackageSource Local -Force -NoExplorerRestart` completed; `SystemToolsManager.ps1 -Action VerifyMenu -NoPause` passed; HKCU registry readback confirmed flat `Windows\shell\z10_BootSafe` through `z15_LogOff` commands and confirmed the earlier cascade keys were removed; Explorer restarted.

### Entry - 2026-05-14 (Desktop menu item limit and child installer discipline)

- Date: 2026-05-14
- Problem: Desktop background `System Tools > Windows` exceeded Explorer's static menu rendering limit after child installers re-added `Take Ownership` and `Who is using this?`, causing SafeMode/power entries to disappear; category icons also regressed to `imageres` fallbacks and `Firewall Rules` reappeared under `System Tools`.
- Root cause: `SystemTools` and child profiles were all contributing desktop-background children, and `TakeOwnership` / `WhoIsUsingThis` profiles still owned desktop-background entries that do not make sense without a selected item.
- Guardrail/rule: Desktop background `System Tools > Windows` must stay lean: keep desktop-appropriate entries only (`SystemCleanup`, `WinAppManager`, SafeMode/power actions). Do not register `TakeOwnership`, `WhoIsUsingThis`, or `FirewallRules` there. Keep `Explorer` and `Windows` category icons on repo-owned `.assets\icons\explorer.ico` and `.assets\icons\windows.ico`.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `.assets\systemtools-family.json`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, child `TakeOwnership` / `WhoIsUsingThis` generated installers, and `InstallerCore` profiles.
- Validation/tests run: Parser/profile validation passed; local-source updates completed for `SystemTools`, `TakeOwnership`, and `WhoIsUsingThis`; registry readback confirmed desktop-background `TakeOwnership`, `WhoIsUsingThis`, and `FirewallRules` keys are absent, category icons use installed `.ico` files, and SafeMode flat entries exist.

### Entry - 2026-05-14 (Desktop right-click uses Directory Background)

- Date: 2026-05-14
- Problem: The visible desktop right-click `System Tools > Windows` menu still showed `Take Ownership` / `Who is using this?` and did not show SafeMode/power entries even after the `DesktopBackground` branch was fixed.
- Root cause: On this host the visible desktop right-click path is `HKCU\Software\Classes\Directory\Background\shell\SystemTools`, while the earlier fix only pruned and populated `DesktopBackground\Shell\SystemTools`.
- Guardrail/rule: For desktop-visible menu fixes, validate both `Directory\Background` and `DesktopBackground`. SafeMode/power entries must exist under `Directory\Background\shell\SystemTools\shell\Windows\shell\z10_BootSafe` through `z15_LogOff`, and `TakeOwnership` / `WhoIsUsingThis` must not register there.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`, child `TakeOwnership` / `WhoIsUsingThis` generated installers, and `InstallerCore` profiles.
- Validation/tests run: Parser/profile validation passed; local-source updates completed for `SystemTools`, `TakeOwnership`, and `WhoIsUsingThis`; registry readback confirmed `Directory\Background` has SafeMode/power entries and no `TakeOwnership` / `WhoIsUsingThis`; `SystemToolsManager.ps1 -Action VerifyMenu -NoPause` passed; Explorer restarted with execution-policy bypass.

### Entry - 2026-05-17 (CRITICAL: Explorer 16-Entry Cascade Hard Limit — Proven)

- Date: 2026-05-17
- Problem: SafeMode/power entries silently disappeared from `System Tools > Windows` desktop menu after child installers added entries that pushed the total past an unknown limit. No error, no warning — entries simply did not render. Diagnosis took a full day across multiple agents (Claude, Gemini) and multiple architectures.
- Root cause: Windows 10 Explorer enforces an undocumented **hard limit of 16 visible entries per cascade level** in static registry-based context menus. The limit counts submenu headers AND leaf commands together. Entries beyond 16 are silently dropped. This applies to ALL static registry architectures: nested `shell` keys, `ExtendedSubCommandsKey` (HKCU reusable), and HKLM `CommandStore` + `SubCommands` verb lists. None bypass the limit.
- Guardrail/rule: **NEVER exceed 16 entries (menus + commands) at any single cascade level.** Separators (`CommandFlags` `0x20`/`0x40`) are FREE and do not count. Each cascade depth level has its own independent 16-budget. If a category grows past 16, split it into sub-categories. Always count entries before adding to any cascade level. Only COM `IExplorerCommand` extensions remain untested as a potential bypass. Current safe budgets: Root=3/16, Explorer=3/16, Windows(desktop)=10/16.
- Evidence: 10 independent dummy tests (T1–T10) across 6 architectures with 100% consistency. Full documentation: `docs/AG_CASCADE_LIMIT_TESTS.md`, `docs/STATIC_CASCADE_DUMMY_TESTS.md`, `docs/EXTENDED_SUBCOMMANDSKEY_DUMMY_TESTS.md`.
- Files affected: `docs/AG_CASCADE_LIMIT_TESTS.md` (NEW), `GEMINI.md` (rule 54 added), `PROJECT_RULES.md`.
- Validation/tests run: All 10 dummy tests confirmed by user visual inspection; all dummy registry keys cleaned up after testing (HKCU `z_AgDummyT1`–`z_AgDummyT10`, `AgDummy` tree, HKLM `CommandStore\shell\AgDummy.Item01`–`AgDummy.Item20`).

### Entry - 2026-05-17 (Restore stable SystemTools layout; SafeMode separate)

- Date: 2026-05-17
- Problem: Folding SafeMode/power actions into `System Tools > Windows` made the registry cascade fragile and caused repeated menu truncation/confusion while testing the 16-entry Explorer limit.
- Root cause: `SystemTools`, SafeMode/power actions, and child tool installers were all competing for the same static registry cascade level. Even after proving the per-level limit, keeping SafeMode inside the shared Windows submenu left the menu too close to the failure mode.
- Guardrail/rule: Keep the registry-based `SystemTools` layout stable and small: root `Explorer`, `Windows`, and `Tool Manager / Updates`; `Explorer` owns `Refresh Shell`, `Restart Explorer`, `Clear Icon Cache`; `Windows` owns `Firewall Rules`, `Manage Folder PATH...`, `Windows Update Cleanup`, `Take Ownership`, `Who is using this?`, and `WinAppManager`. Do not put SafeMode/power actions back inside `SystemTools`; build them as a separate menu until a COM/DLL implementation exists.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `SystemToolsMenu.reg`, `.assets\systemtools-family.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, and related `InstallerCore` / child-tool profiles.
- Validation/tests run: Parser validation passed for generated installers; local-source updates completed for `SystemTools`, `TakeOwnership`, and `WhoIsUsingThis`; HKCU readback confirmed both `Directory\Background` and `DesktopBackground` Windows submenus contain the six expected entries and no `z10_BootSafe` through `z15_LogOff` leftovers.

### Entry - 2026-05-17 (SafeMode top-level menu and PATH icon)

- Date: 2026-05-17
- Problem: SafeMode needed to return without consuming the `SystemTools > Windows` cascade budget, and `Manage Folder PATH...` needed the custom icon from `Documents\Icons\managefolderpath.ico`.
- Root cause: Nesting SafeMode inside `SystemTools` had caused repeated truncation. Reusing the old `folder_to_path.ico` filename also risks Explorer icon-cache stickiness.
- Guardrail/rule: Keep `Safe Mode Options` as a separate top-level desktop/folder-background cascade with exactly two children: `Boot in Normal Mode` and `Boot in Safe Mode`. Keep `SystemTools` itself at root=3, Explorer=3, Windows=6. Use `.assets\icons\managefolderpath.ico` for `PathManager`.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `.assets\icons\managefolderpath.ico`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed; profile JSON validation passed; local-source update completed; HKCU readback confirmed PathManager icon values, separate SafeMode menu values, SystemTools level counts, and SafeMode child count; `SystemToolsManager.ps1 -Action VerifyMenu -NoPause` passed; Explorer restarted.

### Entry - 2026-05-17 (SafeMode is Shift-only)

- Date: 2026-05-17
- Problem: `Safe Mode Options` should be available but not visible on every normal desktop/folder-background right-click.
- Root cause: The separate SafeMode root keys lacked the registry `Extended` value.
- Guardrail/rule: `Safe Mode Options` root keys under `Directory\Background\shell` and `DesktopBackground\Shell` must include empty `Extended` values so they appear only with Shift+right-click.
- Files affected: `Install.ps1`, `Install-SystemToolsMenu.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\SystemTools.json`.
- Validation/tests run: Parser validation passed; profile JSON validation passed; local-source update completed; HKCU readback confirmed `Extended` on both SafeMode root keys; `SystemToolsManager.ps1 -Action VerifyMenu -NoPause` and `InstallerCore` verify passed; Explorer restarted.

### Entry - 2026-05-17 (Tool Manager provenance-aware status)

- Date: 2026-05-17
- Problem: `SystemToolsManager.ps1` showed a vague `Update available` for tools such as `Windows Update Cleanup`, even when the workspace was already at the remote commit and the installed files appeared to contain dirty-source changes later committed upstream.
- Root cause: The manager compared only the installed `state\install-meta.json` `github_commit` to GitHub `master`, so installs made from dirty local workspaces looked simply behind. The Firewall verify path also still expected the removed top-level `exefile\shell\FirewallManager` key.
- Guardrail/rule: Manager status must separate installed provenance (`Inst`), local workspace HEAD (`Work`, `*` when dirty), and GitHub HEAD (`Remote`). If `install-meta.json` says `source_dirty = true`, label it as `Dirty-source install` instead of generic update availability. Provide a read-only inspect path before install/repair/update so the user can see installed metadata, workspace state, remote state, and status meaning for one tool. Firewall verification should target the supported shared `SystemTools > Windows > Firewall Rules` key.
- Files affected: `SystemToolsManager.ps1`, `.assets\systemtools-family.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed for `SystemToolsManager.ps1`; family JSON parsed; `SystemToolsManager.ps1 -Action Status -NoPause` showed distinct `Inst`/`Work`/`Remote` columns; `SystemToolsManager.ps1 -Action InspectTool -ToolName SystemCleanup -NoPause` explained the dirty-source install state; `SystemToolsManager.ps1 -Action VerifyMenu -NoPause` passed without install/repair/update.

### Entry - 2026-05-17 (Manager scope expands beyond SystemTools cascade)

- Date: 2026-05-17
- Problem: The 16-item Explorer static cascade limit means future tools cannot all live under `System Tools`, but they still need the same status/update/registry monitoring as the tools inside the shared menu.
- Root cause: The original manager model treated the `SystemTools` cascade as the family boundary. After proving the cascade limit, standalone top-level menus and host-owned surfaces became part of the same operational family.
- Guardrail/rule: Treat `System Tools` as one managed surface, not the boundary of management. `SystemToolsManager.ps1` should monitor repo-backed standalone tools such as `mklink`, host-owned surfaces such as `Safe Mode Options`, and future external menus through `.assets\systemtools-family.json` surfaces and budget groups. Add read-only surface and 16-item budget views before adding any more install/update actions.
- Files affected: `SystemToolsManager.ps1`, `.assets\systemtools-family.json`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON parsed; `Status`, `Surfaces`, `Budgets`, `InspectTool -ToolName mklink`, `InspectTool -ToolName SafeModeOptions`, and `VerifyMenu` ran with `-NoPause` without install/repair/update. `mklink` verified as standalone InstallerCore app; `Safe Mode Options` verified as host-owned monitored surface.

### Entry - 2026-05-17 (PowerShell foreach pipeline parser trap)

- Date: 2026-05-17
- Problem: Ad-hoc PowerShell readback snippets repeatedly hit `ParserError: An empty pipe element is not allowed` when piping directly after a multi-line `foreach {}` block.
- Root cause: The shell parsed the closing brace and following pipeline ambiguously in inline command text.
- Guardrail/rule: For multi-line object-building snippets, assign the loop output to `$rows = foreach (...) { ... }` first, then pipe `$rows | Format-Table -AutoSize`. Avoid direct `} | Format-Table` patterns in inline verification commands.
- Files affected: `PROJECT_RULES.md`.
- Validation/tests run: Subsequent readback snippets using `$rows = foreach (...) { ... }` completed without parser errors.

### Entry - 2026-05-17 (Manager UI template and ContextLens monitoring)

- Date: 2026-05-17
- Problem: `SystemToolsManager.ps1` had a custom arrow-key menu instead of the shared PowerShell UI template, and `ContextLens` was missing from the managed external-tool inventory.
- Root cause: The first manager expansion focused on status provenance and standalone surfaces, but did not reuse the canonical `PS_UI_Blueprint.psm1` pattern already used by `AddDelPath.ps1` and `Toggle-PSRemoting.ps1`.
- Guardrail/rule: Interactive `.ps1` tools in this repo should load `.codex\tools\PS_UI_Blueprint.psm1` and use `Write-UiBanner` / `Invoke-ArrowMenu` for main menus. `SystemToolsManager.ps1` is responsible for monitoring external managed menus such as `mklink`, `ContextLens`, and host-owned surfaces such as `Safe Mode Options`, even when they cannot live inside the `System Tools` cascade.
- Files affected: `SystemToolsManager.ps1`, `.assets\systemtools-family.json`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; `PS_UI_Blueprint.psm1` import exposed `Invoke-ArrowMenu`; family JSON and app metadata JSON parsed; `Status`, `Surfaces`, `Budgets`, `InspectTool -ToolName ContextLens`, and `VerifyMenu` ran with `-NoPause` without install/repair/update. `ContextLens` verified as a standalone InstallerCore app with installed metadata, workspace HEAD, and GitHub `master` all at commit `56ec4df`.

### Entry - 2026-05-17 (Manager menu must not rescan on arrow keys)

- Date: 2026-05-17
- Problem: The first `PS_UI_Blueprint.psm1` conversion made `SystemToolsManager.ps1` slow and visually broken: startup and every arrow-key movement flashed through a black/full redraw and rescanned status.
- Root cause: `Invoke-ArrowMenu` rebuilds its `HeaderBlock` on every frame, and the manager header called `Get-StatusRows`, which performs registry checks and GitHub/workspace commit reads.
- Guardrail/rule: Expensive manager status belongs in a cached snapshot. Arrow-key movement must repaint only the menu block in place with `SetCursorPosition`; only explicit refresh (`R`) should rebuild the registry/git status snapshot.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; read-only `Status`, `VerifyMenu`, and `Budgets` smokes completed without install/repair/update.

### Entry - 2026-05-17 (Manager UI should match WinAppManager composition)

- Date: 2026-05-17
- Problem: After the redraw fix, `SystemToolsManager.ps1` was faster but still looked far from WinAppManager because it displayed a raw wide status table above a plain numbered menu.
- Root cause: The previous UI used the low-level blueprint mechanics but ignored the actual WinAppManager composition: versioned three-line banner, compact summary, section dividers, semantic action colors, and a focused menu list.
- Guardrail/rule: For manager-style PowerShell menus, treat WinAppManager as the visual reference, not just `PS_UI_Blueprint.psm1` helpers. Keep raw diagnostic tables in explicit read-only views such as `Status`; the main menu should show a compact summary and colored action list.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed after the UI composition refactor; family JSON and app metadata JSON parsed; read-only `Status` smoke completed without install/repair/update.

### Entry - 2026-05-17 (Manager key handling and surfaces summary)

- Date: 2026-05-17
- Problem: `SystemToolsManager.ps1` arrow movement could skip one menu row, `Esc` from nested tool selection still fell through to a `Press Enter` pause, and `Show managed surfaces` no longer showed the installed/workspace/remote commit summary.
- Root cause: The manager used mixed input paths: a local cached main-menu renderer plus `Invoke-ArrowMenu` for nested tool selection, while some terminal hosts emitted duplicate arrow key events quickly enough to look like a two-row jump. The surface view had also been split away from the provenance table too aggressively.
- Guardrail/rule: Manager menus should use one local key-reading path with duplicate-arrow debounce for both main menu and nested selectors. `Esc` in a nested selector is a true cancel and returns to the parent menu without an extra pause. Surface/budget monitoring views should keep provenance visible when it helps explain what is installed, what the workspace has, and what GitHub has.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; read-only `Status`, `Surfaces`, and `VerifyMenu` smokes completed without install/repair/update. Interactive arrow/Esc behavior requires a real terminal pass by the user because this session cannot press keys inside the launched Windows Terminal UI.

### Entry - 2026-05-17 (Manager should explain itself)

- Date: 2026-05-17
- Problem: The manager still exposed implementation words such as `surfaces`, separated summary from inspection, and rescanned registry/git state when opening read-only views even if no install/update/repair had happened.
- Root cause: The UI was organized around internal implementation concepts instead of the user's mental model: "what tools do I have?" and "where are their context-menu entries?" Read-only screens were also calling scan functions directly instead of consuming the already-built startup snapshot.
- Guardrail/rule: The interactive manager should center on `Tools Summary` and `Menu Entries`. `Tools Summary` must be navigable and Enter should inspect the selected tool. `Menu Entries` should combine verification state with context-menu entry/count information. Read-only views must use the cached startup snapshot; only explicit refresh or real install/update/repair should rescan.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `Status`, `MenuEntries`, `Budgets`, and `VerifyMenu` read-only smokes completed without install/repair/update; `git diff --check` passed. Interactive arrow/Esc behavior still needs a real terminal pass by the user because this session cannot press keys inside the TUI.

### Entry - 2026-05-17 (Menu Structure tree view)

- Date: 2026-05-17
- Problem: Separate `Menu Entries` and `Check 16-item menu limits` screens made the manager harder to understand because menu placement and budget health were split apart.
- Root cause: The UI mirrored internal data tables instead of showing the context-menu structure as the user sees it in Explorer.
- Guardrail/rule: Combine menu entry verification and 16-item budget status into one `Menu Structure` view. Render groups in a directory-tree style outline, show `used/free/status` for each group, and list each entry's tool, scope, visibility, item count, and menu verification state.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `SystemToolsManager.ps1 -Action MenuStructure -NoPause` rendered the tree-style combined view; `git diff --check` passed. No install/repair/update was run.

### Entry - 2026-05-17 (Root menus are not submenu budgets)

- Date: 2026-05-17
- Problem: `Menu Structure` showed labels such as `DesktopBackground.Root OK (3/16 used, 13 free)`, which implied the desktop root menu itself had three visible entries and was governed by the same 16-item submenu budget.
- Root cause: The budget calculation reused the largest child submenu count for root groups. For desktop, `3` came from `ContextLens` child items, not from top-level desktop entries. The desktop right-click menu also includes entries sourced from `Directory\Background`, such as `mklink`.
- Guardrail/rule: Do not show `x/16` budget labels for root context-menu groups. Root groups should show monitored entry counts, and the manager should include a `Desktop right-click` summary for monitored tools that appear there, including entries sourced from `Directory\Background`. Keep 16-item warnings for nested static submenus/cascades.
- Files affected: `SystemToolsManager.ps1`, `.assets\systemtools-family.json`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `SystemToolsManager.ps1 -Action MenuStructure -NoPause` showed `Desktop right-click` with four monitored entries (`ContextLens`, `mklink`, `Safe Mode Options`, `System Tools`) and no `x/16` root-budget label. No install/repair/update was run.

### Entry - 2026-05-17 (Menu Structure labels should not repeat context)

- Date: 2026-05-17
- Problem: `Menu Structure` rows repeated context already present in the section header, such as `Desktop ContextLens menu - ContextLens` under `DesktopBackground.Root`.
- Root cause: The renderer used the internal surface name as the primary row label, even though the group title already says whether the row is desktop, folder background, or file-specific.
- Guardrail/rule: In `Menu Structure`, use the human tool name as the primary tree row label and move technical/context detail to secondary metadata only when useful. Highlight tool names with the gold/orange accent for scanability.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `SystemToolsManager.ps1 -Action MenuStructure -NoPause` showed simplified gold/orange tool-name labels without repeated `Desktop/Folder background ... menu` text; `git diff --check` passed. No install/repair/update was run.

### Entry - 2026-05-17 (Menu Structure should use human targets)

- Date: 2026-05-17
- Problem: `Menu Structure` still exposed registry-style groups such as `Directory.Folder.Root`, `PngFile.Root`, and `SystemTools.Root`, forcing the user to translate registry roots into actual right-click scenarios.
- Root cause: The renderer grouped directly by internal `budget_group` values instead of the menu surfaces a human sees in Explorer.
- Guardrail/rule: Group `Menu Structure` by human targets first: `Right-click on Desktop / empty folder space`, `Right-click on a folder`, `Right-click on a PNG file`, and `Inside System Tools`. Keep registry/root names out of the primary labels; show technical information only as secondary details when needed.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `SystemToolsManager.ps1 -Action MenuStructure -NoPause` rendered human target sections without registry-style primary labels; `git diff --check` passed. No install/repair/update was run.

### Entry - 2026-05-17 (Menu Structure should show actual SystemTools children)

- Date: 2026-05-17
- Problem: `Right-click on a folder` omitted `System Tools`, and `Inside System Tools` hid the actual root children (`Explorer`, `Windows`, `Tool Manager / Updates`) behind a generic host entry.
- Root cause: The human target renderer treated `SystemTools.Root` only as an internal surface instead of both a folder right-click entry and a menu container with children.
- Guardrail/rule: Include `System Tools` under `Right-click on a folder`. In `Inside System Tools`, read the cached root children and show `Explorer`, `Windows`, and `Tool Manager / Updates` directly, with submenu budget counts for children that contain nested entries.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `SystemToolsManager.ps1 -Action MenuStructure -NoPause` showed `System Tools` under `Right-click on a folder` and showed `Explorer`, `Windows`, and `Tool Manager / Updates` under `Inside System Tools`. No install/repair/update was run.

### Entry - 2026-05-17 (SystemTools children differ per target)

- Date: 2026-05-17
- Problem: `Inside System Tools` implied a single root layout, but `System Tools > Windows` has different child counts on folder, folder-background/desktop, and file targets.
- Root cause: The manager read only `Directory\shell\SystemTools\shell` for the `Inside System Tools` view. Actual Explorer context roots have separate registry trees for folder item, folder/desktop background, and file targets.
- Guardrail/rule: Render `Inside System Tools` per human target: desktop/empty folder space, folder, and file. Read each target's actual `SystemTools\shell` children from the cached snapshot and show the submenu counts independently.
- Files affected: `SystemToolsManager.ps1`, `.assets\systemtools-family.json`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Parser validation passed; family JSON and app metadata JSON parsed; `SystemToolsManager.ps1 -Action MenuStructure -NoPause` showed `Inside System Tools` split into desktop/empty folder space (`Windows` 6/16), folder (`Windows` 5/16), and file (`Windows` 3/16); `git diff --check` passed. No install/repair/update was run.

### Entry - 2026-05-17 (SystemTools budget must be shown per popup)

- Date: 2026-05-17
- Problem: `Inside System Tools` temporarily reported a combined tree total (`root entries + submenu children`), which incorrectly implied a new submenu with 4 child items should disappear when the combined number exceeded 16.
- Root cause: A first live probe was added only under `DesktopBackground`, while the visible desktop menu also used the `Directory\Background` branch. That made the test result look like a 17-entry tree failure when it was actually the wrong branch.
- Guardrail/rule: Show the 16-item static cascade budget per visible popup. The `System Tools` root popup counts only its visible branches/direct items (`Explorer`, `Windows`, `Tool Manager / Updates`, etc.). Each submenu popup (`Explorer`, `Windows`, a future `Test` menu, etc.) has its own 16-item budget. Separators remain free.
- Files affected: `SystemToolsManager.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Temporarily added `zzz_LimitTest` with 2 and then 4 child commands under both `DesktopBackground\Shell\SystemTools\shell` and `Directory\Background\shell\SystemTools\shell`; user visually confirmed the 4-child test branch and all child items appeared. Cleanup removed both temporary registry branches successfully. No install/repair/update was run.

### Entry - 2026-05-18 (CORRECTION: 16-Entry Limit Is DEPTH-FIRST GLOBAL, Not Per-Popup)

- Date: 2026-05-18
- Problem: Previous Codex entry concluded the 16-limit was per-popup (each submenu has its own 16-budget). User believed a 4th submenu with 4 children made 17 total visible. On re-test, `z_ToolManager` had silently disappeared — user simply didn't notice.
- Root cause: The 16-entry limit counts entries DEPTH-FIRST across the ENTIRE cascade tree (not per popup). Explorer walks registry keys alphabetically, descends into each submenu's children BEFORE moving to the next sibling, and stops at entry 16. T11: 18 registered entries -> exactly 16 visible, `z_ToolManager` and last dummy child silently cut.
- Guardrail/rule: ALWAYS count the GLOBAL depth-first total of the cascade tree (headers + all children recursively). Current SystemTools uses 12 of 16 budget (4 remaining). Previous T9 result ("per-level independence") needs re-verification.
- Files affected: `AG_CASCADE_LIMIT_TESTS.md`, `GEMINI.md` (guardrail #54), `PROJECT_RULES.md`.
- Validation/tests run: T11 test script (`DummyTest-T11-Verify18.ps1`) added 5 children to real SystemTools cascade; user screenshot confirmed exactly 16 visible (3 root headers + 3+6+4 children); dummy removed and cascade restored to 12/16.

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

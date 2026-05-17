# Antigravity Cascade Limit Tests — Definitive Results

Date: 2026-05-17
Host: Windows 10 Explorer, `Directory\Background` desktop right-click menu.
Tester: Antigravity (Claude Opus 4.6) + user visual confirmation.

## Purpose

Independent verification of the static registry cascade rendering limit observed in previous Claude/Gemini tests documented in:

- `STATIC_CASCADE_DUMMY_TESTS.md`
- `EXTENDED_SUBCOMMANDSKEY_DUMMY_TESTS.md`

All tests used isolated dummy roots with harmless commands (`cmd.exe /c exit /b 0`).

## Complete Test Results (T1–T10)

| Test | Architecture | Registry Shape | Visible Menus | Visible Items | **Total Visible** |
|------|-------------|----------------|---------------|---------------|-------------------|
| T1 | Static nested `shell` | 3×3 = 12 | 3 | 3+3+3 = 9 | **12** ✅ |
| T2 | Static nested `shell` | 4×4 = 20 | 4 | 4+4+4+0 = 12 | **16** 🔒 |
| T3 | Static nested `shell` | 3×8 = 27 | 2 | 8+6 = 14 | **16** 🔒 |
| T4 | `ExtendedSubCommandsKey` | 4×4 = 20 | 4 | 4+4+4+0 = 12 | **16** 🔒 |
| T5 | `ExtendedSubCommandsKey` | 3×8 = 27 | 2 | 8+6 = 14 | **16** 🔒 |
| T6 | Static flat (no subs) | 20 flat | — | 16 | **16** 🔒 |
| T7 | Static flat + separators | 16 + `CommandFlags` | — | 16 + 2 sep lines | **16** 🔒 |
| T8 | Static flat boundary | 17 flat | — | 16 | **16** 🔒 |
| T9 | Per-level independence | 3×16 = 51 | 3 | 15 per submenu | **3 + 15×3** ✅ |
| T10 | HKLM `CommandStore` + `SubCommands` verb list | 20 verbs | — | 16 | **16** 🔒 |

## Proven Conclusions

### 1. Hard Limit = 16 Visible Entries Per Cascade Level

```text
Windows 10 Explorer enforces a hard rendering limit of 16 visible entries
per cascade level in static registry-based context menus.

This was proven across 10 independent tests with 100% consistency.
Every test that exceeded 16 was truncated to exactly 16.
```

### 2. The Limit Counts ALL Entry Types Together

```text
The 16-entry budget includes BOTH:
  - Submenu headers (entries with cascade arrows)
  - Leaf command items (entries with direct commands)

They share the same budget. Examples:
  T2: 4 menus + 12 items = 16
  T3: 2 menus + 14 items = 16
  T6: 0 menus + 16 items = 16
```

### 3. Separators Do NOT Count Toward the Budget

```text
T7: 16 items registered with CommandFlags=0x20 on items 6 and 12.
Result: All 16 items rendered PLUS 2 visible separator lines.
Separators are FREE — they do not consume a budget slot.
```

### 4. ExtendedSubCommandsKey Does NOT Bypass the Limit

```text
T4 vs T2: identical results (4 menus, 4+4+4+0 items)
T5 vs T3: identical results (2 menus, 8+6 items)

ExtendedSubCommandsKey is a cleaner architecture but does not
increase the rendering budget on Windows 10.
```

### 5. HKLM CommandStore + SubCommands Verb List Does NOT Bypass the Limit

```text
T10: 20 named verbs created in HKLM CommandStore, referenced via
semicolon-separated SubCommands value. Registry readback confirmed
all 20 verbs existed.

Result: Only 16 verbs rendered visually. The CommandStore architecture
does not bypass the 16-entry limit.
```

### 6. Each Cascade Level Has an Independent Budget

```text
T9: 3 menus at root level (3 of 16 budget = OK).
Each submenu contained 16 registered items.
Each submenu independently rendered 15 items (likely 16 minus
screen height constraint).

The 16-limit is enforced at each individual cascade popup level,
not as a global cap across all nesting depths. Parent and child
levels do not share the same budget.
```

### 7. Truncation Is Sequential, Not Random

```text
Explorer renders entries in registry key order until the budget is exhausted.
It does not skip or randomize. The last entries in sort order are the ones cut.

T3 example: Menu01 got all 8 items, Menu02 got only 6 (budget ran out at 16),
Menu03 was hidden entirely.
```

## Summary of What Bypasses the Limit

| Architecture | Bypasses 16-limit? |
|-------------|-------------------|
| Static nested `shell` keys | ❌ No |
| `ExtendedSubCommandsKey` (HKCU reusable) | ❌ No |
| `ExtendedSubCommandsKey` (inline) | ❌ No (did not even cascade) |
| HKLM `CommandStore` + `SubCommands` verb list | ❌ No |
| `CommandFlags` separators | ✅ Free (not counted) |
| Nesting deeper (more cascade levels) | ✅ Each level = own budget |

## Practical Implications for SystemTools

### Safe Budget Per Cascade Level

```text
Maximum safe entries per cascade popup = 16
This includes both submenu folders AND leaf commands.
Separators (CommandFlags 0x20/0x40) are free.
```

### Current SystemTools Layout Guidance

```text
System Tools (root cascade)
├── Explorer (submenu)         → counts as 1
├── Windows (submenu)          → counts as 1
└── Tool Manager / Updates     → counts as 1
                               ─────────────
                               Total: 3 of 16 budget (SAFE)

Inside "Explorer" submenu:
├── Refresh Shell              → 1
├── Restart Explorer           → 1
└── Clear Icon Cache           → 1
                               ─────────────
                               Total: 3 of 16 budget (SAFE)

Inside "Windows" submenu (desktop background):
├── Manage Folder PATH...      → 1
├── System Cleanup             → 1
├── WinAppManager              → 1
├── Windows Update Cleanup     → 1
├── ── separator ──            → FREE
├── Boot in Safe Mode          → 1
├── Boot in Normal Mode        → 1
├── Restart                    → 1
├── Shutdown                   → 1
├── Sleep                      → 1
├── Log Off                    → 1
                               ─────────────
                               Total: 10 of 16 budget (SAFE, 6 remaining)
```

### Maximum Expansion Room

```text
Root level:          3 used, 13 remaining  → can add up to 13 more categories
Explorer:            3 used, 13 remaining  → can add up to 13 more tools
Windows (desktop):  10 used,  6 remaining  → can add up to 6 more entries
Separators:         Unlimited (free)       → use freely for visual grouping
```

### Design Rules Going Forward

```text
1. Never exceed 16 entries (menus + commands) at any single cascade level.
2. Use separators (CommandFlags) freely — they don't count.
3. If a category grows past 16, split it into sub-categories.
4. No registry architecture (static shell, ExtendedSubCommandsKey,
   CommandStore) can bypass this limit.
5. Only IExplorerCommand/IContextMenu COM extensions remain untested
   as a potential bypass.
```

## What Was NOT Tested

```text
1. IExplorerCommand / IContextMenu COM shell extensions
2. Whether the limit differs on Windows 11
3. Whether the limit differs for HKCR vs HKCU
4. Whether icons or other value types affect the count
5. Whether the 15-item child result (T9) was screen height or a real limit
```

## Cleanup

All dummy registry keys were removed after testing:

```text
HKCU keys: z_AgDummyT1 through z_AgDummyT10, AgDummy tree
HKLM keys: CommandStore\shell\AgDummy.Item01 through AgDummy.Item20
```

## Test Scripts

All test scripts located in:

```text
d:\Users\joty79\scripts\SystemTools\scratch\DummyTest-T*.ps1
```

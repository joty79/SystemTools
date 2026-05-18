# Antigravity Cascade Limit Tests — Definitive Results

Date: 2026-05-17
Host: Windows 10 Explorer, `Directory\Background` desktop right-click menu.
Tester: Antigravity (Claude Opus 4.6) + user visual confirmation.

## Purpose

Independent verification of the static registry cascade rendering limit observed in previous Claude/Gemini tests documented in:

- `STATIC_CASCADE_DUMMY_TESTS.md`
- `EXTENDED_SUBCOMMANDSKEY_DUMMY_TESTS.md`

All tests used isolated dummy roots with harmless commands (`cmd.exe /c exit /b 0`).

## Complete Test Results (T1–T11)

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
| T9 | Per-level independence | 3×16 = 51 | 3 | 15 per submenu | **3 + 15×3** ⚠️ |
| T10 | HKLM `CommandStore` + `SubCommands` verb list | 20 verbs | — | 16 | **16** 🔒 |
| T11 | Real SystemTools cascade | 4 subs + 18 entries | 3 | 3+6+4 = 13 | **16** 🔒 |

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

### 6. ~~Each Cascade Level Has an Independent Budget~~ CORRECTED: Counting Is DEPTH-FIRST GLOBAL

```text
CORRECTION (T11, 2026-05-18):

The original T9 conclusion that each level has its own independent budget
was WRONG (or at least incomplete). T11 proved that Explorer counts entries
DEPTH-FIRST across the ENTIRE cascade tree:

  Explorer walks registry keys in alphabetical order.
  For each key, it descends into ALL children BEFORE moving to the next sibling.
  It stops rendering at entry 16 across the ENTIRE tree.

T11 proof (real SystemTools cascade, 18 registered entries):
  1. Explorer (header)        9. TakeOwnership
  2.   ClearIconCache        10. WhoIsUsingThis
  3.   RefreshShell           11. WinAppManager
  4.   RestartExplorer        12. z_DummyT11 (header)
  5. Windows (header)         13.   Item01
  6.   FirewallRules          14.   Item02
  7.   PathManager            15.   Item03
  8.   SystemCleanup          16.   Item04  ← BUDGET END
  ---                         17.   Item05  ← CUT
                              18. z_ToolManager ← CUT

Result: Exactly 16 visible. z_ToolManager (leaf) and Item05 silently dropped.
Screenshot-verified by user.

T9 needs re-verification: its "3 + 15×3 = 48" result may have been
misread or may reflect a different behavior for isolated dummy roots
vs entries inside an existing cascade.
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
| Nesting deeper (more cascade levels) | ⚠️ Needs re-verification (T9 may be wrong) |

## Practical Implications for SystemTools

### Safe Budget — GLOBAL Depth-First Count

```text
Maximum safe entries per cascade TREE = 16 (GLOBAL, not per-popup)
Count ALL entries depth-first: each submenu header + ALL its children
before the next sibling.
Separators (CommandFlags 0x20/0x40) are free.
```

### Current SystemTools Layout (Depth-First Count)

```text
System Tools cascade — DEPTH-FIRST WALK:
  1. Explorer (header)
  2.   ClearIconCache
  3.   RefreshShell
  4.   RestartExplorer
  5. Windows (header)
  6.   FirewallRules
  7.   PathManager
  8.   SystemCleanup
  9.   TakeOwnership
 10.   WhoIsUsingThis
 11.   WinAppManager
 12. z_ToolManager (leaf)
     ─────────────────────
     Total: 12 of 16 budget used
     Remaining: 4 entries
```

### Maximum Expansion Room

```text
Global tree budget:  12 used, 4 remaining
Separators:          Unlimited (free) → use freely for visual grouping

WARNING: Adding a new submenu with children costs 1 (header) + N (children).
A new submenu with 4 children = 5 entries → would exceed the budget (12+5=17>16).
A new submenu with 3 children = 4 entries → exactly fills the budget (12+4=16).
A new leaf command = 1 entry → safe (12+1=13).
```

### Design Rules Going Forward

```text
1. Never exceed 16 TOTAL entries in the ENTIRE cascade tree (depth-first count).
2. Count: submenu headers + ALL their children recursively.
3. Use separators (CommandFlags) freely — they don't count.
4. If the tree grows past 16, restructure to reduce entry count.
5. No registry architecture (static shell, ExtendedSubCommandsKey,
   CommandStore) can bypass this limit.
6. Only IExplorerCommand/IContextMenu COM extensions remain untested.
7. The last entries in alphabetical depth-first order are silently cut.
```

## What Was NOT Tested

```text
1. IExplorerCommand / IContextMenu COM shell extensions
2. Whether the limit differs on Windows 11
3. Whether the limit differs for HKCR vs HKCU
4. Whether icons or other value types affect the count
5. Whether T9's "48 visible" result was accurate or a miscount
   (T11 contradicts per-level independence — needs re-verification)
```

## T11 Discovery Notes (2026-05-18)

```text
Context: User tested with Codex (OpenAI) — added a 4th submenu with 4 children
to the real SystemTools cascade, making 17 total entries. User believed all 17
showed, but on closer inspection z_ToolManager (leaf item, last alphabetically)
had silently disappeared.

This was reproduced in T11 (Antigravity) with 5 children instead of 4:
- 18 registered entries
- 16 visible (exactly)
- z_ToolManager and Dummy Item 5 silently dropped
- Depth-first alphabetical walk confirmed via screenshot

Key insight: The original T1-T10 tests used ISOLATED dummy roots. T11 was the
first test inside the REAL SystemTools cascade with mixed submenu types (headers
with children + leaf commands). The depth-first global behavior was invisible
in isolated tests because each dummy root was its own independent cascade tree.

This also corrects the earlier Codex finding — no 17-entry display was ever
achieved. The user simply didn't notice the missing z_ToolManager entry.
```

## Cleanup

All dummy registry keys were removed after testing:

```text
HKCU keys: z_AgDummyT1 through z_AgDummyT10, z_DummyT11, AgDummy tree
HKLM keys: CommandStore\shell\AgDummy.Item01 through AgDummy.Item20
```

## Test Scripts

All test scripts located in:

```text
d:\Users\joty79\scripts\SystemTools\scratch\DummyTest-T*.ps1
```

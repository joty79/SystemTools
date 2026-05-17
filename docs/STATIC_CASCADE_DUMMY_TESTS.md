# Static Registry Cascade Dummy Tests

Date: 2026-05-17
Host/context: Windows Explorer desktop right-click menu, `Directory\Background` branch.

## Purpose

These tests were created to verify whether the current `SystemTools` style of static registry cascading menus can reliably expand to more than two or three main submenus.

The tests were intentionally isolated from the real `System Tools` menu. They used separate dummy roots under:

```text
HKCU\Software\Classes\Directory\Background\shell
```

No real tool commands were used. Dummy commands were harmless:

```text
cmd.exe /c exit /b 0
```

## Important Context

The visible desktop right-click menu on this host was observed to use:

```text
HKCU\Software\Classes\Directory\Background\shell
```

This matters because earlier checks against:

```text
HKCU\Software\Classes\DesktopBackground\Shell
```

did not always reflect what was actually visible on the desktop right-click menu.

## Test 1 - 3 Menus x 2 Items

Registry root:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyTest
```

Shape:

```text
SystemTools Dummy Test
├── Dummy Explorer
│   ├── Refresh Shell
│   └── Restart Explorer
├── Dummy Windows
│   ├── Take Ownership
│   └── Who is using this?
└── Dummy Safe Mode Options
    ├── Boot in Normal Mode
    └── Boot in Safe Mode
```

Registry count:

```text
3 main submenus + 6 child items = 9 visual entries
```

Observed result:

```text
User confirmed that this menu worked visually.
```

Conclusion:

```text
A third main submenu is possible in this static registry shape.
The earlier failure was not proof that Explorer can only show two submenus.
```

## Test 2 - 5 Menus x 5 Items

Registry root:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest
```

Shape:

```text
SystemTools Dummy Stress Test
├── Dummy Menu 1
│   ├── Dummy Item 1.1
│   ├── Dummy Item 1.2
│   ├── Dummy Item 1.3
│   ├── Dummy Item 1.4
│   └── Dummy Item 1.5
├── Dummy Menu 2
│   └── 5 dummy child items
├── Dummy Menu 3
│   └── 5 dummy child items
├── Dummy Menu 4
│   └── 5 dummy child items
└── Dummy Menu 5
    └── 5 dummy child items
```

Registry count:

```text
5 main submenus + 25 child items = 30 visual entries
```

Observed result:

```text
User reported that the menu worked, but the screenshot did not prove all 5 main submenus were visible at once.
```

Conclusion:

```text
This test showed that a larger static cascade can be written and at least partially rendered.
It did not fully prove reliable rendering of all main submenu entries.
```

## Test 3 - 6 Menus x 5 Items

Registry root:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest
```

Shape:

```text
SystemTools Dummy Stress Test
├── Dummy Menu 1
│   └── 5 dummy child items
├── Dummy Menu 2
│   └── 5 dummy child items
├── Dummy Menu 3
│   └── 5 dummy child items
├── Dummy Menu 4
│   └── 5 dummy child items
├── Dummy Menu 5
│   └── 5 dummy child items
└── Dummy Menu 6
    └── 5 dummy child items
```

Registry readback:

```text
menus=6 items=30 total=36
```

Readback confirmed these keys existed:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest\shell\Menu01
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest\shell\Menu02
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest\shell\Menu03
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest\shell\Menu04
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest\shell\Menu05
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest\shell\Menu06
```

Observed result:

```text
User screenshot showed only 3 visible main submenu entries.
```

Conclusion:

```text
Registry accepted all 6 main submenus and all 30 child items.
Explorer did not visibly render all 6 main submenus in the observed desktop right-click menu.
```

## Test 4 - 6 Menus x 6 Items

Registry root:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix
```

Shape:

```text
SystemTools Dummy 6x6 Test
├── 01 MENU 1
│   ├── Item 1.1
│   ├── Item 1.2
│   ├── Item 1.3
│   ├── Item 1.4
│   ├── Item 1.5
│   └── Item 1.6
├── 02 MENU 2
│   └── 6 dummy child items
├── 03 MENU 3
│   └── 6 dummy child items
├── 04 MENU 4
│   └── 6 dummy child items
├── 05 MENU 5
│   └── 6 dummy child items
└── 06 MENU 6
    └── 6 dummy child items
```

Registry readback:

```text
menus=6 items=36 total=42
```

Readback confirmed these keys existed:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix\shell\Menu01
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix\shell\Menu02
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix\shell\Menu03
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix\shell\Menu04
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix\shell\Menu05
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix\shell\Menu06
```

Observed result:

```text
User reported: "ye only 3 menu"
```

Conclusion:

```text
Registry accepted 6 main submenus and 36 child items.
Explorer visually rendered only 3 main submenus in this test.
This is evidence of a practical Explorer rendering/truncation limit for this static nested registry cascade shape on this host.
```

## Current Evidence-Based Conclusion

The tests do not prove that static registry cascading menus are limited to exactly 16 total entries. They also do not prove that only two submenus can exist.

They do show this:

```text
3 main submenus can render.
6 main submenus can be written to registry.
6 main submenus did not visually render in Explorer in the observed 6x5 and 6x6 tests.
```

Therefore, the current `SystemTools` architecture should not assume unlimited expansion as:

```text
One root cascade -> many main submenus -> many child tools
```

with only static nested registry keys.

## Research Questions For Follow-Up

1. Is there an official Microsoft-documented limit for static nested `shell` cascades under `Directory\Background\shell`?
2. Is the observed 3-main-submenu rendering limit caused by:
   - `SubCommands=""`,
   - nested `shell` keys,
   - menu height/screen positioning,
   - ordering,
   - Explorer cache,
   - icon lookup,
   - or a known Windows 10 shell behavior?
3. Does `ExtendedSubCommandsKey` render more reliably than nested `shell` keys?
4. Does `IExplorerCommand` / COM shell extension avoid this practical rendering limit?
5. Can a static registry design stay reliable by using fewer main submenus and more child items inside each submenu?

## Cleanup Commands

These dummy menus can be removed with:

```powershell
reg.exe delete "HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyTest" /f
reg.exe delete "HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummyStressTest" /f
reg.exe delete "HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsDummySixBySix" /f
```

Then restart Explorer.

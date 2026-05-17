# ExtendedSubCommandsKey Dummy Tests

Date: 2026-05-17
Host/context: Windows 10 Explorer desktop right-click menu, `Directory\Background` branch.

## Purpose

These tests were created after static nested `shell` cascade tests showed practical Explorer truncation: registry accepted 6 main menus, but Explorer visually rendered only 3.

The goal here was to test whether Microsoft's `ExtendedSubCommandsKey` architecture avoids that truncation for a large dummy tree.

No real `System Tools` menu keys were modified. All tests used isolated dummy roots and harmless dummy commands:

```text
cmd.exe /c exit /b 0
```

## Official Microsoft Direction Being Tested

Microsoft documents three static/dynamic approaches for cascading menus:

```text
SubCommands
ExtendedSubCommandsKey
IExplorerCommand
```

The tested idea was:

```text
Use HKCU ExtendedSubCommandsKey first.
Do not jump to HKLM CommandStore or COM until HKCU is proven insufficient.
```

This matters because Microsoft notes that `HKEY_CLASSES_ROOT` is a merged view and custom verbs can be registered under:

```text
HKCU\Software\Classes
```

which avoids elevation.

## Test A - Inline ExtendedSubCommandsKey

Registry root:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsExtendedDummySixBySix
```

Attempted shape:

```text
z_SystemToolsExtendedDummySixBySix
└── ExtendedSubCommandsKey
    └── Shell
        ├── Menu01
        │   └── ExtendedSubCommandsKey
        │       └── Shell
        │           ├── Item01
        │           └── ...
        └── ...
```

Target count:

```text
6 main menus + 36 child items = 42 visual entries
```

Observed result:

```text
Explorer showed only the root item:

SystemTools Extended 6x6 Test

There was no cascade arrow.
```

Conclusion:

```text
The inline ExtendedSubCommandsKey structure did not work for this Directory\Background target.
This does not prove ExtendedSubCommandsKey is unusable; it only proves this inline shape was wrong or unsupported here.
```

## Test B - Microsoft-Style Reusable ExtendedSubCommandsKey

Registry root:

```text
HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsExtendedDummySixBySix
```

Root values:

```text
(Default) = ""
MUIVerb = "SystemTools Extended 6x6 Test"
Icon = "imageres.dll,-109"
ExtendedSubCommandsKey = "SystemToolsDummy\ExtendedSixBySix"
```

Reusable command tree:

```text
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix
```

Main menu entries:

```text
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix\Shell\Menu01
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix\Shell\Menu02
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix\Shell\Menu03
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix\Shell\Menu04
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix\Shell\Menu05
HKCU\Software\Classes\SystemToolsDummy\ExtendedSixBySix\Shell\Menu06
```

Each main menu referenced its own reusable child tree:

```text
Menu01 -> ExtendedSubCommandsKey = SystemToolsDummy\ExtendedSixBySix\Menu01
Menu02 -> ExtendedSubCommandsKey = SystemToolsDummy\ExtendedSixBySix\Menu02
Menu03 -> ExtendedSubCommandsKey = SystemToolsDummy\ExtendedSixBySix\Menu03
Menu04 -> ExtendedSubCommandsKey = SystemToolsDummy\ExtendedSixBySix\Menu04
Menu05 -> ExtendedSubCommandsKey = SystemToolsDummy\ExtendedSixBySix\Menu05
Menu06 -> ExtendedSubCommandsKey = SystemToolsDummy\ExtendedSixBySix\Menu06
```

Each child tree contained six static commands:

```text
SystemToolsDummy\ExtendedSixBySix\Menu01\Shell\Item01 ... Item06
SystemToolsDummy\ExtendedSixBySix\Menu02\Shell\Item01 ... Item06
...
SystemToolsDummy\ExtendedSixBySix\Menu06\Shell\Item01 ... Item06
```

Registry readback:

```text
menus=6 items=36 total=42
```

Observed result:

```text
Explorer showed a cascade arrow for the root item.

Visible main menus in the screenshot:

01 MENU 1
02 MENU 2
03 MENU 3

Opening 03 MENU 3 showed only:

Item 3.1
```

Conclusion:

```text
The reusable ExtendedSubCommandsKey structure works as a cascade.
It does not require HKLM for this basic test.
It does not require admin for this HKCU-based test.

However, it did not visibly render all 6 main menus or all 6 child commands in the observed Windows 10 Explorer menu.
```

## Evidence-Based Conclusions So Far

### Confirmed

```text
1. HKCU ExtendedSubCommandsKey can create a visible cascade on Windows 10.
2. The reusable-key form worked; the inline form did not.
3. HKLM CommandStore was not required for the reusable HKCU test to show a cascade.
4. Admin elevation was not required for the reusable HKCU test.
5. Registry accepted 6 main menus and 36 child commands.
6. Explorer visually rendered only 3 main menus in the observed screenshot.
7. Explorer visually rendered only 1 child item under the opened third menu in the observed screenshot.
```

### Not Proven

```text
1. An exact official "16 total item" limit was not proven by this test.
2. A universal "3 main menu" limit was not proven for every possible architecture.
3. HKLM CommandStore behavior was not tested here.
4. COM / IExplorerCommand behavior was not tested here.
5. Whether menu height/screen position contributed to the visual result was not isolated.
```

## Interpretation

The current evidence suggests that simply switching from nested `shell` keys to HKCU `ExtendedSubCommandsKey` is not enough to make a large native Explorer cascade reliably expandable on this Windows 10 host.

The reusable `ExtendedSubCommandsKey` architecture is cleaner and more official than the earlier nested `shell` shape, but the 6x6 stress test still showed practical visual truncation.

## Follow-Up Tests For Claude/Gemini/Web Research

Ask specifically:

```text
On Windows 10 Explorer, can a registry-only ExtendedSubCommandsKey cascade under Directory\Background\shell reliably show more than 3 main submenu entries?
```

Potential next experiments:

```text
1. HKLM CommandStore + SubCommands list.
2. HKLM CommandStore + ExtendedSubCommandsKey references.
3. HKCU equivalent of CommandStore-style reusable verbs.
4. Fewer main submenus, more child commands per submenu.
5. Flat root with no second-level cascading.
6. IExplorerCommand COM extension.
```

Important: any answer should distinguish these concepts:

```text
MultipleInvokePromptMinimum
SubCommands
ExtendedSubCommandsKey
CommandStore
nested shell keys
Directory\Background
DesktopBackground
IExplorerCommand
IContextMenu
```

## Cleanup Commands

Remove the ExtendedSubCommandsKey dummy test with:

```powershell
reg.exe delete "HKCU\Software\Classes\Directory\Background\shell\z_SystemToolsExtendedDummySixBySix" /f
reg.exe delete "HKCU\Software\Classes\SystemToolsDummy" /f
```

Then restart Explorer.

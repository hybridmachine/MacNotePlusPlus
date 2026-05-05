# ComparePlus Settings radio groups — honor `startsGroup`

**Date:** 2026-04-21
**Scope:** `macos/shim/` only. No plugin or upstream Notepad++ changes.

## Problem

The ComparePlus **Settings** dialog (`IDD_SETTINGS_DIALOG`) has four
logically independent radio groups down its left column:

1. *Set as First to Compare* — `IDC_FIRST_NEW`, `IDC_FIRST_OLD`
2. *Files Position* — `IDC_NEW_IN_SUB`, `IDC_OLD_IN_SUB`
3. *Default Compare in Single-View* — `IDC_COMPARE_TO_PREV`, `IDC_COMPARE_TO_NEXT`
4. *Compare StatusBar Info* — `IDC_DIFFS_SUMMARY`, `IDC_COMPARE_OPTIONS`, `IDC_STATUS_DISABLED`

On macOS they render as a single mutually-exclusive group of nine, so
selecting any radio deselects every other radio in the column.

The **Compare Options** dialog (`IDD_COMPARE_OPTIONS_DIALOG`) has one radio
group (`IDC_REGEX_MODE_IGNORE`, `IDC_REGEX_MODE_MATCH`) that works by
accident today — it's the only radio group in that dialog — but it's
affected by the same render-path shortcoming and will benefit from the
same fix.

## Root cause

`macos/shim/src/dialog_controls.mm:85-94` renders each Radio descriptor
as a plain `NSButton` added to the dialog's content view. Then
`Win32Button_Init` (`macos/shim/src/win32_dialog_controls.mm:92-116`)
assigns the same action — `@selector(buttonClicked:)` on a
`Win32ButtonTarget` — to every button including every radio.

Apple's auto-grouping rule for `NSButtonTypeRadio` (macOS 10.8+):
radios with the **same superview AND the same action selector**
automatically form one mutually-exclusive group. Every ComparePlus
radio matches both predicates, so Cocoa treats the whole column as one
group.

The template already carries the intent correctly — each group's first
radio is marked `startsGroup: true` in
`macos/shim/src/dialog_template_settings.mm` and
`macos/shim/src/dialog_template_compare_options.mm` — but
`createDialogControl` never reads the flag.

## Design

Honor `startsGroup` by assigning a **distinct action selector per
group**, while keeping all selectors funneling into the same
`buttonClicked:` dispatch that already posts WM_COMMAND/BN_CLICKED to
the owning dialog.

### 1. `Win32ButtonTarget` gains 16 group-specific selectors

In `macos/shim/src/win32_dialog_controls.mm`, add sixteen methods
`radioGroup0:` through `radioGroup15:` to `Win32ButtonTarget`. Each one
forwards to the existing `buttonClicked:`:

```objc
- (void)radioGroup0:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup1:(id)sender  { [self buttonClicked:sender]; }
// … through radioGroup15:
```

Sixteen is generous — the largest dialog in the shim has four groups
today. The cap keeps the code fully static (no runtime method synthesis),
makes selectors debuggable in Instruments, and is trivial to extend if
a future template needs more.

Non-radio buttons keep `buttonClicked:` as their action — no behavior
change for checkbox/pushbutton dispatch.

### 2. `createDialogControl` accepts a radio group index

Signature in `macos/shim/include/dialog_controls.h`:

```cpp
HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentViewRaw,
                         HWND ownerDialog,
                         double duX,
                         double duY,
                         int radioGroupIndex);   // new, -1 if N/A
```

The Radio case in `macos/shim/src/dialog_controls.mm` calls a new
`Win32Radio_Init(hwnd, radioGroupIndex)` instead of `Win32Button_Init`.
`Win32Radio_Init` performs the normal `Win32ButtonTarget` wiring but sets
the action to the group's selector.

Radio buttons with `radioGroupIndex < 0` (or ≥ 16, belt-and-suspenders)
fall back to `buttonClicked:` — this keeps the fix contained to the
paths that go through the template loop, and means a misconfigured
template degrades to today's behavior rather than crashing.

### 3. Caller computes group indices from `startsGroup`

In `macos/shim/src/win32_message.mm`, the `DialogBoxParamW` population
loop (currently lines 299-307) tracks a running group index. Each time
a `DlgControlClass::Radio` with `startsGroup == true` is seen, the
counter increments; subsequent `Radio` descriptors without
`startsGroup` inherit the current counter. Non-Radio controls are
passed with `radioGroupIndex = -1`.

Concretely:

```cpp
int currentGroup = -1;
for (const auto& desc : tmpl->controls)
{
    int group = -1;
    if (desc.kind == DlgControlClass::Radio)
    {
        if (desc.startsGroup || currentGroup < 0) ++currentGroup;
        group = currentGroup;
    }
    createDialogControl(desc, contentView, dlgHwnd, duX, duY, group);
}
```

This mirrors the Win32 semantics of WS_GROUP: a WS_GROUP on a control
starts a new group; subsequent controls belong to the most recent
group until the next WS_GROUP. The first radio in any dialog always
starts a group, regardless of whether the template author remembered
to flag it — matching `GetNextDlgGroupItem` behavior on Windows.

### 4. Templates are already correct

`dialog_template_settings.mm` already flags the first radio of each of
the four groups, and `dialog_template_compare_options.mm` flags the
regex-mode group's first radio. No template changes required.

## Data flow

1. Plugin calls `DialogBoxParamW(IDD_SETTINGS_DIALOG, …)`.
2. Shim walks the template, tracking `currentGroup`.
3. For each Radio, `createDialogControl` calls `Win32Radio_Init`, which
   assigns `@selector(radioGroupN:)` where N is the group index.
4. User clicks a radio. Cocoa's built-in mutual exclusion runs across
   all radios sharing this superview + action — exactly the peers of
   that group. Other groups (different selectors) are unaffected.
5. The group-specific selector calls `buttonClicked:`, which posts
   WM_COMMAND/BN_CLICKED to the dialog. Plugin behavior is unchanged.

The plugin's existing `Button_SetCheck`/`Button_GetCheck` calls
(`plugins/comparePlus/src/SettingsDlg/SettingsDialog.cpp:325-355`,
`438-443`) still work — those operate on individual buttons by
ID, independent of grouping.

## Error handling

- `radioGroupIndex` out of range (< 0 or ≥ 16) → fall back to
  `buttonClicked:`. Same as today's behavior, and the fallback keeps
  non-template code paths (if any direct `CreateWindowExW` radio
  ever lands through this path) working unchanged.
- Non-Radio controls keep the existing `Win32Button_Init` call.
- Template with a non-Radio control that has `startsGroup == true`:
  ignored. The flag only matters for Radios; other uses of WS_GROUP on
  Windows (tab-stop boundaries) aren't modeled by the shim.

## Testing

No automated UI tests exist for shim dialogs. Manual verification on
macOS Debug build:

1. Build: `cd macos/build && cmake --build . --target PaperWasp`.
2. Open the app, load two files, open **Plugins → ComparePlus →
   Settings**.
3. Click each radio in each of the four groups. Assert:
   - Exactly one radio stays checked within its group.
   - Clicking in one group leaves all other groups' selections intact.
4. Click **Reset**. All four groups should return to defaults with
   exactly one radio per group checked.
5. Click **OK** with a non-default selection, reopen the dialog, and
   confirm the saved selection is restored in the correct group.
6. Repeat step 3 for **Plugins → ComparePlus → Compare Options**, and
   verify the regex-mode group still behaves correctly (regression
   check — this dialog was accidentally correct before).

## Out of scope

- GroupBox content-view reparenting (option B in brainstorming).
  Radios remain siblings of the NSBox. Their visual placement already
  matches the Win32 layout; changing the hierarchy is a bigger change
  with no user-visible payoff here.
- Tab-stop semantics of WS_GROUP. The shim doesn't implement
  arrow-key navigation inside radio groups today and this fix doesn't
  add that. If it becomes important, it's a follow-up.
- Dynamic method synthesis. The 16-method cap is deliberately static.

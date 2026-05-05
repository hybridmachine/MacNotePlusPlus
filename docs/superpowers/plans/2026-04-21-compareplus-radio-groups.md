# ComparePlus Settings radio groups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the ComparePlus Settings dialog so its four radio groups on the left column behave as four independent mutually-exclusive groups instead of one.

**Architecture:** Shim-only change. Assign a distinct Cocoa action selector (`radioGroupN:`) per startsGroup run while keeping all selectors forwarded to the existing `Win32ButtonTarget.buttonClicked:` dispatcher, so WM_COMMAND routing stays intact. Cap groups at 16 via a static selector table. Templates already mark the group boundaries correctly.

**Tech Stack:** Objective-C++ (`.mm`) on top of AppKit. All edits are under `macos/shim/`.

**Spec:** [`docs/superpowers/specs/2026-04-21-compareplus-radio-groups-design.md`](../specs/2026-04-21-compareplus-radio-groups-design.md).

**Testing note:** There is no automated UI test harness for shim dialogs. This plan ends with a manual smoke-test task; every compile-only task must leave the tree buildable so we can bisect regressions later.

---

## File map

| File | Role |
|------|------|
| `macos/shim/src/win32_dialog_controls.mm` | Add 16 `radioGroupN:` forwarders on `Win32ButtonTarget` and a new `Win32Radio_Init` that wires per-group selectors. |
| `macos/shim/src/win32_dialog_controls_impl.h` | Declare `Win32Radio_Init`. |
| `macos/shim/include/dialog_controls.h` | Extend `createDialogControl` signature with `int radioGroupIndex`. |
| `macos/shim/src/dialog_controls.mm` | Pass `radioGroupIndex` through; call `Win32Radio_Init` from the Radio case. |
| `macos/shim/src/win32_message.mm` | In the `DialogBoxParamW` population loop, track a running group counter driven by `startsGroup` and pass it to `createDialogControl`. |

No plugin or template files change — both `dialog_template_settings.mm` and `dialog_template_compare_options.mm` already flag group starts correctly.

---

### Task 1: Add `radioGroupN:` forwarders on `Win32ButtonTarget`

Introduce 16 group-specific selectors that all forward to the existing `buttonClicked:` dispatcher. With this task alone the selectors are unreferenced; the build stays green and behavior is unchanged.

**Files:**
- Modify: `macos/shim/src/win32_dialog_controls.mm:18-41`

- [ ] **Step 1: Extend the interface**

Open `macos/shim/src/win32_dialog_controls.mm`. Replace the existing `@interface Win32ButtonTarget` block (lines 18-21) with:

```objc
@interface Win32ButtonTarget : NSObject
@property (assign) HWND buttonHwnd;
- (void)buttonClicked:(id)sender;
// Per-group radio selectors. Cocoa's NSButtonTypeRadio auto-grouping
// keys on (superview, action). Distinct selectors that forward to
// buttonClicked: let us honor the template's startsGroup flag without
// losing WM_COMMAND/BN_CLICKED dispatch.
- (void)radioGroup0:(id)sender;
- (void)radioGroup1:(id)sender;
- (void)radioGroup2:(id)sender;
- (void)radioGroup3:(id)sender;
- (void)radioGroup4:(id)sender;
- (void)radioGroup5:(id)sender;
- (void)radioGroup6:(id)sender;
- (void)radioGroup7:(id)sender;
- (void)radioGroup8:(id)sender;
- (void)radioGroup9:(id)sender;
- (void)radioGroup10:(id)sender;
- (void)radioGroup11:(id)sender;
- (void)radioGroup12:(id)sender;
- (void)radioGroup13:(id)sender;
- (void)radioGroup14:(id)sender;
- (void)radioGroup15:(id)sender;
@end
```

- [ ] **Step 2: Implement the forwarders**

Immediately after the closing `@end` of `@implementation Win32ButtonTarget` (currently at line 41), insert the forwarders *inside* the existing `@implementation` block — i.e. before its closing `@end`. Replace the block (lines 23-41) with:

```objc
@implementation Win32ButtonTarget
- (void)buttonClicked:(id)sender
{
	auto* info = HandleRegistry::getWindowInfo(self.buttonHwnd);
	if (!info) return;

	HWND parentHwnd = info->parent;
	if (parentHwnd)
	{
		auto* parentInfo = HandleRegistry::getWindowInfo(parentHwnd);
		if (parentInfo && parentInfo->wndProc)
		{
			WPARAM wp = MAKEWPARAM(info->controlId, BN_CLICKED);
			parentInfo->wndProc(parentHwnd, WM_COMMAND, wp,
			                    reinterpret_cast<LPARAM>(self.buttonHwnd));
		}
	}
}
- (void)radioGroup0:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup1:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup2:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup3:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup4:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup5:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup6:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup7:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup8:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup9:(id)sender  { [self buttonClicked:sender]; }
- (void)radioGroup10:(id)sender { [self buttonClicked:sender]; }
- (void)radioGroup11:(id)sender { [self buttonClicked:sender]; }
- (void)radioGroup12:(id)sender { [self buttonClicked:sender]; }
- (void)radioGroup13:(id)sender { [self buttonClicked:sender]; }
- (void)radioGroup14:(id)sender { [self buttonClicked:sender]; }
- (void)radioGroup15:(id)sender { [self buttonClicked:sender]; }
@end
```

- [ ] **Step 3: Build and verify the tree still compiles**

Run:

```bash
cd macos/build
cmake --build . --target PaperWasp
```

Expected: build succeeds. No warnings about the new selectors (they're declared and implemented).

- [ ] **Step 4: Commit**

```bash
git add macos/shim/src/win32_dialog_controls.mm
git commit -m "fix(shim): add radioGroupN: forwarders on Win32ButtonTarget

Preparatory commit for honoring the template's startsGroup flag on
radio buttons. The 16 forwarders all call buttonClicked:, so the
WM_COMMAND/BN_CLICKED dispatch is unchanged. Unused for now — the
next commit plumbs them in."
```

---

### Task 2: Add `Win32Radio_Init` that assigns a per-group selector

Provide the entry point the Radio case will call from `dialog_controls.mm`. `groupIndex < 0` or `>= 16` falls back to `buttonClicked:`, which matches today's behavior exactly.

**Files:**
- Modify: `macos/shim/src/win32_dialog_controls_impl.h`
- Modify: `macos/shim/src/win32_dialog_controls.mm:92-116` (add a new function below the existing `Win32Button_Init`)

- [ ] **Step 1: Declare `Win32Radio_Init`**

In `macos/shim/src/win32_dialog_controls_impl.h`, add the declaration after `Win32Button_Init`'s (after line 10):

```cpp
// Initialize radio-button control. `groupIndex` selects one of the
// per-group selectors on Win32ButtonTarget; pass < 0 or >= 16 to fall
// back to buttonClicked: (single-group legacy behavior).
void Win32Radio_Init(void* hwndVoid, int groupIndex);
```

- [ ] **Step 2: Implement `Win32Radio_Init`**

In `macos/shim/src/win32_dialog_controls.mm`, insert this function directly after the closing brace of `Win32Button_Init` (currently at line 116, before `Win32Button_Destroy`):

```objc
void Win32Radio_Init(void* hwndVoid, int groupIndex)
{
	HWND hwnd = reinterpret_cast<HWND>(hwndVoid);
	uintptr_t key = reinterpret_cast<uintptr_t>(hwnd);

	auto* info = HandleRegistry::getWindowInfo(hwnd);
	if (!info || !info->nativeView) return;

	id view = (__bridge id)info->nativeView;
	if (![view isKindOfClass:[NSButton class]]) return;

	if (!s_buttonTargets)
		s_buttonTargets = [NSMutableDictionary dictionary];

	Win32ButtonTarget* target = [[Win32ButtonTarget alloc] init];
	target.buttonHwnd = hwnd;

	NSButton* btn = (NSButton*)view;
	btn.target = target;

	SEL selector = @selector(buttonClicked:);
	if (groupIndex >= 0 && groupIndex < 16)
	{
		static const SEL kGroupSelectors[16] = {
			@selector(radioGroup0:),  @selector(radioGroup1:),
			@selector(radioGroup2:),  @selector(radioGroup3:),
			@selector(radioGroup4:),  @selector(radioGroup5:),
			@selector(radioGroup6:),  @selector(radioGroup7:),
			@selector(radioGroup8:),  @selector(radioGroup9:),
			@selector(radioGroup10:), @selector(radioGroup11:),
			@selector(radioGroup12:), @selector(radioGroup13:),
			@selector(radioGroup14:), @selector(radioGroup15:),
		};
		selector = kGroupSelectors[groupIndex];
	}
	btn.action = selector;

	s_buttonTargets[@(key)] = target;
}
```

- [ ] **Step 3: Build and verify**

```bash
cd macos/build
cmake --build . --target PaperWasp
```

Expected: build succeeds. The function is unused for now — no warning because it has external linkage.

- [ ] **Step 4: Commit**

```bash
git add macos/shim/src/win32_dialog_controls_impl.h macos/shim/src/win32_dialog_controls.mm
git commit -m "fix(shim): introduce Win32Radio_Init with per-group selectors

Mirrors Win32Button_Init but picks one of the radioGroupN: selectors
on Win32ButtonTarget based on groupIndex. groupIndex < 0 or >= 16
falls back to buttonClicked:. Still unused — next commit wires it
into createDialogControl."
```

---

### Task 3: Extend `createDialogControl` signature and route Radios through `Win32Radio_Init`

Add the new parameter with a `-1` default-ish behavior at the callsite (plumbed in the next task). Radios now use `Win32Radio_Init` instead of `Win32Button_Init`.

**Files:**
- Modify: `macos/shim/include/dialog_controls.h:16-20`
- Modify: `macos/shim/src/dialog_controls.mm:51-55` (signature) and `85-94` (Radio case)
- Modify: `macos/shim/src/win32_message.mm:306` (pass `-1` for now)

- [ ] **Step 1: Update the public header**

Replace the `createDialogControl` declaration in `macos/shim/include/dialog_controls.h` (lines 16-20) with:

```cpp
// parentView is NSView* (Objective-C type; passed as void* so the
// caller can stay in C++ if it wants).
// duX / duY convert dialog units to pixels for positioning.
// radioGroupIndex selects the per-group selector for radio controls
// (0..15). Pass -1 for non-Radio controls or when grouping is N/A.
HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentView,
                         HWND ownerDialog,
                         double duX,
                         double duY,
                         int radioGroupIndex);
```

- [ ] **Step 2: Update the implementation signature**

In `macos/shim/src/dialog_controls.mm`, change the function signature (lines 51-55) to:

```cpp
HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentViewRaw,
                         HWND ownerDialog,
                         double duX,
                         double duY,
                         int radioGroupIndex)
```

- [ ] **Step 3: Route Radio through `Win32Radio_Init`**

Replace the Radio case (lines 85-94) with:

```cpp
		case DlgControlClass::Radio:
		{
			NSButton* b = [[NSButton alloc] initWithFrame:frame];
			b.buttonType = NSButtonTypeRadio;
			b.title      = text;
			[parent addSubview:b];
			HWND h = registerDialogChild(b, desc, ownerDialog, ControlType::Button, L"Button");
			Win32Radio_Init(h, radioGroupIndex);
			return h;
		}
```

- [ ] **Step 4: Update the callsite to pass `-1` for every control**

In `macos/shim/src/win32_message.mm`, line 306 currently reads:

```cpp
				createDialogControl(desc, contentView, dlgHwnd, duX, duY);
```

Change it to:

```cpp
				createDialogControl(desc, contentView, dlgHwnd, duX, duY, -1);
```

This keeps behavior identical to today (every radio falls back to `buttonClicked:`), so the build stays green and the dialog stays one mega-group until Task 4.

- [ ] **Step 5: Build and verify**

```bash
cd macos/build
cmake --build . --target PaperWasp
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add macos/shim/include/dialog_controls.h macos/shim/src/dialog_controls.mm macos/shim/src/win32_message.mm
git commit -m "fix(shim): plumb radioGroupIndex through createDialogControl

Radio case now calls Win32Radio_Init. Caller in DialogBoxParamW
passes -1 for every control, so behavior is unchanged — next commit
computes real indices from the startsGroup flag."
```

---

### Task 4: Compute group indices in the `DialogBoxParamW` population loop

Drive the counter off `DlgControlDescriptor::startsGroup`. This is the commit that actually fixes user-visible behavior.

**Files:**
- Modify: `macos/shim/src/win32_message.mm:299-307`

- [ ] **Step 1: Replace the population loop**

Open `macos/shim/src/win32_message.mm`. The current block (lines 299-307) reads:

```cpp
	if (tmpl)
	{
		auto* info = HandleRegistry::getWindowInfo(dlgHwnd);
		if (info && info->nativeView)
		{
			void* contentView = info->nativeView;
			for (const auto& desc : tmpl->controls)
				createDialogControl(desc, contentView, dlgHwnd, duX, duY, -1);
		}
	}
```

Replace it with:

```cpp
	if (tmpl)
	{
		auto* info = HandleRegistry::getWindowInfo(dlgHwnd);
		if (info && info->nativeView)
		{
			void* contentView = info->nativeView;
			int currentGroup = -1;
			for (const auto& desc : tmpl->controls)
			{
				int group = -1;
				if (desc.kind == DlgControlClass::Radio)
				{
					// WS_GROUP / startsGroup starts a new run. The first
					// radio in a dialog always starts a group, even if the
					// template author forgot to flag it.
					if (desc.startsGroup || currentGroup < 0) ++currentGroup;
					group = currentGroup;
				}
				createDialogControl(desc, contentView, dlgHwnd, duX, duY, group);
			}
		}
	}
```

- [ ] **Step 2: Build and verify**

```bash
cd macos/build
cmake --build . --target PaperWasp
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add macos/shim/src/win32_message.mm
git commit -m "fix(shim): honor startsGroup when creating radio buttons

Walk the template controls in order and bump a counter each time a
Radio descriptor has startsGroup set. The first radio in any dialog
also starts a group, matching Win32 GetNextDlgGroupItem semantics.
Non-Radio controls still pass -1. ComparePlus Settings now has four
independent radio groups instead of one."
```

---

### Task 5: Manual smoke test

The shim has no UI test harness. Verify by hand on a Debug build.

**Files:** none.

- [ ] **Step 1: Launch the app**

```bash
cd macos/build
cmake --build . --target PaperWasp
./Debug/PaperWasp
```

- [ ] **Step 2: Open two files and the ComparePlus Settings dialog**

In the running app: open any two files (File → New twice is fine), then **Plugins → ComparePlus → Settings**.

- [ ] **Step 3: Exercise each radio group independently**

For each of the four groups in the left column:

1. *Set as First to Compare*: click each of **Set as new file** and **Set as old file** and verify only one stays on.
2. *Files Position*: click each of **New file in right view** and **Old file in right view**.
3. *Default Compare in Single-View*: click each of **Current and previous files** and **Current and next files**.
4. *Compare StatusBar Info*: click each of **Diffs summary**, **Compare options**, **Disabled**.

After clicking a radio in group N, every other group's previously-selected radio must still be selected. Expected: all four groups show exactly one selected radio at all times; selections in different groups are independent.

- [ ] **Step 4: Reset / OK / round-trip**

1. Click **Reset**. Every group should show exactly one selected radio at its default value.
2. Change one selection in at least two different groups, click **OK**.
3. Reopen **Plugins → ComparePlus → Settings** and confirm each group's selection matches what you saved (the dialog reads state via `Button_GetCheck` in `SettingsDialog.cpp:438-443`, independent of the shim's grouping).

- [ ] **Step 5: Regression check — Compare Options dialog**

Open **Plugins → ComparePlus → Compare Options**. Click **Ignore matches** and **Compare matches** (the regex-mode group). Only one should stay on. This group worked by accident before the fix; it must still work.

- [ ] **Step 6: Sign off**

If steps 3-5 all pass, the fix is complete. If any step fails, document which radios misbehaved and re-open the implementation.

- [ ] **Step 7: Final build (clean tree)**

```bash
cd macos/build
cmake --build . --target PaperWasp
```

Expected: build succeeds, working tree is clean (`git status` shows no pending changes beyond pre-existing untracked files).

---

## Self-review notes

- Spec coverage: Tasks 1-2 cover spec §1 (selectors + Win32Radio_Init). Task 3 covers §2 (signature change). Task 4 covers §3 (counter loop). Task 5 covers the spec's Testing section. Spec §4 (templates already correct) requires no task — confirmed above.
- Each of Tasks 1-4 leaves the tree buildable. Tasks 1-3 are behavior-preserving; Task 4 is the behavior-changing commit.
- No placeholders, no "similar to Task N", no `# ...` elisions in code blocks.
- Selector name `radioGroupN:` is consistent across the interface, implementation, and `kGroupSelectors[16]` table.

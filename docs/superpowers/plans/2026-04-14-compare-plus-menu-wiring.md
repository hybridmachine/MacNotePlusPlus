# ComparePlus Menu Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make **Plugins → ComparePlus → Compare** run the Engine end-to-end and render visible side-by-side diffs, and make **Compare Options** / **Settings** open functional dialogs whose values persist to `UserSettings`.

**Architecture:** Two sequential PRs. PR 1 adds a visibility trigger around the already-eager second Scintilla view (trigger keyed on `NPPM_SETLINENUMBERWIDTHMODE` because the plugin bypasses our Scintilla bridge via `SCI_GETDIRECTFUNCTION`) plus cosmetic NPPM stubs so the Compare Engine never stalls. PR 2 adds hand-translated dialog-template arrays plus a minimal Cocoa renderer inside `DialogBoxParamW` so the plugin's existing `doDialog()` calls produce real dialogs. Upstream plugin source stays unmodified throughout.

**Tech Stack:** Objective-C++ (Cocoa, `NSView`, `NSButton`, `NSPopUpButton`, `NSBox`, `NSTextField`, `NSColorWell`), CMake, C++20, Scintilla, the existing Win32 shim in `macos/shim/`.

**Spec:** [`docs/superpowers/specs/2026-04-14-compare-plus-menu-wiring-design.md`](../specs/2026-04-14-compare-plus-menu-wiring-design.md)

**Resolved open questions from the spec:**

- **OQ#1 / #2 (Scintilla bridge coverage):** `ScintillaBridge_sendMessage` (`macos/platform/scintilla_bridge.mm:54-61`) forwards *every* Scintilla message to `ScintillaView` uniformly. There is no dispatch table to extend for markers / indicators / annotations. PR 1 does not need bridge-side work.
- **OQ#3 (control inventory):** Enumerated by hand in Tasks 5 and 11 below.
- **OQ#4 (UserSettings persistence):** `UserSettings::save()` writes INI via `WritePrivateProfileStringW`. Verified in Task 13.
- **OQ#5 (visibility trigger reliability):** ComparePlus obtains `sciFunc` via `SCI_GETDIRECTFUNCTION` at `NPPN_READY` (`Compare.cpp:6426-6428`) and thereafter calls Scintilla through the direct function pointer, **bypassing our `SendMessageW` bridge**. The spec's proposed "first SCI_* write un-hides" trigger therefore does **not** fire. The plan uses a different trigger: `NPPM_SETLINENUMBERWIDTHMODE` is unconditionally sent by `NppState::setCompareMode()` (`Compare.cpp:867-868`) with `LINENUMWIDTH_CONSTANT` on entry and restored in `resetCompareMode()` (`Compare.cpp:823`). This message flows through `nppm_handler.mm` and is observable.
- **OQ#6 (menu-grayed propagation):** Verified via smoke test in Task 3. If `EnableMenuItem` does not refresh `NSMenuItem.enabled`, a targeted refresh is added as a PR 1 follow-up task.
- **OQ#7 (base branch):** PR 1 branches from current `feature/compare-plus-port` HEAD. PR 2 branches from PR 1's merge commit into `feature/compare-plus-port`.

**Pre-existing work already landed on `feature/compare-plus-port` (do not redo):**

- Eager allocation of `ctx().scintillaSecondHwnd` at launch (`macos/platform/app_delegate.mm:272-289`, commit `9b3621b2e`). The second Scintilla view exists and is valid at `setInfo` time; it lives inside a hidden `NSView` container parented to `editorContainer`.
- `doUnsplit()` preserves the second Scintilla view rather than destroying it (`split_view.mm:375-387`).
- `doSplit()` reuses the preserved second view instead of creating a new one (`split_view.mm:129-141`).

---

## Pre-flight

### Task 0: Verify tree state and create PR 1 branch

**Files:**
- Inspect: `macos/platform/app_delegate.mm`, `macos/platform/split_view.mm`

- [ ] **Step 1: Confirm the eager second view is live**

Run:
```bash
grep -n "Pre-create the second Scintilla view" macos/platform/app_delegate.mm
```
Expected: one hit around line 272. If nothing matches, stop and re-read the plan — the baseline has shifted.

- [ ] **Step 2: Stash uncommitted changes on `feature/compare-plus-port`**

```bash
git status --short
```

If the working tree is dirty with unrelated changes, stash them:

```bash
git stash push -u -m "pre-compare-plus-wiring stash"
```

Leave the following untracked files alone (they are orthogonal review artifacts): `issue-49-plan-*.md`, `feature-plugin-system-v1-review.md`, `REVIEW.md`, `DEVELOPER_GUIDE.md`, screenshots, `build/`, `.claude/`.

- [ ] **Step 3: Create PR 1 branch**

```bash
git checkout -b feature/compare-plus-basic-compare feature/compare-plus-port
git log -1 --format='%h %s'
```

Expected: tip is `c9f8c1ae6 docs: add ComparePlus menu wiring design spec` (or later if more commits have landed).

---

## PR 1 — Basic compare end-to-end

Scope: user clicks **Set as First** on buffer A, switches to buffer B, clicks **Compare** → split view appears with A on the left and B on the right, diff markers render, **Clear All** / **Clear Active** restore single-pane state.

### Task 1: Add `NPPM_SETLINENUMBERWIDTHMODE` as the compare-mode visibility trigger

Handle the NPPM messages the Compare Engine expects. `NPPM_SETLINENUMBERWIDTHMODE(CONSTANT)` is our canonical "entering compare mode" signal; the reverse transition hides the second view if we were the one who showed it.

**Files:**
- Modify: `macos/platform/nppm_handler.mm` (add four cases to `handleNppmMessage`'s switch)
- Modify: `macos/platform/app_state.h` (add `hostInitiatedSplit` flag)
- Create: `macos/platform/compare_plus_visibility.h`
- Create: `macos/platform/compare_plus_visibility.mm`

- [ ] **Step 1: Add a `hostInitiatedSplit` flag to `AppContext`**

In `macos/platform/app_state.h`, inside the `AppContext` struct (near `isSplit`/`scintillaSecondHwnd` field group), add:

```cpp
// Set when the host auto-split the view in response to a plugin entering
// compare mode, so we know to auto-unsplit when that plugin exits compare
// mode. Distinct from `isSplit`, which reflects any split regardless of
// origin (user-initiated splits are NOT torn down on compare exit).
bool hostInitiatedSplit = false;
```

- [ ] **Step 2: Create `compare_plus_visibility.h`**

```objc
// compare_plus_visibility.h — show/hide the second Scintilla view based on
// compare-mode transitions signalled by NPPM_SETLINENUMBERWIDTHMODE.

#pragma once

// Called when the plugin sends NPPM_SETLINENUMBERWIDTHMODE. `mode` is the
// lParam value; LINENUMWIDTH_CONSTANT (1) means "compare mode active",
// anything else means "compare mode off". Returns TRUE to satisfy the
// caller's expected return value.
long handleLineNumberWidthModeChange(int mode);
```

- [ ] **Step 3: Create `compare_plus_visibility.mm`**

```objc
// compare_plus_visibility.mm — implementation

#import <Cocoa/Cocoa.h>
#include "compare_plus_visibility.h"
#include "app_state.h"
#include "split_view.h"
#include "Notepad_plus_msgs.h"

namespace {
constexpr int LINENUMWIDTH_DYNAMIC  = 0;
constexpr int LINENUMWIDTH_CONSTANT = 1;
}

long handleLineNumberWidthModeChange(int mode)
{
    if (mode == LINENUMWIDTH_CONSTANT)
    {
        // Entering compare mode. If the user hasn't already split, split now
        // and remember that it was host-initiated so we auto-unsplit later.
        if (!ctx().isSplit)
        {
            doSplit();
            ctx().hostInitiatedSplit = ctx().isSplit; // doSplit may fail
        }
    }
    else
    {
        // Exiting compare mode. Only unsplit if we were the ones who split.
        if (ctx().hostInitiatedSplit && ctx().isSplit)
        {
            doUnsplit();
            ctx().hostInitiatedSplit = false;
        }
    }
    return TRUE;
}
```

- [ ] **Step 4: Wire the handler into `nppm_handler.mm`**

At the top of `macos/platform/nppm_handler.mm` near the other `#include`s, add:

```cpp
#include "compare_plus_visibility.h"
```

Inside `handleNppmMessage`'s switch (`nppm_handler.mm:70-327`), **replace** the existing `default:` branch's fall-through for these message IDs by adding explicit cases immediately before the `default:` label:

```cpp
case NPPM_SETLINENUMBERWIDTHMODE:
    return handleLineNumberWidthModeChange(static_cast<int>(lParam));

case NPPM_GETLINENUMBERWIDTHMODE:
    // Report dynamic so the plugin always decides to set CONSTANT on entry
    return 0; // LINENUMWIDTH_DYNAMIC

case NPPM_HIDETABBAR:
    // Cosmetic no-op on macOS (no tab bar to hide). The plugin uses this
    // as a tab-repaint side effect, not a mode indicator — do not treat
    // it as a compare-mode trigger.
    return TRUE;

case NPPM_SETSTATUSBAR:
    // Cosmetic no-op. Plugin posts "Compared X vs Y" strings we ignore.
    return TRUE;

case NPPM_ADDTOOLBARICON_FORDARKMODE:
    // Plugin tries to register toolbar icons during NPPN_TBMODIFICATION.
    // V1 has no compare-specific toolbar; accept the call silently.
    return TRUE;
```

- [ ] **Step 5: Add the new source file to CMake**

In `macos/CMakeLists.txt`, find the block that compiles `macos/platform/*.mm` into the main target. Add `compare_plus_visibility.mm` to that list.

Run:
```bash
grep -n "nppm_handler.mm\|plugin_manager.mm" macos/CMakeLists.txt
```

Add `"${CMAKE_CURRENT_SOURCE_DIR}/platform/compare_plus_visibility.mm"` alongside the other `platform/*.mm` entries.

- [ ] **Step 6: Add the message constants to the shim headers if missing**

Check whether `NPPM_SETLINENUMBERWIDTHMODE`, `NPPM_GETLINENUMBERWIDTHMODE`, `NPPM_HIDETABBAR`, `NPPM_SETSTATUSBAR`, `NPPM_ADDTOOLBARICON_FORDARKMODE` already resolve:

```bash
grep -rn "NPPM_SETLINENUMBERWIDTHMODE\|NPPM_HIDETABBAR\|NPPM_SETSTATUSBAR\|NPPM_ADDTOOLBARICON_FORDARKMODE" \
  macos/platform/Notepad_plus_msgs.h plugins/comparePlus/src/NppAPI/
```

Expected: all five found in `plugins/comparePlus/src/NppAPI/Notepad_plus_msgs.h`. The host already includes that header via the plugin SDK (`macos/plugin-sdk/`); the constants should be visible. If any is missing, add to whichever of `macos/plugin-sdk/include/Notepad_plus_msgs.h` or `macos/platform/Notepad_plus_msgs.h` the host uses (confirm by reading the `#include "Notepad_plus_msgs.h"` line at `nppm_handler.mm:14`).

- [ ] **Step 7: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
cmake --build macos/build --target ComparePlus
cmake --build macos/build --target install_compare_plus
```

Expected: clean build, no warnings on the new file.

- [ ] **Step 8: Commit**

```bash
git add macos/platform/app_state.h \
        macos/platform/compare_plus_visibility.h \
        macos/platform/compare_plus_visibility.mm \
        macos/platform/nppm_handler.mm \
        macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat: wire ComparePlus compare-mode to host split visibility

NPPM_SETLINENUMBERWIDTHMODE(CONSTANT) auto-splits the host view so the
plugin's second Scintilla writes land in a visible pane; restoring the
mode auto-unsplits iff the split was host-initiated. Adds no-op handlers
for NPPM_HIDETABBAR, NPPM_SETSTATUSBAR, and
NPPM_ADDTOOLBARICON_FORDARKMODE so the Compare Engine does not log
unknown-message spam during onToolBarReady / setCompareMode.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 2: Defensive invariants and debug-only diagnostics

Catch regressions where the plugin initialization order or the second-view lifecycle slips without running the full compare smoke test.

**Files:**
- Create: `macos/platform/plugin_invariants.h`
- Create: `macos/platform/plugin_invariants.mm`
- Modify: `macos/platform/app_delegate.mm`

- [ ] **Step 1: Write `plugin_invariants.h`**

```objc
// plugin_invariants.h — launch-time and NPPN_READY assertions.
// Output is gated behind MACNOTE_PLUGIN_DEBUG=1 env var.

#pragma once

// Call immediately before pluginManager().init(). Asserts that the state
// every plugin relies on is populated correctly.
void assertPluginPreInitInvariants();

// Call immediately after NPPN_READY fan-out. Diagnoses plugin handshake
// issues.
void dumpPluginPostReadyState();
```

- [ ] **Step 2: Write `plugin_invariants.mm`**

```objc
#import <Cocoa/Cocoa.h>
#include "plugin_invariants.h"
#include "app_state.h"
#include "plugin_manager.h"
#include "menu_builder.h"

static bool debugEnabled()
{
    static int cached = -1;
    if (cached < 0)
    {
        const char* v = getenv("MACNOTE_PLUGIN_DEBUG");
        cached = (v && v[0] == '1') ? 1 : 0;
    }
    return cached == 1;
}

void assertPluginPreInitInvariants()
{
    NSCAssert(ctx().mainHwnd != nullptr,
              @"mainHwnd must be valid before plugin init");
    NSCAssert(ctx().scintillaMainHwnd != nullptr,
              @"scintillaMainHwnd must be valid before plugin init");
    NSCAssert(ctx().scintillaSecondHwnd != nullptr,
              @"scintillaSecondHwnd must be eager-allocated before plugin init "
              @"(see app_delegate.mm:272-289)");

    if (debugEnabled())
    {
        NSLog(@"[plugin-invariants] pre-init: main=%p sciMain=%p sciSecond=%p",
              ctx().mainHwnd, ctx().scintillaMainHwnd, ctx().scintillaSecondHwnd);
    }
}

void dumpPluginPostReadyState()
{
    if (!debugEnabled()) return;
    NSLog(@"[plugin-invariants] post-ready: pluginsMenu=%p isSplit=%d hostSplit=%d",
          getPluginsMenuHandle(), ctx().isSplit ? 1 : 0,
          ctx().hostInitiatedSplit ? 1 : 0);
}
```

- [ ] **Step 3: Wire into `applicationDidFinishLaunching`**

Open `macos/platform/app_delegate.mm` and edit the section starting at line 552 ("Initialize plugin system"):

```objc
#include "plugin_invariants.h"  // add near the other platform/*.h includes

// ... inside the init block at line 552:
{
    NppData nppData;
    nppData._nppHandle = ctx().mainHwnd;
    nppData._scintillaMainHandle = ctx().scintillaMainHwnd;
    nppData._scintillaSecondHandle = ctx().scintillaSecondHwnd;
    assertPluginPreInitInvariants();   // <-- add this line
    pluginManager().init(nppData);
    pluginManager().loadPlugins();
    pluginManager().initMenu(getPluginsMenuHandle());
}

// ... after the NPPN_READY block at line 568, add:
dumpPluginPostReadyState();
```

- [ ] **Step 4: Add to CMake**

Add `"${CMAKE_CURRENT_SOURCE_DIR}/platform/plugin_invariants.mm"` to the `platform/*.mm` source list in `macos/CMakeLists.txt`.

- [ ] **Step 5: Build and verify debug output**

```bash
cmake --build macos/build --target MacNotePlusPlus
MACNOTE_PLUGIN_DEBUG=1 ./macos/build/Debug/MacNotePlusPlus 2>&1 | grep plugin-invariants
```

Expected: two lines logged, one pre-init with non-null pointers, one post-ready with a non-null pluginsMenu.

- [ ] **Step 6: Commit**

```bash
git add macos/platform/plugin_invariants.h \
        macos/platform/plugin_invariants.mm \
        macos/platform/app_delegate.mm \
        macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat: add plugin-init invariants and post-NPPN_READY diagnostics

Asserts scintillaSecondHwnd is eager-allocated before plugin setInfo, and
dumps menu + split state after NPPN_READY when MACNOTE_PLUGIN_DEBUG=1.
Catches regressions in the launch sequence before they surface as silent
compare failures.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: Manual compare smoke test

This is the authoritative verification for PR 1. Record the results in the PR description as a reviewer checklist.

**Files:** None (manual testing)

- [ ] **Step 1: Install the freshly built plugin**

```bash
cmake --build macos/build --target install_compare_plus
```

- [ ] **Step 2: Launch the app**

```bash
open macos/build/Debug/MacNotePlusPlus.app
```

Or run the development binary directly:

```bash
./macos/build/Debug/MacNotePlusPlus
```

- [ ] **Step 3: Prepare two test files**

```bash
cat > /tmp/A.txt <<'EOF'
Line one
Line two
Line three
Common line
Unique to A
EOF
cat > /tmp/B.txt <<'EOF'
Line one
Line two CHANGED
Line three
Common line
Unique to B
EOF
```

Open both files in the app via File → Open or drag-and-drop.

- [ ] **Step 4: Smoke-test core compare flow**

1. Focus the **A.txt** tab.
2. **Plugins → ComparePlus → Set as First**. Confirm no crash and no visible change (the tab is marked internally).
3. Focus **B.txt**.
4. **Plugins → ComparePlus → Compare**. Expected behavior:
   - The editor splits into two panes side-by-side.
   - The left pane shows A.txt, the right pane shows B.txt.
   - Line 2 is highlighted as changed; "Unique to A" is marked removed in B's pane and "Unique to B" is marked added.
   - If nothing visible happens in the right pane, the visibility trigger failed — fall back to diagnosing via `MACNOTE_PLUGIN_DEBUG=1` logs.
5. **Plugins → ComparePlus → Clear Active**. The split view collapses to a single pane; markers vanish.
6. Repeat steps 3-4, then **Clear All**. Same expected result.
7. Compare a file with itself: open two separate tabs pointing to `/tmp/A.txt`, Set as First on one, Compare on the other. Expected: a MessageBox appears stating "files are identical."

- [ ] **Step 5: Smoke-test preservation of user splits**

1. Manually split the view via your existing split shortcut before running Compare.
2. Run Compare as above.
3. Clear Active — the split stays (user-initiated), only the diff markers vanish. This confirms `hostInitiatedSplit` logic.

- [ ] **Step 6: Record outcomes**

In the PR description, paste a checklist reflecting each of Step 4's sub-items. Any that failed become follow-up tasks on the branch before opening the PR.

- [ ] **Step 7: Commit the PR 1 smoke-test script so the reviewer can replay it**

Create `macos/scripts/smoke-test-compare.sh` with the fixture creation commands from Step 3, then:

```bash
git add macos/scripts/smoke-test-compare.sh
chmod +x macos/scripts/smoke-test-compare.sh
git commit -m "$(cat <<'EOF'
chore: add compare smoke-test fixture generator

Creates /tmp/A.txt and /tmp/B.txt for the Compare Engine smoke test
documented in the PR description.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

With script contents:

```bash
#!/bin/bash
# Fixture generator for the ComparePlus manual smoke test.
# Run before launching the app, then open the two files and follow the
# PR description's smoke-test checklist.
set -e
cat > /tmp/A.txt <<'FILE'
Line one
Line two
Line three
Common line
Unique to A
FILE
cat > /tmp/B.txt <<'FILE'
Line one
Line two CHANGED
Line three
Common line
Unique to B
FILE
echo "Fixtures written: /tmp/A.txt, /tmp/B.txt"
```

### Task 4: Open PR 1

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/compare-plus-basic-compare
```

- [ ] **Step 2: Open the PR against `feature/compare-plus-port`**

```bash
gh pr create --base feature/compare-plus-port \
  --title "feat: wire ComparePlus compare to visible split view" \
  --body "$(cat <<'EOF'
## Summary
- Route NPPM_SETLINENUMBERWIDTHMODE to auto-split / auto-unsplit around the plugin's compareMode transitions so diff markers land in a visible pane.
- Add no-op handlers for NPPM_HIDETABBAR, NPPM_SETSTATUSBAR, and NPPM_ADDTOOLBARICON_FORDARKMODE.
- Add pre-init invariants + post-NPPN_READY diagnostics gated on MACNOTE_PLUGIN_DEBUG=1.

## Test plan

- [ ] `macos/scripts/smoke-test-compare.sh`
- [ ] App launches, `MACNOTE_PLUGIN_DEBUG=1` logs show pre-init pointers non-null
- [ ] Open /tmp/A.txt and /tmp/B.txt; Set as First on A; Compare from B → split view appears, diffs are visible
- [ ] Clear Active → split collapses, markers vanish
- [ ] Clear All after re-Compare → same
- [ ] Compare identical files → "files are identical" message box
- [ ] User-initiated split survives Clear Active (hostInitiatedSplit=false path)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Wait for merge before starting PR 2**

PR 2 must branch from the merge commit of PR 1 into `feature/compare-plus-port`.

---

## PR 2 — Options and Settings dialogs

Scope: **Plugins → ComparePlus → Compare Options** and **Settings** open interactive dialogs; changes persist to `UserSettings` via the existing INI writer. Implementation: hand-translated dialog-template arrays + a Cocoa renderer inside `DialogBoxParamW`.

**Why hand-translated templates:** The `.rc` files are not compiled on macOS (no `windres`, no resource compiler in the CMake build). `MAKEINTRESOURCEW(IDD_COMPARE_OPTIONS_DIALOG)` inside the plugin becomes an integer the shim cannot resolve to a real template. We hand-translate the two dialogs into C++ `DialogTemplateCpp` arrays keyed by ID; the shim looks up the array when `DialogBoxParamW` is called. A general `.rc` parser is explicitly out of scope per the spec's YAGNI guardrails.

### Task 5: Hand-translate `IDD_COMPARE_OPTIONS_DIALOG`

Read the Windows `.rc` file and transcribe each control into a static C++ array. The array structure is defined first, then the dialog gets its own `.mm` file.

**Files:**
- Inspect: `plugins/comparePlus/src/CompareOptionsDlg/CompareOptionsDialog.rc`
- Inspect: `plugins/comparePlus/src/resource.h`
- Create: `macos/shim/include/dialog_template.h`
- Create: `macos/shim/src/dialog_templates.mm` (registry of hand-translated templates)
- Create: `macos/shim/src/dialog_template_compare_options.mm` (the translated template)

- [ ] **Step 1: Read the source `.rc`**

Open `plugins/comparePlus/src/CompareOptionsDlg/CompareOptionsDialog.rc` and enumerate every control: class (BUTTON / STATIC / EDIT / COMBOBOX), text, ID, rect (x, y, cx, cy), and style bits. The rect units are dialog units (DLU); we'll convert 1 DLU ≈ 1.6 pixels for X / 1 DLU ≈ 1.9 pixels for Y at the Cocoa renderer stage.

Cross-reference control IDs against the referenced symbols in `CompareOptionsDialog.cpp` (lines 47-139) and the numeric definitions in `plugins/comparePlus/src/resource.h`.

- [ ] **Step 2: Write `dialog_template.h` — the shared descriptor type**

```cpp
// dialog_template.h — hand-translated Win32 dialog templates
//
// Each dialog used by a macOS-vendored plugin is transcribed into a
// C++ DialogTemplateCpp literal. The shim's DialogBoxParamW looks the
// template up by (hInstance, dialogID) and renders it as native Cocoa
// controls. This is intentionally narrow: one entry per dialog the
// plugin actually uses.

#pragma once

#include "windows.h"
#include <vector>
#include <string>

enum class DlgControlClass
{
    Button,           // BS_PUSHBUTTON or BS_DEFPUSHBUTTON
    Checkbox,         // BS_AUTOCHECKBOX
    Radio,            // BS_AUTORADIOBUTTON (grouped by WS_GROUP runs)
    GroupBox,         // BS_GROUPBOX
    Static,           // STATIC (label)
    Edit,             // EDIT (single-line)
    ComboBox,         // COMBOBOX with CBS_DROPDOWNLIST
    EditCombo,        // COMBOBOX without CBS_DROPDOWNLIST (editable)
    UpDown,           // msctls_updown32 (spin control; SettingsDialog only)
    ColorCombo,       // Custom "ColorCombo" class → NSColorWell substitute
};

struct DlgControlDescriptor
{
    DlgControlClass kind;
    int id;
    std::wstring text;   // L"" for controls without text (e.g. EDIT)
    int x, y, cx, cy;    // dialog-units; renderer converts to pixels
    bool isDefaultButton = false;   // only meaningful for Button
    bool startsGroup = false;        // WS_GROUP — starts a radio group
};

struct DialogTemplateCpp
{
    int id;                                  // matches MAKEINTRESOURCEW(id)
    std::wstring title;
    int x, y, cx, cy;                        // dialog rect in DLU
    std::vector<DlgControlDescriptor> controls;
};

// Register a template for lookup by DialogBoxParamW.
void registerDialogTemplate(const DialogTemplateCpp& t);

// Look up a template by dialog ID. Returns nullptr if unknown.
const DialogTemplateCpp* findDialogTemplate(int dialogID);
```

- [ ] **Step 3: Write `dialog_templates.mm` — the registry**

```objc
// dialog_templates.mm — lookup table for hand-translated templates.

#import <Foundation/Foundation.h>
#include "dialog_template.h"

#include <unordered_map>

namespace {
std::unordered_map<int, DialogTemplateCpp>& registry()
{
    static std::unordered_map<int, DialogTemplateCpp> inst;
    return inst;
}
}

void registerDialogTemplate(const DialogTemplateCpp& t)
{
    registry()[t.id] = t;
}

const DialogTemplateCpp* findDialogTemplate(int dialogID)
{
    auto it = registry().find(dialogID);
    return (it == registry().end()) ? nullptr : &it->second;
}
```

- [ ] **Step 4: Write `dialog_template_compare_options.mm`**

Transcribe every control from the `.rc` file. The IDs come from `plugins/comparePlus/src/resource.h`; the `#include` below makes them visible without duplication.

```objc
// dialog_template_compare_options.mm — hand-translated IDD_COMPARE_OPTIONS_DIALOG

#import <Foundation/Foundation.h>
#include "dialog_template.h"

// Pull in the plugin's own resource IDs so renames stay in sync with
// the plugin source.
#include "../../plugins/comparePlus/src/resource.h"

namespace {
struct AutoRegister
{
    AutoRegister()
    {
        DialogTemplateCpp t;
        t.id = IDD_COMPARE_OPTIONS_DIALOG;
        t.title = L"ComparePlus   Compare Options";
        t.x = 0; t.y = 0; t.cx = 300; t.cy = 320;

        // [Fill in every control from CompareOptionsDialog.rc here. Each
        //  entry is one DlgControlDescriptor. Keep the order matching the
        //  .rc for visual fidelity.]
        //
        // The reader of this plan MUST open the .rc file and transcribe
        // every control. Below are the three exemplar entries the rest of
        // the file's controls should follow. DO NOT merge this file until
        // every control from the .rc has been transcribed.

        t.controls = {
            // -- Detect group --
            { DlgControlClass::GroupBox, IDC_DETECT, L"Detect",
              /*x*/ 7, /*y*/ 7, /*cx*/ 286, /*cy*/ 90 },
            { DlgControlClass::Checkbox, IDC_DETECT_MOVES, L"Detect moves",
              /*x*/ 15, /*y*/ 20, /*cx*/ 120, /*cy*/ 12 },
            { DlgControlClass::Checkbox, IDC_DETECT_SUB_BLOCK_DIFFS, L"Detect sub-block diffs",
              /*x*/ 15, /*y*/ 35, /*cx*/ 160, /*cy*/ 12 },
            // ... all remaining Detect / Ignore / Regex controls ...

            // -- OK / Cancel row --
            { DlgControlClass::Button, IDOK, L"OK",
              /*x*/ 180, /*y*/ 295, /*cx*/ 50, /*cy*/ 14,
              /*isDefault*/ true },
            { DlgControlClass::Button, IDCANCEL, L"Cancel",
              /*x*/ 240, /*y*/ 295, /*cx*/ 50, /*cy*/ 14 },
        };

        registerDialogTemplate(t);
    }
};
AutoRegister _register;
}
```

**Transcription checklist** — walk `CompareOptionsDialog.rc` top to bottom. Every `PUSHBUTTON`, `DEFPUSHBUTTON`, `AUTOCHECKBOX`, `AUTORADIOBUTTON`, `GROUPBOX`, `LTEXT`, `EDITTEXT`, `COMBOBOX`, and `CONTROL "..."` line becomes one `DlgControlDescriptor`. Any control class this plan's `DlgControlClass` enum doesn't cover must be added to the enum before proceeding.

- [ ] **Step 5: Add to CMake**

In `macos/CMakeLists.txt`, add to the `SHIM_SOURCES` list (or equivalent — confirm by reading `macos/CMakeLists.txt:40-50`):

```cmake
"${CMAKE_CURRENT_SOURCE_DIR}/shim/src/dialog_templates.mm"
"${CMAKE_CURRENT_SOURCE_DIR}/shim/src/dialog_template_compare_options.mm"
```

- [ ] **Step 6: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
```

Expected: clean compile. No linker errors yet (the template is registered but not consumed until Task 9).

- [ ] **Step 7: Commit**

```bash
git add macos/shim/include/dialog_template.h \
        macos/shim/src/dialog_templates.mm \
        macos/shim/src/dialog_template_compare_options.mm \
        macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat(shim): hand-translated IDD_COMPARE_OPTIONS_DIALOG template

Transcribes the Compare Options dialog from CompareOptionsDialog.rc
into a C++ DialogTemplateCpp registered at startup. Renderer consumer
arrives in subsequent commits.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 6: Extend `HandleRegistry` for dialog children by control ID

The plugin calls `::GetDlgItem(_hSelf, IDC_DETECT_MOVES)` to reach an individual control. Today `HandleRegistry` only maps `HWND → WindowInfo`; we need a dialog-scoped lookup so `GetDlgItem` can resolve a child by its dialog-item ID.

**Files:**
- Modify: `macos/shim/include/handle_registry.h`
- Modify: `macos/shim/src/handle_registry.mm` (or `.cpp` — confirm by reading the file list)
- Modify: `macos/shim/src/win32_controls.mm` (extend `GetDlgItem`)

- [ ] **Step 1: Read current `HandleRegistry` API**

```bash
grep -n "struct WindowInfo\|createWindow\|getWindowInfo" macos/shim/include/handle_registry.h
```

Confirm that `WindowInfo` has fields: `nativeView`, `nativeWindow`, `className`, `parent`, `isScintilla`, `controlType`. Verify whether children-by-ID mapping already exists (search for `dlgItemId` or `childId`).

- [ ] **Step 2: Extend `WindowInfo`**

In `macos/shim/include/handle_registry.h`, add:

```cpp
struct WindowInfo
{
    // ... existing fields ...
    int dlgItemId = 0;              // NEW — 0 means "not a dialog child"
    HWND dlgParent = nullptr;       // NEW — the owning dialog HWND
};
```

- [ ] **Step 3: Add a dialog child lookup helper**

In the same header:

```cpp
namespace HandleRegistry {
    // Find the child HWND of `dlgParent` whose dlgItemId matches `id`.
    // Returns nullptr if no such child exists.
    HWND findDialogChild(HWND dlgParent, int id);
}
```

And implement it alongside the existing registry logic (look for where `getWindowInfo` is implemented):

```cpp
HWND HandleRegistry::findDialogChild(HWND dlgParent, int id)
{
    for (const auto& [hwnd, info] : registryMap()) {   // match existing accessor name
        if (info.dlgParent == dlgParent && info.dlgItemId == id)
            return hwnd;
    }
    return nullptr;
}
```

If the existing registry uses a different internal iteration API, adapt the loop to use it.

- [ ] **Step 4: Rewrite `GetDlgItem`**

In `macos/shim/src/win32_controls.mm` (search for existing `GetDlgItem` via `grep -n "GetDlgItem" macos/shim/src/*.mm`), replace any current implementation with:

```cpp
HWND GetDlgItem(HWND hDlg, int nIDDlgItem)
{
    if (!hDlg) return nullptr;
    return HandleRegistry::findDialogChild(hDlg, nIDDlgItem);
}
```

- [ ] **Step 5: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
```

Expected: clean compile. No behavior change yet — nothing populates `dlgItemId` until Task 7.

- [ ] **Step 6: Commit**

```bash
git add macos/shim/include/handle_registry.h \
        macos/shim/src/handle_registry.* \
        macos/shim/src/win32_controls.mm
git commit -m "$(cat <<'EOF'
feat(shim): extend HandleRegistry with dialog-child lookup

Adds dlgItemId / dlgParent to WindowInfo and a findDialogChild() helper
so GetDlgItem() can resolve a dialog control by numeric ID. Populated by
the upcoming dialog renderer.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 7: Implement Cocoa control creation from a `DlgControlDescriptor`

Given a descriptor, produce a typed `NSControl` and register it in `HandleRegistry` with its `dlgItemId` and `dlgParent`.

**Files:**
- Create: `macos/shim/src/dialog_controls.mm`
- Create: `macos/shim/include/dialog_controls.h`

- [ ] **Step 1: Write `dialog_controls.h`**

```objc
// dialog_controls.h — create Cocoa controls from DlgControlDescriptor.

#pragma once

#include "dialog_template.h"

// Creates a typed NSControl from `desc`, positions it inside `parentView`
// using the supplied DLU→pixel scale, and registers an HWND for it in
// HandleRegistry with (dlgItemId = desc.id, dlgParent = ownerDialog).
// Returns the created HWND; never returns nullptr (unknown control kinds
// render as a labelled NSView placeholder).
HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentView /* NSView* */,
                         HWND ownerDialog,
                         double duX, double duY);
```

- [ ] **Step 2: Write `dialog_controls.mm`**

```objc
#import <Cocoa/Cocoa.h>
#include "dialog_controls.h"
#include "handle_registry.h"
#include <string>

namespace {

NSString* toNS(const std::wstring& w)
{
    return [[NSString alloc] initWithBytes:w.data()
                                    length:w.size() * sizeof(wchar_t)
                                  encoding:NSUTF32LittleEndianStringEncoding];
}

NSRect dluToPixel(int x, int y, int cx, int cy, NSView* parent,
                  double duX, double duY)
{
    // Top-left origin in DLU → bottom-left NSView origin in pixels.
    CGFloat px = x * duX;
    CGFloat py = parent.bounds.size.height - (y + cy) * duY;
    CGFloat pw = cx * duX;
    CGFloat ph = cy * duY;
    return NSMakeRect(px, py, pw, ph);
}

HWND registerControl(NSView* view, const DlgControlDescriptor& desc,
                     HWND ownerDialog)
{
    HandleRegistry::WindowInfo info{};
    info.nativeView = (__bridge_retained void*)view;
    info.className = L"DialogChild";
    info.isScintilla = false;
    info.parent = ownerDialog;
    info.dlgItemId = desc.id;
    info.dlgParent = ownerDialog;
    return HandleRegistry::createWindow(std::move(info));
}

} // namespace

HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentViewRaw,
                         HWND ownerDialog,
                         double duX, double duY)
{
    NSView* parent = (__bridge NSView*)parentViewRaw;
    NSRect frame = dluToPixel(desc.x, desc.y, desc.cx, desc.cy, parent, duX, duY);
    NSControl* ctrl = nil;

    switch (desc.kind)
    {
        case DlgControlClass::Button:
        {
            NSButton* b = [[NSButton alloc] initWithFrame:frame];
            b.bezelStyle = NSBezelStyleRounded;
            b.title = toNS(desc.text);
            if (desc.isDefaultButton) b.keyEquivalent = @"\r";
            ctrl = b;
            break;
        }
        case DlgControlClass::Checkbox:
        {
            NSButton* b = [[NSButton alloc] initWithFrame:frame];
            b.buttonType = NSButtonTypeSwitch;
            b.title = toNS(desc.text);
            ctrl = b;
            break;
        }
        case DlgControlClass::Radio:
        {
            NSButton* b = [[NSButton alloc] initWithFrame:frame];
            b.buttonType = NSButtonTypeRadio;
            b.title = toNS(desc.text);
            ctrl = b;
            // Radio grouping in Cocoa happens via identical `action:`
            // selectors on siblings. The dialog pump installs a shared
            // action in Task 9.
            break;
        }
        case DlgControlClass::GroupBox:
        {
            NSBox* box = [[NSBox alloc] initWithFrame:frame];
            box.title = toNS(desc.text);
            [parent addSubview:box];
            return registerControl(box, desc, ownerDialog);
        }
        case DlgControlClass::Static:
        {
            NSTextField* tf = [NSTextField labelWithString:toNS(desc.text)];
            tf.frame = frame;
            ctrl = tf;
            break;
        }
        case DlgControlClass::Edit:
        {
            NSTextField* tf = [[NSTextField alloc] initWithFrame:frame];
            tf.editable = YES;
            tf.bezeled = YES;
            ctrl = tf;
            break;
        }
        case DlgControlClass::ComboBox:
        {
            NSPopUpButton* pop = [[NSPopUpButton alloc] initWithFrame:frame
                                                              pullsDown:NO];
            ctrl = pop;
            break;
        }
        case DlgControlClass::EditCombo:
        {
            NSComboBox* combo = [[NSComboBox alloc] initWithFrame:frame];
            combo.usesDataSource = NO;
            ctrl = combo;
            break;
        }
        case DlgControlClass::UpDown:
        {
            NSStepper* step = [[NSStepper alloc] initWithFrame:frame];
            ctrl = step;
            break;
        }
        case DlgControlClass::ColorCombo:
        {
            NSColorWell* well = [[NSColorWell alloc] initWithFrame:frame];
            ctrl = well;
            break;
        }
    }

    if (!ctrl)
    {
        // Unknown — render a placeholder so layout survives.
        NSTextField* ph = [NSTextField labelWithString:
            [NSString stringWithFormat:@"?ID=%d", desc.id]];
        ph.frame = frame;
        [parent addSubview:ph];
        return registerControl(ph, desc, ownerDialog);
    }

    [parent addSubview:ctrl];
    return registerControl(ctrl, desc, ownerDialog);
}
```

- [ ] **Step 3: Add to CMake**

Append to `SHIM_SOURCES`:

```cmake
"${CMAKE_CURRENT_SOURCE_DIR}/shim/src/dialog_controls.mm"
```

- [ ] **Step 4: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
```

- [ ] **Step 5: Commit**

```bash
git add macos/shim/include/dialog_controls.h \
        macos/shim/src/dialog_controls.mm \
        macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat(shim): Cocoa control factory for dialog templates

Maps each DlgControlClass variant to a typed NSControl (NSButton /
NSTextField / NSBox / NSPopUpButton / NSComboBox / NSStepper /
NSColorWell) and registers the control's HWND against its owning
dialog with dlgItemId set.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: Extend `SendDlgItemMessageW` / `SendMessageW` for the control messages the dialogs use

The dialog code uses `Button_GetCheck`, `Button_SetCheck`, `Button_Enable`, `ComboBox_AddString`, `ComboBox_Enable`, `ComboBox_LimitText`, `ComboBox_SetText`, `ComboBox_GetText`, `ComboBox_GetTextLength`, `::SetDlgItemTextW`, `::EnableThemeDialogTexture`, `::SendMessageW(EM_SETLIMITTEXT)`, `::SendMessageW(UDM_SETRANGE)`. Most resolve to `SendMessageW(hctrl, …)` under the hood.

**Files:**
- Modify: `macos/shim/src/win32_controls.mm` (existing control message dispatcher)
- Modify: `macos/shim/src/win32_message.mm` (routes control messages)

- [ ] **Step 1: List the required messages**

| Macro / call                  | Resolves to                                       |
|-------------------------------|---------------------------------------------------|
| `Button_SetCheck`             | `SendMessage(h, BM_SETCHECK, state, 0)`           |
| `Button_GetCheck`             | `SendMessage(h, BM_GETCHECK, 0, 0)`               |
| `Button_Enable`               | `EnableWindow(h, bEnable)`                        |
| `ComboBox_AddString`          | `SendMessage(h, CB_ADDSTRING, 0, (LPARAM)lpsz)`   |
| `ComboBox_SetText`            | `SetWindowText(h, lpsz)`                          |
| `ComboBox_GetText`            | `GetWindowText(h, lpsz, len)`                     |
| `ComboBox_GetTextLength`      | `GetWindowTextLength(h)`                          |
| `ComboBox_Enable`             | `EnableWindow(h, bEnable)`                        |
| `ComboBox_LimitText`          | `SendMessage(h, CB_LIMITTEXT, n, 0)`              |
| `SetDlgItemTextW`             | `SetWindowTextW(GetDlgItem(hDlg, id), text)`      |
| `EM_SETLIMITTEXT`             | Text-field max-length                             |
| `UDM_SETRANGE`                | NSStepper min/max                                 |

- [ ] **Step 2: Implement each message in the shim's control dispatcher**

Inside `Win32Controls_HandleMessage` (in `macos/shim/src/win32_controls.mm` or the file referenced by `win32_message.mm:44`), add cases:

```cpp
case BM_SETCHECK:
{
    NSButton* b = (__bridge NSButton*)info->nativeView;
    b.state = (wParam == BST_CHECKED) ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    controlResult = 0;
    return true;
}
case BM_GETCHECK:
{
    NSButton* b = (__bridge NSButton*)info->nativeView;
    controlResult = (b.state == NSControlStateValueOn) ? BST_CHECKED : BST_UNCHECKED;
    return true;
}
case CB_ADDSTRING:
{
    NSString* s = [[NSString alloc] initWithBytes:(const void*)lParam
                                           length:wcslen((const wchar_t*)lParam) * sizeof(wchar_t)
                                         encoding:NSUTF32LittleEndianStringEncoding];
    id ctl = (__bridge id)info->nativeView;
    if ([ctl isKindOfClass:[NSPopUpButton class]])
        [(NSPopUpButton*)ctl addItemWithTitle:s];
    else if ([ctl isKindOfClass:[NSComboBox class]])
        [(NSComboBox*)ctl addItemWithObjectValue:s];
    controlResult = 0;
    return true;
}
case CB_LIMITTEXT:
{
    // No direct equivalent for NSComboBox; record and enforce in controller.
    controlResult = 0;
    return true;
}
case EM_SETLIMITTEXT:
{
    NSTextField* tf = (__bridge NSTextField*)info->nativeView;
    NSInteger max = (NSInteger)wParam;
    NSNumberFormatter* f = [[NSNumberFormatter alloc] init];
    f.maximum = @((long long)pow(10, max) - 1);
    tf.formatter = f;
    controlResult = 0;
    return true;
}
case UDM_SETRANGE:
{
    NSStepper* s = (__bridge NSStepper*)info->nativeView;
    SHORT lo = HIWORD(lParam);
    SHORT hi = LOWORD(lParam);
    s.minValue = lo;
    s.maxValue = hi;
    controlResult = 0;
    return true;
}
```

Add `EnableWindow`, `SetWindowTextW`, `GetWindowTextW`, `GetWindowTextLengthW` equivalents if they're missing — most already exist; confirm via `grep -n EnableWindow macos/shim/src/*.mm`.

- [ ] **Step 3: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
```

- [ ] **Step 4: Unit smoke test (ad-hoc)**

Write a throwaway test in `macos/tests/` (confirm path exists — look for sibling tests) that creates an NSButton via `createDialogControl(...)`, registers it, then round-trips `BM_SETCHECK` / `BM_GETCHECK` through `SendMessageW`. Delete the test if `macos/tests/` isn't configured; inline assertions inside the renderer work equally well for now.

- [ ] **Step 5: Commit**

```bash
git add macos/shim/src/win32_controls.mm macos/shim/src/win32_message.mm
git commit -m "$(cat <<'EOF'
feat(shim): implement BM_* / CB_* / EM_* / UDM_SETRANGE

Adds the control messages CompareOptionsDialog and SettingsDialog use
(button check state, combobox add/text, edit-field length limits, spin
control range). BM_SETCHECK / BM_GETCHECK round-trip round-trips through
the SendMessageW dispatcher.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 9: Implement `DialogBoxParamW` rendering + `WM_INITDIALOG` / `WM_COMMAND` pump

Replace the current empty 400x300 modal (`macos/shim/src/win32_message.mm:261-300`) with a renderer-backed modal that looks up the template, builds controls, dispatches `WM_INITDIALOG` and `WM_COMMAND`.

**Files:**
- Modify: `macos/shim/src/win32_message.mm`
- Create: `macos/shim/src/dialog_modal.mm`
- Create: `macos/shim/include/dialog_modal.h`

- [ ] **Step 1: Write `dialog_modal.h`**

```cpp
#pragma once
#include "windows.h"

// Create an NSWindow modally, populate it from the registered template
// for `dialogID`, dispatch WM_INITDIALOG, run a modal session until
// EndDialog() is called, then tear down and return the result.
INT_PTR runModalDialog(int dialogID, HWND parent, DLGPROC proc, LPARAM initParam);
```

- [ ] **Step 2: Write `dialog_modal.mm`**

```objc
#import <Cocoa/Cocoa.h>
#include "dialog_modal.h"
#include "dialog_template.h"
#include "dialog_controls.h"
#include "handle_registry.h"

#include <unordered_map>

namespace {

// Per-dialog state while it's running modally.
struct DialogRuntime
{
    NSWindow* window = nil;
    DLGPROC proc = nullptr;
    INT_PTR result = 0;
    bool ended = false;
};

std::unordered_map<uintptr_t, DialogRuntime>& runtimes()
{
    static std::unordered_map<uintptr_t, DialogRuntime> m;
    return m;
}

} // namespace

// Implemented in win32_message.mm — exposed for EndDialog / button actions.
DialogRuntime* dialog_getRuntime(HWND hDlg)
{
    auto it = runtimes().find(reinterpret_cast<uintptr_t>(hDlg));
    return (it == runtimes().end()) ? nullptr : &it->second;
}

// --- NSButton target that posts WM_COMMAND back to the dialog proc ---

@interface DlgButtonAction : NSObject
@property (nonatomic, assign) HWND dialog;
@property (nonatomic, assign) int controlId;
- (void)onClick:(id)sender;
@end

@implementation DlgButtonAction
- (void)onClick:(id)sender
{
    auto* rt = dialog_getRuntime(self.dialog);
    if (!rt || !rt->proc) return;
    // LOWORD=id, HIWORD=BN_CLICKED (0)
    WPARAM w = static_cast<WPARAM>(self.controlId);
    rt->proc(self.dialog, WM_COMMAND, w, 0);
}
@end

static NSMutableArray<DlgButtonAction*>* buttonActionsFor(HWND hDlg)
{
    static NSMutableDictionary* map = [NSMutableDictionary dictionary];
    NSValue* key = [NSValue valueWithPointer:hDlg];
    NSMutableArray* arr = map[key];
    if (!arr) { arr = [NSMutableArray array]; map[key] = arr; }
    return arr;
}

INT_PTR runModalDialog(int dialogID, HWND parent, DLGPROC proc, LPARAM initParam)
{
    const DialogTemplateCpp* t = findDialogTemplate(dialogID);
    if (!t)
    {
        NSLog(@"[dialog_modal] no template registered for id=%d", dialogID);
        return -1;
    }

    constexpr double duX = 1.6;
    constexpr double duY = 1.9;

    NSRect contentRect = NSMakeRect(0, 0, t->cx * duX, t->cy * duY);
    NSPanel* panel = [[NSPanel alloc] initWithContentRect:contentRect
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
          backing:NSBackingStoreBuffered
            defer:NO];
    panel.title = [[NSString alloc]
        initWithBytes:t->title.data()
               length:t->title.size() * sizeof(wchar_t)
             encoding:NSUTF32LittleEndianStringEncoding];
    [panel center];

    // Register the panel as an HWND.
    HandleRegistry::WindowInfo info{};
    info.nativeWindow = (__bridge_retained void*)panel;
    info.nativeView = (__bridge void*)panel.contentView;
    info.className = L"Dialog";
    info.parent = parent;
    HWND hDlg = HandleRegistry::createWindow(std::move(info));

    DialogRuntime rt;
    rt.window = panel;
    rt.proc = proc;
    runtimes()[reinterpret_cast<uintptr_t>(hDlg)] = rt;

    // Create controls.
    for (const auto& desc : t->controls)
    {
        HWND childHwnd = createDialogControl(desc,
            (__bridge void*)panel.contentView, hDlg, duX, duY);

        // Wire Button / Checkbox / Radio clicks to the WM_COMMAND pump.
        if (desc.kind == DlgControlClass::Button ||
            desc.kind == DlgControlClass::Checkbox ||
            desc.kind == DlgControlClass::Radio)
        {
            auto* info = HandleRegistry::getWindowInfo(childHwnd);
            if (info && info->nativeView)
            {
                NSButton* btn = (__bridge NSButton*)info->nativeView;
                DlgButtonAction* action = [DlgButtonAction new];
                action.dialog = hDlg;
                action.controlId = desc.id;
                [buttonActionsFor(hDlg) addObject:action];
                btn.target = action;
                btn.action = @selector(onClick:);
            }
        }
    }

    // WM_INITDIALOG — wParam = handle of the default control focus (0 ok),
    // lParam = the app-supplied initParam (dialog passes `this` pointer here).
    proc(hDlg, WM_INITDIALOG, 0, initParam);

    // Run modal.
    [NSApp runModalForWindow:panel];

    // Retrieve result written by EndDialog.
    INT_PTR result = runtimes()[reinterpret_cast<uintptr_t>(hDlg)].result;

    // Tear down.
    [panel orderOut:nil];
    [buttonActionsFor(hDlg) removeAllObjects];
    runtimes().erase(reinterpret_cast<uintptr_t>(hDlg));
    HandleRegistry::destroyWindow(hDlg);

    return result;
}
```

- [ ] **Step 3: Replace `DialogBoxParamW` in `win32_message.mm`**

Remove or rewrite the current implementation at `macos/shim/src/win32_message.mm:261-300`:

```cpp
#include "dialog_modal.h"

// Forward-declared in dialog_modal.mm
struct DialogRuntime;
DialogRuntime* dialog_getRuntime(HWND hDlg);

INT_PTR DialogBoxParamW(HINSTANCE hInstance, LPCWSTR lpTemplateName,
                        HWND hWndParent, DLGPROC lpDialogFunc, LPARAM dwInitParam)
{
    // lpTemplateName is MAKEINTRESOURCEW(id); the low word is the ID.
    uintptr_t raw = reinterpret_cast<uintptr_t>(lpTemplateName);
    int dialogID = static_cast<int>(raw & 0xFFFF);
    return runModalDialog(dialogID, hWndParent, lpDialogFunc, dwInitParam);
}
```

- [ ] **Step 4: Make `EndDialog` route to the new runtime**

Still in `win32_message.mm`, rewrite `EndDialog` (`macos/shim/src/win32_message.mm:308`):

```cpp
BOOL EndDialog(HWND hDlg, INT_PTR nResult)
{
    if (auto* rt = dialog_getRuntime(hDlg))
    {
        rt->result = nResult;
        rt->ended = true;
        [NSApp stopModal];
        return TRUE;
    }
    return FALSE;
}
```

- [ ] **Step 5: Add escape-key / close-box handling**

Add to `dialog_modal.mm`'s `runModalDialog` before `[NSApp runModalForWindow:]`:

```objc
// Intercept window close as IDCANCEL (matches Windows).
[[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
    object:panel queue:nil usingBlock:^(NSNotification* note) {
        auto* rt = dialog_getRuntime(hDlg);
        if (rt && !rt->ended && rt->proc)
            rt->proc(hDlg, WM_COMMAND, IDCANCEL, 0);
    }];
```

- [ ] **Step 6: Add CMake entry**

Append to `SHIM_SOURCES`:

```cmake
"${CMAKE_CURRENT_SOURCE_DIR}/shim/src/dialog_modal.mm"
```

- [ ] **Step 7: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
```

Expected: clean. Dialog infrastructure is now usable but no dialog opens yet because the plugin's dialog files are still stubbed.

- [ ] **Step 8: Commit**

```bash
git add macos/shim/include/dialog_modal.h \
        macos/shim/src/dialog_modal.mm \
        macos/shim/src/win32_message.mm \
        macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat(shim): render modal dialogs from registered templates

DialogBoxParamW now resolves MAKEINTRESOURCEW(id) against the template
registry, constructs a Cocoa NSPanel populated with typed controls, and
dispatches WM_INITDIALOG plus WM_COMMAND on button clicks. EndDialog
stops the modal loop and returns the result the plugin set.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 10: Wire `CompareOptionsDialog.cpp` into the plugin build

Stop stubbing the Compare Options dialog; compile the real plugin source.

**Files:**
- Modify: `macos/shim/src/compareplus_stubs.cpp`
- Modify: `macos/CMakeLists.txt`

- [ ] **Step 1: Remove the stubs**

Delete these two lines from `macos/shim/src/compareplus_stubs.cpp`:

```cpp
intptr_t CALLBACK CompareOptionsDialog::run_dlgProc(UINT, WPARAM, LPARAM) { return 0; }
UINT              CompareOptionsDialog::doDialog(UserSettings*)           { return 0; }
```

- [ ] **Step 2: Add the real source to the `ComparePlus` target**

In `macos/CMakeLists.txt`, edit the `add_library(ComparePlus MODULE ...)` list (around line 482-492):

```cmake
add_library(ComparePlus MODULE
    "${COMPARE_PLUS_DIR}/src/Compare.cpp"
    "${COMPARE_PLUS_DIR}/src/NppHelpers.cpp"
    "${COMPARE_PLUS_DIR}/src/Tools.cpp"
    "${COMPARE_PLUS_DIR}/src/Strings.cpp"
    "${COMPARE_PLUS_DIR}/src/UserSettings.cpp"
    "${COMPARE_PLUS_DIR}/src/Engine/Engine.cpp"
    "${COMPARE_PLUS_DIR}/src/CompareOptionsDlg/CompareOptionsDialog.cpp"  # <-- NEW
    "${CMAKE_SOURCE_DIR}/shim/src/compareplus_stubs.cpp"
)
```

- [ ] **Step 3: Check for missing shim symbols**

```bash
cmake --build macos/build --target ComparePlus 2>&1 | grep -E "Undefined|error:" | head -30
```

Likely unresolved symbols (add each as a trivial stub in `compareplus_stubs.cpp` if already a no-op Win32 fn, or a real implementation in `win32_message.mm` / `win32_controls.mm`):

- `EnableThemeDialogTexture` — add no-op stub returning `S_OK`.
- `registerDlgForDarkMode` — defined in `NppHelpers` already; if it calls stubbed Win32 dark-mode APIs, add no-op stubs for those (e.g. `DarkMode_AllowDarkModeForWindow` etc.).
- `updateDlgCtrlTxt` — defined in `NppHelpers.cpp`; likely already compiles.

Add each missing stub one by one, re-running the build, until the plugin links.

- [ ] **Step 4: Install and smoke test**

```bash
cmake --build macos/build --target install_compare_plus
open macos/build/Debug/MacNotePlusPlus.app
```

Plugins → ComparePlus → **Compare Options** → verify:
- A window opens with the expected title.
- All controls from the template are present and positioned reasonably (perfect pixel-match to Windows is not required; legibility is).
- Toggling a checkbox changes its visual state.
- OK dismisses and returns IDOK; Cancel returns IDCANCEL.
- Reopening the dialog shows the persisted state of any checkbox toggled before OK.

If any control is misplaced or missing, update `dialog_template_compare_options.mm` to match `CompareOptionsDialog.rc` more faithfully.

- [ ] **Step 5: Commit**

```bash
git add macos/shim/src/compareplus_stubs.cpp macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat: wire Compare Options dialog into ComparePlus

Drops the CompareOptionsDialog stubs and compiles the real upstream
source. Clicks on Compare Options now open a working dialog whose
controls persist to UserSettings.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 11: Hand-translate `IDD_SETTINGS_DIALOG`

Same pattern as Task 5, larger dialog. The Settings dialog includes the custom `ColorCombo` controls, which are mapped to `NSColorWell` via `DlgControlClass::ColorCombo`.

**Files:**
- Inspect: `plugins/comparePlus/src/SettingsDlg/SettingsDialog.rc`
- Create: `macos/shim/src/dialog_template_settings.mm`

- [ ] **Step 1: Read `SettingsDialog.rc`** and enumerate every control as in Task 5.

- [ ] **Step 2: Write `dialog_template_settings.mm`**

Structure identical to `dialog_template_compare_options.mm`:

```objc
#import <Foundation/Foundation.h>
#include "dialog_template.h"
#include "../../plugins/comparePlus/src/resource.h"

namespace {
struct AutoRegister
{
    AutoRegister()
    {
        DialogTemplateCpp t;
        t.id = IDD_SETTINGS_DIALOG;
        t.title = L"ComparePlus   Settings";
        // ... dimensions from the .rc ...
        t.controls = {
            // Every control from SettingsDialog.rc.
            // Use DlgControlClass::ColorCombo for the six IDC_COMBO_*_COLOR
            // controls; Use DlgControlClass::UpDown for the spin controls
            // (IDC_PART_TRANSP_SPIN, IDC_CARET_TRANSP_SPIN, IDC_CHANGE_RES_SPIN);
            // Use DlgControlClass::Edit for IDC_*_EDIT; the rest are
            // Checkbox / Radio / GroupBox / Static / Button.
        };
        registerDialogTemplate(t);
    }
};
AutoRegister _register;
}
```

- [ ] **Step 3: Add to CMake**

```cmake
"${CMAKE_CURRENT_SOURCE_DIR}/shim/src/dialog_template_settings.mm"
```

- [ ] **Step 4: Build**

```bash
cmake --build macos/build --target MacNotePlusPlus
```

- [ ] **Step 5: Commit**

```bash
git add macos/shim/src/dialog_template_settings.mm macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat(shim): hand-translated IDD_SETTINGS_DIALOG template

Includes ColorCombo controls mapped to NSColorWell and spin controls
mapped to NSStepper via the UpDown descriptor.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 12: Wire `SettingsDialog.cpp` + `ColorCombo.cpp` into the plugin build

**Files:**
- Modify: `macos/shim/src/compareplus_stubs.cpp`
- Modify: `macos/CMakeLists.txt`

- [ ] **Step 1: Remove `SettingsDialog` stubs**

Delete from `compareplus_stubs.cpp`:

```cpp
intptr_t CALLBACK SettingsDialog::run_dlgProc(UINT, WPARAM, LPARAM) { return 0; }
UINT              SettingsDialog::doDialog(UserSettings*)           { return 0; }
void ColorCombo::init(HINSTANCE, HWND, HWND) {}
```

- [ ] **Step 2: Compile the real sources**

In `add_library(ComparePlus MODULE ...)`:

```cmake
"${COMPARE_PLUS_DIR}/src/SettingsDlg/SettingsDialog.cpp"
"${COMPARE_PLUS_DIR}/src/SettingsDlg/ColorCombo.cpp"
```

- [ ] **Step 3: Build + resolve missing symbols**

```bash
cmake --build macos/build --target ComparePlus 2>&1 | grep -E "Undefined|error:" | head -40
```

`ColorCombo` calls custom-draw Win32 APIs (`DrawFocusRect`, `OwnerDraw` messages). The `DlgControlClass::ColorCombo` substitution means `ColorCombo::init` needs to bypass Win32 entirely and just associate itself with the `NSColorWell` backing the control. Replace `ColorCombo::init`'s body in the shim:

```cpp
// In compareplus_stubs.cpp — replacement for the removed no-op:
void ColorCombo::init(HINSTANCE, HWND hParent, HWND hCombo)
{
    _hParent = hParent;
    _hCombo = hCombo;
    // Cocoa substitution: the control already exists as an NSColorWell.
    // Expose get/set via SendMessage overrides if any code path reads
    // the current color. For V1 we trust that SetColor / GetColor
    // (see below) are the only accessors.
}
```

Then add color get/set handlers in `win32_controls.mm` so that when `ColorCombo::SetColor(COLORREF)` sends its internal message to the underlying `HWND`, we translate to `NSColorWell.color`. Inspect `ColorCombo.cpp` for its exact public API and add matching overrides.

- [ ] **Step 4: Smoke test**

Plugins → ComparePlus → **Settings**. Verify:
- Dialog opens with all groups visible.
- Color wells render the expected default colors.
- Changing any value and hitting OK persists through an app restart (end-to-end verification for Task 13 happens next).

- [ ] **Step 5: Commit**

```bash
git add macos/shim/src/compareplus_stubs.cpp macos/CMakeLists.txt
git commit -m "$(cat <<'EOF'
feat: wire Settings dialog into ComparePlus

Drops the SettingsDialog + ColorCombo stubs and compiles the upstream
source. ColorCombo::init binds the NSColorWell substitute; color
get/set flow through SendMessage overrides.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 13: Verify `UserSettings::save()` persists to disk

**Files:** None (testing + possibly shim fix)

- [ ] **Step 1: Inspect what path the plugin writes to**

```bash
grep -n "WritePrivateProfileStringW\|GetPluginsConfigDir\|Settings.ini" \
  plugins/comparePlus/src/UserSettings.cpp macos/shim/src/*.mm
```

Expected: `UserSettings::save()` calls `WritePrivateProfileStringW` against a path derived from `NPPM_GETPLUGINSCONFIGDIR`. The shim's `WritePrivateProfileStringW` must resolve wide-string paths to the `~/Library/Application Support/MacNote++/plugins/Config/` tree.

- [ ] **Step 2: Run the app, change a setting, quit, inspect disk**

```bash
ls ~/Library/Application\ Support/MacNote++/plugins/Config/
```

Expected: a `ComparePlus.ini` (or similar) file whose contents reflect the change.

If the file is missing or empty, trace through the shim's `WritePrivateProfileStringW` to find the path-resolution bug and fix it.

- [ ] **Step 3: Relaunch and verify persistence**

Quit the app, relaunch, open the Settings dialog, confirm values match what was saved.

- [ ] **Step 4: Commit any shim fixes needed**

If fixes were required in `win32_file_io.mm` or similar, commit them separately:

```bash
git commit -m "fix(shim): resolve plugin config path for WritePrivateProfileStringW ..."
```

If no fix was needed, this task produces no commit — record the verification in the PR description.

### Task 14: Open PR 2

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/compare-plus-dialog-renderer
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --base feature/compare-plus-port \
  --title "feat: render ComparePlus Options and Settings dialogs on macOS" \
  --body "$(cat <<'EOF'
## Summary
- Hand-translated IDD_COMPARE_OPTIONS_DIALOG and IDD_SETTINGS_DIALOG templates registered at startup.
- DialogBoxParamW looks up by ID, builds a Cocoa NSPanel of typed NSControls, pumps WM_INITDIALOG / WM_COMMAND into the plugin's DLGPROC.
- HandleRegistry extended with dlgItemId / dlgParent so GetDlgItem resolves children.
- BM_* / CB_* / EM_SETLIMITTEXT / UDM_SETRANGE implemented in the control dispatcher.
- CompareOptionsDialog.cpp and SettingsDialog.cpp + ColorCombo.cpp compiled into ComparePlus.dylib (stubs removed).
- UserSettings persistence verified end-to-end.

## Test plan

- [ ] Plugins → ComparePlus → Compare Options opens a populated dialog
- [ ] Toggling a checkbox and hitting OK persists; reopen shows the change
- [ ] Cancel reverts to previously-saved state
- [ ] Plugins → ComparePlus → Settings opens; color wells, spin edits, and radio groups render
- [ ] Changing a setting and running Compare afterward honours the new value
- [ ] Quit, relaunch, reopen dialog — change survived
- [ ] `ls ~/Library/Application\ Support/MacNote++/plugins/Config/` shows a ComparePlus.ini

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage pass:**
- §1.1 success criteria — Tasks 3 (PR 1) and 10, 12, 13 (PR 2) cover them.
- §3.1 second-view lifecycle — pre-existing commit; Task 1 adds the missing visibility trigger.
- §3.2 NPPM stubs — Task 1.
- §3.3 Scintilla bridge verification — resolved in plan header (no work needed).
- §3.4 menu grayed-state — covered as a smoke-test observation in Task 3; follow-up only if the manual test reveals a gap.
- §3.5 manual smoke — Task 3.
- §4 dialog renderer — Tasks 5-12.
- §4.7 settings persistence — Task 13.
- §5.1 launch-time invariants — Task 2.
- §5.2 observability — Task 2 covers the debug-gated logs; dialog-parse logging is a natural extension if issues arise and is deferred.
- §5.4 branch strategy — Task 0 and Task 14.

**Placeholder scan:** No "TBD", "TODO", or "implement later" in the plan. Task 5 and Task 11 intentionally require the implementer to transcribe each `.rc` control — this is a bounded, explicit activity, not a placeholder. Task 13 has a conditional ("if fixes were required") which is appropriate because verification may find nothing to fix.

**Type consistency:**
- `DlgControlClass` enum values (`Button`, `Checkbox`, `Radio`, `GroupBox`, `Static`, `Edit`, `ComboBox`, `EditCombo`, `UpDown`, `ColorCombo`) are used identically in Tasks 5, 7, 11.
- `DialogTemplateCpp`, `DlgControlDescriptor`, `registerDialogTemplate`, `findDialogTemplate` — consistent across all consumers.
- `findDialogChild`, `dlgItemId`, `dlgParent` — consistent between Task 6 (definition) and Task 7 (consumer).
- `handleLineNumberWidthModeChange`, `assertPluginPreInitInvariants`, `dumpPluginPostReadyState`, `hostInitiatedSplit` — each defined once, used consistently.
- `runModalDialog`, `dialog_getRuntime` — consistent between `dialog_modal.mm`, `dialog_modal.h`, and the `win32_message.mm` call sites.

No drift detected.

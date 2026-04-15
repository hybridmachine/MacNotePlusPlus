# ComparePlus Menu Wiring — Design

**Date:** 2026-04-14
**Branch context:** `feature/compare-plus-port`
**Status:** Spec approved, ready for plan authoring.

## 1. Overview & Scope

### Goal

Make **Plugins → ComparePlus → Compare** produce a working side-by-side diff on macOS, and make **Plugins → ComparePlus → Compare Options** and **Settings** open functional dialogs. The ComparePlus dylib already loads and its menu is clickable (commit `f1e6e1a73`); this work closes the gap between "click does nothing visible" and "click does a real diff."

### In Scope

- **PR 1 — Basic compare end-to-end.** Commands: `CMD_SET_FIRST`, `CMD_COMPARE`, `CMD_CLEAR_ACTIVE`, `CMD_CLEAR_ALL`. The second Scintilla view is eager-allocated so the Compare Engine has a valid `nppData._scintillaSecondHandle` at `setInfo` time. Cosmetic NPPM stubs (`NPPM_HIDETABBAR`, `NPPM_SETSTATUSBAR`, `NPPM_GET/SETLINENUMBERWIDTHMODE`, `NPPM_ADDTOOLBARICON_FORDARKMODE`) return sensible defaults so the Engine does not stall.
- **PR 2 — Options + Settings dialogs.** A minimal Win32 dialog-template renderer backed by Cocoa. `StaticDialog::create()` and `::destroy()` become real implementations; `CompareOptionsDialog::doDialog()` and `SettingsDialog::doDialog()` open interactive dialogs that persist to `UserSettings`.

### Out of Scope

- Diff navigation commands (`CMD_PREV`, `CMD_NEXT`, `CMD_FIRST`, `CMD_LAST`, `CMD_PREV_CHANGE_POS`, `CMD_NEXT_CHANGE_POS`, `CMD_COMPARE_SUMMARY`).
- Selection compare, Find-Unique modes, Last-save / Clipboard / Git / SVN diff (need `LibHelpers` or temp-buffer plumbing).
- NavBar docking panel (`NPPM_DMM*`).
- Toolbar icons (`NPPM_ADDTOOLBARICON_FORDARKMODE` ships as a cosmetic no-op only).
- Generalizing the dialog renderer beyond what the two target dialogs require.

### Success Criteria

- **PR 1:** Open two buffers; click **Set as First** on A; switch to B; click **Compare** — view splits, A on the left and B on the right, changed/added/deleted lines render ComparePlus markers and indicator colors. **Clear Active** / **Clear All** return the views to normal.
- **PR 2:** **Compare Options** opens a functional dialog; toggling fields and clicking OK persists to `UserSettings`; Cancel discards. Same for **Settings**. Subsequent compares honor the new settings.

## 2. Architecture

Three subsystems participate.

```
 ┌────────────────────────────────────────────────────────────────┐
 │ ComparePlus.dylib (vendored, unmodified)                       │
 │   Compare.cpp → compare() → Engine/Engine.cpp → markers via    │
 │     sciFunc(SCI_MARKERADD, …) on BOTH Scintilla handles        │
 │   StaticDialog::create()  ──┐                                  │
 │   CompareOptionsDialog::    │   (currently stubbed no-ops)     │
 │   SettingsDialog::          │                                  │
 └───────────────────┬─────────┴──────────────────────────────────┘
                     │ Win32 shim API boundary
 ┌───────────────────┴────────────────────────────────────────────┐
 │ macos/shim/src/  (Win32 API surface on macOS)                  │
 │   compareplus_stubs.cpp — NavDialog / ProgressDlg stay stubbed │
 │   dialog_template.mm (new, PR 2) — parses DLGTEMPLATE[EX],     │
 │     builds a Cocoa NSWindow of NSControls, routes WM_COMMAND   │
 │     back into the plugin's DLGPROC                             │
 │   StaticDialog real create()/destroy() live here (PR 2)        │
 └───────────────────┬────────────────────────────────────────────┘
                     │
 ┌───────────────────┴────────────────────────────────────────────┐
 │ macos/platform/  (host)                                        │
 │   app_delegate.mm — create scintillaSecondHwnd eagerly (PR 1)  │
 │   split_view.mm   — show/hide the existing HWND, don't         │
 │                     destroy/recreate (PR 1)                    │
 │   nppm_handler.mm — add no-op stubs for HIDETABBAR,            │
 │                     SETSTATUSBAR, GET/SETLINENUMBERWIDTHMODE   │
 │   menu_builder.mm — unchanged; clicks already dispatch right   │
 └────────────────────────────────────────────────────────────────┘
```

### Call flow: Compare (after PR 1)

1. User clicks **Plugins → ComparePlus → Compare**.
2. `MainWndProc` `WM_COMMAND` → `pluginManager().runPluginCommand(i)` → plugin's `CompareWhole()` → `compare()`.
3. `compare()` captures current buffer ID and asserts two views are available; the second HWND is real even if its NSView is currently hidden.
4. Engine runs the LCS diff in a background thread, consulting the stubbed `ProgressDlg::IsCancelled()` (always `false`).
5. Engine issues `SCI_MARKERADD` / `SCI_INDICATORFILLRANGE` / `SCI_SETSEL` against both handles. These flow through `scintilla_bridge.mm` and render into the two `NSView`s.
6. Engine calls `NPPM_SETMENUITEMCHECK` / `NPPM_HIDETABBAR` (no-op) / `NPPM_SETSTATUSBAR` (no-op). The diff itself is visible; only chrome strings are missing.
7. If the second NSView was hidden, the host un-hides it on the first Scintilla write to the second handle (trigger described in 3.1).

### Call flow: Options dialog (after PR 2)

1. User clicks **Plugins → ComparePlus → Compare Options**.
2. Plugin's `openOptions()` → `CompareOptionsDialog::doDialog()` → `StaticDialog::create(IDD_COMPARE_OPTIONS_DIALOG, …)`.
3. `StaticDialog::create()` (now real) pulls the compiled `DLGTEMPLATE` resource out of the dylib, walks it, and constructs a Cocoa `NSWindow` of typed `NSControl`s.
4. The dialog pump dispatches `WM_INITDIALOG` into the plugin's registered `DLGPROC`, which populates fields from `UserSettings`.
5. Button clicks post `WM_COMMAND(IDOK | IDCANCEL | custom)` back into the `DLGPROC`.
6. On `IDOK` / `IDCANCEL`, the shim ends the modal session; `doDialog()` returns and the plugin persists to `UserSettings`.

### Interface contract

- **Upstream plugin source is not modified.** Everything the plugin observes must match upstream semantics: `nppData` valid at `setInfo`, Scintilla handles valid for the whole run, `StaticDialog::create()` behaves like a modeless Win32 dialog.
- Host split-view UI stays user-controlled. Eager-allocating the second Scintilla HWND is invisible to the user; the NSView only becomes visible when (a) the user splits, or (b) Compare is active.

## 3. PR 1 — Basic Compare End-to-End

### 3.1 Second Scintilla view lifecycle

**Today.** `ctx().scintillaSecondHwnd` is created on first split (`split_view.mm:152`) and destroyed on unsplit (`app_delegate.mm:671-674`). Plugin `setInfo` runs at launch (`app_delegate.mm:552-558`), so the plugin caches `_scintillaSecondHandle = nullptr` forever.

**After.** The host owns a real, always-valid second Scintilla HWND from launch to shutdown. Visibility changes, not existence.

- `app_delegate.mm` — in `applicationDidFinishLaunching`, call the same `HandleRegistry::createWindow` path `split_view.mm` uses, **before** `pluginManager().init(nppData)`. The NSView is created `hidden = YES` and not added to the split-view container.
- `split_view.mm:152` — remove the "create on first split" branch; un-hide the existing NSView and install it into the `NSSplitView`.
- `split_view.mm` unsplit path — remove the NSView from the split container and hide it; **do not** call `HandleRegistry::destroyWindow()`. Document the rule inline.
- `app_delegate.mm:671-674` — shutdown destroys the handle exactly once, at the same point the main Scintilla HWND tears down.
- `NPPM_GETNBOPENFILES` split-view dedup (`nppm_handler.mm:116-137`) — unchanged.

**Compare-driven visibility.** The plugin calls `SCI_*` against `_scintillaSecondHandle` once compare starts. We add a one-shot hook in `scintilla_bridge.mm`: the first `SCI_*` directed at the hidden second handle un-hides the NSView and installs it into the split container. On `Clear All` / `Clear Active` the plugin calls `NPPM_HIDETABBAR(false)` which we treat as the "compare ended" signal and use to hide the second view again. (`NPPM_HIDETABBAR` has no real tab-bar semantics on macOS; we reuse the signal.)

### 3.2 NPPM message stubs

Add to `nppm_handler.mm` (replacing the current `NSLog` "Unhandled" fallthroughs):

- `NPPM_HIDETABBAR` — record the state; `false` hides the second view again. Otherwise a cosmetic no-op (we do not actually hide the tab bar on macOS).
- `NPPM_SETSTATUSBAR` — cosmetic no-op `return TRUE`.
- `NPPM_GETLINENUMBERWIDTHMODE` / `NPPM_SETLINENUMBERWIDTHMODE` — return / accept `LINENUMWIDTH_DYNAMIC` (0).
- `NPPM_ADDTOOLBARICON_FORDARKMODE` — cosmetic no-op `return TRUE`.

### 3.3 Engine / Scintilla bridge verification

The Engine renders diffs via these Scintilla messages:
- `SCI_MARKERDEFINE`, `SCI_MARKERADD`, `SCI_MARKERDELETEALL`
- `SCI_INDICSETSTYLE`, `SCI_INDICSETFORE`, `SCI_INDICATORFILLRANGE`
- `SCI_SETFOLDLEVEL`, `SCI_SETLINESTATE`, `SCI_ANNOTATIONSETTEXT`

The plan pass confirms each is handled by `scintilla_bridge.mm`. Missing messages go into the plan's task list. Stubbed-but-important ones (e.g. annotations) are called out as possibly-visible gaps rather than silently broken.

The stubbed `ProgressDlg` (`compareplus_stubs.cpp:42-66`) stays: `IsCancelled() == false` so the engine never aborts; `Advance() == true` so it never stalls. Users will not see a progress bar. Acceptable for V1.

### 3.4 Menu enable/disable sync

`NppState::enableClearCommands()` (`Compare.cpp:619-633`) calls `::EnableMenuItem` on the HMENU from `NPPM_GETMENUHANDLE(NPPPLUGINMENU)`. `EnableMenuItem` is in the shim; the plan verifies the enabled flag reaches the `NSMenuItem`. If not, a targeted refresh is added.

### 3.5 Testing plan — PR 1

**Manual smoke test:**
1. Launch app, open `A.txt` and `B.txt`.
2. On A, Plugins → ComparePlus → **Set as First**. No visible change.
3. Switch to B, Plugins → ComparePlus → **Compare**. Split view appears, diff markers render on both panes, changed lines are colored.
4. Plugins → ComparePlus → **Clear Active**. Markers disappear; split view collapses to single pane.
5. Repeat with **Compare** + **Clear All**.
6. Compare a file with itself → "files are identical" message box from the plugin (confirms `MessageBoxW` path).
7. With three files open, Set-as-First on one, compare the other two → both pairs can coexist.

**Automated (targeted):**
- Scintilla-bridge unit test: `SCI_MARKERADD` on the second view's handle is readable back via `SCI_MARKERGET`. Asserts "second handle is live."
- Launch-time assertion: `ctx().scintillaSecondHwnd != nullptr` by the time `pluginManager().init()` runs.

### 3.6 Risks — PR 1

- **Memory cost of always-allocated second view.** A Scintilla instance is ~a few MB. Acceptable.
- **Visibility trigger relies on the plugin routing Scintilla writes through our bridge.** ComparePlus uses `sciFunc(h, …)` with `h` from `nppData`, so `HandleRegistry` sees every call. Future plugins that cache `SciFnDirect` via `SCI_GETDIRECTFUNCTION` could bypass the bridge — out of scope for V1.
- **Menu-grayed state may not re-sync on every call.** Mitigation in 3.4; fallback is re-sync on buffer activation.

## 4. PR 2 — Options & Settings Dialogs

### 4.1 Target dialog inventory

The plan pass reads the two `.rc` files and produces a control histogram:
- `plugins/comparePlus/src/CompareOptionsDlg/CompareOptionsDialog.rc`
- `plugins/comparePlus/src/SettingsDlg/SettingsDialog.rc`

Expected control classes:
- `BUTTON` with `BS_DEFPUSHBUTTON`, `BS_PUSHBUTTON`, `BS_CHECKBOX`, `BS_GROUPBOX`, `BS_AUTORADIOBUTTON`
- `STATIC`
- `EDIT`
- `COMBOBOX` (`CBS_DROPDOWNLIST`)

Custom controls (`ColorCombo`, `URLCtrl`): V1 substitutes `NSColorWell` / `NSTextField`.

### 4.2 Renderer architecture

**New files in `macos/shim/src/`:**
- `dialog_template.mm` — parses `DLGTEMPLATE` and `DLGTEMPLATEEX`, yields `{className, text, id, rect, style}` descriptors.
- `dialog_window.mm` — builds a Cocoa `NSWindow` (sheet style) from descriptors; maintains an `HWND → NSControl` lookup so `GetDlgItem(hwnd, id)` works.
- `dialog_msg_pump.mm` — pumps `WM_INITDIALOG`, `WM_COMMAND`, `WM_NOTIFY`, `WM_CLOSE`, `WM_DESTROY` into the plugin's `DLGPROC`; translates Cocoa actions to Win32 messages.

**Existing files that change:**
- `compareplus_stubs.cpp` — `StaticDialog::~StaticDialog`, `create()`, `destroy()` forward to the new renderer. Other stubbed dialogs stay stubbed.
- `win32_message.mm` — `IsDialogMessageW()` recognizes our live dialog windows and dispatches into the pump.

**Menu accelerator forwarding in `macos/platform/`:** when a compare dialog is frontmost, Enter maps to `IDOK`, Escape to `IDCANCEL`.

### 4.3 Win32 → Cocoa control mapping

| Win32 class / style                         | Cocoa control                               | Notes                                             |
|---------------------------------------------|---------------------------------------------|---------------------------------------------------|
| `BUTTON` + `BS_DEFPUSHBUTTON` / `PUSHBUTTON`| `NSButton` (push)                           | Default button: `keyEquivalent = @"\r"`           |
| `BUTTON` + `BS_AUTOCHECKBOX`                | `NSButton` (switch on 11+, else check)      | `BM_GETCHECK` translated                          |
| `BUTTON` + `BS_AUTORADIOBUTTON`             | `NSButton` (radio), grouped by `WS_GROUP`   | Group = run between `WS_GROUP` bits               |
| `BUTTON` + `BS_GROUPBOX`                    | `NSBox` with title                          | Visual only                                       |
| `STATIC`                                    | `NSTextField` (label)                       |                                                   |
| `EDIT`                                      | `NSTextField` (editable)                    | `ES_NUMBER` → `NSNumberFormatter`                 |
| `COMBOBOX` + `CBS_DROPDOWNLIST`             | `NSPopUpButton`                             | `CB_ADDSTRING` / `CB_GETCURSEL` translated         |

Unknown control → placeholder `NSView` + warning log. Dialog still opens; the unknown control is inert.

### 4.4 Message translation

Implemented:
- `WM_INITDIALOG` — once, after controls exist, before sheet is shown.
- `WM_COMMAND(LOWORD=id, HIWORD=notification)` — from button clicks (`BN_CLICKED`), combo selection (`CBN_SELCHANGE`).
- `WM_CLOSE`, `WM_DESTROY` — sheet dismiss / teardown.
- `SendDlgItemMessageW` extended for `BM_SETCHECK`, `BM_GETCHECK`, `CB_ADDSTRING`, `CB_GETCURSEL`, `CB_SETCURSEL`, `EM_SETSEL`, `WM_GETTEXT`, `WM_SETTEXT`.

Not implemented in V1:
- `WM_NOTIFY` — unless the plan pass finds a `SysLink`/`Syslistview32` in the target `.rc` files.
- `WM_CTLCOLORDLG`, `WM_CTLCOLORSTATIC` — dialogs use system appearance.

### 4.5 Modal lifecycle

Upstream `doDialog()` is modeless with its own message loop. We model it as a **window-modal sheet** on the main window, driven by `[NSApp runModalForWindow:]`. `doDialog()` blocks until the sheet ends and returns the stored result. `EndDialog(hDlg, result)` calls `[NSApp stopModalWithCode:]` and stores the result on the `HWND`'s registry entry.

### 4.6 Wiring the two target dialogs

- Remove `CompareOptionsDialog::run_dlgProc` and `doDialog` stubs from `compareplus_stubs.cpp`.
- Remove `SettingsDialog::run_dlgProc` and `doDialog` stubs from `compareplus_stubs.cpp`.
- Add `plugins/comparePlus/src/CompareOptionsDlg/CompareOptionsDialog.cpp` and `plugins/comparePlus/src/SettingsDlg/SettingsDialog.cpp` to the `ComparePlus` target in `macos/CMakeLists.txt`.
- Add shim implementations for any missing symbols (likely `GetDlgItemText`, `CheckDlgButton`, `IsDlgButtonChecked`).

`NavDialog`, `AboutDialog`, `VisualFiltersDialog` stay stubbed. If `SettingsDialog` contains a button that opens `AboutDialog`, hide that button in our layout or route to a standard macOS about sheet.

### 4.7 Settings persistence

`UserSettings::save()` (in `UserSettings.cpp`) writes INI via `WritePrivateProfileStringW`. Verify the shim's INI writer resolves paths against `NPPM_GETPLUGINSCONFIGDIR` (`~/Library/Application Support/MacNote++/plugins/Config/`).

### 4.8 Testing plan — PR 2

**Manual:**
1. Launch app (after PR 1 merge). Plugins → ComparePlus → **Compare Options** — sheet opens with controls matching the Windows version.
2. Toggle "Detect moves," OK. Reopen dialog — checkbox is still on. Quit, relaunch, reopen — still on.
3. Change a field, Cancel — reopen, change not persisted.
4. Plugins → ComparePlus → **Settings** — repeat steps 1–3 on the settings sheet.
5. Change a compare-affecting setting (e.g. "ignore whitespace") and run **Compare** — verify new setting took effect.

**Automated (targeted):**
- Parse a synthetic `DLGTEMPLATEEX` blob; assert descriptor list.
- Round-trip `SendDlgItemMessageW(BM_SETCHECK / BM_GETCHECK)` against a synthetic dialog.

### 4.9 Risks — PR 2

- **Scope creep into a general-purpose renderer.** Guardrail: "only what these two dialogs use." The plan enumerates every distinct control style in the two `.rc` files; anything unexpected renders as a placeholder.
- **Custom-painted controls** (`ColorCombo`): V1 substitutes `NSColorWell`.
- **Dark-mode dialog chrome:** without `WM_CTLCOLORSTATIC`, dark-mode users see light dialog chrome over a dark app. Cosmetic; deferred.
- **Nested modal (Settings → About):** nested sheets are legal on macOS; pump must not deadlock. Verified in plan pass.
- **C++/Obj-C lifetime across the boundary:** pump retains Cocoa objects; `HandleRegistry` extended with a dialog-entry variant holding the `NSWindow` and control lookup.

## 5. Cross-Cutting Concerns

### 5.1 Testing strategy across both PRs

Three layers:
- **Launch-time assertions** (`macos/platform/plugin_invariants.mm`, gated behind `MACNOTE_PLUGIN_DEBUG=1`): `scintillaSecondHwnd != nullptr` after `applicationDidFinishLaunching`, plugin command-ID allocations within range, `NPPM_GETMENUHANDLE(NPPPLUGINMENU)` non-null. Catches ordering regressions; doesn't prove compare works.
- **Focused unit tests** (2 per PR, under `macos/tests/`). Catches single-unit regressions; doesn't exercise integration.
- **Manual smoke tests** (Sections 3.5, 4.8). Authoritative; recorded in PR description as a reviewer checklist.

We deliberately **do not** build automated end-to-end diff tests. That infrastructure does not exist in the macOS port and building it is a separate project.

### 5.2 Observability

- `NSLog` when the second Scintilla view un-hides / re-hides, with the triggering call.
- `NSLog` on dialog template parse, with the control-class histogram.
- `NSLog` when `StaticDialog::create()` hits the unknown-control fallback.

All gated behind `MACNOTE_PLUGIN_DEBUG=1`.

### 5.3 Rollback

- **PR 1:** eager-second-view change is self-contained in `app_delegate.mm` and `split_view.mm`; revert restores lazy behavior.
- **PR 2:** restore `StaticDialog::create()` no-ops in `compareplus_stubs.cpp`; remove `CompareOptionsDialog.cpp` / `SettingsDialog.cpp` from the target. Dialogs stop opening; compare from PR 1 still works.

### 5.4 Branching & review

- Both PRs land on new branches, not on `feature/compare-plus-port` (which carries a large pre-existing diff).
- Before starting PR 1, commit or stash the uncommitted changes on `feature/compare-plus-port` so the new branch forks from a green base.
- PR 1 branch: `feature/compare-plus-basic-compare` off the appropriate base (decided in plan pass — depends on whether `feature/compare-plus-port` is close to merging).
- PR 2 branch: `feature/compare-plus-dialog-renderer` off PR 1's merge commit.

### 5.5 Open questions for the plan pass

1. Exact `SCI_*` messages the Engine sends that our bridge doesn't handle yet. Resolution: grep `sciFunc(` in `plugins/comparePlus/src/Engine/Engine.cpp` and `NppHelpers.cpp`; cross-reference `scintilla_bridge.mm`.
2. Does the bridge forward `SCI_ANNOTATIONSETTEXT` / `SCI_ANNOTATIONSETSTYLE`? If not, plan decides PR 1 vs defer.
3. Exact control inventory for the two target `.rc` files. Produce a `{class, count, max instance ID}` table; flag unmapped controls.
4. Does `UserSettings::save()` succeed against `~/Library/Application Support/MacNote++/plugins/Config/` through the existing `WritePrivateProfileStringW` shim?
5. Does the "first write un-hides second view" trigger fire reliably, or does the Engine issue reads before writes? Enumerate the first N Scintilla calls in `Engine.cpp`'s setup prologue; widen trigger to "any `SCI_*` against second handle with compareMode implied" if reads precede writes.
6. Does `EnableMenuItem`'s disabled/enabled flag propagate to `NSMenuItem.enabled`?
7. What base branch should PR 1 fork from? `git log --graph master..feature/compare-plus-port` to decide.

### 5.6 YAGNI guardrails

Not built unless a later deliverable explicitly needs them:
- General extensible dialog-template renderer.
- `WM_CTLCOLOR*` handlers.
- Dark-mode dialog painting.
- `NPPM_DMM*` docking panel support.
- Toolbar icon rendering.
- Scintilla direct-function-pointer trampoline.
- Automated end-to-end diff tests.

If the plan pass finds any of these necessary, it escalates back to this spec rather than expanding scope silently.

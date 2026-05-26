# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PaperWasp 1.0** is an independent macOS port of the Notepad++ Win32 C++20 source code editor. It is **not a cross-platform rewrite** — instead it runs the original Win32 codebase against a header-only Win32-to-Cocoa shim, with a separate Objective-C++ platform layer providing the macOS-native UI shell. Not affiliated with or endorsed by the creators of Notepad++.

Active development happens on the `macos-port` branch; PRs target `master`.

## Build Commands

### macOS port (CMake + Xcode generator)

```bash
# First-time setup (or full clean rebuild)
cd macos/build
rm -rf *
cmake -G Xcode ..

# Dev binary at macos/build/{Debug,Release}/PaperWasp
cmake --build . --config Debug --target PaperWasp

# .app bundle at macos/dist/PaperWasp.app (used for icon/Finder testing & release)
cmake --build . --config Release --target PaperWasp_package

# Unsigned DMG at macos/dist/PaperWasp-unsigned.dmg
cmake --build . --target PaperWasp_dmg
```

**Must use `-G Xcode`.** The default Makefiles generator fails on deeply nested object paths in this repo.

### Signing, notarization, and releases

Releases use the tag convention `paperwasp-vX.Y.Z` (older `v1.0.X` tags are pre-rename). Build the `.app` first, then run:

```bash
export CODESIGN_IDENTITY="Developer ID Application: ..."
export APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=...
macos/scripts/sign-and-notarize.sh    # signs .app inside-out, builds signed DMG, notarizes, staples both
```

Artifacts land in `macos/dist/PaperWasp.{app,dmg}`. The script is the canonical signing path — the `PaperWasp_sign` cmake target is a simpler subset and is not used for releases. Full release procedure is in the `macos-release` skill.

### Windows builds (legacy upstream)

The Windows build paths still exist but are not exercised on macOS. MSBuild solution at `PowerEditor/visual.net/notepadPlus.sln` (requires VS 2022 v143 toolset, builds Scintilla/Lexilla as dependencies). MinGW build at `PowerEditor/gcc/` via `mingw32-make`. See `AGENTS.md` or `.github/copilot-instructions.md` for full Windows command details.

## Tests

The repo's test suites (`PowerEditor/Test/FunctionList/`, `PowerEditor/Test/UrlDetection/`, `PowerEditor/Test/xmlValidator/`) are **Windows-only** and require a built `notepad++.exe`. There is no macOS test runner. When adding macOS-only features, verify by running the built `.app` manually.

CI (`.github/workflows/CI_build.yml`) is Windows-only. Commit-title flags `[force all]`, `[force one]`, `[force xml]`, `[force none]` scope CI jobs.

## Architecture

### Two-layer split: shim + platform

```
Notepad++ Win32 C++ source  ──►  macos/shim/include/windows.h  ──►  Cocoa/AppKit
        (PowerEditor/)              (header-only Win32 API)         (NSWindow, NSMenu, …)

Application entry point & UI shell:  macos/platform/*.mm  (Objective-C++)
```

- **`macos/shim/`** — header-only Win32 API surface (`windows.h`, `winuser.h`, etc.) plus `.mm` implementations that back Win32 calls with Cocoa. **Does NOT define `WIN32`/`_WIN32`** — defining them breaks C++ stdlib on macOS. Code that needs to branch on platform should use `__APPLE__`.
- **`macos/platform/`** — the macOS app itself (entry point in `app_main.mm`, app delegate, menu builder, find/replace, doc manager, lexer styles, language defs, panels). This is where most macOS-specific work lands.
- **`macos/platform/scintilla_bridge.*`** — **critical isolation layer.** Scintilla's `ScintillaView.h` defines `WM_COMMAND`/`WM_NOTIFY` as `1001`/`1002`, which collide with the shim's real Win32 values (`0x0111`/`0x004E`). The bridge exposes a small C API (`ScintillaBridge_createView`, `ScintillaBridge_sendMessage`, `ScintillaBridge_setNotifyCallback`) compiled **without** the Win32 shim force-include, so Scintilla's headers never see shim symbols. When touching Scintilla integration, route through this bridge — do not include `ScintillaView.h` from Win32-shim translation units.
- **Global state** lives in `macos/platform/app_state.h` as `AppContext& ctx()` — a singleton that holds Scintilla views, document list, active tab, find/replace state, and HWND handles. This is a deliberate simplification to ease Win32-codebase migration; treat reads/writes as the migration path's compromise rather than a pattern to extend.

### Upstream Notepad++ core (`PowerEditor/src/`)

The Win32 code is largely untouched. Message flow:

```
winmain.cpp → Notepad_plus_Window (window/loop) → Notepad_plus (core)
                                                    ├─ ScintillaEditView ×2 (main + sub views)
                                                    ├─ DocTabView ×2
                                                    ├─ FileManager singleton (Buffer.h, owns all Buffers)
                                                    ├─ NppParameters singleton (Parameters.cpp, XML config)
                                                    ├─ PluginsManager
                                                    └─ DockingManager
```

Message dispatch is split across `NppBigSwitch.cpp` (window proc / `Notepad_plus::process`), `NppCommands.cpp` (menu commands / `Notepad_plus::command`), `NppNotification.cpp` (Scintilla/tab notifications), and `NppIO.cpp` (file I/O).

### Vendored, not submoduled

- `scintilla/` — Scintilla editor component
- `lexilla/` — ~130 lexers
- `boostregex/` — stripped Boost 1.90.0 (PCRE regex; chosen over ECMAScript)
- `PowerEditor/src/{uchardet,pugixml,json}/`

### Plugins

Windows plugin contract in `PowerEditor/src/MISC/PluginsManager/PluginInterface.h` (exports: `setInfo`, `getName`, `getFuncsArray`, `beNotified`, `messageProc`, `isUnicode`) using messages from `Notepad_plus_msgs.h`. macOS-side plugin scaffolding lives under `macos/plugin-sdk/` (early WIP).

## Coding Style

Allman braces, tabs, PascalCase classes, camelCase methods, `_memberVar` for fields, C++ casts only, pre-increment, `{}` init for non-primitives. C++20. No `using namespace` in headers. Full rules in upstream `CONTRIBUTING.md` — keep patches compact and avoid whitespace churn.

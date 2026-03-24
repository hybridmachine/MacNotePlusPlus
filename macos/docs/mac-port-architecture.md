# macOS Port Architecture Document

## Overview

This document describes the architecture of the macOS port of Notepad++, covering the Win32 shim layer, platform-specific implementations, build system integration, and merge compatibility considerations with the upstream Windows codebase.

The macOS port uses a **Win32 shim layer strategy** that avoids modifying the original PowerEditor source files. Instead, shim headers intercept Win32 API calls at compile time, routing them to macOS-native implementations via Objective-C++.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Win32 Shim Layer](#2-win32-shim-layer)
3. [Platform-Specific Implementations](#3-platform-specific-implementations)
4. [Build System Integration](#4-build-system-integration)
5. [Dependency Management](#5-dependency-management)
6. [Merge Compatibility Analysis](#6-merge-compatibility-analysis)
7. [Recommendations](#7-recommendations)

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MacOSNotePP App                       │
│  ┌───────────────┐  ┌────────────────┐  ┌────────────┐  │
│  │ PowerEditor   │  │ macos/platform │  │ macos/shim │  │
│  │ (unmodified)  │──│ (native macOS) │──│ (Win32 API │  │
│  │               │  │                │  │  wrappers) │  │
│  └───────┬───────┘  └────────────────┘  └────────────┘  │
│          │                                               │
│  ┌───────┴───────┐  ┌────────────────┐                   │
│  │  Scintilla    │  │   Lexilla      │                   │
│  │  (macOS/Cocoa)│  │   (portable)   │                   │
│  └───────────────┘  └────────────────┘                   │
└─────────────────────────────────────────────────────────┘
```

### Design Principles

- **Zero modifications** to original `PowerEditor/src/` files
- Shim headers replace `<windows.h>` via CMake include path ordering
- macOS-specific UI built separately in `macos/platform/` (Objective-C++)
- Scintilla uses its native Cocoa backend; Lexilla is portable C++

---

## 2. Win32 Shim Layer

### 2.1 Directory Structure

```
macos/shim/
├── include/              # Shim headers (intercepted at compile time)
│   ├── windows.h         # Master include — replaces <windows.h>
│   ├── windef.h          # HWND, HDC, HMENU, COLORREF, etc.
│   ├── winbase.h         # File I/O, memory, string operations
│   ├── winuser.h         # Window management, messages, menus
│   ├── wingdi.h          # GDI drawing, fonts, device contexts
│   ├── commctrl.h        # Common controls (TreeView, ListView, etc.)
│   ├── shlwapi.h         # Shell lightweight utility functions
│   ├── shellapi.h        # Shell API (drag-drop, ShellExecute)
│   ├── commdlg.h         # Common dialogs (Open/Save/Color/Font)
│   ├── richedit.h        # Rich edit control messages
│   ├── handle_registry.h # HWND ↔ NSView* bidirectional mapping
│   └── ...
└── src/                  # Shim implementations (Objective-C++)
    ├── win32_window.mm   # Window/HWND management
    ├── win32_gdi.mm      # GDI → Core Graphics
    ├── win32_menu.mm     # Menu → NSMenu
    ├── win32_file.mm     # File I/O → POSIX/Foundation
    ├── win32_misc.mm     # Registry stubs, system info, misc
    ├── win32_string.mm   # String conversion (wchar_t ↔ UTF-8)
    ├── win32_controls.mm # Common controls → AppKit
    └── handle_registry.mm
```

### 2.2 Type Mappings

| Win32 Type | macOS Mapping | Notes |
|---|---|---|
| `HWND` | `void*` (opaque) | Resolved via HandleRegistry to `NSView*` |
| `HDC` | Wrapper struct | Around `CGContextRef` |
| `HMENU` | `void*` | Maps to `NSMenu*` |
| `HFONT` | `void*` | Maps to `NSFont*` |
| `HBRUSH` | `void*` | Maps to `NSColor*` or `CGColor` |
| `COLORREF` | `uint32_t` | 0x00BBGGRR format preserved |
| `WPARAM` / `LPARAM` | `intptr_t` | Pointer-sized integers |
| `HINSTANCE` | `void*` | Maps to `NSBundle*` or nullptr |
| `HMODULE` | `void*` | Maps to `dlopen` handle |

### 2.3 HandleRegistry

The `HandleRegistry` (`macos/shim/include/handle_registry.h`) provides bidirectional mapping between Win32 `HWND` handles and native `NSView*` pointers:

- Maps `HWND` ↔ `NSView*` bidirectionally
- Stores `WNDPROC` callback and user data per handle
- Thread-safe global dictionary
- Used by all window management, message dispatch, and control APIs

### 2.4 Stubbed APIs (Intentional No-ops)

These APIs are shimmed to fail gracefully, returning appropriate error codes:

| API Category | Behavior | Return Value |
|---|---|---|
| Registry (`RegOpenKeyExW`, etc.) | Always fails | `ERROR_FILE_NOT_FOUND` |
| Registry write (`RegSetValueExW`) | Always fails | `ERROR_ACCESS_DENIED` |
| DLL loading (`LoadLibrary`) | Always fails | `nullptr` |
| Resources (`FindResource`, `LoadResource`) | Always fails | `nullptr` |
| File version info (`GetFileVersionInfoW`) | Always fails | `FALSE` |
| Theme APIs (`OpenThemeData`) | Always fails | `nullptr` |
| Process elevation / UAC | No-op | Success codes |
| System metrics | Hardcoded values | 1920x1080 screen, 15px scrollbars |
| OS version info | Reports "Windows 10" | For compatibility checks |

---

## 3. Platform-Specific Implementations

### 3.1 macOS Platform Layer

```
macos/platform/
├── app_delegate.mm       # NSApplicationDelegate — app lifecycle
├── main_window.mm        # Main editor window (NSWindow)
├── editor_view.mm        # ScintillaView integration
├── tab_bar.mm            # Tab bar (replaces DocTabView)
├── file_monitor_mac.mm   # FSEvents-based file monitoring
├── appearance.mm         # Dark mode via NSAppearance
├── menu_bar.mm           # macOS menu bar
├── preferences.mm        # Preferences window
└── main.mm               # Entry point (replaces winmain.cpp)
```

### 3.2 Key Platform Replacements

| Windows Subsystem | macOS Replacement | Notes |
|---|---|---|
| `winmain.cpp` (WinMain) | `main.mm` (NSApplication) | Completely different entry point |
| `ReadDirectoryChanges/` | `file_monitor_mac.mm` (FSEvents) | Different API, same semantics |
| `DarkMode/DarkMode.cpp` | `appearance.mm` (NSAppearance) | Incompatible architectures |
| Dialog resources (`.rc` files) | Programmatic Objective-C | No resource-based dialog system |
| `Processus.cpp` (ShellExecute) | Not yet implemented | Needs `NSTask` / `posix_spawn` |
| `CustomFileDialog` (IFileDialog COM) | `NSOpenPanel` / `NSSavePanel` | Native macOS file dialogs |
| `pluginsAdmin` (WinInet) | Not yet implemented | Would need `NSURLSession` |

### 3.3 Scintilla Integration

The macOS port uses Scintilla's native **Cocoa backend** (`scintilla/cocoa/`), not the Win32 backend:

- `ScintillaView` (NSView subclass) wraps the editor
- Direct Objective-C++ integration — no Win32 message passing for editor operations
- Lexilla is portable C++ and works unchanged

---

## 4. Build System Integration

### 4.1 CMake Configuration

The build uses CMake with the **Xcode generator** (required for reliable builds):

```bash
cd macos/build
cmake -G Xcode ..
cmake --build . --target MacOSNotePP
```

### 4.2 Include Path Strategy

The shim intercepts Win32 headers by placing the shim include directory **first** in the include path:

```cmake
# Force shim headers to override system headers
target_include_directories(MacOSNotePP PRIVATE
    "${SHIM_INCLUDE_DIR}"     # First: intercepts <windows.h>
    "${NPP_SRC_DIR}"          # PowerEditor source
    ...
)

# Force-include windows.h in every translation unit
add_compile_options(-include "${SHIM_INCLUDE_DIR}/windows.h")
```

### 4.3 Files Excluded from macOS Build

The CMakeLists.txt explicitly excludes Windows-only files:

```cmake
# Excluded: uses PE/IAT hooking (Windows-only)
# "${NPP_SRC_DIR}/DarkMode/DarkMode.cpp"

# Excluded: Windows-only subsystems
list(FILTER NPP_WINCONTROLS_SOURCES EXCLUDE REGEX "ReadDirectoryChanges")
list(FILTER NPP_WINCONTROLS_SOURCES EXCLUDE REGEX "CustomFileDialog")
list(FILTER NPP_WINCONTROLS_SOURCES EXCLUDE REGEX "pluginsAdmin")
```

### 4.4 Compile Test Target

A separate target validates shim compatibility with 39 key PowerEditor source files:

```cmake
add_library(npp_macos_compile_test STATIC
    Parameters.cpp, Notepad_plus.cpp, NppBigSwitch.cpp, Buffer.cpp,
    ScintillaEditView.cpp, FindReplaceDlg.cpp, UserDefineDialog.cpp,
    ... # 39 total files
)
```

This ensures the shim layer compiles against core PowerEditor code but does **not** test runtime behavior.

### 4.5 Packaging and Distribution

```bash
# .app bundle
cmake --build . --target MacOSNotePP_package

# Unsigned DMG
cmake --build . --target MacOSNotePP_dmg

# Code signing (opt-in)
cmake -G Xcode .. -DCODESIGN_ENABLED=ON -DCODESIGN_IDENTITY="Developer ID Application"
cmake --build . --target MacOSNotePP_sign
```

---

## 5. Dependency Management

### 5.1 Vendored Dependencies

| Dependency | Location | macOS Status |
|---|---|---|
| Scintilla | `scintilla/` | Cocoa backend used (native macOS) |
| Lexilla | `lexilla/` | Portable C++, works unchanged |
| pugixml | `PowerEditor/src/pugixml/` | Portable C++, works unchanged |
| uchardet | `PowerEditor/src/uchardet/` | Portable C++, works unchanged |
| Boost.Regex | `boostregex/` | Portable C++, compiled for macOS |

### 5.2 macOS Frameworks

The macOS port links against these system frameworks:

- **Cocoa** — AppKit, Foundation
- **CoreGraphics** — GDI replacement
- **CoreText** — Font management
- **Carbon** (legacy) — Some keyboard/event handling
- **Security** — Code signing validation

---

## 6. Merge Compatibility Analysis

### 6.1 Win32 API Usage Density in PowerEditor

| Metric | Count |
|---|---|
| `SendMessage` / `PostMessage` calls | 1,230+ across 61 files |
| File I/O operations (`CreateFile`, `ReadFile`, etc.) | 70+ |
| `SendMessage` in `NppBigSwitch.cpp` alone | 49 |
| `SendMessage` in `Notepad_plus.cpp` | 97 |
| File I/O in `Buffer.cpp` | 12 |

### 6.2 Platform Preprocessor Guards (Current State)

The Windows codebase has almost no platform guards:

- Only **3 `#ifdef _MSC_VER`** checks (all pragma-related)
- **No `#ifdef WIN32` or `#ifdef _WIN32`** guards in main source files
- Code assumes Windows everywhere; the shim masks this at compile time

### 6.3 Conflict Severity by Subsystem

| Area | Severity | Affected Files | Impact |
|---|---|---|---|
| **Dialogs** | EXTREME | FindReplaceDlg, PreferenceDlg, 30+ controls | Completely different implementation per dialog |
| **Registry** | CRITICAL | Common.cpp, RegExt/*, NppCommands.cpp | Silent failures on macOS |
| **File Monitoring** | CRITICAL | ReadDirectoryChanges/* (8 files) | Excluded; macOS uses FSEvents |
| **Dark Mode** | HIGH | DarkMode/*, NppDarkMode.cpp | Incompatible architectures; excluded |
| **Process Execution** | HIGH | Processus.cpp, winmain.cpp | Not implemented on macOS |
| **Plugin System** | MODERATE | PluginsManager/* | DLL loading → dylib; different interface |
| **Win32 Message Dispatch** | MODERATE | NppBigSwitch.cpp | Routed through shim; slower dispatch |
| **Configuration (XML)** | MODERATE | Parameters.cpp | XML-based (portable); registry reads fail silently |
| **String/Encoding** | LOW | Utf8_16.cpp | Platform-independent; compatible |

### 6.4 Silent Failure Risks

Registry stubs return failure codes that cause code to always take the failure path on macOS:

```cpp
// Example: This always evaluates to false on macOS
RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\...", 0, KEY_READ, &hKey);
if (result == ERROR_SUCCESS) { ... }  // Never reached on macOS
```

This masks bugs where macOS builds silently skip functionality that should have a macOS-native equivalent.

### 6.5 Future Upstream Changes: Likely Problems

| Change Type | Impact |
|---|---|
| New registry settings | Silently fail; need manual mapping to config files |
| New dark mode features | Won't compile without `#ifdef` guards |
| New dialog additions | Each needs independent macOS implementation |
| Process elevation enhancements | Not implementable (no UAC equivalent) |
| Plugin interface changes | HWND parameters not portable |
| New Win32 HANDLE types | Shim compatibility breaks |

---

## 7. Recommendations

### 7.1 Short-Term (0-6 months)

1. **Add `#ifdef __APPLE__` guards** in Windows-only code paths that have macOS equivalents
2. **Document divergence points** with comments linking to macOS equivalents:
   ```cpp
   // MACOS: Registry code silently fails on macOS.
   // See macos/platform/settings_manager.mm for macOS equivalent.
   ```
3. **Expand the compile test target** to cover more PowerEditor files

### 7.2 Medium-Term (6-12 months)

1. **Create platform abstraction interfaces** for:
   - Configuration storage (registry vs. plist/JSON)
   - Theme/appearance system
   - File monitoring
   - Process execution
2. **Add parallel CI pipeline** testing Windows changes against the macOS shim
3. **Implement missing platform features**: process execution, plugin system (dylib)

### 7.3 Long-Term (12+ months)

1. **Extract platform-independent core**: separate pure logic (buffer management, Scintilla integration) from OS-specific code
2. **Cross-platform test suite**: ensure same functional tests run on both platforms
3. **Upstream collaboration**: propose platform abstraction layer to official Notepad++ project

---

## Appendix: Key File Reference

| File | Role |
|---|---|
| `macos/CMakeLists.txt` | Build configuration, file exclusions, shim integration |
| `macos/shim/include/windows.h` | Master shim header (replaces Win32 `<windows.h>`) |
| `macos/shim/include/handle_registry.h` | HWND ↔ NSView* mapping |
| `macos/shim/src/win32_window.mm` | Window management shim |
| `macos/shim/src/win32_gdi.mm` | GDI → Core Graphics shim |
| `macos/shim/src/win32_misc.mm` | Registry stubs, system info |
| `macos/platform/main.mm` | macOS entry point |
| `macos/platform/app_delegate.mm` | Application lifecycle |
| `macos/platform/file_monitor_mac.mm` | FSEvents file monitoring |
| `macos/platform/appearance.mm` | Dark mode (NSAppearance) |

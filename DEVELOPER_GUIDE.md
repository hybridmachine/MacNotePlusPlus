# PaperWasp Developer Guide

## Project Overview

PaperWasp is an **experimental independent macOS port** based on the Notepad++ v7.9.5 codebase using a Win32 compatibility shim layer. The goal is to run the existing C++/Win32 code on macOS with minimal modifications.

PaperWasp is not endorsed by the creators of Notepad++.

**Key distinction:** This is NOT a cross-platform rewrite. It's a compatibility port that maps Win32 APIs to Cocoa/AppKit via a shim layer.

## Architecture

### Core Design Pattern: Win32 Shim

The project uses a **header-only Win32 shim** (`macos/shim/include/`) that replaces `<windows.h>`:

```
N++ Source Code → #include <windows.h> → macos/shim/include/windows.h → Cocoa/AppKit
```

The shim provides:
- All Win32 type definitions (`HWND`, `WPARAM`, `WNDCLASS`, etc.)
- Function declarations for Windows APIs
- Objective-C++ implementations backed by Cocoa equivalents
- **Critical:** Does NOT define `WIN32`/`_WIN32` macros to avoid C++ standard library issues

### Component Breakdown

#### 1. **Shim Layer** (`macos/shim/`)
- `include/` - Header-only Win32 API declarations
- `src/*.mm` - Objective-C++ implementations
- Key files:
  - `windows.h` - Master header, includes all other shim headers
  - `win32_window.mm` - Window creation/management (backed by NSWindow/NSView)
  - `win32_gdi.mm` - Drawing operations (backed by CoreGraphics)
  - `win32_file.mm` - File I/O (backed by NSURL/NSFileManager)
  - `win32_menu.mm` - Menu system (backed by NSMenu)
  - `win32_message.mm` - Message queue (backed by NSRunLoop)

#### 2. **Scintilla Bridge** (`macos/platform/scintilla_bridge.*`)
- **Purpose:** Isolate Scintilla Cocoa integration from Win32 code
- **Problem:** ScintillaView.h defines WM_COMMAND/WM_NOTIFY with values (1001/1002) that conflict with the shim's Win32 values (0x0111/0x004E)
- **Solution:** C interface compiled WITHOUT the Win32 shim force-include
- **Key functions:**
  - `ScintillaBridge_createView()` - Create ScintillaView as NSView subview
  - `ScintillaBridge_sendMessage()` - Send SCI_xxx messages
  - `ScintillaBridge_setNotifyCallback()` - Register for Scintilla notifications

#### 3. **Platform Layer** (`macos/platform/`)
Modular Objective-C++ implementation files:

| File | Responsibility |
|------|----------------|
| `app_main.mm` | Application entry point |
| `app_delegate.mm` | NSApplication lifecycle, drag-and-drop |
| `app_state.h/mm` | Global application state (singleton `ctx()`) |
| `document_manager.*` | Tab management, document state save/restore |
| `wndproc.mm` | Main window procedure (WM_COMMAND dispatch) |
| `menu_builder.*` | Menu bar construction |
| `find_replace.*` | Find/replace dialog implementation |
| `split_view.*` | Dual-view editor support |
| `preferences_dialog.*` | Settings UI |
| `lexer_styles.*` | Syntax highlighting configuration |
| `language_defs.*` | Language definitions (C, C++, Python, etc.) |

### State Management

**Centralized global state** in `app_state.h`:

```cpp
struct AppContext {
    void* scintillaView;           // Main editor view
    void* scintillaView2;          // Secondary view (split)
    std::vector<DocumentData> documents;
    int activeTab;
    HWND mainHwnd, tabHwnd, statusBarHwnd;
    
    // Find/Replace state
    HWND findDlgHwnd;
    std::wstring findText, replaceText;
    
    // Preferences
    int fontSize, tabWidth;
    std::string fontName;
    
    // Split view helpers
    void*& activeScintillaView() { return activeView == 0 ? scintillaView : scintillaView2; }
    // ...
};
AppContext& ctx();  // Global accessor
```

**Design rationale:** Single global instance simplifies migration from Windows codebase. Future refactoring should consider dependency injection.

## Build System

### CMake Configuration (`macos/CMakeLists.txt`)

**Three-tier build:**

1. **win32shim** - Static library with shim implementations
2. **Scintilla** - Static library (Cocoa backend)
3. **Lexilla** - Lexer library
4. **PaperWasp** - Main application executable

**Build commands:**

```bash
cd macos/build
cmake -G Xcode ..          # Configure with Xcode generator
cmake --build . --target PaperWasp          # Build app
cmake --build . --target PaperWasp_package  # Build .app bundle
cmake --build . --target PaperWasp_dmg      # Build unsigned DMG
```

**Critical:** Use Xcode generator (`-G Xcode`). Makefiles fails on deeply nested object paths.

**Code signing (opt-in):**

```bash
cmake -G Xcode .. -DCODESIGN_ENABLED=ON
cmake --build . --target PaperWasp_sign     # Sign .app bundle
cmake --build . --target PaperWasp_dmg      # Build + sign DMG
```

See [docs/macos-code-signing.md](docs/macos-code-signing.md) for full documentation
including Apple Developer account setup, notarization, and CI configuration.

**Artifacts:**
- `macos/build/PaperWasp` - Development binary
- `macos/dist/PaperWasp.app` - Packaged app bundle
- `macos/dist/PaperWasp-unsigned.dmg` - Unsigned distribution DMG
- `macos/dist/PaperWasp.dmg` - Signed distribution DMG (when code signing enabled)

## Key Concepts for Developers

### 1. Header Inclusion Order Matters

The Win32 shim MUST be included first:

```cpp
#include "windows.h"        // MUST be first - provides Win32 types
#include "commctrl.h"       // Common controls (ListView, TreeView, etc.)
#include "scintilla_bridge.h"  // Scintilla-specific C interface
```

**Why:** The shim uses `#include "windows.h"` force-include via `-include` compiler flag to ensure all N++ code gets Win32 types.

### 2. Objective-C++ Compilation

All platform code is `.mm` (Objective-C++):
- Can call both C++ and Objective-C code
- Uses `__bridge` casts for toll-free bridging
- ARC enabled (`-fobjc-arc`) for memory management

### 3. Command Dispatch Pattern

Windows uses message loops; macOS uses Cocoa event loop. The port bridges this gap:

```
User Action → Cocoa Event → NSApplication → N++ WM_* Message → WndProc → Command Handler
```

**Example - File New:**

```objc
// app_delegate.mm - Handle menu item
[NSMenuItem action:@selector(fileNew:)]

// -> calls C++ function
void fileNew() {
    addNewTab(L"Untitled", "");
}
```

```cpp
// wndproc.mm - Handle WM_COMMAND
case WM_COMMAND:
    if (LOWORD(wParam) == IDM_FILE_NEW) {
        addNewTab(L"Untitled", "");
    }
    break;
```

### 4. Scintilla Integration

**Two communication paths:**

1. **Direct message sending** (C++ → ScintillaView):
   ```cpp
   void* sci = ctx().activeScintillaView();
   ScintillaBridge_sendMessage(sci, SCI_UNDO, 0, 0);
   ```

2. **Notification callbacks** (ScintillaView → C++):
   ```cpp
   ScintillaBridge_setNotifyCallback(sciView, (intptr_t)hWnd, callback);
   // Callback receives SCI notifications as WM_* messages
   ```

### 5. String Handling

**Windows:** `wchar_t*` (UTF-16 on Windows, UTF-32 on macOS)

**Conversion helpers** in `string_utils.h`:
```cpp
std::wstring NSStringToWide(NSString* str);
NSString* WideToNSString(const wchar_t* wstr);
```

**Critical:** On macOS, `wchar_t` is 32-bit (UTF-32), not 16-bit like Windows.

### 6. Constants & IDs

**Command IDs** in `npp_constants.h`:
- Match original Notepad++ `IDM_*` convention
- Phase-based grouping (Phase 1-7 for different feature sets)
- Example: `IDM_FILE_NEW = 41001`, `IDM_EDIT_UNDO = 42001`

**SCI message IDs** - Subset of Scintilla messages defined in `npp_constants.h`

## Coding Guidelines

### 1. Follow Existing Patterns

**File organization:**
- Each major feature has its own `*.h`/`*.mm` pair in `macos/platform/`
- Headers are small (typically < 50 lines)
- Implementations are focused on single responsibility

**Naming:**
- C++ functions: `camelCase`
- Objective-C methods: `lowercaseWithColon:`
- Global functions: `PascalCase` (e.g., `addNewTab`, `openFile`)

### 2. Memory Management

- Use ARC for Objective-C objects
- C++ uses RAII, smart pointers
- No manual `new`/`delete` in new code

### 3. Error Handling

- Win32 APIs return BOOL/HRESULT
- Cocoa methods use NSError** or return nil
- Convert errors appropriately at shim boundaries

### 4. Threading

- Main thread only for UI operations
- Use `dispatch_async()` for background tasks
- Scintilla must be accessed only from main thread

## Important Files Reference

### Entry Point
- `macos/platform/app_main.mm` - `main()` function
- `macos/platform/app_delegate.mm` - Application lifecycle

### Core Logic
- `macos/platform/wndproc.mm` - Main window procedure (420 lines)
- `macos/platform/menu_builder.mm` - Menu construction (142 lines)
- `macos/platform/app_state.h` - Global state definition

### Scintilla Integration
- `macos/platform/scintilla_bridge.*` - C interface to ScintillaView
- `macos/platform/scintilla_config.*` - Editor configuration

### Document Management
- `macos/platform/document_manager.*` - Tab/document operations
- `macos/platform/file_operations.*` - File I/O
- `macos/platform/session_manager.*` - Session save/restore

### UI Components
- `macos/platform/find_replace.*` - Find/replace dialog
- `macos/platform/preferences_dialog.*` - Settings UI
- `macos/platform/status_bar.*` - Status bar updates
- `macos/platform/split_view.*` - Dual-view editor

### Supporting
- `macos/platform/npp_constants.h` - All IDs and constants (334 lines)
- `macos/platform/language_defs.*` - Language definitions
- `macos/platform/lexer_styles.*` - Syntax highlighting

## Current Status & Limitations

### Completed Features (Phase 1-7)
- ✓ Basic file operations (new, open, save, close)
- ✓ Tabbed interface with multiple documents
- ✓ Split view (horizontal)
- ✓ Find/replace dialog
- ✓ Menu bar with all major commands
- ✓ Syntax highlighting (lexers)
- ✓ Auto-completion
- ✓ Bookmarks
- ✓ EOL conversion
- ✓ Encoding conversion
- ✓ Preferences dialog
- ✓ Recent files
- ✓ Session management

### Known Limitations
- **Plugin system:** Not yet implemented (requires DLL loading on macOS)
- **Full macOS menu bar:** Some menu items not yet connected
- **Dark mode:** Partial implementation
- **Accessibility:** Not yet implemented
- **Print support:** Not yet implemented
- **Find in files:** Not yet implemented
- **Macro recording:** Not yet implemented

### Windows-Specific Code Not Yet Handled
- COM interfaces (IFileDialog, IShellDispatch)
- WinInet/WinHTTP for network operations
- Registry access
- GDI+ drawing
- SEH (Structured Exception Handling)
- Windows-specific threading APIs

## Development Workflow

### Adding a New Feature

1. **Add command ID** in `npp_constants.h`
2. **Add menu item** in `menu_builder.mm`
3. **Add handler** in `wndproc.mm` (WM_COMMAND case)
4. **Implement logic** in appropriate `platform/` file
5. **Update constants** as needed

### Example: Adding a New Menu Command

```cpp
// 1. Add to npp_constants.h
#define IDM_FILE_MYFEATURE 41200

// 2. Add menu item in menu_builder.mm
AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_MYFEATURE, L"My Feature\tCtrl+M");

// 3. Add handler in wndproc.mm
case WM_COMMAND:
    if (LOWORD(wParam) == IDM_FILE_MYFEATURE) {
        handleMyFeature();
        return 0;
    }

// 4. Implement in appropriate file (e.g., file_operations.h/cpp)
void handleMyFeature() {
    // Your implementation
}
```

### Debugging

**Build with debug symbols:**
```bash
cmake -G Xcode -DCMAKE_BUILD_TYPE=Debug ..
```

**Use Xcode for debugging:**
```bash
open macos/build/NotepadPlusPlusMac.xcodeproj
```

**Key logs:**
- Check console for Cocoa error messages
- Scintilla notifications visible via callback

## Contributing

1. Follow existing coding style (see `CONTRIBUTING.md` in root)
2. Keep changes focused (single feature per PR)
3. Test on macOS 12+ (current development target)
4. Update this guide for new patterns

## Resources

- **Original Notepad++ codebase:** `PowerEditor/src/`
- **Scintilla documentation:** https://www.scintilla.org/
- **Lexilla documentation:** https://www.scintilla.org/Lexilla.html
- **macOS AppKit:** https://developer.apple.com/documentation/appkit

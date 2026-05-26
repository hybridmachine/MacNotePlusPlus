#pragma once
// Win32 Menu Implementation Interface
// Host-facing accessors for code that already understands NSMenu semantics
// (e.g. the plugin manager needs to attach AppKit keyEquivalents to menu
// items it created via AppendMenuW). The shim owns the HMENU -> NSMenu map;
// this header lets callers borrow the NSMenu without duplicating it.

#ifdef __APPLE__

#include "windows.h"

// Returns the NSMenu* backing an HMENU, or nullptr if the handle is unknown.
// Typed as void* so C/C++ callers stay ObjC-free; cast to NSMenu* on the
// Objective-C side via __bridge.
void* Win32Menu_GetNSMenu(HMENU hMenu);

#endif // __APPLE__

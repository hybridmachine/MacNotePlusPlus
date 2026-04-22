#pragma once
// Cocoa control factory for dialog templates. Given one
// DlgControlDescriptor, builds the matching NSControl, adds it to
// `parentView`, and registers it in HandleRegistry with
// (controlId = desc.id, parent = ownerDialog) so the existing
// GetDlgItem / WM_COMMAND routing works unchanged.

#ifdef __APPLE__

#include "dialog_template.h"
#include "windows.h"

// parentView is NSView* (Objective-C type; passed as void* so the
// caller can stay in C++ if it wants).
// duX / duY convert dialog units to pixels for positioning.
HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentView,
                         HWND ownerDialog,
                         double duX,
                         double duY);

#endif // __APPLE__

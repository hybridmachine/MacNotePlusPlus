// wndproc.h — Main window procedure (command dispatch)
// Part of the PaperWasp macOS app.

#pragma once

#import <Cocoa/Cocoa.h>
#include "windows.h"

LRESULT CALLBACK MainWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

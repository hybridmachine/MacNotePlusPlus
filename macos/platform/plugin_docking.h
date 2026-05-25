#pragma once

#include "windows.h"

bool registerPluginDockingDialog(const void* dockingData);
bool showPluginDockingDialog(HWND hwnd);
bool hidePluginDockingDialog(HWND hwnd);
bool updatePluginDockingDialog(HWND hwnd);
bool showPluginDockingDialogByName(const wchar_t* name);
HWND findPluginDockingDialog(const wchar_t* windowName, const wchar_t* moduleName);

bool isPluginDockingVisible();
void* pluginDockingContainerView();
void layoutPluginDockingViews();

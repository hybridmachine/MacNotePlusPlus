// recent_files.h — Recent files list management
// Part of the PaperWasp macOS app.

#pragma once

#include <string>

void addRecentFile(const std::wstring& path);
void rebuildRecentMenu();
void openRecentFile(int index);

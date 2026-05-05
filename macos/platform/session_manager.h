// session_manager.h — Session save/restore
// Part of the PaperWasp macOS app.

#pragma once

#include <string>

std::string sessionPath();
void saveSession();
void restoreSession();

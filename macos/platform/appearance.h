// appearance.h — Dark/light mode, theme switching
// Part of the PaperWasp macOS app.

#pragma once

bool isAppDarkMode();
void applyFoldMarkerColorsToView(void* sci, bool isDark);
void applyAppearanceToView(void* sci, int langIdx, bool isDark);
void applyAppearance();

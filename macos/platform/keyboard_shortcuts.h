// keyboard_shortcuts.h — Native macOS keyboard shortcut configuration
// Part of the PaperWasp macOS app.

#pragma once

// Configure native macOS keyboard shortcuts on a Scintilla view.
// Must be called after each ScintillaView is created.
void configureKeyboardShortcuts(void* sci);

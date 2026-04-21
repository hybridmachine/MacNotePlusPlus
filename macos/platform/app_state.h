// app_state.h — Shared application state (globals + AppContext)
// Part of the Notepad++ macOS port modular refactor.
//
// Design note: All mutable application state is grouped in AppContext.
// A single global instance is accessed via ctx(). This centralizes
// coupling and makes it straightforward to refactor toward dependency
// injection for testability in the future.

#pragma once

#import <Cocoa/Cocoa.h>
#include <string>
#include <vector>

// Include windows.h AFTER Cocoa — the shim skips its BOOL typedef
// in ObjC++ because ObjC defines BOOL as bool.
#include "windows.h"

#include "document_data.h"

class FileMonitorMac;

struct AppContext
{
	// Main editor
	void* scintillaView = nullptr;
	HWND scintillaMainHwnd = nullptr;
	NSWindow* mainWindow = nil;
	HWND mainHwnd = nullptr;
	HWND tabHwnd = nullptr;
	HWND statusBarHwnd = nullptr;
	std::vector<DocumentData> documents;
	int activeTab = -1;
	FileMonitorMac* fileMonitor = nullptr;

	// Find/Replace state
	HWND findDlgHwnd = nullptr;
	std::wstring findText;
	std::wstring replaceText;
	bool matchCase = false;
	bool wholeWord = false;
	bool useRegex = false;
	bool findMode = true; // true = Find, false = Replace

	// Recent files
	static const int MAX_RECENT_FILES = 10;
	std::vector<std::wstring> recentFiles;
	HMENU recentMenu = nullptr;

	// Preferences state
	int fontSize = 13;
	int tabWidth = 4;
	std::string fontName = "Menlo";
	bool showLineNumbers = true;
	bool showCaretLine = true;
	bool autoIndent = true;
	bool useTabs = false;
	bool showWhitespace = false;
	bool showEol = false;
	bool showIndentGuides = false;
	bool autoCloseBrackets = true;
	bool showChangeHistory = true;

	// Split view state
	void* scintillaView2 = nullptr;
	HWND scintillaSecondHwnd = nullptr;
	NSSplitView* splitView = nil;
	bool isSplit = false;
	// Set when the host auto-split the view in response to a plugin entering
	// compare mode, so we know to auto-unsplit when that plugin exits compare
	// mode. Distinct from `isSplit`, which reflects any split regardless of
	// origin (user-initiated splits are NOT torn down on compare exit).
	bool hostInitiatedSplit = false;
	// Last value a plugin passed to NPPM_SETLINENUMBERWIDTHMODE. Tracked so
	// NPPM_GETLINENUMBERWIDTHMODE reports the actual current mode rather than
	// a fixed default, preserving the Win32 set/get round-trip contract.
	// 0 = LINENUMWIDTH_DYNAMIC (default), 1 = LINENUMWIDTH_CONSTANT.
	int lineNumberWidthMode = 0;
	int activeView = 0; // 0=main, 1=sub
	std::vector<DocumentData> documents2;
	int activeTab2 = -1;
	HWND tabHwnd2 = nullptr;
	NSView* editorContainer = nil;
	NSView* editorContainer2 = nil;
	NSView* sciContainer2 = nil;
	bool syncScrolling = false;
	bool syncScrollReentrant = false;
	bool suppressSyncScroll = false; // Suppresses sync during batch fold operations
	intptr_t syncScrollVDelta = 0;   // Main first-visible - sub first-visible
	bool syncScrollVDeltaValid = false;

	// Document map state
	bool documentMapEnabled = false;
	int documentMapWidth = 140;
	NSView* documentMapContainer = nil;
	NSView* documentMapOverlay = nil;
	void* documentMapScintilla = nullptr;
	intptr_t documentMapBoundDoc = 0; // Currently bound document pointer (for ref counting)

	// Function list state
	bool functionListEnabled = false;

	// Clipboard history state
	bool clipboardHistoryEnabled = false;

	// Left zone — File Browser + File Switcher
	bool fileBrowserEnabled = false;
	bool fileSwitcherEnabled = false;
	int leftPanelWidth = 200;
	CGFloat fileBrowserHeightRatio = 0.6;
	std::string fileBrowserRootPath;
	std::vector<std::string> fileBrowserIgnorePatterns = {
		".git", ".DS_Store", "node_modules", "__pycache__", ".build", "build"
	};

	// Right zone — replaces per-panel widths for Function List + Clipboard History
	int rightPanelWidth = 220;
	CGFloat functionListHeightRatio = 0.5;

	// Notification suppression (prevents false dirty indicators during tab switches)
	bool suppressSavePointNotifications = false;

	// Auto-close internal edit guard (prevents recursive handling on programmatic edits)
	bool autoCloseInternalEdit = false;

	// Incremental search bar state
	NSView* incrementalSearchBar = nil;
	bool incrSearchVisible = false;
	int incrSearchCurrentMatch = -1;
	int incrSearchTotalMatches = 0;

	// Accessor helpers for split view
	void*& activeScintillaView() { return activeView == 0 ? scintillaView : scintillaView2; }
	std::vector<DocumentData>& activeDocuments() { return activeView == 0 ? documents : documents2; }
	int& activeTabIndex() { return activeView == 0 ? activeTab : activeTab2; }
	HWND& activeTabHwnd() { return activeView == 0 ? tabHwnd : tabHwnd2; }
};

// Global application context accessor
AppContext& ctx();

// follow_mode.mm — Tail-follow external file changes + per-line age tracking.
// Part of the PaperWasp macOS app.

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#include "follow_mode.h"
#include "age_bar_view.h"
#include "app_state.h"
#include "scintilla_bridge.h"
#include "scintilla_config.h"
#include "scintilla_notify.h"
#include "npp_constants.h"
#include "file_monitor_mac.h"
#include "document_manager.h"
#include "file_operations.h"
#include "handle_registry.h"
#include "tab_bar_view.h"
#include "string_utils.h"

#include <mach/mach_time.h>
#include <sys/stat.h>
#include <fstream>
#include <vector>
#include <algorithm>

#ifndef SCI_APPENDTEXT
#define SCI_APPENDTEXT 2282
#endif

class FollowMirrorSuppression
{
public:
	FollowMirrorSuppression()
		: _savePoint(ctx().suppressSavePointNotifications)
		, _followTracking(ctx().suppressFollowTracking)
	{
		ctx().suppressSavePointNotifications = true;
		ctx().suppressFollowTracking = true;
	}

	~FollowMirrorSuppression()
	{
		ctx().suppressFollowTracking = _followTracking;
		ctx().suppressSavePointNotifications = _savePoint;
	}

private:
	bool _savePoint;
	bool _followTracking;
};

// ---------------------------------------------------------------------------
// Time helper (mirrors age_bar_view.mm's local helper)
// ---------------------------------------------------------------------------

static uint64_t currentMillisFM()
{
	static mach_timebase_info_data_t tb = {0, 0};
	if (tb.denom == 0)
		mach_timebase_info(&tb);
	return (mach_absolute_time() * tb.numer / tb.denom) / 1000000ULL;
}

// ---------------------------------------------------------------------------
// View/doc lookup helpers
// ---------------------------------------------------------------------------

static void* scintillaForView(int viewIndex)
{
	return (viewIndex == 0) ? ctx().scintillaView : ctx().scintillaView2;
}

static std::vector<DocumentData>& docsForView(int viewIndex)
{
	return (viewIndex == 0) ? ctx().documents : ctx().documents2;
}

static int activeTabForView(int viewIndex)
{
	return (viewIndex == 0) ? ctx().activeTab : ctx().activeTab2;
}

static NppEditorContainer* editorContainerForView(int viewIndex)
{
	NSView* v = (viewIndex == 0) ? ctx().editorContainer : ctx().editorContainer2;
	return [v isKindOfClass:[NppEditorContainer class]] ? (NppEditorContainer*)v : nil;
}

// Locate (viewIndex, tabIndex) for a given filePath if any tab in any view is
// currently following it. Returns true on match.
static bool findFollowingTabForPath(const std::wstring& path, int& outView, int& outTab)
{
	for (int vi = 0; vi < 2; ++vi)
	{
		auto& docs = docsForView(vi);
		for (size_t i = 0; i < docs.size(); ++i)
		{
			if (docs[i].followMode && docs[i].filePath == path)
			{
				outView = vi;
				outTab = (int)i;
				return true;
			}
		}
	}
	return false;
}

// ---------------------------------------------------------------------------
// Tab eye-icon + age bar visibility sync
// ---------------------------------------------------------------------------

static void updateTabFollowedIndicator(int viewIndex, int tabIndex)
{
	HWND tabHwnd = (viewIndex == 0) ? ctx().tabHwnd : ctx().tabHwnd2;
	if (!tabHwnd) return;
	auto& docs = docsForView(viewIndex);
	if (tabIndex < 0 || tabIndex >= (int)docs.size()) return;

	auto* info = HandleRegistry::getWindowInfo(tabHwnd);
	if (!info || !info->nativeView) return;
	NppTabBarView* tabView = (__bridge NppTabBarView*)info->nativeView;
	[tabView setFollowed:docs[tabIndex].followMode forTabAtIndex:tabIndex];
}

// Forward decl: defined below alongside the other file-watch helpers, but
// refreshFollowUIForViewActiveTab() above the helpers needs to call it.
static void catchUpFollowedTab(int viewIndex);

static void applyAgeBarVisibilityForActive(int viewIndex)
{
	NppEditorContainer* container = editorContainerForView(viewIndex);
	if (!container) return;
	auto& docs = docsForView(viewIndex);
	int tab = activeTabForView(viewIndex);
	bool show = (tab >= 0 && tab < (int)docs.size() && docs[tab].followMode);
	container.ageBarVisible = show;
}

void refreshFollowUIForViewActiveTab(int viewIndex)
{
	applyAgeBarVisibilityForActive(viewIndex);
	catchUpFollowedTab(viewIndex);

	// For follow-mode tabs, re-anchor the view to the new bottom on activation —
	// the saved firstVisibleLine/cursor from restoreViewToScintilla() points at
	// wherever the user left the view, but follow semantics ("tail -F") mean
	// "reattach to the end" on return.
	auto& docs = docsForView(viewIndex);
	int tab = activeTabForView(viewIndex);
	if (tab < 0 || tab >= (int)docs.size()) return;
	if (!docs[tab].followMode) return;
	void* sci = scintillaForView(viewIndex);
	if (!sci) return;
	intptr_t lineCount = ScintillaBridge_sendMessage(sci, SCI_GETLINECOUNT, 0, 0);
	if (lineCount > 0)
		ScintillaBridge_sendMessage(sci, SCI_GOTOLINE, (uintptr_t)(lineCount - 1), 0);
}

// ---------------------------------------------------------------------------
// File reading helpers
// ---------------------------------------------------------------------------

static uint64_t fileSizeBytes(const std::wstring& wpath)
{
	NSString* nsPath = WideToNSString(wpath.c_str());
	if (!nsPath) return 0;
	struct stat st;
	const char* fs = [nsPath fileSystemRepresentation];
	if (!fs || stat(fs, &st) != 0) return 0;
	return (uint64_t)st.st_size;
}

static std::string readFileRange(const std::wstring& wpath, uint64_t offset, uint64_t length)
{
	if (length == 0) return "";
	NSString* nsPath = WideToNSString(wpath.c_str());
	if (!nsPath) return "";
	const char* fs = [nsPath fileSystemRepresentation];
	if (!fs) return "";
	std::ifstream f(fs, std::ios::binary);
	if (!f.is_open()) return "";
	f.seekg((std::streamoff)offset, std::ios::beg);
	std::string out;
	out.resize((size_t)length);
	f.read(&out[0], (std::streamsize)length);
	out.resize((size_t)f.gcount());
	return out;
}

static std::string decodeFollowBytes(const std::string& bytes, int encoding, bool entireFile)
{
	if (bytes.empty()) return "";
	int effectiveEncoding = (!entireFile && encoding == ENC_UTF8_BOM) ? ENC_UTF8 : encoding;
	NSData* data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
	return decodeFileData(data, effectiveEncoding);
}

static size_t lineCountForContent(const std::string& content)
{
	size_t lineCount = 1;
	for (size_t i = 0; i < content.size(); ++i)
	{
		if (content[i] == '\r')
		{
			++lineCount;
			if (i + 1 < content.size() && content[i + 1] == '\n')
				++i;
		}
		else if (content[i] == '\n')
		{
			++lineCount;
		}
	}
	return lineCount;
}

static size_t normalizeLineBirthTimes(DocumentData& doc)
{
	size_t lineCount = lineCountForContent(doc.content);
	doc.lineBirthTimes.resize(lineCount, 0);
	return lineCount;
}

static void markFollowAppendLineBirths(DocumentData& doc, size_t oldLineCount)
{
	size_t newLineCount = lineCountForContent(doc.content);
	if (newLineCount == 0)
		return;

	doc.lineBirthTimes.resize(newLineCount, 0);
	size_t firstTouchedLine = (oldLineCount > 0) ? oldLineCount - 1 : 0;
	if (firstTouchedLine >= newLineCount)
		firstTouchedLine = newLineCount - 1;

	uint64_t now = currentMillisFM();
	for (size_t i = firstTouchedLine; i < newLineCount; ++i)
		doc.lineBirthTimes[i] = now;
}

static std::string appendFileRangeToDocument(DocumentData& doc, const std::wstring& path,
                                             uint64_t offset, uint64_t newSize)
{
	if (newSize <= offset)
	{
		doc.lastKnownFileSize = newSize;
		return "";
	}

	std::string rawBytes = readFileRange(path, offset, newSize - offset);
	if (rawBytes.empty())
		return "";

	size_t oldLineCount = normalizeLineBirthTimes(doc);
	std::string appendedText = decodeFollowBytes(rawBytes, doc.encoding, false);
	if (!appendedText.empty())
	{
		doc.content.append(appendedText);
		doc.eolMode = detectEOLMode(doc.content.c_str(), doc.content.size());
		markFollowAppendLineBirths(doc, oldLineCount);
	}
	doc.lastKnownFileSize = offset + (uint64_t)rawBytes.size();
	doc.followSuspended = false;
	return appendedText;
}

static bool replaceDocumentWithFile(DocumentData& doc, const std::wstring& path)
{
	uint64_t size = fileSizeBytes(path);
	std::string rawContent = readFileRange(path, 0, size);
	if (rawContent.size() != (size_t)size)
		return false;

	doc.content = decodeFollowBytes(rawContent, doc.encoding, true);
	doc.eolMode = detectEOLMode(doc.content.c_str(), doc.content.size());
	doc.lineBirthTimes.assign(lineCountForContent(doc.content), (uint64_t)0);
	doc.lastKnownFileSize = size;
	doc.followSuspended = false;
	return true;
}

// ---------------------------------------------------------------------------
// SCN_MODIFIED hook — records lineBirthTimes for the active tab of viewIndex.
// ---------------------------------------------------------------------------

void handleFollowModified(int viewIndex, const SciNotification* scn)
{
	if (!scn) return;
	if (!(scn->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))) return;
	// Tab-switch restores re-insert the entire buffer into Scintilla. We need
	// to treat those inserts as not-new so existing line ages survive the
	// round-trip. We can't piggyback on suppressSavePointNotifications because
	// other programmatic edit paths also set that flag to avoid dirty marks.
	if (ctx().suppressFollowTracking) return;
	auto& docs = docsForView(viewIndex);
	int tab = activeTabForView(viewIndex);
	if (tab < 0 || tab >= (int)docs.size()) return;
	DocumentData& doc = docs[tab];
	if (!doc.followMode) return;

	// Tail-follow only cares about lines being added at the end or removed from
	// the end. SCN_MODIFIED's `line` field can be unreliable, so resize the
	// timestamp vector to match the new line count and tag newly-appended
	// entries with the current time. Interior edits won't refresh per-line ages
	// but that's outside the tail-follow contract.
	void* sci = scintillaForView(viewIndex);
	if (!sci) return;
	intptr_t newLineCount = ScintillaBridge_sendMessage(sci, SCI_GETLINECOUNT, 0, 0);
	if (newLineCount < 0) newLineCount = 0;
	size_t newSize = (size_t)newLineCount;
	size_t oldSize = doc.lineBirthTimes.size();
	if (newSize > oldSize)
	{
		uint64_t now = currentMillisFM();
		doc.lineBirthTimes.resize(newSize, now);
	}
	else if (newSize < oldSize)
	{
		doc.lineBirthTimes.resize(newSize);
	}
}

// ---------------------------------------------------------------------------
// File-watch callback dispatcher
// ---------------------------------------------------------------------------

static void scrollScintillaToBottom(void* sci)
{
	if (!sci) return;
	intptr_t lineCount = ScintillaBridge_sendMessage(sci, SCI_GETLINECOUNT, 0, 0);
	if (lineCount > 0)
		ScintillaBridge_sendMessage(sci, SCI_GOTOLINE, (uintptr_t)(lineCount - 1), 0);
}

static void appendTextToVisibleScintilla(int viewIndex, DocumentData& doc, const std::string& text)
{
	void* sci = scintillaForView(viewIndex);
	if (!sci || text.empty()) return;

	{
		FollowMirrorSuppression suppress;
		ScintillaBridge_sendMessage(sci, SCI_APPENDTEXT,
		                            (uintptr_t)text.size(), (intptr_t)text.data());
		ScintillaBridge_sendMessage(sci, SCI_SETSAVEPOINT, 0, 0);
	}

	doc.modified = false;
	doc.savePointValid = true;
	scrollScintillaToBottom(sci);
	refreshLineNumberMargin(sci);
	invalidateAgeBarForView(viewIndex);
}

static void replaceVisibleScintillaFromDocument(int viewIndex, DocumentData& doc)
{
	void* sci = scintillaForView(viewIndex);
	if (!sci) return;

	bool wasReadOnly = ScintillaBridge_sendMessage(sci, SCI_GETREADONLY, 0, 0) != 0;
	{
		FollowMirrorSuppression suppress;
		ScintillaBridge_sendMessage(sci, SCI_SETREADONLY, 0, 0);
		ScintillaBridge_sendMessage(sci, SCI_CLEARALL, 0, 0);
		if (!doc.content.empty())
			ScintillaBridge_sendMessage(sci, SCI_APPENDTEXT,
			                            (uintptr_t)doc.content.size(), (intptr_t)doc.content.data());
		ScintillaBridge_sendMessage(sci, SCI_EMPTYUNDOBUFFER, 0, 0);
		ScintillaBridge_sendMessage(sci, SCI_SETSAVEPOINT, 0, 0);
		ScintillaBridge_sendMessage(sci, SCI_SETREADONLY, wasReadOnly ? 1 : 0, 0);
	}

	doc.modified = false;
	doc.savePointValid = true;
	scrollScintillaToBottom(sci);
	refreshLineNumberMargin(sci);
	invalidateAgeBarForView(viewIndex);
}

// Stops follow mode without prompting (deletion / explicit toggle off).
static void stopFollowAt(int viewIndex, int tabIndex, bool unwatch)
{
	auto& docs = docsForView(viewIndex);
	if (tabIndex < 0 || tabIndex >= (int)docs.size()) return;
	DocumentData& doc = docs[tabIndex];
	if (!doc.followMode) return;

	std::wstring path = doc.filePath;
	doc.followMode = false;
	doc.lineBirthTimes.clear();
	doc.lastKnownFileSize = 0;
	doc.followSuspended = false;

	if (unwatch && !path.empty() && ctx().fileMonitor)
	{
		int otherView = -1, otherTab = -1;
		if (!findFollowingTabForPath(path, otherView, otherTab))
			ctx().fileMonitor->removeFilePath(path);
	}

	updateTabFollowedIndicator(viewIndex, tabIndex);
	if (tabIndex == activeTabForView(viewIndex))
		applyAgeBarVisibilityForActive(viewIndex);
}

void stopFollowForBufferAtIndex(int viewIndex, int tabIndex)
{
	stopFollowAt(viewIndex, tabIndex, true);
}

// Safety net for coalesced/missed file events. Normal FSEvents callbacks keep
// DocumentData current even while hidden; activation only has to bridge any
// size delta that slipped past the watcher into the now-visible Scintilla view.
static void catchUpFollowedTab(int viewIndex)
{
	auto& docs = docsForView(viewIndex);
	int tab = activeTabForView(viewIndex);
	if (tab < 0 || tab >= (int)docs.size()) return;
	DocumentData& doc = docs[tab];
	if (!doc.followMode || doc.filePath.empty() || doc.modified) return;

	void* sci = scintillaForView(viewIndex);
	if (!sci) return;

	uint64_t newSize = fileSizeBytes(doc.filePath);
	if (newSize < doc.lastKnownFileSize)
	{
		if (replaceDocumentWithFile(doc, doc.filePath))
			replaceVisibleScintillaFromDocument(viewIndex, doc);
		return;
	}
	if (newSize > doc.lastKnownFileSize)
	{
		uint64_t offset = doc.lastKnownFileSize;
		std::string appended = appendFileRangeToDocument(doc, doc.filePath, offset, newSize);
		if (!appended.empty())
			appendTextToVisibleScintilla(viewIndex, doc, appended);
	}
}

static void handleFileChangedForTab(const std::wstring& path, FileMonitorAction action,
                                    int viewIndex, int tabIndex)
{
	auto& docs = docsForView(viewIndex);
	if (tabIndex < 0 || tabIndex >= (int)docs.size()) return;
	DocumentData& doc = docs[tabIndex];

	if (action == FileMonitorAction::Removed)
	{
		stopFollowAt(viewIndex, tabIndex, true);
		return;
	}

	// If user has unsaved changes, don't clobber them.
	if (doc.modified)
	{
		doc.followSuspended = true;
		return;
	}

	uint64_t newSize = fileSizeBytes(path);
	if (newSize == doc.lastKnownFileSize) return; // metadata-only touch

	bool isVisibleTab = (tabIndex == activeTabForView(viewIndex));

	if (newSize < doc.lastKnownFileSize)
	{
		if (replaceDocumentWithFile(doc, path) && isVisibleTab)
			replaceVisibleScintillaFromDocument(viewIndex, doc);
		return;
	}

	uint64_t offset = doc.lastKnownFileSize;
	std::string appended = appendFileRangeToDocument(doc, path, offset, newSize);
	if (isVisibleTab && !appended.empty())
		appendTextToVisibleScintilla(viewIndex, doc, appended);
}

static void onFileChanged(const std::wstring& path, FileMonitorAction action)
{
	for (int vi = 0; vi < 2; ++vi)
	{
		auto& docs = docsForView(vi);
		for (int ti = 0; ti < (int)docs.size(); ++ti)
		{
			if (docs[ti].followMode && docs[ti].filePath == path)
				handleFileChangedForTab(path, action, vi, ti);
		}
	}
}

// ---------------------------------------------------------------------------
// Toggle entry points
// ---------------------------------------------------------------------------

void toggleFollowMode(int viewIndex, int tabIndex)
{
	auto& docs = docsForView(viewIndex);
	if (tabIndex < 0 || tabIndex >= (int)docs.size()) return;
	DocumentData& doc = docs[tabIndex];

	if (doc.followMode)
	{
		stopFollowAt(viewIndex, tabIndex, true);
		return;
	}

	// Turn ON — works for any tab, but requires a file path for the watch.
	doc.followMode = true;
	doc.followSuspended = false;

	void* sci = scintillaForView(viewIndex);
	if (tabIndex == activeTabForView(viewIndex) && sci)
	{
		intptr_t lineCount = ScintillaBridge_sendMessage(sci, SCI_GETLINECOUNT, 0, 0);
		doc.lineBirthTimes.assign((size_t)std::max<intptr_t>(0, lineCount), (uint64_t)0);
	}
	else
	{
		doc.lineBirthTimes.assign(lineCountForContent(doc.content), (uint64_t)0);
	}

	if (!doc.filePath.empty())
	{
		doc.lastKnownFileSize = fileSizeBytes(doc.filePath);
		if (ctx().fileMonitor)
		{
			std::wstring p = doc.filePath;
			ctx().fileMonitor->addFilePath(p, [p](FileMonitorAction action, const std::wstring& /*evtPath*/) {
				dispatch_async(dispatch_get_main_queue(), ^{
					onFileChanged(p, action);
				});
			});
		}
	}

	updateTabFollowedIndicator(viewIndex, tabIndex);
	if (tabIndex == activeTabForView(viewIndex))
		applyAgeBarVisibilityForActive(viewIndex);
}

void toggleFollowModeForActiveTab(int viewIndex)
{
	int tab = activeTabForView(viewIndex);
	if (tab < 0) return;
	toggleFollowMode(viewIndex, tab);
}

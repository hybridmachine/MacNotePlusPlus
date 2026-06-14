// document_data.h — Per-tab document state, encoding types
// Part of the PaperWasp macOS app.

#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include "npp_constants.h"

// Encoding constants
enum DocEncoding
{
	ENC_UTF8 = 0,
	ENC_UTF8_BOM = 1,
	ENC_UTF16_LE = 2,
	ENC_UTF16_BE = 3,
	ENC_ANSI = 4,
};

inline const char* encodingName(int enc)
{
	switch (enc)
	{
		case ENC_UTF8:     return "UTF-8";
		case ENC_UTF8_BOM: return "UTF-8 BOM";
		case ENC_UTF16_LE: return "UTF-16 LE";
		case ENC_UTF16_BE: return "UTF-16 BE";
		case ENC_ANSI:     return "ANSI";
		default:           return "UTF-8";
	}
}

inline const char* eolName(int mode)
{
	switch (mode)
	{
		case SC_EOL_CRLF: return "CRLF";
		case SC_EOL_CR:   return "CR";
		case SC_EOL_LF:   return "LF";
		default:          return "LF";
	}
}

struct DocumentData
{
	std::wstring filePath;
	std::wstring title = L"Untitled";
	std::string content;
	intptr_t cursorPos = 0;
	intptr_t anchorPos = 0;
	intptr_t firstVisibleLine = 0;
	bool modified = false;
	bool savePointValid = true; // false when Scintilla's save point doesn't reflect real saved state
	bool readOnly = false;
	int languageIndex = 2; // Default: C++
	std::vector<int> bookmarkedLines; // Persisted across tab switches
	intptr_t documentPtr = 0; // Scintilla Document* (via SCI_CREATEDOCUMENT); preserves undo/change history across tab switches
	int encoding = ENC_UTF8;
	int eolMode = SC_EOL_LF;
	int zoomLevel = 0;
	uint64_t functionListDocumentId = 0;
	uint64_t functionListRevision = 0;
	uint64_t bufferId = 0; // Stable buffer ID for plugin API (NPPM_GETCURRENTBUFFERID etc.)

	// Follow Mode: tail-follow external file changes; render per-line age heatmap.
	bool followMode = false;
	std::vector<uint64_t> lineBirthTimes; // monotonic ms per line index
	uint64_t lastKnownFileSize = 0;       // last on-disk size we've observed
	bool followSuspended = false;         // true when external change arrived while dirty
};

// Allocate a unique buffer ID (monotonic, never reused)
uint64_t allocateBufferId();

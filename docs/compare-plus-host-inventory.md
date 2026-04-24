# ComparePlus Host-Surface Inventory

Generated as part of Phase 0, Issue #100. Updated after ComparePlus colors and
Visual Filters work.

Status note: "accepted no-op" means the macOS host consumes the message so
ComparePlus can continue, but there is no equivalent visible macOS UI surface yet.

## Tier 1: Blocks Basic Compare

| Message | Used In | Host Status |
|---------|---------|-------------|
| `NPPM_GETCURRENTBUFFERID` | NppHelpers.h:473 | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_GETPOSFROMBUFFERID` | NppHelpers.h:459,466; NppHelpers.cpp:302 | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_GETBUFFERIDFROMPOS` | NppHelpers.cpp:508,516 | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_GETFULLPATHFROMBUFFERID` | Compare.h:77; NppHelpers.cpp:509,511,517,519; Compare.cpp:1135 | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_DOOPEN` | Compare.cpp:2983 | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_SWITCHTOFILE` | Compare.cpp:5108,5113 | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_SETBUFFERLANGTYPE` | Compare.cpp (createTempFile) | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_GETBUFFERLANGTYPE` | Compare.cpp (createTempFile) | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPN_BUFFERACTIVATED` | Compare.cpp (onBufferActivated) | **EMITTED** (document_manager.mm) |

## Tier 2: Blocks UI/Toolbar

| Message | Used In | Host Status |
|---------|---------|-------------|
| `NPPM_ADDTOOLBARICON_FORDARKMODE` | Compare.cpp (onToolBarReady) | **IMPLEMENTED** (accepted no-op, nppm_handler.mm) |
| `NPPM_HIDETABBAR` | Compare.cpp (5 calls) | **IMPLEMENTED** (accepted no-op, nppm_handler.mm) |
| `NPPM_GETMENUHANDLE` | Compare.cpp (NppState, 8 calls) | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_DMMREGASDCKDLG` | NavDialog.cpp | **NOT IMPLEMENTED** |
| `NPPM_DMMSHOW` / `NPPM_DMMHIDE` | NavDialog.cpp | **NOT IMPLEMENTED** |
| `NPPN_TBMODIFICATION` | Compare.cpp (onToolBarReady) | **EMITTED** (app_delegate.mm) |
| `NPPN_BEFORESHUTDOWN` | Compare.cpp (onBeforeShutdown) | **EMITTED** (app_delegate.mm) |

## Tier 3: Polish

| Message | Used In | Host Status |
|---------|---------|-------------|
| `NPPM_SETSTATUSBAR` | Compare.cpp (setStatus) | **IMPLEMENTED** (accepted no-op, nppm_handler.mm) |
| `NPPM_ADDSCNMODIFIEDFLAGS` | Compare.cpp (onNppReady) | **IMPLEMENTED** (accepted no-op, host forwards all SCN_MODIFIED) |
| `NPPM_ISTABBARHIDDEN` | NppHelpers.cpp (NppTabHandleGetter) | **IMPLEMENTED** (nppm_handler.mm, returns false) |
| `NPPM_GETBUFFERENCODING` | NppHelpers.h (encoding check) | **IMPLEMENTED** (nppm_handler.mm, maps document encoding to UniMode) |
| `NPPM_GETLINENUMBERWIDTHMODE` | Compare.cpp (NppState) | **IMPLEMENTED** (nppm_handler.mm, tracks current mode) |
| `NPPM_SETLINENUMBERWIDTHMODE` | Compare.cpp (3 calls) | **IMPLEMENTED** (compare_plus_visibility.mm, drives compare split state) |
| `NPPM_GETBOOKMARKID` | NppHelpers.h (bookmark sync) | **IMPLEMENTED** (nppm_handler.mm, returns host bookmark marker) |
| `NPPM_GETNATIVELANGFILENAME` | NppHelpers.h (localization lookup) | **IMPLEMENTED** (nppm_handler.mm, reports no localization file) |
| `NPPM_GETCURRENTCMDLINE` | Compare.cpp (checkCmdLine) | **IMPLEMENTED** (nppm_handler.mm, returns empty command line) |
| `NPPM_GETCURRENTNATIVELANGENCODING` | NppHelpers.h | **IMPLEMENTED** (nppm_handler.mm, returns UTF-8) |
| `NPPN_GLOBALMODIFIED` | Compare.cpp | **NOT EMITTED** |
| `NPPN_DARKMODECHANGED` | Compare.cpp | **NOT EMITTED** |
| `NPPN_WORDSTYLESUPDATED` | Compare.cpp | **NOT EMITTED** |

## Dialog / Control Surface

| Surface | Used In | macOS Status |
|---------|---------|--------------|
| Compare Options dialog | CompareOptionsDialog.cpp | **IMPLEMENTED** (template + real upstream dialog) |
| Settings dialog | SettingsDialog.cpp | **IMPLEMENTED** (template + real upstream dialog) |
| Settings color controls | ColorCombo.h | **IMPLEMENTED** (NSColorWell bridge, persists through UserSettings) |
| Visual Filters dialog | VisualFiltersDialog.cpp | **IMPLEMENTED** (template + real upstream dialog) |
| About dialog / URL links | AboutDialog.cpp, URLCtrl.cpp | **NOT IMPLEMENTED** (accepted no-op stubs) |
| NavBar docking panel | NavDialog.cpp | **NOT IMPLEMENTED** (blocked on `NPPM_DMM*` host surface) |
| Progress dialog | ProgressDlg.cpp | **IMPLEMENTED** (functional no-UI stub; compare never stalls/cancels) |

## Already Implemented (working)

NPPM: GETCURRENTSCINTILLA, GETCURRENTLANGTYPE, SETCURRENTLANGTYPE, GETCURRENTVIEW,
GETNBOPENFILES, MENUCOMMAND, SETMENUITEMCHECK, GETPLUGINSCONFIGDIR, GETNPPVERSION,
ALLOCATECMDID, ALLOCATEMARKER, ALLOCATEINDICATOR, GETFULLCURRENTPATH, GETFILENAME,
GETCURRENTDIRECTORY, GETNAMEPART, GETEXTPART, GETCURRENTWORD, GETCURRENTLINE, GETCURRENTCOLUMN,
GETCURRENTBUFFERID, GETPOSFROMBUFFERID, GETBUFFERIDFROMPOS, GETFULLPATHFROMBUFFERID,
DOOPEN, SWITCHTOFILE, SETBUFFERLANGTYPE, GETBUFFERLANGTYPE, GETMENUHANDLE,
ADDTOOLBARICON_FORDARKMODE, HIDETABBAR, ISTABBARHIDDEN, SETSTATUSBAR,
ADDSCNMODIFIEDFLAGS, GETBUFFERENCODING, GETLINENUMBERWIDTHMODE,
SETLINENUMBERWIDTHMODE, GETBOOKMARKID, GETNATIVELANGFILENAME, GETCURRENTCMDLINE,
GETCURRENTNATIVELANGENCODING

NPPN: NPPN_READY, NPPN_SHUTDOWN, NPPN_LANGCHANGED, NPPN_FILEBEFORECLOSE, NPPN_FILESAVED,
NPPN_FILEOPENED, NPPN_FILECLOSED, NPPN_BUFFERACTIVATED, NPPN_BEFORESHUTDOWN, NPPN_TBMODIFICATION

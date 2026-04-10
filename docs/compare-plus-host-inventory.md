# ComparePlus Host-Surface Inventory

Generated as part of Phase 0, Issue #100. Updated after Phase 1 implementation.

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
| `NPPM_ADDTOOLBARICON_FORDARKMODE` | Compare.cpp (onToolBarReady) | **NOT IMPLEMENTED** |
| `NPPM_HIDETABBAR` | Compare.cpp (5 calls) | **NOT IMPLEMENTED** |
| `NPPM_GETMENUHANDLE` | Compare.cpp (NppState, 8 calls) | **IMPLEMENTED** (nppm_handler.mm) |
| `NPPM_DMMREGASDCKDLG` | NavDialog.cpp | **NOT IMPLEMENTED** |
| `NPPM_DMMSHOW` / `NPPM_DMMHIDE` | NavDialog.cpp | **NOT IMPLEMENTED** |
| `NPPN_TBMODIFICATION` | Compare.cpp (onToolBarReady) | **EMITTED** (app_delegate.mm) |
| `NPPN_BEFORESHUTDOWN` | Compare.cpp (onBeforeShutdown) | **EMITTED** (app_delegate.mm) |

## Tier 3: Polish

| Message | Used In | Host Status |
|---------|---------|-------------|
| `NPPM_SETSTATUSBAR` | Compare.cpp (setStatus) | **NOT IMPLEMENTED** |
| `NPPM_ADDSCNMODIFIEDFLAGS` | Compare.cpp (onNppReady) | **IMPLEMENTED** (no-op, host forwards all SCN_MODIFIED) |
| `NPPM_GETLINENUMBERWIDTHMODE` | Compare.cpp (NppState) | **NOT IMPLEMENTED** |
| `NPPM_SETLINENUMBERWIDTHMODE` | Compare.cpp (3 calls) | **NOT IMPLEMENTED** |
| `NPPM_GETCURRENTCMDLINE` | Compare.cpp (checkCmdLine) | **NOT IMPLEMENTED** |
| `NPPM_GETCURRENTNATIVELANGENCODING` | NppHelpers.h | **IMPLEMENTED** (nppm_handler.mm, returns UTF-8) |
| `NPPN_GLOBALMODIFIED` | Compare.cpp | **NOT EMITTED** |
| `NPPN_DARKMODECHANGED` | Compare.cpp | **NOT EMITTED** |
| `NPPN_WORDSTYLESUPDATED` | Compare.cpp | **NOT EMITTED** |

## Already Implemented (working)

NPPM: GETCURRENTSCINTILLA, GETCURRENTLANGTYPE, SETCURRENTLANGTYPE, GETCURRENTVIEW,
GETNBOPENFILES, MENUCOMMAND, SETMENUITEMCHECK, GETPLUGINSCONFIGDIR, GETNPPVERSION,
ALLOCATECMDID, ALLOCATEMARKER, ALLOCATEINDICATOR, GETFULLCURRENTPATH, GETFILENAME,
GETCURRENTDIRECTORY, GETNAMEPART, GETEXTPART, GETCURRENTWORD, GETCURRENTLINE, GETCURRENTCOLUMN,
GETCURRENTBUFFERID, GETPOSFROMBUFFERID, GETBUFFERIDFROMPOS, GETFULLPATHFROMBUFFERID,
DOOPEN, SWITCHTOFILE, SETBUFFERLANGTYPE, GETBUFFERLANGTYPE, GETMENUHANDLE,
GETCURRENTNATIVELANGENCODING, ADDSCNMODIFIEDFLAGS

NPPN: NPPN_READY, NPPN_SHUTDOWN, NPPN_LANGCHANGED, NPPN_FILEBEFORECLOSE, NPPN_FILESAVED,
NPPN_FILEOPENED, NPPN_FILECLOSED, NPPN_BUFFERACTIVATED, NPPN_BEFORESHUTDOWN, NPPN_TBMODIFICATION

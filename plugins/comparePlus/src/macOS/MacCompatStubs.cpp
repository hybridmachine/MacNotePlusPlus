// ComparePlus macOS compatibility stubs.
//
// Phase 2 goal: let the dylib dlopen cleanly even though we only compile the
// diff-engine slice of the plugin. Every Win32-heavy UI class (dialogs,
// progress window, URL/color controls) still has header declarations that
// reach into symbols we don't build on macOS, so dyld's flat-namespace
// binding fails at load time on the first unresolved symbol
// (`ProgressDlg::Inst`, then vtables for `StaticDialog` / `NavDialog` / ...).
//
// This file provides minimal, no-op implementations that anchor the vtables
// and satisfy ODR. When Phase 5 lands native AppKit replacements for each
// dialog, delete the corresponding stub here. Not a single method should do
// anything observable — the point is purely to link.
//
// Path-A rationale (see PR #101 discussion): keep upstream .cpp files
// untouched so future upstream merges stay clean.

#ifdef __APPLE__

#include <cstdint>
#include <memory>

#include <string>
#include <vector>

#include "NppAPI/DockingFeature/StaticDialog.h"
#include "ProgressDlg/ProgressDlg.h"
#include "NavDlg/NavDialog.h"
#include "AboutDlg/AboutDialog.h"
#include "AboutDlg/URLCtrl.h"
#include "CompareOptionsDlg/CompareOptionsDialog.h"
#include "VisualFiltersDlg/VisualFiltersDialog.h"
#include "SettingsDlg/SettingsDialog.h"
#include "SettingsDlg/ColorCombo.h"
#include "LibHelpers.h"

// ---------------------------------------------------------------------------
// StaticDialog — base for every dialog below.
// Defining ~StaticDialog() gives clang a "key function" so the vtable and
// typeinfo land in this TU instead of being weak-refs everywhere.
// ---------------------------------------------------------------------------

StaticDialog::~StaticDialog() {}

void StaticDialog::create(int, bool, bool) {}
void StaticDialog::destroy() {}
void StaticDialog::getMappedChildRect(HWND, RECT&) const {}
void StaticDialog::getMappedChildRect(int, RECT&) const {}
void StaticDialog::redrawDlgItem(int, bool) const {}
void StaticDialog::goToCenter(UINT) {}
void StaticDialog::display(bool, bool) const {}
RECT StaticDialog::getViewablePositionRect(RECT testRc) const { return testRc; }
POINT StaticDialog::getTopPoint(HWND, bool) const { return POINT{0, 0}; }
intptr_t StaticDialog::dlgProc(HWND, UINT, WPARAM, LPARAM) { return 0; }
HGLOBAL StaticDialog::makeRTLResource(int, DLGTEMPLATE**) { return nullptr; }

// ---------------------------------------------------------------------------
// ProgressDlg — functional stub.
// Engine.cpp calls Open()/Get()/IsCancelled()/Advance()/etc. on every compare,
// so this has to return sensible values. We track phase/max/count but never
// show UI and never signal cancellation.
// ---------------------------------------------------------------------------

// Static data members referenced via name lookup from other TUs.
progress_ptr ProgressDlg::Inst;

// Private statics — keep definitions here so nothing ODR-breaks if upstream
// starts referencing them from headers in the future.
const wchar_t ProgressDlg::cClassName[]  = L"ComparePlusProgressStub";
const int     ProgressDlg::cBackgroundColor = 0;
const int     ProgressDlg::cPBwidth      = 0;
const int     ProgressDlg::cPBheight     = 0;
const int     ProgressDlg::cBTNwidth     = 0;
const int     ProgressDlg::cBTNheight    = 0;
const int     ProgressDlg::cPhases[]     = { 0 };

ProgressDlg::ProgressDlg()
    : _hInst(nullptr), _hwnd(nullptr), _hThread(nullptr), _hActiveState(nullptr),
      _hFont(nullptr), _hPText(nullptr), _hPBar(nullptr), _hBtn(nullptr),
      _hKeyHook(nullptr),
      _phase(0), _phaseRange(0), _phasePosOffset(0),
      _max(0), _count(0), _pos(0)
{}

ProgressDlg::~ProgressDlg() {}

progress_ptr& ProgressDlg::Open(const wchar_t*)
{
    if (!Inst)
        Inst.reset(new ProgressDlg());
    return Inst;
}

void     ProgressDlg::Show() const {}
bool     ProgressDlg::IsCancelled() const { return false; }
unsigned ProgressDlg::NextPhase() { return ++_phase; }

bool ProgressDlg::SetMaxCount(intptr_t max, unsigned)
{
    _max = max;
    _count = 0;
    return true;
}

bool ProgressDlg::SetCount(intptr_t cnt, unsigned)
{
    _count = cnt;
    return true;
}

bool ProgressDlg::Advance(intptr_t cnt, unsigned)
{
    _count += cnt;
    return true;
}

// ---------------------------------------------------------------------------
// NavDialog — Compare.cpp declares a global `NavDialog NavDlg;`, so its
// vtable and default ctor are needed at load time even though we never
// actually show the nav panel in Phase 2.
// ---------------------------------------------------------------------------

// Static constants referenced by private methods (defensive; may not be ODR-used).
const int NavDialog::cSpace         = 0;
const int NavDialog::cScrollerWidth = 0;

NavDialog::NavDialog()
    : m_hInst(nullptr), m_isDarkMode(false), m_hScroll(nullptr),
      m_hBackBrush(nullptr), m_mouseOver(false),
      m_navViewWidth1(0), m_navViewWidth2(0),
      m_navHeight(0), m_navHeightTotal(0),
      m_pixelsPerLine(0), m_maxBmpLines(0),
      m_syncView(nullptr)
{}

NavDialog::~NavDialog() {}

void NavDialog::init(HINSTANCE hInst) { m_hInst = hInst; }
void NavDialog::Show() {}
void NavDialog::Hide() {}
void NavDialog::Update() {}

intptr_t NavDialog::run_dlgProc(UINT, WPARAM, LPARAM) { return 0; }

// NavView — nested inside NavDialog. reset() runs from NavView's dtor, so
// the global `NavDialog NavDlg;` and its m_view[2] array both need these
// symbols present at process start.
void NavDialog::NavView::init(HDC) {}
void NavDialog::NavView::reset() {}
int  NavDialog::NavView::docToBmpLine(intptr_t) const { return 0; }

// ---------------------------------------------------------------------------
// AboutDialog / CompareOptionsDialog / VisualFiltersDialog / SettingsDialog
// Each lives only inside a menu-handler function, so the body of doDialog()
// never runs until a user clicks the corresponding menu item. Returning 0
// is interpreted upstream as "dialog closed without action".
// ---------------------------------------------------------------------------

UINT     AboutDialog::doDialog()                            { return 0; }
intptr_t AboutDialog::run_dlgProc(UINT, WPARAM, LPARAM)     { return 0; }

UINT     CompareOptionsDialog::doDialog(UserSettings*)      { return 0; }
intptr_t CompareOptionsDialog::run_dlgProc(UINT, WPARAM, LPARAM) { return 0; }

UINT     VisualFiltersDialog::doDialog(UserSettings*)       { return 0; }
intptr_t VisualFiltersDialog::run_dlgProc(UINT, WPARAM, LPARAM)  { return 0; }

UINT     SettingsDialog::doDialog(UserSettings*)            { return 0; }
intptr_t SettingsDialog::run_dlgProc(UINT, WPARAM, LPARAM)  { return 0; }

// ---------------------------------------------------------------------------
// URLCtrl / ColorCombo — members of AboutDialog and SettingsDialog
// respectively. Anchor their vtables with one out-of-line virtual each.
// ---------------------------------------------------------------------------

void URLCtrl::create(HWND, const wchar_t*, COLORREF) {}
void URLCtrl::create(HWND, int, HWND)                {}
void URLCtrl::destroy()                              {}

void ColorCombo::init(HINSTANCE, HWND, HWND) {}

// ---------------------------------------------------------------------------
// LibHelpers — git/svn integration. Compare.cpp references these from menu
// handlers ("Compare to Git", "Compare to SVN", About dialog version strings).
// We don't compile LibHelpers.cpp on macOS because libgit2/sqlite plumbing is
// Phase 6 work. Report the features as absent.
// ---------------------------------------------------------------------------

bool isSQLlibFound() { return false; }
bool isGITlibFound() { return false; }

bool GetSvnFile(const wchar_t*, wchar_t*, unsigned) { return false; }

std::vector<char> GetGitFileContent(const wchar_t*) { return {}; }

std::wstring GetLibGit2Ver() { return L""; }
std::wstring GetSQLite3Ver() { return L""; }

#endif  // __APPLE__

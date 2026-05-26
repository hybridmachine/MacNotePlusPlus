// Hand-translated IDD_COMPARE_OPTIONS_DIALOG from Compare.rc.
//
// Each control is one DlgControlDescriptor; ordering and coordinates
// mirror the .rc file. Rect units are dialog units (DLU); the modal
// renderer converts to pixels.

#ifdef __APPLE__

#import <Foundation/Foundation.h>
#include "windows.h"             // IDOK / IDCANCEL
#include "dialog_template.h"

// Pull in plugin resource IDs so renames in the plugin source stay in
// sync automatically.
#include "../../plugins/comparePlus/src/resource.h"

namespace {

struct AutoRegister
{
	AutoRegister()
	{
		DialogTemplateCpp t;
		t.id    = IDD_COMPARE_OPTIONS_DIALOG;
		t.title = L"ComparePlus   Compare Options";
		t.x = 0; t.y = 0; t.cx = 240; t.cy = 326;

		t.controls = {
			// -- Detect group --
			{ DlgControlClass::GroupBox, IDC_DETECT, L"Detect",
			  7, 10, 226, 61 },
			{ DlgControlClass::Checkbox, IDC_DETECT_MOVES, L"Moves",
			  15, 27, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_DETECT_SUB_BLOCK_DIFFS, L"Sub-block diffs",
			  125, 27, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_DETECT_SUB_LINE_MOVES, L"Sub-line moves",
			  15, 47, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_DETECT_CHAR_DIFFS, L"Character diffs",
			  125, 47, 100, 16 },

			// -- Ignore group --
			{ DlgControlClass::GroupBox, IDC_IGNORE, L"Ignore",
			  7, 80, 226, 101 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_FOLDED_LINES, L"Folded lines",
			  15, 97, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_HIDDEN_LINES, L"Hidden lines",
			  125, 97, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_EMPTY_LINES, L"Empty lines",
			  15, 117, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_CASE, L"Case",
			  15, 137, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_EOL, L"Line endings (EOL)",
			  125, 137, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_CHANGED_SPACES, L"Changed spaces",
			  15, 157, 80, 16 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_ALL_SPACES, L"All spaces",
			  125, 157, 80, 16 },

			// -- Ignore line portions Regex group --
			{ DlgControlClass::GroupBox, IDC_REGEX, L"Ignore line portions Regex (works per-line)",
			  7, 190, 226, 101 },
			{ DlgControlClass::Checkbox, IDC_IGNORE_REGEX, L"Enable",
			  15, 207, 40, 16 },
			{ DlgControlClass::Checkbox, IDC_HIGHLIGHT_REGEX_IGNORES, L"Highlight ignored portions",
			  105, 207, 105, 16 },
			{ DlgControlClass::EditCombo, IDC_IGNORE_REGEX_STR, L"",
			  15, 227, 210, 12 },
			{ DlgControlClass::Radio, IDC_REGEX_MODE_IGNORE, L"Ignore matches",
			  20, 247, 100, 16,
			  /*isDefaultButton*/ false, /*startsGroup*/ true },
			{ DlgControlClass::Radio, IDC_REGEX_MODE_MATCH, L"Compare matches",
			  125, 247, 100, 16 },
			{ DlgControlClass::Checkbox, IDC_REGEX_INCL_NOMATCH_LINES,
			  L"Compare also lines without match",
			  70, 267, 150, 16 },

			// -- OK / Cancel --
			{ DlgControlClass::Button, IDOK, L"OK",
			  52, 303, 44, 16,
			  /*isDefaultButton*/ true },
			{ DlgControlClass::Button, IDCANCEL, L"Cancel",
			  144, 303, 44, 16 },
		};

		registerDialogTemplate(t);
	}
};

AutoRegister _register;

} // namespace

#endif // __APPLE__

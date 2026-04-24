// Hand-translated IDD_VISUAL_FILTERS_DIALOG from Compare.rc.
//
// Controls ordered to match the .rc top to bottom; rect units are
// dialog units (DLU). The dialog only uses labels, group boxes,
// checkboxes, and OK/Cancel buttons, all already supported by the shim.

#ifdef __APPLE__

#import <Foundation/Foundation.h>
#include "windows.h"
#include "dialog_template.h"

#include "../../plugins/comparePlus/src/resource.h"

namespace {

struct AutoRegister
{
	AutoRegister()
	{
		DialogTemplateCpp t;
		t.id    = IDD_VISUAL_FILTERS_DIALOG;
		t.title = L"ComparePlus   Visual Filters";
		t.x = 0; t.y = 0; t.cx = 150; t.cy = 208;

		t.controls = {
			{ DlgControlClass::Static, IDC_NOTE, L"NOTE: First line can never be hidden",
			  10, 8, 130, 16 },
			{ DlgControlClass::GroupBox, IDC_FILTERS, L"Diffs Filters",
			  7, 29, 136, 121 },
			{ DlgControlClass::Checkbox, IDC_HIDE_MATCHES, L"Hide matches",
			  15, 46, 115, 16 },
			{ DlgControlClass::Checkbox, IDC_HIDE_ALL_DIFFS, L"Hide all diffs",
			  15, 66, 115, 16 },
			{ DlgControlClass::Checkbox, IDC_HIDE_NEW_LINES, L"Hide added/removed lines",
			  20, 86, 110, 16 },
			{ DlgControlClass::Checkbox, IDC_HIDE_CHANGED_LINES, L"Hide changed lines",
			  20, 106, 110, 16 },
			{ DlgControlClass::Checkbox, IDC_HIDE_MOVED_LINES, L"Hide moved lines",
			  20, 126, 114, 16 },
			{ DlgControlClass::Checkbox, IDC_SHOW_ONLY_SELECTIONS, L"Show only compared selections",
			  15, 159, 120, 16 },
			{ DlgControlClass::Button, IDOK, L"OK",
			  20, 185, 45, 16, /*isDefault*/ true },
			{ DlgControlClass::Button, IDCANCEL, L"Cancel",
			  85, 185, 45, 16 },
		};

		registerDialogTemplate(t);
	}
};

AutoRegister _register;

} // namespace

#endif // __APPLE__

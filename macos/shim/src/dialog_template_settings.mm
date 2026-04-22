// Hand-translated IDD_SETTINGS_DIALOG from Compare.rc.
//
// Controls ordered to match the .rc top to bottom; rect units are
// dialog units (DLU). The six IDC_COMBO_*_COLOR controls are ColorCombo
// instances in the plugin (custom owner-drawn COMBOBOX that picks a
// color), rendered here as DlgControlClass::ColorCombo → NSColorWell.
// The three IDC_*_SPIN controls become NSSteppers via UpDown.

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
		t.id    = IDD_SETTINGS_DIALOG;
		t.title = L"ComparePlus   Settings";
		t.x = 0; t.y = 0; t.cx = 630; t.cy = 350;

		t.controls = {
			// -- Main column (left group) --
			{ DlgControlClass::GroupBox, IDC_MAIN, L"Main",
			  7, 7, 310, 309 },

			{ DlgControlClass::GroupBox, IDC_FIRST, L"Set as First to Compare",
			  15, 22, 122, 61 },
			{ DlgControlClass::Radio, IDC_FIRST_NEW, L"Set as new file",
			  21, 39, 107, 16, /*isDefault*/ false, /*startsGroup*/ true },
			{ DlgControlClass::Radio, IDC_FIRST_OLD, L"Set as old file",
			  21, 59, 107, 16 },

			{ DlgControlClass::GroupBox, IDC_FILES_POS, L"Files Position",
			  15, 90, 122, 61 },
			{ DlgControlClass::Radio, IDC_NEW_IN_SUB, L"New file in right view",
			  21, 107, 107, 16, false, /*startsGroup*/ true },
			{ DlgControlClass::Radio, IDC_OLD_IN_SUB, L"Old file in right view",
			  21, 127, 107, 16 },

			{ DlgControlClass::GroupBox, IDC_DEFAULT_COMPARE, L"Default Compare in Single-View",
			  15, 158, 122, 61 },
			{ DlgControlClass::Radio, IDC_COMPARE_TO_PREV, L"Current and previous files",
			  21, 175, 107, 16, false, /*startsGroup*/ true },
			{ DlgControlClass::Radio, IDC_COMPARE_TO_NEXT, L"Current and next files",
			  21, 195, 107, 16 },

			{ DlgControlClass::GroupBox, IDC_STATUS_BAR, L"Compare StatusBar Info",
			  15, 226, 122, 81 },
			{ DlgControlClass::Radio, IDC_DIFFS_SUMMARY, L"Diffs summary",
			  21, 243, 107, 16, false, /*startsGroup*/ true },
			{ DlgControlClass::Radio, IDC_COMPARE_OPTIONS, L"Compare options",
			  21, 263, 107, 16 },
			{ DlgControlClass::Radio, IDC_STATUS_DISABLED, L"Disabled",
			  21, 283, 107, 16 },

			// -- Misc. column --
			{ DlgControlClass::GroupBox, IDC_MISC, L"Misc.",
			  145, 22, 163, 285 },
			{ DlgControlClass::Checkbox, IDC_ENCODINGS_CHECK, L"Warn about encodings mismatch",
			  153, 39, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_SIZES_CHECK, L"Warn before comparing big files",
			  153, 59, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_MANUAL_SYNC_CHECK, L"Warn about active manual sync points",
			  153, 79, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_CLOSE_ON_MATCH, L"Prompt to close files on match",
			  153, 99, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_HIDE_MARGIN, L"Hide compare margin",
			  153, 119, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_NEVER_MARK_IGNORED, L"Never colorize ignored lines",
			  153, 139, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_FOLLOWING_CARET, L"Move caret on navigation",
			  153, 159, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_WRAP_AROUND, L"Wrap around diffs on navigation",
			  153, 179, 138, 16 },
			{ DlgControlClass::Checkbox, IDC_GOTO_FIRST_DIFF, L"Go to first diff after re-Compare",
			  153, 199, 138, 16 },

			// -- Coloring column --
			{ DlgControlClass::GroupBox, IDC_COLORS, L"Coloring",
			  327, 7, 146, 309 },

			{ DlgControlClass::Static, IDC_ADDED, L"Added line",
			  338, 25, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_ADDED_COLOR, L"",
			  423, 23, 40, 12 },
			{ DlgControlClass::Static, IDC_REMOVED, L"Removed line",
			  338, 46, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_REMOVED_COLOR, L"",
			  423, 44, 40, 12 },
			{ DlgControlClass::Static, IDC_MOVED, L"Moved line",
			  338, 67, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_MOVED_COLOR, L"",
			  423, 65, 40, 12 },
			{ DlgControlClass::Static, IDC_CHANGED, L"Changed line",
			  338, 88, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_CHANGED_COLOR, L"",
			  423, 86, 40, 12 },
			{ DlgControlClass::Static, IDC_ADDED_PART, L"Added part",
			  338, 109, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_ADDED_PART_COLOR, L"",
			  423, 107, 40, 12 },
			{ DlgControlClass::Static, IDC_REMOVED_PART, L"Removed part",
			  338, 130, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_REMOVED_PART_COLOR, L"",
			  423, 128, 40, 12 },
			{ DlgControlClass::Static, IDC_MOVED_PART, L"Moved part:",
			  338, 151, 60, 16 },
			{ DlgControlClass::ColorCombo, IDC_COMBO_MOVED_PART_COLOR, L"",
			  423, 149, 40, 12 },

			{ DlgControlClass::Static, IDC_PART_TRANSP, L"Part transparency [%]",
			  338, 174, 70, 24 },
			{ DlgControlClass::Edit, IDC_PART_TRANSP_EDIT, L"",
			  435, 175, 28, 14 },
			{ DlgControlClass::UpDown, IDC_PART_TRANSP_SPIN, L"",
			  458, 182, 6, 14 },

			{ DlgControlClass::Static, IDC_CARET_TRANSP, L"Caret line transparency [%]",
			  338, 202, 70, 24 },
			{ DlgControlClass::Edit, IDC_CARET_TRANSP_EDIT, L"",
			  435, 203, 28, 14 },
			{ DlgControlClass::UpDown, IDC_CARET_TRANSP_SPIN, L"",
			  458, 210, 6, 14 },

			{ DlgControlClass::Static, IDC_CHANGE_RESEMBL,
			  L"Min line resemblance to mark as changed [%]",
			  338, 230, 70, 24 },
			{ DlgControlClass::Edit, IDC_CHANGE_RES_EDIT, L"",
			  435, 231, 28, 14 },
			{ DlgControlClass::UpDown, IDC_CHANGE_RES_SPIN, L"",
			  458, 238, 6, 14 },

			// -- Toolbar column --
			{ DlgControlClass::GroupBox, IDC_TOOLBAR, L"Toolbar (require restart)",
			  483, 7, 140, 309 },
			{ DlgControlClass::Checkbox, IDC_ENABLE_TOOLBAR, L"Add the following to the toolbar:",
			  491, 25, 122, 16 },
			{ DlgControlClass::Checkbox, IDC_SET_AS_FIRST_TB, L"Set as First to Compare",
			  496, 48, 107, 16 },
			{ DlgControlClass::Checkbox, IDC_COMPARE_TB, L"Compare",
			  496, 68, 107, 16 },
			{ DlgControlClass::Checkbox, IDC_COMPARE_SELECTIONS_TB, L"Compare Selections",
			  496, 88, 107, 16 },
			{ DlgControlClass::Checkbox, IDC_CLEAR_COMPARE_TB, L"Clear Active Compare",
			  496, 108, 107, 16 },
			{ DlgControlClass::Checkbox, IDC_NAVIGATION_TB, L"Navigation commands",
			  496, 128, 107, 16 },
			{ DlgControlClass::Checkbox, IDC_DIFFS_FILTERS_TB, L"Diffs Visual Filters",
			  496, 148, 107, 16 },
			{ DlgControlClass::Checkbox, IDC_NAV_BAR_TB, L"Navigation Bar",
			  496, 168, 107, 16 },

			// -- Bottom button row --
			{ DlgControlClass::Button, IDOK, L"OK",
			  204, 327, 50, 16, /*isDefault*/ true },
			{ DlgControlClass::Button, IDDEFAULT, L"Reset",
			  282, 327, 50, 16 },
			{ DlgControlClass::Button, IDCANCEL, L"Cancel",
			  360, 327, 50, 16 },
		};

		registerDialogTemplate(t);
	}
};

AutoRegister _register;

} // namespace

#endif // __APPLE__

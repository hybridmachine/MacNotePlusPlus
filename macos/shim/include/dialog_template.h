#pragma once
// Hand-translated Win32 dialog templates for macOS-vendored plugins.
//
// Win32 .rc files aren't compiled by the macOS build, so
// `MAKEINTRESOURCEW(IDD_…)` reaches DialogBoxParamW as an integer with
// no backing template. Each dialog a vendored plugin uses is transcribed
// once into a DialogTemplateCpp literal and auto-registered at startup;
// the shim's DialogBoxParamW looks the template up by ID and renders it
// as native Cocoa controls.

#ifdef __APPLE__

#include <string>
#include <vector>

enum class DlgControlClass
{
	Button,      // BS_PUSHBUTTON or BS_DEFPUSHBUTTON
	Checkbox,    // BS_AUTOCHECKBOX
	Radio,       // BS_AUTORADIOBUTTON — grouped by startsGroup runs
	GroupBox,    // BS_GROUPBOX
	Static,      // STATIC — label text
	Edit,        // EDIT — single-line text field
	ComboBox,    // COMBOBOX with CBS_DROPDOWNLIST
	EditCombo,   // COMBOBOX without CBS_DROPDOWNLIST
	UpDown,      // msctls_updown32 spin control
	ColorCombo,  // custom ColorCombo class → NSColorWell substitute
};

struct DlgControlDescriptor
{
	DlgControlClass kind;
	int id = 0;
	std::wstring text;                // L"" for controls without text
	int x = 0, y = 0, cx = 0, cy = 0; // dialog units (DLU)
	bool isDefaultButton = false;     // only meaningful for Button
	bool startsGroup = false;         // WS_GROUP — starts a radio/tab group
};

struct DialogTemplateCpp
{
	int id = 0;                                  // matches MAKEINTRESOURCEW(id)
	std::wstring title;
	int x = 0, y = 0, cx = 0, cy = 0;            // dialog rect in DLU
	std::vector<DlgControlDescriptor> controls;
};

// Register a template for later lookup by DialogBoxParamW. Safe to call
// during static initialization.
void registerDialogTemplate(const DialogTemplateCpp& t);

// Look up a template by dialog ID. Returns nullptr if unknown.
const DialogTemplateCpp* findDialogTemplate(int dialogID);

#endif // __APPLE__

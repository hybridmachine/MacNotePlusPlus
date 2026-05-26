// Cocoa control factory for hand-translated dialog templates.

#ifdef __APPLE__

#import <Cocoa/Cocoa.h>

#include "dialog_controls.h"
#include "handle_registry.h"
#include "win32_controls_impl.h"
#include "win32_dialog_controls_impl.h"
#include "win32_string_helpers.h"

namespace {

NSString* wideToNS(const std::wstring& w)
{
	if (w.empty()) return @"";
	return [[NSString alloc] initWithBytes:w.data()
	                                length:w.size() * sizeof(wchar_t)
	                              encoding:NSUTF32LittleEndianStringEncoding];
}

// Top-left-DLU rect -> bottom-left-pixel NSRect inside `parent`.
NSRect dluToPixel(int x, int y, int cx, int cy, NSView* parent,
                  double duX, double duY)
{
	CGFloat px = x * duX;
	CGFloat pw = cx * duX;
	CGFloat ph = cy * duY;
	CGFloat py = parent.bounds.size.height - (y + cy) * duY;
	return NSMakeRect(px, py, pw, ph);
}

HWND registerDialogChild(NSView* view, const DlgControlDescriptor& desc,
                         HWND ownerDialog, ControlType controlType,
                         const wchar_t* className)
{
	HandleRegistry::WindowInfo info{};
	// HandleRegistry::createWindow() CFRetains nativeView; use __bridge to avoid double-retain.
	info.nativeView    = (__bridge void*)view;
	info.parent        = ownerDialog;
	info.controlId     = desc.id;
	info.controlType   = controlType;
	info.className     = className;
	info.windowName    = desc.text;
	return HandleRegistry::createWindow(std::move(info));
}

} // namespace

HWND createDialogControl(const DlgControlDescriptor& desc,
                         void* parentViewRaw,
                         HWND ownerDialog,
                         double duX,
                         double duY,
                         int radioGroupIndex)
{
	NSView* parent = (__bridge NSView*)parentViewRaw;
	NSRect frame   = dluToPixel(desc.x, desc.y, desc.cx, desc.cy, parent, duX, duY);
	NSString* text = wideToNS(desc.text);

	switch (desc.kind)
	{
		case DlgControlClass::Button:
		{
			NSButton* b = [[NSButton alloc] initWithFrame:frame];
			b.bezelStyle = NSBezelStyleRounded;
			b.buttonType = NSButtonTypeMomentaryPushIn;
			b.title      = text;
			if (desc.isDefaultButton) b.keyEquivalent = @"\r";
			[parent addSubview:b];
			HWND h = registerDialogChild(b, desc, ownerDialog, ControlType::Button, L"Button");
			Win32Button_Init(h);
			return h;
		}
		case DlgControlClass::Checkbox:
		{
			NSButton* b = [[NSButton alloc] initWithFrame:frame];
			b.buttonType = NSButtonTypeSwitch;
			b.title      = text;
			[parent addSubview:b];
			HWND h = registerDialogChild(b, desc, ownerDialog, ControlType::Button, L"Button");
			Win32Button_Init(h);
			return h;
		}
		case DlgControlClass::Radio:
		{
			NSButton* b = [[NSButton alloc] initWithFrame:frame];
			b.buttonType = NSButtonTypeRadio;
			b.title      = text;
			[parent addSubview:b];
			HWND h = registerDialogChild(b, desc, ownerDialog, ControlType::Button, L"Button");
			Win32Radio_Init(h, radioGroupIndex);
			return h;
		}
		case DlgControlClass::GroupBox:
		{
			NSBox* box = [[NSBox alloc] initWithFrame:frame];
			box.title    = text;
			box.boxType  = NSBoxPrimary;
			box.titlePosition = NSAtTop;
			[parent addSubview:box];
			return registerDialogChild(box, desc, ownerDialog, ControlType::Button, L"Button");
		}
		case DlgControlClass::Static:
		{
			NSTextField* tf = [NSTextField labelWithString:text];
			tf.frame = frame;
			[parent addSubview:tf];
			return registerDialogChild(tf, desc, ownerDialog, ControlType::Static, L"Static");
		}
		case DlgControlClass::Edit:
		{
			NSTextField* tf = [[NSTextField alloc] initWithFrame:frame];
			tf.editable = YES;
			tf.bezeled  = YES;
			tf.drawsBackground = YES;
			tf.stringValue = text;
			[parent addSubview:tf];
			HWND h = registerDialogChild(tf, desc, ownerDialog, ControlType::Edit, L"Edit");
			Win32Edit_Init(h);
			return h;
		}
		case DlgControlClass::ComboBox:
		{
			NSPopUpButton* pop = [[NSPopUpButton alloc] initWithFrame:frame
			                                                pullsDown:NO];
			[parent addSubview:pop];
			return registerDialogChild(pop, desc, ownerDialog, ControlType::ComboBox, L"ComboBox");
		}
		case DlgControlClass::EditCombo:
		{
			NSComboBox* combo = [[NSComboBox alloc] initWithFrame:frame];
			combo.usesDataSource = NO;
			combo.editable       = YES;
			combo.stringValue    = text;
			[parent addSubview:combo];
			return registerDialogChild(combo, desc, ownerDialog, ControlType::ComboBox, L"ComboBox");
		}
		case DlgControlClass::UpDown:
		{
			NSStepper* step = [[NSStepper alloc] initWithFrame:frame];
			step.autorepeat = YES;
			[parent addSubview:step];
			return registerDialogChild(step, desc, ownerDialog, ControlType::UpDown, L"msctls_updown32");
		}
		case DlgControlClass::ColorCombo:
		{
			NSColorWell* well = [[NSColorWell alloc] initWithFrame:frame];
			well.enabled = YES;
			[parent addSubview:well];
			return registerDialogChild(well, desc, ownerDialog, ControlType::None, L"ColorCombo");
		}
	}

	// Unknown kind — render a labelled placeholder so layout survives.
	NSTextField* ph = [NSTextField labelWithString:
	    [NSString stringWithFormat:@"?ID=%d", desc.id]];
	ph.frame = frame;
	[parent addSubview:ph];
	return registerDialogChild(ph, desc, ownerDialog, ControlType::Static, L"Static");
}

#endif // __APPLE__

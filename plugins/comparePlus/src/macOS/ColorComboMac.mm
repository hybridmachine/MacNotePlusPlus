#ifdef __APPLE__

#import <Cocoa/Cocoa.h>

#include "SettingsDlg/ColorCombo.h"
#include "handle_registry.h"

namespace {

static NSMutableDictionary<NSNumber*, id>* s_colorWellTargets = nil;

static NSNumber* keyForHwnd(HWND hwnd)
{
	return [NSNumber numberWithUnsignedLongLong:
		static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(hwnd))];
}

static CGFloat colorByte(BYTE value)
{
	return static_cast<CGFloat>(value) / 255.0;
}

static NSColor* nsColorFromColorRef(COLORREF color)
{
	return [NSColor colorWithSRGBRed:colorByte(GetRValue(color))
	                           green:colorByte(GetGValue(color))
	                            blue:colorByte(GetBValue(color))
	                           alpha:1.0];
}

static BYTE componentToByte(CGFloat value)
{
	if (value <= 0.0) return 0;
	if (value >= 1.0) return 255;
	return static_cast<BYTE>(value * 255.0 + 0.5);
}

static COLORREF colorRefFromNSColor(NSColor* color)
{
	NSColor* rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	if (!rgb)
		rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	if (!rgb)
		return RGB(0, 0, 0);

	CGFloat r = 0.0;
	CGFloat g = 0.0;
	CGFloat b = 0.0;
	CGFloat a = 0.0;
	[rgb getRed:&r green:&g blue:&b alpha:&a];
	return RGB(componentToByte(r), componentToByte(g), componentToByte(b));
}

static NSColorWell* colorWellForHwnd(HWND hwnd)
{
	auto* info = HandleRegistry::getWindowInfo(hwnd);
	if (!info || !info->nativeView)
		return nil;

	id view = (__bridge id)info->nativeView;
	if (![view isKindOfClass:[NSColorWell class]])
		return nil;

	return (NSColorWell*)view;
}

} // namespace

@interface ComparePlusColorWellTarget : NSObject
@property (assign) ColorCombo* colorCombo;
- (void)colorChanged:(id)sender;
@end

@implementation ComparePlusColorWellTarget
- (void)colorChanged:(id)sender
{
	if (!self.colorCombo || ![sender isKindOfClass:[NSColorWell class]])
		return;

	NSColorWell* well = (NSColorWell*)sender;
	self.colorCombo->setColor(colorRefFromNSColor(well.color));
}
@end

void ColorCombo::init(HINSTANCE hInst, HWND hParent, HWND hCombo)
{
	Window::init(hInst, hParent);
	_hSelf = nullptr;
	_hDefaultComboProc = nullptr;

	_comboBoxInfo = {};
	_comboBoxInfo.cbSize = sizeof(_comboBoxInfo);
	_comboBoxInfo.hwndCombo = hCombo;

	::SetWindowLongPtrW(hCombo, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

	NSColorWell* well = colorWellForHwnd(hCombo);
	if (!well)
		return;

	well.enabled = YES;
	well.color = nsColorFromColorRef(_color);

	if (!s_colorWellTargets)
		s_colorWellTargets = [[NSMutableDictionary alloc] init];

	ComparePlusColorWellTarget* target = [[ComparePlusColorWellTarget alloc] init];
	target.colorCombo = this;
	well.target = target;
	well.action = @selector(colorChanged:);
	[s_colorWellTargets setObject:target forKey:keyForHwnd(hCombo)];
	[target release];
}

void ColorCombo::destroy()
{
	HWND hCombo = _comboBoxInfo.hwndCombo;
	if (hCombo)
	{
		NSColorWell* well = colorWellForHwnd(hCombo);
		if (well)
		{
			well.target = nil;
			well.action = nil;
		}

		::SetWindowLongPtrW(hCombo, GWLP_USERDATA, 0);
		[s_colorWellTargets removeObjectForKey:keyForHwnd(hCombo)];
	}

	_comboBoxInfo = {};
	_hDefaultComboProc = nullptr;
	_hSelf = nullptr;
}

void ColorCombo::drawColor()
{
	NSColorWell* well = colorWellForHwnd(_comboBoxInfo.hwndCombo);
	if (!well)
		return;

	well.enabled = YES;
	well.color = nsColorFromColorRef(_color);
}

#endif // __APPLE__

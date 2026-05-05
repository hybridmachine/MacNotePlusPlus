// app_main.mm — Application entry point
// Part of the PaperWasp macOS app.

#import <Cocoa/Cocoa.h>
#include "app_delegate.h"

int main(int argc, const char* argv[])
{
	@autoreleasepool
	{
		NSApplication* app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];

		NppAppDelegate* delegate = [[NppAppDelegate alloc] init];
		app.delegate = delegate;

		[app run];
	}
	return 0;
}

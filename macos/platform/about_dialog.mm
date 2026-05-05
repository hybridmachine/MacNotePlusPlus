// about_dialog.mm — About dialog
// Part of the PaperWasp macOS app.

#import <Cocoa/Cocoa.h>
#include "about_dialog.h"

@interface AboutDialogController : NSObject <NSWindowDelegate>
- (void)openRepository:(id)sender;
@end

@implementation AboutDialogController
- (void)openRepository:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:
		[NSURL URLWithString:@"https://github.com/hybridmachine/PaperWasp"]];
}

- (void)windowWillClose:(NSNotification*)notification
{
	[NSApp stopModal];
}
@end

static NSTextField* makeCenteredLabel(NSString* text, NSFont* font, NSColor* color, CGFloat maxWidth)
{
	NSTextField* label = [NSTextField wrappingLabelWithString:text];
	[label setFont:font];
	if (color)
		[label setTextColor:color];
	[label setAlignment:NSTextAlignmentCenter];
	[label setLineBreakMode:NSLineBreakByWordWrapping];
	[label setMaximumNumberOfLines:0];
	[label setPreferredMaxLayoutWidth:maxWidth];
	[label setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[label widthAnchor] constraintLessThanOrEqualToConstant:maxWidth].active = YES;
	[label setContentCompressionResistancePriority:NSLayoutPriorityRequired
	                                forOrientation:NSLayoutConstraintOrientationVertical];
	return label;
}

static NSView* makeSpacer(CGFloat height)
{
	NSView* spacer = [[NSView alloc] init];
	[spacer setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[spacer heightAnchor] constraintEqualToConstant:height].active = YES;
	[[spacer widthAnchor] constraintEqualToConstant:1].active = YES;
	return spacer;
}

void showAboutDlg()
{
	@autoreleasepool {
		const CGFloat panelWidth = 480;
		const CGFloat panelHeight = 440;
		const CGFloat sideInset = 25;
		const CGFloat contentWidth = panelWidth - (sideInset * 2);

		NSPanel* panel = [[NSPanel alloc]
			initWithContentRect:NSMakeRect(0, 0, panelWidth, panelHeight)
			styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
			backing:NSBackingStoreBuffered
			defer:NO];
		[panel setTitle:@"About PaperWasp"];
		[panel center];
		[panel setReleasedWhenClosed:NO];

		// Keep the controller alive during modal
		AboutDialogController* controller = [[AboutDialogController alloc] init];

		NSView* contentView = [panel contentView];

		NSStackView* stack = [[NSStackView alloc] init];
		[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[stack setAlignment:NSLayoutAttributeCenterX];
		[stack setSpacing:7];
		[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
		[contentView addSubview:stack];

		[NSLayoutConstraint activateConstraints:@[
			[[stack topAnchor] constraintEqualToAnchor:[contentView topAnchor] constant:28],
			[[stack leadingAnchor] constraintEqualToAnchor:[contentView leadingAnchor] constant:sideInset],
			[[stack trailingAnchor] constraintEqualToAnchor:[contentView trailingAnchor] constant:-sideInset],
			[[stack bottomAnchor] constraintLessThanOrEqualToAnchor:[contentView bottomAnchor] constant:-18]
		]];

		// App icon
		NSImage* logo = [NSApp applicationIconImage];
		if (!logo)
		{
			NSString* dir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
			logo = [[NSImage alloc] initWithContentsOfFile:[dir stringByAppendingPathComponent:@"logo.png"]];
		}
		if (logo)
		{
			NSImageView* iconView = [[NSImageView alloc] init];
			[iconView setImage:logo];
			[iconView setImageScaling:NSImageScaleProportionallyUpOrDown];
			[iconView setTranslatesAutoresizingMaskIntoConstraints:NO];
			[[iconView widthAnchor] constraintEqualToConstant:72].active = YES;
			[[iconView heightAnchor] constraintEqualToConstant:72].active = YES;
			[stack addArrangedSubview:iconView];
		}

		// App name
		NSTextField* nameLabel = makeCenteredLabel(
			@"PaperWasp",
			[NSFont boldSystemFontOfSize:24],
			[NSColor labelColor],
			contentWidth);
		[stack addArrangedSubview:nameLabel];

		// Version - read from bundle at runtime
		NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
		if (!version) version = @"1.0.0";
		NSString* build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
		NSString* versionStr = build && ![build isEqualToString:version]
			? [NSString stringWithFormat:@"Version %@ (%@)", version, build]
			: [NSString stringWithFormat:@"Version %@", version];
		NSTextField* versionLabel = makeCenteredLabel(
			versionStr,
			[NSFont systemFontOfSize:15],
			[NSColor secondaryLabelColor],
			contentWidth);
		[stack addArrangedSubview:versionLabel];
		[stack setCustomSpacing:18 afterView:versionLabel];

		// Attribution
		NSTextField* creditLabel = makeCenteredLabel(
			@"Based on Notepad++ by Don Ho and the Notepad++ contributors",
			[NSFont systemFontOfSize:13],
			[NSColor labelColor],
			contentWidth);
		[stack addArrangedSubview:creditLabel];

		NSTextField* disclaimerLabel = makeCenteredLabel(
			@"PaperWasp is independent and is not endorsed by the creators of Notepad++.",
			[NSFont systemFontOfSize:12],
			[NSColor secondaryLabelColor],
			contentWidth);
		[stack addArrangedSubview:disclaimerLabel];
		[stack setCustomSpacing:20 afterView:disclaimerLabel];

		// Separator
		NSBox* separator = [[NSBox alloc] init];
		[separator setBoxType:NSBoxSeparator];
		[separator setTranslatesAutoresizingMaskIntoConstraints:NO];
		[[separator widthAnchor] constraintEqualToConstant:contentWidth].active = YES;
		[stack addArrangedSubview:separator];
		[stack setCustomSpacing:16 afterView:separator];

		// Component versions
		NSTextField* compLabel = makeCenteredLabel(
			@"Scintilla 5.5.3  \u2022  Lexilla 5.4.0  \u2022  Boost.Regex 1.90.0",
			[NSFont systemFontOfSize:11],
			[NSColor tertiaryLabelColor],
			contentWidth);
		[stack addArrangedSubview:compLabel];

		// Build date
		NSString* buildDate = [NSString stringWithFormat:@"Built: %s", __DATE__];
		NSTextField* buildLabel = makeCenteredLabel(
			buildDate,
			[NSFont systemFontOfSize:11],
			[NSColor tertiaryLabelColor],
			contentWidth);
		[stack addArrangedSubview:buildLabel];
		[stack setCustomSpacing:12 afterView:buildLabel];

		// Repository link (clickable button styled as link)
		NSButton* linkButton = [[NSButton alloc] init];
		[linkButton setTitle:@"github.com/hybridmachine/PaperWasp"];
		[linkButton setBezelStyle:NSBezelStyleInline];
		[linkButton setBordered:NO];
		[linkButton setTarget:controller];
		[linkButton setAction:@selector(openRepository:)];
		NSMutableAttributedString* linkAttr = [[NSMutableAttributedString alloc]
			initWithString:@"github.com/hybridmachine/PaperWasp"];
		[linkAttr addAttribute:NSForegroundColorAttributeName
		                 value:[NSColor linkColor]
		                 range:NSMakeRange(0, linkAttr.length)];
		[linkAttr addAttribute:NSUnderlineStyleAttributeName
		                 value:@(NSUnderlineStyleSingle)
		                 range:NSMakeRange(0, linkAttr.length)];
		[linkAttr addAttribute:NSFontAttributeName
		                 value:[NSFont systemFontOfSize:11]
		                 range:NSMakeRange(0, linkAttr.length)];
		[linkButton setAttributedTitle:linkAttr];
		[linkButton setAlignment:NSTextAlignmentCenter];
		[linkButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[[linkButton widthAnchor] constraintLessThanOrEqualToConstant:contentWidth].active = YES;
		[stack addArrangedSubview:linkButton];

		// License
		NSTextField* licenseLabel = makeCenteredLabel(
			@"GNU General Public License v3",
			[NSFont systemFontOfSize:11],
			[NSColor secondaryLabelColor],
			contentWidth);
		[stack addArrangedSubview:licenseLabel];
		[stack addArrangedSubview:makeSpacer(6)];

		// OK button
		NSButton* okButton = [[NSButton alloc] init];
		[okButton setTitle:@"OK"];
		[okButton setBezelStyle:NSBezelStyleRounded];
		[okButton setTarget:NSApp];
		[okButton setAction:@selector(stopModal)];
		[okButton setKeyEquivalent:@"\r"];
		[okButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[[okButton widthAnchor] constraintEqualToConstant:92].active = YES;
		[[okButton heightAnchor] constraintEqualToConstant:32].active = YES;
		[stack addArrangedSubview:okButton];

		// Escape triggers the panel's close, which calls windowWillClose: → stopModal
		[panel setDefaultButtonCell:[okButton cell]];
		[panel setDelegate:controller];

		[NSApp runModalForWindow:panel];
		[panel close];

		// prevent ARC from releasing controller during modal
		(void)controller;
	}
}

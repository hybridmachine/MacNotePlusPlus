// preferences_dialog.mm — Preferences dialog
// Part of the PaperWasp macOS app.

#import <Cocoa/Cocoa.h>
#include "preferences_dialog.h"
#include "npp_constants.h"
#include "app_state.h"
#include "lexer_styles.h"
#include "appearance.h"
#include "scintilla_bridge.h"
#include "settings_manager.h"
#include "language_defs.h"

void showPreferencesDlg()
{
	@autoreleasepool {
		NSPanel* panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 370)
		                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
		                                    backing:NSBackingStoreBuffered
		                                    defer:NO];
		[panel setTitle:@"Preferences"];
		[panel center];

		NSView* content = panel.contentView;

		NSTextField* asmLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 305, 130, 20)];
		asmLabel.stringValue = @".asm files:";
		asmLabel.bezeled = NO;
		asmLabel.drawsBackground = NO;
		asmLabel.editable = NO;
		asmLabel.selectable = NO;
		[content addSubview:asmLabel];

		NSPopUpButton* asmPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 302, 210, 26) pullsDown:NO];
		[asmPopup addItemWithTitle:@"Assembly (x86)"];
		[asmPopup addItemWithTitle:@"Assembly (65C02)"];
		{
			const std::string& dialect = SettingsManager::instance().settings.asmDefault;
			[asmPopup selectItemAtIndex:(dialect == "65c02") ? 1 : 0];
		}
		[content addSubview:asmPopup];

		NSTextField* asmHelp = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 273, 340, 18)];
		asmHelp.stringValue = @"(.a65 and .s65 are always 65C02.)";
		asmHelp.bezeled = NO;
		asmHelp.drawsBackground = NO;
		asmHelp.editable = NO;
		asmHelp.selectable = NO;
		asmHelp.textColor = [NSColor secondaryLabelColor];
		asmHelp.font = [NSFont systemFontOfSize:11];
		[content addSubview:asmHelp];

		NSTextField* fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 225, 100, 20)];
		fontLabel.stringValue = @"Font:";
		fontLabel.bezeled = NO;
		fontLabel.drawsBackground = NO;
		fontLabel.editable = NO;
		fontLabel.selectable = NO;
		[content addSubview:fontLabel];

		NSPopUpButton* fontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 222, 200, 26) pullsDown:NO];
		NSArray* fonts = @[@"Menlo", @"Monaco", @"SF Mono", @"Courier New", @"Consolas",
		                   @"Fira Code", @"JetBrains Mono", @"Source Code Pro"];
		for (NSString* f in fonts)
			[fontPopup addItemWithTitle:f];
		NSString* currentFont = [NSString stringWithUTF8String:ctx().fontName.c_str()];
		[fontPopup selectItemWithTitle:currentFont];
		if (fontPopup.indexOfSelectedItem < 0)
			[fontPopup selectItemAtIndex:0];
		[content addSubview:fontPopup];

		NSTextField* sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 190, 100, 20)];
		sizeLabel.stringValue = @"Font Size:";
		sizeLabel.bezeled = NO;
		sizeLabel.drawsBackground = NO;
		sizeLabel.editable = NO;
		sizeLabel.selectable = NO;
		[content addSubview:sizeLabel];

		NSPopUpButton* sizePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 187, 80, 26) pullsDown:NO];
		NSArray* sizes = @[@"9", @"10", @"11", @"12", @"13", @"14", @"16", @"18", @"20", @"24"];
		for (NSString* s in sizes)
			[sizePopup addItemWithTitle:s];
		[sizePopup selectItemWithTitle:[NSString stringWithFormat:@"%d", ctx().fontSize]];
		if (sizePopup.indexOfSelectedItem < 0)
			[sizePopup selectItemAtIndex:4];
		[content addSubview:sizePopup];

		NSTextField* tabLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 155, 100, 20)];
		tabLabel.stringValue = @"Tab Width:";
		tabLabel.bezeled = NO;
		tabLabel.drawsBackground = NO;
		tabLabel.editable = NO;
		tabLabel.selectable = NO;
		[content addSubview:tabLabel];

		NSPopUpButton* tabPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 152, 80, 26) pullsDown:NO];
		NSArray* tabSizes = @[@"2", @"3", @"4", @"5", @"6", @"7", @"8"];
		for (NSString* t in tabSizes)
			[tabPopup addItemWithTitle:t];
		[tabPopup selectItemWithTitle:[NSString stringWithFormat:@"%d", ctx().tabWidth]];
		if (tabPopup.indexOfSelectedItem < 0)
			[tabPopup selectItemAtIndex:2];
		[content addSubview:tabPopup];

		NSButton* useTabsCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 120, 300, 20)];
		useTabsCheck.title = @"Use Tabs (instead of Spaces)";
		[useTabsCheck setButtonType:NSButtonTypeSwitch];
		useTabsCheck.state = ctx().useTabs ? NSControlStateValueOn : NSControlStateValueOff;
		[content addSubview:useTabsCheck];

		NSButton* caretLineCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 90, 300, 20)];
		caretLineCheck.title = @"Highlight current line";
		[caretLineCheck setButtonType:NSButtonTypeSwitch];
		caretLineCheck.state = ctx().showCaretLine ? NSControlStateValueOn : NSControlStateValueOff;
		[content addSubview:caretLineCheck];

		NSButton* autoIndentCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 65, 300, 20)];
		autoIndentCheck.title = @"Auto-indent on Enter";
		[autoIndentCheck setButtonType:NSButtonTypeSwitch];
		autoIndentCheck.state = ctx().autoIndent ? NSControlStateValueOn : NSControlStateValueOff;
		[content addSubview:autoIndentCheck];

		NSTextField* darkLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 340, 20)];
		darkLabel.stringValue = @"Dark mode follows system preferences.";
		darkLabel.bezeled = NO;
		darkLabel.drawsBackground = NO;
		darkLabel.editable = NO;
		darkLabel.selectable = NO;
		darkLabel.textColor = [NSColor secondaryLabelColor];
		[content addSubview:darkLabel];

		NSButton* okButton = [[NSButton alloc] initWithFrame:NSMakeRect(270, 15, 90, 32)];
		okButton.title = @"OK";
		okButton.bezelStyle = NSBezelStyleRounded;
		okButton.keyEquivalent = @"\r";
		okButton.tag = 1;
		[content addSubview:okButton];

		NSButton* cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(170, 15, 90, 32)];
		cancelButton.title = @"Cancel";
		cancelButton.bezelStyle = NSBezelStyleRounded;
		cancelButton.keyEquivalent = @"\033";
		cancelButton.tag = 0;
		[content addSubview:cancelButton];

		okButton.target = NSApp;
		okButton.action = @selector(stopModal);
		cancelButton.target = NSApp;
		cancelButton.action = @selector(abortModal);

		NSModalResponse result = [NSApp runModalForWindow:panel];

		if (result == NSModalResponseStop)
		{
			NSString* selFont = fontPopup.titleOfSelectedItem;
			ctx().fontName = [selFont UTF8String];
			ctx().fontSize = sizePopup.titleOfSelectedItem.intValue;
			ctx().tabWidth = tabPopup.titleOfSelectedItem.intValue;
			ctx().showCaretLine = (caretLineCheck.state == NSControlStateValueOn);
			ctx().autoIndent = (autoIndentCheck.state == NSControlStateValueOn);
			ctx().useTabs = (useTabsCheck.state == NSControlStateValueOn);

			std::string newAsmDefault = (asmPopup.indexOfSelectedItem == 1) ? "65c02" : "x86";
			std::string oldAsmDefault = SettingsManager::instance().settings.asmDefault;
			SettingsManager::instance().settings.asmDefault = newAsmDefault;

			void* views[] = { ctx().scintillaView, ctx().scintillaView2 };
			for (void* sci : views)
			{
				if (!sci) continue;
				ScintillaBridge_sendMessage(sci, SCI_STYLESETFONT, 32, (intptr_t)ctx().fontName.c_str());
				ScintillaBridge_sendMessage(sci, SCI_STYLESETSIZE, 32, ctx().fontSize);
				ScintillaBridge_sendMessage(sci, SCI_STYLECLEARALL, 0, 0);
				ScintillaBridge_sendMessage(sci, SCI_SETTABWIDTH, ctx().tabWidth, 0);
				ScintillaBridge_sendMessage(sci, SCI_SETUSETABS, ctx().useTabs ? 1 : 0, 0);
			}

			applyAppearance();

			// If the .asm dialect changed, re-detect language on any open .asm documents
			// (auto-detected as Assembly), but preserve any manually-overridden language.
			if (newAsmDefault != oldAsmDefault)
			{
				auto retagAsm = [](std::vector<DocumentData>& docs) {
					for (auto& doc : docs)
					{
						if (doc.filePath.empty()) continue;
						if (doc.languageIndex != LANG_ASM_X86 && doc.languageIndex != LANG_ASM_65C02)
							continue;
						int detected = guessLanguage(doc.filePath);
						if (detected == LANG_ASM_X86 || detected == LANG_ASM_65C02)
							doc.languageIndex = detected;
					}
				};
				retagAsm(ctx().documents);
				retagAsm(ctx().documents2);
			}

			if (ctx().activeTab >= 0 && ctx().activeTab < static_cast<int>(ctx().documents.size()))
				applyLanguageToView(ctx().scintillaView, ctx().documents[ctx().activeTab].languageIndex);
			if (ctx().isSplit && ctx().scintillaView2 && ctx().activeTab2 >= 0 &&
			    ctx().activeTab2 < static_cast<int>(ctx().documents2.size()))
				applyLanguageToView(ctx().scintillaView2, ctx().documents2[ctx().activeTab2].languageIndex);

			auto& ss = SettingsManager::instance().settings;
			ss.fontName = ctx().fontName;
			ss.fontSize = ctx().fontSize;
			ss.tabWidth = ctx().tabWidth;
			ss.showCaretLine = ctx().showCaretLine;
			ss.autoIndent = ctx().autoIndent;
			ss.useTabs = ctx().useTabs;
			// asmDefault already set above
			SettingsManager::instance().save();
		}

		[panel orderOut:nil];
	}
}

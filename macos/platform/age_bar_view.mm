// age_bar_view.mm — Follow Mode UI: per-line age heatmap strip and editor container.
// Part of the PaperWasp macOS app.

#import "age_bar_view.h"
#include "app_state.h"
#include "settings_manager.h"
#include "scintilla_bridge.h"
#include "npp_constants.h"

#include <mach/mach_time.h>
#include <algorithm>
#include <cmath>

const CGFloat kNppAgeBarWidth = 14.0;

#ifndef SCI_POINTYFROMPOSITION
#define SCI_POINTYFROMPOSITION 2165
#endif
#ifndef SCI_TEXTHEIGHT
#define SCI_TEXTHEIGHT 2279
#endif

// ---------------------------------------------------------------------------
// Timer registry — one shared 4 Hz timer drives all visible age bars so colors
// fade smoothly without per-keystroke invalidation.
// ---------------------------------------------------------------------------

static NSHashTable<NppAgeBarView*>* sLiveBars = nil;
static NSTimer* sTickTimer = nil;

static void ensureBarRegistry()
{
	if (!sLiveBars)
		sLiveBars = [NSHashTable weakObjectsHashTable];
}

static void onTick()
{
	if (!sLiveBars) return;
	for (NppAgeBarView* bar in sLiveBars.allObjects)
	{
		if (!bar.hidden && bar.window)
			[bar setNeedsDisplay:YES];
	}
}

static void startTimerIfNeeded()
{
	if (sTickTimer) return;
	sTickTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
	                                              repeats:YES
	                                                block:^(NSTimer* /*t*/) { onTick(); }];
}

static void stopTimerIfIdle()
{
	if (!sTickTimer) return;
	BOOL anyVisible = NO;
	for (NppAgeBarView* bar in sLiveBars.allObjects)
	{
		if (!bar.hidden && bar.window) { anyVisible = YES; break; }
	}
	if (!anyVisible)
	{
		[sTickTimer invalidate];
		sTickTimer = nil;
	}
}

void invalidateAllAgeBars(void)
{
	if (!sLiveBars) return;
	for (NppAgeBarView* bar in sLiveBars.allObjects)
		[bar setNeedsDisplay:YES];
}

void invalidateAgeBarForView(int viewIndex)
{
	if (!sLiveBars) return;
	for (NppAgeBarView* bar in sLiveBars.allObjects)
	{
		if (bar.viewIndex == viewIndex && !bar.hidden)
			[bar setNeedsDisplay:YES];
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static uint64_t currentMillis()
{
	static mach_timebase_info_data_t tb = {0, 0};
	if (tb.denom == 0)
		mach_timebase_info(&tb);
	uint64_t now = mach_absolute_time();
	// to nanoseconds, then ms
	return (now * tb.numer / tb.denom) / 1000000ULL;
}

static NSColor* colorFromARGB(uint32_t argb)
{
	CGFloat a = ((argb >> 24) & 0xFF) / 255.0;
	CGFloat r = ((argb >> 16) & 0xFF) / 255.0;
	CGFloat g = ((argb >>  8) & 0xFF) / 255.0;
	CGFloat b = ( argb        & 0xFF) / 255.0;
	return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}

static NSColor* lerpColor(NSColor* a, NSColor* b, CGFloat t)
{
	if (t <= 0) return a;
	if (t >= 1) return b;
	CGFloat ar, ag, ab, aa;
	CGFloat br, bg, bb, ba;
	[a getRed:&ar green:&ag blue:&ab alpha:&aa];
	[b getRed:&br green:&bg blue:&bb alpha:&ba];
	return [NSColor colorWithCalibratedRed:ar + (br - ar) * t
	                                 green:ag + (bg - ag) * t
	                                  blue:ab + (bb - ab) * t
	                                 alpha:aa + (ba - aa) * t];
}

// Map an age in milliseconds to a heatmap color using the 3 stops + 3 thresholds.
// <newSec → newColor; between new and medium → lerp(new, medium); between medium
// and old → lerp(medium, old); >oldSec → oldColor.
static NSColor* colorForAge(uint64_t ageMs)
{
	int tNew = ctx().followThresholdNewSec;
	int tMid = ctx().followThresholdMediumSec;
	int tOld = ctx().followThresholdOldSec;
	if (tNew < 0) tNew = 0;
	if (tMid < tNew + 1) tMid = tNew + 1;
	if (tOld < tMid + 1) tOld = tMid + 1;

	NSColor* cNew = colorFromARGB(ctx().followColorNew);
	NSColor* cMid = colorFromARGB(ctx().followColorMedium);
	NSColor* cOld = colorFromARGB(ctx().followColorOld);

	double sec = (double)ageMs / 1000.0;
	if (sec <= tNew) return cNew;
	if (sec >= tOld) return cOld;
	if (sec < tMid)
	{
		CGFloat t = (sec - tNew) / (tMid - tNew);
		return lerpColor(cNew, cMid, t);
	}
	CGFloat t = (sec - tMid) / (tOld - tMid);
	return lerpColor(cMid, cOld, t);
}

// Resolve the active document for a given view index, or nullptr if no tab is open.
static DocumentData* activeDocForView(int viewIndex)
{
	auto& docs = (viewIndex == 0) ? ctx().documents : ctx().documents2;
	int idx = (viewIndex == 0) ? ctx().activeTab : ctx().activeTab2;
	if (idx < 0 || idx >= (int)docs.size()) return nullptr;
	return &docs[idx];
}

// ---------------------------------------------------------------------------
// NppAgeBarView
// ---------------------------------------------------------------------------

@implementation NppAgeBarView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self)
	{
		ensureBarRegistry();
		[sLiveBars addObject:self];
	}
	return self;
}

- (void)dealloc
{
	if (sLiveBars)
		[sLiveBars removeObject:self];
	stopTimerIfIdle();
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if (self.window && !self.hidden)
		startTimerIfNeeded();
	else
		stopTimerIfIdle();
}

- (void)setHidden:(BOOL)hidden
{
	[super setHidden:hidden];
	if (!hidden)
		startTimerIfNeeded();
	else
		stopTimerIfIdle();
}

- (BOOL)isFlipped { return YES; } // top-down so Y aligns with Scintilla's Y

- (BOOL)isDarkMode
{
	NSAppearanceName name = [self.effectiveAppearance
		bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	return [name isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)drawRect:(NSRect)dirtyRect
{
	// Background — match the editor: white in light mode, near-black in dark mode.
	BOOL dark = [self isDarkMode];
	NSColor* bg = dark
		? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]
		: [NSColor whiteColor];
	[bg setFill];
	NSRectFill(self.bounds);

	DocumentData* doc = activeDocForView(_viewIndex);
	if (!doc || !doc->followMode) return;

	void* sci = (_viewIndex == 0) ? ctx().scintillaView : ctx().scintillaView2;
	if (!sci) return;

	const auto& bt = doc->lineBirthTimes;
	if (bt.empty()) return;

	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;
	if (w <= 0 || h <= 0) return;

	uint64_t now = currentMillis();

	intptr_t firstVis      = ScintillaBridge_sendMessage(sci, SCI_GETFIRSTVISIBLELINE, 0, 0);
	intptr_t linesOnScreen = ScintillaBridge_sendMessage(sci, SCI_LINESONSCREEN, 0, 0);
	intptr_t totalDocLines = (intptr_t)bt.size();

	// Walk every visible line, paint a rectangle in the bar at the same Y as
	// the line in the editor so colors stay locked to lines as the user scrolls.
	for (intptr_t v = 0; v <= linesOnScreen; ++v)
	{
		intptr_t visibleLine = firstVis + v;
		intptr_t docLine = ScintillaBridge_sendMessage(sci, SCI_DOCLINEFROMVISIBLE,
		                                               (uintptr_t)visibleLine, 0);
		if (docLine < 0 || docLine >= totalDocLines) continue;

		intptr_t pos = ScintillaBridge_sendMessage(sci, SCI_POSITIONFROMLINE,
		                                           (uintptr_t)docLine, 0);
		intptr_t y  = ScintillaBridge_sendMessage(sci, SCI_POINTYFROMPOSITION, 0, pos);
		intptr_t lh = ScintillaBridge_sendMessage(sci, SCI_TEXTHEIGHT,
		                                          (uintptr_t)docLine, 0);
		if (lh <= 0) continue;
		if ((CGFloat)y >= h) break;

		uint64_t birth = bt[(size_t)docLine];
		NSColor* c;
		if (birth == 0)
		{
			c = colorFromARGB(ctx().followColorOld);
		}
		else
		{
			uint64_t age = (now < birth) ? 0 : (now - birth);
			c = colorForAge(age);
		}

		[c setFill];
		NSRectFill(NSMakeRect(0, (CGFloat)y, w, (CGFloat)lh));
	}
}

@end

// ---------------------------------------------------------------------------
// NppEditorContainer
// ---------------------------------------------------------------------------

@implementation NppEditorContainer

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self)
	{
		_viewIndex = 0;
		_ageBarVisible = NO;
		_ageBar = [[NppAgeBarView alloc] initWithFrame:NSMakeRect(0, 0, kNppAgeBarWidth, frameRect.size.height)];
		_ageBar.viewIndex = 0;
		_ageBar.hidden = YES;
		_ageBar.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
		[self addSubview:_ageBar];
	}
	return self;
}

- (void)setViewIndex:(int)viewIndex
{
	_viewIndex = viewIndex;
	_ageBar.viewIndex = viewIndex;
}

- (void)setAgeBarVisible:(BOOL)visible
{
	if (_ageBarVisible == visible) return;
	_ageBarVisible = visible;
	_ageBar.hidden = !visible;
	[self applyLayout];
	[_ageBar setNeedsDisplay:YES];
}

- (void)setScintillaChild:(NSView*)child
{
	_scintillaChild = child;
	// Manage the child's frame ourselves so we can inset for the age bar.
	if (child)
		child.autoresizingMask = NSViewNotSizable;
	[self applyLayout];
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self applyLayout];
}

- (void)applyLayout
{
	NSSize sz = self.bounds.size;
	CGFloat barW = _ageBarVisible ? kNppAgeBarWidth : 0.0;
	CGFloat sciW = std::max<CGFloat>(0.0, sz.width - barW);

	if (_scintillaChild)
		_scintillaChild.frame = NSMakeRect(0, 0, sciW, sz.height);

	if (_ageBar)
		_ageBar.frame = NSMakeRect(sciW, 0, barW, sz.height);
}

@end

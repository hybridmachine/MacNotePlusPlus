// age_bar_view.h — Follow Mode UI: per-line age heatmap strip and editor container.
// Part of the PaperWasp macOS app.

#pragma once

#import <Cocoa/Cocoa.h>

@class NppAgeBarView;

// NSView subclass that hosts the Scintilla view and (when follow mode is active)
// the age bar strip on its right edge. Overrides setFrameSize: to keep both
// subviews positioned correctly when the container is resized by the panel layout.
@interface NppEditorContainer : NSView
@property (nonatomic, assign) int viewIndex; // 0 = main, 1 = sub-split
@property (nonatomic, weak) NSView* scintillaChild; // ScintillaView or wrapping container
@property (nonatomic, strong, readonly) NppAgeBarView* ageBar;
@property (nonatomic, assign) BOOL ageBarVisible;
- (void)applyLayout;
@end

// Custom NSView that paints a minimap-style age heatmap for the followed document
// bound to the given editor view (0 = main, 1 = sub-split).
@interface NppAgeBarView : NSView
@property (nonatomic, assign) int viewIndex;
@end

// Public bar width (used by NppEditorContainer to inset Scintilla)
extern const CGFloat kNppAgeBarWidth;

// Invalidate all visible age bars (call after settings change so colors refresh
// without waiting for the next timer tick).
void invalidateAllAgeBars(void);

// Invalidate the age bar bound to a specific view index (0 main, 1 sub-split).
// Called from the Scintilla scroll/update handler so the bar tracks scrolling.
void invalidateAgeBarForView(int viewIndex);

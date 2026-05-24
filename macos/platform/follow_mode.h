// follow_mode.h — Tail-follow external file changes + per-line age tracking.
// Part of the PaperWasp macOS app.

#pragma once

struct SciNotification;

// Toggle Follow Mode on the active tab of the given view (0 = main, 1 = sub-split).
// Updates the buffer flag, wires/unwires the file watch, updates tab indicators
// and the age bar visibility.
void toggleFollowModeForActiveTab(int viewIndex);

// Toggle Follow Mode on a specific tab in a specific view (used by tab right-click).
void toggleFollowMode(int viewIndex, int tabIndex);

// SCN_MODIFIED notification hook — records lineBirthTimes for inserted lines
// and erases them for deleted lines on the active tab of the given view.
void handleFollowModified(int viewIndex, const SciNotification* scn);

// Called when the active tab in a view changes; refreshes the age bar visibility
// and rebinds the bar to the new active document.
void refreshFollowUIForViewActiveTab(int viewIndex);

// Called when a tab is being closed — stops watching the file and clears state.
void stopFollowForBufferAtIndex(int viewIndex, int tabIndex);

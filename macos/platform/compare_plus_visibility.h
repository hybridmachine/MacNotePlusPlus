// compare_plus_visibility.h — show/hide the second Scintilla view based on
// compare-mode transitions signalled by NPPM_SETLINENUMBERWIDTHMODE.

#pragma once

// Called when the plugin sends NPPM_SETLINENUMBERWIDTHMODE. `mode` is the
// lParam value; LINENUMWIDTH_CONSTANT (1) means "compare mode active",
// anything else means "compare mode off". Returns TRUE to satisfy the
// caller's expected return value.
long handleLineNumberWidthModeChange(int mode);

// plugin_invariants.h — launch-time and NPPN_READY assertions.
// Output is gated behind MACNOTE_PLUGIN_DEBUG=1 env var.

#pragma once

// Call immediately before pluginManager().init(). Asserts that the state
// every plugin relies on is populated correctly.
void assertPluginPreInitInvariants();

// Call immediately after NPPN_READY fan-out. Diagnoses plugin handshake
// issues.
void dumpPluginPostReadyState();

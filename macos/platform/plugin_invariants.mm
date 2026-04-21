#import <Cocoa/Cocoa.h>
#include "plugin_invariants.h"
#include "app_state.h"
#include "menu_builder.h"

static bool debugEnabled()
{
    static int cached = -1;
    if (cached < 0)
    {
        const char* v = getenv("MACNOTE_PLUGIN_DEBUG");
        cached = (v && v[0] == '1') ? 1 : 0;
    }
    return cached == 1;
}

void assertPluginPreInitInvariants()
{
    NSCAssert(ctx().mainHwnd != nullptr,
              @"mainHwnd must be valid before plugin init");
    NSCAssert(ctx().scintillaMainHwnd != nullptr,
              @"scintillaMainHwnd must be valid before plugin init");
    NSCAssert(ctx().scintillaSecondHwnd != nullptr,
              @"scintillaSecondHwnd must be eager-allocated before plugin init "
              @"(see app_delegate.mm:272-289)");

    if (debugEnabled())
    {
        NSLog(@"[plugin-invariants] pre-init: main=%p sciMain=%p sciSecond=%p",
              ctx().mainHwnd, ctx().scintillaMainHwnd, ctx().scintillaSecondHwnd);
    }
}

void dumpPluginPostReadyState()
{
    if (!debugEnabled()) return;
    NSLog(@"[plugin-invariants] post-ready: pluginsMenu=%p isSplit=%d hostSplit=%d",
          getPluginsMenuHandle(), ctx().isSplit ? 1 : 0,
          ctx().hostInitiatedSplit ? 1 : 0);
}

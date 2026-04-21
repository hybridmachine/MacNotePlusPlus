// compare_plus_visibility.mm — implementation

#import <Cocoa/Cocoa.h>
#include "compare_plus_visibility.h"
#include "app_state.h"
#include "split_view.h"
#include "Notepad_plus_msgs.h"

long handleLineNumberWidthModeChange(int mode)
{
    ctx().lineNumberWidthMode = mode;

    if (mode == LINENUMWIDTH_CONSTANT)
    {
        // Entering compare mode. If the user hasn't already split, split now
        // and remember that it was host-initiated so we auto-unsplit later.
        if (!ctx().isSplit)
        {
            doSplit();
            ctx().hostInitiatedSplit = ctx().isSplit; // doSplit may fail
        }
    }
    else
    {
        // Exiting compare mode. Always clear hostInitiatedSplit so a manual
        // unsplit during compare cannot leak the flag into a later
        // user-initiated split.
        if (ctx().hostInitiatedSplit)
        {
            if (ctx().isSplit)
                doUnsplit();
            ctx().hostInitiatedSplit = false;
        }
    }
    return TRUE;
}

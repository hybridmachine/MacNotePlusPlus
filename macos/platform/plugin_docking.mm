#import <Cocoa/Cocoa.h>

#include "plugin_docking.h"
#include "app_state.h"
#include "handle_registry.h"
#include "panel_layout.h"
#include "Docking.h"

#include <cwchar>
#include <vector>

struct PluginDockingPanel
{
	HWND hwnd = nullptr;
	std::wstring name;
	std::wstring moduleName;
	int dlgID = 0;
	UINT mask = 0;
	bool visible = false;
};

static NSView* sPluginDockingContainer = nil;
static std::vector<PluginDockingPanel> sPanels;

static bool ensureContainer()
{
	if (sPluginDockingContainer)
		return true;
	if (!ctx().mainWindow)
		return false;
	NSView* contentView = ctx().mainWindow.contentView;
	if (!contentView)
		return false;

	sPluginDockingContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, ctx().rightPanelWidth, 100)];
	sPluginDockingContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	sPluginDockingContainer.hidden = YES;
	[contentView addSubview:sPluginDockingContainer];
	return true;
}

static PluginDockingPanel* findPanel(HWND hwnd)
{
	for (auto& panel : sPanels)
	{
		if (panel.hwnd == hwnd)
			return &panel;
	}
	return nullptr;
}

static NSView* nativeViewForHwnd(HWND hwnd)
{
	auto* info = HandleRegistry::getWindowInfo(hwnd);
	if (!info || !info->nativeView)
		return nil;
	return (__bridge NSView*)info->nativeView;
}

static void attachPanelView(HWND hwnd)
{
	if (!ensureContainer())
		return;
	NSView* view = nativeViewForHwnd(hwnd);
	if (!view)
		return;
	if (view.superview != sPluginDockingContainer)
	{
		[view removeFromSuperview];
		[sPluginDockingContainer addSubview:view];
	}
	view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

bool registerPluginDockingDialog(const void* dockingData)
{
	if (!dockingData)
		return false;
	const tTbData* data = static_cast<const tTbData*>(dockingData);
	if (!data->hClient)
		return false;
	if (!ensureContainer())
		return false;

	PluginDockingPanel* existing = findPanel(data->hClient);
	if (!existing)
	{
		PluginDockingPanel panel;
		panel.hwnd = data->hClient;
		panel.name = data->pszName ? data->pszName : L"";
		panel.moduleName = data->pszModuleName ? data->pszModuleName : L"";
		panel.dlgID = data->dlgID;
		panel.mask = data->uMask;
		sPanels.push_back(std::move(panel));
		existing = &sPanels.back();
	}
	else
	{
		existing->name = data->pszName ? data->pszName : L"";
		existing->moduleName = data->pszModuleName ? data->pszModuleName : L"";
		existing->dlgID = data->dlgID;
		existing->mask = data->uMask;
	}

	attachPanelView(data->hClient);
	NSView* view = nativeViewForHwnd(data->hClient);
	if (view)
		view.hidden = YES;
	layoutPluginDockingViews();
	return true;
}

bool showPluginDockingDialog(HWND hwnd)
{
	PluginDockingPanel* panel = findPanel(hwnd);
	if (!panel)
		return false;
	attachPanelView(hwnd);

	for (auto& candidate : sPanels)
	{
		candidate.visible = (candidate.hwnd == hwnd);
		NSView* view = nativeViewForHwnd(candidate.hwnd);
		if (view)
			view.hidden = !candidate.visible;
	}

	if (sPluginDockingContainer)
		sPluginDockingContainer.hidden = NO;
	relayoutPanels();
	layoutPluginDockingViews();
	return true;
}

bool hidePluginDockingDialog(HWND hwnd)
{
	PluginDockingPanel* panel = findPanel(hwnd);
	if (!panel)
		return false;
	panel->visible = false;
	NSView* view = nativeViewForHwnd(hwnd);
	if (view)
		view.hidden = YES;
	if (sPluginDockingContainer)
		sPluginDockingContainer.hidden = !isPluginDockingVisible();
	relayoutPanels();
	return true;
}

bool updatePluginDockingDialog(HWND hwnd)
{
	NSView* view = nativeViewForHwnd(hwnd);
	if (!view)
		return false;
	view.needsDisplay = YES;
	return true;
}

bool showPluginDockingDialogByName(const wchar_t* name)
{
	if (!name)
		return false;
	for (const auto& panel : sPanels)
	{
		if (panel.name == name)
			return showPluginDockingDialog(panel.hwnd);
	}
	return false;
}

HWND findPluginDockingDialog(const wchar_t* windowName, const wchar_t* moduleName)
{
	if (!moduleName)
		return nullptr;
	for (const auto& panel : sPanels)
	{
		if (panel.moduleName != moduleName)
			continue;
		if (!windowName || panel.name == windowName)
			return panel.hwnd;
	}
	return nullptr;
}

bool isPluginDockingVisible()
{
	for (const auto& panel : sPanels)
	{
		if (panel.visible)
			return true;
	}
	return false;
}

void* pluginDockingContainerView()
{
	if (!sPluginDockingContainer)
		ensureContainer();
	return (__bridge void*)sPluginDockingContainer;
}

void layoutPluginDockingViews()
{
	if (!sPluginDockingContainer)
		return;

	sPluginDockingContainer.hidden = !isPluginDockingVisible();
	for (const auto& panel : sPanels)
	{
		NSView* view = nativeViewForHwnd(panel.hwnd);
		if (!view)
			continue;
		view.hidden = !panel.visible;
		if (panel.visible)
			view.frame = sPluginDockingContainer.bounds;
	}
}

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#include "windows.h"
#include "PluginInterface.h"
#include "Docking.h"
#include "handle_registry.h"

#include <algorithm>
#include <cctype>
#include <cwchar>
#include <cwctype>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

static constexpr int kCommandCount = 6;
static constexpr int kToggleCommand = 0;
static constexpr int kSyncCommand = 2;
static constexpr int kOptionsCommand = 4;
static constexpr int kAboutCommand = 5;

static NppData sNppData{};
static FuncItem sFuncItems[kCommandCount]{};
static ShortcutKey sToggleShortcut{true, false, true, 'M'};
static HWND sPreviewHwnd = nullptr;
static WKWebView* sWebView = nil;
static bool sVisible = false;
static bool sRenderDirty = true;

struct MarkdownViewerConfig
{
	bool synchronizeScrolling = false;
	bool includeNewFiles = true;
	std::wstring fileExtensions;
	std::wstring customCss;
	std::wstring iniPath;
};

static MarkdownViewerConfig sConfig;

static NSString* wideToNSString(const std::wstring& value)
{
	return [[NSString alloc] initWithBytes:value.data()
	                                length:value.size() * sizeof(wchar_t)
	                              encoding:NSUTF32LittleEndianStringEncoding] ?: @"";
}

static std::wstring nsStringToWide(NSString* value)
{
	if (!value)
		return L"";
	NSData* data = [value dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
	if (!data || data.length == 0)
		return L"";
	return std::wstring(reinterpret_cast<const wchar_t*>(data.bytes),
	                    data.length / sizeof(wchar_t));
}

static std::string nsStringToUTF8(NSString* value)
{
	return value ? std::string(value.UTF8String ? value.UTF8String : "") : "";
}

static std::string wideToUTF8(const std::wstring& value)
{
	return nsStringToUTF8(wideToNSString(value));
}

static std::wstring getNppString(UINT message)
{
	wchar_t buffer[MAX_PATH] = {};
	::SendMessageW(sNppData._nppHandle, message, MAX_PATH, reinterpret_cast<LPARAM>(buffer));
	return buffer;
}

static std::wstring currentDirectory()
{
	return getNppString(NPPM_GETCURRENTDIRECTORY);
}

static std::wstring currentFileName()
{
	return getNppString(NPPM_GETFILENAME);
}

static HWND currentScintilla()
{
	int which = 0;
	::SendMessageW(sNppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, reinterpret_cast<LPARAM>(&which));
	return which == 0 ? sNppData._scintillaMainHandle : sNppData._scintillaSecondHandle;
}

static std::string activeEditorText()
{
	HWND sci = currentScintilla();
	if (!sci)
		return "";
	LRESULT length = ::SendMessageW(sci, SCI_GETTEXTLENGTH, 0, 0);
	if (length <= 0)
		return "";
	std::vector<char> text(static_cast<size_t>(length) + 1, '\0');
	::SendMessageW(sci, SCI_GETTEXT, static_cast<WPARAM>(text.size()),
	               reinterpret_cast<LPARAM>(text.data()));
	return text.data();
}

static void loadConfig()
{
	wchar_t configDir[MAX_PATH] = {};
	::SendMessageW(sNppData._nppHandle, NPPM_GETPLUGINSCONFIGDIR, MAX_PATH,
	               reinterpret_cast<LPARAM>(configDir));
	sConfig.iniPath = configDir;
	if (!sConfig.iniPath.empty() && sConfig.iniPath.back() != L'/' && sConfig.iniPath.back() != L'\\')
		sConfig.iniPath += L'/';
	sConfig.iniPath += L"MarkdownViewerPlusPlus.ini";

	sConfig.synchronizeScrolling = ::GetPrivateProfileIntW(
		L"MarkdownViewerPlusPlus", L"synchronizeScrolling", 0, sConfig.iniPath.c_str()) != 0;
	sConfig.includeNewFiles = ::GetPrivateProfileIntW(
		L"MarkdownViewerPlusPlus", L"includeNewFiles", 1, sConfig.iniPath.c_str()) != 0;

	wchar_t extensions[32768] = {};
	::GetPrivateProfileStringW(L"MarkdownViewerPlusPlus", L"fileExtensions", L"",
	                           extensions, 32768, sConfig.iniPath.c_str());
	sConfig.fileExtensions = extensions;

	wchar_t css[32768] = {};
	::GetPrivateProfileStringW(L"MarkdownViewerPlusPlus", L"customCss", L"",
	                           css, 32768, sConfig.iniPath.c_str());
	sConfig.customCss = css;
}

static void saveConfig()
{
	if (sConfig.iniPath.empty())
		return;
	::WritePrivateProfileStringW(L"MarkdownViewerPlusPlus", L"synchronizeScrolling",
	                             sConfig.synchronizeScrolling ? L"1" : L"0", sConfig.iniPath.c_str());
	::WritePrivateProfileStringW(L"MarkdownViewerPlusPlus", L"includeNewFiles",
	                             sConfig.includeNewFiles ? L"1" : L"0", sConfig.iniPath.c_str());
	::WritePrivateProfileStringW(L"MarkdownViewerPlusPlus", L"fileExtensions",
	                             sConfig.fileExtensions.c_str(), sConfig.iniPath.c_str());
	::WritePrivateProfileStringW(L"MarkdownViewerPlusPlus", L"customCss",
	                             sConfig.customCss.c_str(), sConfig.iniPath.c_str());
}

static std::string trim(const std::string& value)
{
	size_t start = 0;
	while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start])))
		++start;
	size_t end = value.size();
	while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1])))
		--end;
	return value.substr(start, end - start);
}

static std::string escapeHtml(const std::string& value)
{
	std::string escaped;
	escaped.reserve(value.size());
	for (char ch : value)
	{
		switch (ch)
		{
			case '&': escaped += "&amp;"; break;
			case '<': escaped += "&lt;"; break;
			case '>': escaped += "&gt;"; break;
			case '"': escaped += "&quot;"; break;
			default: escaped += ch; break;
		}
	}
	return escaped;
}

static std::string renderInlineMarkdown(const std::string& value)
{
	std::string rendered = escapeHtml(value);
	rendered = std::regex_replace(rendered, std::regex("!\\[([^\\]]*)\\]\\(([^\\)]+)\\)"),
	                              "<img alt=\"$1\" src=\"$2\" />");
	rendered = std::regex_replace(rendered, std::regex("\\[([^\\]]+)\\]\\(([^\\)]+)\\)"),
	                              "<a href=\"$2\">$1</a>");
	rendered = std::regex_replace(rendered, std::regex("`([^`]+)`"), "<code>$1</code>");
	rendered = std::regex_replace(rendered, std::regex("\\*\\*([^*]+)\\*\\*"), "<strong>$1</strong>");
	rendered = std::regex_replace(rendered, std::regex("\\*([^*]+)\\*"), "<em>$1</em>");
	return rendered;
}

static std::string markdownToHtml(const std::string& markdown)
{
	std::istringstream input(markdown);
	std::ostringstream html;
	std::string line;
	std::string paragraph;
	bool inList = false;
	bool inCode = false;

	auto flushParagraph = [&]() {
		if (!paragraph.empty())
		{
			html << "<p>" << renderInlineMarkdown(paragraph) << "</p>\n";
			paragraph.clear();
		}
	};
	auto closeList = [&]() {
		if (inList)
		{
			html << "</ul>\n";
			inList = false;
		}
	};

	while (std::getline(input, line))
	{
		if (!line.empty() && line.back() == '\r')
			line.pop_back();
		std::string stripped = trim(line);

		if (stripped.rfind("```", 0) == 0)
		{
			flushParagraph();
			closeList();
			if (inCode)
				html << "</code></pre>\n";
			else
				html << "<pre><code>";
			inCode = !inCode;
			continue;
		}

		if (inCode)
		{
			html << escapeHtml(line) << "\n";
			continue;
		}

		if (stripped.empty())
		{
			flushParagraph();
			closeList();
			continue;
		}

		size_t headingLevel = 0;
		while (headingLevel < stripped.size() && headingLevel < 6 && stripped[headingLevel] == '#')
			++headingLevel;
		if (headingLevel > 0 && headingLevel < stripped.size() && stripped[headingLevel] == ' ')
		{
			flushParagraph();
			closeList();
			std::string heading = trim(stripped.substr(headingLevel + 1));
			html << "<h" << headingLevel << ">" << renderInlineMarkdown(heading)
			     << "</h" << headingLevel << ">\n";
			continue;
		}

		if ((stripped.rfind("- ", 0) == 0) || (stripped.rfind("* ", 0) == 0))
		{
			flushParagraph();
			if (!inList)
			{
				html << "<ul>\n";
				inList = true;
			}
			html << "<li>" << renderInlineMarkdown(trim(stripped.substr(2))) << "</li>\n";
			continue;
		}

		closeList();
		if (!paragraph.empty())
			paragraph += " ";
		paragraph += stripped;
	}

	flushParagraph();
	closeList();
	if (inCode)
		html << "</code></pre>\n";
	return html.str();
}

static std::string baseCss()
{
	return R"CSS(
body {
	font: -apple-system-body;
	line-height: 1.5;
	margin: 18px;
	color: #202124;
	background: #ffffff;
}
h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1em 0 0.45em; }
pre {
	background: #f6f8fa;
	border-radius: 6px;
	overflow: auto;
	padding: 12px;
}
code {
	background: #f6f8fa;
	border-radius: 4px;
	font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
	padding: 0.1em 0.3em;
}
pre code { padding: 0; }
img { max-width: 100%; }
a { color: #0969da; }
blockquote {
	border-left: 4px solid #d0d7de;
	color: #57606a;
	margin-left: 0;
	padding-left: 12px;
}
@media (prefers-color-scheme: dark) {
	body { color: #d4d4d4; background: #1e1e1e; }
	pre, code { background: #2d2d2d; }
	a { color: #6cb6ff; }
	blockquote { border-left-color: #555; color: #aaa; }
}
)CSS";
}

static std::string buildHtmlDocument(const std::string& body, const std::wstring& title)
{
	std::string css = baseCss();
	std::string customCss = wideToUTF8(sConfig.customCss);
	std::smatch match;
	std::regex importPattern("(@import\\s+[^;]+;)");
	std::string imports;
	std::string remainingCss = customCss;
	while (std::regex_search(remainingCss, match, importPattern))
	{
		imports += match.str(1);
		imports += "\n";
		remainingCss = match.prefix().str() + match.suffix().str();
	}

	std::ostringstream html;
	html << "<!doctype html>\n<html><head><meta charset=\"UTF-8\" />\n";
	html << "<meta name=\"author\" content=\"MarkdownViewer++\" />\n";
	html << "<title>" << escapeHtml(wideToUTF8(title)) << "</title>\n";
	html << "<style>\n" << imports << css << "\n" << remainingCss << "\n</style>\n";
	html << "</head><body>\n" << body << "\n</body></html>\n";
	return html.str();
}

static std::wstring extensionOf(const std::wstring& fileName)
{
	size_t slash = fileName.find_last_of(L"/\\");
	size_t dot = fileName.find_last_of(L'.');
	if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash) || dot + 1 >= fileName.size())
		return L"";
	std::wstring ext = fileName.substr(dot + 1);
	std::transform(ext.begin(), ext.end(), ext.begin(), towlower);
	return ext;
}

static bool extensionAllowed(const std::wstring& fileName)
{
	std::wstring ext = extensionOf(fileName);
	if (sConfig.fileExtensions.empty())
		return true;
	if (ext.empty())
		return sConfig.includeNewFiles && (fileName.empty() || fileName.rfind(L"new ", 0) == 0);

	std::wstring configured = sConfig.fileExtensions;
	std::transform(configured.begin(), configured.end(), configured.begin(), towlower);
	std::wistringstream parts(configured);
	std::wstring part;
	while (std::getline(parts, part, L','))
	{
		part.erase(part.begin(), std::find_if(part.begin(), part.end(), [](wchar_t ch) {
			return !iswspace(ch) && ch != L'.';
		}));
		part.erase(std::find_if(part.rbegin(), part.rend(), [](wchar_t ch) {
			return !iswspace(ch);
		}).base(), part.end());
		if (part == ext)
			return true;
	}
	return false;
}

static void loadHtml(const std::string& html, const std::wstring& directory)
{
	if (!sWebView)
		return;
	NSString* htmlString = [NSString stringWithUTF8String:html.c_str()];
	NSURL* baseURL = nil;
	if (!directory.empty())
		baseURL = [NSURL fileURLWithPath:wideToNSString(directory) isDirectory:YES];
	[sWebView loadHTMLString:htmlString ?: @"" baseURL:baseURL];
}

static void scrollPreviewByRatio(double ratio)
{
	if (!sWebView)
		return;
	if (ratio < 0.0) ratio = 0.0;
	if (ratio > 1.0) ratio = 1.0;
	NSString* js = [NSString stringWithFormat:
		@"window.scrollTo(0, Math.max(0, "
		 "((document.documentElement.scrollHeight || document.body.scrollHeight) - window.innerHeight) * %.12f));",
		ratio];
	[sWebView evaluateJavaScript:js completionHandler:nil];
}

static void updateScrollPosition()
{
	if (!sConfig.synchronizeScrolling || !sVisible)
		return;
	HWND sci = currentScintilla();
	if (!sci)
		return;
	double firstVisible = static_cast<double>(::SendMessageW(sci, SCI_GETFIRSTVISIBLELINE, 0, 0));
	double linesOnScreen = static_cast<double>(::SendMessageW(sci, SCI_LINESONSCREEN, 0, 0));
	double lineCount = static_cast<double>(::SendMessageW(sci, SCI_GETLINECOUNT, 0, 0));
	double denominator = std::max<double>(1.0, lineCount - linesOnScreen);
	scrollPreviewByRatio(firstVisible / denominator);
}

static void renderPreview(bool force)
{
	if (!sVisible || !sWebView)
		return;
	if (!force && !sRenderDirty)
		return;

	std::wstring fileName = currentFileName();
	std::wstring directory = currentDirectory();
	if (!extensionAllowed(fileName))
	{
		std::ostringstream message;
		message << "<p>Your configuration settings do not include the currently selected file extension.<br />"
		        << "The rendered file extensions are <b>'" << escapeHtml(wideToUTF8(sConfig.fileExtensions)) << "'</b>.<br />"
		        << "The current file is <i>'" << escapeHtml(wideToUTF8(fileName)) << "'</i>.</p>";
		loadHtml(buildHtmlDocument(message.str(), fileName), directory);
		sRenderDirty = false;
		return;
	}

	std::string html = markdownToHtml(activeEditorText());
	loadHtml(buildHtmlDocument(html, fileName.empty() ? L"MarkdownViewer++" : fileName), directory);
	sRenderDirty = false;
}

static bool ensurePreview()
{
	if (sPreviewHwnd && sWebView)
		return true;
	sPreviewHwnd = ::CreateWindowExW(0, L"MarkdownViewerPlusPlusPreview", L"",
	                                WS_CHILD | WS_VISIBLE, 0, 0, 320, 480,
	                                sNppData._nppHandle, nullptr, nullptr, nullptr);
	if (!sPreviewHwnd)
		return false;

	auto* info = HandleRegistry::getWindowInfo(sPreviewHwnd);
	if (!info || !info->nativeView)
		return false;
	NSView* container = (__bridge NSView*)info->nativeView;
	container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
	sWebView = [[WKWebView alloc] initWithFrame:container.bounds configuration:configuration];
	sWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	[container addSubview:sWebView];

	tTbData data{};
	data.hClient = sPreviewHwnd;
	data.pszName = L"MarkdownViewer++";
	data.dlgID = kToggleCommand;
	data.uMask = DWS_DF_CONT_RIGHT;
	data.pszModuleName = L"MarkdownViewerPlusPlus";
	::SendMessageW(sNppData._nppHandle, NPPM_DMMREGASDCKDLG, 0, reinterpret_cast<LPARAM>(&data));
	::SendMessageW(sNppData._nppHandle, NPPM_DMMHIDE, 0, reinterpret_cast<LPARAM>(sPreviewHwnd));
	return true;
}

static void focusEditor()
{
	HWND sci = currentScintilla();
	if (!sci)
		return;
	::SetFocus(sci);
	::SendMessageW(sci, SCI_SETFOCUS, TRUE, 0);
}

static void setMenuCheck(int index, bool checked)
{
	if (sFuncItems[index]._cmdID)
		::SendMessageW(sNppData._nppHandle, NPPM_SETMENUITEMCHECK,
		               static_cast<WPARAM>(sFuncItems[index]._cmdID), checked ? TRUE : FALSE);
}

static void togglePreview()
{
	if (!ensurePreview())
		return;
	sVisible = !sVisible;
	if (sVisible)
	{
		::SendMessageW(sNppData._nppHandle, NPPM_DMMSHOW, 0, reinterpret_cast<LPARAM>(sPreviewHwnd));
		setMenuCheck(kToggleCommand, true);
		sRenderDirty = true;
		renderPreview(true);
		updateScrollPosition();
		focusEditor();
	}
	else
	{
		::SendMessageW(sNppData._nppHandle, NPPM_DMMHIDE, 0, reinterpret_cast<LPARAM>(sPreviewHwnd));
		setMenuCheck(kToggleCommand, false);
	}
}

static void toggleSynchronizedScrolling()
{
	sConfig.synchronizeScrolling = !sConfig.synchronizeScrolling;
	sFuncItems[kSyncCommand]._init2Check = sConfig.synchronizeScrolling;
	setMenuCheck(kSyncCommand, sConfig.synchronizeScrolling);
	saveConfig();
	updateScrollPosition();
}

static NSTextField* label(NSString* title, NSRect frame)
{
	NSTextField* field = [NSTextField labelWithString:title];
	field.frame = frame;
	return field;
}

static void showOptions()
{
	@autoreleasepool {
		NSAlert* alert = [[NSAlert alloc] init];
		alert.messageText = @"MarkdownViewer++ Options";
		alert.informativeText = @"Configure the macOS MarkdownViewer++ preview.";
		[alert addButtonWithTitle:@"OK"];
		[alert addButtonWithTitle:@"Cancel"];

		NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 300)];
		[accessory addSubview:label(@"Rendered file extensions (comma-separated, empty renders all):",
		                            NSMakeRect(0, 270, 520, 20))];

		NSTextField* extensions = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 242, 520, 24)];
		extensions.stringValue = wideToNSString(sConfig.fileExtensions);
		[accessory addSubview:extensions];

		NSButton* includeNewFiles = [[NSButton alloc] initWithFrame:NSMakeRect(0, 210, 260, 24)];
		[includeNewFiles setButtonType:NSButtonTypeSwitch];
		includeNewFiles.title = @"Include untitled/new files";
		includeNewFiles.state = sConfig.includeNewFiles ? NSControlStateValueOn : NSControlStateValueOff;
		[accessory addSubview:includeNewFiles];

		NSButton* syncScrolling = [[NSButton alloc] initWithFrame:NSMakeRect(270, 210, 250, 24)];
		[syncScrolling setButtonType:NSButtonTypeSwitch];
		syncScrolling.title = @"Synchronize scrolling";
		syncScrolling.state = sConfig.synchronizeScrolling ? NSControlStateValueOn : NSControlStateValueOff;
		[accessory addSubview:syncScrolling];

		[accessory addSubview:label(@"Custom CSS:", NSMakeRect(0, 184, 520, 20))];
		NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 520, 180)];
		scrollView.hasVerticalScroller = YES;
		scrollView.borderType = NSBezelBorder;
		NSTextView* cssView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 180)];
		cssView.string = wideToNSString(sConfig.customCss);
		scrollView.documentView = cssView;
		[accessory addSubview:scrollView];

		alert.accessoryView = accessory;
		NSModalResponse response = [alert runModal];
		if (response != NSAlertFirstButtonReturn)
			return;

		sConfig.fileExtensions = nsStringToWide(extensions.stringValue);
		sConfig.includeNewFiles = includeNewFiles.state == NSControlStateValueOn;
		sConfig.synchronizeScrolling = syncScrolling.state == NSControlStateValueOn;
		sConfig.customCss = nsStringToWide(cssView.string);
		sFuncItems[kSyncCommand]._init2Check = sConfig.synchronizeScrolling;
		setMenuCheck(kSyncCommand, sConfig.synchronizeScrolling);
		saveConfig();
		sRenderDirty = true;
		renderPreview(true);
	}
}

static void showAbout()
{
	@autoreleasepool {
		NSAlert* alert = [[NSAlert alloc] init];
		alert.messageText = @"MarkdownViewer++";
		alert.informativeText =
			@"Native PaperWasp macOS port inspired by nea/MarkdownViewerPlusPlus.\n\n"
			@"The upstream plugin is MIT licensed and implemented for Notepad++ as a .NET/WinForms plugin. "
			@"This macOS port preserves the plugin menu and live preview workflow with a native WKWebView renderer.";
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
	}
}

static void initializeFuncItems()
{
	for (auto& item : sFuncItems)
		item = FuncItem{};

	wcscpy(sFuncItems[kToggleCommand]._itemName, L"MarkdownViewer++");
	sFuncItems[kToggleCommand]._pFunc = togglePreview;
	sFuncItems[kToggleCommand]._pShKey = &sToggleShortcut;

	wcscpy(sFuncItems[1]._itemName, L"---");

	wcscpy(sFuncItems[kSyncCommand]._itemName, L"Synchronize scrolling (Editor -> Viewer)");
	sFuncItems[kSyncCommand]._pFunc = toggleSynchronizedScrolling;
	sFuncItems[kSyncCommand]._init2Check = sConfig.synchronizeScrolling;

	wcscpy(sFuncItems[3]._itemName, L"---");

	wcscpy(sFuncItems[kOptionsCommand]._itemName, L"Options");
	sFuncItems[kOptionsCommand]._pFunc = showOptions;

	wcscpy(sFuncItems[kAboutCommand]._itemName, L"About");
	sFuncItems[kAboutCommand]._pFunc = showAbout;
}

extern "C" BOOL APIENTRY DllMain(HINSTANCE, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_DETACH)
	{
		saveConfig();
		if (sPreviewHwnd)
		{
			::DestroyWindow(sPreviewHwnd);
			sPreviewHwnd = nullptr;
			sWebView = nil;
		}
	}
	return TRUE;
}

extern "C" __declspec(dllexport) void setInfo(NppData data)
{
	sNppData = data;
	loadConfig();
	initializeFuncItems();
	ensurePreview();
}

extern "C" __declspec(dllexport) const wchar_t* getName()
{
	return L"MarkdownViewer++";
}

extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* nbItems)
{
	if (nbItems)
		*nbItems = kCommandCount;
	return sFuncItems;
}

extern "C" __declspec(dllexport) void beNotified(SCNotification* notification)
{
	if (!notification)
		return;

	switch (notification->nmhdr.code)
	{
		case NPPN_READY:
			sRenderDirty = true;
			renderPreview(true);
			break;
		case NPPN_BUFFERACTIVATED:
			sRenderDirty = true;
			renderPreview(true);
			updateScrollPosition();
			break;
		case SCN_MODIFIED:
			if (notification->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))
				sRenderDirty = true;
			break;
		case SCN_UPDATEUI:
			renderPreview(false);
			if (notification->updated & SC_UPDATE_V_SCROLL)
				updateScrollPosition();
			break;
		case NPPN_SHUTDOWN:
			saveConfig();
			break;
		default:
			break;
	}
}

extern "C" __declspec(dllexport) LRESULT messageProc(UINT, WPARAM, LPARAM)
{
	return TRUE;
}

extern "C" __declspec(dllexport) BOOL isUnicode()
{
	return TRUE;
}

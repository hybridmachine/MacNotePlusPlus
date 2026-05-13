#pragma once
// Settings Manager for PaperWasp
// Reads/writes settings to ~/Library/Application Support/PaperWasp/settings.json.

#include <string>
#include <vector>

struct AppSettings
{
	// Window geometry
	double windowX = 100;
	double windowY = 100;
	double windowWidth = 1000;
	double windowHeight = 750;

	// Editor preferences
	std::string fontName = "Menlo";
	int fontSize = 13;
	int tabWidth = 4;

	// Default assembly dialect for .asm files. Values: "x86" or "65c02".
	// .a65/.s65 are always treated as 65C02 regardless of this setting.
	std::string asmDefault = "x86";

	// View state
	bool wordWrap = false;
	bool showLineNumbers = true;
	bool showCaretLine = true;
	bool autoIndent = true;
	bool autoCloseBrackets = true;
	bool useTabs = false;
	bool showWhitespace = false;
	bool showEol = false;
	bool showIndentGuides = false;
	bool syncScrolling = false;
	bool documentMap = false;
	bool functionList = false;
	bool clipboardHistory = false;
	bool showChangeHistory = true;
	int documentMapWidth = 140;
	bool fileBrowser = false;
	bool fileSwitcher = false;
	int leftPanelWidth = 200;
	double fileBrowserHeightRatio = 0.6;
	std::string fileBrowserRootPath;
	int rightPanelWidth = 220;
	double functionListHeightRatio = 0.5;

	// Recent files
	std::vector<std::string> recentFiles;
};

class SettingsManager
{
public:
	static SettingsManager& instance();

	// Load settings from ~/Library/Application Support/PaperWasp/settings.json
	// Returns true if file was found and parsed successfully.
	bool load();

	// Save current settings to ~/Library/Application Support/PaperWasp/settings.json
	bool save();

	AppSettings settings;

private:
	SettingsManager() = default;
	std::string settingsDir() const;
	std::string settingsPath() const;
};

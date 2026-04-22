// Lookup table for hand-translated Win32 dialog templates.

#ifdef __APPLE__

#include "dialog_template.h"

#include <unordered_map>

namespace {

std::unordered_map<int, DialogTemplateCpp>& registry()
{
	static std::unordered_map<int, DialogTemplateCpp> inst;
	return inst;
}

} // namespace

void registerDialogTemplate(const DialogTemplateCpp& t)
{
	registry()[t.id] = t;
}

const DialogTemplateCpp* findDialogTemplate(int dialogID)
{
	auto it = registry().find(dialogID);
	return (it == registry().end()) ? nullptr : &it->second;
}

#endif // __APPLE__

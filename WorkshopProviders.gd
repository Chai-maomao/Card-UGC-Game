class_name WorkshopProviders
extends RefCounted

# A Steam integration registers its factory at startup. No SDK or App ID is
# fabricated in non-Steam builds, and the UI never shows a nonfunctional tab.
static var platform_script: Script

static func create() -> WorkshopBackend:
	if platform_script != null:
		var backend = platform_script.new()
		if backend is WorkshopBackend: return backend
	return WorkshopClient.new()

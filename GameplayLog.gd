class_name GameplayLog
extends RefCounted

const SETTING := "debug/gameplay_verbose_logging"


static func is_enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, false))


static func write(message: Variant) -> void:
	if is_enabled():
		print(message)

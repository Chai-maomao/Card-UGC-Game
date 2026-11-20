class_name TutorialProgress
extends RefCounted

const DEFAULT_PATH := "user://tutorial_progress.cfg"

var path: String


func _init(storage_path: String = DEFAULT_PATH) -> void:
	path = storage_path


func status() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return "never"
	var value := str(cfg.get_value("tutorial", "status", "never"))
	return value if value in ["never", "in_progress", "completed", "skipped"] else "never"


func initialize_startup(has_existing_library: bool) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK and bool(cfg.get_value("startup", "initialized", false)):
		return OK
	# An existing library predates this introduction. Do not force returning
	# players through it, or replace their completed/skipped tutorial progress.
	var finished := str(cfg.get_value("tutorial", "status", "never")) in ["completed", "skipped"]
	var required := not has_existing_library and not finished
	cfg.set_value("startup", "initialized", true)
	cfg.set_value("startup", "required", required)
	cfg.set_value("tutorial", "schema", 3)
	if required:
		cfg.set_value("tutorial", "status", "in_progress")
	return cfg.save(path)


func needs_startup_tutorial() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(path) == OK and bool(cfg.get_value("startup", "required", false)) and not is_finished()


func is_finished() -> bool:
	return status() in ["completed", "skipped"]


func editor_completed() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value("tutorial", "editor_completed", false))


func mark_editor_completed() -> int:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("tutorial", "schema", 3)
	cfg.set_value("tutorial", "editor_completed", true)
	cfg.set_value("tutorial", "updated_at", Time.get_unix_time_from_system())
	return cfg.save(path)


func mark_completed() -> int:
	return _save("completed")


func mark_skipped() -> int:
	return _save("skipped")


func clear() -> int:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _save(value: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("tutorial", "schema", 3)
	cfg.set_value("tutorial", "status", value)
	cfg.set_value("tutorial", "updated_at", Time.get_unix_time_from_system())
	return cfg.save(path)

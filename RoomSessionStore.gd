class_name RoomSessionStore
extends RefCounted

var path: String


func _init(storage_path: String) -> void:
	path = storage_path


func save(data: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("room", str(key), data[key])
	return cfg.save(path) == OK


func load() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	return {
		"mode": str(cfg.get_value("room", "mode", "room")),
		"address": str(cfg.get_value("room", "address", "")),
		"port": int(cfg.get_value("room", "port", 0)),
		"code": str(cfg.get_value("room", "code", "")),
		"player": int(cfg.get_value("room", "player", 0)),
		"token": str(cfg.get_value("room", "token", "")),
		"card_art": bool(cfg.get_value("room", "card_art", false)),
		"match_started": bool(cfg.get_value("room", "match_started", false)),
		"session_id": str(cfg.get_value("room", "session_id", "")),
	}


func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

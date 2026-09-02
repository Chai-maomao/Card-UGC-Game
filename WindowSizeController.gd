extends Node

const WINDOW_PRESETS: Array[Vector2i] = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const LEGACY_WINDOW_PRESETS: Array[Vector2i] = [
	Vector2i(1152, 648), Vector2i(1600, 900), Vector2i(1920, 1080),
]
const DEFAULT_PRESET_INDEX := 1
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	get_window().unresizable = false
	_load_resolution.call_deferred()


func get_current_preset_index() -> int:
	var current_size: Vector2i = DisplayServer.window_get_size()
	for index in WINDOW_PRESETS.size():
		if WINDOW_PRESETS[index] == current_size:
			return index
	return DEFAULT_PRESET_INDEX


func apply_preset(index: int) -> void:
	if index < 0 or index >= WINDOW_PRESETS.size():
		return
	DisplayServer.window_set_size(WINDOW_PRESETS[index])
	_save_resolution(index)


func preset_label(index: int) -> String:
	if index < 0 or index >= WINDOW_PRESETS.size():
		return ""
	var size: Vector2i = WINDOW_PRESETS[index]
	return "%d x %d" % [size.x, size.y]


func _load_resolution() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var saved_size := Vector2i(
		int(config.get_value("display", "resolution_width", 0)),
		int(config.get_value("display", "resolution_height", 0))
	)
	if saved_size in WINDOW_PRESETS:
		DisplayServer.window_set_size(saved_size)
		return
	# Versions before responsive-window support persisted only an array index.
	# Decode that index against the old array so adding presets cannot silently
	# change a player's selected resolution.
	var legacy_index: int = int(config.get_value("display", "resolution_preset", -1))
	if legacy_index >= 0 and legacy_index < LEGACY_WINDOW_PRESETS.size():
		DisplayServer.window_set_size(LEGACY_WINDOW_PRESETS[legacy_index])


func _save_resolution(index: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "resolution_preset", index)
	config.set_value("display", "resolution_width", WINDOW_PRESETS[index].x)
	config.set_value("display", "resolution_height", WINDOW_PRESETS[index].y)
	config.save(SETTINGS_PATH)

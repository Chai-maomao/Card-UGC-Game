extends Node

const WINDOW_PRESETS: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	get_window().unresizable = true
	_load_resolution.call_deferred()


func get_current_preset_index() -> int:
	var current_size: Vector2i = DisplayServer.window_get_size()
	for index in WINDOW_PRESETS.size():
		if WINDOW_PRESETS[index] == current_size:
			return index
	return 0


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
	var index: int = int(config.get_value("display", "resolution_preset", 0))
	if index >= 0 and index < WINDOW_PRESETS.size():
		DisplayServer.window_set_size(WINDOW_PRESETS[index])


func _save_resolution(index: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "resolution_preset", index)
	config.save(SETTINGS_PATH)


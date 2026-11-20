extends Node

signal changed(key: String)
const PATH := "user://settings.cfg"
const DEFAULTS := {"window_mode":0,"fullscreen":true,"vsync":true,"fps":120,"quality":1,"master":0.8,"bgm":0.45,"sfx":0.8,"ui":0.6,"mute":false,"reduced_motion":false,"camera_shake":true,"text_size":0,"high_contrast":false,"title_card_ids":[]}
var values: Dictionary = {}
var _background_visual_test := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_background_visual_test = OS.get_cmdline_user_args().has("--background-visual-test")
	if _background_visual_test and DisplayServer.get_name() != "headless":
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var config := ConfigFile.new()
	config.load(PATH)
	for key in DEFAULTS: values[key] = _validated(key,config.get_value("presentation",key,_default_value(key)))
	values["fullscreen"] = values["window_mode"] == 0
	_load_keys(config)
	apply_display.call_deferred()

func _validated(key: String, value: Variant) -> Variant:
	if key == "title_card_ids":
		var ids: Array[String] = []
		if value is Array:
			for id in value:
				if id is String and not id.is_empty() and not ids.has(id): ids.append(id)
				if ids.size() == 5: break
		return ids
	if key == "window_mode": return clampi(int(value),0,2)
	if key in ["master","bgm","sfx","ui"]: return clampf(float(value),0,1)
	if key == "text_size": return clampi(int(value),0,2)
	if key == "quality": return clampi(int(value),0,2)
	if key == "fps": return int(value) if int(value) in [0,30,60,120,144] else 120
	return bool(value)

func get_value(key: String) -> Variant:
	return values.get(key,_default_value(key))

func _default_value(key: String) -> Variant:
	if key == "fps" and OS.has_feature("android"):
		return 60
	return DEFAULTS.get(key)

func set_value(key: String, value: Variant) -> void:
	if key == "fullscreen":
		set_value("window_mode",0 if bool(value) else 1)
		return
	if not DEFAULTS.has(key): return
	values[key] = _validated(key,value)
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("presentation",key,values[key])
	if key == "window_mode":
		values["fullscreen"] = values[key] == 0
		config.set_value("presentation","fullscreen",values["fullscreen"])
	config.save(PATH)
	if key in ["window_mode","vsync","fps"]: apply_display()
	changed.emit(key)

func reset() -> void:
	for key in DEFAULTS: set_value(key,_default_value(key))
	for action in KEY_DEFAULTS: _apply_key(action,KEY_DEFAULTS[action])
	var config := ConfigFile.new()
	config.load(PATH)
	if config.has_section("keys"): config.erase_section("keys")
	config.save(PATH)

func apply_display() -> void:
	if DisplayServer.get_name() == "headless": return
	if not OS.has_feature("android"):
		var mode := 1 if _background_visual_test else int(get_value("window_mode"))
		var window := get_window()
		window.borderless = mode == 2
		window.mode = [Window.MODE_EXCLUSIVE_FULLSCREEN,Window.MODE_WINDOWED,Window.MODE_FULLSCREEN][mode]
		if mode == 1: WindowSizeController.restore_window_size()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("fps"))


const KEY_DEFAULTS := {"ui_accept":KEY_ENTER,"ui_cancel":KEY_ESCAPE,"ui_focus_next":KEY_TAB}
var bindings: Dictionary = {}

func _load_keys(config: ConfigFile) -> void:
	for action in KEY_DEFAULTS:
		var code := int(config.get_value("keys",action,KEY_DEFAULTS[action]))
		if code <= 0: code = KEY_DEFAULTS[action]
		_apply_key(action,code)

func _apply_key(action: String, code: int) -> void:
	bindings[action] = code
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.keycode = code
	InputMap.action_add_event(action,event)
	if action == "ui_focus_next":
		InputMap.action_erase_events("ui_focus_prev")
		var previous := InputEventKey.new()
		previous.keycode = code
		previous.shift_pressed = true
		InputMap.action_add_event("ui_focus_prev",previous)
	if action == "ui_accept":
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		InputMap.action_add_event(action,space)

func bind_key(action: String, code: int) -> bool:
	if not KEY_DEFAULTS.has(action) or code <= 0: return false
	if action != "ui_accept" and code == KEY_SPACE: return false
	for other in bindings:
		if other != action and int(bindings[other]) == code: return false
	_apply_key(action,code)
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("keys",action,code)
	config.save(PATH)
	return true

func reset_bindings() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	for action in KEY_DEFAULTS:
		_apply_key(action,KEY_DEFAULTS[action])
		config.set_value("keys",action,KEY_DEFAULTS[action])
	config.save(PATH)

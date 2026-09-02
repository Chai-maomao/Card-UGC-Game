extends Node

var failures: Array[String] = []


func _ready() -> void:
	var app_icon_path := str(ProjectSettings.get_setting("application/config/icon", ""))
	_assert(app_icon_path == "res://res/ui/icons/cardex_app_icon.png" and ResourceLoader.exists(app_icon_path),
			"project window icon must point to the shipped CARDEX PNG")
	var export_source := _read("res://export_presets.cfg")
	_assert("application/icon=\"res://res/ui/icons/cardex_app_icon.ico\"" in export_source,
			"Windows export must embed the multi-resolution CARDEX ICO")
	_assert(_line_count("res://Main.gd") <= 2000, "Main.gd must remain a thin scene controller")
	for path in [
		"res://BattleMainFoundation.gd",
		"res://BattleMainActions.gd",
		"res://BattleMainPresentation.gd",
		"res://BattleMainNetwork.gd",
	]:
		_assert(_line_count(path) <= 1600, "%s became a replacement giant controller" % path)
	_assert(not FileAccess.file_exists("res://BattleMain3DAdapter.gd"), "retired 3D battle adapter returned to the active project")
	var main_scene_source := _read("res://Main.tscn")
	_assert(not "Node3D" in main_scene_source and not "BattleStage3D" in main_scene_source,
			"Main.tscn must remain a pure 2D battlefield")
	var state_source := _read("res://GameState.gd")
	_assert(state_source.begins_with("extends RefCounted"), "core GameState must stay UI-free")
	_assert(not "Control" in state_source and not "CanvasLayer" in state_source, "core GameState gained UI dependencies")
	_assert(not "Node3D" in state_source and not "Camera3D" in state_source, "core GameState gained 3D presentation dependencies")
	if failures.is_empty():
		print("TEST_MAIN_ARCHITECTURE_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_MAIN_ARCHITECTURE_FAILED: %s" % failure)
		get_tree().quit(1)


func _line_count(path: String) -> int:
	return _read(path).count("\n") + 1


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

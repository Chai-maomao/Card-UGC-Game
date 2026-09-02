extends Node
# ============================================
# UIMotion — autoload. Global scene-transition overlay and shared motion
# entry point. Every scene change fades the screen to black and the next
# scene fades in automatically via SceneTree.scene_changed, so all menus
# and the battlefield share one consistent transition.
# ============================================

const OVERLAY_COLOR := Color(0.02, 0.025, 0.045)
const FADE_OUT_TIME := 0.16
const FADE_IN_TIME := 0.22

var _layer: CanvasLayer
var _overlay: ColorRect
var _busy: bool = false
var _startup := true
var _scene_history: Array[Dictionary] = []
var _pending_restore_state := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.name = "UIMotionLayer"
	_layer.layer = 1000
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.color = OVERLAY_COLOR
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_overlay)
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)
	# Startup: reveal the very first scene from black.
	_overlay.color = Color(OVERLAY_COLOR, 1.0)
	fade_in()


# Fade out -> change scene. Ordinary forward navigation records the current
# menu so a Back button can always return to the actual previous level.
func change_scene(path: String, return_state: String = "") -> void:
	if _busy:
		return
	var current_path := _current_scene_path()
	if not current_path.is_empty() and current_path != path:
		_scene_history.append({"path": current_path, "state": return_state})
	_pending_restore_state = ""
	_transition_to(path)


# Return to the most recently recorded scene without recording the scene that
# is being left. `fallback` keeps directly-launched/test scenes deterministic.
func go_back(fallback: String = "res://MainMenu.tscn") -> void:
	go_back_levels(1, fallback)


func go_back_levels(levels: int, fallback: String = "res://MainMenu.tscn") -> void:
	if _busy:
		return
	var destination := fallback
	_pending_restore_state = ""
	for _index in range(maxi(1, levels)):
		if _scene_history.is_empty():
			break
		var entry: Dictionary = _scene_history.pop_back()
		destination = str(entry.get("path", fallback))
		_pending_restore_state = str(entry.get("state", ""))
	_transition_to(destination)


# Use for terminal routes such as returning to the title after a finished
# battle. They must not create a fake "previous menu" entry.
func replace_scene(path: String, clear_history_first: bool = false, restore_state: String = "") -> void:
	if _busy:
		return
	if clear_history_first:
		_scene_history.clear()
	_pending_restore_state = restore_state
	_transition_to(path)


func clear_history() -> void:
	_scene_history.clear()
	_pending_restore_state = ""


func history_depth() -> int:
	return _scene_history.size()


func consume_restore_state() -> String:
	var value := _pending_restore_state
	_pending_restore_state = ""
	return value


func _current_scene_path() -> String:
	var current := get_tree().current_scene
	if current == null:
		return ""
	return current.scene_file_path


func _transition_to(path: String) -> void:
	_busy = true
	_startup = false
	if _overlay == null:
		get_tree().change_scene_to_file(path)
		_busy = false
		return
	var twn := create_tween()
	twn.tween_property(_overlay, "color:a", 1.0, FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await twn.finished
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(path)


func _on_scene_changed() -> void:
	_busy = false
	if _overlay == null:
		return
	if _startup:
		# The startup fade_in in _ready is still revealing the first scene;
		# don't snap the overlay back to opaque and fade again.
		_startup = false
		return
	_overlay.color = Color(OVERLAY_COLOR, 1.0)
	fade_in()


func fade_in() -> void:
	if _overlay == null:
		return
	var twn := create_tween()
	twn.tween_property(_overlay, "color:a", 0.0, FADE_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

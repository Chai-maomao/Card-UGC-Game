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


# Fade out -> change scene. The scene_changed hook fades the new scene back in.
func change_scene(path: String) -> void:
	if _busy:
		return
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

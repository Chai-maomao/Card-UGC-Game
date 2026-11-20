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
const GAME_CURSOR = preload("res://res/ui/cardex_cursor.png")
const GAME_CURSOR_PRESSED = preload("res://res/ui/cardex_cursor_pressed.png")
const GAME_CURSOR_HOTSPOT := Vector2(5, 4)
const CURSOR_PRESS_TIME := 0.075

var _layer: CanvasLayer
var _overlay: ColorRect
var _fade_in_tween: Tween
var _busy: bool = false
var _startup := true
var _scene_history: Array[Dictionary] = []
var _pending_restore_state := ""
var _rollback_history: Array[Dictionary] = []
var _transition_generation := 0
var last_navigation_error := ""
var _popup_stack: Array[Dictionary] = []
var key_capture: Callable
var keyboard_navigation := false
signal navigation_failed(path: String)
signal navigation_input_changed
var unavailable_feedback: Node
var _cursor_press_timer: Timer
var _left_mouse_down := false
var _cursor_press_visible := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		_set_game_cursor(GAME_CURSOR)
		_cursor_press_timer = Timer.new()
		_cursor_press_timer.one_shot = true
		_cursor_press_timer.timeout.connect(_restore_released_cursor)
		add_child(_cursor_press_timer)
		get_window().focus_exited.connect(_reset_cursor_press)
	ThemeDB.fallback_font = UITheme.regular_font()
	get_tree().node_added.connect(_on_ui_node_added)
	unavailable_feedback = preload("res://UIRejectFeedback.gd").new()
	unavailable_feedback.name = "UnavailableFeedback"
	add_child(unavailable_feedback)
	var hints := preload("res://UIHoverHints.gd").new()
	hints.name = "HoverHints"
	add_child(hints)
	_layer = CanvasLayer.new()
	_layer.name = "UIMotionLayer"
	_layer.layer = 1200
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


func _set_game_cursor(texture: Texture2D) -> void:
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, GAME_CURSOR_HOTSPOT)
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_POINTING_HAND, GAME_CURSOR_HOTSPOT)


func _update_cursor_press(event: InputEventMouseButton) -> void:
	if _cursor_press_timer == null or event.button_index != MOUSE_BUTTON_LEFT or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	_left_mouse_down = event.pressed
	if _left_mouse_down:
		_cursor_press_timer.start(CURSOR_PRESS_TIME)
		if not _cursor_press_visible:
			_cursor_press_visible = true
			_set_game_cursor(GAME_CURSOR_PRESSED)
	elif _cursor_press_timer.is_stopped():
		_restore_released_cursor()


func _restore_released_cursor() -> void:
	if _cursor_press_visible and not _left_mouse_down:
		_cursor_press_visible = false
		_set_game_cursor(GAME_CURSOR)


func _reset_cursor_press() -> void:
	_left_mouse_down = false
	_cursor_press_timer.stop()
	_restore_released_cursor()


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	UITheme.clear_popup_surfaces()


func _on_ui_node_added(node: Node) -> void:
	if node is Label or node is Button:
		preload("res://presentation/KeywordTextOverlay.gd").watch(node)
	if node is BaseButton and unavailable_feedback != null:
		unavailable_feedback.watch_button(node)
	if node is CanvasLayer and node.layer >= 40 and node.layer < 1000:
		register_popup(node)
	if node is Window:
		if not node.about_to_popup.is_connected(register_popup.bind(node)):
			node.about_to_popup.connect(register_popup.bind(node))
	# Includes internal OptionButton/LineEdit menus and dynamically-created
	# right-click/left-click menus, without replacing the block colours.
	if node is PopupMenu:
		UITheme.apply_popup_menu(node)
		get_node("HoverHints").watch_menu(node)
		if not node.about_to_popup.is_connected(UITheme.apply_popup_menu.bind(node)):
			node.about_to_popup.connect(UITheme.apply_popup_menu.bind(node))


# Fade out -> change scene. Ordinary forward navigation records the current
# menu so a Back button can always return to the actual previous level.
func change_scene(path: String, return_state: String = "") -> void:
	if _busy:
		return
	var previous: Array[Dictionary] = _scene_history.duplicate(true)
	var current_path := _current_scene_path()
	if not current_path.is_empty() and current_path != path:
		_scene_history.append({"path": current_path, "state": return_state})
	_pending_restore_state = ""
	_transition_to(path,previous)


# Return to the most recently recorded scene without recording the scene that
# is being left. `fallback` keeps directly-launched/test scenes deterministic.
func go_back(fallback: String = "res://MainMenu.tscn") -> void:
	go_back_levels(1, fallback)


func go_back_levels(levels: int, fallback: String = "res://MainMenu.tscn") -> void:
	if _busy:
		return
	var previous: Array[Dictionary] = _scene_history.duplicate(true)
	var destination := fallback
	_pending_restore_state = ""
	for _index in range(maxi(1, levels)):
		if _scene_history.is_empty():
			break
		var entry: Dictionary = _scene_history.pop_back()
		destination = str(entry.get("path", fallback))
		_pending_restore_state = str(entry.get("state", ""))
	_transition_to(destination,previous)


# Use for terminal routes such as returning to the title after a finished
# battle. They must not create a fake "previous menu" entry.
func replace_scene(path: String, clear_history_first: bool = false, restore_state: String = "") -> void:
	if _busy:
		return
	var previous: Array[Dictionary] = _scene_history.duplicate(true)
	if clear_history_first:
		_scene_history.clear()
	_pending_restore_state = restore_state
	_transition_to(path,previous)


func clear_history() -> void:
	_scene_history.clear()
	_pending_restore_state = ""


func history_depth() -> int:
	return _scene_history.size()


func is_transitioning() -> bool:
	return _busy


func consume_restore_state() -> String:
	var value := _pending_restore_state
	_pending_restore_state = ""
	return value


func _current_scene_path() -> String:
	var current := get_tree().current_scene
	if current == null:
		return ""
	return current.scene_file_path


func _transition_to(path: String, previous: Array[Dictionary]) -> void:
	_rollback_history = previous
	last_navigation_error = ""
	if not ResourceLoader.exists(path,"PackedScene"):
		_navigation_failed(path)
		return
	_busy = true
	_transition_generation += 1
	var generation := _transition_generation
	_startup = false
	if _overlay != null:
		if _fade_in_tween != null:
			_fade_in_tween.kill()
		_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		var twn := create_tween()
		twn.tween_property(_overlay,"color:a",1.0,FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await twn.finished
	if not is_inside_tree(): return
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_navigation_failed(path)
		return
	get_tree().create_timer(8.0).timeout.connect(func():
		if _busy and generation == _transition_generation: _navigation_failed(path)
	)


func _navigation_failed(path: String) -> void:
	_busy = false
	_scene_history = _rollback_history.duplicate(true)
	_pending_restore_state = ""
	last_navigation_error = path
	if _overlay != null:
		_overlay.color.a = 0
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation_failed.emit(path)
	push_warning("Navigation target could not be opened: "+path)
	if DisplayServer.get_name() != "headless":
		var dialog := AcceptDialog.new()
		dialog.title = Locale.t("navigation.error_title")
		dialog.dialog_text = Locale.t("navigation.error_body")
		add_child(dialog)
		UITheme.apply_dialog(dialog,true)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()


func _on_scene_changed() -> void:
	_busy = false
	_rollback_history.clear()
	if _overlay != null: _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if _fade_in_tween != null:
		_fade_in_tween.kill()
	_fade_in_tween = create_tween()
	_fade_in_tween.tween_property(_overlay, "color:a", 0.0, FADE_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Network-driven views can reveal the new page immediately without delaying room state.
func reveal_view(scene: Node) -> void:
	if _busy or _overlay == null or scene != get_tree().current_scene:
		return
	_overlay.color.a = 1.0
	fade_in()


func _popup_visible(node: Node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return false
	var parent := node.get_parent()
	while parent != null:
		if parent.is_queued_for_deletion(): return false
		parent = parent.get_parent()
	if node is Window or node is CanvasLayer: return node.visible
	return node is Control and node.is_visible_in_tree()


func top_popup() -> Node:
	for i in range(_popup_stack.size()-1,-1,-1):
		var node: Node = _popup_stack[i].node
		if _popup_visible(node): return node
	return null


func register_popup(node: Node, initial_focus: Control = null) -> void:
	if not is_instance_valid(node): return
	for entry in _popup_stack:
		if entry.node == node: return
	var current := top_popup()
	if node is CanvasLayer and current is CanvasLayer:
		node.layer = maxi(node.layer,current.layer+1)
	var owner_viewport := node.get_parent().get_viewport() if node is Window else node.get_viewport()
	var before := owner_viewport.gui_get_focus_owner()
	for i in range(_popup_stack.size() - 1, -1, -1):
		var entry := _popup_stack[i]
		if is_instance_valid(before) and is_instance_valid(entry.node) and not _popup_visible(entry.node) and entry.node.is_ancestor_of(before):
			before = entry.before
	_popup_stack.append({"node":node,"before":before})
	if not node.tree_exiting.is_connected(_popup_exited.bind(node)):
		node.tree_exiting.connect(_popup_exited.bind(node),CONNECT_ONE_SHOT)
	if node.has_signal("visibility_changed") and not node.has_meta("modal_visibility_hook"):
		node.set_meta("modal_visibility_hook",true)
		node.visibility_changed.connect(func():
			if not _popup_visible(node): _popup_exited(node))
	var initial_focus_ref: WeakRef = weakref(initial_focus) if is_instance_valid(initial_focus) else null
	_focus_popup.call_deferred(weakref(node), initial_focus_ref)


func _popup_exited(node: Node) -> void:
	for i in range(_popup_stack.size()-1,-1,-1):
		if _popup_stack[i].node == node:
			var before = _popup_stack[i].before
			_popup_stack.remove_at(i)
			for entry in _popup_stack:
				if is_instance_valid(entry.before) and node.is_ancestor_of(entry.before):
					entry.before = before
			if is_instance_valid(before): _restore_focus.call_deferred(weakref(before))


func _restore_focus(reference: WeakRef) -> void:
	var control = reference.get_ref()
	var top := top_popup()
	if top != null and is_instance_valid(control) and top != control and not top.is_ancestor_of(control):
		return
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree() and not control.is_queued_for_deletion():
		control.grab_focus()


func _popup_focusables(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.find_children("*","Control",true,false):
		if child.focus_mode != Control.FOCUS_ALL or not child.is_visible_in_tree(): continue
		if child is BaseButton and child.disabled: continue
		result.append(child)
	return result


func _focus_popup(reference: WeakRef, initial_focus_ref: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if not _popup_visible(node) or top_popup() != node: return
	var controls := _popup_focusables(node)
	if controls.is_empty(): return
	var initial_focus: Control = initial_focus_ref.get_ref() if initial_focus_ref != null else null
	if initial_focus in controls:
		initial_focus.grab_focus()
	elif controls[0].get_viewport().gui_get_focus_owner() not in controls:
		controls[0].grab_focus()


func close_top_popup() -> bool:
	var node := top_popup()
	if node == null: return false
	if node.get_meta("popup_close_locked", false): return true
	if not node.get_meta("popup_close_animated", false):
		_popup_exited(node)
	if node.has_meta("popup_close"):
		node.get_meta("popup_close").call()
		return true
	if node is AcceptDialog:
		node.canceled.emit()
		node.hide()
	elif node is Window or node is Control:
		node.hide()
	else:
		for button in node.find_children("*","Button",true,false):
			if button.visible and not button.disabled and button.text in [Locale.t("common.cancel"),Locale.t("common.back"),Locale.t("common.close")]:
				button.pressed.emit()
				return true
		var owner_node := node.get_parent()
		if owner_node != null and owner_node.has_method("_on_exit"): owner_node._on_exit()
		else: node.queue_free()
	return true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_update_cursor_press(event)
	if event is InputEventKey and DevConsole.is_open():
		return
	if event is InputEventKey and event.pressed:
		_set_keyboard_navigation(true)
	elif event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_keyboard_navigation(false)
	# The fade catches mouse clicks, but focused controls can still receive keys.
	if _busy:
		get_viewport().set_input_as_handled()
		return
	if key_capture.is_valid() and event is InputEventKey and event.pressed and not event.echo:
		var callback := key_capture
		key_capture = Callable()
		callback.call(event.keycode)
		get_viewport().set_input_as_handled()
		return
	var top := top_popup()
	# Node2D battle scenes have their controls inside CanvasLayers. Seed focus
	# explicitly when no Control owns it, then let Godot traverse normally.
	if top == null and get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")):
		var scene := get_tree().current_scene
		if scene != null:
			var controls := _popup_focusables(scene)
			controls = controls.filter(func(control): return control.get_viewport() == get_viewport())
			if not controls.is_empty():
				controls[-1 if event.is_action_pressed("ui_focus_prev") else 0].grab_focus()
				get_viewport().set_input_as_handled()
				return
	if top != null and (event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")):
		var controls := _popup_focusables(top)
		if not controls.is_empty():
			var focused := controls[0].get_viewport().gui_get_focus_owner()
			var index := controls.find(focused)
			var backwards := event.is_action_pressed("ui_focus_prev")
			var next_index := controls.size() - 1 if backwards else 0
			if index >= 0:
				next_index = posmod(index + (-1 if backwards else 1), controls.size())
			controls[next_index].grab_focus()
			get_viewport().set_input_as_handled()
		elif top.get_meta("popup_close_locked", false):
			get_viewport().set_input_as_handled()
		return
	var escape_pressed: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	if not event.is_action_pressed("ui_cancel") and not escape_pressed: return
	get_viewport().set_input_as_handled()
	_handle_back()


func _set_keyboard_navigation(enabled: bool) -> void:
	if keyboard_navigation != enabled:
		keyboard_navigation = enabled
		navigation_input_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and OS.has_feature("android") and not _busy:
		_handle_back(true)

func _handle_back(system_back := false) -> void:
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
		return
	if close_top_popup(): return
	var scene := get_tree().current_scene
	if scene == null: return
	if scene.has_method("cancel_pending_battle_selection") and scene.cancel_pending_battle_selection():
		return
	if scene.has_method("_show_abandon_confirmation"):
		var pause_menu := preload("res://presentation/BattlePause.gd").new()
		pause_menu.battle = scene
		scene.add_child(pause_menu)
		return
	for handler in ["_on_cancel_pressed","_on_back_button_pressed","_on_back_pressed","_on_back_to_menu_pressed"]:
		if scene.has_method(handler):
			scene.call(handler)
			return
	if scene.scene_file_path != "res://MainMenu.tscn": go_back()
	elif system_back: AppAudio.quit_to_desktop()

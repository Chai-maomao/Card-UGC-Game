extends Node

const Outline = preload("res://SkillFieldOutline.gd")
var _active: Dictionary = {}

func watch_button(button: BaseButton) -> void:
	if button.get_meta("reject_feedback_watched",false): return
	button.set_meta("reject_feedback_watched",true)
	var reference: WeakRef = weakref(button)
	button.button_down.connect(func():
		var target = reference.get_ref()
		if target != null: target.set_meta("enabled_press_frame",Engine.get_process_frames()))
	button.gui_input.connect(func(event: InputEvent):
		var target = reference.get_ref()
		if target == null or not event is InputEventMouseButton: return
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed or not target.disabled: return
		if target.get_meta("enabled_press_frame",-1) == Engine.get_process_frames(): return
		reject(target)
		target.accept_event())
	button.tree_exiting.connect(_cancel.bind(button.get_instance_id(),false),CONNECT_ONE_SHOT)

func reject(button: BaseButton) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree(): return
	var id := button.get_instance_id()
	_cancel(id,true)
	var motion: Control = button.call("get_reject_motion_target") if button.has_method("get_reject_motion_target") else button
	var offsets := Vector4(motion.offset_left,motion.offset_top,motion.offset_right,motion.offset_bottom)
	var outline: CanvasItem
	if button.has_method("create_reject_outline"):
		outline = button.call("create_reject_outline")
	else:
		var field_outline := Outline.new()
		field_outline.fill_alpha = 0.12
		var style := button.get_theme_stylebox("disabled" if button.disabled else "normal") as StyleBoxFlat
		if style != null: field_outline.radius = style.corner_radius_top_left
		outline = field_outline
	outline.name = "UnavailableFeedback"
	outline.modulate.a = 0
	button.add_child(outline)
	var reference: WeakRef = weakref(motion)
	var tween := button.create_tween()
	_active[id] = {"button":reference,"offsets":offsets,"tween":tween,"outline":outline}
	var separate_motion := motion != button
	var outline_start: Vector2 = (outline as Control).position if separate_motion else Vector2.ZERO
	tween.tween_method(func(t: float):
		if is_instance_valid(outline): outline.modulate.a = pow(sin(t*PI*2),2),0.0,1.0,0.42)
	if not AppPreferences.get_value("reduced_motion"):
		tween.parallel().tween_method(func(t: float):
			var target = reference.get_ref()
			if target == null: return
			var delta := sin(t*PI*6)*4*(1-t)
			target.offset_left = offsets.x + delta
			target.offset_right = offsets.z + delta,0.0,1.0,0.32)
		if separate_motion:
			tween.parallel().tween_method(func(t: float):
				if is_instance_valid(outline): outline.position = outline_start+Vector2(sin(t*PI*6)*4*(1-t),0),0.0,1.0,0.32)
	tween.tween_callback(_cancel.bind(id,true))
	AppAudio.play("denied","UI")

func _cancel(id: int, restore: bool) -> void:
	if not _active.has(id): return
	var state: Dictionary = _active[id]
	_active.erase(id)
	if state.tween.is_valid(): state.tween.kill()
	var button = state.button.get_ref()
	if restore and button != null:
		var offsets: Vector4 = state.offsets
		button.offset_left = offsets.x
		button.offset_top = offsets.y
		button.offset_right = offsets.z
		button.offset_bottom = offsets.w
		if button.get_parent() is Container: button.get_parent().queue_sort()
	if is_instance_valid(state.outline): state.outline.queue_free()

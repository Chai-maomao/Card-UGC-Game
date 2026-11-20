extends Control

signal view_changed
signal script_moved(at: Vector2, allow_attachment: bool)

var zoom := 0.85
var pan := Vector2(42, 46)
var stack: VBoxContainer
var world: Control
var script_position := Vector2.ZERO
var loose_views: Array[Control] = []
var _script_dragging := false
var _script_pointer := Vector2.ZERO
var _script_origin := Vector2.ZERO
var _middle_panning := false
var last_pointer := Vector2.ZERO
var press_pointer := Vector2.ZERO
var editor_ref: WeakRef
var _panning := false
var _pointer_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	stack = VBoxContainer.new()
	stack.name = "ScriptStack"
	stack.add_theme_constant_override("separation", -preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
	world.add_child(stack)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_sync_view()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.COLOR_BG)
	var spacing := 28.0 * zoom
	var origin := pan.posmod(spacing)
	for x in range(ceili(size.x / spacing) + 1):
		for y in range(ceili(size.y / spacing) + 1):
			draw_circle(origin + Vector2(x, y) * spacing, 1.0, Color(UITheme.Tokens.BORDER, 0.40))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				set_zoom(zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), event.position)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			_panning = event.pressed
			if _panning:
				_pointer_origin = event.position
				_pan_origin = pan
			mouse_default_cursor_shape = CURSOR_DRAG if _panning else CURSOR_ARROW
			accept_event()
	elif event is InputEventMouseMotion and _panning:
		pan = _pan_origin + event.position - _pointer_origin
		_sync_view()
		accept_event()

func _input(event: InputEvent) -> void:
	# Capture middle-button panning over blocks too, without stealing their left drag.
	if not is_visible_in_tree():
		return
	if event is InputEventMagnifyGesture and not get_viewport().gui_is_dragging() and UIMotion.top_popup() == null:
		# Android can clear the emulated mouse hover when a second finger lands.
		var anchor: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, size).has_point(anchor):
			set_zoom(zoom * event.factor, anchor)
			get_viewport().set_input_as_handled()
	if event is InputEventMouse:
		last_pointer = get_global_transform().affine_inverse() * event.position
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			press_pointer = last_pointer
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _script_dragging:
			_script_dragging = false
			script_moved.emit(script_position, _script_origin.distance_to(script_position) * zoom >= 6.0)
		_panning = false
		mouse_default_cursor_shape = CURSOR_ARROW
	if event is InputEventMouseMotion and _script_dragging:
		script_position = _script_origin + to_world(last_pointer) - _script_pointer
		_sync_view()
		var editor = editor_ref.get_ref()
		if editor != null:
			if _script_origin.distance_to(script_position) * zoom >= 6.0:
				editor._preview_trigger_attachment()
			else:
				editor._clear_trigger_attachment()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and get_global_rect().has_point(event.position):
			_panning = true
			_middle_panning = true
			_pointer_origin = get_global_transform().affine_inverse() * event.position
			_pan_origin = pan
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			_panning = false
			_middle_panning = false
	elif event is InputEventMouseMotion and _panning and _middle_panning:
		pan = _pan_origin + (get_global_transform().affine_inverse() * event.position) - _pointer_origin
		_sync_view()
		get_viewport().set_input_as_handled()

func set_zoom(value: float, at: Vector2 = Vector2.INF) -> void:
	if at == Vector2.INF:
		at = size * 0.5
	var next := clampf(value, 0.35, 1.5)
	pan = at - (at - pan) * next / zoom
	zoom = next
	_sync_view()

func reset_view() -> void:
	var bounds := Rect2(script_position,stack.get_combined_minimum_size())
	for view in loose_views:
		if is_instance_valid(view): bounds = bounds.merge(Rect2(view.position,view.get_combined_minimum_size()))
	zoom = clampf(minf((size.x - 64) / maxf(1,bounds.size.x),(size.y - 96) / maxf(1,bounds.size.y)),0.35,1.0)
	pan = Vector2(32, 40) - bounds.position * zoom
	_sync_view()

func reveal(control: Control) -> void:
	pan -= (control.get_global_rect().position - global_position) - Vector2(32, 40)
	_sync_view()

func begin_script_drag(global_point: Vector2) -> void:
	_script_dragging = true
	_script_pointer = to_world(get_global_transform().affine_inverse() * global_point)
	_script_origin = script_position
	mouse_default_cursor_shape = CURSOR_DRAG

func to_world(local_point: Vector2) -> Vector2:
	return (local_point - pan) / zoom

func _sync_view() -> void:
	if stack != null:
		world.position = pan
		world.scale = Vector2.ONE * zoom
		stack.position = script_position
		stack.size = stack.get_combined_minimum_size().max(Vector2(360, 0))
	queue_redraw()
	view_changed.emit()

func _process(_delta: float) -> void:
	if get_viewport().gui_is_dragging():
		var point := last_pointer
		if Rect2(Vector2.ZERO, size).has_point(point):
			var direction := Vector2.ZERO
			if point.x < 28: direction.x = 1
			elif point.x > size.x - 28: direction.x = -1
			if point.y < 28: direction.y = 1
			elif point.y > size.y - 28: direction.y = -1
			if direction != Vector2.ZERO:
				pan += direction * 320 * _delta
				_sync_view()
	if stack != null:
		stack.size = stack.get_combined_minimum_size().max(Vector2(360, 0))
	for view in loose_views:
		if is_instance_valid(view): view.size = view.get_combined_minimum_size()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _script_dragging:
			_script_dragging = false
			script_moved.emit(script_position, false)
		_panning = false
		_middle_panning = false
		mouse_default_cursor_shape = CURSOR_ARROW

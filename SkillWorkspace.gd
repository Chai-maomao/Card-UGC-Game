extends Control

const CONDITION_SOCKET := preload("res://SkillConditionSocket.gd")
const DragPreview := preload("res://SkillDragPreview.gd")
const MIN_SOCKET_OVERLAP := 0.30

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
var _snap_marker: Line2D
var _highlighted_reporter: Control

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.set_meta("skill_workspace_world", true)
	add_child(world)
	stack = VBoxContainer.new()
	stack.name = "ScriptStack"
	stack.add_theme_constant_override("separation", -preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
	world.add_child(stack)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_snap_marker = Line2D.new()
	_snap_marker.name = "SnapMarker"
	_snap_marker.z_index = 5
	_snap_marker.default_color = Color("82e5ff")
	_snap_marker.antialiased = true
	_snap_marker.hide()
	world.add_child(_snap_marker)
	_sync_view()

func find_reporter_socket(pointer: Vector2, payload: Variant) -> Control:
	if not payload is Dictionary:
		return null
	var kind: String = payload.get("type", "")
	if kind not in ["boolean_block", "logic_block", "condition_block", "var_block", "expr_block", "target_block", "side_block"]:
		return null
	var workspace_bounds := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	var face := DragPreview.face_in(get_viewport())
	if face == null or not workspace_bounds.has_point(pointer):
		return null
	var dragged_bounds := DragPreview.bounds_at(face, pointer)
	var grab := pointer.clamp(dragged_bounds.position, dragged_bounds.end)
	var best_socket: Control
	var best_overlap := 0.0
	var best_distance := INF
	var best_grab_area := INF
	for socket in world.find_children("*", "PanelContainer", true, false):
		if not (socket is ValueSlot or socket is TargetSlot or socket.get_script() == CONDITION_SOCKET):
			continue
		if not socket.is_visible_in_tree():
			continue
		var bounds: Rect2 = socket.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, socket.size)
		var intersect := dragged_bounds.intersection(bounds).intersection(workspace_bounds)
		if not intersect.has_area():
			continue
		var fraction := intersect.get_area() / minf(dragged_bounds.get_area(), bounds.get_area())
		if fraction < MIN_SOCKET_OVERLAP or not socket.accepts_reporter(payload):
			continue
		# When a wide reporter covers adjacent sockets, the spot held on its
		# face resolves the ambiguity. A socket still needs actual overlap.
		var grab_area := bounds.get_area() if bounds.has_point(grab) else INF
		var distance := dragged_bounds.get_center().distance_squared_to(bounds.get_center())
		var closer_overlap := fraction > best_overlap or (is_equal_approx(fraction, best_overlap) and distance < best_distance)
		if grab_area < best_grab_area or (grab_area == best_grab_area and closer_overlap):
			best_socket = socket
			best_overlap = fraction
			best_distance = distance
			best_grab_area = grab_area
	return best_socket

func highlight_reporter_socket(socket: Control) -> void:
	if _highlighted_reporter == socket:
		return
	if is_instance_valid(_highlighted_reporter):
		_highlighted_reporter.set_reporter_highlight(false)
	_highlighted_reporter = socket
	if socket != null:
		socket.set_reporter_highlight(true)

func show_snap_marker(anchor: Vector2) -> void:
	_snap_marker.position = anchor
	_snap_marker.width = 3.0 / zoom
	_snap_marker.points = PackedVector2Array([
		Vector2(4, 0), Vector2(16, 0), Vector2(20, 4),
		Vector2(36, 4), Vector2(40, 0), Vector2(58, 0),
	])
	_snap_marker.show()

func hide_snap_marker() -> void:
	_snap_marker.hide()

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
		last_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			press_pointer = last_pointer
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _script_dragging:
			_script_dragging = false
			_update_script_drag_position()
			script_moved.emit(script_position, _script_origin.distance_to(script_position) * zoom >= 6.0)
		_panning = false
		mouse_default_cursor_shape = CURSOR_ARROW
	if event is InputEventMouseMotion and _script_dragging:
		_update_script_drag_position()
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

func _update_script_drag_position() -> void:
	script_position = _script_origin + to_world(last_pointer) - _script_pointer
	_sync_view()

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

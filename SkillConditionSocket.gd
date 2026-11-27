extends PanelContainer

const DragPreview := preload("res://SkillDragPreview.gd")

var block: Node
var condition_path: Array = []
var highlighted := false
var _attached := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_drag_forwarding(_get_reporter_drag, _can_drop_data, _drop_data)
	_refresh_style()

func _get_reporter_drag(position: Vector2):
	var reporter := get_child(0) if get_child_count() > 0 else null
	if reporter != null and reporter.has_method("_slot_get_drag_data"):
		return reporter._slot_get_drag_data(reporter.get_global_transform().affine_inverse() * (get_global_transform() * position))
	return null

func _can_drop_data(_position: Vector2, payload) -> bool:
	if DragPreview.uses_socket_overlap(self):
		return false
	var accepted := accepts_reporter(payload)
	set_reporter_highlight(accepted)
	return accepted

func _drop_data(_position: Vector2, payload) -> void:
	if not _can_drop_data(Vector2.ZERO, payload): return
	drop_reporter(payload)

func accepts_reporter(payload: Variant) -> bool:
	return is_instance_valid(block) and block._can_drop_condition_at(condition_path, payload)

func drop_reporter(payload: Dictionary) -> void:
	set_reporter_highlight(false)
	block._drop_condition_at(condition_path, payload)

func set_reporter_highlight(on: bool) -> void:
	if highlighted != on:
		highlighted = on
		_refresh_style()

func _process(_delta: float) -> void:
	if highlighted and not DragPreview.uses_socket_overlap(self):
		if not get_viewport().gui_is_dragging() or not get_global_rect().has_point(get_global_mouse_position()):
			set_reporter_highlight(false)


func flash_attachment() -> void:
	_attached = true
	_refresh_style()
	var flash := create_tween()
	flash.tween_interval(0.45)
	flash.tween_callback(func():
		_attached = false
		_refresh_style()
	)


func _refresh_style() -> void:
	var active := highlighted or _attached
	var style := StyleBoxFlat.new()
	style.bg_color = Color("265d5c") if active else Color("123c3d")
	style.border_color = Color("9cddd0") if active else Color("438d87")
	style.set_border_width_all(2 if active else 1)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", preload("res://SkillSocketStyle.gd").from_flat(style, "boolean"))

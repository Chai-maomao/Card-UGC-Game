extends Button

@onready var _prompt := Label.new()
@onready var _shortcut := Label.new()


static func uses_touch_picker() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


func _ready() -> void:
	if not uses_touch_picker():
		button_mask = 0
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	custom_minimum_size.y = 92
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	center.add_child(content)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(24, 20)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func():
		var ink := UITheme.Tokens.MUTED
		icon.draw_rect(Rect2(1, 1, 22, 18), ink, false, 1.25)
		icon.draw_circle(Vector2(8, 6.5), 1.5, ink, true, -1, true)
		icon.draw_polyline(PackedVector2Array([Vector2(2, 15), Vector2(7, 11),
			Vector2(11, 14), Vector2(17, 8), Vector2(22, 13)]), ink, 1.25, true)
	)
	content.add_child(icon)
	for label in [_prompt, _shortcut]:
		label.set_meta("keyword_literal", true)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(label)
	UITheme.apply_label(_prompt)
	UITheme.apply_label(_shortcut, true)
	_prompt.add_theme_font_size_override("font_size", 14)
	_shortcut.add_theme_font_size_override("font_size", 12)


func _gui_input(event: InputEvent) -> void:
	if uses_touch_picker() or disabled or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if event.pressed:
		grab_focus()
		if event.double_click:
			pressed.emit()


func set_copy(prompt: String, shortcut: String) -> void:
	_prompt.text = prompt
	_shortcut.text = shortcut
	_shortcut.visible = not shortcut.is_empty()
	accessibility_name = prompt
	accessibility_description = shortcut


func _draw() -> void:
	var last := size - Vector2(1, 1)
	if last.x <= 1 or last.y <= 1:
		return
	var ink := UITheme.Tokens.TEAL if has_focus() else UITheme.Tokens.TEAL.lerp(UITheme.Tokens.BG, 0.28)
	var corners := [Vector2.ONE, Vector2(last.x, 1), last, Vector2(1, last.y)]
	for index in range(corners.size()):
		draw_dashed_line(corners[index], corners[(index + 1) % corners.size()], ink, 1.0, 5.0, true, true)

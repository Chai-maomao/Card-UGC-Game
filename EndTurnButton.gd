extends Button

var _preview_timer: Timer
var _preview_panel: Control
var _touch_started := -1


func _ready() -> void:
	set_meta("suppress_hover_hint",true)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.35
	add_child(_preview_timer)
	_preview_timer.timeout.connect(_show_preview)
	mouse_entered.connect(func(): _preview_timer.start())
	mouse_exited.connect(_hide_preview)
	pressed.connect(_hide_preview)
	focus_exited.connect(_hide_preview)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _hide_preview()
	)

func _gui_input(event: InputEvent) -> void:
	if not OS.has_feature("android") or not event is InputEventMouseButton or disabled:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed: _show_preview()
		else: _hide_preview()
		accept_event()
		return
	if event.device != InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Android releases the emulated left button when it converts a hold into a
	# context click. Only a short, completed tap should commit a battle action.
	accept_event()
	if event.pressed:
		_touch_started = Time.get_ticks_msec()
		button_down.emit()
		_preview_timer.start()
	elif _touch_started >= 0:
		var duration := Time.get_ticks_msec() - _touch_started
		_touch_started = -1
		button_up.emit()
		if not event.is_canceled() and duration < _preview_timer.wait_time * 1000 and Rect2(Vector2.ZERO, size).has_point(event.position):
			if toggle_mode: button_pressed = not button_pressed
			pressed.emit()
		else:
			_hide_preview()


func _get_tooltip(_at_position: Vector2) -> String:
	# This project suppresses native tooltips globally. Use a contextual panel
	# with its own delay, also avoiding duplicate popups if that setting changes.
	return ""


func _show_preview() -> void:
	if disabled or not is_visible_in_tree() or tooltip_text.is_empty():
		return
	_hide_preview()
	_preview_panel = _make_custom_tooltip(tooltip_text) as Control
	_preview_panel.top_level = true
	_preview_panel.z_index = 100
	_ignore_pointer(_preview_panel)
	add_child(_preview_panel)
	_position_preview.call_deferred()


func _position_preview() -> void:
	if not is_instance_valid(_preview_panel):
		return
	var bounds := get_viewport_rect()
	var button := get_global_rect()
	var dimensions := _preview_panel.get_combined_minimum_size()
	_preview_panel.size = dimensions
	var preview_x := button.end.x + 12.0
	if preview_x + dimensions.x > bounds.end.x - 12.0:
		preview_x = button.position.x - dimensions.x - 12.0
	_preview_panel.global_position = Vector2(
		clampf(preview_x, 12, bounds.size.x - dimensions.x - 12),
		clampf(button.get_center().y - dimensions.y * 0.5, 12, bounds.size.y - dimensions.y - 12)
	)


func _hide_preview() -> void:
	_preview_timer.stop()
	if is_instance_valid(_preview_panel):
		_preview_panel.hide()
		_preview_panel.queue_free()
	_preview_panel = null


func _ignore_pointer(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control: _ignore_pointer(child)


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.name = "EndTurnPreview"
	UITheme.apply_panel(panel, "tooltip")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var lines := for_text.split("\n", true, 1)
	var title := Label.new()
	title.text = lines[0]
	UITheme.apply_title(title, 16)
	title.add_theme_color_override("font_color", UITheme.Tokens.HEADING_GOLD)
	content.add_child(title)
	var body := Label.new()
	body.text = lines[1] if lines.size() > 1 else ""
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = minf(340.0, get_viewport_rect().size.x - 48.0)
	body.add_theme_font_size_override("font_size", 14)
	UITheme.apply_label(body)
	content.add_child(body)
	return panel

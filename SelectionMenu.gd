extends CanvasLayer
## A list of choices with the same controls and focus cues as the title.

signal closing

var heading := ""
var title_entry: Button
var scroll_choices := false
var backdrop := Color.TRANSPARENT
var blur_backdrop := false
var placement: Callable
var surface: Node2D
var entries: VBoxContainer
var heading_label: Label
var _scroll: ScrollContainer
var _footer: Button
var _backdrop_material: ShaderMaterial
var _heading_tween: Tween
var _returning := false


func _ready() -> void:
	set_meta("popup_close", dismiss)
	if is_instance_valid(title_entry):
		set_meta("popup_close_animated", true)
	surface = Node2D.new()
	entries = VBoxContainer.new()
	heading_label = Label.new()
	if backdrop.a > 0.0:
		var shade := ColorRect.new()
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.color = backdrop
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		if blur_backdrop and AppPreferences.get_value("quality") > 0:
			var capture := BackBufferCopy.new()
			capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			add_child(capture)
			_backdrop_material = ShaderMaterial.new()
			_backdrop_material.shader = preload("res://presentation/SelectionBackdrop.gdshader")
			_backdrop_material.set_shader_parameter("far_tint", 0.38 if backdrop.a >= 1.0 else backdrop.a * 0.58)
			shade.color.a = 1.0
			shade.material = _backdrop_material
		add_child(shade)
		if blur_backdrop:
			UITheme.fade_enter(shade, 0.16)
	add_child(surface)
	UITheme.apply_title(heading_label, 24)
	_apply_heading()
	heading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(heading_label)
	entries.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if scroll_choices:
		_scroll = ScrollContainer.new()
		_scroll.name = "ChoiceScroll"
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.follow_focus = true
		surface.add_child(_scroll)
		entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(entries)
	else:
		surface.add_child(entries)
	viewport_changed()
	get_viewport().size_changed.connect(viewport_changed)


func add_choice(text: String, action: Callable, hint := "") -> Button:
	var button := _make_choice(text, action)
	button.tooltip_text = hint
	entries.add_child(button)
	return button


func finish(with_back := true) -> void:
	if with_back:
		if scroll_choices:
			_footer = _make_choice(Locale.t("common.back"), dismiss)
			surface.add_child(_footer)
		else:
			var gap := Control.new()
			gap.custom_minimum_size.y = 8
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entries.add_child(gap)
			add_choice(Locale.t("common.back"), dismiss)
	viewport_changed()
	for choice in entries.get_children():
		if choice is Button and not choice.disabled:
			choice.grab_focus()
			return


func dismiss() -> void:
	if is_queued_for_deletion() or _returning:
		return
	if not is_instance_valid(title_entry) or AppPreferences.get_value("reduced_motion"):
		_finish_dismiss()
		return
	_returning = true
	set_meta("popup_close_locked", true)
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		button.disabled = true
	for list in [entries, _footer]:
		if list == null:
			continue
		var fade: Tween = list.get_meta("ui_fade") if list.has_meta("ui_fade") else null
		if fade != null and fade.is_valid():
			fade.kill()
		list.create_tween().tween_property(list, "modulate:a", 0.0, 0.10)
	_tween_heading(_entry_text_position() - heading_label.pivot_offset, _entry_text_scale(), title_entry.text, title_entry.get_theme_color("font_color"))
	_heading_tween.finished.connect(_finish_dismiss)


func _finish_dismiss() -> void:
	if not is_queued_for_deletion():
		queue_free()
		closing.emit()


func slide_entries(distance: float) -> void:
	if not is_queued_for_deletion():
		UITheme.animate_list_enter(entries, distance)


func fade_choices(delay := 0.0) -> void:
	if not is_queued_for_deletion():
		UITheme.fade_enter(entries, 0.14, delay)
		UITheme.fade_enter(_footer, 0.14, delay)


func reveal_from_child(opener: Button) -> void:
	surface.show()
	# Keep the returning label at full opacity while the other rows reappear.
	var fade: Tween = entries.get_meta("ui_fade") if entries.has_meta("ui_fade") else null
	if fade != null and fade.is_valid():
		fade.kill()
	entries.modulate.a = 1.0
	for choice in entries.get_children():
		if choice is Button and choice != opener:
			UITheme.fade_enter(choice, 0.14)
	UITheme.fade_enter(_footer, 0.14)
	if is_instance_valid(opener) and opener.is_visible_in_tree():
		opener.grab_focus()


func promote_heading() -> void:
	if is_queued_for_deletion() or _returning or not surface.is_visible_in_tree():
		return
	if AppPreferences.get_value("reduced_motion"):
		fade_choices()
		return
	var destination := heading_label.position
	var source := _entry_text_position()
	heading_label.pivot_offset = Vector2(0, heading_label.size.y * 0.5)
	heading_label.position = source - heading_label.pivot_offset
	heading_label.scale = Vector2.ONE * _entry_text_scale()
	_set_heading_text(title_entry.text, title_entry.get_theme_color("font_color"))
	_tween_heading(destination, 1.0, heading, _heading_color())
	# An entry below the first row travels through the options on its way up.
	fade_choices(0.13 if source.y > heading_label.size.y else 0.08)


func _entry_text_position() -> Vector2:
	var left := title_entry.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
	var center := title_entry.get_global_transform_with_canvas() * Vector2(left, title_entry.size.y * 0.5)
	return surface.get_global_transform_with_canvas().affine_inverse() * center


func _entry_text_scale() -> float:
	return float(title_entry.get_theme_font_size("font_size")) / heading_label.get_theme_font_size("font_size")


func _tween_heading(destination: Vector2, scale_value: float, text: String, color: Color) -> void:
	if _heading_tween != null and _heading_tween.is_valid():
		_heading_tween.kill()
	_heading_tween = heading_label.create_tween().set_parallel()
	_heading_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_heading_tween.tween_property(heading_label, "position", destination, 0.19)
	_heading_tween.tween_property(heading_label, "scale", Vector2.ONE * scale_value, 0.19)
	if heading_label.text != text:
		_heading_tween.tween_property(heading_label, "self_modulate:a", 0.0, 0.055).set_delay(0.03)
		_heading_tween.tween_callback(_set_heading_text.bind(text, color)).set_delay(0.085)
		_heading_tween.tween_property(heading_label, "self_modulate:a", 1.0, 0.065).from(0.0).set_delay(0.085)
	else:
		_heading_tween.tween_property(heading_label, "self_modulate:a", 1.0, 0.065)
		_heading_tween.tween_method(_set_heading_color, heading_label.get_theme_color("font_color"), color, 0.19)


func _apply_heading() -> void:
	_set_heading_text(heading, _heading_color())


func _set_heading_text(text: String, color: Color) -> void:
	heading_label.text = text
	_set_heading_color(color)


func _set_heading_color(color: Color) -> void:
	heading_label.add_theme_color_override("font_color", color)


func _heading_color() -> Color:
	return UITheme.Tokens.CONTRAST_INK if AppPreferences.get_value("high_contrast") else UITheme.Tokens.HEADING_GOLD


func focus_choice(text_or_name: String) -> void:
	var choice := find_choice(text_or_name)
	if choice != null:
		choice.grab_focus()


func find_choice(text_or_name: String) -> Button:
	for choice in entries.get_children():
		if choice is Button and (choice.text == text_or_name or choice.name == text_or_name):
			return choice
	return null


func _make_choice(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	if scroll_choices:
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_selection_entry(button, title_entry.get_theme_font("font") if is_instance_valid(title_entry) else null)
	button.pressed.connect(action)
	return button


func viewport_changed() -> void:
	if placement.is_valid():
		placement.call()
		return
	var screen := get_viewport().get_visible_rect().size
	place(Transform2D(0, screen * Vector2(0.115, 0.36)), minf(screen.x / 1152.0, screen.y / 648.0))


func place(transform: Transform2D, scale_value: float) -> void:
	surface.transform = transform
	if _heading_tween != null and _heading_tween.is_valid():
		_heading_tween.kill()
		if _returning:
			_finish_dismiss.call_deferred()
			return
		heading_label.scale = Vector2.ONE
		heading_label.self_modulate.a = 1.0
		_apply_heading()
	var heading_gap := UITheme.Tokens.SPACING[1] * scale_value
	heading_label.position = Vector2(22, -heading_label.get_combined_minimum_size().y - heading_gap)
	var separation := roundi(4 * scale_value)
	entries.add_theme_constant_override("separation", separation)
	var row_size := Vector2(218, 36) * scale_value
	var screen := get_viewport().get_visible_rect().size
	var available := (screen.y - transform.origin.y - 16) / transform.y.y
	if _scroll == null and entries.get_child_count() > 0:
		var rows := 0
		var gaps := float(separation * (entries.get_child_count() - 1))
		for child: Control in entries.get_children():
			if child is Button: rows += 1
			else: gaps += child.get_combined_minimum_size().y
		if rows > 0:
			row_size.y = clampf((available - gaps) / rows, 0.0, row_size.y)
	var text_size := 20 + 2 * int(AppPreferences.get_value("text_size"))
	for button in entries.get_children():
		if button is Button:
			button.custom_minimum_size = row_size
			button.add_theme_font_size_override("font_size", text_size)
	entries.reset_size()
	if _scroll != null and _footer != null:
		_footer.custom_minimum_size = row_size
		_footer.add_theme_font_size_override("font_size", text_size)
		var list_height := minf(entries.get_combined_minimum_size().y, available - row_size.y - 8)
		_scroll.size = Vector2(clampf(screen.x * 0.34, 280, 410), maxf(row_size.y, list_height))
		_footer.position = Vector2(0, _scroll.size.y + 8)
		_footer.size = row_size
		var last := entries.get_child(-1) as Button
		if last != null:
			last.focus_neighbor_bottom = last.get_path_to(_footer)
			_footer.focus_neighbor_top = _footer.get_path_to(last)
	if _backdrop_material != null:
		var heading_size := heading_label.get_combined_minimum_size()
		var menu_size := _scroll.size if _scroll != null else entries.get_combined_minimum_size()
		if _footer != null:
			menu_size.y = _footer.position.y + _footer.size.y
		var edge := 22.0 * scale_value
		var menu_width := maxf(menu_size.x, heading_size.x + heading_label.position.x)
		var bounds := Rect2(transform * Vector2(0, heading_label.position.y), Vector2.ZERO)
		for corner in [Vector2(menu_width, heading_label.position.y), Vector2(0, menu_size.y), Vector2(menu_width, menu_size.y)]:
			bounds = bounds.expand(transform * corner)
		bounds = bounds.grow(edge)
		var backdrop_scale := sqrt(0.92)
		var backdrop_size := bounds.size * backdrop_scale
		bounds = Rect2(bounds.get_center() - backdrop_size * 0.5, backdrop_size)
		_backdrop_material.set_shader_parameter("view_size", get_viewport().get_visible_rect().size)
		_backdrop_material.set_shader_parameter("focus_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
		_backdrop_material.set_shader_parameter("feather", 260.0 * scale_value * backdrop_scale)


static func tabletop_axis(table: Node3D, screen_point: Vector2) -> Vector2:
	var point: Vector3 = table.plane_point(screen_point)
	var camera: Camera3D = table.camera
	var projected := camera.unproject_position(point)
	var right := camera.unproject_position(point + Vector3.RIGHT * 0.25) - projected
	var down := camera.unproject_position(point + Vector3.BACK * 0.25) - projected
	return down / right.x

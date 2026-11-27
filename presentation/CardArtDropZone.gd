extends Button

signal paste_requested

@onready var _prompt := Label.new()
@onready var _shortcut := Label.new()
var _empty_content: CenterContainer
var _imported_content: MarginContainer
var _thumbnail: TextureRect
var _file_title: Label
var _file_size: Label
var _art_path := ""
var _attached_style: StyleBoxFlat
var _focused_style: StyleBoxFlat
var _browse_on_release := false
var _paste_on_release := false


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
	_empty_content = center
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
	_build_imported_row()


func _build_imported_row() -> void:
	_attached_style = UITheme.panel_style(UITheme.Tokens.BG.lightened(0.02), UITheme.Tokens.FIELD_BORDER, 1, 5)
	_focused_style = UITheme.panel_style(UITheme.Tokens.BG.lightened(0.02), UITheme.Tokens.TEAL, 1, 5)
	_imported_content = MarginContainer.new()
	_imported_content.name = "ImportedArt"
	_imported_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		_imported_content.add_theme_constant_override("margin_" + side, 8)
	add_child(_imported_content)
	_imported_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_imported_content.minimum_size_changed.connect(_fit_imported_row)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_imported_content.add_child(row)
	_thumbnail = TextureRect.new()
	_thumbnail.custom_minimum_size = Vector2(34, 34)
	_thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_thumbnail)
	var description := VBoxContainer.new()
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.alignment = BoxContainer.ALIGNMENT_CENTER
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_constant_override("separation", 1)
	row.add_child(description)
	_file_title = Label.new()
	_file_title.name = "ImportedArtName"
	_file_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_file_title.set_meta("keyword_literal", true)
	_file_title.add_theme_font_size_override("font_size", 13)
	UITheme.apply_label(_file_title)
	description.add_child(_file_title)
	_file_size = Label.new()
	_file_size.name = "ImportedArtSize"
	_file_size.set_meta("keyword_literal", true)
	_file_size.add_theme_font_size_override("font_size", 12)
	UITheme.apply_label(_file_size, true)
	description.add_child(_file_size)
	var replace := Button.new()
	replace.name = "ReplaceArt"
	replace.text = Locale.t("editor.replace_art")
	replace.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(replace, "utility")
	replace.pressed.connect(func(): pressed.emit.call_deferred())
	row.add_child(replace)
	_imported_content.hide()


func set_art(path: String) -> void:
	if _art_path == path:
		return
	_art_path = path
	var attached := not path.is_empty()
	_empty_content.visible = not attached
	_imported_content.visible = attached
	custom_minimum_size.y = 54 if attached else 92
	_thumbnail.texture = null
	if attached:
		var file := FileAccess.open(path, FileAccess.READ)
		_file_size.visible = file != null
		if file != null:
			_file_size.text = String.humanize_size(file.get_length())
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D if path.begins_with("res://") and ResourceLoader.exists(path, "Texture2D") else null
		if texture == null and file != null:
			var thumbnail := Image.load_from_file(path)
			if thumbnail != null and not thumbnail.is_empty():
				var bounds := Vector2(thumbnail.get_size())
				var reduced := Vector2i(bounds * minf(1.0, 72.0 / maxf(bounds.x, bounds.y))).max(Vector2i.ONE)
				thumbnail.resize(reduced.x, reduced.y, Image.INTERPOLATE_BILINEAR)
				texture = ImageTexture.create_from_image(thumbnail)
		_thumbnail.texture = texture
		_thumbnail.visible = texture != null
	_file_title.text = path.get_file()
	if attached and _thumbnail.texture == null:
		_file_size.visible = true
		_file_size.text = Locale.t("editor.art_missing")
	_fit_imported_row()
	queue_redraw()


func _fit_imported_row() -> void:
	if _imported_content.visible:
		custom_minimum_size.y = maxf(54.0, _imported_content.get_combined_minimum_size().y)


func _gui_input(event: InputEvent) -> void:
	if uses_touch_picker() or disabled or not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		accept_event()
		if event.pressed:
			grab_focus()
			_paste_on_release = true
		elif _paste_on_release:
			_paste_on_release = false
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				paste_requested.emit.call_deferred()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if event.pressed:
		grab_focus()
		_browse_on_release = event.double_click
	elif _browse_on_release:
		_browse_on_release = false
		if Rect2(Vector2.ZERO, size).has_point(event.position):
			pressed.emit.call_deferred()


func set_copy(prompt: String, shortcut: String) -> void:
	_prompt.text = prompt
	_shortcut.text = shortcut
	_shortcut.visible = not shortcut.is_empty()
	accessibility_name = prompt
	accessibility_description = shortcut


func _draw() -> void:
	if not _art_path.is_empty():
		draw_style_box(_focused_style if has_focus() else _attached_style, Rect2(Vector2.ZERO, size))
		return
	var last := size - Vector2(1, 1)
	if last.x <= 1 or last.y <= 1:
		return
	var ink := UITheme.Tokens.TEAL if has_focus() else UITheme.Tokens.TEAL.lerp(UITheme.Tokens.BG, 0.28)
	var corners := [Vector2.ONE, Vector2(last.x, 1), last, Vector2(1, last.y)]
	for index in range(corners.size()):
		draw_dashed_line(corners[index], corners[(index + 1) % corners.size()], ink, 1.0, 5.0, true, true)

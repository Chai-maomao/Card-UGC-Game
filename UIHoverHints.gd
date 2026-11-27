extends CanvasLayer

const DELAY := 0.45
const EDGE_MARGIN := 12.0
const ANCHOR_GAP := 10.0
var panel: PanelContainer
var label: RichTextLabel
var _displayed_text := ""
var source: Node
var active_menu: PopupMenu
var elapsed := 0.0
var current_text := ""
var _using_touch := false
var _pointer := Vector2.INF
var _layout_viewport_size := Vector2.ZERO


func _ready() -> void:
	# This service owns tooltips for the game. Suppress the native timer without
	# clearing tooltip_text: reused controls can then replace/remove text normally.
	# Also configured at startup in project.godot because existing Viewports cache
	# the native delay. This runtime setting covers subsequently created viewports.
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", 86400.0)
	# Embedded PopupMenu windows occupy layer 1024 in Godot.
	layer = 1100
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_panel(panel, "tooltip")
	add_child(panel)
	label = preload("res://presentation/SkillDescription.gd").build("")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.fit_content = false
	label.clip_contents = true
	panel.add_child(label)
	panel.hide()
	AppPreferences.changed.connect(_on_preferences_changed)


func _on_preferences_changed(key: String) -> void:
	if key == "appearance":
		UITheme.apply_panel(panel, "tooltip")
		label.add_theme_color_override("default_color", UITheme.COLOR_TEXT)
		_displayed_text = ""
		panel.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
	if event is InputEventScreenTouch or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION):
		_using_touch = true
	elif event is InputEventKey or (event is InputEventMouseMotion and event.device >= 0 and event.button_mask == 0):
		_using_touch = false

func _process(delta: float) -> void:
	# A lifted finger leaves an emulated pointer over the last control.
	if _using_touch and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		panel.hide()
		elapsed = 0.0
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var pointer := get_viewport().get_mouse_position() if _pointer == Vector2.INF else _pointer
	var hint := hint_for(hovered, pointer)
	# PopupMenu items are not Controls. Preserve their existing item tooltips
	# when the native renderer is suppressed, and don't leak background hints.
	if is_instance_valid(active_menu) and active_menu.visible:
		hint = menu_hint(active_menu)
	var next_source: Node = hint.get("source")
	var battle_frame := UITheme.is_battle_context(next_source)
	if panel.get_meta("battle_frame", false) != battle_frame:
		panel.set_meta("battle_frame", battle_frame)
		panel.queue_redraw()
	var next_text: String = hint.get("text", "")
	if next_source != source or next_text != current_text:
		source = next_source
		current_text = next_text
		elapsed = 0
		panel.hide()
	if current_text.is_empty() or get_viewport().gui_is_dragging():
		panel.hide()
		return
	elapsed += delta
	if elapsed >= DELAY:
		var anchor := Rect2()
		var beside_menu := false
		if source is PopupMenu and source.is_embedded():
			anchor = Rect2(Vector2(source.position), Vector2(source.size))
			beside_menu = true
		elif source is Control and not hint.get("at_pointer", false):
			anchor = source.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, source.size)
		show_hint(current_text, pointer, anchor, beside_menu)


func watch_menu(menu: PopupMenu) -> void:
	menu.about_to_popup.connect(func():
		active_menu = menu
		elapsed = 0
		panel.hide()
	)


static func menu_hint(menu: PopupMenu) -> Dictionary:
	var index := menu.get_focused_item()
	if index < 0 or index >= menu.item_count:
		return {}
	var text := menu.get_item_tooltip(index)
	return {"source": menu, "text": text} if not text.is_empty() else {}


static func hint_for(control: Control, pointer: Vector2 = Vector2.INF) -> Dictionary:
	var ancestor := control
	var suppress_plain := false
	while is_instance_valid(ancestor):
		if ancestor.get_meta("tabletop_arriving",false): return {}
		suppress_plain = suppress_plain or bool(ancestor.get_meta("suppress_hover_hint", false))
		ancestor = ancestor.get_parent_control()
	while is_instance_valid(control):
		if control is RichTextLabel and control.is_inside_tree():
			var point := control.get_local_mouse_position() if pointer == Vector2.INF else control.get_global_transform_with_canvas().affine_inverse() * pointer
			var tooltip: String = control.get_tooltip(point)
			if tooltip.begins_with(SkillHelp.KEYWORD_PREFIX):
				var help := SkillHelp.keyword_description(tooltip.trim_prefix(SkillHelp.KEYWORD_PREFIX))
				if not help.is_empty():
					return {"source": control, "text": help, "at_pointer": true}
		var text: String = control.tooltip_text
		if not suppress_plain and not text.is_empty():
			return {"source": control, "text": text}
		control = control.get_parent_control()
	return {}


func show_hint(text: String, at: Vector2, anchor := Rect2(), beside_menu := false) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var needs_layout := _displayed_text != text or _layout_viewport_size != viewport_size
	var reposition := not panel.visible or needs_layout or not anchor.has_area()
	var padding := panel.get_theme_stylebox("panel").get_minimum_size()
	if needs_layout:
		_layout_viewport_size = viewport_size
		_displayed_text = text
		var max_width := minf(340, maxf(1, viewport_size.x - 32 - padding.x))
		var font_size := label.get_theme_font_size("normal_font_size")
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text = preload("res://presentation/SkillDescription.gd").colored(text, font_size)
		var width := clampf(ceilf(label.get_content_width()) + 2.0, 1.0, max_width)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(width, 0)
		label.size.x = width
		var height := ceilf(label.get_content_height())
		label.custom_minimum_size.y = minf(height, maxf(1, viewport_size.y - padding.y - 24))
		panel.size = label.custom_minimum_size + padding
	panel.show()
	if reposition:
		_position_hint(at, anchor, beside_menu)


func _position_hint(at: Vector2, anchor: Rect2, beside_menu: bool) -> void:
	if not is_instance_valid(panel):
		return
	var bounds := get_viewport().get_visible_rect().size
	var pos := at + Vector2(16, 22)
	if anchor.has_area():
		pos = anchor.position
		if beside_menu:
			# Align hints with the menu rather than a selectable row.
			pos.x = anchor.end.x + ANCHOR_GAP
			if pos.x + panel.size.x > bounds.x - EDGE_MARGIN:
				pos.x = anchor.position.x - panel.size.x - ANCHOR_GAP
		else:
			pos.y = anchor.end.y + ANCHOR_GAP
			if pos.y + panel.size.y > bounds.y - EDGE_MARGIN:
				pos.y = anchor.position.y - panel.size.y - ANCHOR_GAP
	elif pos.y + panel.size.y > bounds.y - EDGE_MARGIN:
		pos.y = at.y - panel.size.y - EDGE_MARGIN
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(EDGE_MARGIN, bounds.x - panel.size.x - EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(EDGE_MARGIN, bounds.y - panel.size.y - EDGE_MARGIN))
	panel.position = pos

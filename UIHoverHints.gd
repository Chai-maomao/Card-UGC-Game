extends CanvasLayer

const DELAY := 0.45
var panel: PanelContainer
var label: RichTextLabel
var _displayed_text := ""
var source: Node
var active_menu: PopupMenu
var elapsed := 0.0
var current_text := ""
var _using_touch := false
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
	set_process_input(OS.has_feature("android"))
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

func _input(event: InputEvent) -> void:
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
	var hint := hint_for(hovered)
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
		show_hint(current_text, get_viewport().get_mouse_position())


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


static func hint_for(control: Control) -> Dictionary:
	var ancestor := control
	while is_instance_valid(ancestor):
		if ancestor.get_meta("suppress_hover_hint",false) or ancestor.get_meta("tabletop_arriving",false): return {}
		if ancestor.has_meta("hand_hover_hit_test") and not ancestor.get_meta("hand_hover_hit_test").call(ancestor): return {}
		ancestor = ancestor.get_parent_control()
	while is_instance_valid(control):
		var text: String = control.tooltip_text
		if not text.is_empty():
			return {"source": control, "text": text}
		control = control.get_parent_control()
	return {}


func show_hint(text: String, at: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var padding := panel.get_theme_stylebox("panel").get_minimum_size()
	if _displayed_text != text or _layout_viewport_size != viewport_size:
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
	_position_hint(at)


func _position_hint(at: Vector2) -> void:
	if not is_instance_valid(panel):
		return
	var bounds := get_viewport().get_visible_rect().size
	var pos := at + Vector2(16, 22)
	if is_instance_valid(active_menu) and active_menu.visible and active_menu.is_embedded():
		# Keep explanations beside the menu, not over the selectable rows.
		var menu_rect := Rect2(Vector2(active_menu.position), Vector2(active_menu.size))
		pos.x = menu_rect.end.x + 12
		if pos.x + panel.size.x > bounds.x - 12:
			pos.x = menu_rect.position.x - panel.size.x - 12
	if pos.y + panel.size.y > bounds.y - 12:
		pos.y = at.y - panel.size.y - 12
	pos.x = clampf(pos.x, 12, maxf(12, bounds.x - panel.size.x - 12))
	pos.y = clampf(pos.y, 12, maxf(12, bounds.y - panel.size.y - 12))
	panel.position = pos

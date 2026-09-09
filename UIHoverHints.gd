extends CanvasLayer

const DELAY := 0.45
var panel: PanelContainer
var label: Label
var source: Node
var active_menu: PopupMenu
var elapsed := 0.0
var current_text := ""


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
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.COLOR_PANEL_DARK, UITheme.COLOR_GOLD_SOFT, 1, 8, UITheme.COLOR_SHADOW, 3))
	add_child(panel)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 14)
	UITheme.apply_label(label)
	panel.add_child(label)
	panel.hide()


func _process(delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var hint := hint_for(hovered)
	# PopupMenu items are not Controls. Preserve their existing item tooltips
	# when the native renderer is suppressed, and don't leak background hints.
	if is_instance_valid(active_menu) and active_menu.visible:
		hint = menu_hint(active_menu)
	var next_source: Node = hint.get("source")
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
	while is_instance_valid(control):
		var text: String = control.tooltip_text
		if not text.is_empty():
			return {"source": control, "text": text}
		control = control.get_parent_control()
	return {}


func show_hint(text: String, at: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(360, maxf(60, viewport_size.x - 32))
	var line_height := label.get_theme_font("font").get_height(14) + 3
	label.max_lines_visible = maxi(1, int((viewport_size.y - 56) / line_height))
	label.custom_minimum_size.x = width - 20
	if label.text != text:
		label.text = text
	panel.size = Vector2(width, 0)
	panel.show()
	_position_hint(at)
	_position_hint.call_deferred(at)


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

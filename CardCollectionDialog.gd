extends CanvasLayer

const CardScene = preload("res://CardUI.tscn")
var cards: Array = []
var heading := ""
var pick_limit := 0
var on_confirm: Callable
var include_source_positions := false
var selected: Dictionary = {}
var selected_order: Array[int] = []
var card_uis: Dictionary = {}
var selection_overlays: Dictionary = {}
var panel: PanelContainer
var grid: GridContainer
var confirm_button: Button
var scroll: ScrollContainer
var _card_scale := 1.0


static func show_cards(parent: Node, items: Array, title: String, limit: int = 0, callback: Callable = Callable(), with_source_positions: bool = false):
	var dialog = load("res://CardCollectionDialog.gd").new()
	dialog.cards = items.duplicate()
	dialog.heading = title
	dialog.pick_limit = maxi(0, mini(limit, items.size()))
	dialog.on_confirm = callback
	dialog.include_source_positions = with_source_positions
	parent.add_child(dialog)
	return dialog


func _ready() -> void:
	layer = 120
	var backdrop := ColorRect.new()
	UITheme.apply_overlay(backdrop)
	add_child(backdrop)
	panel = PanelContainer.new()
	panel.name = "CardCollectionPanel"
	UITheme.apply_panel(panel, "gold")
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = heading
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 18)
	box.add_child(title)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	if pick_limit > 0:
		confirm_button = Button.new()
		confirm_button.text = Locale.t("battle.confirm")
		confirm_button.disabled = true
		confirm_button.custom_minimum_size = Vector2(130, 38)
		UITheme.apply_button(confirm_button, "primary", false)
		confirm_button.pressed.connect(_confirm)
		footer.add_child(confirm_button)
	var close := Button.new()
	close.text = Locale.t("battle.close")
	close.custom_minimum_size = Vector2(130, 38)
	UITheme.apply_button(close, "secondary", false)
	close.pressed.connect(queue_free)
	footer.add_child(close)
	for index in range(cards.size()):
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var center := CenterContainer.new()
		cell.add_child(center)
		var card_ui := CardScene.instantiate()
		center.add_child(card_ui)
		card_uis[index] = card_ui
		card_ui.set_card(cards[index])
		card_ui.set_battle_layout_preview(true)
		if pick_limit > 0:
			_apply_selection_card_style(card_ui)
			var overlay := ColorRect.new()
			overlay.name = "SelectionShade"
			overlay.color = Color(0.01, 0.025, 0.06, 0.62)
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.z_index = 100
			card_ui.add_child(overlay)
			selection_overlays[index] = overlay
			_ignore_descendant_mouse(card_ui)
			card_ui.mouse_filter = Control.MOUSE_FILTER_STOP
			card_ui.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card_ui.gui_input.connect(_on_card_input.bind(index))
	get_viewport().size_changed.connect(_layout)
	panel.minimum_size_changed.connect(_fit_panel, CONNECT_DEFERRED)
	_layout()


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var desired := _desired_size(viewport_size)
	_fit_panel()
	_card_scale = clampf(viewport_size.y / 648.0, 0.75, 1.1)
	grid.columns = maxi(1, mini(cards.size(), mini(6, int((desired.x - 60) / (120 * _card_scale + 12)))))
	for cell in grid.get_children():
		var card_ui = cell.get_child(0).get_child(0)
		card_ui.apply_ui_scale(_card_scale)
		card_ui.set_battle_layout_preview(true)
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var desired := _desired_size(viewport_size)
	panel.size = desired
	panel.position = (viewport_size - desired) * 0.5


func _desired_size(viewport_size: Vector2) -> Vector2:
	var width := minf(880, viewport_size.x - 32)
	var preview_scale := clampf(viewport_size.y / 648.0, 0.75, 1.1)
	var columns := maxi(1, mini(cards.size(), mini(6, int((width - 60) / (120 * preview_scale + 12)))))
	var rows := ceili(float(cards.size()) / columns)
	var content_height := rows * (160 * preview_scale + 12) + 110
	return Vector2(width, minf(minf(600, viewport_size.y - 32), content_height))


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(not selected.has(index), index)


func _select(pressed: bool, index: int, _legacy_button: Control = null) -> void:
	if pressed and selected.size() >= pick_limit:
		return
	if pressed:
		selected[index] = true
		selected_order.append(index)
	else:
		selected.erase(index)
		selected_order.erase(index)
	var overlay: ColorRect = selection_overlays.get(index)
	if overlay:
		overlay.visible = not pressed
	var card_ui: Control = card_uis.get(index)
	if card_ui:
		card_ui.modulate = Color(1.08, 1.08, 1.03) if pressed else Color.WHITE
	confirm_button.disabled = selected.is_empty()


func _ignore_descendant_mouse(root: Node) -> void:
	for child in root.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_descendant_mouse(child)


func _apply_selection_card_style(card_ui: Control) -> void:
	var background := card_ui.get_node_or_null("Background") as Panel
	if background == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.095, 0.18, 1.0)
	style.border_color = Color(0.88, 0.68, 0.25, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	background.add_theme_stylebox_override("panel", style)


func _confirm() -> void:
	if selected.is_empty():
		return
	var chosen: Array = []
	var origins: Array = []
	for index in selected_order:
		chosen.append(cards[index])
		var card_ui: Control = card_uis.get(index)
		origins.append(card_ui.global_position + card_ui.size / 2 if card_ui != null else Vector2.ZERO)
	if on_confirm.is_valid():
		if include_source_positions:
			on_confirm.call(chosen, origins)
		else:
			on_confirm.call(chosen)
	queue_free()

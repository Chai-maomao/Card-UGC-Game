extends Node

var editor: Node
var button: Button
var popup_layer: CanvasLayer
var panel: PanelContainer
var action_input: SpinBox
var points_input: SpinBox
var mana_input: SpinBox
var quote_label: Label
var status_label: Label
var config: Dictionary


func setup(owner_editor: Node, box: VBoxContainer) -> void:
	name = "ActionEconomyDiagnostics"
	editor = owner_editor
	button = Button.new()
	button.name = "ActionEconomyButton"
	button.text = Locale.t("economy.button")
	button.visible = not PlayerData.skill_tutorial_active
	UITheme.apply_button(button, "secondary")
	button.pressed.connect(open)
	box.add_child(button)
	editor.get_viewport().size_changed.connect(_resize)


func open() -> void:
	editor._save_form_to_draft()
	var card := PlayerData.build_card_from_draft()
	config = PlayerData.battle_config.duplicate(true)
	close()
	popup_layer = UITheme.make_popup_layer(editor, 150).layer
	popup_layer.name = "ActionEconomyLayer"
	panel = PanelContainer.new()
	panel.name = "ActionEconomyPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	popup_layer.add_child(panel)
	UITheme.apply_popup_frame(panel, "gold", false)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize()
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("economy.title", [card.card_name])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title.text
	UITheme.apply_title(title, 22)
	box.add_child(title)
	var rules := Label.new()
	rules.text = Locale.t("economy.rules" if config.has("action_base") else "economy.legacy")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(rules, true)
	box.add_child(rules)
	var inputs := HBoxContainer.new()
	inputs.name = "ActionEconomyInputs"
	inputs.add_theme_constant_override("separation", 16)
	box.add_child(inputs)
	action_input = _make_input(inputs, "ActionNumber", "economy.action_number", 1, 40, 5)
	points_input = _make_input(inputs, "RemainingPoints", "economy.remaining_points", 0, 100, 2)
	mana_input = _make_input(inputs, "AvailableMana", "economy.available_mana", 0, 100, 2)
	quote_label = Label.new()
	quote_label.name = "ActionEconomyQuote"
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(quote_label, 18)
	box.add_child(quote_label)
	status_label = Label.new()
	status_label.name = "ActionEconomyStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(status_label)
	box.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.name = "ActionEconomyNotesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 90
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.apply_scrollbar(scroll.get_v_scroll_bar())
	box.add_child(scroll)
	var notes := Label.new()
	notes.name = "ActionEconomyNotes"
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.text = ActionEconomyAnalyzer.description(card)
	UITheme.apply_label(notes)
	scroll.add_child(notes)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var close_button := Button.new()
	close_button.name = "ActionEconomyClose"
	close_button.text = Locale.t("common.close")
	close_button.custom_minimum_size = Vector2(120, 40)
	UITheme.apply_button(close_button, "secondary")
	close_button.pressed.connect(close)
	row.add_child(close_button)
	_refresh()
	# Content minimum sizes settle before centering and starting the entrance.
	_finish_open.call_deferred()


func _finish_open() -> void:
	if not is_instance_valid(panel): return
	_resize()
	UITheme.animate_popup_enter(panel)


func _make_input(parent: Control, node_name: String, key: String, minimum: int, maximum: int, initial: int) -> SpinBox:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var label := Label.new()
	label.text = Locale.t(key)
	UITheme.apply_label(label, true)
	box.add_child(label)
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = minimum
	input.max_value = maximum
	input.value = initial
	input.step = 1
	UITheme.apply_input(input)
	input.value_changed.connect(func(_value): _refresh())
	box.add_child(input)
	return input


func _refresh() -> void:
	if not is_instance_valid(quote_label): return
	var quote := ActionEconomyAnalyzer.quote(int(action_input.value), int(points_input.value), int(mana_input.value), config)
	quote_label.text = Locale.t("economy.quote", [quote.cost, quote.points, quote.mana])
	status_label.text = Locale.t("economy.affordable" if quote.ok else "economy.unaffordable")
	var status_color := UITheme.Tokens.SUCCESS if quote.ok else UITheme.Tokens.WARNING
	status_label.add_theme_color_override("font_color", status_color)


func _resize() -> void:
	if not is_instance_valid(panel): return
	var dimensions := Vector2(720, 520).min(editor.get_viewport_rect().size - Vector2(32, 32))
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2


func close() -> void:
	if is_instance_valid(popup_layer): popup_layer.queue_free()
	popup_layer = null
	panel = null


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(popup_layer) and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

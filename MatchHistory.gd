extends Control

const UITheme = preload("res://UITheme.gd")

var list_box: VBoxContainer
var empty_label: Label
var count_label: Label


func _ready() -> void:
	_build_ui()
	_refresh_list()


func _build_ui() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_right", 52)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var back := Button.new()
	back.text = Locale.t("common.back")
	UITheme.apply_button(back, "secondary")
	back.pressed.connect(func(): UIMotion.change_scene("res://MainMenu.tscn"))
	header.add_child(back)
	var title := Label.new()
	title.text = Locale.t("history.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 32)
	header.add_child(title)
	var clear := Button.new()
	clear.text = Locale.t("history.clear")
	UITheme.apply_button(clear, "danger")
	clear.pressed.connect(_show_clear_confirmation)
	header.add_child(clear)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(count_label, true)
	root.add_child(count_label)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.apply_panel(frame, "dark")
	root.add_child(frame)
	var inner := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		inner.add_theme_constant_override(side, 14)
	frame.add_child(inner)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)
	empty_label = Label.new()
	empty_label.text = Locale.t("history.empty")
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.custom_minimum_size = Vector2(0, 160)
	UITheme.apply_label(empty_label, true)
	list_box.add_child(empty_label)


func _refresh_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	count_label.text = Locale.t("history.count", [PlayerData.match_history.size(), PlayerData.MAX_MATCH_HISTORY])
	if PlayerData.match_history.is_empty():
		empty_label = Label.new()
		empty_label.text = Locale.t("history.empty")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, 160)
		UITheme.apply_label(empty_label, true)
		list_box.add_child(empty_label)
		return
	for entry in PlayerData.match_history:
		list_box.add_child(_make_match_row(entry))


func _make_match_row(entry: Dictionary) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 66)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "%s    %s    %s    %s" % [
		_format_time(int(entry.get("timestamp", 0))),
		_mode_text(str(entry.get("mode", ""))),
		_outcome_text(str(entry.get("outcome", ""))),
		Locale.t("history.turn_hp", [int(entry.get("turns", 0)), int(entry.get("player_hp", 0)), int(entry.get("opponent_hp", 0))]),
	]
	row.tooltip_text = Locale.t("history.open_detail")
	UITheme.apply_button(row, "secondary")
	var outcome := str(entry.get("outcome", ""))
	row.add_theme_color_override("font_color", Color(0.42, 0.95, 0.58) if outcome == "victory" else (Color(1.0, 0.48, 0.45) if outcome in ["defeat", "forfeit"] else Color(0.88, 0.82, 0.66)))
	row.pressed.connect(_show_detail.bind(entry))
	return row


func _show_detail(entry: Dictionary) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_top = -270
	panel.offset_right = 340
	panel.offset_bottom = 270
	UITheme.apply_panel(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "%s · %s" % [_outcome_text(str(entry.get("outcome", ""))), _mode_text(str(entry.get("mode", "")))]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 28)
	box.add_child(title)
	var summary := Label.new()
	summary.text = "%s\n%s\n%s\n%s" % [
		_format_time(int(entry.get("timestamp", 0))),
		Locale.t("history.turn_hp", [int(entry.get("turns", 0)), int(entry.get("player_hp", 0)), int(entry.get("opponent_hp", 0))]),
		Locale.t("history.deck_name", [str(entry.get("deck_name", Locale.t("history.unknown_deck")))]),
		Locale.t("history.version", [str(entry.get("app_version", ""))]),
	]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(summary, true)
	box.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var cards := Label.new()
	cards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var own: Array = entry.get("deck_cards", [])
	var enemy: Array = entry.get("opponent_cards", [])
	cards.text = "%s\n%s\n\n%s\n%s" % [
		Locale.t("history.your_cards"), _card_list_text(own),
		Locale.t("history.opponent_cards"), _card_list_text(enemy),
	]
	UITheme.apply_label(cards)
	scroll.add_child(cards)
	var close := Button.new()
	close.text = Locale.t("battle.close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(close, "secondary")
	close.pressed.connect(layer.queue_free)
	box.add_child(close)
	UITheme.animate_popup_enter(panel)


func _show_clear_confirmation() -> void:
	if PlayerData.match_history.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = Locale.t("history.clear")
	dialog.dialog_text = Locale.t("history.clear_confirm")
	dialog.ok_button_text = Locale.t("common.confirm")
	dialog.cancel_button_text = Locale.t("common.cancel")
	dialog.confirmed.connect(func():
		PlayerData.clear_match_history()
		_refresh_list()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(430, 180))


func _mode_text(mode: String) -> String:
	match mode:
		"online": return Locale.t("result.mode_online")
		"practice": return Locale.t("result.mode_practice")
		"hotseat": return Locale.t("result.mode_hotseat")
	return mode


func _outcome_text(outcome: String) -> String:
	return Locale.t("history.outcome.%s" % outcome)


func _format_time(timestamp: int) -> String:
	if timestamp <= 0:
		return "--"
	var dt := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d  %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]


func _card_list_text(cards: Array) -> String:
	if cards.is_empty():
		return Locale.t("history.cards_unavailable")
	return "、".join(cards) if Locale.language == "zh" else ", ".join(cards)

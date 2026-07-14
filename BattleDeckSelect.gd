extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")

var card_ui_scene = preload("res://CardUI.tscn")

@onready var panel = $Panel
@onready var root_box = $Panel/VBoxContainer
@onready var top_bar = $Panel/VBoxContainer/TopBar
@onready var title_label = $Panel/VBoxContainer/TopBar/TitleLabel
@onready var deck_select = $Panel/VBoxContainer/TopBar/DeckSelect
@onready var scroll_container = $Panel/VBoxContainer/ScrollContainer
@onready var card_grid = $Panel/VBoxContainer/ScrollContainer/CardGrid

var selected_deck_id: String = ""


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_theme()
	_setup_deck_select()
	_apply_texts()
	_refresh_cards()
	_apply_responsive_layout()


func _apply_theme() -> void:
	UITheme.apply_app_background(panel)
	UITheme.apply_panel(panel, "dark")
	UITheme.apply_title(title_label, max(18, int(24 * _ui_scale())))
	UITheme.apply_button($Panel/VBoxContainer/TopBar/ConfirmButton, "primary")
	UITheme.apply_button($Panel/VBoxContainer/TopBar/BackButton, "secondary")
	UITheme.apply_button(deck_select, "secondary")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _apply_texts() -> void:
	match PlayerData.battle_select_mode:
		"hotseat_p2":
			title_label.text = Locale.t("select.player2_title")
		"online":
			title_label.text = Locale.t("select.online_title")
		"practice":
			title_label.text = Locale.t("select.practice_title", [Locale.t("menu.ai_%s" % PlayerData.practice_ai_difficulty)])
		_:
			title_label.text = Locale.t("select.player1_title")


func _setup_deck_select() -> void:
	deck_select.clear()
	for i in range(PlayerData.deck_library.size()):
		var deck: Dictionary = PlayerData.deck_library[i]
		deck_select.add_item(_deck_label(deck), i)
	if PlayerData.deck_library.is_empty():
		selected_deck_id = ""
		return
	selected_deck_id = PlayerData.deck_library[0].get("id", "")
	deck_select.item_selected.connect(func(index: int):
		selected_deck_id = PlayerData.deck_library[index].get("id", "")
		_refresh_cards()
	)


func _deck_label(deck: Dictionary) -> String:
	return "%s (%d)" % [deck.get("name", Locale.t("deck.default_name")), deck.get("cards", []).size()]


func _refresh_cards() -> void:
	for child in card_grid.get_children():
		child.queue_free()
	card_grid.columns = 4
	for card in PlayerData.get_cards_for_deck(selected_deck_id):
		_add_card_box(card)


func _add_card_box(card_data: CardData) -> void:
	var s := _ui_scale()
	var card_width: float = 132.0 * s
	var card_box := PanelContainer.new()
	card_box.custom_minimum_size = Vector2(card_width, 172 * s)
	UITheme.apply_panel(card_box, "soft")
	card_grid.add_child(card_box)
	var box := CenterContainer.new()
	card_box.add_child(box)
	var card_ui_instance = card_ui_scene.instantiate()
	box.add_child(card_ui_instance)
	card_ui_instance.set_card(card_data)
	card_ui_instance.set_actions_visible(false)
	card_ui_instance.apply_ui_scale(s)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var margin: int = max(12, int(24 * s))
	panel.offset_left = margin
	panel.offset_top = margin
	panel.offset_right = -margin
	panel.offset_bottom = -margin
	root_box.add_theme_constant_override("separation", max(6, int(10 * s)))
	top_bar.add_theme_constant_override("separation", max(4, int(8 * s)))
	title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	deck_select.custom_minimum_size = Vector2(220 * s, 0)
	scroll_container.custom_minimum_size = Vector2(0, 540 * s)


func _selected_cards() -> Array:
	var result: Array = []
	for card in PlayerData.get_cards_for_deck(selected_deck_id):
		result.append(card.duplicate_card())
	return result


func _on_confirm_pressed() -> void:
	var cards := _selected_cards()
	if cards.is_empty():
		_show_message(Locale.t("select.need_deck"))
		return
	# hotseat_p2: P1 already configured, skip popup.
	# online: both players configure locally; P1's config is synced to P2 via RPC
	#         after the connection is established (in Lobby/DirectLobby).
	if PlayerData.battle_select_mode == "hotseat_p2":
		_start_battle_with_cards(cards)
		return
	_show_battle_config_popup(cards)


func _start_battle_with_cards(cards: Array) -> void:
	match PlayerData.battle_select_mode:
		"practice":
			PlayerData.battle_mode = "practice"
			PlayerData.battle_deck = cards
			PlayerData.opponent_battle_deck.clear()
			for card in CardDatabase.starter_library():
				PlayerData.opponent_battle_deck.append(card.duplicate_card())
			get_tree().change_scene_to_file("res://Main.tscn")
		"hotseat_p1":
			PlayerData.pending_hotseat_p1_deck = cards
			PlayerData.battle_select_mode = "hotseat_p2"
			get_tree().reload_current_scene()
		"hotseat_p2":
			PlayerData.battle_mode = "hotseat"
			PlayerData.battle_deck = PlayerData.pending_hotseat_p1_deck.duplicate(true)
			PlayerData.opponent_battle_deck = cards
			PlayerData.pending_hotseat_p1_deck.clear()
			get_tree().change_scene_to_file("res://Main.tscn")
		"online":
			PlayerData.battle_deck = cards
			get_tree().change_scene_to_file(PlayerData.battle_select_next_scene)


func _on_back_pressed() -> void:
	if PlayerData.battle_select_mode == "online":
		get_tree().change_scene_to_file("res://MultiplayerMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://MainMenu.tscn")


func _show_battle_config_popup(cards: Array) -> void:
	var popup := UITheme.make_popup_layer(self, 115)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -240
	panel_box.offset_top = -220
	panel_box.offset_right = 240
	panel_box.offset_bottom = 220
	UITheme.apply_popup_frame(panel_box, "gold")
	layer.add_child(panel_box)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel_box.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "战斗参数设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)

	# Row: Mana per turn
	var mana_row := _make_config_spin_row(box, "每回合回费:", PlayerData.battle_config.get("mana_per_turn", 2), 0, 10)
	
	# Row: Draw per turn
	var draw_row := _make_config_spin_row(box, "每回合抽牌:", PlayerData.battle_config.get("draw_per_turn", 2), 1, 6)
	
	# Row: Starting HP
	var hp_row := _make_config_spin_row(box, "初始血量:", PlayerData.battle_config.get("starting_hp", 30), 1, 99)
	
	# Row: Second player extra cards
	var extra_cards_row := _make_config_spin_row(box, "后手额外卡牌:", PlayerData.battle_config.get("second_extra_cards", 0), 0, 5)
	
	# Row: Second player extra mana
	var extra_mana_row := _make_config_spin_row(box, "后手额外圣水:", PlayerData.battle_config.get("second_extra_mana", 0), 0, 10)

	# Row: Death compensation
	var death_comp_check := _make_config_check_row(box, "战败补偿(卡牌死亡抽1张):", PlayerData.battle_config.get("death_compensation", false))

	# Row: Face damage compensation
	var face_comp_check := _make_config_check_row(box, "本体伤害补偿(临时圣水):", PlayerData.battle_config.get("face_damage_compensation", false))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = "开始战斗"
	start_btn.custom_minimum_size = Vector2(140, 36)
	UITheme.apply_button(start_btn, "primary")
	start_btn.pressed.connect(func():
		# Save config
		PlayerData.battle_config["mana_per_turn"] = int(mana_row.get("spin").value)
		PlayerData.battle_config["draw_per_turn"] = int(draw_row.get("spin").value)
		PlayerData.battle_config["starting_hp"] = int(hp_row.get("spin").value)
		PlayerData.battle_config["second_extra_cards"] = int(extra_cards_row.get("spin").value)
		PlayerData.battle_config["second_extra_mana"] = int(extra_mana_row.get("spin").value)
		PlayerData.battle_config["death_compensation"] = death_comp_check.get("check").button_pressed
		PlayerData.battle_config["face_damage_compensation"] = face_comp_check.get("check").button_pressed
		layer.queue_free()
		_start_battle_with_cards(cards)
	)
	btn_row.add_child(start_btn)
	
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.back")
	cancel_btn.custom_minimum_size = Vector2(140, 36)
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(layer.queue_free)
	btn_row.add_child(cancel_btn)


func _make_config_spin_row(parent: VBoxContainer, label_text: String, default_value: int, min_val: int, max_val: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	UITheme.apply_label(lbl)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_value
	spin.custom_minimum_size = Vector2(80, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_input(spin)
	row.add_child(spin)
	parent.add_child(row)
	return {"spin": spin, "row": row}


func _make_config_check_row(parent: VBoxContainer, label_text: String, default_value: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	UITheme.apply_label(lbl)
	row.add_child(lbl)
	var check := CheckBox.new()
	check.button_pressed = default_value
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(check)
	parent.add_child(row)
	return {"check": check, "row": row}


func _show_message(text: String) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -190
	panel_box.offset_top = -90
	panel_box.offset_right = 190
	panel_box.offset_bottom = 90
	UITheme.apply_popup_frame(panel_box, "gold")
	layer.add_child(panel_box)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel_box.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(ok, "primary")
	ok.pressed.connect(layer.queue_free)
	box.add_child(ok)

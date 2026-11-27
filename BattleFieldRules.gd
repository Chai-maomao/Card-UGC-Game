class_name BattleFieldRules
extends RefCounted


static func match_cards() -> Array:
	# The agreed starting pool is public; never enumerate hidden hands/deck order.
	var cards: Array = []
	for deck in [PlayerData.battle_deck,PlayerData.opponent_battle_deck]:
		for card in (deck if not deck.is_empty() else PlayerData.card_library):
			if card is CardData: cards.append(card.duplicate_card())
	if cards.is_empty():
		for card in CardDatabase.player_starters():
			cards.append(card.duplicate_card())
			cards.append(card.duplicate_card())
	cards.sort_custom(func(a,b): return a.card_name.naturalnocasecmp_to(b.card_name)<0)
	return cards


static func build_info(box: VBoxContainer, game, battle: Node, popup: Node) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",12)
	box.add_child(tabs)
	var pages: Array[ScrollContainer] = []
	var buttons: Array[Button] = []
	for key in ["battle.field_rules","battle.match_cards"]:
		var button := Button.new()
		button.text = ("挑战目标" if Locale.language == "zh" else "Challenge objective") if key == "battle.match_cards" and not PlayerData.practice_challenge_id.is_empty() else Locale.t(key)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_button(button,"secondary",false)
		tabs.add_child(button)
		buttons.append(button)
		var page := ScrollContainer.new()
		page.name = "MatchCardScroll" if pages.size()==1 else "MatchRuleScroll"
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(page)
		pages.append(page)
	build(pages[0],game)
	var grid := GridContainer.new()
	grid.name = "MatchCardGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",18)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,10)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages[1].add_child(margin)
	margin.add_child(grid)
	if not PlayerData.practice_challenge_id.is_empty():
		var objective := Label.new()
		objective.text = PracticeChallenges.objective(PlayerData.practice_challenge_id) + "\n\n" + PracticeChallenges.progress(game,PlayerData.practice_challenge_id)
		objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_child(objective)
		grid.hide()
	var starting_cards := match_cards() if PlayerData.practice_challenge_id.is_empty() else []
	if battle.has_method("match_info_cards"):
		var room_cards: Array = battle.match_info_cards()
		if not room_cards.is_empty():
			starting_cards = room_cards
	for card in starting_cards:
		var cell := CenterContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var ui = preload("res://CardUI.tscn").instantiate()
		cell.add_child(ui)
		ui.set_card(card)
		ui.set_battle_layout_preview(true)
		ui.set_meta("suppress_hover_hint",true)
		ui.apply_ui_scale(0.85)
		ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in ui.find_children("*","Control",true,false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inspect := Button.new()
		inspect.name = "InspectMatchCard"
		inspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for state in ["normal","hover","pressed","focus"]: inspect.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		ui.add_child(inspect)
		inspect.pressed.connect(func(): battle.inspect_collection_card(card,ui,popup))
	var fit := func(): grid.columns = maxi(1,mini(6,int((pages[1].size.x-28)/130.0)))
	pages[1].resized.connect(fit)
	for index in range(2):
		buttons[index].pressed.connect(func():
			var changed := not pages[index].visible
			for i in range(2):
				pages[i].visible = i==index
				buttons[i].set_pressed_no_signal(i==index)
			fit.call()
			if changed: UITheme.fade_enter(pages[index], 0.14)
		)
		buttons[index].toggle_mode = true
	pages[1].hide()
	buttons[0].set_pressed_no_signal(true)


static func rows(config: Dictionary) -> Array:
	var result: Array = []
	var clock := preload("res://BattleActionClock.gd")
	var timed := clock.enabled(config)
	result.append([Locale.t("battle_config.action_time_enabled"), _switch_text(timed)])
	if timed:
		result.append([Locale.t("battle_config.action_time_seconds"), str(clock.seconds(config, false))])
		result.append([Locale.t("battle_config.first_action_time_seconds"), str(clock.seconds(config, true))])
	var enabled := config.has("action_base")
	result.append([Locale.t("battle_config.action_enabled"), _switch_text(enabled)])
	var growing := config.has("mana_increment")
	result.append([Locale.t("battle_config.mana_mode"), Locale.t("battle_config.mana_growing" if growing else "battle_config.mana_fixed")])
	for key in PlayerData.DEFAULT_BATTLE_CONFIG:
		if key in clock.KEYS: continue
		if str(key).begins_with("action_") and not enabled: continue
		if key == "draw_pile_ordered":
			if bool(config.get("draw_pile_visible",false)):
				result.append([Locale.t("battle_config.draw_pile_order"),Locale.t("battle_config.pile_ordered" if bool(config.get(key,false)) else "battle_config.pile_random")])
			continue
		var value: Variant = config.get(key, PlayerData.DEFAULT_BATTLE_CONFIG[key])
		if key == "mana_per_turn" and growing:
			result.append([Locale.t("battle_config.mana_initial"), str(value)])
			result.append([Locale.t("battle_config.mana_increment"), str(config["mana_increment"])])
			continue
		result.append([Locale.t("battle_config." + key), _switch_text(value) if value is bool else str(value)])
		if key == "face_damage_compensation" and value:
			var mana := int(config.get("face_damage_compensation_mana", PlayerData.DEFAULT_FACE_DAMAGE_COMPENSATION_MANA))
			result.append([Locale.t("battle_config.face_damage_compensation_mana"), str(mana)])
	return result


static func _switch_text(enabled: bool) -> String:
	return ("开启" if enabled else "关闭") if Locale.language == "zh" else ("On" if enabled else "Off")


static func build(scroll: ScrollContainer, game) -> void:
	var box := VBoxContainer.new()
	box.name = "FieldRuleRows"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	margin.add_child(box)
	var values := rows(game.battle_config)
	values.append(["首回合普通攻击" if Locale.language == "zh" else "First-turn attacks", _switch_text(game.allow_first_turn_attacks)])
	for index in range(values.size()):
		if index > 0:
			var line := HSeparator.new()
			var style := StyleBoxLine.new()
			style.color = UITheme.Tokens.BORDER
			style.thickness = 1
			line.add_theme_stylebox_override("separator", style)
			box.add_child(line)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		box.add_child(row)
		var label := Label.new()
		label.text = values[index][0]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.apply_label(label)
		row.add_child(label)
		var value := Label.new()
		value.text = values[index][1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UITheme.apply_label(value)
		row.add_child(value)

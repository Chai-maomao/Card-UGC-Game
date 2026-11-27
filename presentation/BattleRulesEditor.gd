extends RefCounted

const ActionClock = preload("res://BattleActionClock.gd")

# Both solo preparation and online rooms build this same form.
static func open(parent: Control, config: Dictionary, locked: Callable, on_confirm: Callable, on_close: Callable = Callable(), timing_only: bool = false, party: bool = false) -> CanvasLayer:
	var popup := UITheme.make_popup_layer(parent, 115)
	var layer: CanvasLayer = popup["layer"]
	layer.name = "AdvancedSettings"
	var close := func():
		if on_close.is_valid(): on_close.call()
		else: layer.queue_free()
	var panel_box := Panel.new()
	panel_box.name = "PopupPanel"
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -330
	panel_box.offset_top = -minf(300, parent.get_viewport_rect().size.y * 0.44)
	panel_box.offset_right = 330
	panel_box.offset_bottom = minf(300, parent.get_viewport_rect().size.y * 0.44)
	UITheme.apply_popup_frame(panel_box, "gold", true, true)
	layer.add_child(panel_box)
	var fit := func():
		var half := parent.get_viewport_rect().size*Vector2(0.44,0.43)
		half.x = minf(370,half.x)
		panel_box.offset_left = -half.x
		panel_box.offset_right = half.x
		panel_box.offset_top = -half.y
		panel_box.offset_bottom = half.y
	fit.call()
	parent.resized.connect(fit)
	layer.tree_exiting.connect(func():
		if is_instance_valid(parent) and parent.resized.is_connected(fit): parent.resized.disconnect(fit))
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
	title.text = Locale.t("battle_config.action_time_enabled" if timing_only else "prep.advanced")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)

	var settings_scroll := ScrollContainer.new()
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true
	UITheme.pad_scroll_content(settings_scroll,8)
	box.add_child(settings_scroll)
	var settings_box := VBoxContainer.new()
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_box.add_theme_constant_override("separation", 12)
	settings_scroll.add_child(settings_box)
	var time_toggle := _make_config_check_row(settings_box, Locale.t("battle_config.action_time_enabled"), ActionClock.enabled(config))
	time_toggle.check.name = "ActionTimeEnabledToggle"
	time_toggle.check.disabled = locked.call()
	var time_options := MarginContainer.new()
	time_options.add_theme_constant_override("margin_left", 16)
	time_options.visible = time_toggle.check.button_pressed
	settings_box.add_child(time_options)
	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", 12)
	time_options.add_child(time_box)
	var time_rows: Array[Dictionary] = []
	for i in range(1, ActionClock.KEYS.size()):
		var key: String = ActionClock.KEYS[i]
		var time_row := _make_config_spin_row(time_box, Locale.t("battle_config." + key), ActionClock.seconds(config, i == 2),
			ActionClock.MIN_SECONDS, ActionClock.MAX_SECONDS)
		time_row.spin.name = key
		time_row.spin.editable = not locked.call()
		time_rows.append(time_row)
	time_toggle.check.toggled.connect(time_options.set_visible)
	var other_rules := VBoxContainer.new()
	other_rules.add_theme_constant_override("separation", 12)
	other_rules.visible = not timing_only
	settings_box.add_child(other_rules)
	settings_box = other_rules
	var action_rows := {}
	var action_toggle := _make_config_check_row(settings_box, Locale.t("battle_config.action_enabled"), config.has("action_base"))
	(action_toggle.check as BaseButton).name = "ActionEnabledToggle"
	(action_toggle.check as BaseButton).disabled = locked.call()
	for key in ["action_base", "action_empty_slot_factor", "action_empty_hand_factor", "action_mana_factor"]:
		action_rows[key] = _make_config_spin_row(settings_box, Locale.t("battle_config." + key), config.get(key, PlayerData.DEFAULT_BATTLE_CONFIG[key]), 0, 20, 1.0 if key == "action_base" else 0.5)
		action_rows[key].spin.name = key
		action_rows[key].row.visible = action_toggle.check.button_pressed
	(action_toggle.check as BaseButton).toggled.connect(func(enabled: bool):
		for row in action_rows.values(): row.row.visible = enabled)
	var hint := Label.new()
	hint.text = Locale.t("battle.action_help")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(hint, true)
	settings_box.add_child(hint)
	hint.hide()

	var visibility := _make_config_check_row(settings_box, Locale.t("battle_config.draw_pile_visible"), bool(config.get("draw_pile_visible",false)))
	visibility.check.name = "DrawPileVisibleToggle"
	visibility.check.disabled = locked.call()
	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation",12)
	settings_box.add_child(order_row)
	var order_label := Label.new()
	order_label.text = Locale.t("battle_config.draw_pile_order")
	order_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(order_label)
	order_row.add_child(order_label)
	var order := OptionButton.new()
	order.name = "DrawPileOrderChoice"
	order.add_item(Locale.t("battle_config.pile_random"))
	order.add_item(Locale.t("battle_config.pile_ordered"))
	order.selected = 1 if bool(config.get("draw_pile_ordered",false)) else 0
	order.disabled = locked.call()
	UITheme.apply_button(order,"secondary")
	order_row.add_child(order)
	order_row.visible = visibility.check.button_pressed
	visibility.check.toggled.connect(func(enabled: bool): order_row.visible=enabled)

	var mana_mode_row := HBoxContainer.new()
	mana_mode_row.add_theme_constant_override("separation", 8)
	settings_box.add_child(mana_mode_row)
	var mana_mode_label := Label.new()
	mana_mode_label.text = Locale.t("battle_config.mana_mode")
	mana_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(mana_mode_label)
	mana_mode_row.add_child(mana_mode_label)
	var mana_mode := OptionButton.new()
	mana_mode.name = "ManaRecoveryMode"
	mana_mode.add_item(Locale.t("battle_config.mana_fixed"))
	mana_mode.add_item(Locale.t("battle_config.mana_growing"))
	mana_mode.select(int(config.has("mana_increment")))
	mana_mode.disabled = locked.call()
	UITheme.apply_button(mana_mode, "secondary")
	mana_mode_row.add_child(mana_mode)
	var mana_row := _make_config_spin_row(settings_box, "", config.get("mana_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["mana_per_turn"]), 0, 10)
	mana_row.spin.name = "mana_per_turn"
	var increment_row := _make_config_spin_row(settings_box, Locale.t("battle_config.mana_increment"), config.get("mana_increment", 1), 1, 10)
	increment_row.spin.name = "mana_increment"
	var update_mana_rows := func(index: int):
		mana_row.row.get_child(0).text = Locale.t("battle_config.mana_initial" if index == 1 else "battle_config.mana_per_turn")
		increment_row.row.visible = index == 1
	mana_mode.item_selected.connect(update_mana_rows)
	update_mana_rows.call(mana_mode.selected)

	# Row: Draw per turn
	var draw_row := _make_config_spin_row(settings_box, Locale.t("battle_config.draw_per_turn"), config.get("draw_per_turn", 2), 1, SkillEngine.MAX_HAND_SIZE)
	draw_row.spin.name = "draw_per_turn"

	# Row: Starting HP
	var hp_row := _make_config_spin_row(settings_box, Locale.t("team.starting_hp" if party else "battle_config.starting_hp"), config.get("starting_hp", 30), 1, 99)
	hp_row.spin.name = "starting_hp"

	# Row: Second player extra cards
	var extra_cards_row := _make_config_spin_row(settings_box, Locale.t("battle_config.second_extra_cards"), config.get("second_extra_cards", 0), 0, 5)
	extra_cards_row.spin.name = "second_extra_cards"

	# Row: Second player extra mana
	var extra_mana_row := _make_config_spin_row(settings_box, Locale.t("battle_config.second_extra_mana"), config.get("second_extra_mana", 0), 0, 10)
	extra_mana_row.spin.name = "second_extra_mana"

	# Row: Death compensation
	var death_comp_check := _make_config_check_row(settings_box, Locale.t("battle_config.death_compensation"), config.get("death_compensation", false))

	var face_comp_check := _make_config_check_row(settings_box, Locale.t("battle_config.face_damage_compensation"), config.get("face_damage_compensation", false))
	face_comp_check.check.name = "FaceDamageCompensationToggle"
	var face_comp_details := MarginContainer.new()
	face_comp_details.add_theme_constant_override("margin_left", 16)
	face_comp_details.visible = face_comp_check.check.button_pressed
	settings_box.add_child(face_comp_details)
	var face_comp_options := VBoxContainer.new()
	face_comp_options.add_theme_constant_override("separation", 6)
	face_comp_details.add_child(face_comp_options)
	var face_comp_mana := _make_config_spin_row(face_comp_options, Locale.t("battle_config.face_damage_compensation_mana"),
		config.get("face_damage_compensation_mana", PlayerData.DEFAULT_FACE_DAMAGE_COMPENSATION_MANA),
		1, PlayerData.MAX_FACE_DAMAGE_COMPENSATION_MANA)
	face_comp_mana.spin.name = "face_damage_compensation_mana"
	var face_comp_help := Label.new()
	face_comp_help.text = Locale.t("battle_config.face_damage_compensation_help")
	face_comp_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	face_comp_help.add_theme_font_size_override("font_size", 14)
	UITheme.apply_label(face_comp_help, true)
	face_comp_options.add_child(face_comp_help)
	face_comp_check.check.toggled.connect(func(enabled: bool):
		face_comp_details.visible = enabled
		if enabled:
			await settings_scroll.get_tree().process_frame
			if is_instance_valid(face_comp_details) and face_comp_details.is_visible_in_tree():
				settings_scroll.ensure_control_visible(face_comp_details)
	)
	if party:
		for row in [visibility.row, order_row, extra_cards_row.row, extra_mana_row.row]:
			row.hide()

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = Locale.t("common.confirm")
	start_btn.custom_minimum_size = Vector2(140, 36)
	UITheme.apply_button(start_btn, "primary")
	start_btn.pressed.connect(func():
		if locked.call():
			close.call()
			return
		config[ActionClock.KEYS[0]] = time_toggle.check.button_pressed
		for i in range(time_rows.size()):
			config[ActionClock.KEYS[i + 1]] = int(time_rows[i].spin.value)
		if timing_only:
			on_confirm.call(config)
			close.call()
			return
		for key in action_rows:
			if action_toggle.check.button_pressed:
				config[key] = action_rows[key]["spin"].value
			else:
				config.erase(key)
		config["draw_pile_visible"] = visibility.check.button_pressed
		config["draw_pile_ordered"] = order.selected == 1
		# Save config
		config["mana_per_turn"] = int(mana_row.get("spin").value)
		if mana_mode.selected == 1:
			config["mana_increment"] = int(increment_row.spin.value)
		else:
			config.erase("mana_increment")
		config["draw_per_turn"] = int(draw_row.get("spin").value)
		config["starting_hp"] = int(hp_row.get("spin").value)
		config["second_extra_cards"] = int(extra_cards_row.get("spin").value)
		config["second_extra_mana"] = int(extra_mana_row.get("spin").value)
		config["death_compensation"] = death_comp_check.get("check").button_pressed
		config["face_damage_compensation"] = face_comp_check.get("check").button_pressed
		var compensation_mana := int(face_comp_mana.spin.value)
		if compensation_mana == PlayerData.DEFAULT_FACE_DAMAGE_COMPENSATION_MANA:
			config.erase("face_damage_compensation_mana")
		else:
			config["face_damage_compensation_mana"] = compensation_mana
		on_confirm.call(config)
		close.call()
	)
	btn_row.add_child(start_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.back")
	cancel_btn.custom_minimum_size = Vector2(140, 36)
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(close)
	btn_row.add_child(cancel_btn)
	if locked.call():
		for row in action_rows.values() + [mana_row, increment_row, draw_row, hp_row, extra_cards_row, extra_mana_row, face_comp_mana]: row["spin"].editable = false
		death_comp_check["check"].disabled = true
		face_comp_check["check"].disabled = true
	return layer


static func _make_config_spin_row(parent: VBoxContainer, label_text: String, default_value: float, min_val: float, max_val: float, step_value: float = 1.0) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(lbl)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.step = step_value
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_value
	spin.custom_minimum_size = Vector2(80, 0)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	UITheme.apply_input(spin)
	row.add_child(spin)
	parent.add_child(row)
	return {"spin": spin, "row": row}


static func _make_config_check_row(parent: VBoxContainer, label_text: String, default_value: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(lbl)
	row.add_child(lbl)
	var check := CheckButton.new()
	check.button_pressed = default_value
	check.custom_minimum_size = Vector2(84, 36)
	check.size_flags_horizontal = Control.SIZE_SHRINK_END
	UITheme.apply_button(check, "secondary", false)
	row.add_child(check)
	parent.add_child(row)
	return {"check": check, "row": row}



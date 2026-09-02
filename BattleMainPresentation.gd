extends "res://BattleMainActions.gd"

# ============================================
# Helpers
# ============================================

func _show_direct_damage(result: Dictionary):
	if not result.get("triggered", false):
		return
	var total: int = result["total_damage"]
	if total <= 0:
		return
	await get_tree().create_timer(0.3).timeout
	var vp_size = get_viewport().get_visible_rect().size
	_spawn_combat_text(Vector2(vp_size.x / 2, vp_size.y / 2 - 80), -total, true)


func _apply_deaths():
	var dead = game.cleanup_deaths()
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()
	for idx in dead.get("p1", []):
		var slot_ui = (p_slots if _view_player() == 1 else e_slots)[idx]
		_play_death_feedback(slot_ui)
	for idx in dead.get("p2", []):
		var slot_ui = (e_slots if _view_player() == 1 else p_slots)[idx]
		_play_death_feedback(slot_ui)
	if not dead.get("p1", []).is_empty() or not dead.get("p2", []).is_empty():
		_refresh_hand_ui()


func _play_death_feedback(slot_ui: Control) -> void:
	if slot_ui == null:
		return
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		slot_ui.set_card(null)
		return
	BattleFx.death_fade($CanvasLayer, card_ui, _ui_scale())
	slot_ui.set_card(null)


# Incremental hand refresh: hand mutations preserve order (plays remove a
# card, draws append), so existing card nodes are matched by card reference
# and reused. Only genuinely new cards are instantiated, replaying the entry
# tween for them alone — the old full rebuild re-instantiated the whole hand
# and replayed every entry animation after each action, causing visible
# flicker and frame spikes.
func _refresh_hand_ui():
	var hand: Array = _my_hand()
	var children: Array = hand_container.get_children()
	# Fast path: identical card sequence — only castability tint can drift.
	if children.size() == hand.size():
		var identical := true
		for i in range(hand.size()):
			if children[i].get("current_card_data") != hand[i]:
				identical = false
				break
		if identical:
			for i in range(hand.size()):
				_apply_hand_castability(children[i], hand[i])
			_update_pile_labels()
			return
	# Order-preserving match: for each hand entry, find the first not-yet-used
	# node whose card instance is identical.
	var reuse: Array = []
	var matched := {}
	var search_from := 0
	for i in range(hand.size()):
		var node = null
		for j in range(search_from, children.size()):
			if matched.has(j):
				continue
			if children[j].get("current_card_data") == hand[i]:
				node = children[j]
				matched[j] = true
				search_from = j + 1
				break
		reuse.append(node)
	# Drop unmatched nodes (played/left the hand).
	for j in range(children.size()):
		if not matched.has(j):
			hand_container.remove_child(children[j])
			children[j].queue_free()
	for i in range(hand.size()):
		var card_data: CardData = hand[i]
		var card_ui = reuse[i]
		if card_ui == null:
			card_ui = card_ui_scene.instantiate()
			hand_container.add_child(card_ui)
			card_ui.set_card(card_data)
			_scale_control(card_ui, BASE_CARD_SIZE)
			card_ui.is_hand_card = true
			_connect_hand_card_signals(card_ui)
			_play_hand_card_enter_feedback(card_ui)
		else:
			# Reused node: refresh texts only (cost/charm state may have
			# changed in place); skip entry feedback to avoid flicker.
			card_ui.set_card(card_data)
		_apply_hand_castability(card_ui, card_data)
	_update_pile_labels()


# Hand cards show a green cost when affordable now, red when mana is
# insufficient. Charmed cards keep their own green "免费" display. The mana
# basis is the hand owner's field (view player), not the acting player's.
func _apply_hand_castability(card_ui, card_data: CardData) -> void:
	if card_data == null or card_data.is_charmed():
		return
	var affordable: bool = _field_for_player(_view_player()).get_total_mana() >= card_data.cost
	var color := Color(0.4, 1.0, 0.5) if affordable else Color(1.0, 0.35, 0.3)
	# Re-applying the same theme override marks the label dirty every refresh;
	# skip when the cached tint still matches (CardUI invalidates on set_card).
	if color.is_equal_approx(card_ui.get("_last_cost_color")):
		return
	card_ui.set("_last_cost_color", color)
	var cost_label = card_ui.get("cost_label")
	if cost_label:
		cost_label.add_theme_color_override("font_color", color)


# Signals are bound to the node itself (not a hand index) so hand nodes can be
# reused across incremental refreshes without re-connecting.
func _connect_hand_card_signals(card_ui) -> void:
	card_ui.skill1_requested.connect(_on_hand_card_skill_activated.bind(card_ui, SpellRules.CAST_SKILL_INDEX))


func _hand_index_of(card_ui) -> int:
	if hand_container == null or card_ui == null or not is_instance_valid(card_ui):
		return -1
	return hand_container.get_children().find(card_ui)


func _play_hand_card_enter_feedback(card_ui: Control) -> void:
	BattleFx.hand_card_enter($CanvasLayer, card_ui, _ui_scale())


func _play_draw_fly_feedback(player: int, count: int) -> void:
	if draw_pile_btn == null or count <= 0:
		return
	var start: Vector2 = draw_pile_btn.global_position + draw_pile_btn.size / 2
	var target: Vector2 = _draw_fly_target_for_player(player)
	for i in range(count):
		_spawn_draw_fly_card(start, target, i)


func _play_opening_draw_feedback() -> void:
	await get_tree().process_frame
	_play_draw_fly_feedback(1, min(3, game.player_hand.size()))
	_play_draw_fly_feedback(2, min(3, game.player2_hand.size()))


func _draw_fly_target_for_player(player: int) -> Vector2:
	if player == _view_player():
		return hand_container.global_position + Vector2(hand_container.size.x * 0.5, hand_container.size.y * 0.35)
	var enemy_slots: Array = enemy_side_ui.get_children()
	if enemy_slots.size() > 0:
		var first: Control = enemy_slots[0]
		var last: Control = enemy_slots[enemy_slots.size() - 1]
		var left: float = first.global_position.x
		var right: float = last.global_position.x + last.size.x
		return Vector2((left + right) * 0.5, first.global_position.y - 28 * _ui_scale())
	return enemy_side_ui.global_position + enemy_side_ui.size / 2


func _spawn_draw_fly_card(start: Vector2, target: Vector2, index: int) -> void:
	BattleFx.spawn_draw_fly_card($CanvasLayer, start, target, index, _ui_scale())


func _play_discard_feedback() -> void:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target == null or not is_instance_valid(target):
		return
	var base_modulate: Color = target.modulate
	var base_scale: Vector2 = target.scale
	var center: Vector2 = target.global_position + target.size / 2
	_spawn_combat_text(center + Vector2(0, -10), 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(target, "modulate", Color(0.7, 1.0, 0.72, 1.0), 0.08)
	twn.tween_property(target, "scale", base_scale * 1.04, 0.08)
	twn.tween_property(target, "modulate", base_modulate, 0.18).set_delay(0.08)
	twn.tween_property(target, "scale", base_scale, 0.18).set_delay(0.08)


func _check_and_show_game_over() -> bool:
	var result: String = game.check_game_over()
	if result == "":
		return false
	_show_result(result)
	return true


func _show_result(result: String):
	if battle_finished:
		return
	battle_finished = true
	practice_ai_running = false
	cancel_attack()
	NetworkManager.clear_room_session()
	if _end_turn_pulse and _end_turn_pulse.is_valid():
		_end_turn_pulse.kill()
		_end_turn_pulse = null
	if end_turn_button:
		end_turn_button.scale = Vector2.ONE
	if turn_label:
		turn_label.text = "[ %s ]" % _result_title(result)
	if end_turn_button:
		end_turn_button.disabled = true
	_show_battle_result_page(result)

# ============================================
# Skill interaction handlers (view discard/deck, zero cost)
# ============================================

func _on_shuffle_discard_into_deck() -> void:
	if game.shared_discard.is_empty():
		return
	game.shared_deck = game.shared_discard.duplicate()
	game.shared_discard.clear()
	game._shuffle_shared_deck()
	print("[Main] Discard shuffled into deck (%d cards)" % game.shared_deck.size())


func _on_view_discard_select(count: int, draw_count: int, current_player: int, hand: Array) -> void:
	if game.shared_discard.is_empty():
		return
	var cards: Array = game.shared_discard
	if draw_count > 0:
		cards = cards.slice(0, min(draw_count, cards.size()))
	_show_pile_selection_popup(cards, count, "discard", hand, current_player)


func _on_view_deck_select(count: int, draw_count: int, current_player: int, hand: Array) -> void:
	if game.shared_deck.is_empty():
		return
	var draw_n: int = draw_count if draw_count > 0 else count * 2
	var display_cards: Array = game.shared_deck.slice(0, min(draw_n, game.shared_deck.size()))
	_show_pile_selection_popup(display_cards, count, "deck", hand, current_player)


func _on_make_zero_cost_select(count: int, _current_player: int, hand: Array, target: String, _random_count: int) -> void:
	var candidates: Array = []
	for card in hand:
		if card is CardData and card.cost > 0 and not card.zero_cost_until_deploy:
			candidates.append(card)
	if candidates.is_empty():
		return
	# For SIDES, player picks 1 card (neighbors auto-included)
	var pick_count: int = 1 if target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES] else min(count, candidates.size())
	_show_zero_cost_selection_popup(candidates, pick_count, hand, target)


func _show_pile_selection_popup(cards: Array, count: int, source: String, hand: Array, _player: int) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320
	panel.offset_top = -300
	panel.offset_right = 320
	panel.offset_bottom = 300
	panel.clip_contents = true
	UITheme.apply_popup_frame(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	var max_slots := SkillEngine.MAX_HAND_SIZE - hand.size()
	var source_label: String = Locale.t("battle.draw_pile") if source == "deck" else Locale.t("battle.discard_pile")
	title.text = Locale.t("battle.choose_keep") + (" (%s)" % source_label)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 18)
	box.add_child(title)
	var hint := Label.new()
	hint.text = Locale.t("battle.hand_remaining") % [max_slots, min(count, max_slots)]
	UITheme.apply_label(hint, true)
	box.add_child(hint)

	var selected_indices: Dictionary = {}
	var grid_scroll: ScrollContainer = ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.custom_minimum_size = Vector2(0, 300 * _ui_scale())
	box.add_child(grid_scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(grid)

	for i in range(cards.size()):
		var card: CardData = cards[i]
		var card_box := VBoxContainer.new()
		card_box.custom_minimum_size = Vector2(100, 140) * _ui_scale()
		card_box.add_theme_constant_override("separation", 2)
		var card_ui := card_ui_scene.instantiate()
		card_ui.set_card(card)
		card_ui.apply_ui_scale(_ui_scale() * 0.7)
		card_ui.set_skill_preview_visible(true)
		card_box.add_child(card_ui)
		var check := CheckBox.new()
		check.text = card.card_name
		check.clip_text = true
		check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		check.toggled.connect(func(pressed: bool):
			if pressed:
				if selected_indices.size() >= count:
					check.button_pressed = false
					return
				selected_indices[i] = true
			else:
				selected_indices.erase(i)
		)
		card_box.add_child(check)
		grid.add_child(card_box)

	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.confirm")
	confirm_btn.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(confirm_btn, "primary")
	confirm_btn.pressed.connect(func():
		if selected_indices.is_empty():
			return
		layer.queue_free()
		for idx in selected_indices.keys():
			if hand.size() >= SkillEngine.MAX_HAND_SIZE:
				break
			var chosen: CardData = cards[int(idx)]
			hand.append(chosen.duplicate_card() if source == "deck" else chosen)
			if source == "deck":
				game.shared_deck.erase(chosen)
			elif source == "discard":
				game.shared_discard.erase(chosen)
		_refresh_hand_ui()
		update_entire_screen()
	)
	box.add_child(confirm_btn)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(layer.queue_free)
	box.add_child(close_btn)


func _show_zero_cost_selection_popup(candidates: Array, count: int, hand: Array = [], target: String = SkillEngine.TARGET_SELF) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -240
	panel.offset_right = 280
	panel.offset_bottom = 240
	panel.clip_contents = true
	UITheme.apply_popup_frame(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var include_sides: bool = target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES]
	var title := Label.new()
	if include_sides:
		title.text = Locale.t("battle.zero_cost_title_sides")
	else:
		title.text = Locale.t("battle.zero_cost_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 16)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var grid_scroll: ScrollContainer = ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.custom_minimum_size = Vector2(0, 220 * _ui_scale())
	grid_scroll.add_child(grid)
	box.add_child(grid_scroll)

	var selected_indices: Dictionary = {}
	for i in range(min(candidates.size(), 8)):
		var card: CardData = candidates[i]
		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 2)
		var card_ui := card_ui_scene.instantiate()
		card_ui.set_card(card)
		card_ui.apply_ui_scale(_ui_scale() * 0.7)
		card_ui.set_skill_preview_visible(true)
		card_box.add_child(card_ui)
		var check := CheckBox.new()
		check.text = card.card_name
		check.clip_text = true
		check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		check.toggled.connect(func(pressed: bool):
			if pressed:
				if selected_indices.size() >= count:
					check.button_pressed = false
					return
				selected_indices[i] = true
			else:
				selected_indices.erase(i)
		)
		card_box.add_child(check)
		grid.add_child(card_box)

	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.confirm")
	confirm_btn.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(confirm_btn, "primary")
	confirm_btn.pressed.connect(func():
		if selected_indices.is_empty():
			return
		layer.queue_free()
		if include_sides and not hand.is_empty():
			# SIDES: apply to chosen card plus its hand neighbors
			var applied: Array = []
			for idx in selected_indices.keys():
				var chosen: CardData = candidates[int(idx)]
				var hand_idx: int = hand.find(chosen)
				if hand_idx >= 0 and not (chosen in applied):
					applied.append(chosen)
					for offset in [-1, 1]:
						var adj_idx : int = hand_idx + offset
						if adj_idx >= 0 and adj_idx < hand.size():
							var adj_card: CardData = hand[adj_idx]
							if adj_card is CardData and adj_card.cost > 0 and not adj_card.zero_cost_until_deploy and not (adj_card in applied):
								applied.append(adj_card)
			for card in applied:
				card.cost = 0
				card.zero_cost_until_deploy = true
		else:
			for idx in selected_indices.keys():
				var chosen: CardData = candidates[int(idx)]
				chosen.cost = 0
				chosen.zero_cost_until_deploy = true
		_refresh_hand_ui()
		update_entire_screen()
	)
	box.add_child(confirm_btn)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(layer.queue_free)
	box.add_child(close_btn)


func _show_disconnect_result_page(resume_sync_failed: bool = false) -> void:
	var old_layer := $CanvasLayer.get_node_or_null("BattleResultLayer")
	if old_layer:
		old_layer.queue_free()
	var layer := Control.new()
	layer.name = "BattleResultLayer"
	_disconnect_overlay = layer
	layer.anchor_right = 1.0
	layer.anchor_bottom = 1.0
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	$CanvasLayer.add_child(layer)
	$CanvasLayer.move_child(layer, $CanvasLayer.get_child_count() - 1)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.015, 0.018, 0.026, 0.86)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 320) * _ui_scale()
	UITheme.apply_panel(panel, "gold")
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := Label.new()
	title.text = Locale.t("result.resume_failed_title") if resume_sync_failed else Locale.t("result.connection_lost_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 36)
	box.add_child(title)

	var body := Label.new()
	body.text = Locale.t("result.resume_failed_body") if resume_sync_failed else Locale.t("result.connection_lost_body")
	body.name = "BodyLabel"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(body, true)
	body.add_theme_font_size_override("font_size", 18)
	box.add_child(body)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 18)
	box.add_child(button_row)

	if resume_sync_failed:
		var retry_btn := Button.new()
		retry_btn.text = Locale.t("result.retry_resume")
		retry_btn.custom_minimum_size = Vector2(170, 48)
		UITheme.apply_button(retry_btn, "primary")
		retry_btn.pressed.connect(_on_resume_retry_pressed)
		button_row.add_child(retry_btn)

	var multiplayer_btn := Button.new()
	multiplayer_btn.text = Locale.t("result.back_multiplayer")
	multiplayer_btn.custom_minimum_size = Vector2(170, 48)
	UITheme.apply_button(multiplayer_btn, "secondary")
	multiplayer_btn.pressed.connect(_on_disconnect_back_multiplayer_pressed)
	button_row.add_child(multiplayer_btn)
	_disconnect_back_btn = multiplayer_btn

	var menu_btn := Button.new()
	menu_btn.text = Locale.t("result.back_menu")
	menu_btn.custom_minimum_size = Vector2(160, 48)
	UITheme.apply_button(menu_btn, "secondary")
	menu_btn.pressed.connect(_on_result_back_menu_pressed)
	button_row.add_child(menu_btn)

	layer.modulate.a = 0.0
	panel.scale = Vector2(0.88, 0.88)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(layer, "modulate:a", 1.0, 0.20)
	twn.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_disconnect_back_multiplayer_pressed() -> void:
	NetworkManager.close_connection()
	UIMotion.change_scene("res://MultiplayerMenu.tscn")


func _result_winner_player(result: String) -> int:
	if result == "p1_wins":
		return 1
	if result == "p2_wins":
		return 2
	return 0


func _did_local_player_win(result: String) -> bool:
	var winner := _result_winner_player(result)
	if winner == 0:
		return false
	if NetworkManager.is_online:
		return winner == my_player
	if PlayerData.battle_mode == "practice":
		return winner == 1
	return winner == _view_player()


func _result_title(result: String) -> String:
	var winner := _result_winner_player(result)
	if NetworkManager.is_online:
		return Locale.t("result.online_win") if _did_local_player_win(result) else Locale.t("result.online_loss")
	if PlayerData.battle_mode == "practice":
		return Locale.t("result.practice_win") if winner == 1 else Locale.t("result.practice_loss")
	if result == "p1_wins":
		return Locale.t("result.p1_wins")
	if result == "p2_wins":
		return Locale.t("result.p2_wins")
	return Locale.t("result.finished")


func _result_mode_text() -> String:
	if NetworkManager.is_online:
		return Locale.t("result.mode_online")
	if PlayerData.battle_mode == "practice":
		return Locale.t("result.mode_practice")
	return Locale.t("result.mode_hotseat")


func _show_battle_result_page(result: String) -> void:
	_record_match_history("victory" if _did_local_player_win(result) else ("finished" if not NetworkManager.is_online and PlayerData.battle_mode != "practice" else "defeat"), result)
	var old_layer := $CanvasLayer.get_node_or_null("BattleResultLayer")
	if old_layer:
		old_layer.queue_free()
	var layer := Control.new()
	layer.name = "BattleResultLayer"
	layer.anchor_right = 1.0
	layer.anchor_bottom = 1.0
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	$CanvasLayer.add_child(layer)
	$CanvasLayer.move_child(layer, $CanvasLayer.get_child_count() - 1)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.015, 0.018, 0.026, 0.82)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 360) * _ui_scale()
	UITheme.apply_panel(panel, "gold")
	center.add_child(panel)
	panel.resized.connect(func():
		panel.pivot_offset = panel.size / 2
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var title := Label.new()
	title.text = _result_title(result)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 42)
	box.add_child(title)

	var outcome := Label.new()
	outcome.text = Locale.t("result.victory") if _did_local_player_win(result) else Locale.t("result.defeat")
	if not NetworkManager.is_online and PlayerData.battle_mode != "practice":
		outcome.text = Locale.t("result.finished")
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(outcome, true)
	outcome.add_theme_font_size_override("font_size", 18)
	box.add_child(outcome)

	var mode_label := Label.new()
	var mode_text := _result_mode_text()
	if PlayerData.battle_mode == "practice":
		mode_text = "%s · %s" % [mode_text, Locale.t("menu.ai_%s" % PlayerData.practice_ai_difficulty)]
	mode_label.text = mode_text
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(mode_label, true)
	box.add_child(mode_label)

	var summary := Label.new()
	summary.text = Locale.t("result.summary", [game.turn_number, game.player_field.player_hp, game.player2_field.player_hp])
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(summary)
	summary.add_theme_font_size_override("font_size", 18)
	box.add_child(summary)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 18)
	box.add_child(button_row)

	if PlayerData.is_card_playtest_active():
		var edit_btn := Button.new()
		edit_btn.text = Locale.t("result.back_editor")
		edit_btn.custom_minimum_size = Vector2(170, 48)
		UITheme.apply_button(edit_btn, "primary")
		edit_btn.pressed.connect(_on_result_back_editor_pressed)
		button_row.add_child(edit_btn)

	var again_btn := Button.new()
	again_btn.text = Locale.t("result.play_again")
	again_btn.custom_minimum_size = Vector2(160, 48)
	UITheme.apply_button(again_btn, "secondary" if PlayerData.is_card_playtest_active() else "primary")
	again_btn.pressed.connect(_on_result_play_again_pressed)
	button_row.add_child(again_btn)

	var menu_btn := Button.new()
	menu_btn.text = Locale.t("result.back_menu")
	menu_btn.custom_minimum_size = Vector2(160, 48)
	UITheme.apply_button(menu_btn, "secondary")
	menu_btn.pressed.connect(_on_result_back_menu_pressed)
	button_row.add_child(menu_btn)

	layer.modulate.a = 0.0
	panel.scale = Vector2(0.88, 0.88)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(layer, "modulate:a", 1.0, 0.20)
	twn.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Victory celebration: confetti rain + warm flash; defeat gets a somber pulse.
	if _did_local_player_win(result):
		BattleFx.victory_confetti($CanvasLayer, _ui_scale(), get_viewport_rect().size)
		BattleFx.screen_flash($CanvasLayer, Color(1.0, 0.86, 0.4), 0.22, 0.5)
	else:
		BattleFx.screen_flash($CanvasLayer, Color(0.4, 0.22, 0.55), 0.16, 0.5)


func _on_result_play_again_pressed() -> void:
	if NetworkManager.is_online:
		NetworkManager.close_connection()
		UIMotion.change_scene("res://MainMenu.tscn")
		return
	get_tree().reload_current_scene()


func _on_result_back_editor_pressed() -> void:
	if PlayerData.restore_after_card_playtest():
		UIMotion.change_scene("res://CardEditor.tscn")


func _on_result_back_menu_pressed() -> void:
	NetworkManager.close_connection()
	UIMotion.change_scene("res://MainMenu.tscn")


# ============================================
# UI refresh
# ============================================

func _update_status_hud(hud: Panel, field: BattleField, hand_size: int, enemy: bool, active: bool) -> void:
	if hud == null or field == null:
		return
	var content := hud.get_node("Margin/Content") as HBoxContainer
	(content.get_node("SideLabel") as Label).text = Locale.t("battle.enemy") if enemy else Locale.t("battle.you")
	(content.get_node("HpLabel") as Label).text = Locale.t("battle.hp_value", [field.player_hp, field.max_player_hp])
	(content.get_node("ManaLabel") as Label).text = Locale.t("battle.mana_value", [field.get_total_mana(), field.max_mana])
	(content.get_node("HandLabel") as Label).text = Locale.t("battle.hand_count", [hand_size, SkillEngine.MAX_HAND_SIZE])

	var hp_bar := content.get_node("HpBar") as ProgressBar
	hp_bar.max_value = max(1, field.max_player_hp)
	hp_bar.value = clamp(field.player_hp, 0, field.max_player_hp)
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	mana_bar.max_value = max(1, max(field.max_mana, field.get_total_mana()))
	mana_bar.value = max(0, field.get_total_mana())
	_apply_status_hud_theme(hud, enemy, active)


func _update_battle_status_huds() -> void:
	if game == null:
		return
	var my_turn_active: bool = game.is_player_turn and game.current_player == _view_player()
	var enemy_turn_active: bool = game.is_player_turn and not my_turn_active
	_update_status_hud(player_status_hud, _my_field(), _my_hand().size(), false, my_turn_active)
	_update_status_hud(enemy_status_hud, _their_field(), _hand_for_player(_opponent_player()).size(), true, enemy_turn_active)


# Coalesces full-screen refreshes: dozens of action paths call this within the
# same frame (play card -> stats -> glows -> turn HUD). Running the whole
# rebuild once per frame (deferred, so it still reflects the final state) cuts
# per-action UI spikes that read as input lag.
func update_entire_screen():
	if battle_finished or _screen_refresh_queued:
		return
	_screen_refresh_queued = true
	_do_update_entire_screen.call_deferred()


func _do_update_entire_screen() -> void:
	_screen_refresh_queued = false
	if battle_finished:
		return
	if turn_label:
		if game.is_player_turn:
			var turn_owner := Locale.t("battle.your_turn") if game.current_player == _view_player() else Locale.t("battle.opponent_turn")
			turn_label.text = "%s  ·  %s" % [Locale.t("battle.turn_label", [game.turn_number]), turn_owner]
		else:
			turn_label.text = Locale.t("battle.switching")
	_update_battle_status_huds()
	if end_turn_button:
		end_turn_button.disabled = match_paused or not game.is_player_turn or (NetworkManager.is_online and (game.current_player != my_player or (not NetworkManager.is_authority() and NetworkManager.pending_game_command_count() > 0)))

	var my_field = _my_field()
	var their_field = _their_field()
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()

	for i in range(5):
		_scale_control(p_slots[i], BASE_SLOT_SIZE)
		_scale_control(e_slots[i], BASE_SLOT_SIZE)
		p_slots[i].set_card(my_field.slots[i])
		if my_field.slots[i] != null and p_slots[i].current_card_ui != null:
			p_slots[i].current_card_ui.set_card(my_field.slots[i])
			_scale_control(p_slots[i].current_card_ui, BASE_CARD_SIZE)

		e_slots[i].set_card(their_field.slots[i])
		if their_field.slots[i] != null and e_slots[i].current_card_ui != null:
			e_slots[i].current_card_ui.set_card(their_field.slots[i])
			_scale_control(e_slots[i].current_card_ui, BASE_CARD_SIZE)
	_toggle_turn_cover()
	_update_action_glows()
	_update_ui_state_motion()
	_refresh_hand_castability()


# Re-applies green/red cost tinting to every hand card so the affordance stays
# correct after mana changes (summons, casts, turn advances, ...).
func _refresh_hand_castability() -> void:
	if hand_container == null or game == null:
		return
	for card_ui in hand_container.get_children():
		var card_data = card_ui.get("current_card_data")
		if card_data != null:
			_apply_hand_castability(card_ui, card_data)


# Attention pulse on the end-turn button while the player can act, and a soft
# pop on the turn label whenever the active turn changes.
func _update_ui_state_motion() -> void:
	if end_turn_button != null:
		var want_pulse: bool = not battle_finished and end_turn_button.visible and not end_turn_button.disabled
		if want_pulse:
			if _end_turn_pulse == null or not _end_turn_pulse.is_valid():
				end_turn_button.pivot_offset = end_turn_button.size / 2
				_end_turn_pulse = create_tween().set_loops()
				_end_turn_pulse.tween_property(end_turn_button, "scale", Vector2(1.035, 1.035), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				_end_turn_pulse.tween_property(end_turn_button, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			if _end_turn_pulse and _end_turn_pulse.is_valid():
				_end_turn_pulse.kill()
				_end_turn_pulse = null
			end_turn_button.scale = Vector2.ONE
	if turn_label != null and turn_label.text != "" and turn_label.text != _turn_last_text:
		_turn_last_text = turn_label.text
		if _turn_pop_tween and _turn_pop_tween.is_valid():
			_turn_pop_tween.kill()
		turn_label.pivot_offset = turn_label.size / 2
		_turn_pop_tween = create_tween()
		_turn_pop_tween.tween_property(turn_label, "scale", Vector2(1.06, 1.06), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_turn_pop_tween.tween_property(turn_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_delta):
	_process_resume_sync()
	if is_my_turn():
		var source: int = -1
		var from_hand: bool = false
		if current_attacker_idx != -1:
			source = current_attacker_idx
		elif summon_targeting:
			source = summon_source_slot
		elif activate_targeting:
			source = activate_source_slot
		elif cast_targeting or parasite_targeting:
			# Spells / parasites cast from hand: the arrow originates at the hand.
			from_hand = true

		if source != -1 or from_hand:
			var start_pos: Vector2
			if from_hand:
				start_pos = hand_container.global_position + Vector2(hand_container.size.x * 0.5, hand_container.size.y * 0.35)
			else:
				var slot_ui = _my_slots_ui()[source]
				start_pos = slot_ui.global_position + slot_ui.size / 2
			var end_pos = get_global_mouse_position()
			attack_arrow.points = [start_pos, end_pos]
			attack_arrow.visible = true

			var hovered := -1
			for i in range(5):
				var e_slot = _their_slots_ui()[i]
				var rect := Rect2(e_slot.global_position, e_slot.size)
				if rect.has_point(get_global_mouse_position()):
					hovered = i
					break
			# Hand-cast aiming is private; only field-source arrows sync to the opponent.
			if not from_hand and hovered != last_hovered_target:
				last_hovered_target = hovered
				if NetworkManager.is_online:
					NetworkManager.rpc_targeting_arrow.rpc(source, hovered, game.current_player)
		else:
			attack_arrow.visible = false
			last_hovered_target = -1
	else:
		if remote_arrow_source >= 0 and remote_arrow_target >= 0:
			var src_slots = _their_slots_ui()
			var src_ui = src_slots[remote_arrow_source]
			var start_pos = src_ui.global_position + src_ui.size / 2
			var tgt_slots = _my_slots_ui()
			var tgt_ui = tgt_slots[remote_arrow_target]
			var end_pos = tgt_ui.global_position + tgt_ui.size / 2
			attack_arrow.points = [start_pos, end_pos]
			attack_arrow.visible = true
		else:
			attack_arrow.visible = false
	_update_slot_highlights()


# Cyan marks every legal destination; the hovered legal target turns gold.
# Recomputed every frame, so highlights never go stale after cancelling a drag.
func _update_slot_highlights() -> void:
	var my_ui: Array = _my_slots_ui()
	var their_ui: Array = _their_slots_ui()
	var targets: Array = []  # [slots_ui, index, hovered]
	var mouse := get_global_mouse_position()
	if get_viewport().gui_is_dragging():
		# Field moves and minion summons can only land on our empty slots.
		for i in range(my_ui.size()):
			var s: Control = my_ui[i]
			if s.get("current_card_data") == null:
				targets.append([my_ui, i, Rect2(s.global_position, s.size).has_point(mouse)])
	elif current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting:
		var sides: Array = []
		if parasite_targeting:
			sides = [my_ui, their_ui]
		elif _targeting_skill_wants_ally():
			sides = [my_ui]
		else:
			sides = [their_ui]
		for slots_ui in sides:
			var player: int = _view_player() if slots_ui == my_ui else _opponent_player()
			for i in range(slots_ui.size()):
				var s: Control = slots_ui[i]
				var card: CardData = _field_for_player(player).slots[i]
				if card == null:
					continue
				var legal := true
				if slots_ui == their_ui and not parasite_targeting and _their_field().has_any_taunt():
					legal = card.has_taunt()
				if legal:
					targets.append([slots_ui, i, Rect2(s.global_position, s.size).has_point(mouse)])
	for slots_ui in [my_ui, their_ui]:
		for s in slots_ui:
			if s.has_method("set_target_hint"):
				s.set_target_hint(false)
			else:
				s.set_highlighted(false)
	for entry in targets:
		var slot = entry[0][entry[1]]
		if slot.has_method("set_target_hint"):
			slot.set_target_hint(true, bool(entry[2]))
		else:
			slot.set_highlighted(bool(entry[2]))


# Pulsing gold border on friendly cards that can still act this turn.
func _update_action_glows() -> void:
	if battle_finished:
		return
	var my_ui: Array = _my_slots_ui()
	var their_ui: Array = _their_slots_ui()
	for i in range(my_ui.size()):
		my_ui[i].set_action_glow(_card_can_act(_my_field().slots[i]))
	for s in their_ui:
		s.set_action_glow(false)


func _card_can_act(card: CardData) -> bool:
	if card == null or not card.is_alive():
		return false
	if not game.is_player_turn or not is_my_turn():
		return false
	if game.turn_number <= 1:
		return false
	if card.is_silenced() and not card.attack_ignores_silence:
		return false
	if card.has_acted:
		return false
	if card.effective_atk() > 0:
		return true
	for i in range(card.skills.size()):
		if not card.skills_used.has(i):
			return true
	return false

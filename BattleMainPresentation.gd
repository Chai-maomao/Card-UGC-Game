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
				children[i].refresh_cost_display()
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
			_prepare_hand_entry_ui(card_ui, card_data)
		else:
			# Reused node: refresh texts only (cost/charm state may have
			# changed in place); skip entry feedback to avoid flicker.
			card_ui.set_card(card_data)
		_apply_hand_castability(card_ui, card_data)
	_update_pile_labels()


# Challenge retries replace CardData objects wholesale. Force the hand view to
# discard every cached node so no dragged, modified, or removed card face can
# survive into the restored puzzle state.
func reset_hand_ui_from_game_state() -> void:
	if hand_container == null:
		return
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()
	_pending_hand_entry_ids.clear()
	_refresh_hand_ui()


# Only an actual discount is green. Ordinary affordable cards stay white and
# unaffordable cards are red; this keeps "green" semantically unambiguous.
func _apply_hand_castability(card_ui, card_data: CardData) -> void:
	if card_data == null:
		return
	var affordable: bool = _field_for_player(_view_player()).get_total_mana() >= card_data.cost
	var color := Color(0.35, 1.0, 0.48) if card_data.is_cost_reduced() \
		else (Color.WHITE if affordable else Color(1.0, 0.35, 0.3))
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


func _prepare_hand_entry_ui(card_ui: Control, card_data: CardData) -> void:
	if card_data != null and _pending_hand_entry_ids.has(card_data.instance_id):
		_pending_hand_entry_ids.erase(card_data.instance_id)
		card_ui.modulate.a = 0.0
		get_tree().create_timer(0.58).timeout.connect(_reveal_arriving_hand_card.bind(weakref(card_ui)))
		return
	_play_hand_card_enter_feedback(card_ui)


func _reveal_arriving_hand_card(reference: WeakRef) -> void:
	var card_ui: Control = reference.get_ref()
	if card_ui != null and is_instance_valid(card_ui):
		_play_hand_card_enter_feedback(card_ui)


func _on_hand_entry_resolved(card: CardData, player: int, destination: String, source: String, source_meta: Dictionary) -> void:
	if destination == "hand" and player == _view_player():
		_pending_hand_entry_ids[card.instance_id] = true
	_play_hand_resolution_feedback(card, player, destination, source, source_meta)
	if destination == "discard":
		_spawn_toast(Locale.t("tip.hand_overflow", [card.card_name]), "warn", 2.0)
	var network_meta := source_meta.duplicate(true)
	# Screen coordinates are local to one client's layout/viewpoint. The remote
	# peer reconstructs a correct source from player + slot instead.
	network_meta.erase("source_position")
	_record_feedback_event("hand_entry", player, -1, {
		"destination": destination,
		"source": source,
		"source_meta": network_meta,
		"instance_id": card.instance_id,
		"card_name": card.card_name,
	})


func _play_hand_resolution_feedback(card: CardData, player: int, destination: String, source: String, source_meta: Dictionary) -> void:
	var start := _hand_resolution_source_position(player, source, source_meta)
	var target := _draw_fly_target_for_player(player) if destination == "hand" else _discard_fly_target()
	var can_show_face := card != null and (destination == "discard" or player == _view_player()) and (source != "deck" or source_meta.has("source_position"))
	if can_show_face:
		var ghost = card_ui_scene.instantiate()
		ghost.set_card(card)
		ghost.set_battle_layout_preview(true)
		ghost.is_hand_card = false
		ghost.apply_ui_scale(0.52 * _ui_scale())
		_set_ghost_mouse_filter(ghost)
		BattleFx.travel_card_control($CanvasLayer, ghost, start, target, 0, _ui_scale())
	else:
		BattleFx.spawn_draw_fly_card($CanvasLayer, start, target, 0, _ui_scale())
	if destination == "discard":
		get_tree().create_timer(0.46).timeout.connect(_play_overflow_discard_feedback)


func _play_overflow_discard_feedback() -> void:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target == null or not is_instance_valid(target):
		return
	var base_modulate: Color = target.modulate
	var base_scale: Vector2 = target.scale
	var twn := create_tween().set_parallel(true)
	twn.tween_property(target, "modulate", Color(1.0, 0.70, 0.42, 1.0), 0.08)
	twn.tween_property(target, "scale", base_scale * 1.04, 0.08)
	twn.tween_property(target, "modulate", base_modulate, 0.18).set_delay(0.08)
	twn.tween_property(target, "scale", base_scale, 0.18).set_delay(0.08)


func _set_ghost_mouse_filter(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_ghost_mouse_filter(child)


func _hand_resolution_source_position(player: int, source: String, source_meta: Dictionary) -> Vector2:
	var exact = source_meta.get("source_position", null)
	if exact is Vector2 and exact != Vector2.ZERO:
		return exact
	if source == "deck" and draw_pile_btn != null:
		return draw_pile_btn.global_position + draw_pile_btn.size / 2
	if source == "discard" and discard_pile_btn != null:
		return discard_pile_btn.global_position + discard_pile_btn.size / 2
	if source == "field":
		var source_player: int = int(source_meta.get("source_player", player))
		var source_slot: int = int(source_meta.get("source_slot", -1))
		var slot_ui := _slot_ui_for_player(source_player, source_slot)
		if slot_ui != null:
			return slot_ui.global_position + slot_ui.size / 2
	if source == "hand" and player == _view_player():
		var source_id := str(source_meta.get("source_instance_id", ""))
		for index in range(_my_hand().size()):
			var hand_card: CardData = _my_hand()[index]
			if hand_card.instance_id == source_id and index < hand_container.get_child_count():
				var card_ui: Control = hand_container.get_child(index)
				return card_ui.global_position + card_ui.size / 2
	return _draw_fly_target_for_player(player)


func _discard_fly_target() -> Vector2:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target != null:
		return target.global_position + target.size / 2
	return get_viewport_rect().size * Vector2(0.9, 0.8)


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
# Skill interaction handlers (view discard/deck, hand cost reduction)
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


func _on_make_zero_cost_select(reduction: int, cost_mode: String, _current_player: int, hand: Array, target: String, _random_count: int) -> void:
	var candidates: Array = []
	for card in hand:
		if card is CardData and card.cost > 0:
			candidates.append(card)
	if candidates.is_empty():
		return
	_show_zero_cost_selection_popup(candidates, reduction, cost_mode, 1, hand, target)


func _show_pile_selection_popup(cards: Array, count: int, source: String, hand: Array, player: int) -> void:
	var source_label: String = Locale.t("battle.draw_pile") if source == "deck" else Locale.t("battle.discard_pile")
	var limit := mini(count, cards.size())
	if limit <= 0:
		return
	var on_selected := func(selected_cards: Array, source_positions: Array):
		var pile: Array = game.shared_deck if source == "deck" else game.shared_discard
		for index in range(selected_cards.size()):
			var chosen: CardData = selected_cards[index]
			if chosen not in pile:
				continue
			pile.erase(chosen)
			var origin: Vector2 = source_positions[index] if index < source_positions.size() else Vector2.ZERO
			game.resolve_hand_entry_for_player(chosen, source, {
				"source_position": origin,
				"source_instance_id": chosen.instance_id,
			}, player)
		_refresh_hand_ui()
		update_entire_screen()
		if NetworkManager.is_online and NetworkManager.is_authority():
			_commit_authority_state("pile selection")
	preload("res://CardCollectionDialog.gd").show_cards(
		self,
		cards,
		Locale.t("battle.choose_keep") + " (" + source_label + ")",
		limit,
		on_selected,
		true
	)


func _show_zero_cost_selection_popup(candidates: Array, reduction: int, cost_mode: String = SkillRegistry.COST_REDUCTION_TURN,
		count: int = 1, hand: Array = [], target: String = SkillEngine.TARGET_SELF) -> void:
	var include_sides: bool = target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES]
	var actual_hand: Array = hand if not hand.is_empty() else _my_hand()
	var mode_text := Locale.term("cost_reduction_mode", cost_mode)
	var title := Locale.t("battle.reduce_cost_title_sides" if include_sides else "battle.reduce_cost_title", [reduction, mode_text])
	preload("res://CardCollectionDialog.gd").show_cards(self, candidates, title, count,
		func(selected_cards: Array):
			var applied: Array = []
			for chosen: CardData in selected_cards:
				var index := actual_hand.find(chosen)
				if index < 0:
					continue
				if chosen not in applied:
					applied.append(chosen)
				if include_sides:
					for offset in [-1, 1]:
						var adjacent: int = index + offset
						if adjacent >= 0 and adjacent < actual_hand.size():
							var card: CardData = actual_hand[adjacent]
							if card not in applied:
								applied.append(card)
			for card: CardData in applied:
				card.apply_cost_reduction(reduction, cost_mode == SkillRegistry.COST_REDUCTION_PERMANENT)
			_refresh_hand_ui()
			update_entire_screen()
	)


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
	PlayerData.restore_after_card_playtest()
	UIMotion.change_scene("res://MainMenu.tscn")


# ============================================
# UI refresh
# ============================================

func _update_status_hud(hud: Panel, field: BattleField, hand_size: int, enemy: bool, active: bool, player_number: int) -> void:
	if hud == null or field == null:
		return
	var content := hud.get_node("Margin/Content") as HBoxContainer
	(content.get_node("SideLabel") as Label).text = Locale.t("battle.enemy") if enemy else Locale.t("battle.you")
	if not NetworkManager.is_online and PlayerData.battle_mode == "hotseat":
		(content.get_node("SideLabel") as Label).text = Locale.t("battle.hotseat_player", [_opponent_player() if enemy else _view_player()])
	(content.get_node("HpLabel") as Label).text = Locale.t("battle.hp_value", [field.player_hp, field.max_player_hp])
	(content.get_node("ManaLabel") as Label).text = Locale.t("battle.mana_value", [field.get_total_mana(), field.max_mana])
	(content.get_node("HandLabel") as Label).text = Locale.t("battle.hand_count", [hand_size, SkillEngine.MAX_HAND_SIZE])

	var hp_bar := content.get_node("HpBar") as ProgressBar
	hp_bar.max_value = max(1, field.max_player_hp)
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	mana_bar.max_value = max(1, max(field.max_mana, field.get_total_mana()))
	var hp_value: int = clampi(field.player_hp, 0, field.max_player_hp)
	var mana_value: int = maxi(0, field.get_total_mana())
	var hud_key: int = hud.get_instance_id()
	var previous: Dictionary = _status_hud_state.get(hud_key, {})
	var same_player: bool = int(previous.get("player", -1)) == player_number
	var may_animate: bool = same_player and not _suppress_status_feedback_once
	var hp_delta: int = hp_value - int(previous.get("hp", hp_value)) if same_player else 0
	var mana_delta: int = mana_value - int(previous.get("mana", mana_value)) if same_player else 0
	_set_status_bar_value(hp_bar, hp_value, may_animate and hp_delta != 0)
	_set_status_bar_value(mana_bar, mana_value, may_animate and mana_delta > 0)
	if may_animate and hp_delta != 0:
		BattleFx.status_bar_feedback($CanvasLayer, hp_bar, hp_delta, "heal" if hp_delta > 0 else "damage", _ui_scale())
	if may_animate and mana_delta > 0:
		BattleFx.status_bar_feedback($CanvasLayer, mana_bar, mana_delta, "mana", _ui_scale())
	_status_hud_state[hud_key] = {"player": player_number, "hp": hp_value, "mana": mana_value}
	_apply_status_hud_theme(hud, enemy, active)


func _set_status_bar_value(bar: ProgressBar, target_value: float, animate: bool) -> void:
	var key: int = bar.get_instance_id()
	var old_tween: Tween = _status_value_tweens.get(key)
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if not animate:
		bar.value = target_value
		_status_value_tweens.erase(key)
		return
	bar.pivot_offset = bar.size * 0.5
	var twn := create_tween().set_parallel(true)
	twn.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(bar, "value", target_value, 0.38)
	twn.tween_property(bar, "scale", Vector2(1.0, 1.16), 0.09)
	twn.tween_property(bar, "scale", Vector2.ONE, 0.22).set_delay(0.09).set_trans(Tween.TRANS_BACK)
	_status_value_tweens[key] = twn


func _update_battle_status_huds() -> void:
	if game == null:
		return
	var my_turn_active: bool = game.is_player_turn and game.current_player == _view_player()
	var enemy_turn_active: bool = game.is_player_turn and not my_turn_active
	_update_status_hud(player_status_hud, _my_field(), _my_hand().size(), false, my_turn_active, _view_player())
	_update_status_hud(enemy_status_hud, _their_field(), _hand_for_player(_opponent_player()).size(), true, enemy_turn_active, _opponent_player())
	_suppress_status_feedback_once = false


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
			var turn_owner := _turn_owner_text()
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
# A guaranteed lethal outcome overrides both with a red glow. Recomputed every
# frame, so neither target nor lethal highlights can go stale after cancelling.
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
			if s.has_method("set_lethal_hint"):
				s.set_lethal_hint(false)
	for entry in targets:
		var slot = entry[0][entry[1]]
		if slot.has_method("set_target_hint"):
			slot.set_target_hint(true, bool(entry[2]))
		else:
			slot.set_highlighted(bool(entry[2]))
		var target_player: int = _view_player() if entry[0] == my_ui else _opponent_player()
		var target_card: CardData = _field_for_player(target_player).slots[int(entry[1])]
		if slot.has_method("set_lethal_hint") and _targeting_action_can_kill(target_card, target_player, int(entry[1])):
			slot.set_lethal_hint(true)


func _targeting_action_can_kill(target: CardData, target_player: int, target_slot: int) -> bool:
	if target == null or parasite_targeting:
		return false
	if current_attacker_idx >= 0:
		var attacker: CardData = _my_field().slots[current_attacker_idx]
		if attacker == null or target_player != _opponent_player():
			return false
		var damage := attacker.effective_atk()
		damage = maxi(0, int(floor(float(damage) * (1.0 - float(target.get_damage_reduction()) / 100.0))))
		# One directed hit is fully intercepted by the outermost parasite even
		# when its damage exceeds the parasite's remaining HP.
		if ParasiteRules.has_damage_absorber(target) or target.immune_lethal:
			return false
		return damage >= target.hp + target.temp_hp

	var skill := _current_targeting_skill()
	var source := _current_targeting_source_card()
	if skill.is_empty() or source == null:
		return false
	var context: Dictionary = game.make_skill_context_for_player(_view_player(), _current_targeting_source_slot(), target_slot, target_player)
	return SkillEngine.predicts_target_lethal(skill, source, target, context)


func _current_targeting_source_card() -> CardData:
	var source_slot := _current_targeting_source_slot()
	if source_slot >= 0:
		return _my_field().slots[source_slot]
	if cast_targeting:
		var hand := _my_hand()
		return hand[cast_hand_index] if cast_hand_index >= 0 and cast_hand_index < hand.size() else null
	return null


func _current_targeting_source_slot() -> int:
	if summon_targeting:
		return summon_source_slot
	if activate_targeting:
		return activate_source_slot
	return -1


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
	if card.is_silenced() and not card.attack_ignores_silence:
		return false
	if card.has_acted:
		return false
	if game.turn_number > 1 and card.effective_atk() > 0:
		return true
	for i in range(card.skills.size()):
		if not card.skills_used.has(i):
			return true
	return false

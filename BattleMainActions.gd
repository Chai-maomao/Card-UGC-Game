extends "res://presentation/BattleEventCapture.gd"

const BattlePlanner = preload("res://BattleAiPlanner.gd")
const BattleCommand = preload("res://BattleRepro.gd")
const MAX_PENDING_WEB_COMMANDS := 32

var _confirmed_game: RefCounted
var _web_prediction_count := 0
var _online_cost_picker: CanvasLayer


func _bind_battle_inputs() -> void:
	if $CanvasLayer/MainBackground:
		$CanvasLayer/MainBackground.mouse_filter = Control.MOUSE_FILTER_PASS
		$CanvasLayer/MainBackground.gui_input.connect(_on_battle_background_gui_input)

	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()

	for i in range(p_slots.size()):
		p_slots[i].set_visual_variant("player")
		e_slots[i].set_visual_variant("enemy")
		p_slots[i].pressed.connect(_on_player_slot_clicked.bind(i))
		if p_slots[i].has_signal("slot_attack_requested"):
			p_slots[i].slot_attack_requested.connect(_on_attack_requested.bind(i))
		if p_slots[i].has_signal("slot_skill1_requested"):
			p_slots[i].slot_skill1_requested.connect(_on_skill_activated.bind(i, 0))
		if p_slots[i].has_signal("slot_skill2_requested"):
			p_slots[i].slot_skill2_requested.connect(_on_skill_activated.bind(i, 1))
		if p_slots[i].has_signal("slot_skill3_requested"):
			p_slots[i].slot_skill3_requested.connect(_on_skill_activated.bind(i, 2))
		if p_slots[i].has_signal("card_dropped_here"):
			p_slots[i].card_dropped_here.connect(_on_card_drag_summoned.bind(i))

		e_slots[i].pressed.connect(_on_enemy_slot_clicked.bind(i))
		if e_slots[i].has_signal("slot_attack_requested"):
			e_slots[i].slot_attack_requested.connect(_on_attack_requested.bind(i))
		if e_slots[i].has_signal("slot_skill1_requested"):
			e_slots[i].slot_skill1_requested.connect(_on_skill_activated.bind(i, 0))
		if e_slots[i].has_signal("slot_skill2_requested"):
			e_slots[i].slot_skill2_requested.connect(_on_skill_activated.bind(i, 1))
		if e_slots[i].has_signal("slot_skill3_requested"):
			e_slots[i].slot_skill3_requested.connect(_on_skill_activated.bind(i, 2))
		if e_slots[i].has_signal("card_dropped_here"):
			e_slots[i].card_dropped_here.connect(_on_card_drag_cast_on_enemy.bind(i))

	if end_turn_button:
		end_turn_button.text = Locale.t("battle.end_turn")
		end_turn_button.pressed.connect(_on_end_turn_pressed)

	face_mana_button.set_meta("keyword_enabled",true)
	face_mana_button.text = "圣水补付" if Locale.language == "zh" else "Use Elixir"
	face_mana_button.tooltip_text = Locale.t("battle.face_mana_hint")
	face_mana_button.toggled.connect(func(_enabled): update_entire_screen())
	if discard_zone and discard_zone.has_signal("card_discarded"):
		discard_zone.card_discarded.connect(_on_card_discarded)
	if EventBus.has_signal("hp_changed"):
		EventBus.hp_changed.connect(_on_hp_changed)
	if EventBus.has_signal("damage_resolved"):
		EventBus.damage_resolved.connect(_on_damage_resolved)
	if EventBus.has_signal("parasite_damage_resolved"):
		EventBus.parasite_damage_resolved.connect(_on_parasite_damage_resolved)
	if EventBus.has_signal("skill_roll_failed"):
		EventBus.skill_roll_failed.connect(_on_skill_roll_failed)
	EventBus.skill_random_resolved.connect(_on_skill_random_resolved)
	EventBus.attack_declared.connect(_on_random_attack_declared)
	if EventBus.has_signal("skill_safety_limit_hit"):
		EventBus.skill_safety_limit_hit.connect(_on_skill_safety_limit_hit)
	if EventBus.has_signal("skill_effect_started"):
		EventBus.skill_effect_started.connect(_on_skill_effect_started)
	if EventBus.has_signal("skill_effect_resolved"):
		EventBus.skill_effect_resolved.connect(_on_skill_effect_resolved)
	if EventBus.has_signal("first_turn_effect_blocked"):
		EventBus.first_turn_effect_blocked.connect(_on_first_turn_effect_blocked)
	if EventBus.has_signal("shuffle_discard_into_deck"):
		EventBus.shuffle_discard_into_deck.connect(_on_shuffle_discard_into_deck)
	if EventBus.has_signal("view_discard_select"):
		EventBus.view_discard_select.connect(_on_view_discard_select)
	if EventBus.has_signal("view_deck_select"):
		EventBus.view_deck_select.connect(_on_view_deck_select)
	if EventBus.has_signal("make_zero_cost_select"):
		EventBus.make_zero_cost_select.connect(_on_make_zero_cost_select)
	if EventBus.has_signal("hand_entry_resolved"):
		EventBus.hand_entry_resolved.connect(_on_hand_entry_resolved)
	EventBus.enemy_hand_discarded.connect(_on_enemy_hand_discarded)


func _predict_web_command(_kind: String, _payload: Dictionary, _player: int) -> bool:
	return false


func _has_online_prediction() -> bool:
	return PlayerData.is_online_battle()


func _deployment_preview() -> Dictionary:
	return {"slots": _my_field().slots, "hand": _my_hand(), "mana": _my_field().get_total_mana()}


func _visible_player_slots() -> Array:
	return _my_field().slots


func _send_remote_intent(kind: String, payload: Dictionary) -> String:
	if _waiting_for_room_link() or _waiting_for_action_state():
		return ""
	var pending := NetworkManager.pending_game_command_count()
	if pending >= MAX_PENDING_WEB_COMMANDS or (pending > 0 and not _can_continue_web_turn()):
		_show_toast("tip.command_pending")
		return ""
	var player: int = game.current_player
	var revision: int = game.state_revision
	var previous_game: RefCounted
	# End-turn snapshots include hero strikes: keep the outgoing board visible
	# until their presentation completes instead of predicting the side switch.
	if _has_online_prediction() and not NetworkManager.is_authority() and kind != "end_turn":
		previous_game = game
		if not _predict_web_command(kind, payload, player):
			return ""
		payload = payload.duplicate()
		match kind:
			"move", "summon", "attack", "discard", "summon_skill":
				payload["local_feedback"] = "skill" if kind == "summon_skill" else kind
			"activate_skill":
				var source := int(payload.get("slot_index", -1))
				if source >= 0:
					payload["local_feedback"] = "skill"
				elif source <= -1000 and source > -2000:
					payload["local_feedback"] = "cast"
	var command_id := NetworkManager.send_game_intent(kind, payload, player, revision)
	if command_id.is_empty():
		if previous_game != null:
			game = previous_game
			_refresh_hand_ui()
		_dismiss_command_prompt(_command_send_failure_prompt)
		_command_send_failure_prompt = weakref(_spawn_toast(Locale.t("tip.command_not_sent"), "warn"))
		update_entire_screen()
		return ""
	_dismiss_command_prompt(_command_result_prompt)
	_command_result_prompt = null
	_dismiss_command_prompt(_command_send_failure_prompt)
	_command_send_failure_prompt = null
	if previous_game != null:
		if _confirmed_game == null:
			_confirmed_game = previous_game
		_web_prediction_count += 1
	_network_command_phase = "sent"
	_refresh_hand_ui()
	update_entire_screen()
	_play_web_prediction_feedback(payload)
	if kind == "summon" and _confirmed_game != null:
		_resume_auto_summon_targeting.call_deferred(int(payload.get("slot_index", -1)))
	return command_id


func _can_continue_web_turn() -> bool:
	return _confirmed_game != null and _web_prediction_count == NetworkManager.pending_game_command_count()


func _play_web_prediction_feedback(payload: Dictionary) -> void:
	match str(payload.get("local_feedback", "")):
		"move":
			_play_move_feedback(_view_player(), int(payload["source_slot"]), int(payload["target_slot"]))
		"summon":
			_play_summon_feedback(_slot_ui_for_player(_view_player(), int(payload["slot_index"])))
		"attack":
			_play_attack_feedback(_view_player(), int(payload["source_slot"]), int(payload["target_slot"]))
		"skill":
			_play_skill_cast_feedback(_view_player(), int(payload["slot_index"]))
		"cast":
			_play_skill_cast_feedback(_view_player(), -1)
		"discard":
			_play_discard_feedback(get_global_mouse_position())


func _restore_confirmed_game() -> void:
	if _confirmed_game != null:
		game = _confirmed_game
		_confirmed_game = null
	_web_prediction_count = 0


func _turn_slot_checkpoint(slots: Array) -> String:
	var identities: Array[String] = []
	for card: CardData in slots:
		identities.append(card.instance_id if card != null else "")
	return BattleCommand.hash_state({"turn": game.turn_number, "player": game.current_player, "slots": identities})


func _web_turn_hash() -> String:
	var state: Dictionary = game.export_initial_state()
	_strip_local_art_paths(state)
	return BattleCommand.hash_state(state)


func _strip_local_art_paths(value: Variant) -> void:
	if value is Dictionary:
		value.erase("art_path")
		value.erase("damaged_art_path")
		for child in value.values():
			_strip_local_art_paths(child)
	elif value is Array:
		for child in value:
			_strip_local_art_paths(child)

# ============================================
# Misc
# ============================================

func _on_card_discarded(card_data: CardData, drop_position: Vector2 = Vector2.INF):
	if not is_my_turn(): return
	if not _tutorial_allows("discard"):
		return
	var card_location := _find_card_location(card_data)
	if drop_position == Vector2.INF: drop_position = get_global_mouse_position()
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_discard(card_location["location"], card_location["index"], game.current_player, drop_position)
		else:
			_send_remote_intent("discard", {"location": card_location["location"], "index": card_location["index"]})
		return
	var refund: int = game.discard_card_with_refund(card_data)
	if refund >= 0:
		_play_discard_feedback(drop_position)
		_show_combat_broadcast(Locale.t(_discard_broadcast_key(refund)))
		_refresh_hand_ui()
		update_entire_screen()


func _discard_broadcast_key(refund: int) -> String:
	return "tip.discard_mana" if refund > 0 else "tip.discard_mana_full"


func _on_battle_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not (current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting):
			return
		if _point_is_over_battle_slot(get_global_mouse_position()):
			return
		cancel_attack()
		update_entire_screen()


func _point_is_over_battle_slot(point: Vector2) -> bool:
	for slot in _my_slots_ui() + _their_slots_ui():
		if slot is Control and Rect2(slot.global_position, slot.size).has_point(point):
			return true
	return false


func _skill_needs_targeting(skill: Dictionary) -> bool:
	return SpellRules.needs_target(skill)


func _manual_target_side(skill: Dictionary) -> String:
	return SpellRules.manual_target_side(skill)


func _manual_target_card_for_skill(skill: Dictionary, target_slot: int, target_player: int = 0) -> CardData:
	var resolved_player := target_player if target_player in [1, 2] else SpellRules.default_target_player(skill, game.current_player)
	var field := _field_for_player(resolved_player)
	return field.slots[target_slot] if target_slot >= 0 and target_slot < field.slots.size() else null

# ============================================
# Splash art
# ============================================

func _show_splash(card: CardData, skill_name: String = "") -> void:
	if card == null:
		return
	if splash_tween and splash_tween.is_valid():
		splash_tween.kill()
	splash_panel.bind(card,skill_name)
	# Restart from outside the left edge; an interrupted reveal must never
	# leave the previous card or an old exit tween on screen.
	splash_slide_progress = 0.0
	_layout_splash_panel()
	splash_panel.show()
	splash_panel.modulate.a = 1.0
	splash_tween = create_tween()
	splash_tween.tween_property(self, "splash_slide_progress", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	splash_tween.tween_interval(0.55)
	splash_tween.tween_property(self, "splash_slide_progress", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	splash_tween.tween_callback(func():
		splash_panel.modulate.a = 0.0
		splash_panel.hide()
	)

# ============================================
# Summon
# ============================================

func _summon_skill_is_pending(card: CardData, skill_index: int) -> bool:
	if card == null or not card.is_alive() or not card.summoned_this_turn:
		return false
	if skill_index < 0 or skill_index >= card.skills.size() or card.skills_used.has(skill_index):
		return false
	var skill: Dictionary = card.skills[skill_index]
	if str(skill.get("trigger", "")) != SkillEngine.TRIGGER_ON_SUMMON:
		return false
	if card.skills_disabled():
		return false
	if not SkillEngine.has_uses_remaining(card, skill, skill_index):
		return false
	return game.turn_number > 1 or not SkillRegistry.skill_changes_enemy_hp_or_presence(skill)


func _summon_skill_has_live_manual_target(skill: Dictionary, player: int) -> bool:
	if not _skill_needs_targeting(skill):
		return false
	var target_player := player if _manual_target_side(skill) == SkillEngine.TARGET_SIDE_ALLY else 3 - player
	var target_field := _field_for_player(target_player)
	for candidate in target_field.slots:
		if candidate != null and candidate.is_alive():
			return true
	return false


func _resolve_local_summon_skill(slot_index: int, skill_index: int, target_slot: int = -1, target_player: int = 0) -> void:
	var source_card: CardData = _my_field().slots[slot_index] if slot_index >= 0 and slot_index < _my_field().slots.size() else null
	if not _summon_skill_is_pending(source_card, skill_index):
		return
	var skill: Dictionary = source_card.skills[skill_index]
	var resolved_target_player := target_player if target_player in [1, 2] else _opponent_player()
	var target_field := _field_for_player(resolved_target_player)
	var target_card: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	source_card.skills_used.append(skill_index)
	_begin_action_broadcast("summon_skill", game.current_player, source_card.card_name, target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	game.trigger_summon_skills(slot_index, target_slot, skill_index, resolved_target_player)
	_finish_action_broadcast()
	_play_skill_cast_feedback(game.current_player, slot_index, skill_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()


func _auto_resolve_local_summon_skills(slot_index: int) -> void:
	var card: CardData = _my_field().slots[slot_index] if slot_index >= 0 and slot_index < _my_field().slots.size() else null
	if card == null:
		return
	for skill_index in range(card.skills.size()):
		if not _summon_skill_is_pending(card, skill_index):
			continue
		var skill: Dictionary = card.skills[skill_index]
		# Choice-requiring battlecries open targeting immediately. If there is no
		# legal target, the trigger still resolves (and harmlessly fizzles).
		if _skill_needs_targeting(skill) and _summon_skill_has_live_manual_target(skill, game.current_player):
			continue
		_resolve_local_summon_skill(slot_index, skill_index)
		card = _my_field().slots[slot_index]
		if card == null:
			break
	_resume_auto_summon_targeting.call_deferred(slot_index)


func _resume_auto_summon_targeting(preferred_slot: int = -1) -> void:
	if not game.is_player_turn or not is_my_turn() or current_attacker_idx != -1 \
			or summon_targeting or activate_targeting or cast_targeting or parasite_targeting:
		return
	var slots: Array = []
	if preferred_slot >= 0:
		slots.append(preferred_slot)
	for slot in range(_my_field().slots.size()):
		if slot != preferred_slot:
			slots.append(slot)
	for slot_value in slots:
		var slot_index := int(slot_value)
		var card: CardData = _my_field().slots[slot_index]
		if card == null:
			continue
		for skill_index in range(card.skills.size()):
			if not _summon_skill_is_pending(card, skill_index):
				continue
			var skill: Dictionary = card.skills[skill_index]
			if not _skill_needs_targeting(skill) or not _summon_skill_has_live_manual_target(skill, game.current_player):
				continue
			summon_targeting = true
			summon_source_slot = slot_index
			summon_skill_idx = skill_index
			if attack_arrow:
				attack_arrow.visible = true
			_sync_targeting_state()
			update_entire_screen()
			return

func _on_card_drag_summoned(card_data, origin_ui, slot_index: int):
	card_data = card_data as CardData
	if card_data == null:
		return
	if not game.is_player_turn or not is_my_turn():
		return
	if not _tutorial_allows("summon", {"slot": slot_index}):
		return

	var their_field = _their_field()
	for i in range(5):
		if their_field.slots[i] == card_data:
			return

	var field = _my_field()
	var visible_slots := _visible_player_slots()

	var source_slot := visible_slots.find(card_data)

	if source_slot >= 0:
		if slot_index == source_slot or slot_index < 0 or slot_index >= visible_slots.size():
			return
		if PlayerData.is_online_battle():
			if NetworkManager.is_authority():
				_host_apply_move(source_slot, slot_index, game.current_player)
			else:
				_send_remote_intent("move", {"source_slot": source_slot, "target_slot": slot_index})
			return
		var displaced: CardData = field.slots[slot_index]
		field.slots[slot_index] = card_data
		field.slots[source_slot] = displaced
		_play_move_feedback(_view_player(), source_slot, slot_index)
		update_entire_screen()
		return

	var hand_index := _my_hand().find(card_data)
	if card_data.is_parasite():
		_execute_parasite_attach(hand_index, _view_player(), slot_index)
		return
	if card_data.cost > field.get_total_mana():
		_show_toast("tip.insufficient_mana")
		return
	if card_data.is_spell():
		_on_card_drag_cast(card_data, origin_ui, hand_index, slot_index, _view_player())
		return
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_summon(hand_index, slot_index, game.current_player)
		else:
			_send_remote_intent("summon", {"hand_index": hand_index, "slot_index": slot_index})
		return

	var ok = game.summon_card(card_data, slot_index)
	if not ok:
		return
	if origin_ui and is_instance_valid(origin_ui):
		origin_ui.queue_free()

	_refresh_hand_ui()
	update_entire_screen()
	_play_summon_feedback(_slot_ui_for_player(_view_player(), slot_index))
	_auto_resolve_local_summon_skills(slot_index)
	_tutorial_notify("summon", {"slot": slot_index})

# ============================================
# Spell cast (from hand)
# ============================================

# Called when a spell or parasite card's skill button is clicked in hand.
func _on_hand_card_skill_activated(card_ui, skill_index: int = SpellRules.CAST_SKILL_INDEX) -> void:
	if not is_my_turn():
		return
	cancel_attack()
	var hand_index := _hand_index_of(card_ui)
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: CardData = hand[hand_index]
	# Spell and parasite chips are descriptive only. Their gameplay gesture is
	# dragging the card to a battlefield slot, never pressing the chip.
	if card != null and (card.is_spell() or card.is_parasite()):
		return


func _start_parasite_attach_from_hand(hand_index: int) -> void:
	if not is_my_turn():
		return
	cancel_attack()
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_data: CardData = hand[hand_index]
	var attach_check: Dictionary = ParasiteRules.can_attach(card_data, _first_available_parasite_target(), game.active_field().get_total_mana())
	if not attach_check.get("ok", false) and attach_check.get("reason", "") == ParasiteRules.REASON_NO_MANA:
		_show_toast("tip.insufficient_mana")
		return
	parasite_targeting = true
	parasite_hand_index = hand_index
	if attack_arrow:
		attack_arrow.visible = true
	_sync_targeting_state()
	update_entire_screen()


func _first_available_parasite_target() -> CardData:
	for field in [_my_field(), _their_field()]:
		for card in field.slots:
			if card != null and card.is_alive():
				return card
	return null


func _start_spell_cast_from_hand(hand_index: int, skill_index: int = SpellRules.CAST_SKILL_INDEX) -> void:
	if not is_my_turn():
		return
	cancel_attack()
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_data: CardData = hand[hand_index]
	var cast_check: Dictionary = SpellRules.can_cast(card_data, game.active_field().get_total_mana(), skill_index, game.turn_number)
	if not cast_check.get("ok", false):
		if cast_check.get("reason", "") == SpellRules.REASON_NO_MANA:
			_show_toast("tip.insufficient_mana")
		elif cast_check.get("reason", "") == SpellRules.REASON_ENEMY_TARGET_TURN_ONE:
			_show_toast("tip.no_enemy_skill_turn1")
		return
	if cast_check.get("needs_target", false):
		cast_targeting = true
		cast_hand_index = hand_index
		cast_skill_index = skill_index
		if attack_arrow:
			attack_arrow.visible = true
		_sync_targeting_state()
		update_entire_screen()
		return
	_execute_spell_cast(hand_index, skill_index, -1)


# Core cast execution, shared by local and online paths.
func _execute_spell_cast(hand_index: int, skill_index: int, target_slot: int, target_player: int = 0) -> void:
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var cast_check: Dictionary = SpellRules.can_cast(hand[hand_index], game.active_field().get_total_mana(), skill_index, game.turn_number)
	if not cast_check.get("ok", false):
		if cast_check.get("reason", "") == SpellRules.REASON_NO_MANA:
			_show_toast("tip.insufficient_mana")
		elif cast_check.get("reason", "") == SpellRules.REASON_ENEMY_TARGET_TURN_ONE:
			_show_toast("tip.no_enemy_skill_turn1")
		return
	var skill: Dictionary = cast_check.get("skill", {})
	var resolved_target_player := target_player
	if cast_check.get("needs_target", false):
		if resolved_target_player not in [1, 2]:
			resolved_target_player = SpellRules.default_target_player(skill, game.current_player)
		var target_field := _field_for_player(resolved_target_player)
		var landed_target: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
		if landed_target == null or not landed_target.is_alive() \
				or not SpellRules.target_player_matches_drop(skill, game.current_player, resolved_target_player):
			_show_toast("tip.spell_drop_target")
			return
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_cast(hand_index, skill_index, target_slot, game.current_player, resolved_target_player)
		else:
			_send_remote_intent("activate_skill", {"slot_index": _spell_intent_source(hand_index), "skill_index": skill_index, "target_slot": target_slot, "target_player": resolved_target_player})
		return
	var spell_name: String = hand[hand_index].card_name
	var target_card := _manual_target_card_for_skill(skill, target_slot, resolved_target_player)
	_begin_action_broadcast("cast", game.current_player, spell_name, target_card.card_name if target_card != null else "")
	if game.cast_spell(hand_index, skill_index, target_slot, resolved_target_player):
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, -1)
		_refresh_hand_ui()
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		_check_and_show_game_over()
	else:
		_action_broadcast.clear()
		_action_hp_events.clear()
		_action_damage_events.clear()
		_action_parasite_events.clear()
		_action_failed_events.clear()


# Drag-to-cast shortcut — delegates to the skill-button handler.
func _on_card_drag_cast(card_data: CardData, origin_ui, hand_index: int, slot_index: int, target_player: int) -> void:
	if card_data == null or not card_data.is_spell():
		return
	if slot_index >= 0:
		_execute_spell_cast(hand_index, SpellRules.CAST_SKILL_INDEX, slot_index, target_player)
		return
	_start_spell_cast_from_hand(hand_index, SpellRules.CAST_SKILL_INDEX)


func _on_card_drag_cast_on_enemy(card_data: CardData, origin_ui, enemy_slot_index: int) -> void:
	if card_data == null:
		return
	var hand_index := _my_hand().find(card_data)
	if hand_index < 0:
		return
	if card_data.is_parasite():
		_execute_parasite_attach(hand_index, _opponent_player(), enemy_slot_index)
		return
	if not card_data.is_spell():
		return
	_execute_spell_cast(hand_index, SpellRules.CAST_SKILL_INDEX, enemy_slot_index, _opponent_player())


func _execute_parasite_attach(hand_index: int, target_player: int, target_slot: int) -> void:
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: CardData = hand[hand_index]
	var target_field := _field_for_player(target_player)
	var target: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	var attach_check: Dictionary = ParasiteRules.can_attach(card, target, game.active_field().get_total_mana())
	if not attach_check.get("ok", false):
		if attach_check.get("reason", "") == ParasiteRules.REASON_NO_MANA:
			_show_toast("tip.insufficient_mana")
		return
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_parasite(hand_index, target_player, target_slot, game.current_player)
		else:
			_send_remote_intent("activate_skill", {"slot_index": _parasite_intent_source(hand_index, target_player), "skill_index": 0, "target_slot": target_slot})
		return
	var parasite_name: String = card.card_name
	_begin_action_broadcast("parasite", game.current_player, parasite_name, target.card_name if target != null else "")
	if game.attach_parasite(hand_index, target_player, target_slot):
		_finish_action_broadcast()
		_refresh_hand_ui()
		update_entire_screen()
	else:
		_action_broadcast.clear()
		_action_hp_events.clear()
		_action_damage_events.clear()
		_action_parasite_events.clear()
		_action_failed_events.clear()


# ============================================
# Skill activation
# ============================================

func _on_skill_activated(slot_index: int, skill_index: int):
	if not game.is_player_turn or not is_my_turn():
		return
	if not game.can_pay_action():
		_show_toast("tip.insufficient_action")
		return
	var card: CardData = _my_field().slots[slot_index]
	if card == null:
		return
	if not _tutorial_allows("skill", {"slot": slot_index, "skill": skill_index}):
		return
	if card.skills_used.has(skill_index):
		return
	if skill_index >= card.skills.size():
		return
	var skill: Dictionary = card.skills[skill_index]
	if not SkillEngine.has_uses_remaining(card, skill, skill_index):
		return
	if game.turn_number <= 1 and SkillRegistry.skill_changes_enemy_hp_or_presence(skill):
		_show_toast("tip.no_enemy_hp_effect_turn1")
		return
	if card.skills_disabled():
		return
	var trig: String = skill.get("trigger", "")
	var is_summon: bool = trig == SkillEngine.TRIGGER_ON_SUMMON
	var is_activate: bool = trig == SkillEngine.TRIGGER_ON_ACTIVATE
	# Summon triggers are battlecries now: deployment resolves them or opens
	# their target picker. The card button remains informational only.
	if is_summon:
		return
	if not is_summon and not is_activate:
		return
	# on_summon abilities can only be used on the turn the card was summoned,
	# and are independent of attack/action state. on_activate keeps its rules.
	if is_summon and not card.summoned_this_turn:
		return
	if is_activate and card.has_attacked:
		return
	cancel_attack()
	if _skill_needs_targeting(skill):
		if is_summon:
			summon_targeting = true
			summon_source_slot = slot_index
			summon_skill_idx = skill_index
		else:
			activate_targeting = true
			activate_source_slot = slot_index
			activate_skill_idx = skill_index
		if attack_arrow:
			attack_arrow.visible = true
		_sync_targeting_state()
		update_entire_screen()
	else:
		if PlayerData.is_online_battle():
			if is_summon:
				if NetworkManager.is_authority():
					_host_apply_summon_skill(slot_index, skill_index, -1, game.current_player)
				else:
					_send_remote_intent("summon_skill", {"slot_index": slot_index, "skill_index": skill_index, "target_slot": -1})
			else:
				if NetworkManager.is_authority():
					_host_apply_skill(slot_index, skill_index, -1, game.current_player)
				else:
					_send_remote_intent("activate_skill", {"slot_index": slot_index, "skill_index": skill_index, "target_slot": -1})
			return
		_begin_action_broadcast("summon_skill" if is_summon else "skill", game.current_player, card.card_name, "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
		if is_summon:
			game.trigger_summon_skills(slot_index, -1, skill_index)
		else:
			game.trigger_activate_skills(slot_index, -1, skill_index)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, slot_index, skill_index)
		_refresh_hand_ui()
		_check_charm_overflow()
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		_tutorial_notify("skill", {"slot": slot_index, "skill": skill_index})
		_check_and_show_game_over()


# ============================================
# Attack
# ============================================

func _on_attack_requested(slot_index: int):
	if not game.can_pay_action():
		_show_toast("tip.insufficient_action")
		return
	if not game.is_player_turn or not is_my_turn():
		return
	if not _tutorial_allows("attack_source", {"slot": slot_index}):
		return
	if game.turn_number <= 1 and not game.allow_first_turn_attacks:
		print("Turn 1: attacks are not allowed!")
		_show_toast("tip.no_attack_turn1")
		return
	var field = _my_field()
	if field.slots[slot_index] == null:
		return
	if field.slots[slot_index].has_acted:
		return
	if field.slots[slot_index].has_stun():
		return
	cancel_attack()
	current_attacker_idx = slot_index
	if attack_arrow:
		attack_arrow.visible = true
	_sync_targeting_state()
	_tutorial_notify("attack_source", {"slot": slot_index})


func _targeting_skill_wants_ally() -> bool:
	var skill := _current_targeting_skill()
	if skill.is_empty():
		return false
	for eff in _skill_effects_for_targeting(skill):
		var target_name: String = eff.get("target", "")
		if target_name in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] and eff.get("target_side", SkillEngine.TARGET_SIDE_ENEMY) == SkillEngine.TARGET_SIDE_ALLY:
			return true
	return false


func _current_targeting_skill() -> Dictionary:
	if summon_targeting:
		var summon_card: CardData = _my_field().slots[summon_source_slot] if summon_source_slot >= 0 else null
		return summon_card.skills[summon_skill_idx] if summon_card != null and summon_skill_idx >= 0 and summon_skill_idx < summon_card.skills.size() else {}
	if activate_targeting:
		var active_card: CardData = _my_field().slots[activate_source_slot] if activate_source_slot >= 0 else null
		return active_card.skills[activate_skill_idx] if active_card != null and activate_skill_idx >= 0 and activate_skill_idx < active_card.skills.size() else {}
	if cast_targeting:
		var hand := _my_hand()
		var spell: CardData = hand[cast_hand_index] if cast_hand_index >= 0 and cast_hand_index < hand.size() else null
		return SpellRules.spell_skill(spell, cast_skill_index)
	return {}


func _skill_effects_for_targeting(skill: Dictionary) -> Array:
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and (skill.get("target", "") != "" or skill.get("effect", "") != ""):
		return [skill]
	return effects


func _apply_targeted_skill_to_selected_side(target_player: int, target_slot: int) -> void:
	if summon_targeting:
		_apply_summon_skill_target(target_player, target_slot)
		return
	if activate_targeting:
		_apply_activate_skill_target(target_player, target_slot)
		return
	if cast_targeting:
		_apply_cast_skill_target(target_player, target_slot)


func _apply_summon_skill_target(target_player: int, target_slot: int) -> void:
	var source_card: CardData = _my_field().slots[summon_source_slot]
	var target_card: CardData = _field_for_player(target_player).slots[target_slot]
	var summon_skill: Dictionary = source_card.skills[summon_skill_idx] if source_card != null and summon_skill_idx < source_card.skills.size() else {}
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_summon_skill(summon_source_slot, summon_skill_idx, target_slot, game.current_player, target_player)
		else:
			_send_remote_intent("summon_skill", {"slot_index": summon_source_slot, "skill_index": summon_skill_idx, "target_slot": target_slot, "target_player": target_player})
		cancel_attack()
		return
	# The source card may have left the field while the aim was active
	# (dragged to the discard / died); abort cleanly instead of crashing.
	if source_card == null:
		cancel_attack()
		return
	source_card.skills_used.append(summon_skill_idx)
	_begin_action_broadcast("summon_skill", game.current_player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": summon_skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	game.trigger_summon_skills(summon_source_slot, target_slot, summon_skill_idx, target_player)
	_finish_action_broadcast()
	_play_skill_cast_feedback(game.current_player, summon_source_slot, summon_skill_idx)
	_refresh_hand_ui()
	_check_charm_overflow()
	cancel_attack()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()


func _apply_activate_skill_target(target_player: int, target_slot: int) -> void:
	var source_card: CardData = _my_field().slots[activate_source_slot]
	var target_card: CardData = _field_for_player(target_player).slots[target_slot]
	var activate_skill: Dictionary = source_card.skills[activate_skill_idx] if source_card != null and activate_skill_idx < source_card.skills.size() else {}
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_skill(activate_source_slot, activate_skill_idx, target_slot, game.current_player)
		else:
			_send_remote_intent("activate_skill", {"slot_index": activate_source_slot, "skill_index": activate_skill_idx, "target_slot": target_slot})
		cancel_attack()
		return
	if source_card == null:
		cancel_attack()
		return
	_begin_action_broadcast("skill", game.current_player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": activate_skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	game.trigger_activate_skills(activate_source_slot, target_slot, activate_skill_idx, target_player)
	_finish_action_broadcast()
	_play_skill_cast_feedback(game.current_player, activate_source_slot, activate_skill_idx)
	_refresh_hand_ui()
	_check_charm_overflow()
	cancel_attack()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()
	_check_and_show_game_over()


func _apply_cast_skill_target(target_player: int, target_slot: int) -> void:
	_execute_spell_cast(cast_hand_index, cast_skill_index, target_slot, target_player)
	cancel_attack()


func _on_player_slot_clicked(index: int):
	if not is_my_turn(): return
	if parasite_targeting:
		if _my_field().slots[index] == null:
			cancel_attack()
			return
		_execute_parasite_attach(parasite_hand_index, _view_player(), index)
		cancel_attack()
		return
	if _targeting_skill_wants_ally():
		if _my_field().slots[index] == null:
			cancel_attack()
			return
		_apply_targeted_skill_to_selected_side(_view_player(), index)
		return
	if current_attacker_idx != -1:
		cancel_attack()
	update_entire_screen()


func _on_enemy_slot_clicked(enemy_index: int):
	if not is_my_turn(): return
	if summon_targeting or activate_targeting or cast_targeting or parasite_targeting or current_attacker_idx != -1:
		_on_opponent_slot_clicked(enemy_index)
	else:
		update_entire_screen()


func _on_opponent_slot_clicked(index: int):
	if current_attacker_idx != -1 and not _tutorial_allows("attack_target", {"slot": index}):
		return
	if parasite_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		_execute_parasite_attach(parasite_hand_index, _opponent_player(), index)
		cancel_attack()
		return

	if _targeting_skill_wants_ally():
		cancel_attack()
		return

	if summon_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		if _their_field().has_any_taunt():
			var target_card = _their_field().slots[index]
			if target_card == null or not target_card.has_taunt():
				print("Must target a taunt minion first!")
				_show_toast("tip.taunt_skill_first")
				return
		if PlayerData.is_online_battle():
			if NetworkManager.is_authority():
				_host_apply_summon_skill(summon_source_slot, summon_skill_idx, index, game.current_player, _opponent_player())
			else:
				_send_remote_intent("summon_skill", {"slot_index": summon_source_slot, "skill_index": summon_skill_idx, "target_slot": index, "target_player": _opponent_player()})
			cancel_attack()
			return
		var summon_card: CardData = _my_field().slots[summon_source_slot]
		if summon_card == null:
			cancel_attack()
			return
		summon_card.skills_used.append(summon_skill_idx)
		var summon_skill: Dictionary = summon_card.skills[summon_skill_idx] if summon_skill_idx < summon_card.skills.size() else {}
		_begin_action_broadcast("summon_skill", game.current_player, summon_card.card_name, _their_field().slots[index].card_name, {"skill": summon_skill.get("skill_name", Locale.t("battle.log.skill_word"))})
		game.trigger_summon_skills(summon_source_slot, index, summon_skill_idx)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, summon_source_slot, summon_skill_idx)
		_refresh_hand_ui()
		_check_charm_overflow()
		summon_targeting = false
		summon_source_slot = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		return

	if activate_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		if _their_field().has_any_taunt():
			var target_card = _their_field().slots[index]
			if target_card == null or not target_card.has_taunt():
				print("Must target a taunt minion first!")
				_show_toast("tip.taunt_skill_first")
				return
		if PlayerData.is_online_battle():
			if NetworkManager.is_authority():
				_host_apply_skill(activate_source_slot, activate_skill_idx, index, game.current_player)
			else:
				_send_remote_intent("activate_skill", {"slot_index": activate_source_slot, "skill_index": activate_skill_idx, "target_slot": index})
			cancel_attack()
			return
		var card: CardData = _my_field().slots[activate_source_slot]
		if card == null:
			cancel_attack()
			return
		var activate_skill: Dictionary = card.skills[activate_skill_idx] if activate_skill_idx < card.skills.size() else {}
		_begin_action_broadcast("skill", game.current_player, card.card_name, _their_field().slots[index].card_name, {"skill": activate_skill.get("skill_name", Locale.t("battle.log.skill_word"))})
		game.trigger_activate_skills(activate_source_slot, index, activate_skill_idx)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, activate_source_slot, activate_skill_idx)
		_refresh_hand_ui()
		_check_charm_overflow()
		activate_targeting = false
		activate_source_slot = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		_check_and_show_game_over()
		return

	if cast_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		if _their_field().has_any_taunt():
			var target_card = _their_field().slots[index]
			if target_card == null or not target_card.has_taunt():
				print("Must target a taunt minion first!")
				_show_toast("tip.taunt_skill_first")
				return
		if PlayerData.is_online_battle():
			if NetworkManager.is_authority():
				_host_apply_cast(cast_hand_index, cast_skill_index, index, game.current_player, _opponent_player())
			else:
				_send_remote_intent("activate_skill", {"slot_index": _spell_intent_source(cast_hand_index), "skill_index": cast_skill_index, "target_slot": index, "target_player": _opponent_player()})
			cancel_attack()
			return
		_execute_spell_cast(cast_hand_index, cast_skill_index, index)
		cast_targeting = false
		cast_hand_index = -1
		cast_skill_index = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		return

	if current_attacker_idx == -1:
		return
	if _their_field().slots[index] == null:
		cancel_attack()
		return
	if _their_field().has_any_taunt():
		var target_card = _their_field().slots[index]
		if target_card == null or not target_card.has_taunt():
			print("Must attack a taunt minion first!")
			_show_toast("tip.taunt_first")
			return
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority():
			_host_apply_attack(current_attacker_idx, index, game.current_player)
		else:
			_send_remote_intent("attack", {"source_slot": current_attacker_idx, "target_slot": index})
		cancel_attack()
		return
	var victim: CardData = _their_field().slots[index]
	var attacker_slot: int = current_attacker_idx
	var attacker_card: CardData = _my_field().slots[attacker_slot]
	var base_damage: int = attacker_card.atk if attacker_card != null else 0
	var effective_damage: int = attacker_card.effective_atk() if attacker_card != null else 0
	_begin_action_broadcast("attack", game.current_player, attacker_card.card_name if attacker_card != null else Locale.t("battle.log.unit"), victim.card_name if victim != null else Locale.t("battle.log.unit"), {"base_damage": base_damage, "effective_damage": effective_damage, "target_player": _opponent_player(), "target_slot": index})
	game.execute_attack(attacker_slot, index)
	if victim != null and not victim.is_alive():
		_action_broadcast["kill_mana"] = true
	_finish_action_broadcast()
	_play_attack_feedback(game.current_player, attacker_slot, index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	cancel_attack()
	_tutorial_notify("attack_target", {"slot": index})
	_check_and_show_game_over()


func cancel_pending_battle_selection() -> bool:
	if not (current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting):
		return false
	cancel_attack()
	update_entire_screen()
	return true


func cancel_attack():
	var resume_auto_summon := summon_targeting
	if PlayerData.is_online_battle() and (current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting):
		NetworkManager.rpc_targeting_arrow.rpc(NetworkManager.battle_match_id, -1, -1, game.current_player)
	current_attacker_idx = -1
	summon_targeting = false
	summon_source_slot = -1
	summon_skill_idx = -1
	activate_targeting = false
	cast_targeting = false
	parasite_targeting = false
	cast_hand_index = -1
	cast_skill_index = -1
	parasite_hand_index = -1
	last_hovered_target = -1
	if attack_arrow:
		attack_arrow.visible = false
	if resume_auto_summon:
		_resume_auto_summon_targeting.call_deferred()


# ============================================
# Skill interaction handlers (view discard/deck, hand cost reduction)
# ============================================

func _on_shuffle_discard_into_deck() -> void:
	if game.shared_discard.is_empty():
		return
	game.shared_deck = game.shared_discard.duplicate()
	game.shared_discard.clear()
	game._shuffle_shared_deck()
	AppAudio.play("shuffle")
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


func _on_make_zero_cost_select(reduction: int, cost_mode: String, player: int, hand: Array, target: String, _random_count: int) -> void:
	var candidates := _positive_cost_cards(hand)
	if candidates.is_empty(): return
	if PlayerData.is_online_battle():
		if NetworkManager.is_authority() and player in [1, 2] and game.pending_cost_choices.size() < UgcSafety.MAX_EXECUTED_EFFECT_NODES:
			game.pending_cost_choices.append({"player": player, "reduction": reduction, "cost_mode": cost_mode, "target": target})
		return
	# Finish the synchronous skill chain before checking its queued roll feedback.
	_show_cost_picker_after_feedback.call_deferred(hand, reduction, cost_mode, target)


func _show_cost_picker_after_feedback(hand: Array, reduction: int, cost_mode: String, target: String) -> void:
	await _wait_for_random_feedback()
	if not is_inside_tree() or battle_finished: return
	var candidates := _positive_cost_cards(hand)
	if not candidates.is_empty():
		_show_zero_cost_selection_popup(candidates, reduction, cost_mode, 1, hand, target)


func _positive_cost_cards(hand: Array) -> Array:
	return hand.filter(func(card): return card is CardData and card.cost > 0)


func _cost_picker_title(reduction: int, cost_mode: String, target: String) -> String:
	var sides := target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES]
	return Locale.t("battle.reduce_cost_title_sides" if sides else "battle.reduce_cost_title", [reduction, Locale.term("cost_reduction_mode", cost_mode)])


func _apply_cost_choice(hand: Array, index: int, reduction: int, cost_mode: String, target: String) -> void:
	var sides := target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES]
	var radius := 1 if sides else 0
	for affected in range(maxi(0, index-radius), mini(hand.size(), index+radius+1)):
		hand[affected].apply_cost_reduction(reduction, cost_mode == SkillRegistry.COST_REDUCTION_PERMANENT)


func _sync_online_cost_picker() -> void:
	if not PlayerData.is_online_battle() or game == null: return
	if is_instance_valid(_online_cost_picker):
		if game.pending_cost_choices.is_empty() or battle_finished or _online_cost_picker.get_meta("revision") != game.state_revision:
			_online_cost_picker.set_meta("submitted", true)
			_online_cost_picker.queue_free()
		return
	if game.pending_cost_choices.is_empty() or battle_finished or match_paused or is_resolution_locked() \
			or _waiting_for_room_link() or NetworkManager.pending_game_command_count() > 0:
		return
	var choice: Dictionary = game.pending_cost_choices.front()
	var hand := _hand_for_player(int(choice.player))
	var candidates := _positive_cost_cards(hand)
	if candidates.is_empty():
		if NetworkManager.is_authority(): _resolve_online_cost_choice(int(choice.player), -1)
		return
	if choice.player != _view_player(): return
	var revision: int = game.state_revision
	var picker: CanvasLayer = preload("res://CardCollectionDialog.gd").show_cards(self, candidates,
		_cost_picker_title(int(choice.reduction), choice.cost_mode, choice.target), 1)
	_online_cost_picker = picker
	picker.set_meta("revision", revision)
	picker.on_confirm = func(selected: Array):
		picker.set_meta("submitted", true)
		_submit_online_cost_choice(revision, hand.find(selected[0]))
	picker.tree_exiting.connect(func():
		if not picker.get_meta("submitted", false): _submit_online_cost_choice.call_deferred(revision, -1))


func _submit_online_cost_choice(revision: int, index: int) -> void:
	if not is_inside_tree() or game.state_revision != revision or battle_finished or match_paused or _waiting_for_room_link(): return
	if NetworkManager.is_authority():
		_resolve_online_cost_choice(_view_player(), index)
	else:
		# Complete the skill through its existing command envelope so the relay needs no new RPC.
		NetworkManager.send_game_intent("activate_skill", {"cost_choice": index}, _view_player(), revision)


func _resolve_online_cost_choice(player: int, index: int) -> void:
	if game.pending_cost_choices.is_empty(): return
	var choice: Dictionary = game.pending_cost_choices.front()
	if choice.player != player: return
	var hand := _hand_for_player(player)
	if index != -1:
		if index < 0 or index >= hand.size() or hand[index].cost <= 0: return
		_apply_cost_choice(hand, index, int(choice.reduction), choice.cost_mode, choice.target)
	game.pending_cost_choices.pop_front()
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("cost choice")


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
		if PlayerData.is_online_battle() and NetworkManager.is_authority():
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
	var title := _cost_picker_title(reduction, cost_mode, target)
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


# ============================================
# Turn
# ============================================

static func end_turn_execution_path(online: bool, authority: bool) -> String:
	if not online:
		return "local"
	return "authority" if authority else "remote"


func _on_end_turn_pressed():
	if not _owns_current_turn():
		return
	if not _tutorial_allows("end_turn"):
		return
	if _turn_ending:
		return
	# Accept the request now, then let deployment and its triggered feedback
	# complete before starting any end-of-turn rules.
	_turn_ending = true
	end_turn_button.disabled = true
	var player: int = game.current_player
	var turn: int = game.turn_number
	var allow_face_mana: bool = face_mana_button.button_pressed
	while _deployment_feedback_delay()>0 or is_resolution_locked() or _turn_request_playback_pending() or not _hp_feedback_batches.is_empty() or hand_container.get_children().any(func(card): return card.get_meta("tabletop_arriving",false)):
		await get_tree().process_frame
		if not is_inside_tree(): return
		if not _owns_current_turn() or game.current_player!=player or game.turn_number!=turn:
			_turn_ending = false
			update_entire_screen()
			return
	_turn_ending = false
	await _finish_end_turn(allow_face_mana)


func _finish_end_turn(allow_face_mana: bool) -> void:
	if _turn_ending or not is_my_turn(): return
	_turn_ending = true
	end_turn_button.disabled = true
	match end_turn_execution_path(PlayerData.is_online_battle(), NetworkManager.is_authority()):
		"authority":
			await _host_apply_end_turn(game.current_player, allow_face_mana)
			_reset_face_mana_toggle()
			_turn_ending = false
			return
		"remote":
			var checkpoint := {"turn_hash": _web_turn_hash()} if _has_online_prediction() else {}
			checkpoint["allow_face_mana"] = allow_face_mana
			if _send_remote_intent("end_turn", checkpoint) == "":
				_turn_ending = false
				update_entire_screen()
			# Non-authority stays locked until authority state arrives
			return
	await _run_local_end_turn(allow_face_mana)
	_reset_face_mana_toggle()
	_tutorial_notify("end_turn")


func _run_local_end_turn(allow_face_mana: bool = true) -> void:
	var result = game.end_player_turn(allow_face_mana)
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	await _wait_for_direct_damage()
	if _check_and_show_game_over():
		_turn_ending = false
		return
	await get_tree().create_timer(0.5).timeout
	game.start_new_turn()
	AppAudio.play("turn")
	if game.current_player == _view_player() and _my_hand().size() >= SkillEngine.MAX_HAND_SIZE:
		_show_toast("tip.hand_full", [SkillEngine.MAX_HAND_SIZE])
	_refresh_hand_ui()
	_turn_ending = false
	update_entire_screen()
	if PlayerData.battle_mode == "practice" and game.current_player == 2:
		_start_practice_ai_turn.call_deferred()


func _start_practice_ai_turn() -> void:
	if PlayerData.is_online_battle() or PlayerData.battle_mode != "practice" or game.current_player != 2 or practice_ai_running:
		return
	await _run_practice_ai_turn()


func _run_practice_ai_turn() -> void:
	practice_ai_running = true
	end_turn_button.disabled = true
	update_entire_screen()
	await get_tree().create_timer(0.35, false).timeout
	var action_count := 0
	while action_count < 40 and game.current_player == 2:
		action_count += 1
		var action := BattlePlanner.choose_action(game, PlayerData.practice_ai_difficulty, game.game_rng)
		if str(action.get("type", "")) == "end_turn":
			break
		var source_slot := int(action.get("source_slot", action.get("slot", -1)))
		var target_slot := int(action.get("target_slot", -1))
		var action_type := str(action.get("type", ""))
		var source: CardData = game.player2_field.slots[source_slot] if source_slot in range(5) else null
		var hand_index := int(action.get("hand_index", -1))
		if action_type in ["summon", "cast"] and hand_index >= 0 and hand_index < game.player2_hand.size():
			source = game.player2_hand[hand_index]
		var target: CardData = game.player_field.slots[target_slot] if target_slot in range(5) else null
		_begin_action_broadcast("skill" if action_type == "activate" else action_type, 2, source.card_name if source != null else "", target.card_name if target != null else "")
		var result := BattleCommand.apply_action(game, action)
		if not bool(result.get("ok", false)):
			_action_broadcast.clear()
			push_warning("Practice AI rejected action: %s" % [action])
			break
		if action_type == "attack":
			_action_presentation_events.push_front({
				"kind": "attack_motion", "player": 2, "source_slot": source_slot, "target_slot": target_slot,
				"feedback_group": 0, "projectile": true, "board_before": _random_action_before,
			})
		# Resolve death passives in this same chain, so their probability rolls
		# still precede the hit. Only the visual removal waits until impact.
		var deaths: Dictionary = game.cleanup_deaths()
		for player in [1, 2]:
			for dead_slot in deaths.get("p%d" % player, []):
				_action_presentation_events.append({"kind":"ai_death", "player":player, "slot":dead_slot, "feedback_group":_action_feedback_next_group})
		if action_type == "summon":
			_play_summon_feedback(_slot_ui_for_player(2, int(action.get("slot", -1))))
		_refresh_hand_ui()
		_finish_action_broadcast()
		update_entire_screen()
		match action_type:
			"activate": _play_skill_cast_feedback(2, source_slot)
			"cast": _play_spell_cast_from_hand_feedback()
		# Keep the current cards visible until their attack and triggered effects
		# have landed; do not let the next AI command overtake this presentation.
		await get_tree().process_frame
		while is_inside_tree() and (_hp_feedback_running or not _hp_feedback_batches.is_empty() or _random_feedback_pending > 0 or not _random_unbatched_events.is_empty()):
			await get_tree().process_frame
		_check_charm_overflow()
		_refresh_hand_ui()
		update_entire_screen()
		if _check_and_show_game_over():
			practice_ai_running = false
			return
		await _wait_for_deployment_feedback()
		await get_tree().create_timer(0.12, false).timeout
		await _wait_for_random_feedback()
	if _check_and_show_game_over():
		practice_ai_running = false
		return
	await get_tree().create_timer(0.35, false).timeout
	practice_ai_running = false
	await _run_local_end_turn()


func _practice_ai_play_cards() -> void:
	match PlayerData.practice_ai_difficulty:
		"easy":
			_practice_ai_summon_cards(1, false)
		"hard":
			_practice_ai_summon_cards(5, true)
		_:
			_practice_ai_summon_cards(1, true)


func _practice_ai_summon_cards(max_cards: int, prefer_expensive: bool) -> void:
	var saved_player: int = game.current_player
	game.current_player = 2
	var played := 0
	while played < max_cards:
		var choice := _practice_ai_choose_summon(prefer_expensive)
		if choice.is_empty():
			break
		if game.summon_card(choice["card"], choice["slot"]):
			played += 1
		else:
			break
	game.current_player = saved_player


func _practice_ai_choose_summon(prefer_expensive: bool) -> Dictionary:
	var hand: Array = game.player2_hand
	var field: BattleField = game.player2_field
	var empty_slot := -1
	for slot in range(field.slots.size()):
		if field.slots[slot] == null:
			empty_slot = slot
			break
	if empty_slot < 0:
		return {}
	var best_index := -1
	var best_score := -999999
	for h in range(hand.size()):
		var card: CardData = hand[h]
		if card == null or card.cost > field.get_total_mana():
			continue
		var score := card.cost if prefer_expensive else -h
		if PlayerData.practice_ai_difficulty == "hard":
			score += card.atk * 2 + card.max_hp
		if score > best_score:
			best_score = score
			best_index = h
	if best_index < 0:
		return {}
	return {"card": hand[best_index], "slot": empty_slot}


func _practice_ai_use_skills() -> void:
	if PlayerData.practice_ai_difficulty != "hard":
		return
	var saved_player: int = game.current_player
	game.current_player = 2
	for slot in range(game.player2_field.slots.size()):
		var card: CardData = game.player2_field.slots[slot]
		if card == null or card.skills_disabled():
			continue
		for skill_idx in range(card.skills.size()):
			if card.skills_used.has(skill_idx):
				continue
			var skill: Dictionary = card.skills[skill_idx]
			var trigger: String = skill.get("trigger", "")
			if trigger != SkillEngine.TRIGGER_ON_ACTIVATE and not (trigger == SkillEngine.TRIGGER_ON_SUMMON and card.summoned_this_turn):
				continue
			var target_slot := _practice_ai_skill_target_slot(skill)
			if target_slot == -2:
				continue
			if trigger == SkillEngine.TRIGGER_ON_SUMMON:
				card.skills_used.append(skill_idx)
				game.trigger_summon_skills(slot, target_slot, skill_idx)
			else:
				game.trigger_activate_skills(slot, target_slot, skill_idx)
			_play_skill_cast_feedback(2, slot, skill_idx)
			_apply_deaths()
			if game.check_game_over() != "":
				game.current_player = saved_player
				return
	game.current_player = saved_player


func _practice_ai_skill_target_slot(skill: Dictionary) -> int:
	for eff in skill.get("effects", []):
		var normalized := _TargetResolver.normalize_effect_target(eff)
		var target: String = normalized.get("target", SkillEngine.TARGET_SELF)
		if target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			var effect: String = normalized.get("effect", "")
			if effect in [SkillEngine.EFFECT_HEAL, SkillEngine.EFFECT_SHIELD, SkillEngine.EFFECT_ADD_BUFF, SkillEngine.EFFECT_DRAW_CARDS]:
				return -2
			var slot := _practice_ai_best_target_slot()
			return slot if slot >= 0 else -2
	return -1


func _practice_ai_attack_with_ready_cards() -> void:
	if game.turn_number <= 1:
		return
	var saved_player: int = game.current_player
	game.current_player = 2
	for slot in range(game.player2_field.slots.size()):
		var card: CardData = game.player2_field.slots[slot]
		if card == null or card.has_acted or card.has_stun():
			continue
		var target_slot := _practice_ai_attack_target_slot(card)
		if target_slot < 0:
			continue
		game.execute_attack(slot, target_slot)
		_play_attack_feedback(2, slot, target_slot)
		_apply_deaths()
		if game.check_game_over() != "":
			break
	game.current_player = saved_player


func _practice_ai_attack_target_slot(attacker: CardData) -> int:
	if PlayerData.practice_ai_difficulty == "easy":
		return _practice_ai_first_attack_target()
	return _practice_ai_best_target_slot(attacker)


func _practice_ai_first_attack_target() -> int:
	for i in range(game.player_field.slots.size()):
		var target: CardData = game.player_field.slots[i]
		if target != null and target.is_alive() and target.has_taunt():
			return i
	for i in range(game.player_field.slots.size()):
		var target: CardData = game.player_field.slots[i]
		if target != null and target.is_alive():
			return i
	return -1


func _practice_ai_best_target_slot(attacker: CardData = null) -> int:
	var best_slot := -1
	var best_score := -999999
	for i in range(game.player_field.slots.size()):
		var target: CardData = game.player_field.slots[i]
		if target == null or not target.is_alive():
			continue
		if game.player_field.has_any_taunt() and not target.has_taunt():
			continue
		var score := 0
		if target.has_taunt():
			score += 1000
		if attacker != null and attacker.effective_atk() >= target.hp:
			score += 500
		score += target.atk * 6 + (target.max_hp - target.hp) * 2 - target.hp
		if PlayerData.practice_ai_difficulty == "hard":
			score += target.cost * 3
		if score > best_score:
			best_score = score
			best_slot = i
	return best_slot

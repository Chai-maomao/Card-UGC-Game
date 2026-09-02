extends "res://BattleMainFoundation.gd"

const BattlePlanner = preload("res://BattleAiPlanner.gd")
const BattleCommand = preload("res://BattleRepro.gd")


func _send_remote_intent(kind: String, payload: Dictionary) -> String:
	if NetworkManager.pending_game_command_count() > 0:
		_show_toast("tip.command_pending")
		return ""
	var command_id := NetworkManager.send_game_intent(kind, payload, game.current_player, game.state_revision)
	if command_id != "":
		_network_command_phase = "sent"
		update_entire_screen()
	return command_id

# ============================================
# Misc
# ============================================

func _on_card_discarded(card_data: CardData):
	if not is_my_turn(): return
	if not _tutorial_allows("discard"):
		return
	var card_location := _find_card_location(card_data)
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_discard(card_location["location"], card_location["index"], game.current_player)
		else:
			_send_remote_intent("discard", {"location": card_location["location"], "index": card_location["index"]})
		return
	if game.discard_card(card_data):
		_show_combat_broadcast(Locale.t("tip.discard_mana"))
		_refresh_hand_ui()
		update_entire_screen()
		_play_discard_feedback()


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
	for eff in _skill_effects_for_targeting(skill):
		var target_name: String = eff.get("target", "")
		if target_name in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			var side: String = eff.get("target_side", SkillEngine.TARGET_SIDE_ENEMY)
			return SkillEngine.TARGET_SIDE_ALLY if side == SkillEngine.TARGET_SIDE_ALLY else SkillEngine.TARGET_SIDE_ENEMY
	return SkillEngine.TARGET_SIDE_ENEMY


func _manual_target_is_enemy(skill: Dictionary) -> bool:
	return _manual_target_side(skill) != SkillEngine.TARGET_SIDE_ALLY


func _manual_target_card_for_skill(skill: Dictionary, target_slot: int) -> CardData:
	var field := _my_field() if _manual_target_side(skill) == SkillEngine.TARGET_SIDE_ALLY else _their_field()
	return field.slots[target_slot] if target_slot >= 0 and target_slot < field.slots.size() else null

# ============================================
# Splash art
# ============================================

func _show_splash(card: CardData) -> void:
	if card == null:
		return
	if splash_tween and splash_tween.is_valid():
		splash_tween.kill()
	splash_name.text = card.card_name
	var has_art: bool = false
	if card.art_path != "":
		var load_path: String = card.art_path
		if load_path.begins_with("user://"):
			load_path = ProjectSettings.globalize_path(load_path)
		var img = Image.new()
		var err = img.load(load_path)
		if err == OK:
			var tex = ImageTexture.create_from_image(img)
			if tex != null:
				splash_art.texture = tex
				splash_art.visible = true
				splash_text.visible = false
				has_art = true
	if not has_art:
		splash_art.visible = false
		splash_text.visible = true
		splash_text.text = card.card_name
	# Lightweight reveal: pop in place on the right edge (no full-screen slide).
	splash_panel.position.x = 0.0
	splash_panel.pivot_offset = splash_panel.size / 2
	splash_panel.scale = Vector2(0.88, 0.88)
	splash_panel.modulate.a = 1.0
	splash_tween = create_tween()
	splash_tween.set_parallel(true)
	splash_tween.tween_property(splash_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	splash_tween.tween_property(splash_panel, "modulate:a", 0.0, 0.28).set_delay(0.75)
	splash_tween.chain().tween_callback(func(): splash_panel.scale = Vector2(0.88, 0.88))

# ============================================
# Summon
# ============================================

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

	var source_slot := -1
	for i in range(5):
		if field.slots[i] == card_data:
			source_slot = i
			break

	if source_slot >= 0:
		if NetworkManager.is_online:
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
	if card_data.is_spell():
		_on_card_drag_cast(card_data, origin_ui, hand_index, slot_index)
		return
	if NetworkManager.is_online:
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

	# on_summon skills are no longer auto-triggered; the player activates them
	# manually this turn via the skill buttons (see _on_skill_activated).
	_refresh_hand_ui()
	_check_charm_overflow()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()
	_play_summon_feedback(_slot_ui_for_player(_view_player(), slot_index))
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
	if card != null and card.is_parasite():
		_start_parasite_attach_from_hand(hand_index)
		return
	_start_spell_cast_from_hand(hand_index, skill_index)


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
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_cast(hand_index, skill_index, target_slot, game.current_player)
		else:
			_send_remote_intent("activate_skill", {"slot_index": _spell_intent_source(hand_index), "skill_index": skill_index, "target_slot": target_slot})
		return
	var spell_name: String = hand[hand_index].card_name
	var target_card := _manual_target_card_for_skill(cast_check.get("skill", {}), target_slot)
	_begin_action_broadcast("cast", game.current_player, spell_name, target_card.card_name if target_card != null else "")
	if game.cast_spell(hand_index, skill_index, target_slot, target_player):
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
func _on_card_drag_cast(card_data: CardData, origin_ui, hand_index: int, slot_index: int) -> void:
	if card_data == null or not card_data.is_spell():
		return
	if slot_index >= 0:
		_execute_spell_cast(hand_index, SpellRules.CAST_SKILL_INDEX, slot_index)
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
	_execute_spell_cast(hand_index, SpellRules.CAST_SKILL_INDEX, enemy_slot_index)


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
	if NetworkManager.is_online:
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
	if card.is_silenced() and skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL) != SkillEngine.SKILL_TYPE_TALENT:
		return
	var trig: String = skill.get("trigger", "")
	var is_summon: bool = trig == SkillEngine.TRIGGER_ON_SUMMON
	var is_activate: bool = trig == SkillEngine.TRIGGER_ON_ACTIVATE
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
		if game.turn_number <= 1 and PlayerData.battle_mode != "tutorial" and _manual_target_is_enemy(skill):
			print("Turn 1: enemy-targeting skills are not allowed!")
			_show_toast("tip.no_enemy_skill_turn1")
			return
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
		if NetworkManager.is_online:
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
		card.skills_used.append(skill_index)
		_begin_action_broadcast("summon_skill" if is_summon else "skill", game.current_player, card.card_name, "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
		if is_summon:
			game.trigger_summon_skills(slot_index, -1, skill_index)
		else:
			game.trigger_activate_skills(slot_index, -1, skill_index)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, slot_index)
		_refresh_hand_ui()
		_check_charm_overflow()
		_show_splash(card)
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		_tutorial_notify("skill", {"slot": slot_index, "skill": skill_index})


# ============================================
# Attack
# ============================================

func _on_attack_requested(slot_index: int):
	if not game.is_player_turn or not is_my_turn():
		return
	if not _tutorial_allows("attack_source", {"slot": slot_index}):
		return
	if game.turn_number <= 1 and PlayerData.battle_mode != "tutorial":
		print("Turn 1: attacks are not allowed!")
		_show_toast("tip.no_attack_turn1")
		return
	var field = _my_field()
	if field.slots[slot_index] == null:
		return
	if field.slots[slot_index].has_acted:
		return
	if field.slots[slot_index].is_silenced() and not field.slots[slot_index].attack_ignores_silence:
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
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_summon_skill(summon_source_slot, summon_skill_idx, target_slot, game.current_player)
		else:
			_send_remote_intent("summon_skill", {"slot_index": summon_source_slot, "skill_index": summon_skill_idx, "target_slot": target_slot})
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
	_play_skill_cast_feedback(game.current_player, summon_source_slot)
	_refresh_hand_ui()
	_check_charm_overflow()
	_show_splash(source_card)
	cancel_attack()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()


func _apply_activate_skill_target(target_player: int, target_slot: int) -> void:
	var source_card: CardData = _my_field().slots[activate_source_slot]
	var target_card: CardData = _field_for_player(target_player).slots[target_slot]
	var activate_skill: Dictionary = source_card.skills[activate_skill_idx] if source_card != null and activate_skill_idx < source_card.skills.size() else {}
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_skill(activate_source_slot, activate_skill_idx, target_slot, game.current_player)
		else:
			_send_remote_intent("activate_skill", {"slot_index": activate_source_slot, "skill_index": activate_skill_idx, "target_slot": target_slot})
		cancel_attack()
		return
	if source_card == null:
		cancel_attack()
		return
	source_card.skills_used.append(activate_skill_idx)
	_begin_action_broadcast("skill", game.current_player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": activate_skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	game.trigger_activate_skills(activate_source_slot, target_slot, activate_skill_idx, target_player)
	_finish_action_broadcast()
	_play_skill_cast_feedback(game.current_player, activate_source_slot)
	_refresh_hand_ui()
	_check_charm_overflow()
	_show_splash(source_card)
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
		if NetworkManager.is_online:
			if NetworkManager.is_authority():
				_host_apply_summon_skill(summon_source_slot, summon_skill_idx, index, game.current_player)
			else:
				_send_remote_intent("summon_skill", {"slot_index": summon_source_slot, "skill_index": summon_skill_idx, "target_slot": index})
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
		_play_skill_cast_feedback(game.current_player, summon_source_slot)
		_refresh_hand_ui()
		_check_charm_overflow()
		if summon_card != null:
			_show_splash(summon_card)
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
		if NetworkManager.is_online:
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
		card.skills_used.append(activate_skill_idx)
		var activate_skill: Dictionary = card.skills[activate_skill_idx] if activate_skill_idx < card.skills.size() else {}
		_begin_action_broadcast("skill", game.current_player, card.card_name, _their_field().slots[index].card_name, {"skill": activate_skill.get("skill_name", Locale.t("battle.log.skill_word"))})
		game.trigger_activate_skills(activate_source_slot, index, activate_skill_idx)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, activate_source_slot)
		_refresh_hand_ui()
		_check_charm_overflow()
		_show_splash(card)
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
		if NetworkManager.is_online:
			if NetworkManager.is_authority():
				_host_apply_cast(cast_hand_index, cast_skill_index, index, game.current_player)
			else:
				_send_remote_intent("activate_skill", {"slot_index": _spell_intent_source(cast_hand_index), "skill_index": cast_skill_index, "target_slot": index})
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
	if NetworkManager.is_online:
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


func cancel_attack():
	if NetworkManager.is_online and (current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting):
		NetworkManager.rpc_targeting_arrow.rpc(-1, -1, game.current_player)
	current_attacker_idx = -1
	summon_targeting = false
	activate_targeting = false
	cast_targeting = false
	parasite_targeting = false
	cast_hand_index = -1
	cast_skill_index = -1
	parasite_hand_index = -1
	last_hovered_target = -1
	if attack_arrow:
		attack_arrow.visible = false


# ============================================
# Turn
# ============================================

static func end_turn_execution_path(online: bool, authority: bool) -> String:
	if not online:
		return "local"
	return "authority" if authority else "remote"


func _on_end_turn_pressed():
	if not game.is_player_turn or not is_my_turn():
		return
	if not _tutorial_allows("end_turn"):
		return
	if _turn_ending:
		return
	_turn_ending = true
	end_turn_button.disabled = true
	match end_turn_execution_path(NetworkManager.is_online, NetworkManager.is_authority()):
		"authority":
			await _host_apply_end_turn(game.current_player)
			_turn_ending = false
			return
		"remote":
			if _send_remote_intent("end_turn", {}) == "":
				_turn_ending = false
				update_entire_screen()
			# Non-authority stays locked until authority state arrives
			return
	await _run_local_end_turn()
	_turn_ending = false
	_tutorial_notify("end_turn")


func _run_local_end_turn() -> void:
	var result = game.end_player_turn()
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	if _check_and_show_game_over():
		return
	await get_tree().create_timer(0.5).timeout
	game.start_new_turn()
	_show_turn_banner()
	if game.current_player == _view_player() and _my_hand().size() >= SkillEngine.MAX_HAND_SIZE:
		_show_toast("tip.hand_full", [SkillEngine.MAX_HAND_SIZE])
	_refresh_hand_ui()
	end_turn_button.disabled = false
	update_entire_screen()
	if PlayerData.battle_mode == "practice" and game.current_player == 2:
		_start_practice_ai_turn.call_deferred()


func _start_practice_ai_turn() -> void:
	if NetworkManager.is_online or PlayerData.battle_mode != "practice" or game.current_player != 2 or practice_ai_running:
		return
	await _run_practice_ai_turn()


func _run_practice_ai_turn() -> void:
	practice_ai_running = true
	end_turn_button.disabled = true
	update_entire_screen()
	await get_tree().create_timer(0.35).timeout
	var action_count := 0
	while action_count < 40 and game.current_player == 2:
		action_count += 1
		var action := BattlePlanner.choose_action(game, PlayerData.practice_ai_difficulty, game.game_rng)
		if str(action.get("type", "")) == "end_turn":
			break
		var source_slot := int(action.get("source_slot", action.get("slot", -1)))
		var target_slot := int(action.get("target_slot", -1))
		var result := BattleCommand.apply_action(game, action)
		if not bool(result.get("ok", false)):
			push_warning("Practice AI rejected action: %s" % [action])
			break
		match str(action.get("type", "")):
			"attack": _play_attack_feedback(2, source_slot, target_slot)
			"activate": _play_skill_cast_feedback(2, source_slot)
			"cast": _play_spell_cast_from_hand_feedback()
		_apply_deaths()
		_check_charm_overflow()
		_refresh_hand_ui()
		update_entire_screen()
		if _check_and_show_game_over():
			practice_ai_running = false
			return
		await get_tree().create_timer(0.12).timeout
	if _check_and_show_game_over():
		practice_ai_running = false
		return
	await get_tree().create_timer(0.35).timeout
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
		if card == null or card.is_silenced():
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
			card.skills_used.append(skill_idx)
			if trigger == SkillEngine.TRIGGER_ON_SUMMON:
				game.trigger_summon_skills(slot, target_slot, skill_idx)
			else:
				game.trigger_activate_skills(slot, target_slot, skill_idx)
			_play_skill_cast_feedback(2, slot)
			_show_splash(card)
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
		if card == null or card.has_acted or card.is_silenced():
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

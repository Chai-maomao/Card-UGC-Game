extends "res://BattleMainActions.gd"

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
	if not game.is_player_turn or not is_my_turn() or game.current_player != _view_player():
		return false
	var ready: Dictionary = game.unit_action_readiness(game.active_field().slots.find(card))
	return bool(ready.attack) or not ready.skills.is_empty()

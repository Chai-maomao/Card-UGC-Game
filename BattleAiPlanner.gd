class_name BattleAiPlanner
extends RefCounted

const DIFFICULTIES := ["easy", "normal", "hard"]


static func generate_legal_actions(game: RefCounted) -> Array:
	var actions: Array = []
	var field: BattleField = game.active_field()
	var enemy: BattleField = game.opponent_field()
	var hand: Array = game.active_hand()
	var mana := field.get_total_mana()
	var empty_slots: Array[int] = []
	for slot in range(field.slots.size()):
		if field.slots[slot] == null:
			empty_slots.append(slot)
	for hand_index in range(hand.size()):
		var card: CardData = hand[hand_index]
		if card == null or card.cost > mana:
			continue
		if card.is_spell():
			_append_spell_actions(actions, game, card, hand_index)
		elif card.is_parasite():
			for target_player in [game.current_player, 3 - game.current_player]:
				var target_field: BattleField = game.player_field if target_player == 1 else game.player2_field
				for target_slot in range(target_field.slots.size()):
					if ParasiteRules.can_attach(card, target_field.slots[target_slot], mana).get("ok", false):
						actions.append({"type": "attach", "hand_index": hand_index, "target_player": target_player, "target_slot": target_slot})
		else:
			for slot in empty_slots:
				actions.append({"type": "summon", "hand_index": hand_index, "slot": slot})
	var taunt_slots: Array[int] = []
	for slot in range(enemy.slots.size()):
		var target: CardData = enemy.slots[slot]
		if target != null and target.is_alive() and target.has_taunt():
			taunt_slots.append(slot)
	for source_slot in range(field.slots.size()):
		var source: CardData = field.slots[source_slot]
		if source == null or not source.is_alive() or source.has_acted:
			continue
		if game.turn_number > 1 and (not source.is_silenced() or source.attack_ignores_silence):
			var targets := taunt_slots if not taunt_slots.is_empty() else _live_slots(enemy)
			for target_slot in targets:
				actions.append({"type": "attack", "source_slot": source_slot, "target_slot": target_slot})
		if not source.is_silenced():
			for skill_index in range(source.skills.size()):
				var skill: Dictionary = source.skills[skill_index]
				if str(skill.get("trigger", "")) != SkillEngine.TRIGGER_ON_ACTIVATE:
					continue
				_append_skill_actions(actions, game, source_slot, skill_index, skill)
	actions.append({"type": "end_turn"})
	return actions


static func choose_action(game: RefCounted, difficulty: String, rng: RandomNumberGenerator) -> Dictionary:
	var scored: Array = []
	for action in generate_legal_actions(game):
		var assessment := score_action(game, action)
		var candidate: Dictionary = action.duplicate(true)
		candidate["score"] = assessment["score"]
		candidate["explanation"] = assessment["factors"]
		scored.append(candidate)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) == float(b["score"]):
			return JSON.stringify(a) < JSON.stringify(b)
		return float(a["score"]) > float(b["score"])
	)
	if scored.is_empty():
		return {"type": "end_turn", "score": 0.0, "explanation": ["no_legal_action"]}
	var level := difficulty if difficulty in DIFFICULTIES else "normal"
	var pick := 0
	if level == "normal" and scored.size() > 1 and rng.randf() < 0.15:
		pick = 1
	elif level == "easy" and scored.size() > 1:
		var pool := mini(4, scored.size())
		pick = rng.randi_range(0, pool - 1)
	return scored[pick]


static func score_action(game: RefCounted, action: Dictionary) -> Dictionary:
	var factors: Array[String] = []
	var score := 0.0
	match str(action.get("type", "")):
		"attack":
			var attacker: CardData = game.active_field().slots[int(action["source_slot"])]
			var target: CardData = game.opponent_field().slots[int(action["target_slot"])]
			var damage := attacker.effective_atk()
			score += damage * 3.0
			score += target.effective_atk() * 2.0 + target.cost
			score -= attacker.cost * 0.5
			factors.append("damage:%d" % damage)
			factors.append("threat:%d" % target.effective_atk())
			if damage >= target.hp + target.temp_hp:
				score += 45.0 + target.cost * 4.0
				factors.append("lethal_trade")
			if damage < target.hp + target.temp_hp and target.effective_atk() >= attacker.hp + attacker.temp_hp:
				score -= 30.0 + attacker.cost * 4.0
				factors.append("counter_risk")
			if target.has_taunt():
				score += 8.0
				factors.append("remove_taunt")
		"summon":
			var card: CardData = game.active_hand()[int(action["hand_index"])]
			var body_value := float(card.max_hp + card.atk * 2)
			var efficiency := body_value / maxi(1.0, float(card.cost))
			score += body_value + efficiency * 2.0 + card.skills.size() * 2.5 - card.cost * 0.35
			factors.append("board_value:%.1f" % body_value)
			factors.append("efficiency:%.2f" % efficiency)
			if game.active_field().get_total_mana() - card.cost >= 2:
				score += 1.5
				factors.append("resource_reserved")
		"activate", "cast":
			var skill := _action_skill(game, action)
			var estimate := _estimate_skill(skill, game, action)
			score += estimate
			factors.append("skill_value:%.1f" % estimate)
			if str(action.get("type")) == "cast":
				var spell: CardData = game.active_hand()[int(action["hand_index"])]
				score -= spell.cost * 0.25
		"attach":
			var parasite: CardData = game.active_hand()[int(action["hand_index"])]
			var target_field: BattleField = game.player_field if int(action["target_player"]) == 1 else game.player2_field
			var host: CardData = target_field.slots[int(action["target_slot"])]
			score += parasite.hp * 2.0 + host.effective_atk() * 0.5
			factors.append("protect_host")
		"end_turn":
			score = -4.0 if _has_non_end_action(generate_legal_actions(game)) else 0.0
			factors.append("end_turn")
	return {"score": score, "factors": factors}


static func _append_spell_actions(actions: Array, game: RefCounted, card: CardData, hand_index: int) -> void:
	var check := SpellRules.can_cast(card, game.active_field().get_total_mana(), 0)
	if not bool(check.get("ok", false)):
		return
	var skill: Dictionary = check.get("skill", {})
	if not bool(check.get("needs_target", false)):
		actions.append({"type": "cast", "hand_index": hand_index, "skill_index": 0, "target_slot": -1, "target_player": 0})
		return
	_append_target_variants(actions, game, {"type": "cast", "hand_index": hand_index, "skill_index": 0}, skill)


static func _append_skill_actions(actions: Array, game: RefCounted, source_slot: int, skill_index: int, skill: Dictionary) -> void:
	if _skill_needs_target(skill):
		_append_target_variants(actions, game, {"type": "activate", "slot": source_slot, "skill_index": skill_index}, skill)
	else:
		actions.append({"type": "activate", "slot": source_slot, "skill_index": skill_index, "target_slot": -1, "target_player": 0})


static func _append_target_variants(actions: Array, game: RefCounted, base: Dictionary, skill: Dictionary) -> void:
	var side := _skill_target_side(skill)
	var players: Array = []
	if side in [SkillEngine.TARGET_SIDE_ALLY, SkillEngine.TARGET_SIDE_ALL]:
		players.append(game.current_player)
	if side in [SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALL]:
		players.append(3 - game.current_player)
	for player in players:
		var field: BattleField = game.player_field if player == 1 else game.player2_field
		for slot in _live_slots(field):
			var action := base.duplicate(true)
			action["target_slot"] = slot
			action["target_player"] = player
			actions.append(action)


static func _skill_needs_target(skill: Dictionary) -> bool:
	for effect in SkillEngine.legacy_skill_effects(skill):
		if str(effect.get("target", "")) in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			return true
	return false


static func _skill_target_side(skill: Dictionary) -> String:
	for effect in SkillEngine.legacy_skill_effects(skill):
		if str(effect.get("target", "")) in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			return str(effect.get("target_side", SkillEngine.TARGET_SIDE_ENEMY))
	return SkillEngine.TARGET_SIDE_ENEMY


static func _estimate_skill(skill: Dictionary, game: RefCounted, action: Dictionary) -> float:
	var total := 0.0
	var direct_damage := 0.0
	var healing := 0.0
	var helpful := false
	for effect in SkillEngine.legacy_skill_effects(skill):
		var value := float(effect.get("value", effect.get("value_max", 1)))
		var effect_id := str(effect.get("effect", ""))
		if effect_id in [SkillEngine.EFFECT_DAMAGE, SkillEngine.EFFECT_EXECUTE, SkillEngine.EFFECT_DISCARD_HAND, SkillEngine.EFFECT_MANA_DRAIN]:
			total += value * 3.0
			direct_damage += value
		elif effect_id in [SkillEngine.EFFECT_HEAL, SkillEngine.EFFECT_SHIELD, SkillEngine.EFFECT_GAIN_ATTACK, SkillEngine.EFFECT_GAIN_MAX_HP]:
			total += value * 2.0
			helpful = true
			if effect_id == SkillEngine.EFFECT_HEAL:
				healing += value
		elif effect_id == SkillEngine.EFFECT_DRAW_CARDS:
			total += value * 4.0
		elif effect_id == SkillEngine.EFFECT_GAIN_MANA:
			total += value * 3.0
		elif effect_id == SkillEngine.EFFECT_ADD_BUFF:
			total += 5.0 + value
			helpful = true
	if int(action.get("target_slot", -1)) >= 0 and int(action.get("target_player", 0)) == 3 - game.current_player:
		var target: CardData = game.opponent_field().slots[int(action["target_slot"])]
		if target != null:
			total += target.effective_atk() * 1.5 + target.cost * 0.5
			if direct_damage >= target.hp + target.temp_hp:
				total += 35.0
	elif helpful and int(action.get("target_slot", -1)) >= 0 and int(action.get("target_player", 0)) == game.current_player:
		var ally: CardData = game.active_field().slots[int(action["target_slot"])]
		if ally != null:
			total += mini(healing, float(maxi(0, ally.max_hp - ally.hp))) * 3.0
			total += ally.effective_atk() * 0.75
	return total


static func _action_skill(game: RefCounted, action: Dictionary) -> Dictionary:
	if str(action.get("type")) == "cast":
		var card: CardData = game.active_hand()[int(action["hand_index"])]
		return SpellRules.spell_skill(card, int(action.get("skill_index", 0)))
	var source: CardData = game.active_field().slots[int(action.get("slot", -1))]
	var index := int(action.get("skill_index", 0))
	return source.skills[index] if source != null and index >= 0 and index < source.skills.size() else {}


static func _live_slots(field: BattleField) -> Array[int]:
	var slots: Array[int] = []
	for index in range(field.slots.size()):
		if field.slots[index] != null and field.slots[index].is_alive():
			slots.append(index)
	return slots


static func _has_non_end_action(actions: Array) -> bool:
	for action in actions:
		if str(action.get("type", "")) != "end_turn":
			return true
	return false

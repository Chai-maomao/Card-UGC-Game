class_name ActionEconomyAnalyzer
extends RefCounted

const Game = preload("res://GameState.gd")


static func inspect(card: CardData) -> Array:
	var notes: Array = []
	if card == null: return notes
	if card.is_spell():
		notes.append({"key": "economy.spell"})
	elif card.is_parasite():
		notes.append({"key": "economy.parasite"})
	else:
		var active := 0
		var mana_skill := false
		for skill in card.skills:
			if str(skill.get("trigger", "")) == SkillEngine.TRIGGER_ON_ACTIVATE:
				active += 1
				mana_skill = mana_skill or _contains_effect(skill.get("effects", []), SkillRegistry.EFFECT_GAIN_MANA)
		if active > 0:
			notes.append({"key": "economy.active", "args": [active]})
		if mana_skill: notes.append({"key": "economy.mana_after_payment"})
		if active == 0: notes.append({"key": "economy.passive"})
	var has_damage := false
	var turn_end := false
	for skill in card.skills:
		for effect in [SkillRegistry.EFFECT_DAMAGE, SkillRegistry.EFFECT_EXECUTE, SkillRegistry.EFFECT_LIFESTEAL_DAMAGE]:
			has_damage = has_damage or _contains_effect(skill.get("effects", []), effect)
		turn_end = turn_end or str(skill.get("trigger", "")) == SkillEngine.TRIGGER_ON_TURN_END
	if has_damage: notes.append({"key": "economy.kill_refund"})
	if turn_end: notes.append({"key": "economy.turn_end"})
	return notes


static func _contains_effect(effects: Variant, wanted: String, depth: int = 0) -> bool:
	if not effects is Array or depth > UgcSafety.MAX_EXPRESSION_NESTING_DEPTH: return false
	for item in effects:
		if not item is Dictionary: continue
		if str(item.get("effect", "")) == wanted: return true
		for branch in ["then_effects", "else_effects"]:
			if _contains_effect(item.get(branch, []), wanted, depth + 1): return true
	return false


static func quote(action_number: int, points: int, mana: int, config: Dictionary) -> Dictionary:
	# Use the authoritative payment path. Do not simulate skills or their income.
	var game := Game.new()
	game.quiet = true
	game.player_field = BattleField.new("Quote", 30, 10)
	game.player2_field = BattleField.new("Opponent", 30, 10)
	game.player_field.quiet = true
	game.player2_field.quiet = true
	game.battle_config = config.duplicate(true)
	game.player_field.actions_taken = maxi(0, action_number - 1)
	game.player_field.action_points = maxi(0, points)
	game.player_field.current_mana = maxi(0, mana)
	return game.next_action_payment()


static func description(card: CardData) -> String:
	var lines: Array[String] = []
	for note in inspect(card):
		lines.append("• " + Locale.t(note.key, note.get("args", [])))
	return "\n\n".join(lines)


static func live_description(game: RefCounted) -> String:
	var quote: Dictionary = game.next_action_payment()
	var text := Locale.t("economy.live", [game.active_field().actions_taken + 1, quote.points, quote.mana])
	text += "\n" + Locale.t("economy.affordable" if quote.ok else "economy.unaffordable")
	return text

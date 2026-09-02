class_name SpellRules
extends RefCounted

const CAST_SKILL_INDEX := 0

const REASON_OK := "ok"
const REASON_NOT_SPELL := "not_spell"
const REASON_NO_SKILL := "no_skill"
const REASON_WRONG_TRIGGER := "wrong_trigger"
const REASON_NO_MANA := "no_mana"
const REASON_ENEMY_TARGET_TURN_ONE := "enemy_target_turn_one"


static func is_spell(card: CardData) -> bool:
	return card != null and card.is_spell()


static func spell_skill(card: CardData, skill_index: int = CAST_SKILL_INDEX) -> Dictionary:
	if not is_spell(card):
		return {}
	if skill_index < 0 or skill_index >= card.skills.size():
		return {}
	return normalize_spell_skill(card, card.skills[skill_index])


static func normalize_spell_skill(card: CardData, skill: Dictionary) -> Dictionary:
	var normalized := skill.duplicate(true)
	normalized["skill_name"] = card.card_name if card != null else normalized.get("skill_name", "")
	normalized["trigger"] = SkillEngine.TRIGGER_ON_CAST
	if not normalized.has("probability"):
		normalized["probability"] = 100
	if not normalized.has("effects"):
		var effect_name: String = normalized.get("effect", "")
		var target_name: String = normalized.get("target", "")
		if effect_name != "" or target_name != "":
			normalized["effects"] = [normalized]
		else:
			normalized["effects"] = []
	return normalized


static func normalize_spell_card(card: CardData) -> void:
	if not is_spell(card):
		return
	card.hp = 0
	card.max_hp = 0
	card.atk = 0
	if card.skills.size() > 1:
		card.skills = [card.skills[0]]
	if card.skills.size() == 1:
		card.skills[0] = normalize_spell_skill(card, card.skills[0])


static func can_cast(card: CardData, current_mana: int, skill_index: int = CAST_SKILL_INDEX, turn_number: int = 2) -> Dictionary:
	if not is_spell(card):
		return {"ok": false, "reason": REASON_NOT_SPELL}
	if skill_index < 0 or skill_index >= card.skills.size():
		return {"ok": false, "reason": REASON_NO_SKILL}
	var skill := spell_skill(card, skill_index)
	if skill.get("trigger", "") != SkillEngine.TRIGGER_ON_CAST:
		return {"ok": false, "reason": REASON_WRONG_TRIGGER}
	if card.cost > current_mana:
		return {"ok": false, "reason": REASON_NO_MANA}
	if turn_number <= 1 and targets_enemy(skill):
		return {"ok": false, "reason": REASON_ENEMY_TARGET_TURN_ONE, "skill": skill}
	return {"ok": true, "reason": REASON_OK, "skill": skill, "needs_target": needs_target(skill)}


static func targets_enemy(skill: Dictionary) -> bool:
	return _effects_target_enemy(_effects_for(skill))


static func _effects_target_enemy(effects: Array) -> bool:
	for value in effects:
		if not value is Dictionary:
			continue
		var effect: Dictionary = value
		var target := str(effect.get("target", ""))
		var side := str(effect.get("target_side", ""))
		if target == "all_enemies":
			return true
		var can_select_field := target in [
			SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_ALL,
			SkillEngine.TARGET_MALE, SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN,
		]
		if can_select_field and side in ["", SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALL]:
			return true
		for branch in ["then_effects", "else_effects"]:
			var nested = effect.get(branch, [])
			if nested is Array and _effects_target_enemy(nested):
				return true
	return false


static func needs_target(skill: Dictionary) -> bool:
	for eff in _effects_for(skill):
		var effect_name: String = eff.get("effect", "")
		if effect_name in [SkillEngine.EFFECT_DRAW_CARDS, SkillEngine.EFFECT_GAIN_MANA]:
			continue
		var target_name: String = eff.get("target", "")
		if target_name in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			return true
	return false


static func _effects_for(skill: Dictionary) -> Array:
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and (skill.get("target", "") != "" or skill.get("effect", "") != ""):
		return [skill]
	return effects

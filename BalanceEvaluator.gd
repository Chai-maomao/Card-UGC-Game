class_name BalanceEvaluator
extends RefCounted

const ATK_WEIGHT := 1.15
const HP_WEIGHT := 0.75
const POINTS_PER_COST := 2.6
const WARNING_MARGIN := 1.25
const SEVERE_MARGIN := 2.25
const WEAK_MARGIN := -1.5
const ACTIVATE_ATTACK_OPPORTUNITY_COST := 0.75
const HEAL_SOFT_CAP := 6.0
const REGEN_SOFT_CAP := 4.0

const TRIGGER_WEIGHTS := {
	"on_activate": 1.0,
	"on_summon": 0.9,
	"on_attack": 0.8,
	"on_damaged": 0.65,
	"on_death": 0.55,
	"on_cast": 1.15,
}

const TARGET_WEIGHTS := {
	"self": 1.0,
	"target_single": 1.0,
	"target_sides": 1.55,
	"self_sides": 1.45,
	"all": 2.25,
	"all_enemies": 2.0,
	"all_allies": 1.9,
	"target_male": 1.45,
	"target_female": 1.45,
	"target_nonhuman": 1.45,
}


static func evaluate_card(card: CardData) -> Dictionary:
	if card == null:
		return _result(0.0, 0, 0.0, "balanced", [])
	return evaluate_values(card.cost, card.atk, card.max_hp, card.skills)


static func evaluate_values(cost: int, atk: int, hp: int, skills: Array) -> Dictionary:
	var body_score: float = _body_score(atk, hp)
	var skill_score: float = 0.0
	for skill in skills:
		if skill is Dictionary and not skill.is_empty():
			skill_score += _skill_score(skill, atk)
	var total_score: float = max(0.0, body_score + skill_score)
	var recommended_cost: int = max(0, int(ceil(total_score / POINTS_PER_COST)))
	var gap: float = total_score - float(cost) * POINTS_PER_COST
	var level: String = "balanced"
	if gap >= SEVERE_MARGIN:
		level = "severe"
	elif gap >= WARNING_MARGIN:
		level = "strong"
	elif gap <= WEAK_MARGIN:
		level = "weak"
	var reasons: Array = _balance_reasons(level, cost, body_score, skill_score)
	return _result(total_score, recommended_cost, gap, level, reasons)


static func _body_score(atk: int, hp: int) -> float:
	var safe_atk: int = max(0, atk)
	var safe_hp: int = max(0, hp)
	return float(safe_atk) * ATK_WEIGHT + float(safe_hp) * HP_WEIGHT


static func _balance_reasons(level: String, cost: int, body_score: float, skill_score: float) -> Array:
	var reasons: Array = []
	if level == "weak":
		reasons.append("cost_high")
		return reasons
	var budget: float = float(cost) * POINTS_PER_COST
	if body_score >= budget + WARNING_MARGIN:
		reasons.append("body")
	if skill_score >= 2.0:
		reasons.append("skill")
	return reasons


static func _skill_score(skill: Dictionary, atk: int) -> float:
	var probability: float = clamp(float(skill.get("probability", 100)) / 100.0, 0.0, 1.0)
	var trigger: String = skill.get("trigger", "")
	var trigger_weight: float = float(TRIGGER_WEIGHTS.get(trigger, 0.8))
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and not skill.get("effect", "").is_empty():
		effects = [skill]
	var score: float = 0.0
	for eff in effects:
		if eff is Dictionary:
			score += _effect_score(eff)
	score *= probability
	if trigger == SkillEngine.TRIGGER_ON_ACTIVATE and score > 0.0:
		score = max(0.0, score - float(max(0, atk)) * ACTIVATE_ATTACK_OPPORTUNITY_COST)
	return score * trigger_weight


static func _polarity_multiplier(polarity: String, eff: Dictionary) -> float:
	if polarity == "harmful":
		return _harmful_target_multiplier(eff)
	return _helpful_target_multiplier(eff)


static func _effect_score(eff: Dictionary) -> float:
	var effect: String = eff.get("effect", "")
	var value: float = _effect_expected_value(eff)
	var probability: float = clamp(float(eff.get("probability", 100)) / 100.0, 0.0, 1.0)
	var target_weight: float = _target_weight(eff)
	var condition_weight: float = _condition_weight(eff)
	var meta: Dictionary = SkillRegistry.effect_meta(effect)
	var kind: String = str(meta.get("score_kind", "none"))
	var weight: float = float(meta.get("score_weight", 0.0))
	var polarity: String = str(meta.get("polarity", "helpful"))
	var score: float = 0.0
	match kind:
		"value_linear":
			score = value * weight * _polarity_multiplier(polarity, eff)
		"value_diminishing":
			score = _diminishing_value(value, HEAL_SOFT_CAP) * weight * _polarity_multiplier(polarity, eff)
		"threshold":
			score = max(1.0, value * weight) * _polarity_multiplier(polarity, eff)
		"fixed":
			score = weight * _polarity_multiplier(polarity, eff)
		"buff":
			score = _buff_score(eff) * _buff_target_multiplier(eff)
	return score * target_weight * probability * condition_weight


static func _target_weight(eff: Dictionary) -> float:
	var target: String = eff.get("target", "")
	var base_weight: float = float(TARGET_WEIGHTS.get(target, 1.0))
	var random_count: int = int(eff.get("random_count", 0))
	if random_count <= 0:
		return base_weight
	var capped_weight: float = max(1.0, float(random_count) * 0.9)
	return min(base_weight, capped_weight)


static func _condition_weight(eff: Dictionary) -> float:
	var condition_type: String = eff.get("condition_type", SkillEngine.CONDITION_NONE)
	if condition_type == "" or condition_type == SkillEngine.CONDITION_NONE:
		return 1.0
	if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
		return 0.7
	return 0.65


static func _harmful_target_multiplier(eff: Dictionary) -> float:
	var target_side: String = _effect_target_side(eff)
	if target_side == SkillEngine.TARGET_SIDE_ALLY:
		return -1.0
	if target_side == SkillEngine.TARGET_SIDE_ALL:
		return 0.2
	return 1.0


static func _helpful_target_multiplier(eff: Dictionary) -> float:
	var target_side: String = _effect_target_side(eff)
	if target_side == SkillEngine.TARGET_SIDE_ENEMY:
		return -1.0
	if target_side == SkillEngine.TARGET_SIDE_ALL:
		return 0.2
	return 1.0


static func _buff_target_multiplier(eff: Dictionary) -> float:
	var buff_id: String = eff.get("buff_id", "")
	if buff_id in [SkillEngine.BUFF_SILENCE, SkillEngine.BUFF_MISFORTUNE]:
		return _harmful_target_multiplier(eff)
	return _helpful_target_multiplier(eff)


static func _effect_target_side(eff: Dictionary) -> String:
	var target: String = eff.get("target", "")
	match target:
		SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES:
			return SkillEngine.TARGET_SIDE_ALLY
		# Legacy save compat: old cards may still carry the pre-combined
		# "all_enemies"/"all_allies" targets.
		"all_allies":
			return SkillEngine.TARGET_SIDE_ALLY
		"all_enemies":
			return SkillEngine.TARGET_SIDE_ENEMY
		SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES:
			var directed_side: String = eff.get("target_side", SkillEngine.TARGET_SIDE_ENEMY)
			return SkillEngine.TARGET_SIDE_ALLY if directed_side == SkillEngine.TARGET_SIDE_ALLY else SkillEngine.TARGET_SIDE_ENEMY
		SkillEngine.TARGET_ALL, SkillEngine.TARGET_MALE, SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN:
			return eff.get("target_side", SkillEngine.TARGET_SIDE_ALL)
	return eff.get("target_side", SkillEngine.TARGET_SIDE_ENEMY)


static func _effect_expected_value(eff: Dictionary) -> float:
	if eff.has("value_min") and eff.has("value_max"):
		return (float(eff.get("value_min", 0)) + float(eff.get("value_max", 0))) / 2.0
	if eff.has("value_var"):
		return max(1.0, float(eff.get("value_offset", 0)) + 2.0)
	return float(eff.get("value", 0))


static func _diminishing_value(value: float, soft_cap: float) -> float:
	if value <= soft_cap:
		return value
	return soft_cap + sqrt(max(0.0, value - soft_cap)) * 0.35


static func _buff_score(eff: Dictionary) -> float:
	var value: float = _effect_expected_value(eff)
	var duration: float = min(max(1.0, float(eff.get("duration", 1))), 3.0)
	match eff.get("buff_id", ""):
		SkillEngine.BUFF_ATK_BOOST:
			return value * 1.05 * duration
		SkillEngine.BUFF_REGEN:
			return _diminishing_value(value, REGEN_SOFT_CAP) * 0.65 * duration
		SkillEngine.BUFF_MANA_REFUND:
			return value * 1.2 * duration
		SkillEngine.BUFF_THORNS:
			return value * 0.7 * duration
		SkillEngine.BUFF_DAMAGE_REDUCTION:
			return max(1.0, value / 22.0) * duration
		SkillEngine.BUFF_TAUNT:
			return 1.2 * duration
		SkillEngine.BUFF_SILENCE:
			return 2.0 * min(duration, 2.0)
		SkillEngine.BUFF_MISFORTUNE:
			return max(1.0, value / 18.0) * duration
		SkillEngine.BUFF_POISON:
			return value * 0.9 * duration
		SkillEngine.BUFF_STUN:
			return 3.0 * min(duration, 2.0)
	return value * 0.45 * duration


static func _result(score: float, recommended_cost: int, gap: float, level: String, reasons: Array) -> Dictionary:
	return {
		"score": score,
		"recommended_cost": recommended_cost,
		"gap": gap,
		"level": level,
		"reasons": reasons,
	}

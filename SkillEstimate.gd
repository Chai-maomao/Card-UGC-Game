class_name SkillEstimate
extends RefCounted

# Explicit scenarios, not mathematical bounds or measured win rates.
const SCENARIOS := {
	"field_total": [0, 5, 10], "field_ally": [0, 2, 5], "field_enemy": [0, 3, 5],
	"empty_ally": [0, 3, 5], "empty_enemy": [0, 2, 5], "hand_count": [0, 3, 6],
	"enemy_hand_count": [0, 3, 6], "mana_current": [0, 5, 10], "enemy_mana": [0, 5, 10],
	"source_hp_pct": [1, 70, 100], "target_hp_pct": [1, 70, 100],
	"target_atk": [0, 3, 10], "target_cost": [0, 3, 10], "turn_number": [1, 5, 15],
	"deck_count": [0, 10, 30],
}


static func operand(data: Dictionary, scenario: int = 1, depth: int = 0) -> float:
	if depth >= UgcSafety.MAX_EXPRESSION_NESTING_DEPTH:
		return 0.0
	match str(data.get("kind", "num")):
		"var":
			return float(SCENARIOS.get(str(data.get("var_id", "")), [0, 0, 0])[scenario])
		"expr":
			var a := operand(data.get("a", {}), scenario, depth + 1)
			var b := operand(data.get("b", {}), scenario, depth + 1)
			match str(data.get("op", "+")):
				"-": return a - b
				"*": return clampf(a * b, -1000000.0, 1000000.0)
				"/": return float(SkillEngine.round_expression_result(a / b, str(data.get("rounding", "round")))) if b != 0 else 0.0
				"rand": return minf(a, b) if scenario == 0 else (maxf(a, b) if scenario == 2 else (a + b) / 2.0)
				_: return a + b
	return float(data.get("value", 0))


static func value(effect: Dictionary, scenario: int = 1, prefix: String = "value") -> float:
	var result: float
	if effect.has(prefix + "_expr"):
		result = operand(effect[prefix + "_expr"], scenario)
	elif not str(effect.get(prefix + "_var", "")).is_empty():
		result = operand({"kind": "var", "var_id": effect[prefix + "_var"]}, scenario) + float(effect.get(prefix + "_offset", 0))
	elif effect.has(prefix + "_min") and effect.has(prefix + "_max"):
		var a := float(effect[prefix + "_min"])
		var b := float(effect[prefix + "_max"])
		result = minf(a, b) if scenario == 0 else (maxf(a, b) if scenario == 2 else (a + b) / 2.0)
	else:
		result = float(effect.get("repeat_count", 2)) if prefix == "repeat" else float(effect.get("value", 1))
	if prefix == "repeat":
		return clampf(result, 0, UgcSafety.MAX_REPEAT_COUNT)
	return result if SkillRegistry.allows_negative(str(effect.get("effect", ""))) else maxf(0, result)


static func uncertain(value_data: Variant) -> bool:
	if value_data is Dictionary:
		if value_data.get("kind") == "var" or value_data.get("op") == "rand":
			return true
		for key in value_data:
			if key in ["value_var", "repeat_var", "value_min", "condition_type", "condition", "random_count"]:
				return true
			if key == "probability" and int(value_data[key]) < 100:
				return true
			if uncertain(value_data[key]):
				return true
	elif value_data is Array:
		for child in value_data:
			if uncertain(child):
				return true
	return false


static func condition_weight(effect: Dictionary, depth: int = 0) -> float:
	if depth >= UgcSafety.MAX_EXPRESSION_NESTING_DEPTH: return 0.5
	var condition: Dictionary = effect.get("condition", effect)
	if condition.has("logic"):
		var kind := str(condition.logic)
		if kind == "not": return 1.0 - condition_weight(condition.get("child", {}), depth + 1)
		var left := condition_weight(condition.get("lhs", {}), depth + 1)
		var right := condition_weight(condition.get("rhs", {}), depth + 1)
		return left * right if kind == "and" else 1.0 - (1.0 - left) * (1.0 - right)
	if condition.has("lhs") and not uncertain(condition):
		var a := operand(condition.get("lhs", {}))
		var b := operand(condition.get("rhs", {}))
		match str(condition.get("op", ">=")):
			">=": return 1.0 if a >= b else 0.0
			"<=": return 1.0 if a <= b else 0.0
			"==": return 1.0 if a == b else 0.0
	if condition.has("lhs") or condition.has("logic"):
		return 0.5
	var kind := str(condition.get("condition_type", "none"))
	return 1.0 if kind in ["", "none"] else 0.65

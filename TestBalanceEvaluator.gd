extends Node


func _ready() -> void:
	_test_active_skill_opportunity_cost()
	_test_target_side_signs()
	_test_random_target_cap_and_conditions()
	_test_large_heal_has_diminishing_returns()
	print("TEST_BALANCE_EVALUATOR_OK")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)


func _test_active_skill_opportunity_cost() -> void:
	var passive_result: Dictionary = BalanceEvaluator.evaluate_values(2, 4, 4, [{
		"skill_name": "反击",
		"trigger": SkillEngine.TRIGGER_ON_ATTACK,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}],
	}])
	var active_result: Dictionary = BalanceEvaluator.evaluate_values(2, 4, 4, [{
		"skill_name": "主动打击",
		"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}],
	}])
	if float(active_result.get("score", 0.0)) >= float(passive_result.get("score", 0.0)):
		_fail("active skill opportunity cost did not reduce score")


func _test_target_side_signs() -> void:
	var enemy_damage: Dictionary = BalanceEvaluator.evaluate_values(1, 0, 1, [{
		"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 3}],
	}])
	var ally_damage: Dictionary = BalanceEvaluator.evaluate_values(1, 0, 1, [{
		"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 3}],
	}])
	if float(ally_damage.get("score", 0.0)) >= float(enemy_damage.get("score", 0.0)):
		_fail("ally-targeted damage should score lower than enemy damage")


func _test_random_target_cap_and_conditions() -> void:
	var broad: Dictionary = BalanceEvaluator.evaluate_values(1, 0, 1, [{
		"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2, "random_count": 0}],
	}])
	var limited_conditional: Dictionary = BalanceEvaluator.evaluate_values(1, 0, 1, [{
		"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2, "random_count": 1, "condition_type": SkillEngine.CONDITION_TARGET_HP_PCT, "condition_op": SkillEngine.CONDITION_OP_LTE, "condition_value": 50}],
	}])
	if float(limited_conditional.get("score", 0.0)) >= float(broad.get("score", 0.0)):
		_fail("random target cap and condition should reduce score")


func _test_large_heal_has_diminishing_returns() -> void:
	var small_heal: Dictionary = BalanceEvaluator.evaluate_values(1, 0, 1, [{
		"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 6}],
	}])
	var huge_heal: Dictionary = BalanceEvaluator.evaluate_values(1, 0, 1, [{
		"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 100}],
	}])
	var small_score: float = float(small_heal.get("score", 0.0))
	var huge_score: float = float(huge_heal.get("score", 0.0))
	if huge_score >= small_score * 2.0:
		_fail("huge heal should have strong diminishing returns")

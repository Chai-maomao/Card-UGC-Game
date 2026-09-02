extends Node

const Safety = preload("res://UgcSafety.gd")

var failures: Array[String] = []


class MockEditor:
	extends Control
	var effect_data: Array = []


func _ready() -> void:
	_test_validation_limits()
	_test_editor_layer()
	_test_import_layer()
	_test_runtime_repeat_clamp()
	_test_runtime_node_budget()
	_test_runtime_expression_depth()
	_test_trigger_chain_budget()
	if failures.is_empty():
		print("TEST_UGC_SAFETY_OK")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error("TEST_UGC_SAFETY_FAILED: %s" % message)
		get_tree().quit(1)


func _test_validation_limits() -> void:
	var repeat_skill := _skill([{"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 1000000, "then_effects": []}])
	_assert(_has_code(Safety.validate_skill(repeat_skill), "repeat_limit"), "million-repeat skill must be rejected")

	var nested: Array = [{"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1}]
	for _i in range(Safety.MAX_EFFECT_NESTING_DEPTH + 2):
		nested = [{"effect": SkillEngine.EFFECT_IF, "condition_type": SkillEngine.CONDITION_NONE, "then_effects": nested}]
	_assert(_has_code(Safety.validate_skill(_skill(nested)), "effect_depth"), "deep effect tree must be rejected")

	var many: Array = []
	for _i in range(Safety.MAX_EFFECT_NODES_PER_SKILL + 1):
		many.append({"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1})
	_assert(_has_code(Safety.validate_skill(_skill(many)), "skill_node_limit"), "oversized skill must be rejected")

	var card := {"skills": [_skill(many.slice(0, 70)), _skill(many.slice(0, 70)), _skill(many.slice(0, 70))]}
	_assert(_has_code(Safety.validate_serialized_card(card), "card_node_limit"), "card-wide node budget must be enforced")


func _test_editor_layer() -> void:
	var editor := MockEditor.new()
	editor.effect_data = [{"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 999999, "then_effects": []}]
	var checker := SkillErrorChecker.new()
	checker.editor = editor
	var issues := checker.collect_issues()
	var found := false
	for issue in issues:
		if str(issue.get("kind", "")) == "ugc_safety":
			found = true
	_assert(found, "skill editor checker must surface UGC safety errors")
	editor.queue_free()


func _test_import_layer() -> void:
	var package := {
		"version": PlayerData.SHARE_VERSION,
		"type": "cards",
		"cards": [{
			"name": "Unsafe", "cost": 1, "max_hp": 1, "atk": 0,
			"skills": [_skill([{"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 999999, "then_effects": []}])],
		}],
	}
	var parsed := PlayerData.parse_share_package(JSON.stringify(package))
	_assert(not bool(parsed.get("ok", true)), "share import must reject unsafe skills before deserialization")
	var prepared := PlayerData.prepare_import_cards(package)
	_assert(bool(prepared.get("invalid", false)), "prepared import must revalidate callers that bypass parsing")


func _test_runtime_repeat_clamp() -> void:
	var source := CardData.new("Repeat Clamp", 1, 5, 0, [])
	var skill := _skill([{
		"effect": SkillEngine.EFFECT_REPEAT,
		"repeat_count": 1000000,
		"then_effects": [{"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1}],
	}])
	SkillEngine.trigger_external_skill(skill, source, _context())
	_assert(source.field_atk_bonus == Safety.MAX_REPEAT_COUNT, "runtime must clamp repeat count to %d, got %d" % [Safety.MAX_REPEAT_COUNT, source.field_atk_bonus])


func _test_runtime_node_budget() -> void:
	var source := CardData.new("Node Budget", 1, 5, 0, [])
	var body: Array = []
	for _i in range(20):
		body.append({"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1})
	var skill := _skill([{"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 20, "then_effects": body}])
	var context := _context()
	SkillEngine.trigger_external_skill(skill, source, context)
	var budget: Dictionary = context.get("_ugc_budget", {})
	_assert(bool(budget.get("aborted", false)), "runtime node budget must abort oversized execution")
	_assert(source.field_atk_bonus < 400, "runtime node budget failed to stop repeated effects")
	_assert(int(budget.get("effect_nodes", 0)) == Safety.MAX_EXECUTED_EFFECT_NODES + 1, "node budget must stop immediately after the limit")


func _test_runtime_expression_depth() -> void:
	var source := CardData.new("Expression Budget", 1, 5, 0, [])
	var expression: Dictionary = {"kind": "num", "value": 1}
	for _i in range(Safety.MAX_EXPRESSION_NESTING_DEPTH + 2):
		expression = {"kind": "expr", "op": "+", "a": expression, "b": {"kind": "num", "value": 1}}
	var context := _context()
	SkillEngine.trigger_external_skill(_skill([{
		"effect": SkillEngine.EFFECT_GAIN_ATTACK,
		"target": SkillEngine.TARGET_SELF,
		"value_expr": expression,
	}]), source, context)
	var budget: Dictionary = context.get("_ugc_budget", {})
	_assert(bool(budget.get("aborted", false)), "runtime expression depth must abort unvalidated deep expressions")
	_assert(source.field_atk_bonus == 0, "aborted expression must not apply a partial value")


func _test_trigger_chain_budget() -> void:
	var source := CardData.new("Recursive Healer", 1, 5, 0, [])
	source.skills = [{
		"skill_name": "Again", "trigger": SkillEngine.TRIGGER_ON_HEALED, "probability": 100,
		"effects": [{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 1}],
	}]
	var context := _context()
	SkillEngine.trigger_external_skill(_skill([{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 1}]), source, context)
	var budget: Dictionary = context.get("_ugc_budget", {})
	_assert(bool(budget.get("aborted", false)), "recursive trigger chain must be aborted")
	_assert(int(budget.get("trigger_depth", 0)) == 0, "trigger depth must unwind after abort")


func _skill(effects: Array) -> Dictionary:
	return {"skill_name": "Safety Test", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100, "effects": effects}


func _context() -> Dictionary:
	return {
		"player_field": null, "enemy_field": null,
		"active_hand": [], "enemy_hand": [], "shared_deck": [], "discard_pile": [],
		"turn_number": 2, "current_player": 1, "rng": RandomNumberGenerator.new(),
	}


func _has_code(issues: Array, code: String) -> bool:
	for issue in issues:
		if str(issue.get("code", "")) == code:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

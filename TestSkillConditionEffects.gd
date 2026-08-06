extends Node

# Headless test for the Scratch-block data structures the editor now produces:
#   - effect-level conditions stored as eff["condition"] (boolean reporter
#     {op,lhs,rhs} or {logic,...} tree) evaluated by _passes_effect_condition;
#   - dynamic value resolution: variable + offset, math expressions (incl.
#     rand) and the legacy value_min/value_max range fields.
# Run: godot --headless --path . res://TestSkillConditionEffects.tscn

var failures: Array = []


func _ready() -> void:
	_test_effect_condition_boolean()
	_test_effect_condition_logic()
	_test_effect_condition_legacy_fields()
	_test_value_offset()
	_test_value_expr()
	_test_value_range()
	if failures.is_empty():
		print("TEST_SKILL_CONDITION_EFFECTS_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


func _src_card() -> CardData:
	return CardData.new("src", 1, 5, 1, [])


func _tgt_card() -> CardData:
	return CardData.new("tgt", 1, 5, 1, [])


func _ctx(hand_size: int) -> Dictionary:
	var hand: Array = []
	for i in range(hand_size):
		hand.append(CardData.new("h%d" % i, 1, 1, 0, []))
	return {
		"player_field": null,
		"enemy_field": null,
		"active_hand": hand,
		"enemy_hand": [],
		"turn_number": 2,
		"rng": RandomNumberGenerator.new(),
	}


func _test_effect_condition_boolean() -> void:
	var src := _src_card()
	var tgt := _tgt_card()
	var eff := {
		"effect": SkillEngine.EFFECT_DAMAGE,
		"condition": {
			"op": SkillEngine.CONDITION_OP_GTE,
			"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
			"rhs": {"kind": "num", "value": 2},
		},
	}
	if not SkillEngine._passes_effect_condition(eff, src, tgt, _ctx(2)):
		_fail("boolean effect condition (hand>=2, 2 cards) should pass")
	if SkillEngine._passes_effect_condition(eff, src, tgt, _ctx(1)):
		_fail("boolean effect condition (hand>=2, 1 card) should fail")
	# Target stat reporter inside the condition.
	var atk_eff := {
		"effect": SkillEngine.EFFECT_DAMAGE,
		"condition": {
			"op": SkillEngine.CONDITION_OP_EQ,
			"lhs": {"kind": "var", "var_id": SkillEngine.VAR_TARGET_ATK},
			"rhs": {"kind": "num", "value": 1},
		},
	}
	if not SkillEngine._passes_effect_condition(atk_eff, src, tgt, _ctx(0)):
		_fail("target-atk==1 condition should pass for 1-atk target")


func _test_effect_condition_logic() -> void:
	var src := _src_card()
	var tgt := _tgt_card()
	var eff := {
		"effect": SkillEngine.EFFECT_HEAL,
		"condition": {
			"logic": "and",
			"lhs": {"op": SkillEngine.CONDITION_OP_GTE, "lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT}, "rhs": {"kind": "num", "value": 2}},
			"rhs": {"op": SkillEngine.CONDITION_OP_LTE, "lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT}, "rhs": {"kind": "num", "value": 3}},
		},
	}
	if not SkillEngine._passes_effect_condition(eff, src, tgt, _ctx(2)):
		_fail("logic AND condition (hand 2..3, 2 cards) should pass")
	if SkillEngine._passes_effect_condition(eff, src, tgt, _ctx(4)):
		_fail("logic AND condition (hand 2..3, 4 cards) should fail")


func _test_effect_condition_legacy_fields() -> void:
	# Legacy direct-field conditions still work (regression guard).
	var src := _src_card()
	var tgt := _tgt_card()
	var eff := {
		"effect": SkillEngine.EFFECT_DAMAGE,
		"condition_type": SkillEngine.CONDITION_HAND_COUNT,
		"condition_op": SkillEngine.CONDITION_OP_GTE,
		"condition_value": 1,
	}
	if not SkillEngine._passes_effect_condition(eff, src, tgt, _ctx(1)):
		_fail("legacy condition_type field should still evaluate")


func _test_value_offset() -> void:
	var src := _src_card()
	var eff := {"effect": SkillEngine.EFFECT_DAMAGE, "value_var": SkillEngine.VAR_HAND_COUNT, "value_offset": 3}
	var got: int = SkillEngine._resolve_value(eff, src, _ctx(2))
	if got != 5:
		_fail("value_var+offset: expected 2+3=5, got %d" % got)


func _test_value_expr() -> void:
	var src := _src_card()
	# Deterministic rand (3..3) + arithmetic nesting.
	var eff := {
		"effect": SkillEngine.EFFECT_DAMAGE,
		"value_expr": {"kind": "expr", "op": "+", "a": {"kind": "num", "value": 2},
				"b": {"kind": "expr", "op": "rand", "a": {"kind": "num", "value": 3}, "b": {"kind": "num", "value": 3}}},
	}
	var got: int = SkillEngine._resolve_value(eff, src, _ctx(0))
	if got != 5:
		_fail("nested expr (2 + rand(3,3)): expected 5, got %d" % got)


func _test_value_range() -> void:
	var src := _src_card()
	var eff := {"effect": SkillEngine.EFFECT_DAMAGE, "value_min": 4, "value_max": 4}
	var got: int = SkillEngine._resolve_value(eff, src, _ctx(0))
	if got != 4:
		_fail("value_min/value_max range: expected 4, got %d" % got)

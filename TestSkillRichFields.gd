extends Node

# ============================================
# Rich-field round-trip tests: every editor field a block can produce
# (nested math expr, var + offset, rand interval, random_count, probability,
# target_side, condition booleans, buff/duration) must survive
#  - CardData serialize -> JSON -> deserialize
#  - SkillEditor load -> _editor_state -> JSON -> _apply_state
# so saved skills reopen byte-identical in the editor and engine.
# ============================================

var failures: Array = []


func _ready() -> void:
	Locale.language = "zh"
	_test_card_serialize_round_trip()
	_test_editor_state_round_trip()
	await get_tree().process_frame
	if failures.is_empty():
		print("TEST_SKILL_RICH_FIELDS_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _rich_skill() -> Dictionary:
	return {
		"skill_name": "富字段测试",
		"trigger": SkillEngine.TRIGGER_ON_ATTACK,
		"probability": 60,
		"max_uses": 2,
		"skill_type": SkillEngine.SKILL_TYPE_TALENT,
		"effects": [
			{
				# Nested math expr + boolean condition + random_count.
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value": 0,
				"value_expr": {
					"kind": "expr", "op": "rand",
					"a": {"kind": "var", "var_id": SkillEngine.VAR_FIELD_TOTAL},
					"b": {"kind": "num", "value": 3},
				},
				"probability": 100,
				"random_count": 2,
				"condition": {
					"logic": "and",
					"lhs": {
						"op": SkillEngine.CONDITION_OP_GTE,
						"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
						"rhs": {"kind": "num", "value": 2},
					},
					"rhs": {
						"op": SkillEngine.CONDITION_OP_LTE,
						"lhs": {"kind": "num", "value": 1},
						"rhs": {"kind": "num", "value": 5},
					},
				},
			},
			{
				"target": SkillEngine.TARGET_SELF,
				"target_side": SkillEngine.TARGET_SIDE_ALL,
				"effect": SkillEngine.EFFECT_ADD_BUFF,
				"buff_id": SkillEngine.BUFF_THORNS,
				"duration": 3,
				"value": 2,
				"probability": 50,
				"random_count": 1,
			},
			{
				# Variable mode with offset.
				"target": SkillEngine.TARGET_ALL,
				"target_side": SkillEngine.TARGET_SIDE_ALLY,
				"effect": SkillEngine.EFFECT_DRAW_CARDS,
				"value_var": SkillEngine.VAR_HAND_COUNT,
				"value_offset": -1,
				"probability": 100,
			},
			{
				# Random interval mode.
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ALLY,
				"effect": SkillEngine.EFFECT_HEAL,
				"value_min": 2,
				"value_max": 5,
				"probability": 30,
			},
		],
	}


func _test_card_serialize_round_trip() -> void:
	var skill := _rich_skill()
	var card := CardData.new("富字段卡", 3, 4, 2, [skill])
	var dict: Dictionary = PlayerData.serialize_card(card)
	var json_str := JSON.stringify(dict, "\t")
	var parsed = JSON.parse_string(json_str)
	_assert(parsed is Dictionary, "card JSON parse failed")
	var card2: CardData = PlayerData.deserialize_card(parsed)
	_assert(card2.skills.size() == 1, "skills lost after round-trip (size=%d)" % card2.skills.size())
	if card2.skills.is_empty():
		return
	var skill2: Dictionary = card2.skills[0]
	_assert(str(skill2.get("trigger", "")) == SkillEngine.TRIGGER_ON_ATTACK, "trigger lost: %s" % str(skill2.get("trigger", "?")))
	_assert(int(skill2.get("probability", -1)) == 60, "probability lost: %s" % str(skill2.get("probability", "?")))
	_assert(int(skill2.get("max_uses", -1)) == 2, "max_uses lost")
	_assert(int(skill2.get("skill_type", -1) == SkillEngine.SKILL_TYPE_TALENT), "skill_type lost")
	var effs: Array = skill2.get("effects", [])
	_assert(effs.size() == 4, "effects count lost (size=%d)" % effs.size())
	if effs.size() != 4:
		return
	var e0: Dictionary = effs[0]
	_assert(e0.get("value_expr", {}) is Dictionary, "value_expr not a dict")
	var expr: Dictionary = e0.get("value_expr", {})
	_assert(str(expr.get("op", "")) == "rand", "expr.op lost: %s" % str(expr.get("op", "?")))
	_assert(str((expr.get("a", {}) as Dictionary).get("var_id", "")) == SkillEngine.VAR_FIELD_TOTAL, "expr var operand lost")
	_assert(int((expr.get("b", {}) as Dictionary).get("value", -1)) == 3, "expr num operand lost")
	_assert(int(e0.get("random_count", -1)) == 2, "random_count lost")
	_assert(int(e0.get("probability", -1)) == 100, "effect probability lost")
	var cond: Dictionary = e0.get("condition", {})
	_assert(str(cond.get("logic", "")) == "and", "condition logic lost")
	_assert(str((cond.get("lhs", {}) as Dictionary).get("op", "")) == SkillEngine.CONDITION_OP_GTE, "condition nested lhs lost")
	_assert(str((cond.get("rhs", {}) as Dictionary).get("op", "")) == SkillEngine.CONDITION_OP_LTE, "condition nested rhs lost")
	var e1: Dictionary = effs[1]
	_assert(str(e1.get("buff_id", "")) == SkillEngine.BUFF_THORNS, "buff_id lost")
	_assert(int(e1.get("duration", -1)) == 3, "duration lost")
	_assert(int(e1.get("random_count", -1)) == 1, "buff random_count lost")
	_assert(int(e1.get("probability", -1)) == 50, "buff probability lost")
	var e2: Dictionary = effs[2]
	_assert(str(e2.get("value_var", "")) == SkillEngine.VAR_HAND_COUNT, "value_var lost")
	_assert(int(e2.get("value_offset", 999)) == -1, "value_offset lost")
	var e3: Dictionary = effs[3]
	_assert(int(e3.get("value_min", -1)) == 2, "value_min lost")
	_assert(int(e3.get("value_max", -1)) == 5, "value_max lost")
	_assert(int(e3.get("probability", -1)) == 30, "heal probability lost")


func _test_editor_state_round_trip() -> void:
	var scene: PackedScene = load("res://SkillEditor.tscn")
	var sed: Node = scene.instantiate()
	add_child(sed)
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerData.card_draft = {
		"name": "富字段卡",
		"cost": 3, "hp": 4, "atk": 2, "gender": "male",
		"card_type": "minion",
		"art_path": "",
		"skill1": {}, "skill2": {}, "skill3": {},
	}
	PlayerData.editing_skill_index = 1
	sed.call("_load_skill", _rich_skill())
	var state: Dictionary = sed.call("_editor_state")
	var json_str := JSON.stringify(state, "\t")
	var state2 = JSON.parse_string(json_str)
	_assert(state2 is Dictionary, "editor state JSON parse failed")
	sed.call("_apply_state", state2)
	var ed: Array = sed.get("effect_data")
	_assert(ed.size() == 4, "editor effects lost (size=%d)" % ed.size())
	if ed.size() != 4:
		return
	var e0: Dictionary = ed[0]
	_assert(str((e0.get("value_expr", {}) as Dictionary).get("op", "")) == "rand", "editor expr op lost")
	_assert(str(((e0.get("value_expr", {}) as Dictionary).get("a", {}) as Dictionary).get("var_id", "")) == SkillEngine.VAR_FIELD_TOTAL, "editor expr var lost")
	_assert(str((e0.get("condition", {}) as Dictionary).get("logic", "")) == "and", "editor condition lost")
	_assert(int(e0.get("random_count", -1)) == 2, "editor random_count lost")
	var e1: Dictionary = ed[1]
	_assert(str(e1.get("buff_id", "")) == SkillEngine.BUFF_THORNS, "editor buff_id lost")
	_assert(int(e1.get("duration", -1)) == 3, "editor duration lost")
	var e2: Dictionary = ed[2]
	_assert(str(e2.get("value_var", "")) == SkillEngine.VAR_HAND_COUNT, "editor value_var lost")
	_assert(int(e2.get("value_offset", 999)) == -1, "editor value_offset lost")
	var e3: Dictionary = ed[3]
	_assert(int(e3.get("value_min", -1)) == 2, "editor value_min lost")
	_assert(int(e3.get("value_max", -1)) == 5, "editor value_max lost")
	_assert(int(e3.get("probability", -1)) == 30, "editor probability lost")


func _assert(cond: bool, message: String) -> void:
	if not cond:
		failures.append(message)

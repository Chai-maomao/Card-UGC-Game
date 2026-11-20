extends Node

const _Formatter = preload("res://SkillTextFormatter.gd")
const _ErrorChecker = preload("res://SkillErrorChecker.gd")
const GameStateScript = preload("res://GameState.gd")

var failures: Array = []
var matrix_cases := 0


func _ready() -> void:
	_test_registry_cartesian_matrix()
	_test_trigger_effect_target_matrix()
	_test_dynamic_value_matrix()
	_test_target_resolution_matrix()
	_test_condition_matrix()
	_test_per_target_execution()
	_test_nested_control_and_targeting()
	_test_semantic_guards()
	_test_non_positive_and_event_guards()
	_test_zero_cost_random_contract()
	_test_turn_one_rule_scope()
	if failures.is_empty():
		print("TEST_SKILL_COMBINATION_MATRIX_OK cases=%d" % matrix_cases)
		get_tree().quit(0)
	else:
		for message in failures:
			push_error(message)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


func _valid_target_sides(target_id: String, effect_id: String = "") -> Array:
	var forced := SkillRegistry.forced_target_side(effect_id)
	if forced != "":
		return [forced]
	if target_id in [SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES]:
		return [SkillEngine.TARGET_SIDE_ALL]
	if target_id in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_PLAYER]:
		return [SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALLY]
	return SkillRegistry.TARGET_SIDE_IDS


func _base_effect(effect_id: String, target_id: String, side_id: String) -> Dictionary:
	return {
		"effect": effect_id,
		"target": target_id,
		"target_side": side_id,
		"value": 2,
		"buff_id": SkillEngine.BUFF_ATK_BOOST,
		"duration": 2,
		"probability": 100,
	}


func _test_registry_cartesian_matrix() -> void:
	var old_language := Locale.language
	for effect_id: String in SkillRegistry.EFFECT_IDS:
		var meta := SkillRegistry.effect_meta(effect_id)
		if str(meta.get("handler", "")) == "":
			_fail("effect %s has no runtime handler" % effect_id)
		var targets: Array = [SkillEngine.TARGET_SELF] if SkillRegistry.force_self(effect_id) else SkillRegistry.allowed_targets(effect_id)
		for target_id: String in targets:
			for side_id: String in _valid_target_sides(target_id, effect_id):
				for value_mode in ["fixed", "global_var", "target_var", "expr"]:
					for condition_id: String in SkillRegistry.CONDITION_IDS:
						var eff := _base_effect(effect_id, target_id, side_id)
						match value_mode:
							"global_var":
								eff.erase("value")
								eff["value_var"] = SkillEngine.VAR_HAND_COUNT
							"target_var":
								eff.erase("value")
								eff["value_var"] = SkillEngine.VAR_TARGET_ATK
							"expr":
								eff.erase("value")
								eff["value_expr"] = {"kind": "expr", "op": "+", "a": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT}, "b": {"kind": "num", "value": 1}}
						if condition_id != SkillEngine.CONDITION_NONE:
							eff["condition_type"] = condition_id
							eff["condition_op"] = SkillEngine.CONDITION_OP_GTE
							eff["condition_value"] = 1
							if condition_id == SkillEngine.CONDITION_TARGET_HAS_BUFF:
								eff["condition_buff_id"] = SkillEngine.BUFF_TAUNT
						for language in ["zh", "en"]:
							Locale.language = language
							var text := _Formatter.format_effect_sentence(eff)
							matrix_cases += 1
							if text == "" or text.contains("{") or text.contains("}"):
								_fail("unrendered text: %s/%s/%s/%s => %s" % [effect_id, target_id, side_id, language, text])
						if SkillRegistry.requires_live_target(effect_id) and target_id in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
							var should_name_side := Locale.term("target_side", side_id)
							var text := _Formatter.format_effect_sentence(eff)
							if should_name_side != "" and not text.contains(should_name_side):
								_fail("directed target text omitted side: %s" % text)
	Locale.language = old_language


func _test_trigger_effect_target_matrix() -> void:
	var unavailable := [SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_TURN_START,
		SkillEngine.TRIGGER_ON_TURN_END, SkillEngine.TRIGGER_ON_HEALED, SkillEngine.TRIGGER_ON_BOARD_CHANGED]
	for trigger_id: String in SkillRegistry.TRIGGER_META.keys():
		for effect_id: String in SkillRegistry.EFFECT_IDS:
			var targets: Array = [SkillEngine.TARGET_SELF] if SkillRegistry.force_self(effect_id) else SkillRegistry.allowed_targets(effect_id)
			for target_id: String in targets:
				for side_id: String in _valid_target_sides(target_id, effect_id):
					var eff := _base_effect(effect_id, target_id, side_id)
					var issues := _ErrorChecker.collect_semantic_issues([eff], trigger_id)
					var should_reject: bool = SkillRegistry.requires_live_target(effect_id) \
							and target_id in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] \
							and trigger_id in unavailable
					should_reject = should_reject or target_id == SkillEngine.TARGET_PLAYER \
							and not SkillRegistry.allows_player_target(effect_id)
					should_reject = should_reject or trigger_id == SkillEngine.TRIGGER_ON_DEATH \
							and effect_id == SkillEngine.EFFECT_CHARM \
							and target_id in [SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES]
					should_reject = should_reject or trigger_id == SkillEngine.TRIGGER_ALWAYS \
							and not SkillRegistry.is_effect_allowed_for_talent_trigger(effect_id, trigger_id)
					should_reject = should_reject or SkillRegistry.is_talent_only_effect(effect_id) \
							and not SkillRegistry.is_effect_allowed_for_talent_trigger(effect_id, trigger_id)
					matrix_cases += 1
					if should_reject and issues.is_empty():
						_fail("trigger matrix accepted impossible %s/%s/%s" % [trigger_id, effect_id, target_id])
					elif not should_reject and not issues.is_empty():
						_fail("trigger matrix rejected legal %s/%s/%s: %s" % [trigger_id, effect_id, target_id, issues])
					# The same trigger can belong to a normal skill or a talent.
					# Talent restrictions must be checked in the actual editor mode.
					var talent_issues := _ErrorChecker.collect_semantic_issues([eff], trigger_id, true)
					var talent_reject := should_reject or not SkillRegistry.is_effect_allowed_for_talent_trigger(effect_id, trigger_id)
					matrix_cases += 1
					if talent_issues.is_empty() == talent_reject:
						_fail("talent matrix disagreed for %s/%s/%s: %s" % [trigger_id, effect_id, target_id, talent_issues])
		var fx := _fixture()
		var game = fx.game
		var source: CardData = fx.source
		source.skills = [{"skill_name": "trigger probe", "trigger": trigger_id, "effects": [{"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 1}]}]
		SkillEngine.trigger_skills(trigger_id, source, game.make_skill_context(2, -1))
		matrix_cases += 1
		if source.field_atk_bonus != 1:
			_fail("registered trigger %s did not execute" % trigger_id)


func _fixture() -> Dictionary:
	var game = GameStateScript.new()
	game.init_game(Callable())
	game.shared_deck.clear()
	game.shared_discard.clear()
	game.player_hand.clear()
	game.player2_hand.clear()
	for i in range(5):
		game.player_field.slots[i] = null
		game.player2_field.slots[i] = null
	game.current_player = 1
	game.turn_number = 2
	var source := CardData.new("source", 2, 10, 4, [])
	game.player_field.slots[2] = source
	return {"game": game, "source": source}


func _test_dynamic_value_matrix() -> void:
	var fx := _fixture()
	var game = fx.game
	var source: CardData = fx.source
	var target := CardData.new("target", 7, 20, 6, [])
	target.hp = 5
	game.player2_field.slots[1] = target
	game.player_hand.append(CardData.new("h", 1, 1, 0, []))
	game.player2_hand.append(CardData.new("eh", 1, 1, 0, []))
	var context: Dictionary = game.make_skill_context(2, 1)
	var expected := {
		SkillEngine.VAR_FIELD_TOTAL: 2,
		SkillEngine.VAR_FIELD_ALLY: 1,
		SkillEngine.VAR_FIELD_ENEMY: 1,
		SkillEngine.VAR_EMPTY_ALLY: 4,
		SkillEngine.VAR_EMPTY_ENEMY: 4,
		SkillEngine.VAR_HAND_COUNT: 1,
		SkillEngine.VAR_ENEMY_HAND_COUNT: 1,
		SkillEngine.VAR_TURN_NUMBER: 2,
		SkillEngine.VAR_DECK_COUNT: 0,
		SkillEngine.VAR_SOURCE_HP_PCT: 100,
		SkillEngine.VAR_TARGET_HP_PCT: 25,
		SkillEngine.VAR_TARGET_ATK: 6,
		SkillEngine.VAR_TARGET_COST: 7,
	}
	for var_id: String in expected:
		var eff := {"effect": SkillEngine.EFFECT_GAIN_ATTACK, "value_var": var_id}
		var actual := SkillEngine._resolve_value(eff, source, target, context)
		matrix_cases += 1
		if actual != expected[var_id]:
			_fail("variable %s expected %d, got %d" % [var_id, expected[var_id], actual])
	for op in ["+", "-", "*", "/", "rand"]:
		var eff := {"effect": SkillEngine.EFFECT_DAMAGE, "value_expr": {"kind": "expr", "op": op, "a": {"kind": "num", "value": 6}, "b": {"kind": "num", "value": 2}}}
		var expected_value: int = {"+": 8, "-": 4, "*": 12, "/": 3, "rand": -1}[op]
		var actual := SkillEngine._resolve_value(eff, source, target, context)
		matrix_cases += 1
		if op == "rand":
			if actual < 2 or actual > 6:
				_fail("random expression escaped bounds: %d" % actual)
		elif actual != expected_value:
			_fail("operator %s expected %d, got %d" % [op, expected_value, actual])


func _test_target_resolution_matrix() -> void:
	var fx := _fixture()
	var game = fx.game
	var source: CardData = fx.source
	source.gender = "male"
	var ally_f := CardData.new("ally_f", 1, 5, 1, [])
	ally_f.gender = "female"
	var ally_n := CardData.new("ally_n", 1, 5, 1, [])
	ally_n.gender = "nonhuman"
	game.player_field.slots[1] = ally_f
	game.player_field.slots[3] = ally_n
	var enemy_m := CardData.new("enemy_m", 1, 5, 1, [])
	enemy_m.gender = "male"
	var enemy_f := CardData.new("enemy_f", 1, 5, 1, [])
	enemy_f.gender = "female"
	var enemy_n := CardData.new("enemy_n", 1, 5, 1, [])
	enemy_n.gender = "nonhuman"
	game.player2_field.slots[0] = enemy_m
	game.player2_field.slots[1] = enemy_f
	game.player2_field.slots[2] = enemy_n
	var context: Dictionary = game.make_skill_context(2, 1)
	for target_id: String in SkillRegistry.TARGET_IDS:
		for side_id: String in _valid_target_sides(target_id):
			var targets := SkillEngine._resolve_targets(target_id, source, context, side_id)
			matrix_cases += 1
			for card in targets:
				if card == null:
					_fail("resolver returned null: %s/%s" % [target_id, side_id])
				if target_id == SkillEngine.TARGET_PLAYER:
					var expected_field: BattleField = game.player2_field if side_id == SkillEngine.TARGET_SIDE_ENEMY else game.player_field
					if card != expected_field:
						_fail("player target resolved the wrong side: %s" % side_id)
					continue
				if side_id == SkillEngine.TARGET_SIDE_ENEMY and card not in game.player2_field.slots:
					_fail("enemy filter leaked ally: %s/%s" % [target_id, card.card_name])
				if side_id == SkillEngine.TARGET_SIDE_ALLY and card not in game.player_field.slots:
					_fail("ally filter leaked enemy: %s/%s" % [target_id, card.card_name])
				var expected_gender: String = str({SkillEngine.TARGET_MALE: "male", SkillEngine.TARGET_FEMALE: "female", SkillEngine.TARGET_NONHUMAN: "nonhuman"}.get(target_id, ""))
				if expected_gender != "" and card.gender != expected_gender:
					_fail("gender filter mismatch: %s returned %s" % [target_id, card.gender])
	var legacy_enemy := SkillEngine.normalize_effect_target({"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE})
	var legacy_ally := SkillEngine.normalize_effect_target({"target": "all_allies", "effect": SkillEngine.EFFECT_HEAL})
	if legacy_enemy.get("target") != SkillEngine.TARGET_ALL or legacy_enemy.get("target_side") != SkillEngine.TARGET_SIDE_ENEMY:
		_fail("legacy all_enemies normalization changed behavior")
	if legacy_ally.get("target") != SkillEngine.TARGET_ALL or legacy_ally.get("target_side") != SkillEngine.TARGET_SIDE_ALLY:
		_fail("legacy all_allies normalization changed behavior")
	matrix_cases += 2


func _test_condition_matrix() -> void:
	var fx := _fixture()
	var game = fx.game
	var source: CardData = fx.source
	source.hp = 5
	var target := CardData.new("condition target", 3, 20, 7, [])
	target.hp = 4
	target.apply_buff(SkillEngine.BUFF_TAUNT, 1, 1)
	game.player2_field.slots[0] = target
	game.player_hand.append(CardData.new("h", 1, 1, 0, []))
	game.player2_hand.append(CardData.new("eh", 1, 1, 0, []))
	game.shared_deck.append(CardData.new("d", 1, 1, 0, []))
	game.player_field.current_mana = 4
	game.turn_number = 3
	var context: Dictionary = game.make_skill_context(2, 0)
	var expected := {
		SkillEngine.CONDITION_SOURCE_HP_PCT: 50,
		SkillEngine.CONDITION_TARGET_HP_PCT: 20,
		SkillEngine.CONDITION_FIELD_ALLY: 1,
		SkillEngine.CONDITION_FIELD_ENEMY: 1,
		SkillEngine.CONDITION_HAND_COUNT: 1,
		SkillEngine.CONDITION_MANA_CURRENT: 4,
		SkillEngine.CONDITION_TARGET_ATK: 7,
		SkillEngine.CONDITION_TARGET_COST: 3,
		SkillEngine.CONDITION_ENEMY_HAND_COUNT: 1,
		SkillEngine.CONDITION_TURN_NUMBER: 3,
		SkillEngine.CONDITION_DECK_COUNT: 1,
	}
	for condition_id: String in expected:
		var actual := SkillEngine._condition_value(condition_id, source, target, context)
		matrix_cases += 1
		if actual != expected[condition_id]:
			_fail("condition %s expected %d, got %d" % [condition_id, expected[condition_id], actual])
	for op in SkillRegistry.CONDITION_OP_IDS:
		matrix_cases += 1
		if not SkillEngine._compare_condition(3, 3, op):
			_fail("condition operator %s rejected equality" % op)
	var has_buff := {"condition_type": SkillEngine.CONDITION_TARGET_HAS_BUFF, "condition_buff_id": SkillEngine.BUFF_TAUNT}
	if not SkillEngine._passes_effect_condition(has_buff, source, target, context):
		_fail("target_has_buff condition failed")
	matrix_cases += 1


func _test_per_target_execution() -> void:
	var fx := _fixture()
	var game = fx.game
	var source: CardData = fx.source
	var hp_values := [2, 5, 9]
	for i in range(hp_values.size()):
		var target := CardData.new("enemy%d" % i, i + 1, 10, i + 2, [])
		target.hp = hp_values[i]
		game.player2_field.slots[i] = target
	source.skills = [{"skill_name": "per target", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{
		"effect": SkillEngine.EFFECT_DAMAGE,
		"target": SkillEngine.TARGET_ALL,
		"target_side": SkillEngine.TARGET_SIDE_ENEMY,
		"value_expr": {"kind": "expr", "op": "/", "a": {"kind": "var", "var_id": SkillEngine.VAR_TARGET_HP_PCT}, "b": {"kind": "num", "value": 10}},
	}]}]
	SkillEngine.trigger_single_skill(source, 0, game.make_skill_context(2, -1))
	for i in range(hp_values.size()):
		matrix_cases += 1
		if game.player2_field.slots[i].hp != 0:
			_fail("target-relative AoE did not calculate enemy%d independently" % i)


func _test_nested_control_and_targeting() -> void:
	var directed := {"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1}
	var nested_skill := {"effects": [{"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 1, "then_effects": [{"effect": SkillEngine.EFFECT_IF, "condition": {"condition_type": SkillEngine.CONDITION_HAND_COUNT, "condition_op": SkillEngine.CONDITION_OP_GTE, "condition_value": 0}, "then_effects": [directed]}]}]}
	if not SpellRules.needs_target(nested_skill):
		_fail("nested directed effect was invisible to target selection")
	if not SpellRules.targets_enemy(nested_skill):
		_fail("nested directed effect was invisible to first-turn spell rule")
	var zero_cost := {"effects": [{"effect": SkillEngine.EFFECT_ZERO_COST, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1}]}
	if SpellRules.needs_target(zero_cost) or SpellRules.targets_enemy(zero_cost):
		_fail("hand effect incorrectly requested/banned a battlefield target")
	var repeat := {"effect": SkillEngine.EFFECT_REPEAT, "repeat_expr": {"kind": "expr", "op": "+", "a": {"kind": "num", "value": 1}, "b": {"kind": "num", "value": 2}}, "then_effects": []}
	var repeat_text := _Formatter.format_control_sentence(repeat)
	if not repeat_text.contains("1") or not repeat_text.contains("2") or repeat_text.contains("重复 2 次"):
		_fail("repeat expression preview fell back to fixed count: %s" % repeat_text)
	var nested_legacy := {"effect": SkillEngine.EFFECT_IF, "condition": {"condition_type": SkillEngine.CONDITION_HAND_COUNT, "condition_op": SkillEngine.CONDITION_OP_GTE, "condition_value": 1}, "then_effects": []}
	var ctx := {"active_hand": [CardData.new("h", 1, 1, 0, [])], "rng": RandomNumberGenerator.new()}
	if not SkillEngine._passes_effect_condition(nested_legacy, CardData.new("s", 1, 1, 0, []), null, ctx):
		_fail("nested legacy condition did not execute")
	if _Formatter.format_condition_sentence(nested_legacy) == "":
		_fail("nested legacy condition did not render")
	matrix_cases += 6


func _test_semantic_guards() -> void:
	var target_value_on_hand := [{"effect": SkillEngine.EFFECT_DRAW_CARDS, "target": SkillEngine.TARGET_SELF, "value_var": SkillEngine.VAR_TARGET_ATK}]
	if _ErrorChecker.collect_semantic_issues(target_value_on_hand, SkillEngine.TRIGGER_ON_ACTIVATE).is_empty():
		_fail("target reporter on targetless effect was accepted")
	var target_repeat := [{"effect": SkillEngine.EFFECT_REPEAT, "repeat_expr": {"kind": "var", "var_id": SkillEngine.VAR_TARGET_COST}, "then_effects": []}]
	if _ErrorChecker.collect_semantic_issues(target_repeat, SkillEngine.TRIGGER_ON_ACTIVATE).is_empty():
		_fail("target reporter in repeat count was accepted")
	var death_directed := [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1}]
	if _ErrorChecker.collect_semantic_issues(death_directed, SkillEngine.TRIGGER_ON_DEATH).is_empty():
		_fail("unresolvable death target was accepted")
	var live_target_value := [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value_var": SkillEngine.VAR_TARGET_ATK}]
	if not _ErrorChecker.collect_semantic_issues(live_target_value, SkillEngine.TRIGGER_ON_ACTIVATE).is_empty():
		_fail("valid per-target reporter was rejected")
	var mixed_sides := [
		{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1},
		{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "value": 1},
	]
	if _ErrorChecker.collect_semantic_issues(mixed_sides, SkillEngine.TRIGGER_ON_ACTIVATE).is_empty():
		_fail("one-click skill accepted conflicting directed sides")
	for card: CardData in CardDatabase.starter_library():
		for skill in card.skills:
			var issues := _ErrorChecker.collect_semantic_issues(SkillEngine.legacy_skill_effects(skill), str(skill.get("trigger", "")))
			matrix_cases += 1
			if not issues.is_empty():
				_fail("built-in card %s failed semantic validation: %s" % [card.card_name, issues])
	matrix_cases += 5


func _test_non_positive_and_event_guards() -> void:
	var fx := _fixture()
	var game = fx.game
	var source: CardData = fx.source
	var enemy := CardData.new("enemy", 1, 5, 1, [])
	game.player2_field.slots[0] = enemy
	source.skills = [{"skill_name": "negative damage", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value_expr": {"kind": "expr", "op": "-", "a": {"kind": "num", "value": 1}, "b": {"kind": "num", "value": 9}}}]}]
	SkillEngine.trigger_single_skill(source, 0, game.make_skill_context(2, 0))
	if enemy.hp != 5:
		_fail("negative damage healed or damaged the target")
	SkillEngine._apply_effect(SkillEngine.EFFECT_GAIN_MAX_HP, enemy, -99, {}, {"source_card": source})
	if enemy.max_hp != 1 or enemy.base_max_hp != 5 or enemy.hp != 1:
		_fail("negative max HP crossed the one-HP floor")
	var healer := CardData.new("full", 1, 5, 1, [{"skill_name": "heal reaction", "trigger": SkillEngine.TRIGGER_ON_HEALED, "effects": [{"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 2}]}])
	SkillEngine._apply_effect(SkillEngine.EFFECT_HEAL, healer, 3, {}, {"source_card": source, "player_field": game.player_field, "enemy_field": game.player2_field})
	if healer.field_atk_bonus != 2:
		_fail("positive heal action did not preserve the established on_healed trigger contract")
	healer.hp = 3
	SkillEngine._apply_effect(SkillEngine.EFFECT_HEAL, healer, 3, {}, {"source_card": source, "player_field": game.player_field, "enemy_field": game.player2_field})
	if healer.field_atk_bonus != 4:
		_fail("positive actual healing did not fire on_healed once")
	matrix_cases += 4


func _test_zero_cost_random_contract() -> void:
	var hand: Array = []
	for i in range(4):
		hand.append(CardData.new("h%d" % i, 2, 2, 1, []))
	var eff := {"effect": SkillEngine.EFFECT_ZERO_COST, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 99, "random_count": 2, "cost_reduction_mode": SkillRegistry.COST_REDUCTION_TURN}
	SkillEngine._apply_effect(SkillEngine.EFFECT_ZERO_COST, null, 99, eff, {"active_hand": hand, "rng": RandomNumberGenerator.new()})
	var changed := 0
	for card: CardData in hand:
		if card.turn_cost_reduction > 0 and card.cost == 0:
			changed += 1
	if changed != 2:
		_fail("random cost-reduction preview/runtime count diverged: %d" % changed)
	var text := _Formatter.format_effect_sentence(eff)
	if not text.contains("2") or not text.contains("99") or text.contains(Locale.t("skill.max_targets", [2])):
		_fail("random cost-reduction formatter must show both reduction and card count: %s" % text)
	matrix_cases += 1


func _test_turn_one_rule_scope() -> void:
	var fx := _fixture()
	var game = fx.game
	var source: CardData = fx.source
	var enemy := CardData.new("turn-one enemy", 1, 5, 1, [])
	game.player2_field.slots[0] = enemy
	game.turn_number = 1
	source.skills = [{"skill_name": "unit skill", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1}]}]
	SkillEngine.trigger_single_skill(source, 0, game.make_skill_context(2, 0))
	if enemy.hp != 5:
		_fail("turn-one enemy HP guard did not cover ordinary unit skills")
	var spell := CardData.new("spell", 1, 0, 0, source.skills.duplicate(true))
	spell.card_type = "spell"
	spell.skills[0]["trigger"] = SkillEngine.TRIGGER_ON_CAST
	if SpellRules.can_cast(spell, 10, 0, 1).get("ok", true):
		_fail("enemy-targeting spell was not blocked on turn one")
	matrix_cases += 2

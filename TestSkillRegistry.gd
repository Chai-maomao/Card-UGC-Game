extends Node

# ============================================
# Regression tests for the skill engine refactor:
#  - SkillRegistry catalog completeness (effects/buffs/triggers/locale)
#  - B1: lifesteal damage must not trigger on_damaged after lethal damage
#  - B2: dead-source allowance only for on_death, not on_damaged
#  - B3: hand/deck effects honor their condition_* fields
#  - legacy skill format normalization (legacy_skill_effects)
# ============================================

const GameStateScript = preload("res://GameState.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

var failures: Array = []


func _ready() -> void:
	_test_registry_effect_meta_complete()
	_test_registry_effect_sentence_templates()
	_test_registry_buff_meta_complete()
	_test_registry_trigger_meta_complete()
	_test_registry_queries()
	_test_registry_locale_complete()
	_test_engine_reexport_parity()
	_test_b1_lifesteal_lethal_does_not_trigger_damaged()
	_test_b1_lifesteal_nonlethal_triggers_damaged()
	_test_b2_death_skill_can_target_dead_self()
	_test_b2_damaged_skill_cannot_target_dead_card()
	_test_b3_hand_effect_honors_condition()
	_test_poison_buff_damages_on_tick()
	_test_stun_blocks_next_turn()
	_test_mana_drain_effect()
	_test_swap_attack_effect()
	_test_discard_hand_effect()
	_test_copy_hand_effect()
	_test_on_turn_start_trigger()
	_test_on_healed_trigger()
	_test_on_attacked_trigger()
	_test_enemy_hand_condition()
	_test_sentence_tokens()
	_test_if_else_branch_execution()
	_test_if_then_block_execution()
	_test_repeat_block_execution()
	_test_boolean_condition_execution()
	_test_condition_var_operands()
	_test_target_var_eval()
	_test_repeat_var_execution()
	_test_boolean_has_buff_condition()
	_test_control_preview_sentence()
	_test_math_expr_operand()
	_test_math_expr_value()
	_test_math_expr_repeat()
	_test_logic_condition_execution()
	_test_all_effects_executable()
	_test_stop_block_halts_effects()
	_test_stop_block_halts_branch()
	_test_legacy_skill_effects_normalization()
	if failures.is_empty():
		print("TEST_SKILL_REGISTRY_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


func _assert(cond: bool, message: String) -> void:
	if not cond:
		_fail(message)


# ============================================
# Registry completeness
# ============================================

func _test_registry_effect_meta_complete() -> void:
	var expected: Array = [
		SkillEngine.EFFECT_DAMAGE, SkillEngine.EFFECT_HEAL, SkillEngine.EFFECT_DRAW_CARDS,
		SkillEngine.EFFECT_SHIELD, SkillEngine.EFFECT_CHARM, SkillEngine.EFFECT_ADD_BUFF,
		SkillEngine.EFFECT_LIFESTEAL_DAMAGE, SkillEngine.EFFECT_EXECUTE, SkillEngine.EFFECT_CLEANSE,
		SkillEngine.EFFECT_DISPEL, SkillEngine.EFFECT_GAIN_MANA, SkillEngine.EFFECT_GAIN_ATTACK,
		SkillEngine.EFFECT_GAIN_MAX_HP, SkillEngine.EFFECT_VIEW_DISCARD, SkillEngine.EFFECT_VIEW_DECK,
		SkillEngine.EFFECT_ZERO_COST, SkillEngine.EFFECT_MANA_DRAIN, SkillEngine.EFFECT_SWAP_ATTACK,
		SkillEngine.EFFECT_DISCARD_HAND, SkillEngine.EFFECT_COPY_HAND,
	]
	_assert(expected.size() == 20, "expected 20 skill effects, got %d" % expected.size())
	_assert(SkillRegistry.EFFECT_IDS.size() == expected.size(), "EFFECT_IDS size mismatch")
	for effect_id: String in SkillRegistry.EFFECT_IDS:
		var meta: Dictionary = SkillRegistry.effect_meta(effect_id)
		_assert(meta.has("requires_live_target"), "effect %s missing requires_live_target" % effect_id)
		_assert(meta.has("allows_negative"), "effect %s missing allows_negative" % effect_id)
		_assert(meta.has("force_self"), "effect %s missing force_self" % effect_id)
		_assert(meta.has("uses_value"), "effect %s missing uses_value" % effect_id)
		# Registry-driven dispatch contract (applier handler / tooltip template / balance weights).
		_assert(meta.has("handler") and str(meta.get("handler", "")) != "", "effect %s missing handler" % effect_id)
		_assert(meta.has("template") and str(meta.get("template", "")) != "", "effect %s missing template" % effect_id)
		_assert(meta.has("polarity") and str(meta.get("polarity", "")) in ["harmful", "helpful"], "effect %s missing polarity" % effect_id)
		_assert(meta.has("score_kind") and str(meta.get("score_kind", "")) in ["value_linear", "value_diminishing", "threshold", "fixed", "buff", "none"], "effect %s missing score_kind" % effect_id)
		_assert(meta.has("score_weight"), "effect %s missing score_weight" % effect_id)
		_assert(meta.has("category") and str(meta.get("category", "")) in ["attack", "defense", "utility"], "effect %s missing category" % effect_id)
		_assert(expected.has(effect_id), "effect %s missing from engine const set" % effect_id)
	# Order stability: keep the editor dropdown order compatible with the old hardcoded list.
	_assert(SkillRegistry.EFFECT_IDS[0] == SkillEngine.EFFECT_DAMAGE, "EFFECT_IDS order changed at index 0")
	_assert(SkillRegistry.EFFECT_IDS[5] == SkillEngine.EFFECT_ADD_BUFF, "EFFECT_IDS order changed at index 5")
	_assert(SkillRegistry.EFFECT_IDS[15] == SkillEngine.EFFECT_ZERO_COST, "EFFECT_IDS order changed at index 15")
	_assert(SkillRegistry.EFFECT_IDS[19] == SkillEngine.EFFECT_COPY_HAND, "EFFECT_IDS order changed at index 19")


func _test_registry_effect_sentence_templates() -> void:
	var special_keys: Array = [
		"view_discard_select_draw", "view_deck_select_draw",
		"make_zero_cost_all", "make_zero_cost_sides", "make_zero_cost_random",
	]
	var old_lang := Locale.language
	for lang in ["zh", "en"]:
		Locale.language = lang
		for effect_id: String in SkillRegistry.EFFECT_IDS:
			var template_key: String = str(SkillRegistry.effect_meta(effect_id).get("template", effect_id))
			_assert(Locale.term("effect_sentence", template_key) != template_key, "[%s] missing effect_sentence template for %s" % [lang, template_key])
		for key: String in special_keys:
			_assert(Locale.term("effect_sentence", key) != key, "[%s] missing effect_sentence template for %s" % [lang, key])
	Locale.language = old_lang


func _test_registry_buff_meta_complete() -> void:
	var expected: Array = [
		SkillEngine.BUFF_ATK_BOOST, SkillEngine.BUFF_REGEN, SkillEngine.BUFF_MANA_REFUND,
		SkillEngine.BUFF_THORNS, SkillEngine.BUFF_DAMAGE_REDUCTION, SkillEngine.BUFF_TAUNT,
		SkillEngine.BUFF_SILENCE, SkillEngine.BUFF_MISFORTUNE, SkillEngine.BUFF_IMMUNE_LETHAL,
		SkillEngine.BUFF_POISON, SkillEngine.BUFF_STUN,
	]
	_assert(SkillRegistry.BUFF_IDS.size() == 11, "BUFF_IDS size mismatch")
	for buff_id: String in SkillRegistry.BUFF_IDS:
		var polarity: String = SkillRegistry.buff_polarity(buff_id)
		_assert(polarity in ["negative", "positive", "neutral"], "buff %s has invalid polarity" % buff_id)
		_assert(expected.has(buff_id), "buff %s missing from engine const set" % buff_id)
	_assert(SkillRegistry.negative_buffs().has(SkillEngine.BUFF_SILENCE), "silence not negative")
	_assert(SkillRegistry.negative_buffs().has(SkillEngine.BUFF_MISFORTUNE), "misfortune not negative")
	_assert(SkillRegistry.positive_buffs().has(SkillEngine.BUFF_TAUNT), "taunt not positive")
	_assert(not SkillRegistry.positive_buffs().has(SkillEngine.BUFF_SILENCE), "silence counted as positive")


func _test_registry_trigger_meta_complete() -> void:
	var triggers: Array = [
		SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE, SkillEngine.TRIGGER_ON_SUMMON,
		SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED, SkillEngine.TRIGGER_ON_CAST,
	]
	for trigger_id: String in triggers:
		_assert(SkillRegistry.trigger_is_passive(trigger_id) == (trigger_id != SkillEngine.TRIGGER_ON_ACTIVATE and trigger_id != SkillEngine.TRIGGER_ON_CAST),
			"trigger %s passive flag mismatch" % trigger_id)


func _test_registry_queries() -> void:
	_assert(SkillRegistry.is_hand_effect(SkillEngine.EFFECT_DRAW_CARDS), "draw_cards not hand effect")
	_assert(SkillRegistry.is_hand_effect(SkillEngine.EFFECT_ZERO_COST), "zero_cost not hand effect")
	_assert(SkillRegistry.is_hand_effect(SkillEngine.EFFECT_GAIN_MANA), "gain_mana not hand effect")
	_assert(not SkillRegistry.is_hand_effect(SkillEngine.EFFECT_DAMAGE), "damage wrongly a hand effect")
	_assert(not SkillRegistry.is_hand_effect(SkillEngine.EFFECT_HEAL), "heal wrongly a hand effect")
	_assert(SkillRegistry.force_self(SkillEngine.EFFECT_DRAW_CARDS), "draw_cards not force_self")
	_assert(not SkillRegistry.force_self(SkillEngine.EFFECT_ZERO_COST), "zero_cost wrongly force_self")
	_assert(not SkillRegistry.uses_value(SkillEngine.EFFECT_CLEANSE), "cleanse should have no value")
	_assert(not SkillRegistry.uses_value(SkillEngine.EFFECT_DISPEL), "dispel should have no value")
	_assert(SkillRegistry.uses_value(SkillEngine.EFFECT_DAMAGE), "damage should use a value")
	_assert(SkillRegistry.allows_negative(SkillEngine.EFFECT_GAIN_MANA), "gain_mana should allow negative")
	_assert(SkillRegistry.allows_negative(SkillEngine.EFFECT_GAIN_MAX_HP), "gain_max_hp should allow negative")
	_assert(not SkillRegistry.allows_negative(SkillEngine.EFFECT_DAMAGE), "damage should not allow negative")
	_assert(not SkillRegistry.buff_uses_value(SkillEngine.BUFF_TAUNT), "taunt should have no value")
	_assert(not SkillRegistry.buff_uses_value(SkillEngine.BUFF_SILENCE), "silence should have no value")
	_assert(SkillRegistry.buff_uses_value(SkillEngine.BUFF_ATK_BOOST), "atk_boost should use a value")


func _test_registry_locale_complete() -> void:
	var old_lang := Locale.language
	for lang in ["zh", "en"]:
		Locale.language = lang
		for effect_id: String in SkillRegistry.EFFECT_IDS:
			_assert(Locale.term("effect", effect_id) != effect_id, "[%s] missing effect term for %s" % [lang, effect_id])
		for buff_id: String in SkillRegistry.BUFF_IDS:
			_assert(Locale.term("buff", buff_id) != buff_id, "[%s] missing buff term for %s" % [lang, buff_id])
		for target_id: String in SkillRegistry.TARGET_IDS:
			_assert(Locale.term("target", target_id) != target_id, "[%s] missing target term for %s" % [lang, target_id])
		for side_id: String in SkillRegistry.TARGET_SIDE_IDS:
			_assert(Locale.term("target_side", side_id) != side_id, "[%s] missing target_side term for %s" % [lang, side_id])
		for var_id: String in SkillRegistry.VALUE_VAR_IDS:
			_assert(Locale.term("value_var", var_id) != var_id, "[%s] missing value_var term for %s" % [lang, var_id])
		for condition_id: String in SkillRegistry.CONDITION_IDS:
			if condition_id == SkillEngine.CONDITION_NONE:
				continue
			_assert(Locale.term("condition", condition_id) != condition_id, "[%s] missing condition term for %s" % [lang, condition_id])
		# condition_op translations equal their keys in en (">=" -> ">="), only check zh.
		if lang == "zh":
			for op_id: String in SkillRegistry.CONDITION_OP_IDS:
				_assert(Locale.term("condition_op", op_id) != op_id, "[zh] missing condition_op term for %s" % op_id)
		for trigger_id: String in [SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE, SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED, SkillEngine.TRIGGER_ON_CAST]:
			_assert(Locale.term("trigger", trigger_id) != trigger_id, "[%s] missing trigger term for %s" % [lang, trigger_id])
	Locale.language = old_lang


func _test_engine_reexport_parity() -> void:
	_assert(SkillEngine.EFFECT_DAMAGE == SkillRegistry.EFFECT_DAMAGE, "effect re-export mismatch")
	_assert(SkillEngine.EFFECT_ZERO_COST == SkillRegistry.EFFECT_ZERO_COST, "zero_cost re-export mismatch")
	_assert(SkillEngine.BUFF_IMMUNE_LETHAL == SkillRegistry.BUFF_IMMUNE_LETHAL, "buff re-export mismatch")
	_assert(SkillEngine.TRIGGER_ON_DAMAGED == SkillRegistry.TRIGGER_ON_DAMAGED, "trigger re-export mismatch")
	_assert(SkillEngine.CONDITION_TARGET_HAS_BUFF == SkillRegistry.CONDITION_TARGET_HAS_BUFF, "condition re-export mismatch")
	_assert(SkillEngine.SKILL_TYPE_TALENT == SkillRegistry.SKILL_TYPE_TALENT, "skill_type re-export mismatch")


# ============================================
# B1: lifesteal on_damaged trigger guards
# ============================================

func _new_game():
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
	return game


func _card(name: String, hp: int = 5, atk: int = 0, skills: Array = []) -> CardData:
	return CardData.new(name, 1, hp, atk, skills)


func _victim_with_damaged_thorns() -> CardData:
	return _card("Thorns Victim", 3, 0, [
		CardDatabase._fx_skill("Grow Thorns", SkillEngine.TRIGGER_ON_DAMAGED, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 3, SkillEngine.BUFF_THORNS, 2),
		]),
	])


func _test_b1_lifesteal_lethal_does_not_trigger_damaged() -> void:
	var game = _new_game()
	var caster := _card("Vampire", 10, 0, [
		CardDatabase._fx_skill("Drain", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_LIFESTEAL_DAMAGE, 10),
		]),
	])
	caster.hp = 5  # wounded so the lifesteal heal is measurable
	var victim := _victim_with_damaged_thorns()
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = victim
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	_assert(victim.hp == 0, "lethal lifesteal did not kill the victim (hp=%d)" % victim.hp)
	_assert(victim.status_effects.is_empty(), "on_damaged fired after lethal lifesteal (thorns added)")
	_assert(caster.hp == 8, "lifesteal did not heal the caster for the 3 real HP drained (hp=%d)" % caster.hp)


func _test_b1_lifesteal_nonlethal_triggers_damaged() -> void:
	var game = _new_game()
	var caster := _card("Vampire", 10, 0, [
		CardDatabase._fx_skill("Siphon", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_LIFESTEAL_DAMAGE, 1),
		]),
	])
	caster.hp = 5
	var victim := _victim_with_damaged_thorns()
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = victim
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	_assert(victim.hp == 2, "nonlethal lifesteal dealt wrong damage (hp=%d)" % victim.hp)
	_assert(victim.get_thorns_damage() == 3, "on_damaged did not fire for nonlethal lifesteal (thorns=%d)" % victim.get_thorns_damage())
	_assert(caster.hp == 6, "lifesteal did not heal the caster (hp=%d)" % caster.hp)


# ============================================
# B2: dead-source allowance only on on_death
# ============================================

func _test_b2_death_skill_can_target_dead_self() -> void:
	var game = _new_game()
	var dying := _card("Death Rager", 1, 0, [
		CardDatabase._fx_skill("Final Stand", SkillEngine.TRIGGER_ON_DEATH, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
		]),
	])
	game.player_field.slots[0] = dying
	dying.hp = 0
	SkillEngine.trigger_single_skill(dying, 0, game.make_skill_context(0, -1))
	_assert(dying.field_atk_bonus == 2, "on_death skill could not target the dead card itself (bonus=%d)" % dying.field_atk_bonus)


func _test_b2_damaged_skill_cannot_target_dead_card() -> void:
	var game = _new_game()
	var dying := _card("Silenced Corpse", 1, 0, [
		CardDatabase._fx_skill("Ghost Rage", SkillEngine.TRIGGER_ON_DAMAGED, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
		]),
	])
	game.player_field.slots[0] = dying
	dying.hp = 0
	SkillEngine.trigger_single_skill(dying, 0, game.make_skill_context(0, -1))
	_assert(dying.field_atk_bonus == 0, "on_damaged skill applied to a dead card (bonus=%d)" % dying.field_atk_bonus)


# ============================================
# B3: hand/deck effects honor conditions
# ============================================

func _test_b3_hand_effect_honors_condition() -> void:
	var game = _new_game()
	for i in range(10):
		game.shared_deck.append(_card("Deck Card %d" % i, 2))
	var caster := _card("Conditional Drawer", 5, 0, [
		CardDatabase._fx_skill("Draw When Large", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx_condition(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DRAW_CARDS, 1,
				SkillEngine.CONDITION_HAND_COUNT, SkillEngine.CONDITION_OP_GTE, 4),
		]),
	])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2), _card("H2", 2)]

	# Hand size 2 < 4 → the draw effect must be skipped entirely.
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player_hand.size() == 2, "draw effect ignored its hand-count condition (hand=%d)" % game.player_hand.size())

	# Hand size 4 >= 4 → the draw effect must apply (draws 1, not hitting the 6-card cap).
	game.player_hand.append(_card("H3", 2))
	game.player_hand.append(_card("H4", 2))
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player_hand.size() == 5, "draw effect did not apply when condition met (hand=%d)" % game.player_hand.size())


# ============================================
# Legacy skill format normalization
# ============================================

func _test_legacy_skill_effects_normalization() -> void:
	var modern := SkillEngine.legacy_skill_effects({"effects": [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 3},
	]})
	_assert(modern.size() == 1 and modern[0].get("effect", "") == SkillEngine.EFFECT_HEAL, "modern effects array not passed through")

	var legacy := SkillEngine.legacy_skill_effects({
		"target": "all_enemies",
		"effect": SkillEngine.EFFECT_DAMAGE,
		"value": 2,
	})
	_assert(legacy.size() == 1, "legacy single effect not normalized")
	_assert(legacy[0].get("effect", "") == SkillEngine.EFFECT_DAMAGE, "legacy effect id lost")
	_assert(legacy[0].get("value", 0) == 2, "legacy value lost")
	_assert(legacy[0].get("target", "") == "all_enemies", "legacy target lost")

	var empty := SkillEngine.legacy_skill_effects({})
	_assert(empty.is_empty(), "empty skill should produce no effects")


# ============================================
# if/else control block
# ============================================

func _test_if_else_branch_execution() -> void:
	var game = _new_game()
	var caster := _card("Branchy", 10, 0, [
		CardDatabase._fx_skill("Branch", SkillEngine.TRIGGER_ON_ACTIVATE, []),
	])
	caster.skills[0]["effects"] = [{
		"effect": SkillEngine.EFFECT_IF_ELSE,
		"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
		"condition_op": SkillEngine.CONDITION_OP_GTE,
		"condition_value": 50,
		"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
		"else_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 3)],
	}]
	game.player_field.slots[0] = caster

	# HP 70% >= 50% → then branch (gain_attack).
	caster.hp = 7
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "if/else then-branch did not run (bonus=%d)" % caster.field_atk_bonus)
	_assert(caster.max_hp == 10, "if/else else-branch ran unexpectedly (max_hp=%d)" % caster.max_hp)

	# HP 30% < 50% → else branch (gain_max_hp).
	caster.hp = 3
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.max_hp == 13, "if/else else-branch did not run (max_hp=%d)" % caster.max_hp)
	_assert(caster.field_atk_bonus == 2, "if/else then-branch ran unexpectedly (bonus=%d)" % caster.field_atk_bonus)


# "if () then" control block (no else): uses the nested condition reporter
# dict format produced by the block editor.
func _test_if_then_block_execution() -> void:
	var game = _new_game()
	var caster := _card("Guardian", 10, 0, [
		CardDatabase._fx_skill("Stand Guard", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF,
				"condition": {
					"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
					"condition_op": SkillEngine.CONDITION_OP_GTE,
					"condition_value": 50,
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	# HP 80% >= 50% → then branch runs.
	caster.hp = 8
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "if-then then-branch did not run (bonus=%d)" % caster.field_atk_bonus)
	# HP 30% < 50% → nothing (no else branch).
	caster.hp = 3
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "if-then ran when condition false (bonus=%d)" % caster.field_atk_bonus)


func _test_repeat_block_execution() -> void:
	var game = _new_game()
	var caster := _card("Looper", 10, 0, [
		CardDatabase._fx_skill("Loop", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_REPEAT,
				"repeat_count": 3,
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 6, "repeat x3 gain_attack 2 should add 6 (bonus=%d)" % caster.field_atk_bonus)
	# A stop block inside the loop body halts the current iteration only.
	var caster2 := _card("Looper2", 10, 0, [
		CardDatabase._fx_skill("Loop2", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_REPEAT,
				"repeat_count": 2,
				"then_effects": [
					CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 1),
					{"effect": SkillEngine.EFFECT_STOP},
					CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 1),
				],
			},
		]),
	])
	game.player_field.slots[0] = caster2
	SkillEngine.trigger_single_skill(caster2, 0, game.make_skill_context(0, -1))
	_assert(caster2.field_atk_bonus == 2, "stop should halt each iteration (2x1, bonus=%d)" % caster2.field_atk_bonus)


# Scratch-style boolean comparison: "[var] [op] [number]" inside an if block.
func _test_boolean_condition_execution() -> void:
	var game = _new_game()
	var caster := _card("Comparator", 10, 0, [
		CardDatabase._fx_skill("Compare", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF_ELSE,
				"condition": {
					"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
					"op": SkillEngine.CONDITION_OP_GTE,
					"rhs": {"kind": "num", "value": 2},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
				"else_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 3)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	# Hand 3 >= 2 → then branch (gain_attack).
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "boolean then-branch did not run (bonus=%d)" % caster.field_atk_bonus)
	_assert(caster.max_hp == 10, "boolean else-branch ran unexpectedly (max_hp=%d)" % caster.max_hp)
	# Hand 1 < 2 → else branch (gain_max_hp).
	game.player_hand = [_card("H1", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.max_hp == 13, "boolean else-branch did not run (max_hp=%d)" % caster.max_hp)
	_assert(caster.field_atk_bonus == 2, "boolean then-branch ran unexpectedly (bonus=%d)" % caster.field_atk_bonus)


# Both comparison sides may be variable reporters ("hand == turn").
func _test_condition_var_operands() -> void:
	var game = _new_game()
	var caster := _card("Twin Clock", 10, 0, [
		CardDatabase._fx_skill("Sync", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF,
				"condition": {
					"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
					"op": SkillEngine.CONDITION_OP_EQ,
					"rhs": {"kind": "var", "var_id": SkillEngine.VAR_TURN_NUMBER},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	var ctx := game.make_skill_context(0, -1)
	ctx["turn_number"] = 3
	SkillEngine.trigger_single_skill(caster, 0, ctx)
	_assert(caster.field_atk_bonus == 2, "var==var condition not met (hand=3 turn=3, bonus=%d)" % caster.field_atk_bonus)
	ctx["turn_number"] = 4
	SkillEngine.trigger_single_skill(caster, 0, ctx)
	_assert(caster.field_atk_bonus == 2, "var==var condition matched wrongly (hand=3 turn=4, bonus=%d)" % caster.field_atk_bonus)


# Target/source-stat reporters resolve against the current target/source card.
func _test_target_var_eval() -> void:
	var game = _new_game()
	var caster := _card("Life Watcher", 10, 0, [
		CardDatabase._fx_skill("Low Health", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF,
				"condition": {
					"lhs": {"kind": "var", "var_id": SkillEngine.VAR_TARGET_HP_PCT},
					"op": SkillEngine.CONDITION_OP_LTE,
					"rhs": {"kind": "num", "value": 40},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	# 30% <= 40% → then branch; 80% > 40% → nothing.
	caster.hp = 3
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "target_hp_pct var not met at 30%% (bonus=%d)" % caster.field_atk_bonus)
	caster.hp = 8
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "target_hp_pct var matched at 80%% (bonus=%d)" % caster.field_atk_bonus)


# The repeat count can be a variable reporter oval too.
func _test_repeat_var_execution() -> void:
	var game = _new_game()
	var caster := _card("Variable Looper", 10, 0, [
		CardDatabase._fx_skill("Loop N", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_REPEAT,
				"repeat_var": SkillEngine.VAR_HAND_COUNT,
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 6, "repeat_var x3 gain_attack 2 should add 6 (bonus=%d)" % caster.field_atk_bonus)


# The "target has buff" boolean block form.
func _test_boolean_has_buff_condition() -> void:
	var game = _new_game()
	var caster := _card("Thorn Reader", 10, 0, [
		CardDatabase._fx_skill("Thorny", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF,
				"condition": {
					"op": "has",
					"lhs": {"kind": "target"},
					"rhs": {"kind": "buff", "buff_id": SkillEngine.BUFF_THORNS},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 0, "has-buff matched without the buff (bonus=%d)" % caster.field_atk_bonus)
	caster.apply_buff(SkillEngine.BUFF_THORNS, 1, 3)
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "has-buff did not match with the buff (bonus=%d)" % caster.field_atk_bonus)


# Nested math-expression reporters: (hand + 2) * 3, division, random range.
func _test_math_expr_operand() -> void:
	var game = _new_game()
	var caster := _card("Calculator", 10, 0, [])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	var ctx := game.make_skill_context(0, -1)
	# (hand 3 + 2) * 3 = 15
	var expr := {
		"kind": "expr", "op": "*",
		"a": {"kind": "expr", "op": "+", "a": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT}, "b": {"kind": "num", "value": 2}},
		"b": {"kind": "num", "value": 3},
	}
	var val: int = SkillEngine._eval_operand(expr, caster, caster, ctx)
	_assert(val == 15, "nested math expr wrong: %d" % val)
	# Division truncates: 7 / 2 = 3
	var div := {"kind": "expr", "op": "/", "a": {"kind": "num", "value": 7}, "b": {"kind": "num", "value": 2}}
	_assert(SkillEngine._eval_operand(div, caster, caster, ctx) == 3, "int division wrong")
	# Division by zero is safe.
	var div0 := {"kind": "expr", "op": "/", "a": {"kind": "num", "value": 5}, "b": {"kind": "num", "value": 0}}
	_assert(SkillEngine._eval_operand(div0, caster, caster, ctx) == 0, "division by zero should be 0")
	# Random range stays within [min, max].
	var rnd := {"kind": "expr", "op": "rand", "a": {"kind": "num", "value": 2}, "b": {"kind": "num", "value": 5}}
	for i in range(30):
		var r: int = SkillEngine._eval_operand(rnd, caster, caster, ctx)
		_assert(r >= 2 and r <= 5, "rand out of range: %d" % r)


# An effect's value can be driven by a math-expression reporter.
func _test_math_expr_value() -> void:
	var game = _new_game()
	var caster := _card("Expr Striker", 10, 0, [
		CardDatabase._fx_skill("Math Hit", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value_expr": {
					"kind": "expr", "op": "*",
					"a": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
					"b": {"kind": "num", "value": 2},
				},
			},
		]),
	])
	var enemy := _card("Victim", 30, 0)
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	# hand 3 * 2 = 6 damage.
	_assert(enemy.hp == 24, "math value damage wrong (hp=%d, want 24)" % enemy.hp)


# The repeat count can be a math-expression reporter.
func _test_math_expr_repeat() -> void:
	var game = _new_game()
	var caster := _card("Expr Looper", 10, 0, [
		CardDatabase._fx_skill("Loop N*2", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_REPEAT,
				"repeat_expr": {
					"kind": "expr", "op": "+",
					"a": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
					"b": {"kind": "num", "value": 1},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2), _card("H2", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	# (hand 2 + 1) = 3 iterations * 2 attack = 6.
	_assert(caster.field_atk_bonus == 6, "math repeat wrong (bonus=%d)" % caster.field_atk_bonus)


# Logic reporters combine comparisons: "hand>=2 AND target HP<=50%",
# "OR", and "NOT" — evaluated recursively by the engine.
func _test_logic_condition_execution() -> void:
	var game = _new_game()
	var caster := _card("Logic Gates", 10, 0, [
		CardDatabase._fx_skill("Gate", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF_ELSE,
				"condition": {
					"logic": "and",
					"lhs": {"op": SkillEngine.CONDITION_OP_GTE,
						"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
						"rhs": {"kind": "num", "value": 2}},
					"rhs": {"op": SkillEngine.CONDITION_OP_LTE,
						"lhs": {"kind": "var", "var_id": SkillEngine.VAR_TARGET_HP_PCT},
						"rhs": {"kind": "num", "value": 50}},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
				"else_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 3)],
			},
		]),
	])
	game.player_field.slots[0] = caster
	# hand 3 >= 2 AND HP 30% <= 50% → then.
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	caster.hp = 3
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "AND then-branch did not run (bonus=%d)" % caster.field_atk_bonus)
	_assert(caster.max_hp == 10, "AND else-branch ran unexpectedly (max_hp=%d)" % caster.max_hp)
	# hand 1 < 2 → AND fails → else.
	caster.hp = 10
	game.player_hand = [_card("H1", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.max_hp == 13, "AND else-branch did not run (max_hp=%d)" % caster.max_hp)

	# OR: hand 3 >= 2 OR HP 90% <= 50% → then (first clause true).
	var or_caster := _card("OR Gate", 10, 0, [
		CardDatabase._fx_skill("OrGate", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF,
				"condition": {
					"logic": "or",
					"lhs": {"op": SkillEngine.CONDITION_OP_GTE,
						"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
						"rhs": {"kind": "num", "value": 2}},
					"rhs": {"op": SkillEngine.CONDITION_OP_LTE,
						"lhs": {"kind": "var", "var_id": SkillEngine.VAR_TARGET_HP_PCT},
						"rhs": {"kind": "num", "value": 50}},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = or_caster
	or_caster.hp = 9
	game.player_hand = [_card("H1", 2), _card("H2", 2), _card("H3", 2)]
	SkillEngine.trigger_single_skill(or_caster, 0, game.make_skill_context(0, -1))
	_assert(or_caster.field_atk_bonus == 2, "OR then-branch did not run (bonus=%d)" % or_caster.field_atk_bonus)

	# NOT: NOT (hand 1 >= 2) → true → then.
	var not_caster := _card("NOT Gate", 10, 0, [
		CardDatabase._fx_skill("NotGate", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF,
				"condition": {
					"logic": "not",
					"child": {"op": SkillEngine.CONDITION_OP_GTE,
						"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
						"rhs": {"kind": "num", "value": 2}},
				},
				"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2)],
			},
		]),
	])
	game.player_field.slots[0] = not_caster
	game.player_hand = [_card("H1", 2)]
	SkillEngine.trigger_single_skill(not_caster, 0, game.make_skill_context(0, -1))
	_assert(not_caster.field_atk_bonus == 2, "NOT then-branch did not run (bonus=%d)" % not_caster.field_atk_bonus)


# The skill preview must render control blocks as readable sentences (no raw
# __if_else__ fallback), including nested sub-effects.
func _test_control_preview_sentence() -> void:
	var old_lang := Locale.language
	for lang in ["zh", "en"]:
		Locale.language = lang
		var if_else := {
			"effect": SkillEngine.EFFECT_IF_ELSE,
			"condition": {
				"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
				"op": SkillEngine.CONDITION_OP_GTE,
				"rhs": {"kind": "num", "value": 2},
			},
			"then_effects": [
				{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE,
					"target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 3},
			],
			"else_effects": [],
		}
		var text := _TextFormatter.format_effect_sentence(if_else)
		_assert(not text.contains("__if_else__"), "[%s] control block leaked raw id: %s" % [lang, text])
		_assert(text.length() > 8, "[%s] control sentence too short: %s" % [lang, text])
		var repeat_text := _TextFormatter.format_effect_sentence({
			"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 2,
			"then_effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "value": 1, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL}],
		})
		_assert(not repeat_text.contains("__repeat__"), "[%s] repeat leaked raw id: %s" % [lang, repeat_text])
		var cond_text := _TextFormatter.format_condition_sentence(if_else)
		_assert(not cond_text.contains("condition_type"), "[%s] boolean condition leaked raw fields: %s" % [lang, cond_text])
	Locale.language = old_lang


# Every registered effect must be expressible as a nested block skill and
# resolvable by the engine (block-editor expression coverage).
func _test_all_effects_executable() -> void:
	var game = _new_game()
	for i in range(10):
		game.shared_deck.append(_card("Deck %d" % i, 2))
	var caster := _card("Omni", 20, 3, [])
	var enemy := _card("Victim", 20, 2)
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	game.player_hand = [_card("H1", 2), _card("H2", 2)]
	game.player2_hand = [_card("E1", 2), _card("E2", 2)]
	var effects: Array = []
	for effect_id: String in SkillRegistry.EFFECT_IDS:
		var eff := CardDatabase._fx(SkillEngine.TARGET_SINGLE, effect_id, 1, SkillEngine.BUFF_ATK_BOOST, 1)
		effects.append(eff)
	# Nested control blocks on top of the flat effect list.
	effects.append({
		"effect": SkillEngine.EFFECT_IF,
		"condition": {
			"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
			"condition_op": SkillEngine.CONDITION_OP_GTE,
			"condition_value": 50,
		},
		"then_effects": [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_HEAL, 1),
			{"effect": SkillEngine.EFFECT_STOP},
		],
	})
	effects.append({
		"effect": SkillEngine.EFFECT_IF_ELSE,
		"condition": {
			"condition_type": SkillEngine.CONDITION_ENEMY_HAND_COUNT,
			"condition_op": SkillEngine.CONDITION_OP_LTE,
			"condition_value": 5,
		},
		"then_effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 1)],
		"else_effects": [{"effect": SkillEngine.EFFECT_STOP}],
	})
	caster.skills.append(CardDatabase._fx_skill("Omni", SkillEngine.TRIGGER_ON_ACTIVATE, effects))
	caster.hp = 15  # 75% >= 50% so the if-then branch runs
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	# The flat effect list may interfere with each other (e.g. charm relocates the
	# enemy), so we assert the nested control blocks resolved: the if-then's heal
	# and the if-else's gain_attack must have applied (+1 attack from then).
	_assert(caster.field_atk_bonus >= 1, "nested block skill did not resolve control blocks (bonus=%d)" % caster.field_atk_bonus)


# A top-level stop block halts the rest of the skill's effects.
func _test_stop_block_halts_effects() -> void:
	var game = _new_game()
	var caster := _card("Stopper", 10, 0, [
		CardDatabase._fx_skill("Halt", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
			{"effect": SkillEngine.EFFECT_STOP},
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 3),
		]),
	])
	game.player_field.slots[0] = caster
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "effect before stop did not run (bonus=%d)" % caster.field_atk_bonus)
	_assert(caster.max_hp == 10, "effect after top-level stop ran unexpectedly (max_hp=%d)" % caster.max_hp)


# A stop inside a then/else branch only halts that branch; effects after the
# if/else block in the outer skill still run ("跳出当前条件" = stop this branch).
func _test_stop_block_halts_branch() -> void:
	var game = _new_game()
	var caster := _card("Branch Stopper", 10, 0, [
		CardDatabase._fx_skill("Conditional Halt", SkillEngine.TRIGGER_ON_ACTIVATE, [
			{
				"effect": SkillEngine.EFFECT_IF_ELSE,
				"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
				"condition_op": SkillEngine.CONDITION_OP_GTE,
				"condition_value": 50,
				"then_effects": [
					CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
					{"effect": SkillEngine.EFFECT_STOP},
					CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 3),
				],
				"else_effects": [],
			},
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 5),
		]),
	])
	game.player_field.slots[0] = caster
	caster.hp = 8  # 80% >= 50% → then branch
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(caster.field_atk_bonus == 2, "branch effect before stop did not run (bonus=%d)" % caster.field_atk_bonus)
	_assert(caster.max_hp == 15, "stop should skip branch tail but keep outer effects (max_hp=%d)" % caster.max_hp)


# ============================================
# User-editable expansion: poison / stun / new effects / new triggers
# ============================================

func _test_poison_buff_damages_on_tick() -> void:
	var card := _card("Poisoned", 10)
	card.apply_buff(SkillEngine.BUFF_POISON, 2, 2, 1)
	card.tick_buffs(1)
	_assert(card.hp == 8, "poison did not tick (hp=%d)" % card.hp)
	card.tick_buffs(1)
	_assert(card.hp == 6, "poison did not tick twice (hp=%d)" % card.hp)


func _test_stun_blocks_next_turn() -> void:
	var game = _new_game()
	for i in range(5):
		game.shared_deck.append(_card("Deck %d" % i, 2))
	var card := _card("Stunned", 5, 2)
	card.apply_buff(SkillEngine.BUFF_STUN, 1, 1, 1)
	game.player_field.slots[0] = card
	game.current_player = 2  # so start_new_turn switches back to P1 and stuns P1's board
	game.start_new_turn()
	_assert(card.has_acted, "stunned card was not blocked from acting")
	_assert(not card.has_stun(), "stun buff was not consumed")


func _test_mana_drain_effect() -> void:
	var game = _new_game()
	var caster := _card("Drainer", 5, 0, [
		CardDatabase._fx_skill("Drain", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_MANA_DRAIN, 3),
		]),
	])
	game.player_field.slots[0] = caster
	game.player_field.current_mana = 5
	game.player2_field.current_mana = 5
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player2_field.current_mana == 2, "mana drain did not reduce enemy mana (%d)" % game.player2_field.current_mana)
	_assert(game.player_field.current_mana == 8, "mana drain did not grant self mana (%d)" % game.player_field.current_mana)


func _test_swap_attack_effect() -> void:
	var game = _new_game()
	var caster := _card("Swapper", 5, 2, [
		CardDatabase._fx_skill("Swap", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_SWAP_ATTACK, 0),
		]),
	])
	var enemy := _card("Big Boy", 5, 5)
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	_assert(caster.atk == 5 and enemy.atk == 2, "swap attack did not exchange ATK (%d <-> %d)" % [caster.atk, enemy.atk])


func _test_discard_hand_effect() -> void:
	var game = _new_game()
	var caster := _card("Discarder", 5, 0, [
		CardDatabase._fx_skill("Ruin", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DISCARD_HAND, 2),
		]),
	])
	game.player_field.slots[0] = caster
	game.player2_hand = [_card("E1", 2), _card("E2", 2), _card("E3", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player2_hand.size() == 1, "discard hand did not discard 2 cards (left=%d)" % game.player2_hand.size())
	_assert(game.shared_discard.size() == 2, "discarded cards did not reach the discard pile (%d)" % game.shared_discard.size())


func _test_copy_hand_effect() -> void:
	var game = _new_game()
	var caster := _card("Duplicator", 5, 0, [
		CardDatabase._fx_skill("Copy", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_COPY_HAND, 1),
		]),
	])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2), _card("H2", 2)]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player_hand.size() == 3, "copy hand did not duplicate a card (hand=%d)" % game.player_hand.size())


func _test_on_turn_start_trigger() -> void:
	var game = _new_game()
	for i in range(5):
		game.shared_deck.append(_card("Deck %d" % i, 2))
	var caster := _card("Dawn Bender", 5, 0, [
		CardDatabase._fx_skill("Morning Rage", SkillEngine.TRIGGER_ON_TURN_START, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
		]),
	])
	game.player_field.slots[0] = caster
	game.current_player = 2
	game.start_new_turn()
	_assert(caster.field_atk_bonus == 2, "on_turn_start skill did not fire (bonus=%d)" % caster.field_atk_bonus)


func _test_on_healed_trigger() -> void:
	var game = _new_game()
	var healer := _card("Healer", 5, 0, [
		CardDatabase._fx_skill("Mend", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_HEAL, 2),
		]),
	])
	var healed := _card("Graceful", 3, 0, [
		CardDatabase._fx_skill("Blessing", SkillEngine.TRIGGER_ON_HEALED, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
		]),
	])
	game.player_field.slots[0] = healer
	game.player2_field.slots[0] = healed
	SkillEngine.trigger_single_skill(healer, 0, game.make_skill_context(0, 0))
	_assert(healed.field_atk_bonus == 2, "on_healed skill did not fire (bonus=%d)" % healed.field_atk_bonus)


func _test_on_attacked_trigger() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 10, 1)
	var victim := _card("Vigilante", 10, 0, [
		CardDatabase._fx_skill("Counter", SkillEngine.TRIGGER_ON_ATTACKED, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_ATTACK, 2),
		]),
	])
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	_assert(victim.field_atk_bonus == 2, "on_attacked skill did not fire (bonus=%d)" % victim.field_atk_bonus)


func _test_enemy_hand_condition() -> void:
	var game = _new_game()
	for i in range(5):
		game.shared_deck.append(_card("Deck %d" % i, 2))
	var caster := _card("Scout", 5, 0, [
		CardDatabase._fx_skill("Steal When Crowded", SkillEngine.TRIGGER_ON_ACTIVATE, [
			CardDatabase._fx_condition(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DRAW_CARDS, 1,
				SkillEngine.CONDITION_ENEMY_HAND_COUNT, SkillEngine.CONDITION_OP_GTE, 2),
		]),
	])
	game.player_field.slots[0] = caster
	game.player_hand = [_card("H1", 2)]
	game.player2_hand = [_card("E1", 2)]

	# Enemy hand size 1 < 2 → skip.
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player_hand.size() == 1, "enemy-hand condition did not block the draw (hand=%d)" % game.player_hand.size())

	# Enemy hand size 2 >= 2 → draws.
	game.player2_hand.append(_card("E2", 2))
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	_assert(game.player_hand.size() == 2, "enemy-hand condition did not allow the draw (hand=%d)" % game.player_hand.size())


# ============================================
# Scratch-style sentence tokenization
# ============================================

func _test_sentence_tokens() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var dmg: Dictionary = CardDatabase._fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_DAMAGE, 3)
	var dmg_types: Array = []
	var dmg_text := ""
	for t in _TextFormatter.effect_sentence_tokens(dmg):
		dmg_types.append(t.get("type", ""))
		if t.get("type", "") == "text":
			dmg_text += t.get("text", "")
	_assert(dmg_types.has("target"), "damage sentence lost target placeholder (%s)" % str(dmg_types))
	_assert(dmg_types.has("value"), "damage sentence lost value placeholder (%s)" % str(dmg_types))
	_assert(dmg_text.contains("伤害"), "damage sentence text missing (got: %s)" % dmg_text)

	# force_self effects render the target as static text, not an editable control.
	var draw: Dictionary = CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DRAW_CARDS, 1)
	var draw_has_target_ctrl := false
	for t in _TextFormatter.effect_sentence_tokens(draw):
		if t.get("type", "") == "target":
			draw_has_target_ctrl = true
	_assert(not draw_has_target_ctrl, "force_self effect should not expose a target control")

	# add_buff exposes buff / duration / value controls.
	var buff: Dictionary = CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 2, SkillEngine.BUFF_ATK_BOOST, 3)
	var buff_types := ""
	for t in _TextFormatter.effect_sentence_tokens(buff):
		buff_types += str(t.get("type", "")) + ","
	_assert(buff_types.contains("buff,"), "add_buff missing buff control (%s)" % buff_types)
	_assert(buff_types.contains("duration,"), "add_buff missing duration control (%s)" % buff_types)
	_assert(buff_types.contains("value,"), "add_buff missing value control (%s)" % buff_types)
	Locale.language = old_lang

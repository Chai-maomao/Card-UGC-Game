extends Node

const GameStateScript = preload("res://GameState.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

var failures: Array = []


func _ready() -> void:
	_test_target_normalization_helpers()
	_test_skill_text_formatter_helpers()
	_test_skill_tooltip_shows_skill_probability()
	_test_thorns_added_on_damaged_is_delayed()
	_test_old_all_enemy_mapping()
	_test_target_side_filter()
	_test_activate_target_single_requires_manual_target()
	_test_target_single_all_side_uses_selected_player()
	_test_target_single_ally_side_uses_ally_field()
	_test_on_attack_target_matrix()
	_test_on_damaged_target_matrix()
	_test_death_self_sides_and_filter_targets()
	_test_death_single_target_does_not_fallback()
	_test_effect_conditions()
	_test_new_effect_pack()
	if failures.is_empty():
		print("TEST_SKILL_TARGETING_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


func _test_target_normalization_helpers() -> void:
	var enemy_aoe := _TargetResolver.normalize_effect_target({"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE, "value": 1})
	if enemy_aoe.get("target", "") != SkillEngine.TARGET_ALL or enemy_aoe.get("target_side", "") != SkillEngine.TARGET_SIDE_ENEMY:
		_fail("target resolver did not normalize old all_enemies target")
	if not _TargetResolver.is_directed_target(SkillEngine.TARGET_SINGLE):
		_fail("target resolver did not identify target_single as directed")
	if _TargetResolver.default_target_side("all_allies") != SkillEngine.TARGET_SIDE_ALLY:
		_fail("target resolver returned wrong default side for all_allies")


func _test_skill_text_formatter_helpers() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var sentence := _TextFormatter.format_effect_sentence({"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE, "value_min": 1, "value_max": 3, "random_count": 2})
	if not sentence.contains("敌方") or not sentence.contains("1-3"):
		_fail("skill text formatter did not describe normalized enemy random damage")
	Locale.language = old_lang


func _test_skill_tooltip_shows_skill_probability() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var tooltip := _TextFormatter.format_skill_tooltip({"skill_name": "自我修复", "trigger": SkillEngine.TRIGGER_ON_DAMAGED, "probability": 33, "effects": [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 3}
	]})
	if not tooltip.contains("33") or not tooltip.contains("恢复 3 点生命"):
		_fail("skill tooltip did not show skill-level trigger probability")
	Locale.language = old_lang


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


func _test_thorns_added_on_damaged_is_delayed() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 10, 2)
	var victim := _card("Thorns Later", 10, 0, [
		CardDatabase._fx_skill("Grow Thorns", SkillEngine.TRIGGER_ON_DAMAGED, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 3, SkillEngine.BUFF_THORNS, 2),
		]),
	])
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	if attacker.hp != 10:
		_fail("on_damaged thorns reflected the current attack")
	if victim.get_thorns_damage() != 3:
		_fail("on_damaged thorns buff was not applied for later attacks")


func _test_old_all_enemy_mapping() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var enemy_a := _card("Enemy A")
	var enemy_b := _card("Enemy B")
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy_a
	game.player2_field.slots[1] = enemy_b
	caster.skills = [{"skill_name": "Old AoE", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if enemy_a.hp != 4 or enemy_b.hp != 4:
		_fail("old all_enemies target did not damage all enemies")
	if caster.hp != 5:
		_fail("old all_enemies target damaged the caster")


func _test_target_side_filter() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var ally_male := _card("Ally Male")
	ally_male.gender = "male"
	var enemy_male := _card("Enemy Male")
	enemy_male.gender = "male"
	var enemy_female := _card("Enemy Female")
	enemy_female.gender = "female"
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally_male
	game.player2_field.slots[0] = enemy_male
	game.player2_field.slots[1] = enemy_female
	caster.skills = [{"skill_name": "Enemy Male Only", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_MALE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if enemy_male.hp != 4:
		_fail("enemy male target_side filter missed enemy male")
	if ally_male.hp != 5 or enemy_female.hp != 5:
		_fail("enemy male target_side filter hit a wrong target")


func _test_activate_target_single_requires_manual_target() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var enemy := _card("Enemy")
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	caster.skills = [{"skill_name": "Manual Bolt", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if enemy.hp != 5:
		_fail("manual target_single fell back without a selected target")
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if enemy.hp != 3:
		_fail("manual target_single did not hit the selected target")


func _test_target_single_all_side_uses_selected_player() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var ally := _card("Ally")
	ally.hp = 2
	var enemy := _card("Enemy")
	enemy.hp = 2
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally
	game.player2_field.slots[1] = enemy
	caster.skills = [{"skill_name": "Open Heal", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALL, "effect": SkillEngine.EFFECT_HEAL, "value": 3}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1, 1))
	if ally.hp != 2:
		_fail("target_single all-side should not resolve selected allied slot")
	if enemy.hp != 5:
		_fail("target_single all-side should fall back to enemy field for directed targets")


func _test_target_single_ally_side_uses_ally_field() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var ally := _card("Ally")
	ally.hp = 2
	var enemy := _card("Enemy")
	enemy.hp = 2
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally
	game.player2_field.slots[1] = enemy
	caster.skills = [{"skill_name": "Ally Heal", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 3}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1, 1))
	if ally.hp != 5:
		_fail("target_single ally-side did not resolve selected allied slot")
	if enemy.hp != 2:
		_fail("target_single ally-side resolved selected allied slot on enemy field")


func _test_on_attack_target_matrix() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 8, 0, [
		{"skill_name": "Attack Matrix", "trigger": SkillEngine.TRIGGER_ON_ATTACK, "effects": [
			{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
			{"target": SkillEngine.TARGET_SELF_SIDES, "effect": SkillEngine.EFFECT_HEAL, "value": 1},
		]}
	])
	var ally := _card("Ally", 5)
	ally.hp = 3
	var defender := _card("Defender", 5)
	var defender_side := _card("Defender Side", 5)
	game.player_field.slots[1] = ally
	game.player_field.slots[2] = attacker
	game.player2_field.slots[3] = defender
	game.player2_field.slots[4] = defender_side
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ATTACK, attacker, game.make_skill_context(2, 3))
	if defender.hp != 4:
		_fail("on_attack target_single did not resolve to defender")
	if defender_side.hp != 5:
		_fail("on_attack target_single incorrectly hit adjacent defender")
	if attacker.hp != 8 or ally.hp != 4:
		_fail("on_attack self_sides did not resolve around attacker and adjacent ally")


func _test_on_damaged_target_matrix() -> void:
	var game = _new_game()
	var attacker := _card("Damage Source", 5)
	var attacker_side := _card("Source Side", 5)
	var victim := _card("Victim", 5, 0, [
		{"skill_name": "Damaged Matrix", "trigger": SkillEngine.TRIGGER_ON_DAMAGED, "effects": [
			{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
			{"target": SkillEngine.TARGET_SELF_SIDES, "effect": SkillEngine.EFFECT_HEAL, "value": 1},
		]}
	])
	var victim_side := _card("Victim Side", 5)
	victim_side.hp = 3
	game.player_field.slots[1] = attacker
	game.player_field.slots[2] = attacker_side
	game.player2_field.slots[1] = victim
	game.player2_field.slots[0] = victim_side
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, victim, game.make_skill_context_for_player(2, 1, 1))
	if attacker.hp != 4:
		_fail("on_damaged target_single did not resolve to damage source")
	if attacker_side.hp != 5:
		_fail("on_damaged target_single incorrectly hit source adjacent")
	if victim.hp != 5 or victim_side.hp != 4:
		_fail("on_damaged self_sides did not resolve around damaged card")


func _test_death_self_sides_and_filter_targets() -> void:
	var game = _new_game()
	var dying := _card("Dying", 0, 0, [
		{"skill_name": "Death Matrix", "trigger": SkillEngine.TRIGGER_ON_DEATH, "effects": [
			{"target": SkillEngine.TARGET_SELF_SIDES, "effect": SkillEngine.EFFECT_HEAL, "value": 2},
			{"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
		]}
	])
	var ally := _card("Death Ally", 5)
	ally.hp = 2
	var enemy := _card("Death Enemy", 5)
	game.player_field.slots[1] = ally
	game.player_field.slots[2] = dying
	game.player2_field.slots[0] = enemy
	game.cleanup_deaths()
	if ally.hp != 4:
		_fail("on_death self_sides did not affect adjacent ally before removal")
	if enemy.hp != 4:
		_fail("on_death all+enemy did not affect enemy field")
	if game.player_field.slots[2] != null:
		_fail("dead source was not removed after on_death trigger")


func _test_death_single_target_does_not_fallback() -> void:
	var game = _new_game()
	var dying := _card("Dying", 0, 0, [
		{"skill_name": "No Free Target", "trigger": SkillEngine.TRIGGER_ON_DEATH, "effects": [
			{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}
		]}
	])
	var enemy := _card("Enemy")
	game.player_field.slots[0] = dying
	game.player2_field.slots[0] = enemy
	game.cleanup_deaths()
	if enemy.hp != 5:
		_fail("on_death target_single fell back to the first enemy")


func _test_effect_conditions() -> void:
	var game = _new_game()
	var caster := _card("Conditional Caster", 10, 0)
	caster.hp = 4
	var enemy := _card("Conditional Enemy", 10, 0)
	var ally := _card("Conditional Ally", 5, 0)
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally
	game.player2_field.slots[0] = enemy

	caster.skills = [{"skill_name": "Low HP Shield", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_SHIELD, "value": 2,
			"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT, "condition_op": SkillEngine.CONDITION_OP_LTE, "condition_value": 50},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2,
			"condition_type": SkillEngine.CONDITION_TARGET_HP_PCT, "condition_op": SkillEngine.CONDITION_OP_LTE, "condition_value": 30},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1,
			"condition_type": SkillEngine.CONDITION_FIELD_ALLY, "condition_op": SkillEngine.CONDITION_OP_GTE, "condition_value": 2},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1,
			"condition_type": SkillEngine.CONDITION_TARGET_HAS_BUFF, "condition_buff_id": SkillEngine.BUFF_MISFORTUNE},
	]}]

	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if caster.temp_hp != 2:
		_fail("source HP condition did not apply shield when caster was low")
	if enemy.hp != 9:
		_fail("target HP/buff conditions should fail while ally-count condition deals 1 damage")

	enemy.hp = 3
	enemy.apply_buff(SkillEngine.BUFF_MISFORTUNE, 10, 1)
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if enemy.hp != 0:
		_fail("target HP, ally count, and target buff conditions did not all apply")


func _test_new_effect_pack() -> void:
	var game = _new_game()
	var caster := _card("New Effect Caster", 10, 1)
	caster.hp = 4
	var enemy := _card("New Effect Enemy", 10, 0)
	enemy.temp_hp = 2
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	game.player_field.current_mana = 8

	caster.skills = [{"skill_name": "New Effects", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_LIFESTEAL_DAMAGE, "value": 9},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_EXECUTE, "value": 3},
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MANA, "value": 5},
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_ATTACK, "value": 2},
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MAX_HP, "value": 3},
	]}]

	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if enemy.hp != 0:
		_fail("execute should defeat enemy after lifesteal reduces HP to threshold")
	if caster.hp != 13:
		_fail("lifesteal plus max HP gain should heal caster to new max HP")
	if game.player_field.current_mana != 10:
		_fail("gain mana should increase current player's mana up to max")
	if caster.atk != 1 or caster.base_atk != 1 or caster.field_atk_bonus != 2 or caster.effective_atk() != 3:
		_fail("gain attack should add a field-only permanent bonus without changing base attack")
	if caster.max_hp != 13 or caster.base_max_hp != 13:
		_fail("gain max HP should permanently increase current and base max HP")
	var high_hp_enemy := _card("High HP Enemy", 10, 0)
	game.player2_field.slots[2] = high_hp_enemy
	caster.skills = [{"skill_name": "Execute Check", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_EXECUTE, "value": 3},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 2))
	if high_hp_enemy.hp != 10:
		_fail("execute should not defeat targets above the HP threshold")

	var status_target := _card("Status Target", 10, 0)
	status_target.apply_buff(SkillEngine.BUFF_SILENCE, 1, 2)
	status_target.apply_buff(SkillEngine.BUFF_MISFORTUNE, 10, 2)
	status_target.apply_buff(SkillEngine.BUFF_ATK_BOOST, 2, 2)
	status_target.apply_buff(SkillEngine.BUFF_TAUNT, 1, 2)
	game.player2_field.slots[1] = status_target
	caster.skills = [{"skill_name": "Status Remove", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_CLEANSE, "value": 1},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1))
	if status_target.is_silenced() or status_target.get_misfortune() != 0:
		_fail("cleanse should remove negative statuses")
	if not status_target.has_taunt() or status_target.effective_atk() != 2:
		_fail("cleanse should not remove positive statuses")
	caster.skills = [{"skill_name": "Status Remove", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DISPEL, "value": 1},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1))
	if status_target.has_taunt() or status_target.effective_atk() != 0:
		_fail("dispel should remove positive statuses")

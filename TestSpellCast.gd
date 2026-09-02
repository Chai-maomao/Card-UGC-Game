extends Node

const GameStateScript = preload("res://GameState.gd")
const SpellRules = preload("res://SpellRules.gd")

var failures: Array = []


func _ready() -> void:
	_test_spell_card_type_flag()
	_test_spell_cast_moves_to_discard()
	_test_spell_cast_consumes_mana()
	_test_spell_cast_triggers_on_cast_skill()
	_test_spell_cast_not_enough_mana_fails()
	_test_spell_cast_single_target()
	_test_spell_no_slot_occupation()
	_test_spell_does_not_grant_discard_mana()
	_test_spell_cast_from_hand_erases_it()
	_test_spell_draw_effect_resolves_without_target()
	_test_spell_gain_mana_effect_resolves_without_target()
	_test_spell_rules_normalize_trigger_and_name()
	_test_spell_rejects_second_skill_index()
	_test_enemy_spell_is_blocked_on_turn_one()
	_test_second_player_enemy_spell_is_blocked_on_turn_one()
	_test_ally_spell_is_allowed_on_turn_one()
	_test_nested_enemy_spell_is_blocked_on_turn_one()
	if failures.is_empty():
		print("TEST_SPELL_CAST_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


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


func _card(name: String, cost: int = 1, hp: int = 5, atk: int = 0, skills: Array = [], ctype: String = "minion") -> CardData:
	var card := CardData.new(name, cost, hp, atk, skills)
	card.card_type = ctype
	return card


func _spell(name: String, cost: int = 1, effects: Array = [], trigger: String = SkillEngine.TRIGGER_ON_CAST) -> CardData:
	return _card(name, cost, 0, 0, [
		{"skill_name": name, "trigger": trigger, "effects": effects},
	], "spell")


func _test_spell_card_type_flag() -> void:
	var minion := _card("Minion", 1, 5, 0, [], "minion")
	var spell := _card("Spell", 1, 0, 0, [], "spell")
	if minion.is_spell():
		_fail("minion was marked as spell")
	if not spell.is_spell():
		_fail("spell was not marked as spell")
	if spell.card_type != "spell":
		_fail("spell card_type value is wrong")


func _test_spell_cast_moves_to_discard() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 4},
	])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	var ok := game.cast_spell(game.player_hand.find(spell), SpellRules.CAST_SKILL_INDEX, -1)
	if not ok:
		_fail("cast_spell returned false for a valid spell")
	if game.player_hand.has(spell):
		_fail("cast spell was not removed from hand")
	if not game.shared_discard.has(spell):
		_fail("cast spell was not moved to discard")


func _test_spell_cast_consumes_mana() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	if game.player_field.current_mana != 2:
		_fail("cast spell did not consume mana (got %d)" % game.player_field.current_mana)


func _test_spell_cast_triggers_on_cast_skill() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 4},
	])
	var enemy := _card("Enemy")
	game.player2_field.slots[0] = enemy
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, 0)
	if enemy.hp != 1:
		_fail("on_cast damage was not dealt (enemy hp = %d)" % enemy.hp)


func _test_spell_cast_not_enough_mana_fails() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [])
	game.player_hand.append(spell)
	game.player_field.current_mana = 2
	var ok := game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	if ok:
		_fail("cast_spell should fail with insufficient mana")
	if not game.player_hand.has(spell):
		_fail("failed cast removed the card from hand")


func _test_spell_cast_single_target() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 4},
	])
	var enemy_a := _card("Enemy A")
	var enemy_b := _card("Enemy B")
	game.player2_field.slots[0] = enemy_a
	game.player2_field.slots[1] = enemy_b
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, 1)
	if enemy_a.hp != 5:
		_fail("spell hit wrong target (enemy_a hp = %d)" % enemy_a.hp)
	if enemy_b.hp != 1:
		_fail("spell single target did not hit selected target (enemy_b hp = %d)" % enemy_b.hp)


func _test_spell_no_slot_occupation() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	for i in range(5):
		if game.player_field.slots[i] == spell:
			_fail("spell card occupied a field slot after cast")


func _test_spell_does_not_grant_discard_mana() -> void:
	var game = _new_game()
	var spell := _spell("Fireball", 3, [])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	var mana_before: int = game.player_field.current_mana
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	var mana_after: int = game.player_field.current_mana
	if mana_after != mana_before - 3:
		_fail("spell cast should not refund the +1 discard mana (before=%d, after=%d)" % [mana_before, mana_after])


func _test_spell_cast_from_hand_erases_it() -> void:
	var game = _new_game()
	var spell := _spell("Draw", 2, [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_DRAW_CARDS, "value": 2},
	])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	var hand_size_before: int = game.player_hand.size()
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	if game.player_hand.size() != hand_size_before - 1:
		_fail("spell cast did not shrink hand by 1")


func _test_spell_draw_effect_resolves_without_target() -> void:
	var game = _new_game()
	var spell := _spell("Draw", 2, [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_DRAW_CARDS, "value": 2},
	])
	var draw_a := _card("Draw A")
	var draw_b := _card("Draw B")
	game.shared_deck.append(draw_a)
	game.shared_deck.append(draw_b)
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	if not game.player_hand.has(draw_a) or not game.player_hand.has(draw_b):
		_fail("spell draw effect did not draw cards without a live target")


func _test_spell_gain_mana_effect_resolves_without_target() -> void:
	var game = _new_game()
	var spell := _spell("Mana", 2, [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MANA, "value": 2},
	])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, -1)
	if game.player_field.current_mana != 5:
		_fail("spell gain mana effect did not resolve after cast cost (mana=%d)" % game.player_field.current_mana)


func _test_spell_rules_normalize_trigger_and_name() -> void:
	var spell := _spell("Clean Name", 2, [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MANA, "value": 1},
	], SkillEngine.TRIGGER_ON_ATTACK)
	var normalized: Dictionary = SpellRules.spell_skill(spell)
	if normalized.get("trigger", "") != SkillEngine.TRIGGER_ON_CAST:
		_fail("SpellRules did not normalize spell trigger to on_cast")
	if normalized.get("skill_name", "") != "Clean Name":
		_fail("SpellRules did not normalize spell skill name to card name")
	if not SpellRules.can_cast(spell, 2).get("ok", false):
		_fail("SpellRules rejected a spell that should be castable after normalization")


func _test_spell_rejects_second_skill_index() -> void:
	var game = _new_game()
	var spell := _card("Two Skill Spell", 1, 0, 0, [
		{"skill_name": "One", "trigger": SkillEngine.TRIGGER_ON_CAST, "effects": []},
		{"skill_name": "Two", "trigger": SkillEngine.TRIGGER_ON_CAST, "effects": []},
	], "spell")
	SpellRules.normalize_spell_card(spell)
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	var ok := game.cast_spell(0, 1, -1)
	if ok:
		_fail("spell cast should reject second skill index after normalization")


func _test_enemy_spell_is_blocked_on_turn_one() -> void:
	var game = _new_game()
	game.turn_number = 1
	var spell := _spell("Opening Fireball", 2, [{
		"target": SkillEngine.TARGET_SINGLE,
		"target_side": SkillEngine.TARGET_SIDE_ENEMY,
		"effect": SkillEngine.EFFECT_DAMAGE,
		"value": 3,
	}])
	var enemy := _card("Enemy")
	game.player2_field.slots[0] = enemy
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	if game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, 0):
		_fail("enemy-targeting spell was cast on turn one")
	if not game.player_hand.has(spell) or game.player_field.current_mana != 5 or enemy.hp != 5:
		_fail("blocked turn-one spell mutated hand, mana, or target")


func _test_second_player_enemy_spell_is_blocked_on_turn_one() -> void:
	var game = _new_game()
	game.current_player = 2
	game.turn_number = 1
	var spell := _spell("Opening Counterblast", 2, [{
		"target": SkillEngine.TARGET_SINGLE,
		"target_side": SkillEngine.TARGET_SIDE_ENEMY,
		"effect": SkillEngine.EFFECT_DAMAGE,
		"value": 3,
	}])
	var enemy := _card("First Player Target")
	game.player_field.slots[0] = enemy
	game.player2_hand.append(spell)
	game.player2_field.current_mana = 5
	if game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, 0):
		_fail("second player cast an enemy-targeting spell during round one")
	if not game.player2_hand.has(spell) or game.player2_field.current_mana != 5 or enemy.hp != 5:
		_fail("blocked second-player opening spell mutated hand, mana, or target")


func _test_ally_spell_is_allowed_on_turn_one() -> void:
	var game = _new_game()
	game.turn_number = 1
	var spell := _spell("Opening Heal", 2, [{
		"target": SkillEngine.TARGET_SINGLE,
		"target_side": SkillEngine.TARGET_SIDE_ALLY,
		"effect": SkillEngine.EFFECT_HEAL,
		"value": 2,
	}])
	var ally := _card("Ally")
	ally.hp = 2
	game.player_field.slots[0] = ally
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	if not game.cast_spell(0, SpellRules.CAST_SKILL_INDEX, 0):
		_fail("ally-only spell should be allowed on turn one")


func _test_nested_enemy_spell_is_blocked_on_turn_one() -> void:
	var game = _new_game()
	game.turn_number = 1
	var spell := _spell("Conditional Blast", 1, [{
		"effect": "if",
		"then_effects": [{
			"target": SkillEngine.TARGET_ALL,
			"target_side": SkillEngine.TARGET_SIDE_ENEMY,
			"effect": SkillEngine.EFFECT_DAMAGE,
			"value": 1,
		}],
	}])
	game.player_hand.append(spell)
	game.player_field.current_mana = 5
	if game.cast_spell(0):
		_fail("nested enemy-targeting spell was cast on turn one")

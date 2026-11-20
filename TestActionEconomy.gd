extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []


func _ready() -> void:
	_test_payments_and_rejection()
	_test_budget_and_restore()
	_test_skill_and_ai()
	_test_empty_field_attacks()
	_test_rules_validation()
	_test_mana_recovery()
	_test_disabled_actions()
	if failures.is_empty():
		print("TEST_ACTION_ECONOMY_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_ACTION_ECONOMY_FAILED: " + failure)
		get_tree().quit(1)


func _game():
	var game = Game.new()
	game.quiet = true
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	game.battle_config["death_compensation"] = false
	game.turn_number = 2
	for index in range(5):
		game.player_field.slots[index] = CardData.new("Attacker%d" % index, 1, 10, 1, [])
		game.player2_field.slots[index] = CardData.new("Target%d" % index, 1, 10, 0, [])
	game.reset_action_budget(1)
	return game


func _test_disabled_actions() -> void:
	var game = _game()
	for key in ["action_base", "action_empty_slot_factor", "action_empty_hand_factor", "action_mana_factor"]:
		game.battle_config.erase(key)
	_check(MatchAgreement.valid_config(game.battle_config), "disabled action rules must be accepted by match agreement")
	game.reset_action_budget(1)
	game.player_field.current_mana = 0
	for slot in range(5):
		_check(not game.execute_attack(slot, slot).is_empty(), "disabled action rules must permit an attack without AP or extra mana")
	_check(game.player_field.action_points == 0 and game.player_field.current_mana == 0, "disabled actions must consume neither resource")
	var restored = Game.new()
	restored.apply_initial_state(game.export_initial_state())
	_check(not restored.battle_config.has("action_base") and restored.next_action_payment().cost == 0, "snapshot restore must retain disabled action rules")


func _test_mana_recovery() -> void:
	for opener in [1, 2]:
		for growing in [false, true]:
			var game := Game.new()
			var rules := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate()
			rules["mana_per_turn"] = 2
			rules["second_extra_mana"] = 2
			if growing: rules["mana_increment"] = 3
			_check(MatchAgreement.valid_config(rules), "both recovery modes must be accepted by match agreement")
			game.initialize_fields(rules)
			game.deal_opening_hands(null, opener)
			var expected := [3, 2, 2, 5, 5, 8, 8, 10] if growing else [3, 2, 2, 2, 2, 2, 2, 2]
			for index in expected.size():
				game.player_field.current_mana = 0
				game.player2_field.current_mana = 0
				game.start_new_turn()
				_check(game.active_field().current_mana == expected[index], "the correct player must receive the configured recovery, capped at maximum")
				if index == 2:
					var rejoined := Game.new()
					rejoined.apply_initial_state(game.export_initial_state())
					game = rejoined
	var invalid := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate()
	for amount in [-1, 0, 1.5, 11, "2"]:
		invalid["mana_increment"] = amount
		_check(not MatchAgreement.valid_config(invalid), "the growth step must be an integer from one to ten")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _test_payments_and_rejection() -> void:
	var game = _game()
	game.player_field.action_points = 2
	game.player_field.current_mana = 4
	game.player_field.temp_mana = 1
	game.battle_config["action_mana_factor"] = 1.5
	_check(not game.execute_attack(0, 0).is_empty(), "first attack succeeds for free")
	_check(game.player_field.action_points == 2 and game.player_field.get_total_mana() == 5, "first attack costs no resources")
	game.execute_attack(1, 0)
	_check(game.player_field.action_points == 1, "second action costs one point")
	game.execute_attack(2, 0)
	_check(game.player_field.action_points == 0 and game.player_field.temp_mana == 0 and game.player_field.current_mana == 3, "third action pays remaining point and ceil(1*1.5) Elixir, temporary first")
	var hp: int = game.player2_field.slots[0].hp
	_check(game.execute_attack(3, 0).is_empty(), "unaffordable fourth action rejected")
	_check(game.player_field.actions_taken == 3 and not game.player_field.slots[3].has_acted and game.player2_field.slots[0].hp == hp and game.player_field.current_mana == 3, "rejection cannot mutate action, card, target or mana")
	game.player_field.current_mana = 5
	_check(not game.execute_attack(3, 0).is_empty() and game.player_field.current_mana == 0, "fourth action costs ceil(3*1.5)")
	_check(game.execute_attack(-1, 0).is_empty(), "invalid slot does not spend anything")


func _test_budget_and_restore() -> void:
	var game = _game()
	game.player_field.slots[3] = null
	game.player_field.slots[4] = null
	for index in range(5): game.player_hand.append(CardData.new("Hand%d" % index, 0, 3, 1, []))
	game.reset_action_budget(1)
	_check(game.player_field.action_budget == 6, "budget floors 3 + two slots + three half hand spaces")
	game.summon_card(game.player_hand[0], 3)
	_check(game.player_field.action_budget == 6, "deployment cannot recalculate current-turn budget")
	game.execute_attack(0, 0)
	game.execute_attack(1, 0)
	var restored = Game.new()
	restored.quiet = true
	restored.apply_initial_state(game.export_initial_state(), false)
	_check(restored.player_field.action_budget == 6 and restored.player_field.action_points == 5 and restored.player_field.actions_taken == 2, "snapshot preserves spent points and next action ordinal")
	_check(restored.next_action_payment() == game.next_action_payment(), "replay and reconnect quote exactly the same price")
	game.start_new_turn()
	_check(game.player2_field.actions_taken == 0 and game.player2_field.action_points == game.player2_field.action_budget, "new owner gets a fresh budget")
	var old_state: Dictionary = restored.export_initial_state()
	old_state.battle_config.erase("action_base")
	for field in [old_state.player_field, old_state.player2_field]:
		for key in ["action_points", "action_budget", "actions_taken"]: field.erase(key)
	restored.apply_initial_state(old_state, false)
	_check(restored.next_action_payment().cost == 0, "legacy saved matches retain free actions")


func _test_skill_and_ai() -> void:
	var game = _game()
	var skill := {"skill_name": "Hit", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100, "effects": [{"effect": "damage", "target": "single", "target_side": "enemy", "value": 10}]}
	game.player_field.slots[0].skills = [skill]
	_check(game.trigger_activate_skills(0, 0, 0), "active skill resolves")
	_check(game.player_field.actions_taken == 1 and game.player_field.current_mana == 4, "skill consumes an action but does not automatically refund a kill")
	_check(not game.trigger_activate_skills(0, 1, 0), "used skill cannot pay or trigger again")
	game.player_field.actions_taken = 4
	game.player_field.action_points = 0
	game.player_field.current_mana = 0
	game.player_field.slots[1].skills = [skill.duplicate(true)]
	_check(not game.trigger_activate_skills(1, 1, 0) and game.player_field.slots[1].skills_used.is_empty(), "failed skill leaves skill-use state intact")
	var actions: Array = BattleAiPlanner.generate_legal_actions(game)
	_check(not actions.any(func(a): return a.type in ["attack", "activate"]), "AI excludes unaffordable unit actions")
	game.player_hand.append(CardData.new("Deploy", 0, 3, 1, []))
	game.player_field.slots[4] = null
	_check(game.summon_card(game.player_hand[0], 4), "deployment still works with no action points or mana")


func _test_empty_field_attacks() -> void:
	var game = _game()
	game.player2_field.slots.fill(null)
	game.player_field.action_points = 1
	game.player_field.current_mana = 0
	var result: Dictionary = game.end_player_turn()
	_check(result.total_damage == 2 and result.cards_hit.size() == 2, "automatic base attacks must respect 0/1/2 cumulative prices")
	_check(game.player_field.actions_taken == 2, "base attacks share the action counter")
	_check(game.player2_field.player_hp == 28, "unaffordable attackers cannot bypass the budget at end turn")


func _test_rules_validation() -> void:
	var rules := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	rules.draw_per_turn = 8
	_check(MatchAgreement.valid_config(rules), "online rules accept eight-card draw and action coefficients")
	rules.action_mana_factor = -1
	_check(not MatchAgreement.valid_config(rules), "negative coefficient is rejected")
	var state: Dictionary = _game().export_initial_state()
	state.player_field.action_points = -1
	_check(not DataSchema.validate(DataSchema.KIND_MATCH_SNAPSHOT, {"schema": 1, "room_code": "STATE", "player": 1, "state": state}).is_empty(), "negative action state is rejected")

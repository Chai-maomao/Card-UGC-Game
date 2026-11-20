extends Node

var failures: Array[String] = []


func _ready() -> void:
	for source_player in [1, 2]:
		for blocked in [false, true]:
			for route in ["attack", "damage", "heal", "spell"]:
				_test_enemy_reaction(source_player, blocked, route)
	_test_ally_heal()
	_test_parasite_and_adjacent()
	_test_recursion_and_simulation()
	if failures.is_empty():
		print("TEST_REACTION_CONTEXT_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_REACTION_CONTEXT_FAILED: " + failure)
		get_tree().quit(1)


func _effect(kind: String, value: int, target: String = "self", side: String = "all") -> Dictionary:
	return {"effect": kind, "value": value, "target": target, "target_side": side}


func _game() -> RefCounted:
	var game := HeadlessBattleSimulator._create_game([], [], 6006, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.turn_number = 2
	game.player_field.current_mana = 3
	game.player2_field.current_mana = 3
	game.player_hand = [CardData.new("P1 hand", 1, 2, 0)]
	game.player2_hand = [CardData.new("P2 hand", 1, 2, 0)]
	game.shared_deck = [CardData.new("Drawn", 1, 3, 0)]
	return game


func _test_enemy_reaction(source_player: int, blocked: bool, route: String) -> void:
	var previous := EventBus.is_blocking_signals()
	EventBus.set_block_signals(blocked)
	var game := _game()
	game.current_player = source_player
	var source_field: BattleField = game.active_field()
	var receiver_field: BattleField = game.opponent_field()
	(game.player2_hand if source_player == 1 else game.player_hand).append(CardData.new("Receiver extra", 1, 2, 0))
	var trigger := "on_healed" if route == "heal" else "on_damaged"
	var variable := _effect("gain_attack", 0)
	variable.value_var = "hand_count"
	var reactor := CardData.new("Reactor", 1, 8, 0, [{"trigger": trigger, "effects": [_effect("gain_mana", 2), _effect("draw_cards", 1), variable, _effect("damage", 2, "target_single", "enemy"), {"effect": "add_buff", "buff_id": "regen", "duration": 2, "value": 1, "target": "self", "target_side": "all"}]}])
	reactor.hp = 6
	receiver_field.slots[1] = reactor
	var source := CardData.new("Initiator", 0, 8, 1, [{"trigger": "on_activate", "effects": [_effect("heal" if route == "heal" else "damage", 1, "target_single", "enemy")]}])
	source_field.slots[4] = source
	var decoy := CardData.new("Unrelated same-slot unit", 1, 8, 0)
	source_field.slots[1] = decoy
	if route == "spell":
		source_field.slots[4] = null
		source.card_type = "spell"
		source.skills[0].trigger = "on_cast"
		game.active_hand().append(source)
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	BattlePosition.ensure_ids(game)
	var record := BattleRepro.begin(game)
	var command: Dictionary
	if route == "attack": command = {"type": "attack", "source_slot": 4, "target_slot": 1}
	elif route == "spell": command = {"type": "cast", "hand_index": 1, "target_slot": 1, "target_player": 3 - source_player}
	else: command = {"type": "activate", "slot": 4, "skill_index": 0, "target_slot": 1, "target_player": 3 - source_player}
	_check(BattleRepro.execute_and_record(game, record, command).ok, route + " fixture must be accepted")
	var label := "%s p%d muted=%s" % [route, source_player, blocked]
	_check(receiver_field.current_mana == 5 and source_field.current_mana == 3, label + ": reactive income must belong to the receiver")
	_check((game.player2_hand if source_player == 1 else game.player_hand).size() == 3 and game.active_hand().size() == 1, label + ": reactive draw must use receiver hand")
	_check(reactor.field_atk_bonus == 3, label + ": reporters must see receiver hand after its draw")
	_check(decoy.hp == 8 and (source.hp == 6 if route != "spell" else source.hp == 8), label + ": directed response must target initiator, not original receiver slot or an absent spell")
	_check(int(reactor.status_effects.back().owner) == 3 - source_player, label + ": reactive buff owner must match receiver")
	_check(metrics.cards.get("Reactor", {}).get("mana_gained", 0) == 2 and metrics.cards.get("Reactor", {}).get("enemy_mana_gained", -1) == 0, label + ": actual metrics must report the receiver's income")
	_check(BattleRepro.verify(record).ok, label + ": silent replay must reproduce complete state")
	EventBus.set_block_signals(previous)


func _test_ally_heal() -> void:
	var game := _game()
	var source := CardData.new("Ally healer", 0, 8, 0, [{"trigger": "on_activate", "effects": [_effect("heal", 1, "target_single", "ally")]}])
	var receiver := CardData.new("Ally healed", 1, 8, 0, [{"trigger": "on_healed", "effects": [_effect("gain_attack", 2, "target_single", "ally"), _effect("damage", 2, "target_single", "enemy")]}])
	receiver.hp = 5
	game.player_field.slots[4] = source
	game.player_field.slots[1] = receiver
	var enemy := CardData.new("Unrelated opposite healer slot", 1, 8, 0)
	game.player2_field.slots[4] = enemy
	game.trigger_activate_skills(4, 1, 0, 1)
	_check(source.field_atk_bonus == 2 and receiver.field_atk_bonus == 0, "ally healing response must select the healer rather than inherit its target slot")
	_check(enemy.hp == 8, "a directed enemy response to ally healing must not select an unrelated enemy")


func _test_parasite_and_adjacent() -> void:
	var game := _game()
	var source := CardData.new("Initiator", 0, 8, 0, [{"trigger": "on_activate", "effects": [_effect("damage", 1, "target_single", "enemy")]}])
	var adjacent := CardData.new("Initiator neighbor", 1, 8, 0)
	var decoy := CardData.new("Unrelated", 1, 8, 0)
	game.player_field.slots[4] = source
	game.player_field.slots[3] = adjacent
	game.player_field.slots[1] = decoy
	var host := CardData.new("Host", 1, 8, 0)
	var parasite := CardData.new("Reactive parasite", 1, 5, 0, [{"trigger": "on_damaged", "effects": [_effect("gain_mana", 2), _effect("draw_cards", 1), _effect("damage", 2, "target_sides", "enemy")]}])
	parasite.card_type = "parasite"
	parasite.parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
	ParasiteRules.attach(parasite, host)
	game.player2_field.slots[1] = host
	BattlePosition.ensure_ids(game)
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	var record := BattleRepro.begin(game)
	_check(BattleRepro.execute_and_record(game, record, {"type": "activate", "slot": 4, "skill_index": 0, "target_slot": 1, "target_player": 2}).ok, "parasite reaction fixture must be legal")
	_check(game.player2_field.current_mana == 5 and game.player2_hand.size() == 2 and source.hp == 6 and adjacent.hp == 6 and decoy.hp == 8, "parasite response must use host owner's resources and initiator adjacency")
	_check(metrics.cards.get("Reactive parasite", {}).get("damage", 0) == 4 and metrics.cards.get("Reactive parasite", {}).get("mana_gained", 0) == 2, "parasite contribution must keep its own identity after context rebinding")
	_check(BattleRepro.verify(record).ok, "parasite reaction must replay completely")


func _test_recursion_and_simulation() -> void:
	var game := _game()
	var response := {"trigger": "on_damaged", "effects": [_effect("damage", 1, "target_single", "enemy")]}
	var source := CardData.new("Loop source", 0, 1000, 0, [{"trigger": "on_activate", "effects": [_effect("damage", 1, "target_single", "enemy")]}, response.duplicate(true)])
	game.player_field.slots[4] = source
	game.player2_field.slots[1] = CardData.new("Loop response", 1, 1000, 0, [response.duplicate(true)])
	var context: Dictionary = game.make_skill_context(4, 1, 2)
	SkillEngine.trigger_single_skill(source, 0, context)
	var budget: Dictionary = context.get("_ugc_budget", {})
	_check(budget.get("aborted", false) and int(budget.get("trigger_depth", -1)) == 0, "rebinding must preserve shared recursion budget and unwind it")
	_check(source.hp > 900 and game.player2_field.slots[1].hp > 900, "reciprocal damage must stop at the original trigger budget")
	game = _game()
	game.player_field.slots[4] = CardData.new("Random source", 0, 8, 1, [{"trigger": "on_activate", "effects": [_effect("damage", 1, "target_single", "enemy")]}])
	game.player2_field.slots[1] = CardData.new("Random response", 1, 8, 0, [{"trigger": "on_damaged", "probability": 75, "effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value_min": 1, "value_max": 3}]}])
	BattlePosition.ensure_ids(game)
	var before := BattleRepro.state_hash(game)
	var simulation: RefCounted = game.copy_for_simulation()
	var action := {"type": "activate", "slot": 4, "skill_index": 0, "target_slot": 1, "target_player": 2}
	BattleAiPlanner.choose_action(simulation, "hard", simulation.game_rng)
	_check(BattleRepro.state_hash(game) == before, "AI reaction previews must not mutate the live game")
	simulation = game.copy_for_simulation()
	var record := BattleRepro.begin(game)
	_check(BattleRepro.execute_and_record(game, record, action).ok and BattleRepro.apply_action(simulation, action).ok, "random reaction must be accepted in live and simulation states")
	_check(BattleRepro.state_hash(game) == BattleRepro.state_hash(simulation) and BattleRepro.verify(record).ok, "random reactions must preserve identical RNG and complete replay state")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

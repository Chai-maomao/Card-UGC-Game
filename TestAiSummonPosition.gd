extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []


func _ready() -> void:
	_test_distinct_positions()
	for player in [1, 2]:
		_test_adjacent_summon(player)
	if failures.is_empty():
		print("TEST_AI_SUMMON_POSITION_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_AI_SUMMON_POSITION_FAILED: " + failure)
		get_tree().quit(1)


func _test_distinct_positions() -> void:
	var ranked: Array = []
	for hand_index in [0, 1]:
		for slot in range(5):
			ranked.append({"type": "summon", "hand_index": hand_index, "slot": slot})
	ranked.append({"type": "end_turn"})
	_check(BattleSearch._diverse_actions(ranked, 20).size() == 11,
		"every distinct deployment position must survive deduplication when the budget allows")
	var bounded := BattleSearch._diverse_actions(ranked, 4)
	_check(bounded.size() == 4 and bounded.any(func(action): return int(action.get("hand_index", -1)) == 1),
		"different cards must retain search space before alternate placements fill the remaining width")
	ranked.append(ranked[0].duplicate(true))
	_check(BattleSearch._diverse_actions(ranked, 20).size() == 11,
		"identical actions must still be deduplicated")


func _test_adjacent_summon(player: int) -> void:
	var game = Game.new()
	game.quiet = true
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.player_field.quiet = true
	game.player2_field.quiet = true
	game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	game.game_rng.seed = 123
	game.current_player = player
	game.turn_number = 3
	game.first_switch = false
	var field: BattleField = game.active_field()
	for slot in [1, 3]:
		var ally := CardData.new("Ally%d" % slot, 1, 5, 1, [])
		ally.has_acted = true
		ally.has_attacked = true
		field.slots[slot] = ally
	var skill := {"trigger": SkillEngine.TRIGGER_ON_SUMMON, "effects": [
		{"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF_SIDES,
			"target_side": SkillEngine.TARGET_SIDE_ALLY, "value": 3}]}
	var source := CardData.new("Neighbor support", 1, 4, 1, [skill])
	game.active_hand().append(source)
	game.reset_action_budget(player)
	var before := BattleRepro.state_hash(game)
	var signal_state := EventBus.is_blocking_signals()
	var choice := BattleAiPlanner.choose_action(game, "hard", game.game_rng)
	_check(choice.get("type") == "summon" and int(choice.get("slot", -1)) == 2,
		"P%d must deploy between both allies instead of the first empty slot: %s" % [player, choice])
	_check(int(choice.get("search_nodes", 0)) > 0 and int(choice.get("search_nodes", 999)) <= BattleSearch.MAX_NODES,
		"position search must stay within its existing node budget")
	_check(BattleRepro.state_hash(game) == before and EventBus.is_blocking_signals() == signal_state,
		"position evaluation must preserve live cards, RNG, stats and signal suppression")
	var was_blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	var result := BattleRepro.apply_action(game, choice)
	EventBus.set_block_signals(was_blocked)
	_check(result.ok and field.slots[1].effective_atk() == 4 and field.slots[3].effective_atk() == 4,
		"the chosen legal deployment must actually grant the adjacent benefit to both allies")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

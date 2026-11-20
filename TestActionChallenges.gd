extends Node

const Simulator = preload("res://HeadlessBattleSimulator.gd")
var failures: Array[String] = []


func _ready() -> void:
	_test_costs_and_replays()
	_test_wrong_orders()
	_test_retry_budget()
	_test_turn_boundary()
	if failures.is_empty():
		print("TEST_ACTION_CHALLENGES_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_ACTION_CHALLENGES_FAILED: " + failure)
		get_tree().quit(1)


func _game(id: String) -> RefCounted:
	var game := Simulator._create_game([], [], 180)
	PracticeChallenges.configure(game, id)
	BattlePosition.ensure_ids(game)
	return game


func _test_costs_and_replays() -> void:
	var preferences := PlayerData.battle_config.duplicate(true)
	var paths := {
		"action_reserve": [
			{"type": "activate", "slot": 0, "skill_index": 0, "target_slot": 1, "target_player": 1},
			{"type": "attack", "source_slot": 1, "target_slot": 0},
		],
		"action_finish": [
			{"type": "cast", "hand_index": 0, "skill_index": 0, "target_slot": 0, "target_player": 1},
			{"type": "end_turn"},
		],
	}
	for id in paths:
		var game := _game(id)
		var record := BattleRepro.begin(game)
		var budget := 9 if id == "action_reserve" else 8
		_check(game.player_field.action_budget == budget and game.player_field.action_points == budget - 6 and game.player_field.actions_taken == 4, "late-turn snapshot must use default budget minus 0+1+2+3")
		_check(game.next_action_payment().cost == 4 and game.next_action_payment().points == budget - 6 and game.next_action_payment().mana == 10 - budget, "shared quote must reflect the fifth action")
		if id == "action_finish":
			var preview: Dictionary = game.preview_end_turn_attacks()
			_check(preview.total_damage == 1 and preview.blocked.size() == 1, "left Support must consume the only affordable automatic attack")
		var before := BattleRepro.state_hash(game)
		var rng_before: int = game.game_rng.state
		for index in range(3): PracticeChallenges.stage(game, id)
		_check(BattleRepro.state_hash(game) == before and game.game_rng.state == rng_before, "objective checks must be read-only")
		_check(BattleRepro.execute_and_record(game, record, paths[id][0]).ok, "setup must use a legal real command")
		BattleRepro.execute_and_record(game, record, {"type": "settle"})
		_check(PracticeChallenges.stage(game, id) == "payoff", "setup must advance objective feedback")
		if id == "action_reserve":
			_check(game.player_field.current_mana == 6 and game.player_field.action_points == 0 and game.player_field.actions_taken == 5, "skill must pay before granting mana, with one shared action")
			_check(game.next_action_payment().mana == 5, "follow-up attack must cost five Elixir")
		else:
			_check(game.player_field.action_points == 2 and game.player_field.actions_taken == 4, "spell and withdrawal must not recalculate or spend AP")
			_check(game.player_field.current_mana == 2 and game.player_field.temp_mana == 1, "spell must spend temporary Elixir first")
			_check(game.preview_end_turn_attacks().total_damage == 5, "withdrawal must preserve the Striker's automatic attack")
		_check(BattleRepro.execute_and_record(game, record, paths[id][1]).ok, "finishing move must be legal")
		BattleRepro.execute_and_record(game, record, {"type": "settle"})
		_check(PracticeChallenges.succeeded(game, id), "real sequence must complete the challenge")
		var verified := BattlePosition.read(BattleRepro.export_json(record))
		_check(verified.ok and BattleRepro.state_hash(verified.game) == BattleRepro.state_hash(game), "challenge solution must replay through every state hash")
	var alternative := _game("action_finish")
	var discard_record := BattleRepro.begin(alternative)
	_check(BattleRepro.execute_and_record(alternative, discard_record, {"type": "discard", "location": "field", "index": 0}).ok, "field discard must offer a legal alternative")
	_check(PracticeChallenges.stage(alternative, "action_finish") == "payoff" and not PracticeChallenges.succeeded(alternative, "action_finish"), "discard setup must still require ending the turn")
	BattleRepro.execute_and_record(alternative, discard_record, {"type": "end_turn"})
	_check(PracticeChallenges.succeeded(alternative, "action_finish") and BattleRepro.verify(discard_record).ok, "alternative discard solution must complete and replay")
	_check(PlayerData.battle_config == preferences, "training must not overwrite player preferences")


func _test_wrong_orders() -> void:
	var game := _game("action_reserve")
	BattleRepro.apply_action(game, {"type": "cast", "hand_index": 0, "skill_index": 0, "target_slot": 0, "target_player": 2})
	var before := BattleRepro.state_hash(game)
	_check(not BattleRepro.apply_action(game, {"type": "activate", "slot": 0, "skill_index": 0, "target_slot": 1, "target_player": 1}).ok, "future rewards must not fund an unaffordable skill")
	_check(BattleRepro.state_hash(game) == before and PracticeChallenges.failed(game, "action_reserve"), "rejected skill must leave state unchanged and explain failure")
	game = _game("action_reserve")
	BattleRepro.apply_action(game, {"type": "activate", "slot": 0, "skill_index": 0, "target_slot": 0, "target_player": 1})
	_check(PracticeChallenges.failed(game, "action_reserve"), "buffing the spent Officer must not masquerade as a viable setup")
	game = _game("action_finish")
	BattleRepro.apply_action(game, {"type": "end_turn"})
	_check(game.player2_field.player_hp == 5 and PracticeChallenges.failed(game, "action_finish"), "immediate end-turn must lose the high-damage opportunity")
	game = _game("action_finish")
	BattleRepro.apply_action(game, {"type": "cast", "hand_index": 0, "skill_index": 0, "target_slot": 1, "target_player": 1})
	_check(not PracticeChallenges.failed(game, "action_finish"), "returning the Striker to hand is recoverable and must not trigger failure")
	BattleRepro.apply_action(game, {"type": "summon", "hand_index": 0, "slot": 1})
	BattleRepro.apply_action(game, {"type": "discard", "location": "field", "index": 0})
	BattleRepro.apply_action(game, {"type": "end_turn"})
	_check(PracticeChallenges.succeeded(game, "action_finish"), "recovery through free redeployment and discard must remain available")
	game = _game("action_finish")
	BattleRepro.apply_action(game, {"type": "discard", "location": "field", "index": 1})
	_check(PracticeChallenges.failed(game, "action_finish"), "discarding the Striker must be recognized as irreversible failure")


func _test_retry_budget() -> void:
	for id in PracticeChallenges.IDS:
		var game := _game(id)
		var expected := [game.player_field.action_budget, game.player_field.action_points, game.player_field.actions_taken]
		var initial := BattleRepro.state_hash(game)
		game.player_field.action_points = 0
		game.player_field.actions_taken = 23
		game.player2_field.actions_taken = 17
		game.first_switch = true
		game.state_revision = 123
		game.stats[1].mana_spent = 42
		PracticeChallenges.configure(game, id)
		BattlePosition.ensure_ids(game)
		_check([game.player_field.action_budget, game.player_field.action_points, game.player_field.actions_taken] == expected and game.player2_field.actions_taken == 0, "retry must restore both action economies: " + id)
		_check(BattleRepro.state_hash(game) == initial, "retry must also restore statistics, first-switch phase, RNG and revision: " + id)


func _test_turn_boundary() -> void:
	var game := _game("combination")
	BattleRepro.apply_action(game, {"type": "end_turn"})
	_check(game.turn_number == 2 and game.current_player == 2 and PracticeChallenges.failed(game, "combination"), "switching to P2 must fail an unfinished single-turn challenge even before round number changes")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

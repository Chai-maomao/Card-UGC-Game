extends Node

const Position = preload("res://BattlePosition.gd")
const Simulator = preload("res://HeadlessBattleSimulator.gd")
const Game = preload("res://GameState.gd")
var failures: Array[String] = []


func _ready() -> void:
	_test_read_only_capture()
	_test_natural_sampling_and_continuation()
	_test_reject_bad_data()
	_test_limited_skill_restore()
	if failures.is_empty():
		print("TEST_BATTLE_POSITION_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_BATTLE_POSITION_FAILED: " + failure)
		get_tree().quit(1)


func _test_read_only_capture() -> void:
	var game = Game.new()
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.player_field.slots[0] = CardData.new("Generated unit", 1, 5, 2)
	game.shared_deck = CardDatabase.beginner_deck()
	game.game_rng.seed = 600
	game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	game.turn_number = 4
	game.reset_action_budget(1)
	var rng_before: int = game.game_rng.state
	var record := Position.capture(game, {"origin": "local_player", "nested": {"name": "author"}})
	_check(game.player_field.slots[0].card_id.is_empty() and game.player_field.slots[0].instance_id.is_empty() and game.shared_deck[0].card_id.is_empty(), "capture must not assign IDs to live cards")
	_check(game.game_rng.state == rng_before and game.stats[1].mana_spent == 0, "capture must leave RNG and statistics untouched")
	_check(BattleRepro.canonical_text(record) == BattleRepro.canonical_text(Position.capture(game, {"origin": "local_player", "nested": {"name": "author"}})), "same anonymous position must serialize deterministically")
	var loaded := Position.read(BattleRepro.export_json(record))
	_check(loaded.ok and BattleRepro.state_hash(loaded.game) == record.state_hashes[0], "position must round-trip without losing RNG precision")
	_check(record.position.players["1"].units == 1 and record.position.players["2"].units == 0, "position dimensions must describe the actual board")
	_check(Position.save(record, "user://position-test.json") == OK, "position must save")
	_check(Position.read(FileAccess.get_file_as_string("user://position-test.json")).ok, "saved position must load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://position-test.json"))


func _test_natural_sampling_and_continuation() -> void:
	var deck := CardDatabase.beginner_deck()
	for case in [["normal", 801], ["hard", 801], ["normal", 20261006]]:
		var level: String = case[0]
		var seed_value: int = case[1]
		var samples: Array = []
		var observer := func(game):
			if game.turn_number >= 4 and samples.size() < 2:
				samples.append(Position.capture(game, {"origin": "natural_simulation", "seed": seed_value, "phase": "turn_start_after_draw"}))
			# A consumer of snapshots must not be able to alter the source game.
			game.player_field.player_hp = 1
			game.player_hand.clear()
		var preferences := PlayerData.battle_config.duplicate(true)
		var sampled := Simulator.run_game(deck, deck, seed_value, level, level, 50, PlayerData.DEFAULT_BATTLE_CONFIG, observer)
		var baseline := Simulator.run_game(deck, deck, seed_value, level, level, 50, PlayerData.DEFAULT_BATTLE_CONFIG)
		_check(sampled.final_hash == baseline.final_hash and sampled.winner == baseline.winner, "observer must preserve source simulation determinism")
		_check(samples.size() == 2 and sampled.stable, "natural game must supply actual midgame samples")
		for sample in samples:
			var continuation := Position.continue_record(sample, level)
			_check(continuation.ok and continuation.stable and not continuation.capped, "natural sample must continue to a terminal result")
			if not continuation.ok: continue
			var expected := "p1_wins" if sampled.winner == "p1" else "p2_wins"
			var resumed: Dictionary = BattleRepro.verify(continuation.record)
			var changed: Array = []
			if resumed.ok:
				var actual: Dictionary = resumed.game.export_initial_state()
				for key in sampled.final_state:
					if BattleRepro.canonical_text(sampled.final_state[key]) != BattleRepro.canonical_text(actual[key]): changed.append(key)
				if not changed.is_empty():
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
					var difference := FileAccess.open("res://artifacts/position-difference.json", FileAccess.WRITE)
					difference.store_string(BattleRepro.export_json({"source": sampled.final_state, "resumed": actual}))
			_check(continuation.winner == expected and continuation.final_hash == sampled.final_hash, "continuation must match uninterrupted game including combat statistics and planner RNG: " + str(changed))
			var verified := BattleRepro.verify(continuation.record)
			_check(verified.ok and verified.final_hash == continuation.final_hash, "every continuation step must replay to the exact hash")
			var repeated := Position.continue_record(sample, level)
			_check(BattleRepro.canonical_text(continuation.record) == BattleRepro.canonical_text(repeated.record), "repeated continuation must choose identical actions")
		_check(PlayerData.battle_config == preferences, "position continuation must preserve user rules")


func _test_reject_bad_data() -> void:
	_check(not Position.read("invalid").ok, "invalid JSON must fail cleanly")
	_check(not Position.read('{"initial_state":{}}').ok, "incomplete record must fail cleanly")
	var game = Game.new()
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	var record := Position.capture(game)
	record.state_hashes[0] = "tampered"
	_check(not Position.read(BattleRepro.export_json(record)).ok, "tampered initial hash must be rejected")


func _test_limited_skill_restore() -> void:
	var card := CardData.new("Limited skill", 1, 5, 1, [{"trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "max_uses": 2, "effects": []}])
	card.skills_used_count[0] = 2
	var encoded := BattleRepro.export_json({"initial_state": {"card": PlayerData.serialize_card(card)}})
	var loaded: Dictionary = BattleRepro.import_json(encoded).record.initial_state.card
	var restored := PlayerData.deserialize_card(loaded)
	_check(restored.skills_used_count == {0: 2} and not SkillEngine.has_uses_remaining(restored, restored.skills[0], 0), "JSON restore must retain limited-use exhaustion with integer skill indexes")
	loaded.skills_used_count = {"0": 2, 0: 1}
	_check(PlayerData.deserialize_card(loaded).skills_used_count == {0: 2}, "mixed legacy skill counters must keep the larger count instead of resetting")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

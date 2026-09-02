extends Node

const BattleReproScript = preload("res://BattleRepro.gd")
const GameStateScript = preload("res://GameState.gd")

var failures: Array[String] = []


func _ready() -> void:
	_test_injected_seed_reproducibility()
	_test_snapshot_resume_determinism()
	_test_different_seed_difference()
	_test_tamper_detection()
	if failures.is_empty():
		print("TEST_BATTLE_REPRO_OK")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error("TEST_BATTLE_REPRO_FAILED: %s" % message)
		get_tree().quit(1)


func _test_injected_seed_reproducibility() -> void:
	var game := _make_game(71337)
	var record := BattleReproScript.begin(game)
	var actions := [
		{"type": "activate", "slot": 0, "skill_index": 0},
		{"type": "end_turn"},
		{"type": "activate", "slot": 0, "skill_index": 0},
		{"type": "end_turn"},
		{"type": "draw", "player": 1, "amount": 1},
	]
	for action in actions:
		var result := BattleReproScript.execute_and_record(game, record, action)
		_assert(bool(result.get("ok", false)), "recorded action must execute: %s" % action)
	var verified := BattleReproScript.verify(record)
	_assert(bool(verified.get("ok", false)), "same seed and actions must reproduce every state hash: %s" % verified)
	_assert(record["state_hashes"].size() == actions.size() + 1, "record must contain an initial and per-action hash")
	var imported := BattleReproScript.import_json(BattleReproScript.export_json(record))
	_assert(bool(imported.get("ok", false)), "reproduction record must round-trip as JSON")
	if bool(imported.get("ok", false)):
		var json_changed: Array[String] = []
		for key in record["initial_state"].keys():
			if BattleReproScript.canonical_text(record["initial_state"][key]) != BattleReproScript.canonical_text(imported["record"]["initial_state"].get(key)):
				json_changed.append(str(key))
		var exported_verify := BattleReproScript.verify(imported["record"])
		_assert(bool(exported_verify.get("ok", false)), "exported JSON replay must retain exact state (changed=%s current=%s imported=%s expected=%s): %s" % [json_changed, BattleReproScript.hash_state(record["initial_state"]), BattleReproScript.hash_state(imported["record"]["initial_state"]), record["state_hashes"][0], exported_verify])


func _test_snapshot_resume_determinism() -> void:
	var uninterrupted := _make_game(8080)
	BattleReproScript.apply_action(uninterrupted, {"type": "activate", "slot": 0, "skill_index": 0})
	BattleReproScript.apply_action(uninterrupted, {"type": "end_turn"})
	var snapshot: Dictionary = uninterrupted.export_initial_state()
	var resumed := GameStateScript.new()
	resumed.apply_initial_state(snapshot)
	var continuation := [
		{"type": "activate", "slot": 0, "skill_index": 0},
		{"type": "end_turn"},
		{"type": "activate", "slot": 0, "skill_index": 0},
		{"type": "draw", "player": 1, "amount": 1},
	]
	for action in continuation:
		var left := BattleReproScript.apply_action(uninterrupted, action)
		var right := BattleReproScript.apply_action(resumed, action)
		_assert(bool(left.get("ok", false)) and bool(right.get("ok", false)), "resume continuation action must be legal")
		_assert(BattleReproScript.state_hash(uninterrupted) == BattleReproScript.state_hash(resumed), "snapshot resume must match uninterrupted state after %s" % action)


func _test_different_seed_difference() -> void:
	var first := _make_game(1)
	var second := _make_game(2)
	for _i in range(4):
		BattleReproScript.apply_action(first, {"type": "activate", "slot": 0, "skill_index": 0})
		BattleReproScript.apply_action(second, {"type": "activate", "slot": 0, "skill_index": 0})
		BattleReproScript.apply_action(first, {"type": "end_turn"})
		BattleReproScript.apply_action(second, {"type": "end_turn"})
	_assert(BattleReproScript.state_hash(first) != BattleReproScript.state_hash(second), "different seeds must produce distinguishable battle state")


func _test_tamper_detection() -> void:
	var game := _make_game(42)
	var record := BattleReproScript.begin(game)
	BattleReproScript.execute_and_record(game, record, {"type": "activate", "slot": 0, "skill_index": 0})
	record["state_hashes"][1] = "tampered"
	var verified := BattleReproScript.verify(record)
	_assert(not bool(verified.get("ok", true)) and verified.get("reason") == "hash_mismatch", "changed replay hash must be detected")


func _make_game(seed_value: int) -> RefCounted:
	var game := GameStateScript.new()
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.game_rng.seed = seed_value
	game.turn_number = 2
	game.current_player = 1
	game.first_switch = false
	game.player_field.slots[0] = _random_card("p1_unit", "P1 Unit")
	game.player2_field.slots[0] = _random_card("p2_unit", "P2 Unit")
	for index in range(3):
		var card := CardData.new("Deck %d" % index, 1, 2, 1, [])
		card.card_id = "deck_card_%d" % index
		card.instance_id = "deck_instance_%d" % index
		game.shared_deck.append(card)
	return game


func _random_card(identifier: String, display_name: String) -> CardData:
	var skill := {
		"skill_name": "Seeded boost",
		"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
		"probability": 100,
		"effects": [{
			"effect": SkillEngine.EFFECT_GAIN_ATTACK,
			"target": SkillEngine.TARGET_SELF,
			"value_min": 1,
			"value_max": 9,
		}],
	}
	var card := CardData.new(display_name, 1, 5, 1, [skill])
	card.card_id = identifier
	card.instance_id = identifier + "_instance"
	return card


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

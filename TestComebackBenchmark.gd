extends Node

const Benchmark = preload("res://ComebackBenchmark.gd")
var failures: Array[String] = []


func _ready() -> void:
	var config_before := PlayerData.battle_config.duplicate(true)
	var pool := Benchmark.vanilla_pool()
	var state := Benchmark.make_state(pool, Benchmark.scenarios()[2], 7301, 2, true)
	_check(state == Benchmark.make_state(pool, Benchmark.scenarios()[2], 7301, 2, true), "initial snapshot is deterministic, including identities and RNG")
	_check(state["current_player"] == 2 and state["turn_number"] == 5 and not state["first_switch"], "continuation begins in a standard midgame turn")
	_check(_count(state["player_field"]["slots"]) == 4 and _count(state["player2_field"]["slots"]) == 1, "leader/trailer receive the declared board advantage")
	var legacy := Benchmark.with_rules(state, "legacy")
	_check(not legacy["battle_config"].has("action_base") and state["battle_config"].has("action_base"), "legacy comparison toggles AP without mutating source state")
	_check(legacy["player_hand"] == state["player_hand"] and legacy["shared_deck"] == state["shared_deck"] and legacy["rng_state"] == state["rng_state"], "paired initial hands, draw order and RNG are identical")
	var first := Benchmark.run(state, 2)
	var repeated := Benchmark.run(state, 2)
	_check(first == repeated and first["stable"], "fixed continuation repeats exactly without illegal actions")
	_check(PlayerData.battle_config == config_before, "benchmark must not change player preferences")
	var mirrored := Benchmark.make_state(pool, Benchmark.scenarios()[2], 7301, 1, true)
	_check(mirrored["player_hand"] == state["player2_hand"] and mirrored["player_field"]["slots"] == state["player2_field"]["slots"], "swapping player labels preserves the role's cards and placements")
	# End-turn lethal must be checked before the defender's start-turn healing.
	var lethal := Benchmark.make_state(pool, {"leader_units": 1, "trailer_units": 0, "leader_hand": 0, "trailer_hand": 0, "trailer_hp": 1}, 17, 2, false)
	lethal["shared_deck"] = []
	var terminal := Benchmark.run(lethal, 2, "action", "hard", 10)
	_check(terminal["outcome"] == "held" and terminal["turns"] == 1 and terminal["trailer"]["turns"] == 0, "end-turn lethal stops before the next player's turn")
	var capped := Benchmark.run(state, 2, "action", "hard", 1)
	_check(capped["capped"] and capped["stable"] and capped["outcome"] == "draw", "turn cap is reported separately from an invalid action")
	if failures.is_empty():
		print("TEST_COMEBACK_BENCHMARK_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_COMEBACK_BENCHMARK_FAILED: " + failure)
		get_tree().quit(1)


func _count(slots: Array) -> int:
	var result := 0
	for card in slots:
		if card != null and not card.is_empty(): result += 1
	return result


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

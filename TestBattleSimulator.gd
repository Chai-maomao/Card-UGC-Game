extends Node

const Simulator = preload("res://HeadlessBattleSimulator.gd")

var failures: Array[String] = []


func _ready() -> void:
	_assert(int(PlayerData.battle_config.get("second_extra_cards", -1)) == 0, "default P2 extra cards must match calibrated setting")
	_assert(int(PlayerData.battle_config.get("second_extra_mana", -1)) == 2, "default P2 extra mana must match calibrated setting")
	_assert(bool(PlayerData.battle_config.get("death_compensation", false)), "default death compensation must be enabled")
	_assert(not bool(PlayerData.battle_config.get("face_damage_compensation", true)), "default face-damage compensation must be disabled")
	var deck_a := _deck("A", 10, 2, 3, 2)
	var deck_b := _deck("B", 10, 3, 4, 3)
	var started := Time.get_ticks_msec()
	var result := Simulator.run_batch({"games": 1000, "seed": 9000, "deck_a": deck_a, "deck_b": deck_b, "ai_a": "hard", "ai_b": "hard", "swap_sides": true, "max_rounds": 50})
	var elapsed := Time.get_ticks_msec() - started
	_assert(int(result.get("games", 0)) == 1000, "batch did not complete 1000 games")
	_assert(int(result.get("stability_failures", -1)) == 0, "simulation reported illegal loops or crashes")
	_assert(int(result.get("rounds", {}).get("maximum", 999)) <= 50, "simulation exceeded round cap")
	_assert(result.get("win_rate", {}).has("p1") and result.has("first_player_win_rate"), "first/second player metrics missing")
	_assert(absf(float(result.get("first_player_win_rate", 0.0)) - 0.5) <= 0.04, "calibrated default first-player win rate drifted beyond 46-54%")
	_assert(float(result.get("mana_utilization", -1.0)) >= 0.0, "mana utilization missing")
	_assert(not result.get("card_metrics", {}).is_empty(), "per-card metrics missing")
	_assert(JSON.parse_string(Simulator.to_json(result)) is Dictionary, "machine-readable JSON export invalid")
	_assert(Simulator.to_csv(result).begins_with("section,key,value"), "machine-readable CSV export invalid")
	var repeat_options := {"games": 20, "seed": 77, "deck_a": deck_a, "deck_b": deck_b, "ai_a": "normal", "ai_b": "normal", "swap_sides": true, "max_rounds": 30}
	_assert(Simulator.to_json(Simulator.run_batch(repeat_options)) == Simulator.to_json(Simulator.run_batch(repeat_options)), "fixed seed batch rerun was not deterministic")
	if failures.is_empty():
		print("TEST_BATTLE_SIMULATOR_OK games=1000 elapsed_ms=%d p1=%.3f deck_a=%.3f avg_rounds=%.2f" % [elapsed, result["win_rate"]["p1"], result["win_rate"]["deck_a"], result["rounds"]["average"]])
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_BATTLE_SIMULATOR_FAILED: %s" % failure)
		get_tree().quit(1)


func _deck(prefix: String, count: int, cost: int, hp: int, atk: int) -> Array:
	var cards: Array = []
	for index in range(count):
		var card := CardData.new("%s-%02d" % [prefix, index], cost, hp + index % 2, atk + index % 2, [])
		card.card_id = "%s-card-%d" % [prefix, index]
		card.instance_id = "%s-instance-%d" % [prefix, index]
		cards.append(card)
	return cards


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

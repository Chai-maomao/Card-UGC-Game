class_name HeadlessBattleSimulator
extends RefCounted

const GameStateScript = preload("res://GameState.gd")
const Planner = preload("res://BattleAiPlanner.gd")
const Repro = preload("res://BattleRepro.gd")

const DEFAULT_MAX_ROUNDS := 60
const MAX_ACTIONS_PER_TURN := 40


static func run_batch(options: Dictionary) -> Dictionary:
	var games := maxi(1, int(options.get("games", 1)))
	var seed_value := int(options.get("seed", 1))
	var deck_a: Array = options.get("deck_a", [])
	var deck_b: Array = options.get("deck_b", [])
	var swap_sides := bool(options.get("swap_sides", false))
	var difficulty_a := str(options.get("ai_a", "normal"))
	var difficulty_b := str(options.get("ai_b", "normal"))
	var max_rounds := maxi(1, int(options.get("max_rounds", DEFAULT_MAX_ROUNDS)))
	var battle_config: Dictionary = options.get("battle_config", PlayerData.battle_config).duplicate(true)
	var outcomes := {"p1": 0, "p2": 0, "draw": 0, "deck_a": 0, "deck_b": 0}
	var rounds: Array[int] = []
	var card_metrics := {}
	var mana_spent := 0
	var unused_mana := 0
	var failures := 0
	for index in range(games):
		var swapped := swap_sides and index % 2 == 1
		var p1_deck := deck_b if swapped else deck_a
		var p2_deck := deck_a if swapped else deck_b
		var p1_ai := difficulty_b if swapped else difficulty_a
		var p2_ai := difficulty_a if swapped else difficulty_b
		var result := run_game(p1_deck, p2_deck, seed_value + index, p1_ai, p2_ai, max_rounds, battle_config)
		var winner := str(result.get("winner", "draw"))
		outcomes[winner] = int(outcomes.get(winner, 0)) + 1
		if winner == "p1":
			outcomes["deck_b" if swapped else "deck_a"] += 1
		elif winner == "p2":
			outcomes["deck_a" if swapped else "deck_b"] += 1
		rounds.append(int(result.get("rounds", max_rounds)))
		mana_spent += int(result.get("mana_spent", 0))
		unused_mana += int(result.get("unused_mana", 0))
		failures += 0 if bool(result.get("stable", false)) else 1
		_merge_card_metrics(card_metrics, result.get("cards", {}))
	rounds.sort()
	var decisive := maxi(1, games - int(outcomes["draw"]))
	return {
		"version": 1,
		"seed": seed_value,
		"games": games,
		"swap_sides": swap_sides,
		"wins": outcomes,
		"win_rate": {
			"p1": float(outcomes["p1"]) / games,
			"p2": float(outcomes["p2"]) / games,
			"deck_a": float(outcomes["deck_a"]) / decisive,
			"deck_b": float(outcomes["deck_b"]) / decisive,
		},
		"rounds": {
			"average": _average(rounds),
			"p50": _percentile(rounds, 0.50),
			"p90": _percentile(rounds, 0.90),
			"p95": _percentile(rounds, 0.95),
			"maximum": rounds[-1] if not rounds.is_empty() else 0,
		},
		"first_player_win_rate": float(outcomes["p1"]) / decisive,
		"mana_utilization": float(mana_spent) / maxi(1.0, float(mana_spent + unused_mana)),
		"mana_spent": mana_spent,
		"card_metrics": card_metrics,
		"stability_failures": failures,
	}


static func run_game(deck_p1: Array, deck_p2: Array, seed_value: int, ai_p1: String = "normal", ai_p2: String = "normal", max_rounds: int = DEFAULT_MAX_ROUNDS, battle_config: Dictionary = {}) -> Dictionary:
	var game := _create_game(deck_p1, deck_p2, seed_value, battle_config)
	var card_metrics := {}
	var unused_mana := 0
	var stable := true
	var winner := ""
	while game.turn_number <= max_rounds:
		var action_count := 0
		while action_count < MAX_ACTIONS_PER_TURN:
			action_count += 1
			var difficulty := ai_p1 if game.current_player == 1 else ai_p2
			var action := Planner.choose_action(game, difficulty, game.game_rng)
			var before := _capture_action_state(game, action)
			if str(action.get("type", "")) == "end_turn":
				unused_mana += game.active_field().get_total_mana()
			var applied := Repro.apply_action(game, action)
			if not bool(applied.get("ok", false)):
				stable = false
				break
			_record_action_metrics(card_metrics, game, action, before)
			game.cleanup_deaths()
			winner = game.check_game_over()
			if winner != "" or str(action.get("type", "")) == "end_turn":
				break
		if not stable or winner != "":
			break
		if action_count >= MAX_ACTIONS_PER_TURN:
			stable = false
			break
	if winner == "p1_wins":
		winner = "p1"
	elif winner == "p2_wins":
		winner = "p2"
	else:
		winner = "draw"
	return {
		"winner": winner,
		"rounds": mini(game.turn_number, max_rounds),
		"stable": stable,
		"mana_spent": int(game.get_stats(1).get("mana_spent", 0)) + int(game.get_stats(2).get("mana_spent", 0)),
		"unused_mana": unused_mana,
		"cards": card_metrics,
		"final_hash": Repro.state_hash(game),
	}


static func to_json(result: Dictionary) -> String:
	return JSON.stringify(result, "\t")


static func to_csv(result: Dictionary) -> String:
	var lines := ["section,key,value"]
	for key in result.get("win_rate", {}).keys():
		lines.append("win_rate,%s,%s" % [key, result["win_rate"][key]])
	for key in result.get("rounds", {}).keys():
		lines.append("rounds,%s,%s" % [key, result["rounds"][key]])
	lines.append("summary,mana_utilization,%s" % result.get("mana_utilization", 0.0))
	lines.append("summary,stability_failures,%s" % result.get("stability_failures", 0))
	lines.append("card,name,summons,skills,attacks,damage,healing")
	for card_name in result.get("card_metrics", {}).keys():
		var metric: Dictionary = result["card_metrics"][card_name]
		lines.append("card,%s,%d,%d,%d,%d,%d" % [card_name, metric.get("summons", 0), metric.get("skills", 0), metric.get("attacks", 0), metric.get("damage", 0), metric.get("healing", 0)])
	return "\n".join(lines)


static func _create_game(deck_p1: Array, deck_p2: Array, seed_value: int, battle_config: Dictionary = {}) -> RefCounted:
	var game := GameStateScript.new()
	game.quiet = true
	game.battle_config = (battle_config if not battle_config.is_empty() else PlayerData.battle_config).duplicate(true)
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.player_field.quiet = true
	game.player2_field.quiet = true
	game.game_rng.seed = seed_value
	for card in deck_p1:
		if card is CardData:
			game.shared_deck.append(card.duplicate_card())
	for card in deck_p2:
		if card is CardData:
			game.shared_deck.append(card.duplicate_card())
	GameplayRng.shuffle(game.shared_deck, game.game_rng)
	game.draw_cards_for_player(3, 1)
	game.draw_cards_for_player(3, 2)
	game.current_player = 1
	game.turn_number = 1
	return game


static func _capture_action_state(game: RefCounted, action: Dictionary) -> Dictionary:
	var source_name := ""
	var target_hp := -1
	var target: CardData = null
	match str(action.get("type", "")):
		"summon", "cast", "attach":
			var index := int(action.get("hand_index", -1))
			if index >= 0 and index < game.active_hand().size():
				source_name = game.active_hand()[index].card_name
		"activate":
			var slot := int(action.get("slot", -1))
			if slot >= 0 and game.active_field().slots[slot] != null:
				source_name = game.active_field().slots[slot].card_name
		"attack":
			var source_slot := int(action.get("source_slot", -1))
			if source_slot >= 0 and game.active_field().slots[source_slot] != null:
				source_name = game.active_field().slots[source_slot].card_name
			target = game.opponent_field().slots[int(action.get("target_slot", -1))]
			target_hp = target.hp + target.temp_hp if target != null else -1
	return {"source": source_name, "target": target, "target_hp": target_hp, "ally_hp": _total_hp(game.active_field()), "enemy_hp": _total_hp(game.opponent_field())}


static func _record_action_metrics(metrics: Dictionary, game: RefCounted, action: Dictionary, before: Dictionary) -> void:
	var name := str(before.get("source", ""))
	if name.is_empty():
		return
	if not metrics.has(name):
		metrics[name] = {"summons": 0, "skills": 0, "attacks": 0, "casts": 0, "damage": 0, "healing": 0}
	var metric: Dictionary = metrics[name]
	match str(action.get("type", "")):
		"summon": metric["summons"] += 1
		"activate": metric["skills"] += 1
		"cast":
			metric["casts"] += 1
			metric["skills"] += 1
		"attack": metric["attacks"] += 1
	var enemy_damage := maxi(0, int(before.get("enemy_hp", 0)) - _total_hp(game.opponent_field()))
	var ally_healing := maxi(0, _total_hp(game.active_field()) - int(before.get("ally_hp", 0)))
	metric["damage"] += enemy_damage
	metric["healing"] += ally_healing


static func _total_hp(field: BattleField) -> int:
	var total := field.player_hp
	for card in field.slots:
		if card is CardData:
			total += maxi(0, card.hp) + maxi(0, card.temp_hp)
	return total


static func _merge_card_metrics(target: Dictionary, source: Dictionary) -> void:
	for card_name in source.keys():
		if not target.has(card_name):
			target[card_name] = {"summons": 0, "skills": 0, "attacks": 0, "casts": 0, "damage": 0, "healing": 0}
		for key in target[card_name].keys():
			target[card_name][key] += int(source[card_name].get(key, 0))


static func _average(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += value
	return float(total) / values.size()


static func _percentile(values: Array[int], fraction: float) -> int:
	if values.is_empty():
		return 0
	return values[clampi(int(ceil(values.size() * fraction)) - 1, 0, values.size() - 1)]

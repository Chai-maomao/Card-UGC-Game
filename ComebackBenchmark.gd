class_name ComebackBenchmark
extends RefCounted

const Game = preload("res://GameState.gd")
const Planner = preload("res://BattleAiPlanner.gd")
const Repro = preload("res://BattleRepro.gd")
const MAX_ACTIONS := 40
const AP_KEYS := ["action_base", "action_empty_slot_factor", "action_empty_hand_factor", "action_mana_factor"]


static func scenarios() -> Array:
	return [
		{"id": "equal", "leader_units": 2, "trailer_units": 2},
		{"id": "slight", "leader_units": 3, "trailer_units": 2},
		{"id": "medium", "leader_units": 4, "trailer_units": 1},
		{"id": "empty", "leader_units": 5, "trailer_units": 0},
		{"id": "combined", "leader_units": 4, "trailer_units": 1, "leader_hp": 26, "trailer_hp": 16, "leader_hand": 5, "trailer_hand": 2, "leader_mana": 8, "trailer_mana": 4},
		{"id": "weak_spots", "leader_units": 4, "trailer_units": 1, "leader_unit_hp": 2},
	]


static func vanilla_pool() -> Array:
	var pool: Array = []
	for index in range(24):
		var cost := 1 + index % 4
		pool.append(CardData.new("Body-%d" % cost, cost, cost + 1, cost, []))
	return pool


# A declared midgame intervention, after the starting player's draw. The two
# rules receive exactly the same cards, placement and RNG state at this point.
static func make_state(pool: Array, scenario: Dictionary, seed_value: int, trailer: int, trailer_next: bool) -> Dictionary:
	var game := Game.new()
	game.quiet = true
	game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.player_field.quiet = true
	game.player2_field.quiet = true
	game.game_rng.seed = seed_value
	game.turn_number = 5
	game.first_switch = false
	game.current_player = trailer if trailer_next else 3 - trailer
	var serial := 0
	for _copy in range(2):
		for specimen: CardData in pool:
			var card := specimen.duplicate_card()
			card.card_id = specimen.card_id if not specimen.card_id.is_empty() else "benchmark-pool-%d" % (serial % pool.size())
			card.instance_id = "bench-pool-%d" % serial
			serial += 1
			game.shared_deck.append(card)
	GameplayRng.shuffle(game.shared_deck, game.game_rng)
	for role in ["leader", "trailer"]:
		var player: int = trailer if role == "trailer" else 3 - trailer
		var field: BattleField = game.player_field if player == 1 else game.player2_field
		field.player_hp = int(scenario.get(role + "_hp", 30))
		field.current_mana = int(scenario.get(role + "_mana", 6))
		game.draw_cards_for_player(int(scenario.get(role + "_hand", 4)), player)
		var positions: Array = [0, 1, 2, 3, 4]
		GameplayRng.shuffle(positions, game.game_rng)
		for index in range(int(scenario.get(role + "_units", 2))):
			var unit := CardData.new("Benchmark Unit", 2, 4, 2, [])
			unit.card_id = "benchmark-unit"
			unit.instance_id = "bench-%s-%d" % [role, index]
			unit.hp = int(scenario.get(role + "_unit_hp", 4))
			unit.summoned_this_turn = false
			field.slots[positions[index]] = unit
	game.reset_action_budget(1)
	game.reset_action_budget(2)
	return game.export_initial_state()


static func with_rules(state: Dictionary, variant: String) -> Dictionary:
	var snapshot := state.duplicate(true)
	var config: Dictionary = snapshot["battle_config"]
	match variant:
		"legacy":
			for key in AP_KEYS: config.erase(key)
		"board_x2": config["action_empty_slot_factor"] = 2.0
		"elixir_x2": config["action_mana_factor"] = 2.0
		"no_hand": config["action_empty_hand_factor"] = 0.0
		"base_1": config["action_base"] = 1
	return snapshot


static func run(state: Dictionary, trailer: int, variant: String = "action", ai: String = "hard", max_turns: int = 100) -> Dictionary:
	var game := Game.new()
	game.quiet = true
	game.apply_initial_state(with_rules(state, variant), false)
	game.draw_callable = game.draw_cards
	game.reset_action_budget(1)
	game.reset_action_budget(2)
	var winner := game.check_game_over()
	var stable := true
	var turns := 0
	var metrics := {1: _metrics(), 2: _metrics()}
	var first_turn_metrics := {}
	var restored_board := false
	var failed_action := {}
	while winner == "" and turns < max_turns:
		var player: int = game.current_player
		var field: BattleField = game.active_field()
		var metric: Dictionary = metrics[player]
		metric["turns"] += 1
		var actions := 0
		var ended := false
		while actions < MAX_ACTIONS:
			var action: Dictionary = Planner.choose_action(game, ai, game.game_rng)
			var kind := str(action.get("type", ""))
			var payment: Dictionary = game.next_action_payment()
			if kind == "end_turn":
				if not game.can_pay_action(): metric["blocked_turns"] += 1
				var before_auto := field.actions_taken
				var mana_before := int(game.get_stats(player).get("mana_spent", 0))
				# Match the battle UI: lethal end-turn damage ends the game before
				# the next player's passives/draw can run.
				game.end_player_turn()
				game.cleanup_deaths()
				metric["auto_actions"] += field.actions_taken - before_auto
				metric["ap_elixir"] += int(game.get_stats(player).get("mana_spent", 0)) - mana_before
				winner = game.check_game_over()
				if not first_turn_metrics.has(player): first_turn_metrics[player] = metric.duplicate(true)
				if winner == "": game.start_new_turn()
				ended = true
				break
			var applied: Dictionary = Repro.apply_action(game, action)
			if not bool(applied.get("ok", false)):
				stable = false
				failed_action = action
				break
			if kind in ["attack", "activate"]:
				metric["unit_actions"] += 1
				metric["ap_elixir"] += int(payment["mana"])
			elif kind == "summon": metric["deployments"] += 1
			elif kind == "cast": metric["spells"] += 1
			actions += 1
			game.cleanup_deaths()
			winner = game.check_game_over()
			var ally: BattleField = game.player_field if trailer == 1 else game.player2_field
			var enemy: BattleField = game.player2_field if trailer == 1 else game.player_field
			if _board_count(ally) >= _board_count(enemy) and _board_hp(ally) >= _board_hp(enemy): restored_board = true
			if winner != "": break
		turns += 1
		if not first_turn_metrics.has(player): first_turn_metrics[player] = metric.duplicate(true)
		if not stable: break
		if winner == "" and not ended:
			stable = false
			failed_action = {"reason": "action_cap"}
			break
	var trailer_won := winner == ("p1_wins" if trailer == 1 else "p2_wins")
	return {
		"outcome": "comeback" if trailer_won else ("held" if winner != "" else "draw"),
		"stable": stable, "capped": winner == "" and stable, "failed_action": failed_action,
		"turns": turns, "board_restored": restored_board,
		"trailer": metrics[trailer], "leader": metrics[3 - trailer],
		"first_trailer": first_turn_metrics.get(trailer, {}), "first_leader": first_turn_metrics.get(3 - trailer, {}),
	}


static func _metrics() -> Dictionary:
	return {"turns": 0, "unit_actions": 0, "auto_actions": 0, "ap_elixir": 0, "deployments": 0, "spells": 0, "blocked_turns": 0}


static func _board_count(field: BattleField) -> int:
	var count := 0
	for card in field.slots:
		if card != null and card.is_alive(): count += 1
	return count


static func _board_hp(field: BattleField) -> int:
	var hp := 0
	for card in field.slots:
		if card != null and card.is_alive(): hp += card.hp + card.temp_hp
	return hp

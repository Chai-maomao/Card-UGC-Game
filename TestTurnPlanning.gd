extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []
var events := 0


func _ready() -> void:
	EventBus.hp_changed.connect(_on_hp)
	_test_quote_and_resolution()
	_test_face_damage_compensation()
	_test_rounding_refunds_and_gates()
	_test_simulation_copy()
	_test_ordering()
	_test_lethal_and_isolation()
	_test_manual_choice_fallback()
	EventBus.hp_changed.disconnect(_on_hp)
	if failures.is_empty():
		print("TEST_TURN_PLANNING_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_TURN_PLANNING_FAILED: " + failure)
		get_tree().quit(1)


func _game():
	var game = Game.new()
	game.quiet = true
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.player_field.quiet = true
	game.player2_field.quiet = true
	game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	game.battle_config.death_compensation = false
	game.turn_number = 3
	game.first_switch = false
	game.game_rng.seed = 913
	return game


func _card(name: String, atk: int, hp: int = 5, cost: int = 1) -> CardData:
	var card := CardData.new(name, cost, hp, atk)
	card.card_id = name
	card.instance_id = name + "_instance"
	return card


func _test_quote_and_resolution() -> void:
	for player in [1, 2]:
		var game = _game()
		game.current_player = player
		var field: BattleField = game.active_field()
		field.slots[0] = _card("Early", 2)
		field.slots[1] = _card("Next", 4)
		field.slots[2] = _card("Blocked", 9)
		field.actions_taken = 1
		field.action_points = 1
		field.current_mana = 2
		field.temp_mana = 10
		var before := BattleRepro.state_hash(game)
		var event_before := events
		var quote: Dictionary = game.preview_end_turn_attacks()
		_check(quote.total_damage == 6 and quote.points == 1 and quote.mana == 2, "quote must pay cumulative costs after temporary Elixir expires")
		_check(quote.cards_hit.size() == 2 and quote.blocked.size() == 1 and quote.blocked[0].slot == 2, "quote must preserve slot order and blocked attacks")
		_check(BattleRepro.state_hash(game) == before and events == event_before, "quote must not mutate state, RNG, stats or emit events")
		var result: Dictionary = game.end_player_turn()
		_check(result.total_damage == quote.total_damage and field.action_points == 0 and field.current_mana == 0 and field.actions_taken == 3, "actual resolution must match the quote for either player")


func _test_face_damage_compensation() -> void:
	for player in [1, 2]:
		for scenario in [[true, null, 2], [true, 3, 6], [false, 3, 0]]:
			var game = _game()
			game.current_player = player
			game.battle_config.face_damage_compensation = scenario[0]
			if scenario[1] != null:
				game.battle_config.face_damage_compensation_mana = scenario[1]
			var attacker: BattleField = game.active_field()
			var defender: BattleField = game.opponent_field()
			attacker.action_points = 10
			attacker.slots[0] = _card("First", 2)
			attacker.slots[1] = _card("Second", 5)
			attacker.slots[2] = _card("Already acted", 8)
			attacker.slots[2].has_acted = true
			attacker.slots[3] = _card("Zero damage", 0)
			_check(MatchAgreement.valid_config(game.battle_config), "match rules must accept both the legacy and custom rates")
			var rules_text := BattleRulesHelp.description(game)
			var rate: int = 1 if scenario[1] == null else scenario[1]
			_check(rules_text.contains(Locale.t("help.face_damage_compensation_rate", [rate])) == scenario[0],
				"battle help must show the actual rate when compensation is enabled")
			var result: Dictionary = game.end_player_turn()
			_check(result.cards_hit.size() == 3 and result.total_damage == 7 and defender.temp_mana == scenario[2] and attacker.temp_mana == 0,
				"only attacks that took hero health should grant Temporary Elixir to the defender")
			game.start_new_turn()
			_check(game.active_field() == defender and defender.temp_mana == scenario[2], "compensation must carry into the defender's turn")
			game.end_player_turn()
			_check(defender.temp_mana == 0, "unused compensation must expire at the end of the defender's turn")
	var invalid := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	for invalid_amount in [0, 11, 1.5, "3"]:
		invalid.face_damage_compensation_mana = invalid_amount
		_check(not MatchAgreement.valid_config(invalid), "match rules must reject invalid compensation amounts")


func _test_rounding_refunds_and_gates() -> void:
	var game = _game()
	game.player_field.actions_taken = 1
	game.player_field.action_points = 0
	game.player_field.current_mana = 0
	game.battle_config.action_mana_factor = 1.5
	game.player_field.slots[0] = _card("Refunded", 3)
	game.player_field.slots[0].status_effects.append({"buff_id": SkillEngine.BUFF_MANA_REFUND, "owner": 1, "value": 2, "duration": 1})
	var quote: Dictionary = game.preview_end_turn_attacks()
	_check(quote.mana == 2 and quote.total_damage == 3 and not quote.conditional, "owned refund must fund rounded action price")
	_check(game.end_player_turn().total_damage == quote.total_damage, "refund quote must agree with resolution")
	game = _game()
	game.player_field.slots[0] = _card("Used", 8)
	game.player_field.slots[0].has_acted = true
	game.player_field.slots[1] = _card("Silenced", 9)
	game.player_field.slots[1].status_effects.append({"buff_id": SkillEngine.BUFF_SILENCE, "value": 1, "duration": 2, "owner": 1})
	_check(game.preview_end_turn_attacks().total_damage == 9, "silence must allow automatic basic attacks")
	game.player_field.slots[1].apply_buff(SkillEngine.BUFF_STUN, 1, 1, 1)
	_check(game.preview_end_turn_attacks().cards_hit.is_empty(), "stun must prevent automatic basic attacks")
	game.player_field.slots[1].attack_ignores_silence = true
	_check(game.preview_end_turn_attacks().total_damage == 0, "legacy silence bypass must not bypass stun")
	game.turn_number = 1
	_check(game.preview_end_turn_attacks().reason == "first_turn", "first-turn gate must be explained")
	game.turn_number = 2
	game.player2_field.slots[0] = _card("Guard", 1)
	_check(game.preview_end_turn_attacks().reason == "defended", "surviving defender must block automatic attacks")
	game.player_field.slots[0].skills = [{"trigger": SkillEngine.TRIGGER_ON_TURN_END, "effects": []}]
	_check(game.preview_end_turn_attacks().conditional, "turn-end skill must mark forecast conditional")
	game.player_field.slots[0].skills.clear()
	game.player_field.slots[0].status_effects.append({"buff_id": SkillEngine.BUFF_POISON, "owner": 2, "value": 5, "duration": 1})
	_check(game.preview_end_turn_attacks().conditional, "pending status tick must mark forecast conditional")


func _test_ordering() -> void:
	var game = _game()
	game.player_field.slots[0] = _card("Small", 1)
	game.player_field.slots[1] = _card("Strong", 6, 10, 4)
	game.player2_field.slots[0] = _card("Weak point", 0, 1)
	game.player2_field.slots[1] = _card("Threat", 8, 10, 5)
	game.player_field.current_mana = 2
	game.player_field.actions_taken = 2
	game.player_field.action_points = 2
	var before := BattleRepro.state_hash(game)
	var choice := BattleAiPlanner.choose_action(game, "hard", game.game_rng)
	_check(choice.get("type") == "attack" and choice.get("source_slot") == 0 and choice.get("target_slot") == 0, "hard AI must use cheap kill refund before expensive follow-up: " + str(choice))
	_check(int(choice.get("search_nodes", 0)) > 0 and int(choice.get("search_nodes", 999)) <= BattleSearch.MAX_NODES, "AP planning must remain bounded")
	_check(BattleRepro.state_hash(game) == before, "ordering search must not mutate live state")
	_check(BattleRepro.apply_action(game, choice).ok, "planned first action must be legal")
	game.cleanup_deaths()
	var next := BattleAiPlanner.choose_action(game, "hard", game.game_rng)
	_check(next.get("type") == "attack" and next.get("source_slot") == 1 and next.get("target_slot") == 1, "refund must make planned second action affordable: " + str(next))


func _test_simulation_copy() -> void:
	var game = _game()
	game.player_field.slots[0] = _card("Host", 3)
	game.player_field.slots[0].status_effects = [{"buff_id": SkillEngine.BUFF_ATK_BOOST, "value": 2, "duration": 3, "owner": 1}]
	game.player_field.slots[0].parasite_cards = [_card("Attached", 2)]
	game.player_hand = [_card("Hand", 1)]
	game.shared_deck = [_card("Deck", 1)]
	game.shared_discard = [_card("Discard", 1)]
	game.player_field.temp_mana = 2
	game.player_field.actions_taken = 3
	game.player_field.action_points = 2
	game.stats[1].mana_spent = 9
	game.game_rng.randi()
	var before := BattleRepro.state_hash(game)
	var copy: RefCounted = game.copy_for_simulation()
	_check(BattleRepro.state_hash(copy) == before, "in-memory simulation copy must match the serialized state exactly")
	copy.player_field.slots[0].status_effects[0].value = 99
	copy.player_field.slots[0].parasite_cards[0].hp = 1
	copy.player_hand[0].hp = 1
	copy.shared_deck.clear()
	copy.shared_discard[0].cost = 9
	copy.battle_config.action_base = 1
	copy.stats[1].mana_spent = 1
	copy.game_rng.randi()
	_check(BattleRepro.state_hash(game) == before, "simulation copy must isolate nested cards, resources, RNG and configuration")


func _test_lethal_and_isolation() -> void:
	var game = _game()
	game.player_field.slots[0] = _card("Finisher", 5)
	game.player_field.slots[0].skills = [{"trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 20}]}]
	game.player_field.slots[1] = _card("Other", 2)
	game.player_field.action_points = 0
	game.player_field.current_mana = 1
	game.player2_field.player_hp = 7
	game.player_hand = [_card("Costly deployment", 9, 5, 1)]
	var before := BattleRepro.state_hash(game)
	var event_before := events
	var preferences := PlayerData.battle_config.duplicate(true)
	for level in ["hard", "normal"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var choice := BattleAiPlanner.choose_action(game, level, rng)
		_check(choice.type == "end_turn", "AI must preserve automatic lethal instead of healing or spending its payment")
	_check(BattleRepro.state_hash(game) == before and events == event_before and PlayerData.battle_config == preferences, "planning must preserve events, player preferences and authoritative state")
	EventBus.set_block_signals(true)
	BattleAiPlanner.choose_action(game, "hard", game.game_rng)
	_check(EventBus.is_blocking_signals(), "nested signal suppression must be restored")
	EventBus.set_block_signals(false)


func _test_manual_choice_fallback() -> void:
	var game = _game()
	game.player_field.slots[0] = _card("Choice", 2)
	game.player_field.slots[0].skills = [{"trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"effect": "view_deck_select", "target": SkillEngine.TARGET_SELF, "value": 1}, {"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1}]}]
	game.player_field.slots[1] = _card("Other", 1)
	game.player_field.action_points = 8
	game.player2_field.slots[0] = _card("Victim", 1, 1)
	var choice := BattleAiPlanner.choose_action(game, "hard", game.game_rng)
	_check(choice.type == "attack", "unsupported manual-choice UGC must fall back to a legal heuristic action instead of ending the turn")


func _on_hp(_card, _delta, _hp) -> void:
	events += 1


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

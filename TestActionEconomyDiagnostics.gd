extends Node

const Analyzer = preload("res://ActionEconomyAnalyzer.gd")
var failures: Array[String] = []


func _ready() -> void:
	_test_quotes()
	_test_trigger_notes()
	_test_multiple_active_skills()
	_test_stun_and_end_metrics()
	if failures.is_empty():
		print("TEST_ACTION_ECONOMY_DIAGNOSTICS_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_ACTION_ECONOMY_DIAGNOSTICS_FAILED: " + failure)
		get_tree().quit(1)


func _game() -> RefCounted:
	return HeadlessBattleSimulator._create_game([], [], 618)


func _test_quotes() -> void:
	var preference := PlayerData.battle_config.duplicate(true)
	var game := _game()
	var before := BattleRepro.state_hash(game)
	for config in [PlayerData.DEFAULT_BATTLE_CONFIG, {"action_base": 3, "action_mana_factor": 1.5}, {}]:
		game.battle_config = config.duplicate(true)
		for number in [1, 2, 5, 8]:
			for points in [0, 2, 9]:
				for mana in [0, 1, 10]:
					game.player_field.action_points = points
					game.player_field.actions_taken = number - 1
					game.player_field.current_mana = mana
					_check(Analyzer.quote(number, points, mana, config) == game.next_action_payment(), "creator quote must match authoritative payment")
	var rounded := Analyzer.quote(5, 1, 4, {"action_base": 3, "action_mana_factor": 1.5})
	_check(rounded.mana == 5 and not rounded.ok, "shortage must round up using the configured multiplier")
	_check(Analyzer.quote(1, 0, 0, PlayerData.DEFAULT_BATTLE_CONFIG).ok, "first unit action must be free")
	_check(Analyzer.quote(9, 0, 0, {}).cost == 0, "legacy rules must remain free")
	var independent := _game()
	_check(BattleRepro.state_hash(independent) == before and PlayerData.battle_config == preference, "quote must preserve independent gameplay RNG and preferences")


func _test_trigger_notes() -> void:
	var card := CardData.new("Resource", 2, 5, 1, [{"trigger": "on_activate", "effects": [{"effect": "__if_else__", "then_effects": [{"effect": "gain_mana", "value_expr": {"kind": "var", "var_id": "hand_count"}}], "else_effects": [{"effect": "execute", "value": 3}]}]}])
	var before := PlayerData.serialize_card(card)
	var notes := Analyzer.inspect(card)
	_check(_has(notes, "economy.active") and _has(notes, "economy.mana_after_payment") and not _has(notes, "economy.conditional") and _has(notes, "economy.kill_refund"), "nested effects retain resource rules without an uncertainty disclaimer")
	_check(PlayerData.serialize_card(card) == before, "inspection must not mutate card definitions")
	var deploy := {"trigger": "on_summon", "effects": [{"effect": "shield", "target": "self", "value": 1}]}
	var draft := {"name": "Deploy", "card_type": "minion", "hp": 4, "cost": 2, "skill1": deploy, "skill2": deploy}
	_check(not _has(CardUsabilityAnalyzer.analyze(draft).issues, "usability.action_competition"), "two deployment triggers must not be classified as competing unit actions")
	draft.skill1 = {"trigger": "on_activate", "effects": []}
	draft.skill2 = draft.skill1.duplicate(true)
	_check(_has(CardUsabilityAnalyzer.analyze(draft).issues, "usability.action_competition"), "multiple active skills must explain the shared escalating budget")
	card.card_type = "spell"
	_check(_has(Analyzer.inspect(card), "economy.spell") and not _has(Analyzer.inspect(card), "economy.active"), "spell casting must not be labeled a unit action")
	card.card_type = "parasite"
	_check(_has(Analyzer.inspect(card), "economy.parasite"), "parasite attachment needs host-action distinction")


func _test_multiple_active_skills() -> void:
	var game := _game()
	game.turn_number = 2
	game.player_field.current_mana = 0
	game.player_field.action_points = 2
	game.player_field.slots[0] = CardData.new("Relay", 1, 5, 1, [
		{"trigger": "on_activate", "effects": [{"effect": "gain_mana", "target": "self", "value": 2}]},
		{"trigger": "on_activate", "effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 3}]},
	])
	game.player2_field.slots[0] = CardData.new("Target", 1, 3, 1)
	BattlePosition.ensure_ids(game)
	var record := BattleRepro.begin(game)
	_check(BattleRepro.execute_and_record(game, record, {"type": "activate", "slot": 0, "skill_index": 0}).ok, "first active skill must resolve")
	var candidates := BattleAiPlanner.generate_legal_actions(game)
	_check(candidates.any(func(action): return action.type == "activate" and int(action.skill_index) == 1), "AI must keep an unused distinct active skill after the first skill")
	_check(not candidates.any(func(action): return action.type == "attack" or (action.type == "activate" and int(action.skill_index) == 0)), "used skill and normal attack must remain unavailable")
	_check(BattleRepro.execute_and_record(game, record, {"type": "activate", "slot": 0, "skill_index": 1, "target_slot": 0, "target_player": 2}).ok, "second distinct skill must use the same real rule as the player")
	_check(game.player_field.actions_taken == 2 and game.player_field.action_points == 1 and game.player_field.current_mana == 2 and game.player2_field.slots[0].hp == 0, "second skill must pay increasing AP; skill kill must not automatically refund mana")
	_check(BattleRepro.verify(record).ok, "multi-skill sequence must replay exactly")
	var used := BattleRepro.state_hash(game)
	_check(not BattleRepro.apply_action(game, {"type": "activate", "slot": 0, "skill_index": 0}).ok and BattleRepro.state_hash(game) == used, "same skill cannot resolve twice or charge on rejection")


func _test_stun_and_end_metrics() -> void:
	var game := _game()
	game.player_field.slots[0] = CardData.new("Stunned", 1, 5, 2, [{"trigger": "on_activate", "effects": [{"effect": "gain_mana", "target": "self", "value": 2}]}])
	game.player_field.slots[0].apply_buff(SkillEngine.BUFF_STUN, 1, 1, 1)
	game.current_player = 2
	game.start_new_turn()
	var before := BattleRepro.state_hash(game)
	_check(not game.trigger_activate_skills(0, -1, 0), "consumed stun must block active skills through the real engine")
	_check(not BattleAiPlanner.generate_legal_actions(game).any(func(action): return action.type == "activate"), "AI must not bypass consumed stun")
	_check(BattleRepro.state_hash(game) == before, "rejected stunned action must be read-only")
	game = _game()
	PracticeChallenges.configure(game, "action_finish")
	BattleRepro.apply_action(game, {"type": "discard", "location": "field", "index": 0})
	var result := BattleRepro.apply_action(game, {"type": "end_turn"})
	_check(result.end_turn_result.unused_mana == 1 and game.player2_field.player_hp == 1, "remaining mana must be measured after temp expiry and automatic attack cost, before opponent income")


func _has(notes: Array, key: String) -> bool:
	return notes.any(func(note): return str(note.get("key", "")) == key)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

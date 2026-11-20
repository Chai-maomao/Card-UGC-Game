extends Node

const BattleScene = preload("res://Main.tscn")
var failures: Array[String] = []


func _ready() -> void:
	var old_mode: String = PlayerData.battle_mode
	PlayerData.battle_mode = "local"
	NetworkManager.close_connection()
	for player in [1, 2]:
		_test_readiness(player)
	PlayerData.battle_mode = old_mode
	if failures.is_empty():
		print("TEST_UNIT_ACTION_READINESS_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_UNIT_ACTION_READINESS_FAILED: " + failure)
		get_tree().quit(1)


func _active(effect: String = "gain_attack", target: String = "self") -> Dictionary:
	return {"trigger": "on_activate", "effects": [{"effect": effect, "target": target, "target_side": "enemy" if target == "target_single" else "ally", "value": 1}]}


func _test_readiness(player: int) -> void:
	var battle := BattleScene.instantiate()
	var game := HeadlessBattleSimulator._create_game([], [], 810, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.current_player = player
	game.turn_number = 1
	battle.game = game
	var field: BattleField = game.active_field()
	field.action_points = 3
	field.current_mana = 3
	var passive := CardData.new("Passive only", 0, 6, 2, [{"trigger": "on_damaged", "effects": [{"effect": "gain_attack", "target": "self", "value": 1}]}])
	field.slots[0] = passive
	_check(not battle._card_can_act(passive), "a passive must not create an actionable glow when first-turn attacks are blocked")
	var enemy_skill := CardData.new("First-turn blocked", 0, 6, 2, [_active("damage", "target_single")])
	field.slots[0] = enemy_skill
	_check(not battle._card_can_act(enemy_skill), "enemy HP skill blocked on round one must not produce a glow")
	var relay := CardData.new("Relay", 0, 6, 2, [_active(), _active()])
	field.slots[0] = relay
	_check(battle._card_can_act(relay), "a legal self-buff must be actionable on round one")
	game.turn_number = 2
	var record := BattleRepro.begin(game)
	_check(BattleRepro.execute_and_record(game, record, {"type": "activate", "slot": 0, "skill_index": 0}).ok, "first skill fixture must execute")
	var before := BattleRepro.state_hash(game)
	_check(battle._card_can_act(relay), "a distinct unused active must retain its actionable glow after the first skill")
	_check(game.unit_action_readiness(0) == {"attack": false, "skills": [1]}, "readiness must expose only the unused distinct active skill")
	var simulation: RefCounted = game.copy_for_simulation()
	_check(simulation.unit_action_readiness(0) == game.unit_action_readiness(0), "simulation readiness must preserve the same pending skill")
	_check(BattleRepro.state_hash(game) == before, "readiness query must preserve state, stats, revision and RNG")
	var second := {"type": "activate", "slot": 0, "skill_index": 1}
	_check(BattleRepro.execute_and_record(game, record, second).ok and BattleRepro.apply_action(simulation, second).ok, "the glowing second active must actually execute")
	_check(BattleRepro.state_hash(game) == BattleRepro.state_hash(simulation) and BattleRepro.verify(record).ok, "shared readiness must preserve copied execution and complete replay")
	_check(not battle._card_can_act(relay), "all used skills plus spent normal attack must remove the glow")
	relay.skills_used.clear()
	relay.skills[0].max_uses = 1
	relay.skills[1].max_uses = 1
	_check(not battle._card_can_act(relay), "lifetime limits must remain respected after clearing per-turn flags")
	game.turn_number = 1
	game.allow_first_turn_attacks = true
	field.slots[0] = CardData.new("Tutorial attacker", 0, 6, 2)
	_check(battle._card_can_act(field.slots[0]), "explicit first-turn attack allowance must produce a glow")
	game.turn_number = 2
	game.allow_first_turn_attacks = false
	field.slots[0] = relay
	relay.skills = [_active()]
	relay.skills_used_count.clear()
	relay.has_acted = false
	relay.has_attacked = false
	relay.apply_buff(SkillEngine.BUFF_SILENCE, 1, 1, player)
	_check(battle._card_can_act(relay), "silence must allow ordinary attacks")
	relay.attack_ignores_silence = true
	_check(battle._card_can_act(relay), "an explicit silence-ignoring normal attack must remain actionable")
	relay.has_acted = true
	_check(not battle._card_can_act(relay), "silence-ignoring attack must not make a silenced active skill usable after acting")
	relay.status_effects.clear()
	relay.has_attacked = true
	_check(not battle._card_can_act(relay), "consumed stun/attack lock must block further active skills")
	relay.has_attacked = false
	field.actions_taken = 3
	field.action_points = 1
	field.current_mana = 2
	field.temp_mana = 0
	game.battle_config.action_mana_factor = 1.5
	_check(not battle._card_can_act(relay), "partial AP and rounded Elixir shortage must be considered")
	field.temp_mana = 1
	_check(battle._card_can_act(relay), "temporary Elixir can make the exact shortage payable")
	game.is_player_turn = false
	_check(not battle._card_can_act(relay), "turn transition must suppress readiness")
	game.is_player_turn = true
	battle.match_paused = true
	_check(not battle._card_can_act(relay), "paused matches must suppress readiness")
	battle.free()


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

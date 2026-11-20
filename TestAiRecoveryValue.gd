extends Node

var failures: Array[String] = []
var events := 0


func _ready() -> void:
	EventBus.hp_changed.connect(_on_hp)
	for player in [1, 2]:
		_test_mana(player)
		_test_heal(player)
		_test_boundaries(player)
	EventBus.hp_changed.disconnect(_on_hp)
	if failures.is_empty():
		print("TEST_AI_RECOVERY_VALUE_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_AI_RECOVERY_VALUE_FAILED: " + failure)
		get_tree().quit(1)


func _game(player: int, effect: String, value: int = 5) -> RefCounted:
	var game := HeadlessBattleSimulator._create_game([], [], 719, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.current_player = player
	game.turn_number = 2
	game.active_field().action_points = 8
	game.active_field().current_mana = 10
	game.active_field().slots[0] = CardData.new("Recovery", 1, 6, 1, [{"trigger": "on_activate", "probability": 100, "effects": [{"effect": effect, "target": "self", "value": value}]}])
	game.opponent_field().slots[0] = CardData.new("Guard", 0, 9, 0)
	BattlePosition.ensure_ids(game)
	return game


func _skill_score(game: RefCounted, action: Dictionary = {}) -> Dictionary:
	var command := {"type": "activate", "slot": 0, "skill_index": 0}
	command.merge(action, true)
	var before := BattleRepro.state_hash(game)
	var previous_events := events
	var result := BattleAiPlanner.score_action(game, command)
	_check(before == BattleRepro.state_hash(game) and events == previous_events, "scoring must preserve live state, RNG, counters and events")
	return result


func _pick(game: RefCounted) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return BattleAiPlanner.choose_action(game, "normal", rng)


func _resolve(game: RefCounted, action: Dictionary) -> void:
	var record := BattlePosition.capture(game)
	_check(BattleRepro.execute_and_record(game, record, action).ok, "reference action must be legal")
	var restored := BattlePosition.read(BattleRepro.export_json(record))
	_check(restored.ok and BattleRepro.state_hash(restored.game) == BattleRepro.state_hash(game), "actual recovery must survive full JSON replay")


func _test_mana(player: int) -> void:
	var game := _game(player, "gain_mana")
	_check(_skill_score(game).score < BattleAiPlanner.score_action(game, {"type": "end_turn"}).score, "full Elixir must not be rewarded as income")
	_check(_pick(game).type == "attack", "normal AI must attack instead of wasting full-cap recovery: " + str(_pick(game)))
	_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0})
	_check(game.active_field().current_mana == 10, "full-cap reference must actually gain zero")
	game = _game(player, "gain_mana")
	game.active_field().current_mana = 9
	_check(is_equal_approx(_skill_score(game).score, 3.0), "one available Elixir slot must value one point, not five")
	_check(_pick(game).type == "activate", "useful recovery must remain available to normal AI")
	_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0})
	_check(game.active_field().current_mana == 10, "partial-cap recovery must actually gain one")
	for temporary in [0, 2, 3]:
		game = _game(player, "gain_mana")
		game.active_field().actions_taken = 3
		game.active_field().action_points = 0
		game.active_field().temp_mana = temporary
		var gained := maxi(0, 3 - temporary)
		var expected := gained * 3.0 if gained > 0 else -8.0
		_check(is_equal_approx(_skill_score(game).score, expected - 15.0), "recovery must count permanent space only after temporary-first action payment")
		_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0})
		_check(game.active_field().current_mana == 10 and game.active_field().temp_mana == maxi(0, temporary - 3), "payment/recovery reference mismatch")
	for temporary in [0, 3]:
		game = _game(player, "gain_mana")
		var spell := CardData.new("Supply spell", 3, 0, 0, [{"trigger": "on_cast", "effects": [{"effect": "gain_mana", "target": "self", "value": 5}]}])
		spell.card_type = "spell"
		game.active_hand().append(spell)
		game.active_field().temp_mana = temporary
		BattlePosition.ensure_ids(game)
		var action := {"type": "cast", "hand_index": 0, "skill_index": 0}
		var score := BattleAiPlanner.score_action(game, action).score as float
		_check(is_equal_approx(score, 8.25 if temporary == 0 else -8.75), "spell cost must open permanent space only when not paid by temporary Elixir")
		_resolve(game, action)
		_check(game.active_field().current_mana == 10, "spell recovery reference must end at cap")


func _test_heal(player: int) -> void:
	var game := _game(player, "heal")
	_check(_skill_score(game).score < -4.0 and _pick(game).type == "attack", "full-health recovery must not replace a useful attack")
	_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0})
	_check(game.active_field().slots[0].hp == 6, "full-health reference must gain zero")
	game = _game(player, "heal")
	game.active_field().slots[0].hp = 5
	_check(is_equal_approx(_skill_score(game).score, 2.0), "self overheal must count only missing health")
	_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0})
	_check(game.active_field().slots[0].hp == 6, "partial self heal must actually gain one")
	game = _game(player, "heal")
	game.active_field().slots[0].skills[0].effects[0].target = "target_single"
	game.active_field().slots[0].skills[0].effects[0].target_side = "ally"
	game.active_field().slots[1] = CardData.new("Injured", 0, 6, 0)
	game.active_field().slots[1].hp = 5
	game.active_field().slots[2] = CardData.new("Full carry", 0, 6, 8)
	game.active_field().slots[1].has_acted = true
	game.active_field().slots[2].has_acted = true
	var injured := {"target_slot": 1, "target_player": player}
	var full := {"target_slot": 2, "target_player": player}
	_check(is_equal_approx(_skill_score(game, injured).score, 5.0) and _skill_score(game, full).score < -4.0, "directed healing must not reward a full-health carry")
	_check(_pick(game).target_slot == 1 and _pick(game).type == "activate", "normal healer must choose actual missing health")
	BattlePosition.ensure_ids(game)
	_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0, "target_slot": 1, "target_player": player})
	_check(game.active_field().slots[1].hp == 6, "directed heal reference must actually gain one")


func _test_boundaries(player: int) -> void:
	for effect in ["gain_mana", "heal"]:
		var waiting := _game(player, effect)
		waiting.opponent_field().slots.fill(null)
		for level in ["normal", "hard"]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1
			_check(BattleAiPlanner.choose_action(waiting, level, rng).type == "end_turn", "AI must preserve its automatic attack rather than consume a known no-op")
	var game := _game(player, "heal")
	game.active_field().slots[0].skills.append({"trigger": "on_healed", "max_uses": 1, "effects": [{"effect": "gain_attack", "target": "self", "value": 2}]})
	_check(_skill_score(game).score > 0.0, "full-health on_healed reactions must retain conservative valuation")
	_resolve(game, {"type": "activate", "slot": 0, "skill_index": 0})
	_check(game.active_field().slots[0].field_atk_bonus == 2, "full-health healing must still trigger actual growth")
	for extra in [{"value_var": "mana_current"}, {"value_expr": {"kind": "num", "value": 5}}, {"value_min": 1, "value_max": 5}, {"condition_type": "mana_current", "condition_op": ">=", "condition_value": 1}, {"probability": 75}, {"random_count": 1}]:
		game = _game(player, "gain_mana")
		game.active_field().slots[0].skills[0].effects[0].merge(extra, true)
		_check(_skill_score(game).score > 0.0, "uncertain/dynamic effects must not be classified as a proven no-op: " + str(extra))
	for extra in [{"op": ">=", "lhs": {"kind": "num", "value": 0}, "rhs": {"kind": "num", "value": 1}}, {"logic": "not", "child": {"condition_type": "mana_current", "condition_value": 1}}]:
		game = _game(player, "gain_mana")
		game.active_field().slots[0].skills[0].effects[0].merge(extra, true)
		_check(_skill_score(game).score > 0.0, "legacy inline boolean conditions must retain fallback estimation")
	game = _game(player, "gain_mana")
	game.active_field().slots[0].skills = UgcBenchmarkPool.card("conditional").skills.duplicate(true)
	_check(not _skill_score(game).factors.has("no_immediate_effect"), "nested conditional UGC must retain fallback estimation")
	game = _game(player, "gain_mana")
	game.active_field().slots[0].skills[0].effects.append({"effect": "gain_attack", "target": "self", "value": 2})
	_check(_skill_score(game).score > 0.0 and not _skill_score(game).factors.has("no_immediate_effect"), "a capped recovery followed by useful growth must retain mixed-effect valuation")
	game = _game(player, "heal")
	game.active_field().slots[0] = UgcBenchmarkPool.card("grower")
	BattlePosition.ensure_ids(game)
	_check(_pick(game).type == "attack", "zero-damage attacks with growth must remain legal and chosen")
	_resolve(game, {"type": "attack", "source_slot": 0, "target_slot": 0})
	_check(game.active_field().slots[0].field_atk_bonus == 2, "zero-damage reference must actually trigger growth")


func _on_hp(_card, _delta, _hp) -> void:
	events += 1


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

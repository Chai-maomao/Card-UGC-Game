extends Node

var failures: Array[String] = []
var ui_events := 0


func _ready() -> void:
	EventBus.hp_changed.connect(_on_hp)
	var preferences := PlayerData.battle_config.duplicate(true)
	var library_hash := FileAccess.get_sha256("user://card_library.json")
	for player in [1, 2]:
		_test_recovery(player)
		_test_growth(player)
	_test_rng_and_rejections()
	EventBus.hp_changed.disconnect(_on_hp)
	_check(PlayerData.battle_config == preferences and FileAccess.get_sha256("user://card_library.json") == library_hash, "tracing must preserve player rules and persisted collection")
	if failures.is_empty():
		print("TEST_AI_DECISION_TRACE_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_AI_DECISION_TRACE_FAILED: " + failure)
		get_tree().quit(1)


func _game(player: int, effect: String) -> RefCounted:
	var game := HeadlessBattleSimulator._create_game([], [], 1921, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.turn_number = 2
	game.current_player = player
	game.active_field().action_points = 1
	game.active_field().current_mana = 10
	game.active_field().slots[0] = CardData.new("Recovery", 1, 6, 1, [{"trigger": "on_activate", "effects": [{"effect": effect, "target": "self", "value": 5}]}])
	game.opponent_field().slots[0] = CardData.new("Guard", 0, 9, 0)
	BattlePosition.ensure_ids(game)
	return game


func _append(game: RefCounted, record: Dictionary, action: Dictionary) -> void:
	_check(BattleRepro.execute_and_record(game, record, action).ok, "recorded fixture must be legal")
	_check(BattleRepro.execute_and_record(game, record, {"type": "settle"}).ok, "settlement fixture must be legal")


func _trace(game: RefCounted, record: Dictionary) -> Dictionary:
	var hash_before := BattleRepro.state_hash(game)
	var record_before := BattleRepro.canonical_text(record)
	var events_before := ui_events
	var old_blocked := EventBus.is_blocking_signals()
	for blocked in [false, true]:
		EventBus.set_block_signals(blocked)
		var result := AiDecisionTrace.build(record)
		_check(result.ok and EventBus.is_blocking_signals() == blocked, "valid trace must verify and restore nested event suppression")
		_check(ui_events == events_before and BattleRepro.state_hash(game) == hash_before and BattleRepro.canonical_text(record) == record_before, "trace must not mutate the live game, input record or emit UI events")
	EventBus.set_block_signals(old_blocked)
	var result := AiDecisionTrace.build(record)
	_check(result.ok and result.report.final_hash == hash_before and result.report.summary.recorded_steps == record.actions.size(), "trace must match every command hash through the final recorded state")
	_check(BattleRepro.canonical_text(result.report) == BattleRepro.canonical_text(AiDecisionTrace.build(record).report), "repeated trace must be deterministic")
	return result.report


func _test_recovery(player: int) -> void:
	for effect in ["gain_mana", "heal"]:
		var game := _game(player, effect)
		var record := BattlePosition.capture(game)
		_append(game, record, {"type": "activate", "slot": 0, "skill_index": 0, "score": 99.0, "explanation": ["recorded_reason"]})
		var report := _trace(game, record)
		_check(report.summary.decisions == 1 and report.summary.activations_without_observed_payload == 1, "full recovery must be observable as an unchanged payload even after consuming a use")
		var row: Dictionary = report.rows[0]
		_check(row.step_start == 1 and row.step_end == 2 and row.player == player, "settlement must be grouped with its actual acting player")
		_check(row.recorded_score == 99.0 and row.recorded_factors == ["recorded_reason"] and row.current_assessment.score == -8.0, "recorded choice reasons must stay separate from current heuristic reassessment")
		_check(row.events.any(func(event): return event.get("kind") == "payment" and event.action == "activate") and row.source.instance_id == game.active_field().slots[0].instance_id, "trace must retain actual payment events and source instance identity")
		game = _game(player, effect)
		if effect == "gain_mana": game.active_field().current_mana = 9
		else: game.active_field().slots[0].hp = 5
		record = BattlePosition.capture(game)
		_append(game, record, {"type": "activate", "slot": 0, "skill_index": 0})
		report = _trace(game, record)
		_check(report.summary.activations_without_observed_payload == 0 and report.rows[0].recorded_score == null, "real income/healing must not be flagged and manual input must not invent a recorded score")
		_check(report.rows[0].events.any(func(event): return event.get("kind") == ("mana_gained" if effect == "gain_mana" else "healing") and event.get("amount") == 1), "one actual recovered point must survive event serialization")


func _test_growth(player: int) -> void:
	var game := _game(player, "heal")
	game.active_field().slots[0].skills.append({"trigger": "on_healed", "max_uses": 1, "effects": [{"effect": "gain_attack", "target": "self", "value": 2}]})
	var record := BattlePosition.capture(game)
	_append(game, record, {"type": "activate", "slot": 0, "skill_index": 0})
	var report := _trace(game, record)
	_check(report.summary.activations_without_observed_payload == 0 and report.rows[0].payload_changed, "full-health healing that triggers growth must count as a visible payload change")
	_check(report.rows[0].after.board[str(player)][0].field_atk_bonus == 2, "trace must expose actual growth rather than only damage metrics")
	game = _game(player, "gain_mana")
	game.active_field().slots[0].skills[0].effects[0].value = -2
	record = BattlePosition.capture(game)
	_append(game, record, {"type": "activate", "slot": 0, "skill_index": 0})
	report = _trace(game, record)
	_check(report.summary.activations_without_observed_payload == 0, "resource loss is an observed effect, not evidence of a no-op")


func _test_rng_and_rejections() -> void:
	var game := _game(1, "heal")
	game.active_field().slots[0] = UgcBenchmarkPool.card("random")
	BattlePosition.ensure_ids(game)
	var record := BattlePosition.capture(game)
	game.game_rng.randf()
	_append(game, record, {"type": "activate", "slot": 0, "skill_index": 0, "target_slot": -1})
	_append(game, record, {"type": "end_turn"})
	var report := _trace(game, record)
	_check(report.summary.decisions == 2 and report.summary.player_turns == 1, "end-turn must use its ending actor, not the next player's resources")
	var original_block := EventBus.is_blocking_signals()
	for blocked in [false, true]:
		EventBus.set_block_signals(blocked)
		var invalid := record.duplicate(true)
		invalid.state_hashes[1] = "tampered"
		_check(not AiDecisionTrace.build(invalid).ok and EventBus.is_blocking_signals() == blocked, "tampered replay must be rejected without leaking signal suppression")
		invalid = record.duplicate(true)
		invalid.actions.resize(BattlePosition.MAX_RECORDED_ACTIONS + 1)
		_check(not AiDecisionTrace.build(invalid).ok and EventBus.is_blocking_signals() == blocked, "oversized command history must be rejected")
	EventBus.set_block_signals(original_block)


func _on_hp(_card, _delta, _hp) -> void:
	ui_events += 1


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

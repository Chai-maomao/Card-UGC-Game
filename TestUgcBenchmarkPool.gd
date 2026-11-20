extends Node

var failures: Array[String] = []
const EXPECTED_POOL_SHA256 := "aa07cbda4ded294fbb9da0fb86cada3f815200d458754b67a1b27db3605ba0d2"


func _ready() -> void:
	var library_hash := FileAccess.get_sha256("user://card_library.json")
	var preferences := PlayerData.battle_config.duplicate(true)
	_test_catalog()
	for player in [1, 2]:
		for blocked in [false, true]:
			var old_blocked := EventBus.is_blocking_signals()
			EventBus.set_block_signals(blocked)
			_test_relay_reaction(player)
			_test_conditions(player)
			_test_spell_and_timed(player)
			EventBus.set_block_signals(old_blocked)
	_test_random_and_legal_actions()
	_test_natural_continuation()
	_check(PlayerData.battle_config == preferences and FileAccess.get_sha256("user://card_library.json") == library_hash, "benchmark must preserve user rules and persisted collection")
	if failures.is_empty():
		print("TEST_UGC_BENCHMARK_POOL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_UGC_BENCHMARK_POOL_FAILED: " + failure)
		get_tree().quit(1)


func _test_catalog() -> void:
	var manifest := UgcBenchmarkPool.manifest()
	print("UGC_POOL_SHA256=" + manifest.sha256)
	_check(manifest.id == "ugc-v1" and manifest.sha256 == EXPECTED_POOL_SHA256, "changing frozen content must require a new benchmark version")
	var first := UgcBenchmarkPool.deck()
	var second := UgcBenchmarkPool.deck()
	_check(first.size() == 16 and manifest.definitions.size() == 8, "frozen pool must contain eight archetypes with two copies")
	first[0].skills[0].effects[0].value = 999
	first[0].skills_used_count[0] = 2
	_check(second[0].skills[0].effects[0].value == 2 and first[8].skills[0].effects[0].value == 2 and second[0].skills_used_count.is_empty(), "factories and repeated copies must not share mutable UGC or counters")
	manifest.definitions[0].skills.clear()
	_check(UgcBenchmarkPool.manifest().definitions[0].skills.size() == 2, "mutating exported definitions must not change the frozen pool")
	_check(UgcBenchmarkPool.card("unknown") == null and not BattleSearch._has_manual_choice(UgcBenchmarkPool.manifest().definitions), "pool must reject unknown cards and avoid synchronous-search UI choices")


func _game(player: int) -> RefCounted:
	var game := HeadlessBattleSimulator._create_game([], [], 981, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.current_player = player
	game.turn_number = 2
	game.active_field().action_points = 3
	game.active_field().current_mana = 5
	game.opponent_field().current_mana = 0
	game.shared_deck = UgcBenchmarkPool.deck()
	return game


func _start_record(game: RefCounted) -> Dictionary:
	BattlePosition.ensure_ids(game)
	return BattlePosition.capture(game, {"pool": UgcBenchmarkPool.ID, "pool_sha256": UgcBenchmarkPool.manifest().sha256, "origin": "mechanism_fixture"})


func _command(game: RefCounted, record: Dictionary, action: Dictionary) -> void:
	_check(BattleRepro.execute_and_record(game, record, action).ok, "fixture command must be accepted: " + str(action))


func _verify(record: Dictionary, game: RefCounted) -> void:
	var restored := BattlePosition.read(BattleRepro.export_json(record))
	_check(restored.ok and BattleRepro.state_hash(restored.game) == BattleRepro.state_hash(game), "complete JSON replay must preserve payments, RNG, growth and independent counters")


func _test_relay_reaction(player: int) -> void:
	var game := _game(player)
	var relay := UgcBenchmarkPool.card("relay")
	var grower := UgcBenchmarkPool.card("grower")
	var reactor := UgcBenchmarkPool.card("reactor")
	var parasite := UgcBenchmarkPool.card("parasite")
	game.active_field().slots[0] = relay
	game.active_field().slots[1] = grower
	game.opponent_field().slots[3] = reactor
	ParasiteRules.attach(parasite, relay)
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	var record := _start_record(game)
	_command(game, record, {"type": "activate", "slot": 0, "skill_index": 0})
	_check(game.unit_action_readiness(0).skills == [1], "frozen relay must allow its second distinct active after income")
	_command(game, record, {"type": "activate", "slot": 0, "skill_index": 1, "target_slot": 3, "target_player": 3 - player})
	_command(game, record, {"type": "attack", "source_slot": 1, "target_slot": 3})
	_check(reactor.hp == 4 and reactor.skills_used_count.get(0) == 2 and game.opponent_field().current_mana == 2, "two reactions must use receiver resources and independent lifetime limits")
	_check((game.player2_hand if player == 1 else game.player_hand).size() == 2 and relay.hp == 5 and grower.hp == 3 and grower.field_atk_bonus == 2, "zero-damage growth and actual initiator targeting must coexist with parasite healing")
	_check(game.active_field().actions_taken == 3 and game.active_field().action_points == 0 and game.active_field().current_mana == 8, "three actions must pay 0/1/2 AP before actual skill income")
	_check(parasite.skills_used_count == {1: 1} and metrics.by_identity[parasite.card_id].mana_gained == 1 and metrics.by_identity[parasite.card_id].healing == 1, "linked parasite must own its reaction counter and actual contribution")
	_check(metrics.by_identity[relay.card_id].unit_actions == 2 and metrics.by_identity[relay.card_id].action_points_spent == 1 and metrics.by_identity[reactor.card_id].damage == 2, "mechanism ledger must record actual actions, fees and responses")
	_command(game, record, {"type": "end_turn"})
	_command(game, record, {"type": "end_turn"})
	_command(game, record, {"type": "activate", "slot": 0, "skill_index": 1, "target_slot": 3, "target_player": 3 - player})
	_check(reactor.hp == 2 and reactor.skills_used_count.get(0) == 2 and relay.hp == 5 and parasite.skills_used_count == {1: 1}, "exhausted passive and parasite limits must survive actual turn transitions")
	_verify(record, game)


func _test_conditions(player: int) -> void:
	for mana in [2, 4, 5]:
		var game := _game(player)
		var doctor := UgcBenchmarkPool.card("conditional")
		doctor.hp = 1
		game.active_field().slots[0] = doctor
		game.active_field().action_points = 0
		game.active_field().actions_taken = 3
		game.active_field().current_mana = mana
		var record := _start_record(game)
		var before := BattleRepro.state_hash(game)
		var applied := BattleRepro.execute_and_record(game, record, {"type": "activate", "slot": 0, "skill_index": 0})
		if mana == 2:
			_check(not applied.ok and BattleRepro.state_hash(game) == before and doctor.skills_used_count.is_empty(), "unpayable conditional income must not execute or reserve a use")
		else:
			_check(applied.ok and doctor.skills_used_count == {0: 1}, "payable conditional fixture must execute once")
			_check(game.active_field().current_mana == (1 if mana == 4 else 3) and doctor.hp == (3 if mana == 4 else 1), "nested condition must read permanent mana after the 3-Elixir payment")
		_verify(record, game)


func _test_spell_and_timed(player: int) -> void:
	var game := _game(player)
	var spell := UgcBenchmarkPool.card("spell")
	var reactor := UgcBenchmarkPool.card("reactor")
	game.active_hand().append(spell)
	game.opponent_field().slots[3] = reactor
	game.active_field().current_mana = 2
	var record := _start_record(game)
	_command(game, record, {"type": "cast", "hand_index": 0, "skill_index": 0, "target_slot": 3, "target_player": 3 - player})
	_check(reactor.hp == 3 and game.active_field().current_mana == 0 and game.active_hand().size() == 1 and game.active_field().actions_taken == 0, "spell must pay deployment cost, draw and avoid unit action count")
	_check(game.opponent_field().current_mana == 1 and reactor.skills_used_count == {0: 1}, "spell response must still belong to receiver without inventing an on-board initiator")
	_verify(record, game)
	game = _game(player)
	var timed := UgcBenchmarkPool.card("timed")
	game.active_hand().append(timed)
	game.opponent_field().slots[3] = UgcBenchmarkPool.card("relay")
	record = _start_record(game)
	_command(game, record, {"type": "summon", "hand_index": 0, "slot": 0})
	_check(timed.temp_hp == 2 and timed.skills_used_count == {0: 1} and game.active_field().actions_taken == 0, "deployment shield must consume its own passive limit but no unit action")
	_command(game, record, {"type": "end_turn"})
	var original: BattleField = game.player_field if player == 1 else game.player2_field
	_check(original.current_mana == 3 and timed.skills_used_count == {0: 1, 1: 1} and original.actions_taken == 0, "end-turn income must be passive and belong to the ending player")
	_verify(record, game)


func _test_random_and_legal_actions() -> void:
	for seed_value in range(6):
		var game := _game(1)
		game.game_rng.seed = seed_value
		game.active_field().slots[0] = UgcBenchmarkPool.card("random")
		game.active_field().slots[1] = UgcBenchmarkPool.card("relay")
		game.opponent_field().slots[0] = UgcBenchmarkPool.card("timed")
		game.opponent_field().slots[3] = UgcBenchmarkPool.card("reactor")
		game.active_hand().append(UgcBenchmarkPool.card("parasite"))
		game.active_hand().append(UgcBenchmarkPool.card("spell"))
		var record := _start_record(game)
		var before := BattleRepro.state_hash(game)
		var legal := BattleAiPlanner.generate_legal_actions(game)
		_check(legal.any(func(a): return a.type == "activate" and a.slot == 0 and a.target_slot == -1) and legal.any(func(a): return a.type == "attach") and legal.any(func(a): return a.type == "cast"), "AI must enumerate random target, parasite and directed spell fixture actions")
		for action in legal:
			var copy: RefCounted = game.copy_for_simulation()
			_check(BattleRepro.apply_action(copy, action).ok, "every enumerated fixture action must execute on a copy")
		_check(BattleRepro.state_hash(game) == before, "enumeration and speculative fixture execution must preserve the source")
		var simulated: RefCounted = game.copy_for_simulation()
		var action := {"type": "activate", "slot": 0, "skill_index": 0}
		_command(game, record, action)
		_check(BattleRepro.apply_action(simulated, action).ok and BattleRepro.state_hash(simulated) == BattleRepro.state_hash(game), "probability and random target must use identical copied RNG")
		_verify(record, game)


func _test_natural_continuation() -> void:
	var samples: Array = []
	var observer := func(game):
		if game.turn_number >= 4 and samples.is_empty():
			samples.append(BattlePosition.capture(game, {"pool": UgcBenchmarkPool.ID, "pool_sha256": UgcBenchmarkPool.manifest().sha256}))
	var source := HeadlessBattleSimulator.run_game(UgcBenchmarkPool.deck(), UgcBenchmarkPool.deck(), 20261005, "hard", "hard", 60, PlayerData.DEFAULT_BATTLE_CONFIG, observer)
	_check(source.stable and source.winner != "draw" and samples.size() == 1, "frozen pool must produce a terminal natural source and actual midgame sample")
	if samples.is_empty(): return
	var continued := BattlePosition.continue_record(samples[0], "hard")
	_check(continued.ok and continued.stable and not continued.capped and continued.final_hash == source.final_hash, "natural complex-UGC continuation must match uninterrupted source")
	if continued.ok:
		_check(BattlePosition.read(BattleRepro.export_json(continued.record)).ok, "every natural continuation step must replay from JSON")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

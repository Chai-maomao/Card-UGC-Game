extends Node

var failures: Array[String] = []


func _ready() -> void:
	_test_payments_and_isolation()
	_test_chains()
	_test_auto_and_parasite()
	_test_status_and_restore()
	_test_actual_effects()
	_test_mana_drain_spell()
	_test_identity()
	_test_refunds()
	_test_recording_isolation()
	_test_exports_and_source_lifetime()
	if failures.is_empty():
		print("TEST_BATTLE_METRICS_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_BATTLE_METRICS_FAILED: " + failure)
		get_tree().quit(1)


func _game() -> RefCounted:
	var game := HeadlessBattleSimulator._create_game([], [], 71, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.turn_number = 2
	return game


func _attach(game: RefCounted) -> BattleMetrics:
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	return metrics


func _skill(trigger: String, effect: String, value: int, target: String = "self") -> Dictionary:
	return {"trigger": trigger, "effects": [{"effect": effect, "value": value, "target": target, "target_side": "enemy" if target == "target_single" else "all"}]}


func _test_payments_and_isolation() -> void:
	var game := _game()
	var plain: RefCounted = game.copy_for_simulation()
	var metrics := _attach(game)
	_check(BattleRepro.state_hash(game) == BattleRepro.state_hash(plain), "attaching observations must not alter game state")
	_check(not game.copy_for_simulation().metrics_callable.is_valid(), "AI simulations must not inherit the metrics sink")
	var specimen := CardData.new("Deploy", 2, 5, 2)
	for subject in [game, plain]:
		subject.player_hand = [specimen.duplicate_card()]
		subject.player_field.current_mana = 6
		subject.player_field.temp_mana = 1
		BattlePosition.ensure_ids(subject)
		_check(BattleRepro.apply_action(subject, {"type": "summon", "hand_index": 0, "slot": 0}).ok, "deployment fixture must be accepted")
	_check(BattleRepro.state_hash(game) == BattleRepro.state_hash(plain), "observed and unobserved deployment must be identical")
	var row: Dictionary = metrics.cards.get("Deploy", {})
	_check(row.get("healing", -1) == 0 and row.get("summons", 0) == 1 and row.get("mana_spent", 0) == 2 and row.get("temporary_mana_spent", 0) == 1, "deployment HP must not count as healing; exact fees must be recorded")
	var before := metrics.snapshot()
	game.player_hand.append(specimen.duplicate_card())
	_check(not BattleRepro.apply_action(game, {"type": "summon", "hand_index": 0, "slot": 0}).ok and metrics.snapshot() == before, "rejected commands must record no payment or effect")
	# A spell may change its own cost after payment: both counters use the paid amount.
	var spell := CardData.new("Cost change", 2, 1, 0, [_skill("on_cast", "change_cost", 5)])
	spell.card_type = "spell"
	game.player_hand = [spell]
	var spent := int(game.get_stats(1).mana_spent)
	_check(game.cast_spell(0), "spell fixture must cast")
	_check(metrics.cards.get("Cost change", {}).get("mana_spent", 0) == 2 and game.get_stats(1).mana_spent - spent == 2, "self cost changes must not retroactively change payment statistics")


func _test_chains() -> void:
	for blocked in [false, true]:
		var previous := EventBus.is_blocking_signals()
		EventBus.set_block_signals(blocked)
		var game := _game()
		game.player_field.slots[0] = CardData.new("Attacker", 1, 9, 5, [_skill("on_attack", "damage", 2, "target_single")])
		game.player2_field.slots[0] = CardData.new("Defender", 1, 10, 1, [_skill("on_damaged", "heal", 2)])
		game.player2_field.slots[0].apply_buff(SkillEngine.BUFF_THORNS, 2, 2, 2)
		game.player2_field.slots[0].temp_hp = 1
		var metrics := _attach(game)
		game.execute_attack(0, 0)
		var attack: Dictionary = metrics.cards.get("Attacker", {})
		var defense: Dictionary = metrics.cards.get("Defender", {})
		_check(attack.get("damage", 0) == 6 and attack.get("shield_damage", 0) == 1 and attack.get("healing", -1) == 0, "attack plus chained damage must not cancel against defender healing")
		_check(defense.get("damage", 0) == 2 and defense.get("healing", 0) == 4, "thorns and reactive healing belong to defender, including suppressed events")
		_check(attack.get("unit_actions", 0) == 1 and defense.get("unit_actions", -1) == 0, "passive chains must not invent paid actions")
		EventBus.set_block_signals(previous)


func _test_auto_and_parasite() -> void:
	var game := _game()
	game.player_field.slots[0] = CardData.new("Left", 1, 5, 2)
	game.player_field.slots[1] = CardData.new("Right", 1, 5, 5)
	game.player2_field.player_hp = 3
	game.player_field.current_mana = 9
	game.player_field.temp_mana = 4
	game.player_field.action_points = 0
	game.player_field.actions_taken = 2
	var metrics := _attach(game)
	game.end_player_turn()
	_check(metrics.cards.get("Left", {}).get("hero_damage", 0) == 2 and metrics.cards.get("Right", {}).get("hero_damage", 0) == 1, "automatic damage is attributed left-to-right and capped by actual hero HP")
	_check(metrics.cards.Left.action_mana_spent == 2 and metrics.cards.Right.action_mana_spent == 3 and metrics.cards.Right.automatic_attacks == 1 and metrics.cards.Left.temporary_mana_spent == 0, "automatic actions record actual fees after temporary mana expiration")
	game = _game()
	game.player_field.slots[0] = CardData.new("Hit", 1, 5, 5)
	var host := CardData.new("Host", 1, 6, 1)
	var parasite := CardData.new("Absorber", 1, 3, 0)
	parasite.card_type = "parasite"
	ParasiteRules.attach(parasite, host)
	game.player2_field.slots[0] = host
	metrics = _attach(game)
	game.execute_attack(0, 0)
	_check(metrics.cards.get("Hit", {}).get("parasite_damage", 0) == 3 and metrics.cards.Hit.damage == 3 and host.hp == 6, "absorber damage must use the resolved amount before parasite reset")
	# Parasite passives use host targeting but contribution belongs to the parasite.
	game = _game()
	var source := CardData.new("Host action", 1, 6, 1)
	parasite = CardData.new("Passenger", 1, 3, 0, [_skill("on_attack", "damage", 2, "target_single")])
	parasite.card_type = "parasite"
	parasite.parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
	ParasiteRules.attach(parasite, source)
	game.player_field.slots[0] = source
	game.player2_field.slots[0] = CardData.new("Receiver", 1, 8, 0)
	metrics = _attach(game)
	game.execute_attack(0, 0)
	_check(metrics.cards.get("Passenger", {}).get("damage", 0) == 2 and metrics.cards.get("Host action", {}).get("damage", 0) == 1, "parasite skill damage must not be credited to its host")


func _test_status_and_restore() -> void:
	var game := _game()
	var poisoner := CardData.new("Poisoner", 1, 5, 0, [{"trigger": "on_activate", "effects": [{"effect": "add_buff", "buff_id": "poison", "duration": 2, "value": 2, "target": "target_single", "target_side": "enemy"}]}])
	game.player_field.slots[0] = poisoner
	game.player2_field.slots[0] = CardData.new("Poisoned", 1, 8, 0)
	var metrics := _attach(game)
	game.trigger_activate_skills(0, 0, 0, 2)
	var snapshot: Dictionary = game.export_initial_state()
	game.end_player_turn()
	# This buff is owned by P1 and ticks when P2 ends.
	game.current_player = 2
	game.end_player_turn()
	_check(metrics.cards.get("Poisoner", {}).get("damage", 0) == 2, "poison tick uses captured source even after the application window")
	game.apply_initial_state(snapshot, false)
	_check(metrics.cards.is_empty() and metrics.status_origins.is_empty(), "restore must start a fresh observation window")
	game.current_player = 2
	game.end_player_turn()
	_check(metrics.cards.get(BattleMetrics.UNKNOWN, {}).get("damage", 0) == 2, "restored older buff without source provenance must be marked unattributed")


func _test_actual_effects() -> void:
	var game := _game()
	var caster := CardData.new("Caster", 1, 5, 0)
	caster.hp = 4
	game.player_field.slots[0] = caster
	var target := CardData.new("Immune", 1, 2, 0)
	target.immune_lethal = true
	game.player2_field.slots[0] = target
	var metrics := _attach(game)
	var context: Dictionary = game.make_skill_context(0, 0, 2)
	context.source_card = caster
	context.metric_source_card = caster
	SkillEffectApplier.apply_effect("execute", target, 3, {}, context)
	SkillEffectApplier.apply_effect("heal", caster, 7, {}, context)
	SkillEffectApplier.apply_effect("damage", game.player2_field, 100, {}, context)
	_check(metrics.cards.get("Caster", {}).get("damage", 0) == 31 and metrics.cards.Caster.healing == 1, "execute immunity, overheal and hero overkill must use actual lost/restored HP")
	var dead := target.duplicate_card()
	dead.hp = 0
	game.shared_discard.append(dead)
	_check(metrics.cards.Caster.healing == 1, "moving/resetting cards must not invent healing")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _test_identity() -> void:
	var game := _game()
	var a := CardData.new("Same name", 1, 5, 0)
	var b := a.duplicate_card()
	a.card_id = "definition-a"
	b.card_id = "definition-b"
	game.player_field.slots[0] = a
	game.player_field.slots[1] = b
	var metrics := _attach(game)
	for source in [a, b]:
		game.record_metric({"kind": "payment", "action": "activate", "source_card": source, "mana": 1 if source == a else 3})
	_check(metrics.cards["Same name"].mana_spent == 4 and metrics.by_identity["definition-a"].mana_spent == 1 and metrics.by_identity["definition-b"].mana_spent == 3, "same-name definitions must remain separate in identity diagnostics")


func _test_refunds() -> void:
	var game := _game()
	var buffer := CardData.new("Refund skill", 1, 5, 0)
	game.player_field.slots[0] = buffer
	game.player_field.current_mana = 9
	var metrics := _attach(game)
	var context: Dictionary = game.make_skill_context(0)
	context.source_card = buffer
	context.metric_source_card = buffer
	SkillEffectApplier.apply_effect("add_buff", buffer, 3, {"buff_id": SkillEngine.BUFF_MANA_REFUND, "duration": 1}, context)
	game.end_player_turn()
	_check(metrics.cards.get("Refund skill", {}).get("mana_refunded", 0) == 1 and metrics.status_origins.is_empty(), "turn-end refunds must respect the mana cap and release expired source records")
	game = _game()
	game.player_field.slots[0] = CardData.new("Killer", 1, 5, 3)
	game.player2_field.slots[0] = CardData.new("Victim", 1, 2, 0)
	game.player_field.current_mana = 9
	metrics = _attach(game)
	game.execute_attack(0, 0)
	_check(metrics.cards.get("Killer", {}).get("mana_refunded", 0) == 1, "normal kill refund belongs to the attacker")


func _test_recording_isolation() -> void:
	var observed := _game()
	observed.player_field.slots[0] = CardData.new("Relay", 1, 5, 0, [_skill("on_activate", "gain_mana", 2), _skill("on_activate", "damage", 3, "target_single")])
	observed.player_field.slots[1] = CardData.new("Fighter", 1, 6, 2)
	observed.player2_field.slots[0] = CardData.new("Reactive", 1, 8, 1, [_skill("on_damaged", "heal", 1)])
	observed.player_field.action_points = 1
	observed.player_field.current_mana = 3
	BattlePosition.ensure_ids(observed)
	var plain: RefCounted = observed.copy_for_simulation()
	var metrics := _attach(observed)
	var record := BattleRepro.begin(observed)
	for action in [{"type": "activate", "slot": 0, "skill_index": 0}, {"type": "activate", "slot": 0, "skill_index": 1, "target_slot": 0, "target_player": 2}, {"type": "attack", "source_slot": 1, "target_slot": 0}, {"type": "end_turn"}]:
		_check(BattleRepro.execute_and_record(observed, record, action).ok and BattleRepro.apply_action(plain, action).ok, "multi-action observation fixture must remain legal")
		_check(BattleRepro.state_hash(observed) == BattleRepro.state_hash(plain), "observations must preserve complete state, stats, RNG and revision after each command")
	_check(BattleRepro.verify(record).ok, "observed command sequence must replay without observations")
	_check(metrics.cards.get("Relay", {}).get("unit_actions", 0) == 2 and metrics.cards.get("Fighter", {}).get("action_mana_spent", 0) == 2, "shared costs must be recorded across skills and attacks")


func _test_exports_and_source_lifetime() -> void:
	var game := _game()
	var source := CardData.new("Cleanup", 1, 5, 0)
	game.player_field.slots[0] = source
	var metrics := _attach(game)
	var context: Dictionary = game.make_skill_context(0)
	context.source_card = source
	context.metric_source_card = source
	SkillEffectApplier.apply_effect("add_buff", source, 1, {"buff_id": SkillEngine.BUFF_REGEN, "duration": 2}, context)
	_check(metrics.status_origins.size() == 1, "new delayed effects must capture a source")
	game.move_card_to_shared_discard(source, 1)
	metrics.snapshot()
	_check(metrics.status_origins.is_empty(), "discard/reset must release stale local status sources")
	var same_name := CardData.new("Quoted, \"card\"", 1, 4, 2)
	same_name.card_id = "csv-card"
	var batch := HeadlessBattleSimulator.run_batch({"games": 2, "seed": 3, "deck_a": [same_name], "deck_b": [same_name], "max_rounds": 4})
	_check(batch.cards_by_identity.has("csv-card") and batch.identity_names.get("csv-card") == same_name.card_name, "batch JSON must retain canonical card identities")
	var csv := HeadlessBattleSimulator.to_csv(batch)
	_check(csv.contains("card,\"Quoted, \"\"card\"\"\",") and csv.contains("action_points_spent") and csv.contains("mana_refunded"), "CSV must escape quoted names and preserve new metric columns")
	var accumulator := CardBalanceSimulation.new_accumulator("units", 1)
	CardBalanceSimulation.add_game(accumulator, {"stable": true, "lost_status_origins": 1})
	_check(CardBalanceSimulation.finalize(accumulator).warnings.has("incomplete_attribution"), "simulation must expose lost status attribution")

func _test_mana_drain_spell() -> void:
	var game := _game()
	var metrics := _attach(game)
	var spell := CardData.new("Drain and heal",1,1,0,[{"trigger":"on_cast","effects":[{"effect":"mana_drain","target":"self","value":1},{"effect":"heal","target":"target_single","target_side":"ally","value":2}]}])
	spell.card_type = "spell"
	game.player_hand = [spell]
	var ally := CardData.new("Wounded ally",1,5,1)
	ally.hp = 1
	game.player_field.slots[0] = ally
	game.player_field.current_mana = 2
	game.player2_field.current_mana = 3
	_check(game.cast_spell(0,0,0,1),"drain and heal spell must cast through the real spell path")
	var row: Dictionary = metrics.cards.get("Drain and heal",{})
	_check(game.player_field.current_mana == 2 and game.player2_field.current_mana == 2 and ally.hp == 3,"drain and healing must resolve their actual gameplay changes")
	_check(row.get("mana_drained",0) == 1 and row.get("mana_gained",0) == 1 and row.get("healing",0) == 2,"drain and heal spell benefits must be attributed to the spell")
	_check(row.get("unmeasured_effects",0) == 0,"already measured mana drain must not invalidate a spell's score")

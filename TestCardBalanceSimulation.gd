extends Node

const Simulation = preload("res://CardBalanceSimulation.gd")

var failures := 0


func _ready() -> void:
	Locale.language = "zh"
	_test_strength_scores()
	_test_drain_spell_scores()
	_test_control_card_scores()
	var candidate := CardData.new("模拟候选", 2, 3, 2, [{
		"skill_name": "试探",
		"trigger": SkillEngine.TRIGGER_ON_SUMMON,
		"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_SHIELD, "value": 1}],
	}])
	candidate.card_id = "original-card"
	candidate.instance_id = "original-instance"
	var original := PlayerData.serialize_card(candidate).duplicate(true)

	for kind in Simulation.POOL_IDS:
		var pool := Simulation.build_pool(kind, candidate)
		_assert(pool.size() == 9, "%s pool should contain eight fixtures and one candidate" % kind)
		var candidate_count := 0
		for card in pool:
			if card is CardData and card.card_name == Simulation.CANDIDATE_METRIC_KEY:
				candidate_count += 1
		_assert(candidate_count == 1, "%s pool must contain exactly one isolated candidate" % kind)
		var accumulator := Simulation.new_accumulator(kind, 2)
		var baseline_pool := Simulation.build_baseline_pool(kind)
		for index in range(2):
			var result := HeadlessBattleSimulator.run_game(
				pool, baseline_pool, Simulation.seed_for_pool(kind) + index, "normal", "normal", 20)
			Simulation.add_game(accumulator, result)
		var report := Simulation.finalize(accumulator)
		_assert(int(report.get("games", 0)) == 2, "%s report lost games" % kind)
		_assert(float(report.get("draw_rate", -1.0)) >= 0.0 and float(report.get("draw_rate", 2.0)) <= 1.0, "%s draw rate is invalid" % kind)
		_assert(float(report.get("first_player_win_rate", -1.0)) >= 0.0 and float(report.get("first_player_win_rate", 2.0)) <= 1.0, "%s first-player rate is invalid" % kind)
		_assert((report.get("candidate", {}) as Dictionary).has("plays_per_game"), "%s candidate metrics are missing" % kind)
		var score: Variant = report.get("strength_score")
		_assert(score==null or (int(score)>=0 and int(score)<=200),"actual simulation strength must stay within 0–200")

	var deterministic_pool := Simulation.build_pool("units", candidate)
	var deterministic_baseline := Simulation.build_baseline_pool("units")
	var first := HeadlessBattleSimulator.run_game(deterministic_pool, deterministic_baseline, 44123, "normal", "normal", 20)
	var second := HeadlessBattleSimulator.run_game(deterministic_pool, deterministic_baseline, 44123, "normal", "normal", 20)
	_assert(first.get("final_hash", "") == second.get("final_hash", ""), "seeded draft simulation is not deterministic")
	_assert(PlayerData.serialize_card(candidate) == original, "simulation mutated the source card")
	var parasite_accumulator := Simulation.new_accumulator("support", 1)
	Simulation.add_game(parasite_accumulator, {
		"winner": "p1", "rounds": 4, "stable": true, "mana_spent": 8, "unused_mana": 2,
		"cards": {Simulation.CANDIDATE_METRIC_KEY: {"attaches": 1}},
	})
	var parasite_report := Simulation.finalize(parasite_accumulator)
	_assert(int(parasite_report.candidate.plays) == 1 and is_equal_approx(float(parasite_report.candidate.plays_per_game), 1.0), "parasite attachment was not counted as candidate use")

	await _check_editor_ui(_control_card())
	if failures > 0:
		push_error("TEST_CARD_BALANCE_SIMULATION_FAILED: %d" % failures)
		get_tree().quit(1)
		return
	print("TEST_CARD_BALANCE_SIMULATION_OK")
	get_tree().quit(0)


func _check_editor_ui(candidate: CardData) -> void:
	var old_draft: Dictionary = PlayerData.card_draft.duplicate(true)
	var old_tutorial := PlayerData.skill_tutorial_active
	PlayerData.skill_tutorial_active = false
	PlayerData.card_draft = {
		"name": candidate.card_name,
		"cost": candidate.cost,
		"hp": candidate.max_hp,
		"atk": candidate.atk,
		"gender": candidate.gender,
		"card_type": candidate.card_type,
		"art_path": "",
		"skill1": candidate.skills[0].duplicate(true),
		"skill2": candidate.skills[1].duplicate(true),
		"skill3": {},
		"talent": {},
	}
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = editor.get("simulation_button")
	_assert(button.text == Locale.t("simulation.button"), "simulation entry is not localized")
	_assert(button.get_meta("ui_button_variant", "") == "utility", "simulation entry must use the same utility style as the other diagnostics")
	var popup: CanvasLayer = editor.call("_open_balance_simulation", candidate, false)
	await get_tree().process_frame
	var panel: Panel = popup.get_node("CardSimulationPanel")
	var note: Label = panel.find_child("SimulationNote", true, false)
	var close_button: Button = panel.find_child("SimulationCancelButton", true, false)
	_assert(panel.get_theme_stylebox("panel") is StyleBoxFlat, "simulation popup does not use the shared panel style")
	_assert(note.text.contains("0–200") and not note.text.contains("Scores range"), "simulation popup mixed languages")
	_assert(close_button.get_meta("ui_button_variant", "") == "secondary", "simulation close action does not use the shared style")

	var cancelled_popup: CanvasLayer = editor.call("_open_balance_simulation", candidate, true, 2)
	var cancelled_progress := cancelled_popup.find_child("SimulationProgress", true, false) as ProgressBar
	var cancel_button := cancelled_popup.find_child("SimulationCancelButton", true, false) as Button
	cancelled_progress.value_changed.connect(func(value: float):
		if value == 2.0:
			cancel_button.pressed.emit.call_deferred()
	)
	for _frame in range(120):
		if not is_instance_valid(cancelled_popup):
			break
		await get_tree().process_frame
	_assert(not is_instance_valid(cancelled_popup), "cancelling at the end of a pool must close the running simulation")
	await get_tree().process_frame

	var running_popup: CanvasLayer = editor.call("_open_balance_simulation", candidate, true, 8)
	var running_panel: Panel = running_popup.get_node("CardSimulationPanel")
	var status: Label = running_panel.find_child("SimulationStatus", true, false)
	for _frame in range(120):
		if status.text == Locale.t("simulation.complete", [24]):
			break
		await get_tree().process_frame
	_assert(status.text == Locale.t("simulation.complete", [24]), "editor simulation did not complete incrementally")
	var progress: ProgressBar = running_panel.find_child("SimulationProgress", true, false)
	var results: VBoxContainer = running_panel.find_child("SimulationResults", true, false)
	_assert(is_equal_approx(progress.value, 24.0), "simulation progress did not reach all games")
	_assert(not progress.visible and not status.visible,"completed scores must not retain progress or summary text")
	var result_count := 0
	for child in results.get_children():
		if child.name.begins_with("PoolResult_"):
			result_count += 1
			var score_label: Label = child.get_node("StrengthScore")
			_assert(score_label.text.is_valid_int() and int(score_label.text) in range(201),
				"the control card must show a numeric score in this environment")
			_assert(child.find_children("*", "Label", true, false).any(func(label):
				return label.text == Locale.t("simulation.partial_score")),
				"the UI must identify the control card's measured score as partial")
	_assert(result_count == 3, "simulation did not render all three environment reports")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/card-simulation-scores.png")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().process_frame
	_assert(not is_instance_valid(running_popup) and editor.get("_simulation_ui").is_empty(),
			"Escape must close the results and clear the simulation state")
	editor.queue_free()
	PlayerData.card_draft = old_draft
	PlayerData.skill_tutorial_active = old_tutorial


func _measured_score(candidate_damage: int, reference_damage: int, candidate_cost: int = 2) -> Variant:
	var metrics := BattleMetrics.new()
	for entry in [[Simulation.CANDIDATE_METRIC_KEY,candidate_damage],["reference",reference_damage]]:
		var source := {"name":entry[0],"identity":entry[0]}
		var cost := candidate_cost if entry[0] == Simulation.CANDIDATE_METRIC_KEY else 2
		metrics.record({"kind":"payment","source":source,"action":"summon","mana":cost,"points":0})
		metrics.record({"kind":"damage","source":source,"source_player":1,"target_player":2,"amount":entry[1]})
	var accumulator := Simulation.new_accumulator("units",1)
	Simulation.add_game(accumulator,{"stable":true,"cards":metrics.cards,"winner":"draw"})
	return Simulation.finalize(accumulator).strength_score


func _test_strength_scores() -> void:
	_assert(_measured_score(4,4)==100,"equal observed resource efficiency must score 100")
	_assert(_measured_score(4,4,0) > 100 and _measured_score(4,4,4) < 100,
		"same contribution must score higher when it cost less Elixir")
	_assert(_measured_score(8,4)>100 and _measured_score(2,4)<100,"observed strength must move the score to the correct side of 100")
	for amount in [0,1,10000]:
		var score: int = _measured_score(amount,4)
		_assert(score>=0 and score<=200,"measured extremes must not escape the score range")
	var missing := Simulation.new_accumulator("units",1)
	Simulation.add_game(missing,{"stable":true,"cards":{},"winner":"draw"})
	_assert(Simulation.finalize(missing).strength_score==null,"unused candidates must not receive a fabricated balanced score")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _test_drain_spell_scores() -> void:
	var spell := CardData.new("Drain and heal",1,1,0,[{"trigger":"on_cast","effects":[{"effect":"mana_drain","target":"self","value":1},{"effect":"heal","target":"target_single","target_side":"ally","value":2}]}])
	spell.card_type = "spell"
	for kind in Simulation.POOL_IDS:
		var accumulator := Simulation.new_accumulator(kind,8)
		for index in range(8):
			var pool := Simulation.build_pool(kind,spell)
			var baseline := Simulation.build_baseline_pool(kind)
			Simulation.add_game(accumulator,HeadlessBattleSimulator.run_game(baseline,pool,Simulation.seed_for_pool(kind)+index,"normal","normal",30))
		var report := Simulation.finalize(accumulator)
		_assert(report.candidate.plays > 0 and report.candidate.mana_drained > 0,"drain spell must actually be played and siphon Elixir in "+kind)
		_assert(report.strength_score != null,"measured drain and healing spell must produce a reference score in "+kind)
		print("DRAIN_SPELL_SCORE ",kind," ",report.strength_score)

func _control_card() -> CardData:
	return CardData.new("控制测试", 3, 4, 2, [
		{"trigger": "on_turn_start", "effects": [{"effect": "add_buff", "buff_id": "regen",
			"target": "self", "value": 1, "duration": 1}]},
		{"trigger": "on_turn_end", "effects": [{"effect": "add_buff", "buff_id": "silence",
			"target": "target_female", "target_side": "enemy", "value": 1, "duration": 1}]},
	])

func _test_control_card_scores() -> void:
	var card := _control_card()
	for kind in Simulation.POOL_IDS:
		var accumulator := Simulation.new_accumulator(kind, 8)
		var pool := Simulation.build_pool(kind, card)
		var baseline := Simulation.build_baseline_pool(kind)
		for index in range(8):
			Simulation.add_game(accumulator, HeadlessBattleSimulator.run_game(baseline, pool,
				Simulation.seed_for_pool(kind) + index, "normal", "normal", 30))
		var report := Simulation.finalize(accumulator)
		_assert(report.candidate.plays > 0 and report.candidate.unmeasured_effects > 0,
			"control sample must be used and trigger an unmeasured status in " + kind)
		_assert(report.strength_score != null,
			"control card must still receive a score in " + kind)
		_assert(report.partial_score, "silence sample must label its score as partial")
		print("CONTROL_CARD_SCORE ", kind, " ", report.strength_score)

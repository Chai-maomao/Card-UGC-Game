extends Node

const Simulation = preload("res://CardBalanceSimulation.gd")

var failures := 0


func _ready() -> void:
	Locale.language = "zh"
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

	await _check_editor_ui(candidate)
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
		"skill2": {},
		"skill3": {},
		"talent": {},
	}
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = editor.get_node("Panel/MarginContainer/ScrollContainer/VBoxContainer/AnalysisActionsRow/SimulationButton")
	_assert(button.text == Locale.t("simulation.button"), "simulation entry is not localized")
	_assert(button.get_meta("ui_button_variant", "") == "secondary", "simulation entry does not use the shared secondary style")
	var popup: CanvasLayer = editor.call("_open_balance_simulation", candidate, false)
	await get_tree().process_frame
	var panel: Panel = popup.get_node("CardSimulationPanel")
	var note: Label = panel.find_child("SimulationNote", true, false)
	var close_button: Button = panel.find_child("SimulationCancelButton", true, false)
	_assert(panel.get_theme_stylebox("panel") is StyleBoxFlat, "simulation popup does not use the shared panel style")
	_assert(note.text.contains("共享牌池") and not note.text.contains("shared pool"), "simulation popup mixed languages")
	_assert(close_button.get_meta("ui_button_variant", "") == "secondary", "simulation close action does not use the shared style")

	var running_popup: CanvasLayer = editor.call("_open_balance_simulation", candidate, true, 2)
	var running_panel: Panel = running_popup.get_node("CardSimulationPanel")
	var status: Label = running_panel.find_child("SimulationStatus", true, false)
	for _frame in range(120):
		if status.text == Locale.t("simulation.complete", [6]):
			break
		await get_tree().process_frame
	_assert(status.text == Locale.t("simulation.complete", [6]), "editor simulation did not complete incrementally")
	var progress: ProgressBar = running_panel.find_child("SimulationProgress", true, false)
	var results: VBoxContainer = running_panel.find_child("SimulationResults", true, false)
	_assert(is_equal_approx(progress.value, 6.0), "simulation progress did not reach all games")
	var result_count := 0
	for child in results.get_children():
		if child.name.begins_with("PoolResult_"):
			result_count += 1
	_assert(result_count == 3, "simulation did not render all three environment reports")
	var running_close: Button = running_panel.find_child("SimulationCancelButton", true, false)
	running_close.pressed.emit()
	await get_tree().process_frame
	_assert(not is_instance_valid(running_popup), "simulation close action did not release the popup")
	editor.queue_free()
	PlayerData.card_draft = old_draft
	PlayerData.skill_tutorial_active = old_tutorial


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

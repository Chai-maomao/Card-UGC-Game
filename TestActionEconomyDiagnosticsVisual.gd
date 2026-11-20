extends Node

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	var old_draft := PlayerData.card_draft.duplicate(true)
	var old_config := PlayerData.battle_config.duplicate(true)
	var old_context := PlayerData.card_playtest_context.duplicate(true)
	var old_setup := PlayerData.battle_preparation_snapshot()
	var old_tutorial := PlayerData.skill_tutorial_active
	var old_language := Locale.language
	PlayerData.skill_tutorial_active = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/action-economy"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			var prefix := "%s-%dx%d" % [language, dimensions.x, dimensions.y]
			await _editor_path(viewport, prefix)
			await _battle_path(viewport, prefix)
		remove_child(viewport)
		viewport.free()
	PlayerData.card_draft = old_draft
	PlayerData._apply_battle_preparation(old_setup)
	PlayerData.battle_config = old_config
	PlayerData.card_playtest_context = old_context
	PlayerData.skill_tutorial_active = old_tutorial
	Locale.language = old_language
	if failures.is_empty():
		print("TEST_ACTION_ECONOMY_DIAGNOSTICS_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_ACTION_ECONOMY_DIAGNOSTICS_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _specimen() -> CardData:
	return CardData.new("资源接力" if Locale.language == "zh" else "Resource Relay", 2, 5, 1, [
		{"skill_name": "补给" if Locale.language == "zh" else "Supply", "trigger": "on_activate", "effects": [{"effect": "gain_mana", "target": "self", "value": 2}]},
		{"skill_name": "打击" if Locale.language == "zh" else "Strike", "trigger": "on_activate", "effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 3}]},
	])


func _editor_path(viewport: SubViewport, prefix: String) -> void:
	PlayerData.card_playtest_context = {}
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	PlayerData.card_draft = PlayerData.card_to_draft(_specimen())
	var editor := preload("res://CardEditor.tscn").instantiate()
	viewport.add_child(editor)
	await get_tree().create_timer(0.3).timeout
	_check(editor.get_node_or_null("ActionEconomyDiagnostics")==null and editor.find_child("ActionEconomyButton",true,false)==null,"card editor must have no action-cost calculator entry")
	await _capture(viewport,prefix+"-creator")
	var simulation: CanvasLayer = editor._open_balance_simulation(_specimen(), true, 2)
	var simulation_panel := simulation.get_node("CardSimulationPanel") as Control
	var simulation_status := simulation_panel.find_child("SimulationStatus", true, false) as Label
	for _frame in range(240):
		if simulation_status.text == Locale.t("simulation.complete", [6]): break
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	_check(simulation_status.text == Locale.t("simulation.complete", [6]), "rendered candidate simulation must finish")
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(simulation_panel.get_global_rect()), "simulation result panel must fit the viewport")
	var results := simulation_panel.find_child("SimulationResults", true, false) as VBoxContainer
	for pool in CardBalanceSimulation.POOL_IDS:
		var row := results.get_node_or_null("PoolResult_" + pool) as HBoxContainer
		var score := row.get_node_or_null("StrengthScore") as Label if row != null else null
		_check(score != null and score.is_visible_in_tree() and score.text.is_valid_int(),
				"completed simulation must display the numeric score for " + pool)
		if score != null:
			_check(row.get_child(0).text == Locale.t("simulation.pool.%s" % pool)
					and row.get_global_rect().encloses(score.get_global_rect()),
					"each score must appear next to its localized environment label")
	var result_scroll := simulation_panel.find_child("SimulationScroll", true, false) as ScrollContainer
	_check(result_scroll.get_global_rect().size.x + 1 >= result_scroll.get_child(0).size.x, "localized result lines must not widen the scroll area")
	var original_size := viewport.size
	viewport.size = Vector2i(960, 540) if original_size.x > 960 else Vector2i(1280, 720)
	await get_tree().create_timer(0.3).timeout
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(simulation_panel.get_global_rect()), "open simulation must fit after live viewport resizing")
	var resize_close := simulation_panel.find_child("SimulationCancelButton", true, false) as Button
	_check(simulation_panel.get_global_rect().encloses(resize_close.get_global_rect()), "close button must remain accessible after live resizing")
	viewport.size = original_size
	await get_tree().create_timer(0.3).timeout
	await _capture(viewport, prefix + "-simulation")
	_click(viewport, simulation_panel.find_child("SimulationCancelButton", true, false).get_global_rect().get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(simulation), "result close button must release the popup")
	editor.free()


func _battle_path(viewport: SubViewport, prefix: String) -> void:
	PlayerData.configure_card_playtest(_specimen())
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	var battle := preload("res://Main.tscn").instantiate()
	viewport.add_child(battle)
	await get_tree().create_timer(0.35).timeout
	battle.game.turn_number = 2
	battle.game.player2_field.slots[3] = CardData.new("Target", 1, 9, 1, [{"trigger": "on_damaged", "max_uses": 1, "effects": [{"effect": "gain_mana", "value": 2, "target": "self"}, {"effect": "draw_cards", "value": 1, "target": "self"}, {"effect": "damage", "value": 2, "target": "target_single", "target_side": "enemy"}]}])
	battle.game.player2_field.current_mana = 0
	battle.game.player2_field.temp_mana = 0
	var enemy_hand_before: int = battle.game.player2_hand.size()
	var decoy := CardData.new("Unrelated same-slot unit", 1, 5, 0)
	battle.game.player_field.slots[3] = decoy
	battle.game.player_field.action_points = 2
	battle.game.player_field.actions_taken = 0
	battle.game.player_field.current_mana = 2
	# Deploy the actual tested instance; an unrelated same-name fixture has a different identity.
	battle._on_card_drag_summoned(battle.game.player_hand[0], null, 0)
	battle.update_entire_screen()
	await get_tree().process_frame
	var card_ui = battle.player_side_ui.get_child(0).current_card_ui
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,card_ui,0)
	await get_tree().create_timer(0.35).timeout
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	print("ECONOMY_UI first: actions=%d skill2_disabled=%s attack_disabled=%s attack_visible=%s" % [battle.game.player_field.actions_taken, card_ui.skill2_btn.disabled, card_ui.normal_atk_btn.disabled, card_ui.normal_atk_btn.visible])
	_check(battle.game.player_field.actions_taken == 1 and not card_ui.skill2_btn.disabled and (card_ui.normal_atk_btn.disabled or not card_ui.normal_atk_btn.visible), "after first skill, distinct skill must remain available and normal attack disabled")
	_check(battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "second legal active skill must retain the actual gold action glow")
	await _capture_readiness(viewport, battle, prefix + "-ready-second-skill")
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,card_ui,1)
	await get_tree().process_frame
	_check(battle.activate_targeting, "second skill button must request a target")
	var slot: Control = battle.enemy_side_ui.get_child(3)
	_click(viewport, slot.get_global_rect().position + slot.size * Vector2(0.5, 0.35))
	await get_tree().create_timer(0.35).timeout
	_check(battle.game.player_field.actions_taken == 2 and battle.game.player_field.action_points == 1 and battle.game.player2_field.slots[3].hp == 6, "real second skill must pay and apply its damage")
	_check(battle.game.player2_field.current_mana == 2 and battle.game.player2_hand.size() == enemy_hand_before + 1 and battle.game.player_field.current_mana == 2, "real reactive income and draw must belong to the receiver")
	_check(battle.game.player_field.slots[0].hp == 3 and decoy.hp == 5, "real targeted response must hit the initiator at a different slot")
	var inspector: PlaytestInspector
	for child in battle.get_children():
		if child is PlaytestInspector: inspector = child
	_check(inspector != null, "card playtest must install the inspector")
	if inspector != null:
		inspector.show_trace()
		await get_tree().create_timer(0.15).timeout
		var label := inspector.dialog.find_child("PlaytestActionEconomy", true, false) as Label
		print("ECONOMY_UI inspector position=%s size=%s box=%s rows=%s" % [inspector.dialog.position, inspector.dialog.size, inspector.dialog.get_child(0).get_combined_minimum_size() if inspector.dialog.get_child(0) is Control else "none", inspector.rows.get_combined_minimum_size()])
		_check(label.text == ActionEconomyAnalyzer.live_description(battle.game), "playtest must quote the live next action")
		var contribution := inspector.dialog.find_child("PlaytestCardContribution", true, false) as Label
		_check(contribution != null and contribution.text == Locale.t("simulation.live_metrics", [2, 1, 0, 2, 2, 3, 0]), "playtest must show actual candidate actions, payments, income and damage")
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(Rect2(Vector2(inspector.dialog.position), Vector2(inspector.dialog.size))), "playtest inspector must fit the viewport")
		await _capture(viewport, prefix + "-playtest")
		inspector.dialog.hide()
	await _wait_for_input(battle)
	_check(not battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "exhausting both active skills must remove the glow after feedback unlocks")
	for _turn in range(2):
		_check(BattleRepro.apply_action(battle.game, {"type": "end_turn"}).ok, "limited passive fixture must advance through both turns")
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var second_mana: int = battle.game.player2_field.current_mana
	var second_hand: int = battle.game.player2_hand.size()
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(battle.is_my_turn() and not card_ui.skill2_btn.disabled, "next-turn skill input must be unlocked before clicking")
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,card_ui,1)
	await get_tree().process_frame
	slot = battle.enemy_side_ui.get_child(3)
	_click(viewport, slot.get_global_rect().position + slot.size * Vector2(0.5, 0.35))
	await get_tree().create_timer(0.35).timeout
	var receiver: CardData = battle.game.player2_field.slots[3]
	_check(receiver.hp == 3 and int(receiver.skills_used_count.get(0, 0)) == 1, "real next-turn hit must preserve the exhausted lifetime limit")
	_check(battle.game.player_field.slots[0].hp == 3 and battle.game.player2_field.current_mana == second_mana and battle.game.player2_hand.size() == second_hand, "exhausted passive must not deal more damage, generate income or draw")
	if inspector != null:
		inspector.show_trace()
		await get_tree().create_timer(0.15).timeout
		var contribution := inspector.dialog.find_child("PlaytestCardContribution", true, false) as Label
		_check(contribution.text == Locale.t("simulation.live_metrics", [3, 1, 0, 2, 2, 6, 0]), "later diagnostics must count actual skill damage without exhausted passive effects")
		await _capture(viewport, prefix + "-use-limit")
		inspector.dialog.hide()
	await _wait_for_input(battle)
	await _rules_help_path(viewport, battle, prefix)
	await _readiness_edge_cases(viewport, battle, prefix)
	battle.free()
	PlayerData.restore_after_card_playtest()


func _rules_help_path(viewport: SubViewport, battle: Node, prefix: String) -> void:
	_click(viewport, battle.help_btn.get_global_rect().get_center())
	await get_tree().create_timer(0.3).timeout
	var layer := battle.get_node_or_null("BattleRulesHelp")
	_check(layer != null, "real help button must open current match rules")
	if layer == null: return
	var panel := layer.find_child("BattleHelpPanel", true, false) as Control
	var body := layer.find_child("BattleHelpBody", true, false) as Label
	var scroll := layer.find_child("BattleHelpScroll", true, false) as ScrollContainer
	var close := layer.find_child("BattleHelpClose", true, false) as Button
	_check(body.text == preload("res://BattleRulesHelp.gd").description(battle.game), "visible rules must match current match configuration")
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel.get_global_rect()) and panel.get_global_rect().encloses(close.get_global_rect()), "rules panel and close button must fit both supported sizes")
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y and body.size.x <= scroll.size.x, "long rules must scroll vertically without horizontal overflow")
	await _capture(viewport, prefix + "-rules")
	# Exercise scrolling through the real input surface, not only a property.
	var point := scroll.get_global_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for _i in range(30):
		for pressed in [true, false]:
			wheel.pressed = pressed
			viewport.push_input(wheel, true)
	await get_tree().process_frame
	_check(scroll.scroll_vertical > 0, "rules must respond to mouse wheel scrolling")
	await _capture(viewport, prefix + "-rules-scrolled")
	_click(viewport, close.get_global_rect().get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	_check(battle.get_node_or_null("BattleRulesHelp") == null, "real close button must dismiss rules")


func _wait_for_input(battle: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while battle.is_resolution_locked() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not battle.is_resolution_locked(), "skill feedback must eventually release its input lock")
	await get_tree().process_frame
	await get_tree().process_frame


func _readiness_edge_cases(viewport: SubViewport, battle: Node, prefix: String) -> void:
	var field: BattleField = battle.game.player_field
	var actor := CardData.new("Readiness", 0, 6, 2, [{"trigger": "on_activate", "effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 1}]}, {"trigger": "on_damaged", "effects": [{"effect": "gain_attack", "target": "self", "value": 1}]}])
	field.slots[0] = actor
	battle.game.turn_number = 1
	field.actions_taken = 0
	field.action_points = 3
	await _refresh_readiness(battle)
	var card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(card_ui.normal_atk_btn.disabled and card_ui.skill1_btn.disabled and card_ui.skill2_btn.disabled and not battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "round-one blocked skills and passives must not advertise usable buttons or glow")
	battle.game.allow_first_turn_attacks = true
	await _refresh_readiness(battle)
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(not card_ui.normal_atk_btn.disabled and card_ui.skill1_btn.disabled and battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "explicit first-turn attack allowance must agree with buttons and glow")
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,card_ui)
	await get_tree().process_frame
	_check(battle.current_attacker_idx == 0, "real attack input must respect the saved first-turn allowance")
	battle.cancel_attack()
	battle.game.allow_first_turn_attacks = false
	battle.game.turn_number = 2
	actor.skills = [{"trigger": "on_activate", "effects": [{"effect": "gain_attack", "target": "self", "value": 1}]}]
	actor.apply_buff(SkillEngine.BUFF_SILENCE, 1, 1, 1)
	actor.attack_ignores_silence = true
	await _refresh_readiness(battle)
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(not card_ui.normal_atk_btn.disabled and card_ui.skill1_btn.disabled and battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "silence exception must enable only the normal attack")
	actor.status_effects.clear()
	actor.has_acted = true
	actor.skills[0].max_uses = 1
	actor.skills_used_count[0] = 1
	await _refresh_readiness(battle)
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(card_ui.normal_atk_btn.disabled and card_ui.skill1_btn.disabled and not battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "lifetime-exhausted active must not leave a ghost glow")
	actor.skills_used_count.clear()
	field.actions_taken = 3
	field.action_points = 1
	field.current_mana = 2
	field.temp_mana = 0
	battle.game.battle_config.action_mana_factor = 1.5
	await _refresh_readiness(battle)
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(card_ui.skill1_btn.disabled and not battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "rounded shortage must disable both active button and glow")
	field.temp_mana = 1
	await _refresh_readiness(battle)
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(not card_ui.skill1_btn.disabled and battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "temporary mana must restore payable active and glow together")
	await _capture_readiness(viewport, battle, prefix + "-ready-shortage")
	actor = CardData.new("Zero attack growth", 0, 6, 0, [{"trigger": "on_attack", "max_uses": 1, "effects": [{"effect": "gain_attack", "target": "self", "value": 1}]}])
	field.slots[0] = actor
	field.actions_taken = 0
	await _refresh_readiness(battle)
	card_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(not card_ui.normal_atk_btn.disabled and battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "existing zero-attack growth cards must remain actionable")
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,card_ui)
	await get_tree().process_frame
	var slot: Control = battle.enemy_side_ui.get_child(3)
	_click(viewport, slot.get_global_rect().position + slot.size * Vector2(0.5, 0.35))
	await get_tree().create_timer(0.15).timeout
	await _wait_for_input(battle)
	_check(actor.field_atk_bonus == 1 and actor.has_attacked and not battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "real zero-damage attack must still trigger growth and then remove readiness")


func _refresh_readiness(battle: Node) -> void:
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_readiness(viewport: SubViewport, battle: Node, name: String) -> void:
	# Preserve the action-art reveal, then photograph the unobscured choices.
	await _wait_for_input(battle)
	if battle.splash_tween != null and battle.splash_tween.is_running():
		await battle.splash_tween.finished
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(20, 200)
	viewport.push_input(motion, true)
	await get_tree().process_frame
	await _capture(viewport, name)


func _check_panel(viewport: SubViewport, diagnostics: Node) -> void:
	var panel: Control = diagnostics.panel
	print("ECONOMY_UI panel=%s viewport=%s minimum=%s" % [panel.get_global_rect(), viewport.size, panel.get_combined_minimum_size()])
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel.get_global_rect()), "diagnostic panel must fit the viewport")
	for name in ["ActionNumber", "RemainingPoints", "AvailableMana", "ActionEconomyClose", "ActionEconomyStatus"]:
		var control := panel.find_child(name, true, false) as Control
		_check(control != null and panel.get_global_rect().encloses(control.get_global_rect()), "diagnostic control must stay visible: " + name)


func _click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)


func _capture(viewport: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/action-economy/" + name + ".png") == OK, "visual evidence must save")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

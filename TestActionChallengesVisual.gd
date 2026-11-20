extends Node

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.card_playtest_context = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/action-challenges"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			for id in ActionPlanningChallenges.IDS:
				PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
				PlayerData.practice_challenge_id = id
				var battle = load("res://Main.tscn").instantiate()
				viewport.add_child(battle)
				await get_tree().create_timer(0.6).timeout
				var controller: ChallengeController
				for child in battle.get_children():
					if child is ChallengeController: controller = child
				_check(controller != null, "new challenge must install its controller")
				if controller == null: continue
				var prefix := "%s-%s-%dx%d" % [id, language, dimensions.x, dimensions.y]
				_check_popup(viewport, controller)
				_click_button(viewport, controller.popup_layer, "ChallengeHintButton")
				await get_tree().create_timer(0.15).timeout
				_check(PracticeChallenges.hint(id) in controller.message_label.text, "hint button must reveal localized help")
				_check_popup(viewport, controller)
				await _capture(viewport, prefix + "-hint")
				_click_button(viewport, controller.popup_layer, "ChallengeCloseButton")
				await get_tree().create_timer(0.15).timeout
				if id == "action_reserve":
					var officer = battle.player_side_ui.get_child(0).current_card_ui
					await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,officer,0)
					await get_tree().create_timer(0.1).timeout
					_check(battle.activate_targeting, "real skill button must request an allied target")
					_click_slot(viewport, battle.player_side_ui.get_child(1))
					await get_tree().create_timer(0.35).timeout
					_check(PracticeChallenges.stage(battle.game, id) == "payoff", "UI skill must grant mana and buff the Striker")
					var striker = battle.player_side_ui.get_child(1).current_card_ui
					await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,striker)
					_click_slot(viewport, battle.enemy_side_ui.get_child(0))
				else:
					_click(viewport, battle.face_mana_button.get_global_rect().get_center())
					await get_tree().process_frame
					await _hover_end_turn(viewport, battle)
					_check(battle.end_turn_button.tooltip_text.contains(Locale.t("battle.end_preview_total", [1, 2, 2])), "initial preview must show the low-damage automatic attack")
					await _capture(viewport, prefix + "-preview")
					# Use the same drop handler as a card dragged onto an ally slot.
					var card_ui = battle.hand_container.get_child(0)
					battle._on_card_drag_cast(card_ui.current_card_data, card_ui, 0, 0, 1)
					await get_tree().create_timer(0.35).timeout
					_check(PracticeChallenges.stage(battle.game, id) == "payoff", "real drop path must withdraw Support")
					_click(viewport, battle.end_turn_button.get_global_rect().get_center())
				await _wait_for_challenge_result(controller)
				_check(controller.finished and PracticeChallenges.succeeded(battle.game, id), "real player actions must produce the success popup")
				_check_popup(viewport, controller)
				await _capture(viewport, prefix + "-success")
				# Restart and produce an actual failed objective, then retry via UI.
				controller._reset()
				await get_tree().create_timer(0.15).timeout
				_click_button(viewport, controller.popup_layer, "ChallengeCloseButton")
				await get_tree().create_timer(0.1).timeout
				if id == "action_reserve":
					var card_ui = battle.hand_container.get_child(0)
					battle._on_card_drag_cast(card_ui.current_card_data, card_ui, 0, 0, 2)
				else:
					_click(viewport, battle.face_mana_button.get_global_rect().get_center())
					await get_tree().process_frame
					_click(viewport, battle.end_turn_button.get_global_rect().get_center())
					await get_tree().create_timer(0.3).timeout
					_check(not controller.finished, "failed end-turn must finish its asynchronous transition before showing retry")
				await _wait_for_challenge_result(controller)
				_check(controller.finished and PracticeChallenges.failed(battle.game, id), "wrong ordering must show a failure popup")
				_check_popup(viewport, controller)
				await _capture(viewport, prefix + "-failure")
				_click_button(viewport, controller.popup_layer, "ChallengeRetryButton")
				await get_tree().create_timer(0.2).timeout
				_check(not controller.finished and battle.game.player_field.actions_taken == 4 and PracticeChallenges.stage(battle.game, id) == "setup", "UI retry must restore the late-turn budget")
				controller._close_popup()
				await get_tree().process_frame
				PracticeChallenges.show_picker(battle)
				await get_tree().create_timer(0.15).timeout
				var picker: Node = battle.get_node("ChallengePickerLayer")
				_check(picker.find_child("Challenge_action_reserve", true, false) != null and picker.find_child("Challenge_action_finish", true, false) != null, "both lessons must be available in the catalog")
				var scroll := picker.find_child("ChoiceScroll", true, false) as ScrollContainer
				_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(scroll.get_global_rect()), "challenge list must fit the viewport")
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				await get_tree().process_frame
				await _capture(viewport, prefix + "-catalog")
				viewport.remove_child(battle)
				battle.free()
		remove_child(viewport)
		viewport.free()
	Locale.language = "zh"
	PlayerData.practice_challenge_id = ""
	if failures.is_empty():
		print("TEST_ACTION_CHALLENGES_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_ACTION_CHALLENGES_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _wait_for_challenge_result(controller: ChallengeController) -> void:
	var deadline := Time.get_ticks_msec() + 4500
	while not controller.finished and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout


func _check_popup(viewport: SubViewport, controller: ChallengeController) -> void:
	_check(is_instance_valid(controller.popup_layer), "objective popup must exist")
	if not is_instance_valid(controller.popup_layer): return
	var panel := controller.popup_layer.get_node("ChallengePopup") as Control
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel.get_global_rect()), "localized popup must remain inside the viewport")
	for child in panel.find_children("*Button", "Button", true, false):
		_check(panel.get_global_rect().encloses(child.get_global_rect()), "popup navigation must remain visible")
	_check(panel.find_child("ChallengeTextScroll", true, false) != null, "long help must use the shared scrollable presentation")


func _click_button(viewport: SubViewport, root: Node, name: String) -> void:
	var button := root.find_child(name, true, false) as Button
	_check(button != null, "expected UI button: " + name)
	if button != null: _click(viewport, button.get_global_rect().get_center())


func _click_slot(viewport: SubViewport, slot: Control) -> void:
	_click(viewport, slot.get_global_rect().position + slot.size * Vector2(0.5, 0.35))


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


func _hover_end_turn(viewport: SubViewport, battle: Node) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = battle.end_turn_button.get_global_rect().get_center()
	viewport.push_input(motion, true)
	await get_tree().create_timer(0.8).timeout


func _capture(viewport: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/action-challenges/" + name + ".png") == OK, "visual evidence must save")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

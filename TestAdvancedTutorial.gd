extends Node

const Exercises = preload("res://AdvancedTutorialExercises.gd")
const Lessons = preload("res://AdvancedTutorialLessons.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	tree.current_scene = null
	var english := OS.get_cmdline_user_args().has("--english")
	Locale.language = "en" if english else "zh"
	AppPreferences.set_value("window_mode", 1)
	get_window().size = Vector2i(1280, 720)
	var original_rules := PlayerData.battle_config.duplicate(true)
	var original_mode := PlayerData.battle_mode
	var collection_hash := FileAccess.get_sha256(PlayerData.save_path)
	var tutorial_hash := FileAccess.get_sha256(PlayerData.tutorial_progress_path) if FileAccess.file_exists(PlayerData.tutorial_progress_path) else ""
	UIMotion.replace_scene("res://MainMenu.tscn", true)
	await tree.scene_changed
	await tree.process_frame
	var menu := tree.current_scene
	menu.start_battle_btn.pressed.emit()
	await tree.process_frame
	var entry: Button = menu.battle_hub_layer.find_choice(Locale.t("menu.advanced_tutorial"))
	if not _check(entry != null, "The battle hub must expose the advanced tutorial"):
		return
	entry.pressed.emit()
	await tree.scene_changed
	await tree.process_frame
	var tutorial := tree.current_scene
	if not _check(tutorial.scene_file_path == "res://AdvancedTutorial.tscn", "The real menu entry must open the tutorial"):
		return
	var initial_guide: Node = tutorial._battle.tutorial_controller
	if not _check(UIMotion.top_popup() == initial_guide.overlay_layer, "The tutorial overlay must receive the back action"):
		return
	for pressed in [true, false]:
		var back := InputEventKey.new()
		back.keycode = KEY_ESCAPE
		back.pressed = pressed
		get_viewport().push_input(back)
		await tree.process_frame
	await tree.create_timer(0.8).timeout
	if not _check(tree.current_scene.scene_file_path == "res://MainMenu.tscn", "Back must exit the tutorial, not free its active guide panel"):
		return
	menu = tree.current_scene
	menu.start_battle_btn.pressed.emit()
	await tree.process_frame
	entry = menu.battle_hub_layer.find_choice(Locale.t("menu.advanced_tutorial"))
	entry.pressed.emit()
	await tree.scene_changed
	await tree.process_frame
	tutorial = tree.current_scene
	for index in range(Lessons.IDS.size() - 1):
		var battle: Node = tutorial._battle
		var guide: Node = battle.tutorial_controller
		var id: String = Lessons.IDS[index]
		if not _check(guide.body_label.text == Lessons.objective(id), id + " should introduce its practice objective"):
			return
		guide.next_button.pressed.emit()
		if not _check(not guide.next_button.visible, id + " should require an actual action"):
			return
		if id in ["deployment", "discard"]:
			await tree.process_frame
			if _capture_enabled():
				await _capture("advanced-tutorial-" + id + "-" + Locale.language)
			var destination: Control = battle.player_side_ui.get_child(2) if id == "deployment" else battle.discard_zone
			await _drag(battle.hand_container.get_child(0).get_global_rect().get_center(), destination.get_global_rect().get_center())
		elif id == "taunt":
			battle.tabletop_slot_clicked(false, 0)
			await tree.process_frame
			var attack := battle.card_inspector.find_child("TabletopAttack", true, false) as Button
			if not _check(is_instance_valid(attack) and not attack.disabled, "Taunt practice must offer an actual basic attack"):
				return
			attack.pressed.emit()
			battle.tabletop_slot_clicked(true, 0)
			if not _check(battle.current_attacker_idx == 0 and battle.game.player2_field.slots[0].hp == 6, "Taunt must reject an attack on the Scout"):
				return
			battle.tabletop_slot_clicked(true, 2)
		elif id == "turn":
			battle.face_mana_button.button_pressed = true
			battle.end_turn_button.pressed.emit()
			if not _check(battle.game.is_player_turn, "supplement must be off for this step"):
				return
			battle.face_mana_button.button_pressed = false
			battle.end_turn_button.pressed.emit()
		else:
			battle.tabletop_slot_clicked(false, 0)
			await tree.process_frame
			var skill := battle.card_inspector.find_child("TabletopSkill0", true, false) as Button
			if not _check(is_instance_valid(skill) and not skill.disabled, id + " must allow the guided skill"):
				return
			skill.pressed.emit()
			if id in ["targets", "damage", "control", "charm"]:
				await tree.process_frame
				if id == "targets":
					battle.tabletop_slot_clicked(true, 0)
					if not _check(battle.activate_targeting and battle.game.player2_field.slots[0].hp == 6, "wrong target must keep the aim and leave the board unchanged"):
						return
				if _capture_enabled() and id == "damage":
					await _capture("advanced-tutorial-aim-" + Locale.language)
				battle.tabletop_slot_clicked(id != "control", 2)
		var deadline := Time.get_ticks_msec() + 5000
		while not guide.next_button.visible and Time.get_ticks_msec() < deadline:
			await tree.process_frame
		if not _check(guide.next_button.visible and _matches_outcome(battle.game, id), id + " must show the actual expected outcome"):
			return
		if _capture_enabled() and id == "damage":
			await _capture("advanced-tutorial-damage-" + Locale.language)
		if _capture_enabled() and id == "charm":
			await _capture("advanced-tutorial-charm-" + Locale.language)
		guide.next_button.pressed.emit()
		await tree.process_frame
		await tree.process_frame
	var battle: Node = tutorial._battle
	var guide: Node = battle.tutorial_controller
	guide.next_button.pressed.emit()
	guide.next_button.pressed.emit()
	await tree.process_frame
	var popup := tutorial.get_node("AdvancedSettings")
	(popup.find_child("draw_per_turn", true, false) as SpinBox).value = 4
	(popup.find_child("starting_hp", true, false) as SpinBox).value = 46
	(popup.find_child("ActionTimeEnabledToggle", true, false) as CheckButton).button_pressed = false
	for node in popup.find_children("*", "Button", true, false):
		if node.text == Locale.t("common.confirm"):
			node.pressed.emit()
			break
	await tree.process_frame
	var after: String = guide.body_label.text
	var expected := "draw 4 cards, and receive 10 action points" if english else "摸到 4 张牌，有 10 行动力"
	var timer_off := "The action timer is off" if english else "限时已关闭"
	if not _check(after.contains(expected) and after.contains("46") and after.contains(timer_off), "The actual setup form must update the sample turn: " + after):
		return
	if _capture_enabled():
		await _capture("advanced-tutorial-rules-" + Locale.language)
		get_window().size = Vector2i(720, 540)
		await tree.create_timer(0.25).timeout
		var picker := tutorial.find_child("ChapterPicker", true, false) as OptionButton
		if not _check(picker.is_visible_in_tree(), "Narrow layouts must offer a chapter picker, window %s, view %s" % [get_window().size, tutorial.size]):
			return
		picker.item_selected.emit(1)
		await tree.create_timer(0.4).timeout
		var compact_guide: Node = tutorial._battle.tutorial_controller
		if not _check(get_viewport().get_visible_rect().encloses(compact_guide.instruction_panel.get_global_rect()),
			"After switching chapters the instruction panel must remain inside the compact viewport"):
			return
		await _capture("advanced-tutorial-compact-" + Locale.language)
	else:
		guide._retry.pressed.emit()
		await tree.process_frame
		await tree.process_frame
		if not _check(tutorial._battle != battle and tutorial._battle.tutorial_controller.body_label.text == Lessons.objective("custom"),
			"Retry must reload the same chapter and reset the local rules"):
			return
	tutorial._on_back_pressed()
	await tree.scene_changed
	await tree.create_timer(0.25).timeout
	menu = tree.current_scene
	var restored: Button = menu.battle_hub_layer.find_choice(Locale.t("menu.advanced_tutorial"))
	if not _check(is_instance_valid(restored) and restored.has_focus(), "Back must restore the battle hub and its entry focus"):
		return
	var same_tutorial := (FileAccess.get_sha256(PlayerData.tutorial_progress_path) if FileAccess.file_exists(PlayerData.tutorial_progress_path) else "") == tutorial_hash
	if not _check(PlayerData.battle_config == original_rules and PlayerData.battle_mode == original_mode
		and FileAccess.get_sha256(PlayerData.save_path) == collection_hash and same_tutorial,
		"Exiting the tutorial must leave game settings, collection, and basic progress intact"):
		return
	print("TEST_ADVANCED_TUTORIAL_OK lessons=%d real_drag,taunt,retry,settings,return,isolation" % Lessons.IDS.size())
	tree.quit(0)


func _matches_outcome(game: RefCounted, id: String) -> bool:
	match id:
		"deployment":
			var recruit: CardData = game.player_field.slots[2]
			return recruit != null and recruit.temp_hp == 2 and game.player_field.current_mana == 2 and game.player_hand.is_empty()
		"taunt":
			return game.player2_field.slots[0].hp == 6 and game.player2_field.slots[2].hp == 4
		"charm":
			return game.player2_field.slots[2] == null and game.player_hand.size() == 1 and game.player_hand[0].cost == 0
		"discard":
			return game.player_hand.is_empty() and game.shared_discard.size() == 1 and game.player_field.current_mana == 4
		"triggers":
			var source: CardData = game.player_field.slots[0]
			return game.player_field.action_points == 0 and game.player_field.current_mana == 2 and source.temp_hp == 0 and source.skills_used_count.is_empty()
		"targets":
			return game.player2_field.slots[0].hp == 6 and game.player2_field.slots[2].hp == 4 and game.player2_field.slots[3].hp == 4
		"damage":
			return game.player_field.slots[0].hp == 4 and game.player2_field.slots[2].hp == 4 and game.player2_field.slots[2].temp_hp == 0
		"control":
			var guard: CardData = game.player_field.slots[2]
			return guard.has_taunt() and guard.temp_hp == 2 and not guard.status_effects.any(func(status): return status.buff_id == SkillEngine.BUFF_POISON)
		"hand":
			return game.player_hand.size() == SkillEngine.MAX_HAND_SIZE and game.shared_discard.size() == 1 and game.player_field.current_mana == 3
		"turn":
			return game.current_player == 1 and not game.is_player_turn and game.player2_field.player_hp == 28
	return false


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("TEST_ADVANCED_TUTORIAL_FAILED " + message)
		get_tree().quit(1)
	return condition


func _capture_enabled() -> bool:
	return DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture")


func _capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/" + name + ".png")


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = from
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var last := from
	for fraction in [0.2, 0.5, 0.8, 1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, fraction)
		motion.relative = motion.position - last
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = motion.position
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.position = to
	release.button_index = MOUSE_BUTTON_LEFT
	get_viewport().push_input(release, true)

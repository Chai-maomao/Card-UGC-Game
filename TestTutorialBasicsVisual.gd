extends Node

var failures: Array[String] = []
var progress_path := "user://test_tutorial_basics_visual.cfg"


func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	var setup := PlayerData.battle_preparation_snapshot()
	var config := PlayerData.battle_config.duplicate(true)
	var context := PlayerData.card_playtest_context.duplicate(true)
	var language_before := Locale.language
	var created_before := PlayerData.tutorial_created_card
	var library_hash := FileAccess.get_sha256("user://card_library.json")
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	TutorialProgress.new(progress_path).clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/tutorial-basics"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			var prefix := "%s-%dx%d" % [language, dimensions.x, dimensions.y]
			await _skill_editor(viewport, prefix)
			await _battle(viewport, prefix)
		viewport.free()
	PlayerData._apply_battle_preparation(setup)
	PlayerData.battle_config = config
	PlayerData.card_playtest_context = context
	PlayerData.tutorial_created_card = created_before
	Locale.language = language_before
	TutorialProgress.new(progress_path).clear()
	_check(FileAccess.get_sha256("user://card_library.json") == library_hash, "tutorial verification must preserve the collection")
	if failures.is_empty():
		print("TEST_TUTORIAL_BASICS_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_TUTORIAL_BASICS_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _skill_editor(viewport: SubViewport, prefix: String) -> void:
	PlayerData.begin_skill_tutorial()
	var editor = preload("res://SkillEditor.tscn").instantiate()
	viewport.add_child(editor)
	await get_tree().create_timer(0.4).timeout
	var guide: SkillEditorTutorialController = editor.skill_tutorial_controller
	guide.progress_path = progress_path
	guide.navigate_on_complete = false
	_click(viewport, guide.next_button.get_global_rect().get_center())
	for letter in "Supply":
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = letter.unicode_at(0)
		viewport.push_input(key, true)
	await get_tree().process_frame
	_check(not guide.next_button.disabled, "actual skill-name input must unlock Next: " + prefix)
	_click(viewport, guide.next_button.get_global_rect().get_center())
	await _palette_focus(viewport, guide, guide._trigger_button(), prefix + "-on-summon")
	if viewport.size == Vector2i(1280, 720):
		viewport.size = Vector2i(960, 540)
		await get_tree().create_timer(0.2).timeout
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(guide.instruction_panel.get_global_rect()), "skill tutorial prompt must follow a live resize: " + prefix)
		_check(guide.focus_frames[0].visible, "trigger highlight must survive a live resize: " + prefix)
		await _save(viewport, prefix + "-live-resize")
		viewport.size = Vector2i(1280, 720)
		await get_tree().create_timer(0.2).timeout
	_click(viewport, guide._trigger_button().get_global_rect().get_center())
	await get_tree().process_frame
	_check(guide.phase == SkillEditorTutorialController.Phase.EFFECT, "real highlighted trigger must advance: " + prefix)
	_check(editor.skill_summary.text.contains(Locale.term("trigger", SkillEngine.TRIGGER_ON_SUMMON)) and editor._build_skill().is_empty(), "selected trigger preview must remain correct before effects: " + prefix)
	await _palette_focus(viewport, guide, guide._effect_button(), prefix + "-draw-cards")
	_click(viewport, guide._effect_button().get_global_rect().get_center())
	await get_tree().process_frame
	var count := guide._draw_count_input()
	_check(guide.phase == SkillEditorTutorialController.Phase.VALUE and count != null and count.editable and count.text.is_empty(),
			"the added draw block must show an empty editable count: " + prefix)
	if count != null:
		await get_tree().process_frame
		_check(not guide.instruction_panel.get_global_rect().intersects(count.get_global_rect()) and guide.focus_frames[0].visible,
				"the count prompt must leave the highlighted input visible: " + prefix)
		await _save(viewport, prefix + "-draw-count")
		_click(viewport, count.get_global_rect().get_center())
		var digit := InputEventKey.new()
		digit.unicode = 49
		digit.pressed = true
		viewport.push_input(digit, true)
		var submit := InputEventKey.new()
		submit.keycode = KEY_ENTER
		submit.pressed = true
		viewport.push_input(submit, true)
		await get_tree().process_frame
		_click(viewport, guide.next_button.get_global_rect().get_center())
	_check(guide.phase == SkillEditorTutorialController.Phase.REVIEW and editor._collect_errors().is_empty(),
			"real draw-count input must unlock the compiled preview: " + prefix)
	editor.free()
	PlayerData.cancel_skill_tutorial()


func _palette_focus(viewport: SubViewport, guide: SkillEditorTutorialController, target: Button, prefix: String) -> void:
	await get_tree().create_timer(0.15).timeout
	_move(viewport, target.get_global_rect().get_center())
	await get_tree().create_timer(0.15).timeout
	var scroll := guide._palette_scroll()
	var frame: Panel = guide.focus_frames[0]
	_check(not target.disabled and frame.visible and scroll.get_global_rect().encloses(frame.get_global_rect()), "hovered palette block must have a visible bounded highlight: " + prefix)
	_check(frame.get_global_rect().position.distance_to(target.get_global_rect().position)<1 and frame.size.distance_to(target.get_global_rect().size)<1,"tutorial highlight must match the actual block bounds: "+prefix)
	var before_y := frame.position.y
	var before_scroll := scroll.scroll_vertical
	scroll.scroll_vertical = before_scroll + 16
	await get_tree().process_frame
	await get_tree().process_frame
	if scroll.scroll_vertical != before_scroll:
		_check(not is_equal_approx(frame.position.y, before_y), "highlight must follow real block when scrolling: " + prefix)
	_check(frame.visible, "small scroll must not hide a fully visible target: " + prefix)
	await _save(viewport, prefix)
	scroll.scroll_vertical = before_scroll
	await get_tree().process_frame


func _battle(viewport: SubViewport, prefix: String) -> void:
	var trainee := CardData.new("Supply", 2, 6, 3, [{"skill_name": "Supply", "trigger": "on_summon", "effects": [{"effect": "draw_cards", "target": "self", "value": 1}]}])
	PlayerData.prepare_tutorial_battle(trainee)
	var battle = preload("res://Main.tscn").instantiate()
	viewport.add_child(battle)
	await get_tree().create_timer(0.4).timeout
	var guide: BattleTutorialController = battle.tutorial_controller
	guide.progress_path = progress_path
	var initial_hash := BattleRepro.state_hash(battle.game)
	for phase in range(BattleTutorialController.Phase.SUMMON):
		_check(guide.phase == phase, "orientation must advance one actual Next click at a time: " + prefix)
		await _guide_layout(viewport, guide, prefix + "-" + str(phase))
		_click(viewport, guide.next_button.get_global_rect().get_center())
		await get_tree().process_frame
	_check(BattleRepro.state_hash(battle.game) == initial_hash, "reading orientation must preserve the game: " + prefix)
	await _guide_layout(viewport, guide, prefix + "-summon")
	var hand_ui: Control = battle.hand_container.get_child(0)
	_drag(viewport, hand_ui.get_global_rect().get_center(), battle._my_slots_ui()[2].get_global_rect().get_center())
	await _settle(battle)
	_check(guide.phase == BattleTutorialController.Phase.SKILL and battle.game.player_field.slots[2] != null and battle.game.player_hand.size() == 1, "actual drag must summon and draw once: " + prefix)
	if guide.phase != BattleTutorialController.Phase.SKILL:
		battle.free()
		return
	_check(battle.game.player_field.current_mana == 3 and battle.game.player_field.action_points == 11 and battle.game.player_field.actions_taken == 0, "deployment and draw must preserve the fixed AP budget: " + prefix)
	await _guide_layout(viewport, guide, prefix + "-skill")
	_click(viewport, guide.next_button.get_global_rect().get_center())
	await _guide_layout(viewport, guide, prefix + "-stats")
	_click(viewport, guide.next_button.get_global_rect().get_center())
	await _guide_layout(viewport, guide, prefix + "-attack")
	var unit_ui = battle._my_slots_ui()[2].current_card_ui
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,unit_ui)
	await get_tree().process_frame
	_check(guide.phase == BattleTutorialController.Phase.ATTACK_TARGET, "real Attack must open target selection: " + prefix)
	_click(viewport, battle._their_slots_ui()[2].get_global_rect().get_center())
	await _settle(battle)
	_check(guide.phase == BattleTutorialController.Phase.COMBAT_RESULT and battle.game.player2_field.slots[2].hp == 3, "real attack result must feed the guide: " + prefix)
	await _guide_layout(viewport, guide, prefix + "-result")
	_click(viewport, guide.next_button.get_global_rect().get_center())
	await _guide_layout(viewport, guide, prefix + "-face")
	_click(viewport, guide.next_button.get_global_rect().get_center())
	await _guide_layout(viewport, guide, prefix + "-end-turn")
	_click(viewport, battle.end_turn_button.get_global_rect().get_center())
	await _settle(battle)
	_check(guide.phase == BattleTutorialController.Phase.COMPLETE, "real End Turn must complete the guide: " + prefix)
	await _guide_layout(viewport, guide, prefix + "-complete")
	battle.free()


func _guide_layout(viewport: SubViewport, guide: BattleTutorialController, prefix: String) -> void:
	await get_tree().create_timer(0.12).timeout
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var panel := guide.instruction_panel.get_global_rect()
	_check(screen.encloses(panel), "instruction panel must fit: " + prefix)
	for control in [guide.body_label, guide.title_label, guide.next_button, guide.exit_button]:
		_check(panel.encloses(control.get_global_rect()), "tutorial copy and navigation must fit: %s (%s, panel=%s, control=%s)" % [
			prefix, control.name, panel, control.get_global_rect()])
	for frame in guide.focus_frames:
		_check(frame.visible and screen.encloses(frame.get_global_rect()), "focus must be visible and inside viewport: " + prefix)
		_check(not panel.intersects(frame.get_global_rect()), "instruction panel must leave the highlighted element visible: " + prefix)
		var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
		_check(style.bg_color.a == 0 and style.shadow_size == 0, "highlight must preserve card-face readability: " + prefix)
	if guide.phase == BattleTutorialController.Phase.CARD_STATS:
		for i in range(guide.focus_frames.size()):
			for j in range(i + 1, guide.focus_frames.size()):
				_check(not guide.focus_frames[i].get_global_rect().intersects(guide.focus_frames[j].get_global_rect()), "stat outlines must not overlap adjacent values: %s %s %s" % [prefix, guide.focus_frames[i].get_global_rect(), guide.focus_frames[j].get_global_rect()])
	_check(not guide.body_label.text.contains("tutorial."), "tutorial copy must be localized: " + prefix)
	await _save(viewport, prefix)


func _settle(battle: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	# A click can queue feedback for the next frame before the animation locks input.
	await get_tree().process_frame
	while (battle.is_resolution_locked() or battle._turn_ending or (battle.splash_tween != null and battle.splash_tween.is_running())) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	_check(not battle.is_resolution_locked() and not battle._turn_ending,
			"tutorial input must unlock after real feedback (phase=%s, resolving=%s, HP feedback=%s, ending turn=%s)" % [
				battle.tutorial_controller.phase, battle._resolution_running, battle._hp_feedback_running, battle._turn_ending])


func _save(viewport: SubViewport, prefix: String) -> void:
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/tutorial-basics/" + prefix + ".png") == OK, "tutorial screenshot must save")


func _move(viewport: SubViewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	viewport.push_input(event, true)


func _click(viewport: SubViewport, point: Vector2) -> void:
	_move(viewport, point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)


func _drag(viewport: SubViewport, from: Vector2, to: Vector2) -> void:
	_move(viewport, from)
	var press := InputEventMouseButton.new()
	press.position = from
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	for fraction in [0.1, 0.35, 0.7, 1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, fraction)
		motion.relative = (to - from) * 0.25
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion, true)
	press = InputEventMouseButton.new()
	press.position = to
	press.button_index = MOUSE_BUTTON_LEFT
	viewport.push_input(press, true)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

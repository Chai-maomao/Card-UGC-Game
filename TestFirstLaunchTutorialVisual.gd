extends Node

var failures: Array[String] = []
var path := "res://artifacts/first-launch/visual-progress.cfg"
var _flow_viewport: SubViewport
var _embedded_scene: Node


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/first-launch"))
	var language_before := Locale.language
	var contrast_before: bool = AppPreferences.get_value("high_contrast")
	var path_before := PlayerData.tutorial_progress_path
	var existing_before := PlayerData.had_saved_library_on_startup
	var library_hash := FileAccess.get_sha256(PlayerData.save_path)
	PlayerData.tutorial_progress_path = path
	var progress := TutorialProgress.new(path)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			progress.clear()
			_check(progress.initialize_startup(false) == OK, "visual first-launch fixture must persist")
			PlayerData.startup_tutorial_pending = true
			var menu = preload("res://MainMenu.tscn").instantiate()
			viewport.add_child(menu)
			await get_tree().create_timer(0.6).timeout
			var guide: TitleTutorialController = menu.title_tutorial_controller
			var prefix := "%s-%dx%d" % [language, dimensions.x, dimensions.y]
			# Click and keyboard activation must not reach a disabled menu entry.
			await _click(menu.card_editor_btn)
			_check(guide.phase == TitleTutorialController.Phase.WELCOME and not PlayerData.skill_tutorial_active, "backdrop must block premature navigation")
			for step in range(TitleTutorialController.Phase.size()):
				_check(guide.phase == step, "real Next must advance the title introduction")
				await _layout(viewport, guide, prefix + "-%d" % step)
				if step == TitleTutorialController.Phase.CONTRAST:
					_check(guide.next_button.disabled, "Next must wait for the player to choose")
					await _click(guide.high_contrast_button)
					var high_border: Color = guide.next_button.get_theme_stylebox("normal").border_color
					_check(guide.high_contrast_button.button_pressed and AppPreferences.get_value("high_contrast"), "click must select and apply high contrast")
					await _save(viewport, prefix + "-contrast-high")
					await _click(guide.low_contrast_button)
					_check(guide.low_contrast_button.button_pressed and not guide.high_contrast_button.button_pressed
							and not AppPreferences.get_value("high_contrast"), "click must switch to low contrast and clear the other selection")
					_check(guide.next_button.get_theme_stylebox("normal").border_color != high_border, "switching contrast must update the rendered controls")
					await _save(viewport, prefix + "-contrast-low")
				if step < TitleTutorialController.Phase.CREATE:
					await _click(guide.next_button)
			if dimensions.x == 1280:
				viewport.size = Vector2i(960, 540)
				await get_tree().create_timer(0.3).timeout
				await _layout(viewport, guide, prefix + "-resized")
				viewport.size = dimensions
				await get_tree().create_timer(0.3).timeout
			await _click(guide.skip_button)
			_check(menu.title_tutorial_controller == null and not menu.start_battle_btn.disabled and progress.status() == "skipped", "real Skip must restore navigation and persist")
			menu.free()
		viewport.free()

	# Keep this QA host alive while actual Bootstrap/UIMotion scene changes run.
	get_tree().current_scene = null
	# A native Window samples the physical OS cursor for background clicks.
	# Embed the menu and battle in a viewport whose pointer is driven by the
	# synthetic input, while preserving Bootstrap and UIMotion routing.
	_flow_viewport = SubViewport.new()
	_flow_viewport.size = Vector2i(1152, 648)
	_flow_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_flow_viewport)
	Locale.language = "zh"
	progress.clear()
	PlayerData.had_saved_library_on_startup = false
	var bootstrap = preload("res://Bootstrap.gd").new()
	add_child(bootstrap)
	var menu = await _wait_scene("MainMenu")
	if menu == null: return
	bootstrap.free()
	var guide: TitleTutorialController = menu.title_tutorial_controller
	_check(guide != null and progress.status() == "in_progress", "real Bootstrap must automatically open the first-launch guide")
	for step in range(TitleTutorialController.Phase.size()):
		if step == TitleTutorialController.Phase.CONTRAST:
			await _click(guide.low_contrast_button)
		await _click(guide.next_button)
	var card_editor = await _wait_scene("CardEditor")
	if card_editor == null: return
	_check(card_editor.card_tutorial_controller != null and card_editor.card_tutorial_controller.progress_path == path, "title CTA must route to the real isolated full-card tutorial")
	await _click(card_editor.card_tutorial_controller.next_button)
	var art_guide: CardEditorTutorialController = card_editor.card_tutorial_controller
	var upload_rect: Rect2 = card_editor.browse_button.get_global_rect()
	var form_rect := art_guide._editor_scroll().get_global_rect()
	_check(art_guide.phase == CardEditorTutorialController.Phase.ART and form_rect.encloses(upload_rect),
		"the art step must bring the whole upload area into view")
	_check(art_guide.focus_frames.size() == 1 and art_guide.focus_frames[0].get_global_rect().is_equal_approx(upload_rect.grow(6.0)),
		"the art step must highlight the upload area itself")
	await _save(card_editor.get_viewport(), "end-to-end-card-art")
	await _click(card_editor.card_tutorial_controller.next_button)
	await _type(card_editor.name_input, "First Card")
	for step in range(3): await _click(card_editor.card_tutorial_controller.next_button)
	await _click(card_editor.edit_skill1_btn)
	var skill_editor = await _wait_scene("SkillEditor")
	if skill_editor == null: return
	var skill_guide: SkillEditorTutorialController = skill_editor.skill_tutorial_controller
	_check(skill_guide != null and skill_guide.progress_path == path, "skill chapter must share first-launch progress")
	await _click(skill_guide.next_button)
	await _type(skill_editor.skill_name_input, "First Supply")
	await _click(skill_guide.next_button)
	await get_tree().create_timer(0.3).timeout
	await _click(skill_guide._trigger_button())
	await get_tree().create_timer(0.3).timeout
	await _click(skill_guide._effect_button())
	var draw_count := skill_guide._draw_count_input()
	await _type(draw_count, "1")
	var submit := InputEventKey.new()
	submit.keycode = KEY_ENTER
	submit.pressed = true
	_push(draw_count.get_viewport(), submit)
	await get_tree().process_frame
	await _click(skill_guide.next_button)
	await _click(skill_guide.next_button)
	await _click(skill_editor.save_button)
	card_editor = await _wait_scene("CardEditor")
	if card_editor == null: return
	_check(card_editor.card_tutorial_controller.phase == CardEditorTutorialController.Phase.REVIEW, "real save must return to full-card review")
	await _click(card_editor.card_tutorial_controller.next_button)
	await _click(card_editor.save_button)
	var battle = await _wait_scene("Main")
	if battle == null: return
	var battle_guide: BattleTutorialController = battle.tutorial_controller
	_check(battle_guide != null and battle_guide.progress_path == path and progress.editor_completed(), "card confirmation must persist its chapter and enter the battlefield")
	for step in range(BattleTutorialController.Phase.SUMMON): await _click(battle_guide.next_button)
	await _save(_flow_viewport, "end-to-end-summon")
	var hand_card: Control = battle.hand_container.get_child(0)
	await _drag(_flow_viewport, hand_card.get_global_rect().get_center(), battle._my_slots_ui()[2].get_global_rect().get_center())
	await get_tree().create_timer(1.5).timeout
	_check(battle_guide.phase == BattleTutorialController.Phase.SKILL and battle.game.player_hand.size() == 1, "real guided deployment must automatically draw a replacement card")
	if battle._my_slots_ui()[2].current_card_ui == null:
		push_error("TEST_FIRST_LAUNCH_TUTORIAL_VISUAL_FAILED: the tutorial card did not land in the highlighted slot (phase %d)" % battle_guide.phase)
		get_tree().quit(1)
		return
	await _click(battle_guide.next_button)
	await _click(battle_guide.next_button)
	await preload("res://tests/VisualBattleInput.gd").action(_flow_viewport,battle,battle._my_slots_ui()[2].current_card_ui)
	await _click(battle._their_slots_ui()[2])
	await get_tree().create_timer(1.5).timeout
	_check(battle_guide.phase == BattleTutorialController.Phase.COMBAT_RESULT, "real attack must feed the battle tutorial")
	for step in range(2): await _click(battle_guide.next_button)
	await _click(battle.end_turn_button)
	await get_tree().create_timer(2.0).timeout
	_check(progress.status() == "completed" and not progress.needs_startup_tutorial(), "end-to-end first launch must finish the persistent marker")
	await _save(_flow_viewport, "end-to-end-complete")
	await _click(battle_guide.exit_button)
	menu = await _wait_scene("MainMenu")
	if menu == null: return
	_check(menu.title_tutorial_controller == null, "completion must return to the ordinary menu without looping")
	_check(FileAccess.get_sha256(PlayerData.save_path) == library_hash, "the entire first-launch flow must preserve the actual collection")
	progress.clear()
	PlayerData.tutorial_progress_path = path_before
	PlayerData.had_saved_library_on_startup = existing_before
	PlayerData.startup_tutorial_pending = false
	Locale.language = language_before
	AppPreferences.set_value("high_contrast", contrast_before)
	if failures.is_empty():
		print("TEST_FIRST_LAUNCH_TUTORIAL_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_FIRST_LAUNCH_TUTORIAL_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _layout(viewport: SubViewport, guide: TitleTutorialController, prefix: String) -> void:
	await get_tree().create_timer(0.15).timeout
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var panel := guide.instruction_panel.get_global_rect()
	_check(screen.encloses(panel), "title prompt must fit: " + prefix)
	for control in [guide.step_label, guide.title_label, guide.body_label, guide.next_button, guide.skip_button]:
		_check(panel.encloses(control.get_global_rect()), "title copy and actions must fit: " + prefix)
	if guide.phase != TitleTutorialController.Phase.CONTRAST:
		_check(screen.encloses(guide.focus_frame.get_global_rect()) and not panel.intersects(guide.focus_frame.get_global_rect()), "highlighted title element must remain visible: " + prefix)
		for dim in guide._dim_rects:
			_check(not dim.get_global_rect().intersects(guide.focus_frame.get_global_rect()), "dimming must leave the current target readable: " + prefix)
	if guide.phase >= TitleTutorialController.Phase.COLLECTION:
		var target: Button = [guide.menu.my_cards_btn, guide.menu.start_battle_btn, guide.menu.card_editor_btn][guide.phase - TitleTutorialController.Phase.COLLECTION]
		_check(target.disabled and target.get_theme_color("font_disabled_color") == target.get_theme_color("font_color"), "modal gating must preserve target label contrast: " + prefix)
	_check(guide.menu.title_label.texture != null and guide.menu.title_label.is_visible_in_tree() and not guide.body_label.text.contains("tutorial."), "title artwork and localized guidance must remain intact")
	var focusable := [guide.next_button, guide.skip_button]
	if guide.phase == TitleTutorialController.Phase.CONTRAST:
		focusable.append_array([guide.high_contrast_button, guide.low_contrast_button])
		_check(panel.encloses(guide.high_contrast_button.get_global_rect()) and panel.encloses(guide.low_contrast_button.get_global_rect()),
				"both contrast options must fit: " + prefix)
	_check(viewport.gui_get_focus_owner() in focusable, "keyboard focus must remain in the mandatory guide")
	await _save(viewport, prefix)


func _wait_scene(name: String) -> Node:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://" + name + ".tscn":
			# Reparented scenes are now owned by the fixture, so retire their input layers here.
			if is_instance_valid(_embedded_scene) and _embedded_scene != scene:
				_embedded_scene.queue_free()
				_embedded_scene = null
			if name in ["MainMenu", "Main"]:
				scene.reparent(_flow_viewport)
				_embedded_scene = scene
			await get_tree().create_timer(0.6).timeout
			return scene
		await get_tree().process_frame
	push_error("TEST_FIRST_LAUNCH_TUTORIAL_VISUAL_FAILED: could not reach real scene " + name)
	get_tree().quit(1)
	return null


func _save(viewport: Viewport, prefix: String) -> void:
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/first-launch/" + prefix + ".png") == OK, "screenshot must save")


func _click(control: Control) -> void:
	var viewport := control.get_viewport()
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	_push(viewport, move)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		_push(viewport, event)
	await get_tree().create_timer(0.2).timeout


func _type(control: Control, value: String) -> void:
	await _click(control)
	var viewport := control.get_viewport()
	for letter in value:
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = letter.unicode_at(0)
		_push(viewport, key)
	await get_tree().process_frame


func _drag(viewport: Viewport, start: Vector2, finish: Vector2) -> void:
	var hover := InputEventMouseMotion.new()
	hover.position = start
	_push(viewport, hover)
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	_push(viewport, press)
	await get_tree().process_frame
	var previous := start
	for fraction in [0.1, 0.35, 0.7, 1.0]:
		var move := InputEventMouseMotion.new()
		move.position = start.lerp(finish, fraction)
		move.relative = move.position - previous
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		_push(viewport, move)
		previous = move.position
		await get_tree().process_frame
	press = InputEventMouseButton.new()
	press.position = finish
	press.button_index = MOUSE_BUTTON_LEFT
	_push(viewport, press)


func _push(viewport: Viewport, event: InputEvent) -> void:
	if viewport is Window:
		if event is InputEventMouse:
			event.position = viewport.get_final_transform() * event.position
			event.global_position = event.position
		Input.parse_input_event(event)
	else:
		viewport.push_input(event, true)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

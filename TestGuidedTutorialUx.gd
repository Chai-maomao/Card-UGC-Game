extends Node

const CardEditorScene = preload("res://CardEditor.tscn")
const SkillEditorScene = preload("res://SkillEditor.tscn")
const BattleScene = preload("res://Main.tscn")
const CardGuide = preload("res://CardEditorTutorialController.gd")
const SkillGuide = preload("res://SkillEditorTutorialController.gd")
const BattleGuide = preload("res://BattleTutorialController.gd")
const ProgressStore = preload("res://TutorialProgress.gd")

var failures: Array[String] = []
var progress_path := "user://test_guided_tutorial_progress.cfg"


func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)


func _ready() -> void:
	ProgressStore.new(progress_path).clear()
	var original_draft := {"card_type": "minion", "name": "KEEP-ME", "cost": 4, "hp": 7, "atk": 2}
	PlayerData.card_draft = original_draft.duplicate(true)
	PlayerData.editing_index = 12
	PlayerData.editing_skill_index = 2
	PlayerData.begin_card_tutorial()
	_assert(PlayerData.skill_tutorial_active, "full-card tutorial must start with an isolated editor session")
	_assert(PlayerData.card_draft.get("name", "") == "", "full-card tutorial must let the player name the card")

	var card_editor = CardEditorScene.instantiate()
	add_child(card_editor)
	await _settle()
	var card_tutorial = card_editor.card_tutorial_controller
	card_tutorial.progress_path = progress_path
	card_tutorial.navigate_on_complete = false
	_assert(card_tutorial != null and card_tutorial.phase == CardGuide.Phase.INTRO, "tutorial must begin in the real card editor")
	_assert(not card_tutorial.focus_frames.is_empty()
			and card_tutorial.instruction_panel.z_index > card_tutorial.focus_frames[0].z_index,
			"card tutorial prompt must render above its highlight frames")
	card_tutorial._on_next()
	card_tutorial._on_next()
	card_editor.name_input.text = "星辉学徒"
	card_editor.gender_select.select(2)
	card_editor._update_balance_from_form()
	_assert(not card_tutorial.next_button.disabled, "a non-empty card name must unlock identity step")
	card_tutorial._on_next()
	card_editor.cost_input.value = 2
	card_editor.hp_input.value = 6
	card_editor.atk_input.value = 3
	card_editor._update_balance_from_form()
	_assert(not card_tutorial.next_button.disabled, "summonable combat stats must unlock stat step")
	card_tutorial._on_next()
	card_tutorial._on_next()
	_assert(card_tutorial.phase == CardGuide.Phase.SKILL, "full-card flow must reach the first-skill action")
	card_tutorial.notify_edit_skill(0)
	card_editor._save_form_to_draft()
	card_editor.queue_free()
	await _settle()

	var skill_editor = SkillEditorScene.instantiate()
	add_child(skill_editor)
	await _settle()
	var skill_tutorial: SkillEditorTutorialController = skill_editor.skill_tutorial_controller
	skill_tutorial.progress_path = progress_path
	skill_tutorial.navigate_on_complete = false
	_assert(skill_tutorial != null and skill_tutorial.phase == SkillGuide.Phase.INTRO, "skill chapter must use the real skill editor")
	_assert(not skill_tutorial.focus_frames.is_empty()
			and skill_tutorial.instruction_panel.z_index > skill_tutorial.focus_frames[0].z_index,
			"skill tutorial prompt must render above its highlight frames")
	for button in skill_editor.palette_vbox.find_children("*","Button",true,false):
		if button is SkillPaletteBlock and button.effect_id==SkillEngine.EFFECT_VIEW_DECK:
			_assert(button.disabled and button.get_theme_color("font_disabled_color").a<0.6,"deck selection must be dimmed like the other unavailable tutorial blocks")
	var colored_block := skill_tutorial._effect_button()
	var normal_style := colored_block.get_theme_stylebox("normal")
	var disabled_style := colored_block.get_theme_stylebox("disabled")
	var normal_color: Color = normal_style.bg_color if normal_style is StyleBoxFlat else normal_style.fill
	var disabled_color: Color = disabled_style.bg_color if disabled_style is StyleBoxFlat else disabled_style.fill
	_assert(colored_block.disabled, "non-current palette blocks must remain functionally unavailable")
	_assert(normal_style.get_script() == disabled_style.get_script() and normal_color.is_equal_approx(disabled_color),
			"disabled tutorial blocks must preserve their original category colour")

	skill_tutorial._on_next()
	await _settle()
	_assert(not skill_tutorial.instruction_panel.get_global_rect().intersects(skill_editor.skill_name_input.get_global_rect().grow(6)),
			"name step must leave the actual skill name input unobstructed")
	skill_editor.skill_name_input.text = "星辉补给"
	skill_editor._on_skill_name_changed(skill_editor.skill_name_input.text)
	skill_tutorial._on_next()
	await _settle()
	await _settle()
	_assert(not skill_tutorial.focus_frames.is_empty() and skill_tutorial.focus_frames[0].visible,
			"On Summon guide must remain visible for the actual palette button")
	_assert(not skill_editor.palette_search.editable, "guided palette search must not hide the required block")
	skill_editor._select_trigger(SkillEngine.TRIGGER_ON_ACTIVATE)
	_assert(skill_tutorial.phase == SkillGuide.Phase.TRIGGER and skill_editor.current_trigger_key != SkillEngine.TRIGGER_ON_ACTIVATE,
			"wrong trigger must be blocked without advancing")
	skill_editor._select_trigger(SkillEngine.TRIGGER_ON_SUMMON)
	_assert(skill_tutorial.phase == SkillGuide.Phase.EFFECT, "real On Summon block must advance the guide")
	_assert(skill_editor.skill_summary.text.contains(Locale.term("trigger", SkillEngine.TRIGGER_ON_SUMMON)) and skill_editor._build_skill().is_empty(),
			"incomplete preview must show selected On Summon while compilation still rejects missing effects")
	await _settle()
	await _settle()
	_assert(not skill_tutorial.focus_frames.is_empty() and skill_tutorial.focus_frames[0].visible,
			"Draw Cards guide must remain visible for the actual palette block")
	var palette_scroll := skill_editor.palette_vbox.get_parent() as ScrollContainer
	var frame_before := skill_tutorial.focus_frames[0].position.y
	var scroll_before := palette_scroll.scroll_vertical
	palette_scroll.scroll_vertical = maxi(0, scroll_before - 36)
	await _settle()
	if palette_scroll.scroll_vertical != scroll_before:
		_assert(not is_equal_approx(skill_tutorial.focus_frames[0].position.y, frame_before),
				"palette guide frame must move together with its block while scrolling")
	skill_editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
	_assert(skill_editor.effect_data.is_empty(), "unrelated effects must remain blocked")
	skill_editor._add_effect_block(SkillEngine.EFFECT_DRAW_CARDS)
	_assert(skill_tutorial.phase == SkillGuide.Phase.VALUE and skill_editor.effect_data.size() == 1,
			"Draw Cards must be assembled into the real script")
	await _settle()
	var count_input := skill_tutorial._draw_count_input()
	_assert(count_input != null and count_input.editable and count_input.text.is_empty() and skill_tutorial.next_button.disabled,
			"the guide must highlight an editable empty count and wait for input")
	if count_input != null:
		_assert(not skill_tutorial.instruction_panel.get_global_rect().intersects(count_input.get_global_rect()),
				"the count prompt must leave the field unobstructed")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/first-launch"))
			var image := get_viewport().get_texture().get_image()
			_assert(image.save_png("res://artifacts/first-launch/skill-draw-count.png") == OK,
					"the count step must render for visual inspection")
		count_input.text = "1"
		count_input.text_submitted.emit(count_input.text)
	_assert(not skill_tutorial.next_button.disabled, "committing one card must unlock the preview")
	skill_tutorial._on_next()
	await _settle()
	_assert(not skill_tutorial.instruction_panel.get_global_rect().intersects(skill_editor.workbench.preview_section.get_global_rect().grow(6)),
			"review step must leave the compiled preview unobstructed")
	skill_tutorial._on_next()
	await _settle()
	_assert(not skill_tutorial.instruction_panel.get_global_rect().intersects(skill_editor.save_button.get_global_rect().grow(6)),
			"save step must leave the actual save button unobstructed")
	_assert(skill_editor._collect_errors().is_empty(), "guided skill must pass existing compiler validation")
	for block in skill_editor.palette_vbox.get_children():
		if block.get("effect_id") == SkillEngine.EFFECT_VIEW_DECK:
			palette_scroll.ensure_control_visible(block)
	await _settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/tutorial-palette-dim.png")
	skill_editor._on_save_pressed()
	_assert(PlayerData.skill_tutorial_active and PlayerData.tutorial_editor_stage == "card_review",
			"saving a skill must return its data to the same tutorial card")
	_assert(not PlayerData.card_draft.get("skill1", {}).is_empty(), "saved tutorial skill must be attached to card draft")
	skill_editor.queue_free()
	await _settle()

	card_editor = CardEditorScene.instantiate()
	add_child(card_editor)
	await _settle()
	card_tutorial = card_editor.card_tutorial_controller
	card_tutorial.progress_path = progress_path
	card_tutorial.navigate_on_complete = false
	_assert(card_tutorial.phase == CardGuide.Phase.REVIEW, "returning from skill editor must resume at full-card review")
	_assert(card_editor.name_input.text == "星辉学徒", "card fields must survive the skill-editor round trip")
	card_tutorial._on_next()
	card_editor._on_save_button_pressed()
	var created := PlayerData.tutorial_created_card
	_assert(created != null and created.card_name == "星辉学徒" and created.cost == 2 and created.max_hp == 6 and created.atk == 3,
			"confirmation must build a CardData matching player input")
	_assert(created != null and created.skills.size() == 1 and str(created.skills[0].get("trigger", "")) == SkillEngine.TRIGGER_ON_SUMMON,
			"confirmed card must retain the compiled summon skill")
	_assert(ProgressStore.new(progress_path).editor_completed(), "full-card editor chapter completion must persist")
	_assert(not PlayerData.skill_tutorial_active and PlayerData.battle_mode == "tutorial", "card confirmation must hand off to tutorial battle")
	_assert(PlayerData.card_draft == original_draft and PlayerData.editing_index == 12 and PlayerData.editing_skill_index == 2,
			"tutorial must restore the player's original draft and editing context")
	_assert(PlayerData.battle_deck.size() == CardDatabase.beginner_deck().size() + 1,
			"tutorial player deck must be one starter set plus the custom card")
	card_editor.queue_free()
	await _settle()

	var battle = BattleScene.instantiate()
	add_child(battle)
	await _settle()
	var battle_tutorial: BattleTutorialController = battle.tutorial_controller
	if battle_tutorial == null:
		failures.append("card confirmation must install the tutorial battle controller")
		for failure in failures:
			push_error("TEST_GUIDED_TUTORIAL_UX_FAILED: " + failure)
		get_tree().quit(1)
		return
	battle_tutorial.progress_path = progress_path
	_assert(battle.game.turn_number == 1 and battle.game.player_hand.size() == 1,
			"custom tutorial card must be guaranteed in the first-turn hand")
	var trainee: CardData = battle.game.player_hand[0]
	_assert(trainee.card_name == "星辉学徒", "opening tutorial hand must contain the player's exact custom card")
	var duplicate_count := 0
	for card in battle.game.shared_deck:
		if (card as CardData).card_name == trainee.card_name:
			duplicate_count += 1
	_assert(duplicate_count == 0, "custom tutorial card must not be duplicated in the draw pile")
	battle_tutorial._on_next()
	_assert(not battle_tutorial.focus_frames.is_empty()
			and battle_tutorial.instruction_panel.z_index > battle_tutorial.focus_frames[0].z_index,
			"battle tutorial prompt must render above its highlight frames")
	_advance_to(battle_tutorial, BattleGuide.Phase.SUMMON)
	battle._on_card_drag_summoned(trainee, null, 2)
	_assert(trainee.skills_used.has(0), "tutorial summon skill must resolve automatically")
	battle_tutorial._on_next()
	battle_tutorial._on_next()
	battle._on_attack_requested(2)
	var target: CardData = battle.game.player2_field.slots[2]
	var target_hp := target.hp
	battle._on_enemy_slot_clicked(2)
	_assert(target.hp < target_hp, "custom card must use the real first-turn tutorial attack path")
	_advance_to(battle_tutorial, BattleGuide.Phase.END_TURN)
	battle._on_end_turn_pressed()
	var deadline := Time.get_ticks_msec() + 10000
	while battle_tutorial.phase != BattleGuide.Phase.COMPLETE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_assert(battle_tutorial.phase == BattleGuide.Phase.COMPLETE, "guided battle actions must reach the exit/continue choice: phase=%s turn_ending=%s deployment=%s resolution=%s playback=%s batches=%s arrivals=%s" % [battle_tutorial.phase,battle._turn_ending,battle._deployment_feedback_delay(),battle.is_resolution_locked(),battle._turn_request_playback_pending(),battle._hp_feedback_batches.size(),battle.hand_container.get_children().map(func(card): return card.get_meta("tabletop_arriving",false))])
	_assert(battle_tutorial.next_button.text == Locale.t("tutorial.continue_battle")
			and battle_tutorial.next_button.custom_minimum_size.x >= 164,
			"continue battle choice must be fully legible")
	_assert(not battle_tutorial.skip_button.visible
			and battle_tutorial.exit_button.text == Locale.t("tutorial.exit_tutorial")
			and battle_tutorial.exit_button.custom_minimum_size.x >= 96,
			"completed tutorial must show a clear exit choice without a skip-button trap")
	battle_tutorial._continue_battle()
	deadline = Time.get_ticks_msec() + 10000
	while (battle.game.current_player != 1 or battle.game.turn_number < 2 or battle.practice_ai_running) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_assert(PlayerData.battle_mode == "practice" and battle.tutorial_controller == null,
			"continue must preserve battle state and remove tutorial restrictions")
	_assert(battle._tutorial_allows("summon", {"slot": 0}), "free play must allow ordinary battle actions")
	_assert(battle.game.current_player == 1 and battle.game.turn_number >= 2,
			"continue must let the practice AI take its turn and return control to the player")

	battle.queue_free()
	await _settle()
	PlayerData.clear_battle_preparation()
	ProgressStore.new(progress_path).clear()
	NetworkManager.close_connection()
	await _test_card_guide_close_lifecycle()
	if failures.is_empty():
		print("TEST_GUIDED_TUTORIAL_UX_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_GUIDED_TUTORIAL_UX_FAILED: %s" % failure)
		get_tree().quit(1)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _advance_to(guide: BattleTutorialController, expected: int) -> void:
	for _step in range(BattleGuide.Phase.size()):
		if guide.phase == expected: return
		if guide.next_button.disabled: break
		guide._on_next()
	_assert(guide.phase == expected, "battle guide must reach its expected next action")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_card_guide_close_lifecycle() -> void:
	for route in ["escape","removed_overlay"]:
		PlayerData.begin_card_tutorial()
		var ui = CardEditorScene.instantiate()
		add_child(ui)
		await _settle()
		var guide = ui.card_tutorial_controller
		guide.navigate_on_complete = false
		# Leave a delayed focus refresh pending while the layer closes.
		guide.set_phase(CardGuide.Phase.ART)
		if route=="escape":
			UIMotion.register_popup(guide.overlay_layer)
			_assert(UIMotion.close_top_popup(),"Escape's popup dispatch must find the editor tutorial")
		else: guide.overlay_layer.queue_free()
		await _settle()
		await _settle()
		_assert(guide.focus_frames.is_empty() and not guide.is_processing(),"closing tutorial must stop focus refresh: "+route)
		if route=="escape": _assert(not PlayerData.skill_tutorial_active,"Escape must cancel the tutorial rather than delete just its view")
		guide.set_process(false)
		ui.queue_free()
		await _settle()
		PlayerData.cancel_skill_tutorial()

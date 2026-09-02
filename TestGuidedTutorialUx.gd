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
	var colored_block := skill_tutorial._effect_button()
	var normal_style := colored_block.get_theme_stylebox("normal") as StyleBoxFlat
	var disabled_style := colored_block.get_theme_stylebox("disabled") as StyleBoxFlat
	_assert(colored_block.disabled, "non-current palette blocks must remain functionally unavailable")
	_assert(normal_style != null and disabled_style != null and normal_style.bg_color.is_equal_approx(disabled_style.bg_color),
			"disabled tutorial blocks must preserve their original category colour")

	skill_tutorial._on_next()
	skill_editor.skill_name_input.text = "星辉补给"
	skill_editor._on_skill_name_changed(skill_editor.skill_name_input.text)
	skill_tutorial._on_next()
	skill_editor._select_trigger(SkillEngine.TRIGGER_ON_ACTIVATE)
	_assert(skill_tutorial.phase == SkillGuide.Phase.TRIGGER and skill_editor.current_trigger_key != SkillEngine.TRIGGER_ON_ACTIVATE,
			"wrong trigger must be blocked without advancing")
	skill_editor._select_trigger(SkillEngine.TRIGGER_ON_SUMMON)
	_assert(skill_tutorial.phase == SkillGuide.Phase.EFFECT, "real On Summon block must advance the guide")
	await _settle()
	var palette_scroll := skill_editor.get_node("Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteScroll") as ScrollContainer
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
	_assert(skill_tutorial.phase == SkillGuide.Phase.REVIEW and skill_editor.effect_data.size() == 1,
			"Draw Cards must be assembled into the real script")
	skill_tutorial._on_next()
	_assert(skill_editor._collect_errors().is_empty(), "guided skill must pass existing compiler validation")
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
	_assert(PlayerData.battle_deck.size() == CardDatabase.player_starters().size() + 1,
			"tutorial player deck must be one starter set plus the custom card")
	card_editor.queue_free()
	await _settle()

	var battle = BattleScene.instantiate()
	add_child(battle)
	await _settle()
	var battle_tutorial: BattleTutorialController = battle.tutorial_controller
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
	battle_tutorial._on_next()
	battle._on_card_drag_summoned(trainee, null, 2)
	battle._on_skill_activated(2, 0)
	battle._on_attack_requested(2)
	var target: CardData = battle.game.player2_field.slots[2]
	var target_hp := target.hp
	battle._on_enemy_slot_clicked(2)
	_assert(target.hp < target_hp, "custom card must use the real first-turn tutorial attack path")
	battle._on_end_turn_pressed()
	await get_tree().create_timer(0.8).timeout
	_assert(battle_tutorial.phase == BattleGuide.Phase.COMPLETE, "guided battle actions must reach the exit/continue choice")
	_assert(battle_tutorial.next_button.text == Locale.t("tutorial.continue_battle")
			and battle_tutorial.next_button.custom_minimum_size.x >= 164,
			"continue battle choice must be fully legible")
	_assert(not battle_tutorial.skip_button.visible
			and battle_tutorial.exit_button.text == Locale.t("tutorial.exit_tutorial")
			and battle_tutorial.exit_button.custom_minimum_size.x >= 96,
			"completed tutorial must show a clear exit choice without a skip-button trap")
	battle_tutorial._continue_battle()
	await get_tree().create_timer(2.2).timeout
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


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

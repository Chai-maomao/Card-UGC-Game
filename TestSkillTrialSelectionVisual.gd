extends "res://TestSkillWorkspaceVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	Input.use_accumulated_input = false
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.init_card_draft()
	var draft := PlayerData.card_draft.duplicate(true)
	var trial := preload("res://SkillTryout.gd").new()
	trial.skill = {"probability":100,"effects":[
		{"effect":SkillEngine.EFFECT_DAMAGE,"target":SkillEngine.TARGET_SINGLE,"value_min":2,"value_max":4},
		{"effect":SkillEngine.EFFECT_VIEW_DECK,"value":2},
		{"effect":SkillEngine.EFFECT_DAMAGE,"target":SkillEngine.TARGET_SINGLE,"value_var":SkillEngine.VAR_HAND_COUNT},
		{"effect":SkillEngine.EFFECT_VIEW_DISCARD,"value":1,"random_count":2},
		{"effect":SkillEngine.EFFECT_ZERO_COST,"target":SkillEngine.TARGET_SIDES,"value":2},
		{"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"value_var":SkillEngine.VAR_HAND_COUNT}]}
	add_child(trial)
	var rolled_damage: int = 10-trial.last_game.player2_field.slots[2].hp
	assert(rolled_damage >= 2 and rolled_damage <= 4)
	assert(trial.last_game.player_hand.size() == 3 and trial._steps.size() == 2, "later effects must wait for the first choice")
	trial.stage.finish()
	await _settle()
	var picker: CanvasLayer = trial._picker
	assert(picker.cards.size() == 4 and picker.pick_limit == 2)
	await _capture("trial-deck-choice")
	await _click(picker.selection_overlays[1].get_global_rect().get_center())
	await _click(picker.selection_overlays[3].get_global_rect().get_center())
	assert(picker.selected_order == [1,3])
	await _click(picker.confirm_button.get_global_rect().get_center())
	await _settle()
	assert(trial.last_game.player_hand.size() == 5)
	assert(trial.last_game.player_hand[3].card_name == "牌库卡牌 2" and trial.last_game.player_hand[4].card_name == "牌库卡牌 4")
	assert(trial.last_game.player2_field.slots[2].hp == 10-rolled_damage-5, "the previous roll must remain fixed and the next effect must read the selected hand")
	assert(trial.last_game.player_field.slots[2].hp == 10, "effects after the second choice must still wait")
	trial.stage.finish()
	await _settle()
	picker = trial._picker
	assert(picker.cards.size() == 2 and picker.pick_limit == 1)
	await _click(picker.selection_overlays[1].get_global_rect().get_center())
	await _click(picker.confirm_button.get_global_rect().get_center())
	await _settle()
	assert(trial.last_game.player_hand.size() == 6 and trial.last_game.player_hand[5].card_name == "弃牌 2")
	assert(trial.last_game.shared_discard.size() == 2)
	trial.stage.finish()
	await _settle()
	picker = trial._picker
	assert(picker.cards.size() == 6)
	await _capture("trial-hand-choice")
	await _click(picker.selection_overlays[1].get_global_rect().get_center())
	await _click(picker.confirm_button.get_global_rect().get_center())
	await _settle()
	assert(trial._selection.pending.is_empty())
	assert(trial.last_game.player_hand[0].cost == 0 and trial.last_game.player_hand[1].cost == 0 and trial.last_game.player_hand[2].cost == 1, "choosing a middle hand card must apply the real neighboring cost reduction")
	assert(trial.last_game.player_hand[3].cost == 2 and trial.last_game.player_hand[4].cost == 4, "non-neighboring cards must keep their cost")
	assert(trial.last_game.player_field.slots[2].hp == 16)
	assert(trial.last_game.player2_field.slots[2].hp == 10-rolled_damage-5)
	trial.stage.finish()
	await _capture("trial-selection-result")
	# Inspect the actual hand after resolution, including the changed costs.
	await _click(trial.stage.resources[0].get_global_rect().position+Vector2(110,25))
	await _settle()
	picker = trial._picker
	assert(is_instance_valid(picker) and picker.cards.size() == 6 and picker.pick_limit == 0)
	assert(picker.card_uis[0].current_card_data.cost == 0 and picker.card_uis[2].current_card_data.cost == 1)
	await _capture("trial-discounted-hand")
	picker.queue_free()
	await _settle()
	var rng_state: int = trial.last_game.game_rng.state
	await _click(trial.replay_button.get_global_rect().get_center())
	assert(trial.last_game.game_rng.state == rng_state and trial._selection.pending.is_empty())
	trial.stage.finish()
	# Cancelling a choice keeps the same trial waiting and allows reopening.
	trial.run_trial()
	trial.stage.finish()
	await _settle()
	picker = trial._picker
	var close: Button
	for button in picker.find_children("*","Button",true,false):
		if button.text == Locale.t("battle.close"): close = button
	await _click(close.get_global_rect().get_center())
	await _settle()
	assert(trial.last_game.player_hand.size() == 3 and trial._selection.choices.is_empty())
	await _click(trial.selection_button.get_global_rect().get_center())
	await _settle()
	assert(is_instance_valid(trial._picker))
	# Repeated choices share a block path but remain distinct calls.
	trial.skill = {"effects":[{"effect":SkillEngine.EFFECT_REPEAT,"repeat_count":2,"then_effects":[{"effect":SkillEngine.EFFECT_VIEW_DECK,"value":1}]},{"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"value_var":SkillEngine.VAR_HAND_COUNT}]}
	trial.run_trial()
	trial.stage.finish()
	await _settle()
	for choice_index in [0,1]:
		picker = trial._picker
		await _click(picker.selection_overlays[choice_index].get_global_rect().get_center())
		await _click(picker.confirm_button.get_global_rect().get_center())
		await _settle()
		trial.stage.finish()
		await _settle()
	assert(trial._selection.pending.is_empty() and trial.last_game.player_hand.size() == 5)
	assert(trial.last_game.player_hand[3].card_name == "牌库卡牌 1" and trial.last_game.player_hand[4].card_name == "牌库卡牌 3")
	assert(trial.last_game.player_field.slots[2].hp == 15)
	# Pile choices use the regular hand limit and send excess cards to discard.
	trial.skill = {"effects":[{"effect":SkillEngine.EFFECT_VIEW_DECK,"value":6}]}
	trial.run_trial()
	trial.stage.finish()
	await _settle()
	picker = trial._picker
	for index in range(6):
		picker.scroll.ensure_control_visible(picker.card_uis[index])
		await _settle()
		await _click(picker.selection_overlays[index].get_global_rect().get_center())
	await _click(picker.confirm_button.get_global_rect().get_center())
	await _settle()
	assert(trial.last_game.player_hand.size() == SkillEngine.MAX_HAND_SIZE and trial.last_game.shared_discard.size() == 4)
	trial.queue_free()
	await _settle()
	Locale.language = "en"
	get_window().size = Vector2i(960,540)
	trial = preload("res://SkillTryout.gd").new()
	trial.skill = {"effects":[{"effect":SkillEngine.EFFECT_VIEW_DECK,"value":2}]}
	add_child(trial)
	trial.stage.finish()
	await _settle()
	picker = trial._picker
	assert(get_viewport().get_visible_rect().encloses(picker.panel.get_global_rect()))
	await _capture("trial-choice-en-960")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape,true)
	await _settle()
	assert(is_instance_valid(trial) and not is_instance_valid(trial._picker))
	trial.source_hp.get_line_edit().grab_focus()
	get_viewport().push_input(escape,true)
	await _settle()
	assert(not is_instance_valid(trial), "Escape from a focused input must close only the current modal level")
	assert(PlayerData.card_draft == draft, "choosing sample cards must not change the editing draft")
	print("TEST_SKILL_TRIAL_SELECTION_VISUAL_OK")
	get_tree().quit(0)

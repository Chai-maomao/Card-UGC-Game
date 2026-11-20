extends "res://TestSkillWorkspaceVisual.gd"

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.init_card_draft()
	var trial := preload("res://SkillTryout.gd").new()
	trial.skill = {"probability":100,"effects":[{"effect":SkillEngine.EFFECT_DAMAGE,"target":SkillEngine.TARGET_ALL,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":3},{"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"value":2}]}
	add_child(trial)
	var stage: Control = trial.stage
	# Observe the first travelling cue, before impact; the real engine has
	# already produced the final result, but the presentation must not lead it.
	var saw_before := false
	var saw_transition := false
	var tested_pause := false
	var deadline := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not saw_before and stage._endpoint == 1 and stage._beam_alpha > 0.0 and stage._travel < 1.0 and stage.playing:
			assert(stage.cards[1].current_card_data.hp == 10 and is_equal_approx(stage.bars[1].value,10), "HP must remain unchanged until the travelling effect reaches its target")
			assert(trial.report.get_parsed_text().is_empty() and stage.action_label.text.is_empty(),
					"the first result must stay out of the log and off the stage until impact")
			saw_before = true
			await _click(trial.pause_button.get_global_rect().get_center())
			assert(stage.paused)
			var travel: float = stage._travel
			var hp: float = stage.bars[1].value
			await _capture("trial-before-impact")
			await get_tree().create_timer(0.12).timeout
			assert(is_equal_approx(stage._travel,travel) and is_equal_approx(stage.bars[1].value,hp), "pause must stop both the effect and its state change")
			await _click(trial.pause_button.get_global_rect().get_center())
			assert(not stage.paused)
			tested_pause = true
		if not saw_transition and stage.bars[1].value > 7.01 and stage.bars[1].value < 9.99:
			saw_transition = true
			assert(trial.report.get_parsed_text() == trial._steps[0].text,
					"impact must reveal the first result without revealing the later heal")
			await _capture("trial-impact")
		if not stage.playing: break
	assert(saw_before and saw_transition and tested_pause,
			"trial must animate the cue and HP change (cue %s, HP transition %s, pause %s)" % [saw_before, saw_transition, tested_pause])
	assert(stage.cards[0].current_card_data.hp == 12 and stage.cards[1].current_card_data.hp == 7)
	for i in range(2):
		assert(stage.bars[i].size.y <= 8, "trial HP bars must remain thin")
		assert(not stage.cards[i].get_global_rect().intersects(stage.health[i].get_global_rect()))
		assert(stage.actors[i].get_child(0).get_global_rect().end.y <= stage.cards[i].get_global_rect().position.y, "role labels must remain above the card")
	await _capture("trial-result")
	get_window().size = Vector2i(960, 540)
	await _settle()
	assert(get_window().size == Vector2i(960, 540), "the test must resize the live trial to a compact window")
	var panel := stage.get_parent().get_parent() as PanelContainer
	assert(get_viewport().get_visible_rect().encloses(panel.get_global_rect())
			and panel.get_global_rect().encloses(trial.replay_button.get_global_rect()),
			"resizing an open trial must keep the panel and replay action in view")
	await _capture("trial-compact-result")
	var rng_state: int = trial.last_game.game_rng.state
	await _click(trial.replay_button.get_global_rect().get_center())
	assert(stage.playing and trial.last_game.game_rng.state == rng_state, "replay must reuse the same outcome without consuming randomness")
	stage.finish()
	assert(trial.report.get_parsed_text() == trial._steps[0].text + "\n" + trial._steps[1].text
			and trial.pause_button.disabled, "finishing playback must reveal every result")
	# Restart while a previous playback is running, then fast-forward.
	trial.run_trial()
	await get_tree().process_frame
	trial.run_trial()
	stage.finish()
	assert(not stage.playing and stage.cards[1].current_card_data.hp == trial.last_game.player2_field.slots[2].hp)
	var reduced_before: Variant = AppPreferences.get_value("reduced_motion")
	AppPreferences.set_value("reduced_motion",true)
	trial.run_trial()
	deadline = Time.get_ticks_msec()+500
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not stage.playing: break
	assert(not stage.playing, "reduced motion must reveal the result promptly")
	AppPreferences.set_value("reduced_motion",reduced_before)
	trial.skill = {"effects":[{"effect":SkillEngine.EFFECT_DAMAGE,"target":SkillEngine.TARGET_ALL,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":30}]}
	trial.run_trial()
	stage.finish()
	assert(trial.last_game.player2_field.slots[2] == null and stage.cards[1].current_card_data.hp == 0 and stage.bars[1].value == 0, "a discarded target's reset stats must not appear as a full heal in the trial")
	trial.skill = {"probability":100,"effects":[{"effect":SkillEngine.EFFECT_VIEW_DECK,"value":2}]}
	trial.run_trial()
	stage.finish()
	assert(trial._steps[0].event == "selection" and trial.last_game.player_hand.size() == 3, "an unanswered card choice must not be presented as a completed draw")
	assert(trial.report.get_parsed_text().contains("等待选择"))
	await _settle()
	assert(is_instance_valid(trial._picker))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape,true)
	await _settle()
	assert(is_instance_valid(trial) and not is_instance_valid(trial._picker), "Escape must close the card picker before the trial")
	var inspected: Array = []
	trial.inspect_step.connect(func(path: Array): inspected.append(path))
	await _click(trial.report.get_global_rect().position+Vector2(24,12))
	await get_tree().process_frame
	assert(inspected == [[0]] and not is_instance_valid(trial), "clicking a trial step must return the actual nested effect path and close the trial")
	print("TEST_SKILL_TRIAL_STAGE_VISUAL_OK")
	get_tree().quit(0)

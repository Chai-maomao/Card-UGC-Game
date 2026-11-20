extends "res://TestSkillWorkspaceVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.init_card_draft()
	var trial := preload("res://SkillTryout.gd").new()
	trial.skill = {"skill_type":SkillEngine.SKILL_TYPE_TALENT,"trigger":SkillEngine.TRIGGER_ALWAYS,"effects":[{"effect":SkillEngine.EFFECT_DAMAGE_CAP,"target":SkillEngine.TARGET_SELF,"value":2}]}
	add_child(trial)
	if trial.last_game.player_field.slots[2].hp != 8:
		push_error("TEST_TRIAL_TALENT_FAILED: a sample hit of 6 must apply the real cap of 2 and leave 8 HP")
		get_tree().quit(1)
		return
	var saw_incoming := false
	var deadline := Time.get_ticks_msec()+2000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if trial.stage._travel > 0.1 and trial.stage._travel < 0.8 and trial.stage.playing:
			assert(trial.stage._origin == 1 and trial.stage._endpoint == 0, "the test hit must travel from the enemy to the talent's owner")
			assert(trial.stage.cards[0].current_card_data.hp == 10, "the cap demonstration must not show damage before arrival")
			saw_incoming = true
			await _capture("trial-talent-incoming")
			break
	assert(saw_incoming)
	trial.stage.finish()
	await _capture("trial-talent-result")
	assert(trial.report.get_parsed_text().contains("实际受到 2"))
	trial.incoming_damage.value = 1
	trial.run_trial()
	assert(trial.last_game.player_field.slots[2].hp == 9, "a cap must never increase a smaller hit")
	trial.skill.effects[0].erase("value")
	trial.skill.effects[0].value_var = SkillEngine.VAR_TARGET_ATK
	trial.incoming_damage.value = 6
	trial.run_trial()
	assert(trial.last_game.player_field.slots[2].hp == 7, "continuous expressions must use the real card-stat rule")
	trial.skill.effects = [{"effect":SkillEngine.EFFECT_DAMAGE_CAP,"value":4},{"effect":SkillEngine.EFFECT_DAMAGE_CAP,"value":2}]
	trial.run_trial()
	assert(trial.last_game.player_field.slots[2].hp == 8, "multiple caps must use the effective minimum")
	trial.source_hp.value = 1
	trial.incoming_damage.value = 99
	trial.run_trial()
	assert(trial.last_game.player_field.slots[2] == null and trial._final.source.hp == 0, "the sample must preserve actual lethal damage and cleanup")
	trial.skill = {"skill_type":SkillEngine.SKILL_TYPE_TALENT,"trigger":SkillEngine.TRIGGER_ON_ADDED,"effects":[{"effect":SkillEngine.EFFECT_MATCH_MAX_HP,"target":SkillEngine.TARGET_SELF,"value":4}]}
	trial.source_hp.value = 10
	trial.run_trial()
	assert(trial.last_game.player_field.slots[2].base_max_hp == 34 and trial.last_game.player_field.slots[2].hp == 14)
	assert(not trial._incoming_row.visible, "an immediate talent must retain the normal effect trial")
	trial.queue_free()
	await _settle()
	Locale.language = "en"
	get_window().size = Vector2i(960,540)
	trial = preload("res://SkillTryout.gd").new()
	trial.skill = {"skill_type":SkillEngine.SKILL_TYPE_TALENT,"trigger":SkillEngine.TRIGGER_ALWAYS,"effects":[{"effect":SkillEngine.EFFECT_DAMAGE_CAP,"value":2}]}
	add_child(trial)
	trial.stage.finish()
	await _settle()
	await _capture("trial-talent-en-960")
	for panel in trial.find_children("*","PanelContainer",true,false):
		assert(get_viewport().get_visible_rect().encloses(panel.get_global_rect()))
	assert(trial._incoming_row.get_global_rect().encloses(trial.incoming_damage.get_global_rect()))
	await _capture("trial-talent-en-960")
	trial.queue_free()
	await _settle()
	print("TEST_SKILL_TRIAL_TALENT_VISUAL_OK")
	get_tree().quit(0)

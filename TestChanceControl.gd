extends Node

var random_outcomes: Array[Dictionary] = []

func _on_random(_source: CardData,outcome: Dictionary) -> void:
	random_outcomes.append(outcome.duplicate(true))

func _ready() -> void:
	Locale.language = "zh"
	EventBus.skill_random_resolved.connect(_on_random)
	var gain := {"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1}
	var block := SkillRegistry.make_chance_block(50)
	block.then_effects = [gain, gain.duplicate(true)]
	var skill := {"skill_name": "概率测试", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [block]}
	var card := CardData.new("测试", 1, 5, 0, [skill])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = rng.seed
	var expected := 0
	for _i in range(200):
		if expected_rng.randi_range(1, 100) <= 50: expected += 2
		SkillEngine._execute_skill(skill, card, {"rng":rng, "turn_number":2})
		assert(card.field_atk_bonus == expected, "the whole body must share one deterministic roll")
	assert(rng.state == expected_rng.state, "one group must consume exactly one random draw")
	for percent in [0, 100]:
		block.condition.rhs.value = percent
		var before := card.field_atk_bonus
		SkillEngine._execute_skill(skill, card, {"rng":rng, "turn_number":2})
		assert(card.field_atk_bonus - before == (2 if percent == 100 else 0))
	var restored := PlayerData.deserialize_card(JSON.parse_string(JSON.stringify(PlayerData.serialize_card(card))))
	assert(SkillRegistry.is_chance_block(restored.skills[0].effects[0]))
	assert(SkillTextFormatter.format_effect_sentence(block).begins_with("以 100% 概率执行"))
	block.condition.rhs.value = 25
	assert(is_equal_approx(SkillEstimate.condition_weight(block), 0.25))
	var nested := SkillRegistry.make_chance_block(100)
	nested.then_effects = [SkillRegistry.make_chance_block(0), gain]
	nested.then_effects[0].then_effects = [gain]
	var before := card.field_atk_bonus
	SkillEngine._execute_skill({"effects":[nested]}, card, {"rng":rng, "turn_number":2})
	assert(card.field_atk_bonus - before == 1)
	# Presentation observes the same rolls, with no additional RNG consumption.
	random_outcomes.clear()
	var legacy := CardData.new("旧概率",0,5,0,[{"skill_name":"概率","trigger":"on_activate","probability":37,"effects":[gain]}])
	expected_rng.state = rng.state
	var percent_roll := expected_rng.randf()*100.0
	SkillEngine.trigger_single_skill(legacy,0,{"rng":rng,"current_player":1})
	assert(random_outcomes.size()==1 and random_outcomes[0].type=="chance")
	assert(is_equal_approx(float(random_outcomes[0].roll),percent_roll) and bool(random_outcomes[0].success)==(percent_roll<=37))
	assert(legacy.field_atk_bonus==(1 if percent_roll<=37 else 0) and rng.state==expected_rng.state)
	random_outcomes.clear()
	var expr := {"kind":"expr","op":"rand","a":{"kind":"num","value":4},"b":{"kind":"num","value":-2}}
	var expected_value := expected_rng.randi_range(-2,4)
	var value := SkillEngine._eval_operand(expr,legacy,legacy,{"rng":rng,"current_player":1})
	assert(value==expected_value and rng.state==expected_rng.state)
	assert(random_outcomes.size()==1 and int(random_outcomes[0].minimum)==-2 and int(random_outcomes[0].maximum)==4 and int(random_outcomes[0].result)==expected_value)
	random_outcomes.clear()
	var silent_rng := RandomNumberGenerator.new()
	silent_rng.state = rng.state
	expected_value = expected_rng.randi_range(2,6)
	value = SkillEngine._resolve_value({"effect":"heal","value_min":6,"value_max":2},legacy,legacy,{"rng":silent_rng,"quiet":true})
	assert(value==expected_value and silent_rng.state==expected_rng.state and random_outcomes.is_empty(),"simulation must consume the existing roll without emitting UI events")
	_check_misfortune(rng, expected_rng)

	PlayerData.skill_tutorial_active = false
	PlayerData.init_card_draft()
	PlayerData.editing_skill_index = 1
	var editor = load("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	editor.effect_data.clear()
	editor._reset_undo_history()
	editor._add_chance_block()
	assert(SkillRegistry.is_chance_block(editor.effect_data[0]))
	editor.effect_data[0].then_effects = [gain.duplicate(true)]
	editor._refresh_script()
	await get_tree().process_frame
	await get_tree().process_frame
	var slot = editor.find_children("ChancePercent", "", true, false)[0]
	var inputs = slot.find_children("*", "LineEdit", true, false)
	assert(inputs.size() == 1)
	var percent := inputs[0] as LineEdit
	percent.text = "200"
	percent.text_submitted.emit(percent.text)
	assert(editor.effect_data[0].condition.rhs.value == 100)
	assert(not slot._can_drop_var(Vector2.ZERO,{"type":"var_block","var_id":SkillEngine.VAR_SOURCE_HP_PCT}))
	percent.text = "37"
	percent.text_submitted.emit(percent.text)
	assert(editor.effect_data[0].condition.rhs.value == 37)
	var state = JSON.parse_string(JSON.stringify(editor._editor_state()))
	editor._apply_state(state)
	assert(SkillRegistry.is_chance_block(editor.effect_data[0]))
	assert(editor.effect_data[0].condition.rhs.value == 37)
	assert(editor._collect_errors().is_empty())
	var built: Dictionary = editor._build_skill()
	assert(built.effects[0].then_effects.size() == 1)
	editor._undo()
	editor._redo()
	assert(SkillRegistry.is_chance_block(editor.effect_data[0]))
	assert(SkillRegistry.is_chance_block(editor._new_block_for(SkillRegistry.CHANCE_PALETTE_ID)))
	editor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("TEST_CHANCE_CONTROL_OK")
	get_tree().quit(0)


func _check_misfortune(rng: RandomNumberGenerator, expected_rng: RandomNumberGenerator) -> void:
	for effect_probability in [100, 67]:
		random_outcomes.clear()
		var effect := {"effect": "gain_attack", "target": "self", "value": 1, "probability": effect_probability}
		var skill := {"skill_name": "Extra attack", "trigger": "on_activate", "probability": 100, "effects": [effect]}
		var card := CardData.new("Caster", 0, 5, 0, [skill])
		card.apply_buff(SkillEngine.BUFF_MISFORTUNE, 5, 4)
		rng.seed = 42
		expected_rng.state = rng.state
		expected_rng.randf()
		if effect_probability < 100:
			expected_rng.randf()
		SkillEngine.trigger_single_skill(card, 0, {"rng": rng, "current_player": 1})
		assert(card.field_atk_bonus == 1 and rng.state == expected_rng.state, "Misfortune must only alter the skill activation roll")
		assert(random_outcomes.size() == (1 if effect_probability == 100 else 2))
		assert(random_outcomes[0].chance_scope == "skill" and random_outcomes[0].probability == 95)
		if effect_probability < 100:
			assert(random_outcomes[1].chance_scope == "effect" and random_outcomes[1].effect_id == "gain_attack")
			assert(random_outcomes[1].probability == effect_probability and random_outcomes[1].success)

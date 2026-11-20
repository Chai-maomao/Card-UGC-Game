extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _verify() -> void:
	get_window().size = Vector2i(1280,720)
	GamePreferences.set_animation_acceleration(true)
	battle.game.current_player = 1
	battle.game.is_player_turn = true
	battle.game.turn_number = 3
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.action_points = 20
	battle.game.player_field.current_mana = 10
	var chance := SkillRegistry.make_chance_block(100)
	chance.then_effects = [{"effect":"damage","target":"all_enemies","value_min":2,"value_max":6}]
	var caster := CardData.new("概率术师",0,8,0,[{"skill_name":"命运回响","trigger":"on_activate","effects":[chance]}])
	caster.instance_id = "wheel-caster"
	var target := CardData.new("目标",0,20,0)
	target.instance_id = "wheel-target"
	battle.game.player_field.slots[0] = caster
	battle.game.player2_field.slots[0] = target
	battle.game.game_rng.seed = 72461
	battle.update_entire_screen()
	await get_tree().create_timer(.35).timeout
	var expected := RandomNumberGenerator.new()
	expected.state = battle.game.game_rng.state
	var chance_roll := expected.randi_range(1,100)
	var damage := expected.randi_range(2,6)
	battle._on_skill_activated(0,0)
	var wheel: CanvasLayer = battle.get_node("RandomWheelPresentation")
	assert(target.hp==20-damage and battle.game.game_rng.state==expected.state,"presentation must preserve real results and exactly the existing RNG draws")
	await _wait_for_settled(wheel,1)
	assert(wheel.history[0].type=="chance" and int(wheel.history[0].roll)==chance_roll,"probability wheel must use the actual chance-block roll")
	assert(wheel.detail.text == "概率积木判定 100%", "the wheel must identify the probability block")
	assert(battle.enemy_side_ui.get_child(0).current_card_data.hp==20,"target must retain pre-effect HP throughout probability reveal")
	await _capture("random-wheel-chance")
	await _wait_for_settled(wheel,2)
	assert(wheel.history[1].type=="integer" and int(wheel.history[1].result)==damage,"numeric wheel must use the effect's actual shared damage roll")
	assert(battle.enemy_side_ui.get_child(0).current_card_data.hp==20,"damage cannot appear before the numeric reveal")
	await _capture("random-wheel-number")
	await _wait_for_finished(wheel)
	await get_tree().process_frame
	assert(battle.enemy_side_ui.get_child(0).current_card_data.hp==target.hp and battle._random_board_override.is_empty(),"landing must release the presentation board and show actual HP")
	assert(battle.game.game_rng.state==expected.state,"wheel animation must never advance the gameplay RNG")
	# Failure is visible, and is not followed by the body's random number roll.
	caster.skills[0].effects[0].condition.rhs.value = 37
	caster.skills_used_count.clear()
	caster.skills_used.clear()
	caster.has_acted = false
	battle.game.player_field.action_points = 20
	var before_hp := target.hp
	var before_count: int = wheel.history.size()
	for seed_value in range(1,100):
		expected.seed = seed_value
		if expected.randi_range(1,100)>37:
			battle.game.game_rng.seed = seed_value
			break
	expected.state = battle.game.game_rng.state
	expected.randi_range(1,100)
	battle._on_skill_activated(0,0)
	await _wait_for_settled(wheel,before_count+1)
	assert(not wheel.history.back().success and target.hp==before_hp,"failed chance must show failure and skip its entire body")
	get_window().size = Vector2i(960,540)
	await _capture("random-wheel-failed-960")
	get_window().size = Vector2i(1280,720)
	await _wait_for_finished(wheel)
	assert(wheel.history.size()==before_count+1 and battle.game.game_rng.state==expected.state,"failure must neither invent a value roll nor consume animation RNG")
	# An unbatched turn-end passive also waits before its healing is displayed.
	caster.skills = [{"skill_name":"回合自疗","trigger":"on_turn_end","effects":[{"effect":"heal","target":"self","value_expr":{"kind":"expr","op":"rand","a":{"kind":"num","value":1},"b":{"kind":"num","value":3}}}]}]
	caster.hp = 2
	battle.update_entire_screen()
	await get_tree().create_timer(.15).timeout
	before_count = wheel.history.size()
	SkillEngine.trigger_skills("on_turn_end",caster,battle.game.make_skill_context_for_player(1,0))
	await _wait_for_settled(wheel,before_count+1)
	assert(battle.player_side_ui.get_child(0).current_card_data.hp==2,"unbatched passive healing must also wait for its wheel")
	await _wait_for_finished(wheel)
	# Lethal random damage must retain the target until the wheel is finished.
	caster.skills = [{"skill_name":"随机终结","trigger":"on_activate","effects":[{"effect":"damage","target":"all_enemies","value_min":4,"value_max":4}]}]
	caster.skills_used.clear()
	caster.has_acted = false
	battle.game.player_field.action_points = 20
	target.hp = 1
	battle.update_entire_screen()
	await get_tree().create_timer(.2).timeout
	before_count = wheel.history.size()
	battle._on_skill_activated(0,0)
	await _wait_for_settled(wheel,before_count+1)
	assert(battle.game.player2_field.slots[0]==null and battle.enemy_side_ui.get_child(0).current_card_data.hp==1,"lethal state must stay hidden until its random result is revealed")
	await _wait_for_finished(wheel)
	await get_tree().create_timer(.7).timeout
	assert(battle.enemy_side_ui.get_child(0).current_card_data==null,"lethal presentation must release the removed target")
	# A passive on the authority records a serializable sequence. Replaying the
	# packet must display its result without executing skills or consuming RNG.
	caster.skills = [{"skill_name":"回放自疗","trigger":"on_turn_end","effects":[{"effect":"heal","target":"self","value_min":1,"value_max":3}]}]
	caster.hp = 2
	battle.update_entire_screen()
	await get_tree().create_timer(.15).timeout
	NetworkManager.is_online = true
	NetworkManager.is_host = true
	NetworkManager.player_number = 1
	battle.my_player = 1
	battle._pending_feedback_events.clear()
	battle._pending_hp_events.clear()
	SkillEngine.trigger_skills("on_turn_end",caster,battle.game.make_skill_context_for_player(1,0))
	var packet: Dictionary = JSON.parse_string(JSON.stringify(battle._pending_feedback_events[0]))
	assert(packet.kind=="presentation" and packet.events.any(func(event): return event.kind=="random"),"authority passive must include its recorded random result in feedback")
	assert(battle._pending_hp_events.is_empty() and packet.events.filter(func(event): return event.kind=="hp").size()==1,"passive HP feedback must occur only once in the authority packet")
	await get_tree().process_frame
	assert(packet.events.size()>1,"deferred flush must not clear the outbound passive sequence")
	await _wait_for_finished(wheel)
	NetworkManager.close_connection()
	var replay_rng: int = battle.game.game_rng.state
	before_count = wheel.history.size()
	AppPreferences.set_value("reduced_motion",true)
	battle._replay_feedback_event(packet)
	await _wait_for_settled(wheel,before_count+1)
	assert(battle.player_side_ui.get_child(0).current_card_data.hp==2,"remote feedback must restore its recorded pre-effect view")
	await _wait_for_finished(wheel)
	assert(battle.game.game_rng.state==replay_rng,"feedback replay must never roll again")
	AppPreferences.set_value("reduced_motion",false)
	# Large ranges, reversed endpoints, and negatives retain readable results.
	Locale.language = "en"
	var visual_event := {"type":"integer","minimum":-1000,"maximum":1000,"result":-721,"source":"Caster","skill":"Random value","player":1,"source_slot":0}
	wheel.play(visual_event)
	await _wait_for_settled(wheel,wheel.history.size()+1)
	await _capture("random-wheel-large-en")
	await _wait_for_finished(wheel)
	Locale.language = "zh"
	AppPreferences.set_value("reduced_motion", true)
	get_window().size = Vector2i(960, 540)
	wheel.play({"type":"chance", "chance_scope":"skill", "probability":95, "roll":30, "success":true, "source":"御坂美琴", "skill":"电磁炮", "player":1})
	assert(wheel.detail.text == "技能发动概率 95%")
	await _wait_for_finished(wheel)
	wheel.play({"type":"chance", "chance_scope":"effect", "effect_id":"damage", "probability":67, "roll":64, "success":true, "source":"御坂美琴", "skill":"电磁炮", "player":1})
	assert(wheel.detail.text == "效果「伤害」生效概率 67%")
	await _wait_for_settled(wheel, wheel.history.size()+1)
	await _capture("random-wheel-effect-chance-960")
	await _wait_for_finished(wheel)
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_RANDOM_WHEEL_VISUAL_OK")
	get_tree().quit(0)

func _wait_for_settled(wheel: CanvasLayer,count: int) -> void:
	var deadline := Time.get_ticks_msec()+15000
	while wheel.history.size()<count:
		assert(Time.get_ticks_msec()<deadline,"random feedback stalled")
		await get_tree().process_frame

func _wait_for_finished(wheel: CanvasLayer) -> void:
	var deadline := Time.get_ticks_msec()+15000
	while wheel.busy or battle._random_feedback_pending>0 or battle._hp_feedback_running:
		assert(Time.get_ticks_msec()<deadline,"random feedback did not release input")
		await get_tree().process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/"+name+".png")

extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _verify() -> void:
	get_window().size = Vector2i(1280,720)
	GamePreferences.set_animation_acceleration(true)
	var wheel: CanvasLayer = battle.get_node("RandomWheelPresentation")
	var status_fx = battle.get_node("CanvasLayer/BattleCardStatusFx")
	for trigger in ["on_attack","on_damaged","parasite","on_death","on_healed","on_summon","on_turn_end","on_turn_start"]:
		await _idle(wheel)
		battle.game.current_player = 1
		battle.game.is_player_turn = true
		battle.game.turn_number = 4
		battle.game.player_field.slots.fill(null)
		battle.game.player2_field.slots.fill(null)
		battle.game.player_field.action_points = 30
		battle.game.player_field.current_mana = 10
		var attacker := CardData.new("测试攻击者",0,8,2)
		attacker.instance_id = "attacker-"+trigger
		var defender := CardData.new("测试宿主",0,20,0)
		defender.instance_id = "defender-"+trigger
		var chance := SkillRegistry.make_chance_block(100)
		chance.then_effects = [{"effect":"heal","target":"self","value":1}]
		var skill := {"skill_name":"受击恢复","trigger":trigger,"effects":[chance]}
		match trigger:
			"on_attack":
				attacker.hp = 3
				skill.effects = [{"effect":"add_buff","target":"all_enemies","buff_id":"silence","value":1,"duration":1,"probability":50}]
				var success_rng := RandomNumberGenerator.new()
				for seed_value in range(64):
					success_rng.seed = seed_value
					if success_rng.randf() <= 0.5:
						battle.game.game_rng.seed = seed_value
						break
				attacker.skills = [skill]
			"on_damaged": defender.skills=[skill]
			"parasite":
				skill.trigger = "on_damaged"
				var parasite := CardData.new("共生芽",0,3,0,[skill])
				parasite.card_type = "parasite"
				parasite.instance_id = "attached"
				defender.parasite_cards.append(parasite)
				defender.parasite_cards[0].parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
			"on_death":
				defender.hp = 1
				chance.then_effects = [{"effect":"damage","target":"all_enemies","value":1}]
				defender.skills = [skill]
			"on_healed", "on_turn_end", "on_turn_start":
				attacker.hp=3
				attacker.atk=0
				if trigger=="on_healed": chance.then_effects=[{"effect":"gain_attack","target":"self","value":1}]
				attacker.skills=[skill]
			"on_summon":
				chance.then_effects = [{"effect":"damage","target":"all_enemies","value":1}]
				attacker.skills=[skill]
		battle.game.player_field.slots[0]=attacker
		battle.game.player2_field.slots[0]=defender
		battle.update_entire_screen()
		await get_tree().create_timer(.2).timeout
		var before_count: int = wheel.history.size()
		var before_attacker: int = attacker.hp
		var before_defender: int = defender.hp
		match trigger:
			"on_attack", "on_damaged", "parasite", "on_death":
				battle._on_attack_requested(0)
				battle._on_enemy_slot_clicked(0)
			"on_healed":
				SkillEngine._execute_skill({"skill_name":"治疗术","effects":[{"effect":"heal","target":"self","value":1}]},attacker,battle.game.make_skill_context_for_player(1,0))
			"on_summon":
				battle.game.player_field.slots[0]=null
				battle.game.player_hand.append(attacker)
				battle._refresh_hand_ui()
				battle._on_card_drag_summoned(attacker,null,0)
			"on_turn_end": battle.game.end_player_turn(false)
			"on_turn_start":
				battle.game.current_player=2
				battle.game.start_new_turn()
		var deadline := Time.get_ticks_msec()+10000
		while wheel.history.size()==before_count:
			assert(Time.get_ticks_msec()<deadline,"trigger never reached its wheel: "+trigger)
			await get_tree().process_frame
			if trigger == "on_attack":
				assert(not _silence_visible(status_fx), "silence must stay off the board until the wheel reveals its result")
		var left: Control = battle.player_side_ui.get_child(0)
		var right: Control = battle.enemy_side_ui.get_child(0)
		var shown_attacker := before_attacker + (1 if trigger == "on_healed" else 0)
		var shown_defender := maxi(0, before_defender - (2 if trigger in ["on_attack","on_damaged","parasite","on_death"] else 0))
		assert(left.current_card_data!=null and left.current_card_data.hp==shown_attacker,"friendly HP must reflect only events before its wheel: "+trigger)
		assert(right.current_card_data!=null and right.current_card_data.hp==shown_defender,"the triggering hit must be visible before its reaction wheel: "+trigger)
		assert(not wheel.title.text.contains("·") and wheel.title.text.contains("的技能"),"wheel subject must be a readable sentence")
		if trigger == "parasite":
			assert(wheel.title.text.contains("测试宿主") and wheel.title.text.contains("共生芽") and wheel.title.text.contains("受击恢复"),
				"parasite roll must identify the host, attachment and skill")
			assert(wheel.history.back().trigger == SkillEngine.TRIGGER_ON_DAMAGED and wheel.detail.text == "概率积木判定 100%",
				"the roll must preserve its on-damaged trigger and show which probability is being checked")
		if trigger in ["parasite","on_death"]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/random-order-"+trigger+".png")
		if trigger == "on_attack":
			while wheel.busy:
				assert(not _silence_visible(status_fx), "the silence badge must remain hidden while the wheel is on screen")
				await get_tree().process_frame
		await _idle(wheel)
		if trigger == "on_attack":
			assert(wheel.history.back().chance_scope == "effect" and wheel.history.back().success, "the fixture must resolve a successful 50% effect roll")
			assert(defender.is_silenced() and _silence_visible(status_fx), "the silence badge must appear after the successful wheel")
		assert(not battle._playing_random_action and battle._random_board_override.is_empty(),"trigger chain must restore normal presentation")
	# A lethal attack records its ordinary hit before cleanup discovers the
	# death passive. The remote packet must preserve that order.
	battle.game.current_player=1
	battle.game.is_player_turn=true
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.action_points=30
	var attacker := CardData.new("回放攻击者",0,8,2)
	attacker.instance_id="replay-attacker"
	var chance := SkillRegistry.make_chance_block(100)
	chance.then_effects=[{"effect":"damage","target":"all_enemies","value":1}]
	var defender := CardData.new("回放亡语者",0,1,0,[{"skill_name":"退场反击","trigger":"on_death","effects":[chance]}])
	defender.instance_id="replay-defender"
	battle.game.player_field.slots[0]=attacker
	battle.game.player2_field.slots[0]=defender
	battle.update_entire_screen()
	await get_tree().create_timer(.2).timeout
	NetworkManager.is_online=true
	NetworkManager.is_host=true
	NetworkManager.player_number=1
	battle.my_player=1
	battle._pending_feedback_events.clear()
	battle._begin_action_broadcast("attack",1,attacker.card_name,defender.card_name)
	battle.game.execute_attack(0,0)
	battle._finish_action_broadcast()
	battle._play_attack_feedback(1,0,0)
	battle._record_feedback_event("attack",1,0,{"target_slot":0})
	battle._apply_deaths()
	var packet: Array = JSON.parse_string(JSON.stringify(battle._pending_feedback_events))
	await _idle(wheel)
	NetworkManager.close_connection()
	var count: int=wheel.history.size()
	var rng_state: int=battle.game.game_rng.state
	for event in packet: battle._replay_feedback_event(event)
	var deadline := Time.get_ticks_msec()+10000
	while wheel.history.size()==count:
		assert(Time.get_ticks_msec()<deadline,"remote death passive failed to reveal")
		await get_tree().process_frame
	assert(battle.player_side_ui.get_child(0).current_card_data.hp==8 and battle.enemy_side_ui.get_child(0).current_card_data.hp==0,"remote replay must show the lethal hit before the death passive's effect")
	await _idle(wheel)
	assert(battle.game.game_rng.state==rng_state,"replay must not change RNG")
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_RANDOM_TRIGGER_ORDER_VISUAL_OK")
	get_tree().quit(0)


func _idle(wheel: CanvasLayer) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while wheel.busy or battle._random_feedback_pending>0 or battle._hp_feedback_running or not battle._random_unbatched_events.is_empty():
		assert(Time.get_ticks_msec()<deadline,"trigger chain remained locked")
		await get_tree().process_frame
	await get_tree().create_timer(.45).timeout


func _silence_visible(status_fx: Node) -> bool:
	return status_fx.effects.values().any(func(entry): return "silence" in entry.statuses)

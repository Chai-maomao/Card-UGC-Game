extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _verify() -> void:
	get_window().size = Vector2i(1280,720)
	battle.game.current_player = 1
	battle.game.is_player_turn = true
	battle.game.turn_number = 3
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	var actor := CardData.new("攻击者",1,6,4)
	var target := CardData.new("目标",1,4,0)
	battle.game.player_field.slots[0] = actor
	battle.game.player2_field.slots[0] = target
	# A random active skill unrelated to this attack must not hide its damage.
	battle.game.player_field.slots[1] = CardData.new("随机技能",1,6,1,[{"trigger":"on_activate","probability":50,"effects":[{"effect":"damage","target":"target_single","value":2}]}])
	battle.game.player_field.action_points = 20
	for reduction in [0,50]:
		target.status_effects.clear()
		if reduction>0: target.apply_buff(SkillEngine.BUFF_DAMAGE_REDUCTION,reduction,2,2)
		battle.game.state_revision += 1
		battle.update_entire_screen()
		await get_tree().create_timer(0.3).timeout
		var before := BattleRepro.state_hash(battle.game)
		battle._on_attack_requested(0)
		await _hover_target()
		var face = battle.tabletop.cards[5].face
		var damage := 4 if reduction==0 else 2
		assert(int(face.prediction.get("hp",0))==-damage,"preview must use actual damage after reduction")
		assert(face._predicted_stat("hp",4)==("0(-4)" if reduction==0 else "2(-2)"),"HP preview must show remaining health and actual loss")
		assert(BattleRepro.state_hash(battle.game)==before,"preview must preserve live state and RNG")
		await _capture("damage-preview-%d"%reduction)
		var actual = battle.game.copy_for_simulation()
		actual.execute_attack(0,0)
		assert(actual.player2_field.slots[0].hp==4-damage,"preview must agree with real attack resolution before death cleanup")
		battle.cancel_attack()
	actor.skills = [{"trigger":"on_attack","probability":50,"effects":[{"effect":"damage","target":"target_single","value":2}]}]
	battle.game.state_revision += 1
	battle._on_attack_requested(0)
	await _hover_target()
	assert(battle.tabletop.cards[5].face.prediction.is_empty(),"a random effect in the actual attack chain must suppress exact numbers")
	battle.cancel_attack()
	actor.skills.clear()
	actor.apply_buff(SkillEngine.BUFF_SILENCE,1,2,2)
	battle.update_entire_screen()
	await get_tree().create_timer(0.2).timeout
	var status = battle.get_node("CanvasLayer/BattleCardStatusFx")
	assert(not status.effects.is_empty(),"silence mark must still be present on its unit")
	var corners: PackedVector2Array = battle.tabletop.projected_slot_corners(0)
	var center: Vector2 = status._point(corners,0.78,0.36)
	var source: Control = battle.hand_container.get_child(0)
	battle.tabletop_hand_inspect(source)
	await get_tree().create_timer(0.2).timeout
	# Place the real inspector over the marked unit, reproducing an occlusion.
	battle.card_inspector.position = center-Vector2(100,100)
	await _capture("silence-under-inspector")
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_COMBAT_PREDICTION_VISUAL_OK")
	get_tree().quit(0)

func _hover_target() -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = battle.enemy_side_ui.get_child(0).get_global_rect().get_center()
	motion.global_position = motion.position
	get_viewport().push_input(motion,true)
	await get_tree().create_timer(0.3).timeout

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/"+name+".png")

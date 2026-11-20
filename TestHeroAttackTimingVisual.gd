extends "res://TestTabletop3DVisual.gd"
var launches: Array = []
var payment_frames: Array = []
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _verify() -> void:
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	for i in range(3): battle.game.player_field.slots[i] = CardData.new("Archer%d" % i,0,5,i+2)
	battle.game.turn_number = 3
	battle.game.player_field.action_points = 3
	battle.game.player_field.action_budget = 3
	battle.game.player_field.actions_taken = 1
	battle.game.player_field.current_mana = 4
	battle.game.player_field.temp_mana = 0
	battle._sync_face_mana_toggle()
	battle.face_mana_button.set_pressed_no_signal(true)
	battle._suppress_status_feedback_once = true
	battle.update_entire_screen()
	await get_tree().create_timer(0.3).timeout
	battle.get_node("CanvasLayer").child_entered_tree.connect(_sample_payment)
	await _click(_center(battle.end_turn_button))
	var deadline := Time.get_ticks_msec()+6000
	while battle._turn_ending and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	var payments := [[2,4],[0,4],[0,1]]
	assert(launches.size()==payments.size(),"all three projectile launches must be displayed")
	for i in range(payments.size()):
		assert(launches[i]==[Locale.t("battle.action_points",[payments[i][0],3]),Locale.t("battle.mana_value",[payments[i][1],10])],"each launch label must show only its own payment")
		var resource := 0 if i<2 else 1
		var before: float = [[3,4],[2,4],[0,4]][i][resource]
		var after: float = payments[i][resource]
		if not payment_frames[i].any(func(values): return float(values[resource])<before and float(values[resource])>after):
			push_error("resource payment must visibly pass through intermediate fill values: shot=%d samples=%s"%[i,payment_frames[i]])
			get_tree().quit(1)
			return
	assert(battle.game.player_field.action_points==0 and battle.game.player_field.current_mana==1,"presentation timing must preserve authoritative payment")
	assert(battle.game.player2_field.player_hp==21,"all three attacks must still deal their full damage")
	assert(battle._hero_resources_shown.is_empty(),"resource overrides must clear after the projectiles finish")
	AppPreferences.set_value("reduced_motion",true)
	battle._my_field().action_points = maxi(0,battle._my_field().action_points-1)
	battle._update_battle_status_huds()
	var reduced_bar: ProgressBar = battle.player_status_hud.get_node("Margin/Content/ActionBar")
	assert(reduced_bar.value==battle._my_field().action_points and reduced_bar.scale==Vector2.ONE,"reduced motion must show the remaining resource immediately without a pulse")
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_HERO_ATTACK_TIMING_VISUAL_OK")
	get_tree().quit()

func _sample_payment(node: Node) -> void:
	if node.name!="HeroStrikeTrail": return
	var hud: Node = battle.player_status_hud.get_node("Margin/Content")
	launches.append([hud.get_node("HandLabel").text,hud.get_node("ManaLabel").text])
	var values: Array = []
	payment_frames.append(values)
	var first := launches.size()==1
	for frame in range(12):
		values.append([hud.get_node("ActionBar").value,hud.get_node("ManaBar").value])
		# A normal HUD refresh must not cut an in-progress payment short.
		if frame==3:
			var before_refresh := [hud.get_node("ActionBar").value,hud.get_node("ManaBar").value]
			battle._update_battle_status_huds()
			assert(is_equal_approx(hud.get_node("ActionBar").value,before_refresh[0]) and is_equal_approx(hud.get_node("ManaBar").value,before_refresh[1]),"unchanged HUD refresh must preserve intermediate resource fill")
		if first and frame==5:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/action-payment-transition.png")
		await get_tree().process_frame

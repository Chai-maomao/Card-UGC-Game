extends "res://TestTabletop3DVisual.gd"
var failed := false
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func check(ok: bool,message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func _verify() -> void:
	var source: CardData = battle.game.player_field.slots[0]
	var target: CardData = battle.game.player2_field.slots[4]
	source.skills = [{"trigger":"on_activate","effects":[{"effect":"add_buff","buff_id":"silence","value":1,"duration":2,"target":"target_single","target_side":"enemy"},{"effect":"add_buff","buff_id":"stun","value":1,"duration":2,"target":"target_single","target_side":"enemy"},{"effect":"add_buff","buff_id":"poison","value":2,"duration":2,"target":"target_single","target_side":"enemy"}]}]
	battle.game.turn_number = 2
	check(battle.game.trigger_activate_skills(0,4,0,2),"real skill must successfully apply all three statuses")
	battle.game.player_field.slots[1].apply_buff("regen",2,2,1)
	battle.update_entire_screen()
	await get_tree().create_timer(0.4).timeout
	var fx = battle.get_node("CanvasLayer/BattleCardStatusFx")
	check(fx.effects.has(target.get_instance_id()),"actual skill application must show status visuals on its target")
	check(fx.effects[target.get_instance_id()].statuses.size()==3,"silence, stun and poison must remain distinct when combined")
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		get_window().size = dimensions
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/status-%d.png" % dimensions.x)
	var before := BattleRepro.hash_state(battle.game.export_initial_state())
	AppPreferences.set_value("reduced_motion",true)
	await get_tree().create_timer(0.3).timeout
	check(fx.elapsed==0 and fx.effects.has(target.get_instance_id()),"reduced motion must retain static state markers")
	check(before==BattleRepro.hash_state(battle.game.export_initial_state()),"status animation must not modify battle state")
	target.status_effects.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not fx.effects.has(target.get_instance_id()),"cleansing a unit must remove its persistent effects immediately")
	battle.game.player_field.slots[1].hp = 0
	await get_tree().process_frame
	await get_tree().process_frame
	check(fx.effects.is_empty(),"dead units must not retain effects")
	AppPreferences.set_value("reduced_motion",false)
	battle.queue_free()
	await get_tree().process_frame
	if not failed: print("TEST_CARD_STATUS_EFFECTS_VISUAL_OK")
	get_tree().quit(1 if failed else 0)

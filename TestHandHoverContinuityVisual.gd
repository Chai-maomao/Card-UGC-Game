extends "res://TestTabletop3DVisual.gd"
var failed := false

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _verify() -> void:
	get_window().size = Vector2i(1280,720)
	battle.game.player_hand.clear()
	for index in range(8):
		var card := CardData.new("手牌%d"%(index+1),1,4,2)
		card.instance_id = "hover-%d"%index
		battle.game.player_hand.append(card)
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().create_timer(.7).timeout
	for index in [0,7]:
		_move(Vector2(5,5))
		await get_tree().create_timer(.3).timeout
		var entry: Dictionary = battle.tabletop.cards[10+index]
		var rest_x: float = battle.tabletop.camera.unproject_position(entry.top.global_position).x
		var item: Control = battle.hand_container.get_child(index)
		var at := item.get_global_rect().get_center()
		if index==0: at.x = (item.global_position.x+battle.hand_container.get_child(1).global_position.x)*.5
		_move(at)
		var drift := 0.0
		var shades: Array[float] = []
		for frame in range(18):
			await get_tree().physics_frame
			await get_tree().process_frame
			drift = maxf(drift,absf(battle.tabletop.camera.unproject_position(entry.top.global_position).x-rest_x))
			if frame in [1,4,10]:
				await RenderingServer.frame_post_draw
				var rendered := get_viewport().get_texture().get_image()
				rendered.save_png("res://artifacts/hand-overlap-20261115/hover-phase-%d-%d.png"%[index,frame])
				var foreground: Polygon2D = battle._hand_focus_overlays[item.get_instance_id()].face
				var points := foreground.polygon
				var point := points[0].lerp(points[1],.55).lerp(points[3].lerp(points[2],.55),.155)
				shades.append(rendered.get_pixelv(Vector2i(point)).get_luminance())
				if battle.player_status_hud.get_global_rect().has_point(point) and shades.back()<.6:
					failed = true
					push_error("lifted paper header must remain visible above the HUD")
		if drift>.8:
			failed = true
			push_error("hover horizontal center drifted %.3f pixels on card %d"%[drift,index])
		if not (shades[0]>=shades[1]-.015 and shades[1]>=shades[2]-.015 and shades[0]-shades[2]>.02):
			failed = true
			push_error("paper shading must darken continuously during lift: "+str(shades))
	_move(Vector2(5,5))
	await get_tree().create_timer(.3).timeout
	battle.queue_free()
	await get_tree().process_frame
	if not failed: print("TEST_HAND_HOVER_CONTINUITY_VISUAL_OK")
	get_tree().quit(1 if failed else 0)

func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion,true)

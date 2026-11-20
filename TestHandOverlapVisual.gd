extends "res://TestTabletop3DVisual.gd"
var failed := false
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func move_pointer(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion,true)
	await get_tree().create_timer(0.22).timeout
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/"+name+".png")
func _verify() -> void:
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		get_window().size = dimensions
		battle.game.player_hand.clear()
		for index in range(8):
			battle.game.player_hand.append(CardData.new("手牌%d" % (index+1),1,4,2))
		battle.game.player_field.current_mana = 10
		battle.game.state_revision += 1
		battle._refresh_hand_ui()
		battle.update_entire_screen()
		await get_tree().create_timer(1.2).timeout
		await move_pointer(Vector2(5,5))
		await capture("rest-%d" % dimensions.x)
		var hash_before := BattleRepro.hash_state(battle.game.export_initial_state())
		for direction in [range(8),range(7,-1,-1)]:
			for index in direction:
				var item: Control = battle.hand_container.get_child(index)
				var rest: Vector2 = item.get_meta("hand_rest_position")
				var next_x: float = battle.hand_container.get_child(index+1).get_meta("hand_rest_position").x if index<7 else rest.x+item.size.x
				var at: Vector2 = battle.hand_container.global_position+Vector2((rest.x+next_x)*0.5,rest.y+item.size.y*0.5)
				await move_pointer(at)
				var hovered := get_viewport().gui_get_hovered_control()
				check(hovered != null and (hovered == item or item.is_ancestor_of(hovered)),"sweeping overlapping cards must pick card %d" % index)
				check(item.scale.x>1.05 and item.position.y<rest.y-5,"hover must raise and enlarge the selected card")
				var entry: Dictionary = battle.tabletop.cards[10+index]
				for other in range(8):
					if other != index: check(entry.root.position.y>battle.tabletop.cards[10+other].root.position.y,"selected card must sit above every neighbor")
				if index==3: await capture("hover-%d" % dimensions.x)
		check(hash_before == BattleRepro.hash_state(battle.game.export_initial_state()),"hover must not change battle rules")
		var returning: Control = battle.hand_container.get_child(0)
		var move := InputEventMouseMotion.new()
		move.position = Vector2(5,5)
		move.global_position = move.position
		get_viewport().push_input(move,true)
		for frame in range(18):
			await get_tree().process_frame
			var entry: Dictionary = battle.tabletop.cards[10]
			var points: PackedVector2Array = battle._hand_face_points(entry)
			var bounds := Rect2(points[0],Vector2.ZERO)
			for point in points: bounds = bounds.expand(point)
			if bounds.intersects(battle.player_status_hud.get_global_rect()):
				check(battle._hand_focus_overlays.has(returning.get_instance_id()) and battle._hand_focus_overlays[returning.get_instance_id()].face.visible,"lowering hand card must retain its foreground above HUD until it clears the bar")
			if frame==2: await capture("lowering-%d" % dimensions.x)
		await move_pointer(Vector2(5,5))
		for item in battle.hand_container.get_children(): check(item.scale.is_equal_approx(Vector2.ONE),"leaving hand must restore every card")
		var source: Control = battle.hand_container.get_child(2)
		var played: CardData = source.current_card_data
		var next: Control = battle.hand_container.get_child(3)
		var at := Vector2((source.global_position.x+next.global_position.x)*0.5,source.get_global_rect().get_center().y)
		await move_pointer(at)
		await _click(at)
		check(is_instance_valid(battle.card_inspector) and battle.card_inspector.visible,"clicking an exposed card must inspect it")
		if is_instance_valid(battle.card_inspector): battle.card_inspector.hide()
		await move_pointer(at)
		await _drag(at,Vector2(8,200))
		check(battle.game.player_hand.size()==8,"invalid drop must keep the card in hand")
		await move_pointer(at)
		await _drag(at,_center(battle.player_side_ui.get_child(3)))
		check(battle.game.player_field.slots[3]==played and battle.game.player_hand.size()==7,"dragging an overlapped card must deploy the selected card")
		battle.game.player_field.slots[3] = null
		battle.update_entire_screen()
		battle.game.player_hand.resize(6)
		battle._refresh_hand_ui()
		battle.update_entire_screen()
		await get_tree().create_timer(0.7).timeout
		await move_pointer(Vector2(5,5))
		var left: PackedVector2Array = battle._hand_face_points(battle.tabletop.cards[10])
		var right: PackedVector2Array = battle._hand_face_points(battle.tabletop.cards[15])
		check(left[1].y<left[0].y and right[1].y>right[0].y,"six separated cards must retain the curved fan")
		await capture("six-card-fan-%d"%dimensions.x)
	battle.queue_free()
	await get_tree().process_frame
	if not failed: print("TEST_HAND_OVERLAP_VISUAL_OK")
	get_tree().quit(1 if failed else 0)


func _drag(start: Vector2, target: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_viewport().push_input(press,true)
	await get_tree().process_frame
	var last := start
	for fraction in [0.2,0.4,0.7,1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = start.lerp(target,fraction)
		motion.global_position = motion.position
		motion.relative = motion.position-last
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = motion.position
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	await get_tree().process_frame
	check(get_viewport().gui_is_dragging(),"actual input must start the hand drag")
	var data: Dictionary = get_viewport().gui_get_drag_data()
	var overlay: Control = battle.player_status_hud.get_node("Margin/Content/ManaBar/ResourceCostPreview")
	check(not battle.hand_container.get_global_rect().has_point(target) and overlay.visible and overlay.get_meta("cost")==data.card_data.cost,"Elixir forecast must remain visible while dragging outside the hand")
	await capture("drag-forecast-%d" % get_window().size.x)
	var release := InputEventMouseButton.new()
	release.position = target
	release.global_position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	get_viewport().push_input(release,true)
	await get_tree().create_timer(0.25).timeout
	check(not overlay.visible,"dropping or cancelling the card must clear its Elixir forecast")

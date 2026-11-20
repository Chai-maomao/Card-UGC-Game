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
	get_window().size = Vector2i(1280,720)
	for direction in ["right","left","middle"]:
		battle.game.player_hand.clear()
		for i in range(8):
			var card := CardData.new("手牌%d"%(i+1),1,4,2)
			card.instance_id = direction+str(i)
			battle.game.player_hand.append(card)
		battle.game.player_field.current_mana = 10
		battle._refresh_hand_ui()
		battle.update_entire_screen()
		await get_tree().create_timer(0.7).timeout
		if direction=="right": await _verify_drag_over_hand()
		for remaining in [7,6,5]:
			var previous := {}
			var old_left: float = battle.tabletop.cards[10].root.position.x
			var old_right: float = battle.tabletop.cards[10+battle.game.player_hand.size()-1].root.position.x
			for index in range(battle.game.player_hand.size()):
				previous[battle.game.player_hand[index].instance_id] = battle.tabletop.cards[10+index].root.get_instance_id()
			var index: int = battle.game.player_hand.size()-1 if direction=="right" else (0 if direction=="left" else battle.game.player_hand.size()/2)
			var source: Control = battle.hand_container.get_child(index)
			var at := source.get_global_rect().get_center()
			if index<battle.hand_container.get_child_count()-1:
				at.x = (source.global_position.x+battle.hand_container.get_child(index+1).global_position.x)*0.5
			await _drag(at,_center(battle.discard_zone))
			await get_tree().create_timer(0.6).timeout
			check(battle.game.player_hand.size()==remaining,"real drag must discard the chosen hand card")
			for slot in range(battle.game.player_hand.size()):
				var card: CardData = battle.game.player_hand[slot]
				check(battle.tabletop.cards[10+slot].root.get_instance_id()==previous[card.instance_id],"discarding "+direction+" must preserve each surviving card mesh")
				var item: Control = battle.hand_container.get_child(slot)
				check(item.position.distance_to(item.get_meta("hand_rest_position"))<1.0,"discard must not leave a stale hover offset: %s/%d/%d actual=%s rest=%s focused=%s"%[direction,remaining,slot,item.position,item.get_meta("hand_rest_position"),item.get_meta("hand_focused",false)])
				var entry: Dictionary = battle.tabletop.cards[10+slot]
				check(entry.root.position.distance_to(entry.target)<0.02,"surviving cards must settle at their new positions")
			check(battle.tabletop.cards[10].root.position.x>old_left+0.01,"left edge must move inward after every discard")
			check(battle.tabletop.cards[10+remaining-1].root.position.x<old_right-0.01,"right edge must move inward after every discard")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/reflow-"+direction+"-"+str(remaining)+".png")
	battle.queue_free()
	await get_tree().process_frame
	if not failed: print("TEST_HAND_DISCARD_REFLOW_VISUAL_OK")
	get_tree().quit(1 if failed else 0)

func _verify_drag_over_hand() -> void:
	var source: Control = battle.hand_container.get_child(7)
	var start := source.get_global_rect().get_center()
	var target: Vector2 = battle.hand_container.get_child(2).get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_viewport().push_input(press,true)
	await get_tree().process_frame
	var last := start
	for fraction in [0.15,0.5,1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = start.lerp(target,fraction)
		motion.global_position = motion.position
		motion.relative = motion.position-last
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		last = motion.position
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	check(get_viewport().gui_is_dragging(),"moving across the hand must keep the actual card drag active")
	var layers := get_tree().root.find_children("TabletopDragForeground","CanvasLayer",true,false)
	check(layers.size()==1 and layers[0].layer>battle.get_node("CanvasLayer").layer,"dragged card must render above the hand canvas")
	if layers.size()==1: check(layers[0].offset.distance_to(target)<2,"drag foreground must follow the pointer while crossing cards")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/drag-over-hand.png")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(8,200)
	motion.global_position = motion.position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.position = motion.position
	release.global_position = release.position
	release.button_index = MOUSE_BUTTON_LEFT
	get_viewport().push_input(release,true)
	await get_tree().create_timer(0.3).timeout
	check(battle.game.player_hand.size()==8,"crossing the hand and cancelling must preserve all cards")

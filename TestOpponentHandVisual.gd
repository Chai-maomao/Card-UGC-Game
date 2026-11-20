extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _verify() -> void:
	get_window().size = Vector2i(1280,720)
	battle.my_player = 1
	battle.game.current_player = 1
	battle.game.turn_number = 3
	battle.game.is_player_turn = true
	battle.game.player_field.slots[0] = _caster()
	battle.game.player_field.action_points = 20
	battle.game.player2_hand = _hand("hidden")
	battle.update_entire_screen()
	await get_tree().create_timer(.6).timeout
	var picker = battle.opponent_hand_presentation
	assert(picker.backs.size()==6 and not picker.dim.visible,"opposing hand count must be represented by resting backs")
	await _hover(Vector2(1170, 350))
	await _capture("enemy-hand-rest")
	var original_layer: int = picker.layer
	var original_depths: Array = picker.backs.map(func(back): return back.z_index)
	var original_positions: Array = picker.backs.map(func(back): return back.position)
	var middle: Button = picker.backs[3]
	var edge := middle.get_global_transform_with_canvas() * Vector2(middle.size.x * 0.85, middle.size.y - 2)
	await _hover(edge)
	for index in range(picker.backs.size()):
		assert(is_equal_approx(picker.backs[index].position.x, original_positions[index].x))
		assert(picker.backs[index].position.y > original_positions[index].y + 16)
	assert(picker.layer == original_layer and picker.backs.map(func(back): return back.z_index) == original_depths)
	assert(not picker.dim.visible and not picker.accepting)
	await _capture("enemy-hand-hover")
	await _hover(Vector2(1170, 350))
	assert(middle.position.distance_to(original_positions[3]) < 0.2)
	var status_rect: Rect2 = battle.enemy_status_hud.get_global_rect()
	var through_status := Vector2(middle.get_global_rect().get_center().x, status_rect.get_center().y)
	assert(status_rect.has_point(through_status) and middle.get_global_rect().has_point(through_status))
	await _hover(through_status)
	assert(middle.position.y > original_positions[3].y + 16, "hovering a card back behind the status HUD must extend the hand")
	await _capture("enemy-hand-through-status")
	await _hover(Vector2(1170, 350))
	var expected = battle.game.copy_for_simulation()
	var blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	expected.trigger_activate_skills(0,-1,0)
	EventBus.set_block_signals(blocked)
	battle._on_skill_activated(0,0)
	await get_tree().create_timer(.7).timeout
	assert(picker.busy and picker.accepting and picker.dim.visible,"real discard-hand skill must open the opponent back picker")
	assert(battle.game.player2_hand.size()==4 and picker.backs.size()==6,"presentation must retain the pre-resolution backs while selection is pending")
	assert(battle._visible_pile_counts().y==0,"discard count must wait for the selected cards to land")
	assert(_ids(battle.game.player2_hand)==_ids(expected.player2_hand) and battle.game.game_rng.state==expected.game_rng.state,"presentation must retain the original random discard rule")
	var settled := BattleRepro.state_hash(battle.game)
	await _capture("enemy-hand-select")
	get_window().size = Vector2i(960,540)
	await get_tree().create_timer(.3).timeout
	await _capture("enemy-hand-select-960")
	assert(picker.backs.back().get_global_rect().end.x<960,"back selection must fit a smaller viewport")
	get_window().size = Vector2i(1280,720)
	await get_tree().create_timer(.3).timeout
	for count in [1,2]:
		var button: Button = picker.backs[0] if count==1 else picker.backs.back()
		var at := button.get_global_transform()*Vector2(button.size.x*(.2 if count==1 else .8),button.size.y*.7)
		await _click(at)
		await get_tree().create_timer(.56).timeout
		assert(not picker.accepting,"selection must lock while the chosen back flies")
		assert(button.has_node("RevealedDiscardFace") and not button.get_node("CardBackArtwork").visible,"chosen card must flip face-up before the discard flight")
		await _capture("enemy-hand-flight-%d"%count)
		await get_tree().create_timer(1.0).timeout
	assert(not picker.busy and not picker.dim.visible and picker.backs.size()==4,"picker must return to the resting hand after the last transfer")
	assert(battle._visible_pile_counts().y==2,"each landing must release its held discard count")
	assert(BattleRepro.state_hash(battle.game)==settled,"clicking arbitrary back positions must not change the authoritative result or RNG")
	# The affected player's perspective uses actual card faces, without a picker.
	battle.game.player_hand = _hand("mine")
	battle.game.player2_field.slots[0] = _caster()
	battle.game.player2_field.action_points = 20
	battle.game.current_player = 2
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().create_timer(.4).timeout
	var victim_state = battle.game.copy_for_simulation()
	var originals: Array = battle.game.player_hand.duplicate()
	EventBus.set_block_signals(true)
	victim_state.trigger_activate_skills(0,-1,0)
	EventBus.set_block_signals(blocked)
	var removed: Array = []
	for index in range(originals.size()):
		if not originals[index].instance_id in _ids(victim_state.player_hand): removed.append({"card":PlayerData.serialize_card(originals[index]),"index":index})
	var incoming := {"kind":"enemy_hand","player":2,"before_count":6,"cards":removed}
	var original_points: PackedVector2Array
	for source in battle.hand_container.get_children():
		if source.current_card_data.instance_id == str(removed[0].card.instance_id):
			original_points = battle._hand_face_points(battle.tabletop.cards[10+source.get_index()])
	battle._prime_remote_hand_entry(incoming,true)
	assert(incoming.cards[0].has("origin"),"remote victim must capture its real card location before applying the new state")
	var held: Polygon2D = picker.pending_own_faces[str(removed[0].card.instance_id)]
	var held_id := held.get_instance_id()
	for index in range(4):
		assert((held.polygon[index]+held.position).distance_to(original_points[index])<.1,"preserved face must match original projected size and angle")
	battle.game.apply_initial_state(victim_state.export_initial_state(),false)
	battle._refresh_hand_ui()
	await get_tree().create_timer(.18).timeout
	assert(is_instance_valid(held) and held.visible,"discarded face must remain visible while feedback waits")
	await _capture("enemy-discard-victim-wait")
	battle._queue_presentation_feedback([incoming])
	await get_tree().create_timer(.2).timeout
	assert(is_instance_valid(held) and held.get_instance_id()==held_id and held.position.distance_to((original_points[0]+original_points[1]+original_points[2]+original_points[3])*.25)>1,"same preserved face must fly directly without respawning")
	assert(not picker.accepting and not picker.dim.visible,"the victim must never see a back-selection interface")
	await _capture("enemy-discard-victim-view")
	await get_tree().create_timer(1.3).timeout
	assert(not picker.busy and battle.game.player_hand.size()==4,"victim transfer must finish normally")
	assert(picker.pending_own_faces.is_empty() and not is_instance_valid(held),"discard landing must release preserved faces")
	battle._show_combat_broadcast("一条新记录","system")
	battle._refresh_action_log_button()
	assert(battle.action_log_button.text==Locale.t("battle.action_log") and battle.action_log_button.get_node("UnreadDot").visible,"unread log must use a dot without changing the button text")
	await _capture("battle-log-unread-dot")
	await _click(battle.action_log_button.get_global_rect().get_center())
	await get_tree().process_frame
	assert(not battle.action_log_button.get_node("UnreadDot").visible,"opening the log must clear its dot")
	var printed: Image = battle.tabletop.cards[0].top.material_override.albedo_texture.get_image()
	assert(printed.get_pixel(0,0).a<.1 and printed.get_pixel(printed.get_width()/2,0).a>.9 and printed.get_pixel(printed.get_width()/2,printed.get_height()/2).a>.9,"rounded card must trim only its outer corners")
	# A real incoming attack triggers the same picker from an on-damaged passive,
	# even though it is currently the other player's turn.
	var defender := CardData.new("受击扰乱",1,8,1,[{"skill_name":"受击弃牌","trigger":"on_damaged","effects":[{"effect":"discard_hand","target":"self","value":1}]}])
	defender.instance_id = "passive-discard-defender"
	battle.game.player_field.slots = [defender,null,null,null,null]
	battle.game.player2_field.slots = [CardData.new("测试攻击者",1,4,1),null,null,null,null]
	battle.game.player2_field.action_points = 20
	battle.game.player2_hand = _hand("passive-hidden")
	battle.game.current_player = 2
	battle.update_entire_screen()
	await get_tree().create_timer(.3).timeout
	var attack: Dictionary = battle.game.execute_attack(0,0)
	assert(not attack.is_empty() and defender.hp==7 and battle.game.player2_hand.size()==5,"real damage must trigger the passive discard")
	for frame in range(180):
		if picker.accepting: break
		await get_tree().process_frame
	assert(picker.accepting and picker.dim.visible,"passive owner must select a back during the opponent's turn")
	var passive_back: Button = picker.backs.back()
	await _click(passive_back.get_global_transform()*Vector2(passive_back.size.x*.8,passive_back.size.y*.7))
	await get_tree().create_timer(.56).timeout
	assert(passive_back.has_node("RevealedDiscardFace"),"passive discard must reveal the chosen face")
	await _capture("enemy-passive-discard-reveal")
	await get_tree().create_timer(1.0).timeout
	assert(not picker.busy and not picker.dim.visible and battle.game.player2_hand.size()==5,"passive discard must finish without changing the resolved hand")
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_OPPONENT_HAND_VISUAL_OK")
	get_tree().quit(0)

func _caster() -> CardData:
	var card := CardData.new("扰乱者",1,5,1,[{"skill_name":"扰乱","trigger":"on_activate","effects":[{"effect":"discard_hand","target":"self","value":2}]}])
	card.instance_id = "caster-%d"%Time.get_ticks_usec()
	return card

func _hand(prefix: String) -> Array:
	var result: Array = []
	for index in range(6):
		var card := CardData.new(prefix+str(index),1,4,2)
		card.instance_id = prefix+str(index)
		result.append(card)
	return result

func _ids(cards: Array) -> Array:
	return cards.map(func(card): return card.instance_id)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/"+name+".png")


func _hover(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.35).timeout

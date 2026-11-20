extends Node

var failures: Array[String] = []

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer; run scripts/run_tests.ps1 -Suite visual")
		get_tree().quit(1)
		return
	var prior_acceleration := GamePreferences.animation_acceleration_enabled()
	GamePreferences.set_animation_acceleration(true)
	_assert(is_equal_approx(BattleFx.draw_card_arrival_delay(2), 0.575), "accelerated mode must preserve the previous draw timing")
	GamePreferences.set_animation_acceleration(false)
	_assert(is_equal_approx(BattleFx.draw_card_arrival_delay(2), 0.575 * GamePreferences.STANDARD_ANIMATION_DURATION_SCALE), "standard mode must slow the complete draw sequence")
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await _settle(12)
	await get_tree().create_timer(0.8).timeout

	# A defeated unit must produce a visible icon while travelling to the shared
	# discard pile; authoritative state has already resolved underneath it.
	battle.game.player_hand.clear()
	battle.game.player2_hand.clear()
	var fallen := CardData.new("余烬守卫", 2, 6, 3, [])
	battle.game.player_field.slots[0] = fallen
	battle.update_entire_screen()
	await _settle(4)
	fallen.hp = 0
	var discard_before_death: int = battle.game.shared_discard.size()
	battle._apply_deaths()
	await get_tree().create_timer(0.29).timeout
	_assert(_count_fx(battle, "death_discard_card") == 1, "defeated card must have one shared card-icon discard flight")
	_assert(battle._last_pile_counts.y==discard_before_death,"discard label must not include the fallen card before it lands")
	await _capture("card-death-discard-flow.png")
	await get_tree().create_timer(0.45).timeout
	_assert(battle.game.shared_discard.has(fallen), "defeated card must remain in the authoritative discard pile")
	_assert(battle._last_pile_counts.y==discard_before_death+1,"fallen card must increase the discard label on arrival")

	# A multi-card draw should read as an ordered stream instead of several
	# perfectly overlapping backs, then reveal the real cards at their slots.
	battle.game.player_hand.clear()
	battle.game.shared_deck = [
		CardData.new("晨星", 1, 4, 1, []),
		CardData.new("远望", 2, 5, 2, []),
		CardData.new("回响", 3, 6, 3, [{"skill_name":"回响", "trigger":"on_activate", "effects":[{"effect":"heal", "target":"self", "value":1}]}]),
	]
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await _settle(3)
	battle._on_game_draw_cards(3)
	await get_tree().create_timer(0.19).timeout
	_assert(_count_fx(battle, "draw_card") >= 2, "draw batch must visibly stagger multiple travelling cards")
	for child in battle.hand_container.get_children():
		_assert(not _arriving_card_is_visible(battle,child), "real hand cards must stay hidden until their travelling backs arrive")
		if battle.get("tabletop") != null:
			var input: Control = child.get_node("TabletopHandInput")
			_assert(not input._has_point(child.size*.5), "in-flight cards must have no mouse hit area")
			input._set_hover(true)
			_assert(not child.get_meta("hand_focused",false), "in-flight card must reject hover")
			_assert(input._get_drag_data(child.size*.5)==null, "in-flight card must reject drag data")
	if battle.get("tabletop") != null:
		var arriving: Control = battle.hand_container.get_child(battle.hand_container.get_child_count()-1)
		_assert(not arriving.tooltip_text.is_empty() and preload("res://UIHoverHints.gd").hint_for(arriving).is_empty(), "the arriving card must not expose its skill tooltip")
		var point := arriving.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		get_viewport().push_input(motion,true)
		var press := InputEventMouseButton.new()
		press.position = point
		press.button_index = MOUSE_BUTTON_LEFT
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.pressed = true
		get_viewport().push_input(press,true)
		motion = InputEventMouseMotion.new()
		motion.position = point+Vector2(45,-35)
		motion.relative = Vector2(45,-35)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await _settle(2)
		_assert(not get_viewport().gui_is_dragging() and not arriving.get_meta("hand_focused",false), "actual pointer must not hover or pick up an in-flight card")
		press.pressed = false
		press.button_mask = 0
		get_viewport().push_input(press,true)
	await _capture("card-draw-flow.png")
	await get_tree().create_timer(1.15).timeout
	_assert(battle.game.player_hand.size() == 3, "draw animation must not change resolved hand contents")
	for child in battle.hand_container.get_children():
		_assert(_arriving_card_is_visible(battle,child), "arriving hand cards must be fully visible after landing")
	if battle.get("tabletop") != null:
		var landed: Control = battle.hand_container.get_child(battle.hand_container.get_child_count()-1)
		var input: Control = landed.get_node("TabletopHandInput")
		_assert(input._has_point(landed.size*.5), "landed card must regain its mouse hit area")
		input._set_hover(true)
		_assert(landed.get_meta("hand_focused",false), "landed card must regain hover")
		input._set_hover(false)

	# Empty deck: recycle visibly before revealing any newly drawn cards.
	battle.game.player_hand.clear()
	battle.game.shared_deck.clear()
	battle.game.shared_discard = [CardData.new("归来一",1,4,1), CardData.new("归来二",2,4,2), CardData.new("归来三",3,4,3)]
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await _settle(4)
	battle._on_game_draw_cards(2)
	await get_tree().create_timer(0.20).timeout
	_assert(_count_fx(battle,"reshuffle_card") == 3,"recycling must show the discard cards flying back to the deck")
	_assert(_count_fx(battle,"draw_card") == 0,"draw flights must wait for the recycle flight")
	_assert(battle._last_pile_counts.x==0,"draw-pile count must wait for the returning cards")
	_assert(battle.game.player_hand.size()==2 and battle.game.shared_deck.size()==1 and battle.game.shared_discard.is_empty(),"recycle presentation must not defer or duplicate game rules")
	for child in battle.hand_container.get_children():
		_assert(not _arriving_card_is_visible(battle,child),"recycled draws must remain concealed during the shuffle")
	await _capture("card-reshuffle-flow.png")
	await get_tree().create_timer(0.20).timeout
	await _capture("card-reshuffle-midflight.png")
	await get_tree().create_timer(0.65).timeout
	_assert(_count_fx(battle,"reshuffle_card")==0 and _count_fx(battle,"draw_card")>0,"recycle must hand off to the normal draw animation")
	_assert(battle._last_pile_counts.x==battle.game.shared_deck.size(),"draw-pile count must settle when shuffle icons land")
	await get_tree().create_timer(1.2).timeout
	for child in battle.hand_container.get_children():
		_assert(_arriving_card_is_visible(battle,child),"recycled hand cards must reveal after landing")

	# Overflow resolves immediately, but its visible card passes the hand edge
	# before being redirected to discard, and never becomes a playable hand card.
	battle.game.player_hand.clear()
	for index in range(SkillEngine.MAX_HAND_SIZE):
		battle.game.player_hand.append(CardData.new("手牌%d"%index,1,4,1))
	var overflow_one := CardData.new("溢出卡一",2,5,2)
	var overflow_two := CardData.new("溢出卡二",3,6,3)
	battle.game.shared_deck = [overflow_one,overflow_two]
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await _settle(4)
	battle._on_game_draw_cards(2)
	await get_tree().create_timer(0.65).timeout
	_assert(_count_fx(battle,"overflow_card")==2,"each overflow card must have its own visible redirect flight")
	_assert(battle._last_pile_counts.y==0,"overflow cards must not increase the discard label in flight")
	_assert(battle.game.shared_discard.has(overflow_one) and battle.game.shared_discard.has(overflow_two),"overflow animation must preserve the resolved discard destination")
	await _capture("card-overflow-redirect.png")
	await get_tree().create_timer(1.8).timeout
	_assert(_count_fx(battle,"overflow_card")==0,"overflow flights must clean themselves up after landing")
	_assert(battle.game.player_hand.size()==SkillEngine.MAX_HAND_SIZE,"animation must never admit overflow cards into the hand")
	_assert(battle._last_pile_counts.y==2,"both overflow arrivals must update the discard label")

	# Manual discard flies from the actual drop position into the right pile. The card is already
	# removed. Multiple arrivals must each release exactly one displayed count.
	var manual_cards: Array = battle.game.player_hand.slice(0,2)
	var drop_offset: Vector2 = battle.discard_zone.size * Vector2(0.85,0.65)
	var drop_point: Vector2 = battle.discard_zone.get_global_transform() * drop_offset
	for card in manual_cards: battle.discard_zone._drop_data(drop_offset, {"card_data":card})
	var ghosts: Array = battle.get_node("CanvasLayer").get_children().filter(func(n): return n is Control and n.get_meta("battle_fx_kind", "") == "manual_discard_card")
	_assert(ghosts.size() == 2, "each dropped card must create a small transfer icon")
	for index in ghosts.size():
		var ghost = ghosts[index]
		_assert(ghost.get_script() == preload("res://presentation/DiscardAbsorb.gd") and ghost.texture != null and ghost.size.y < battle.hand_container.get_child(0).size.y * 0.5, "discard uses a small paper card icon instead of the full card view")
		_assert(ghost.get_global_rect().get_center().distance_to(drop_point) < 2, "discard flight starts at the release position")
	await get_tree().create_timer(0.20).timeout
	_assert(_count_fx(battle,"manual_discard_card")==2,"manual discards must have visible travelling cards")
	_assert(battle._last_pile_counts.y==2,"manual discard count must remain unchanged before landing")
	_assert(battle.game.shared_discard.size()==4 and battle.game.player_hand.size()==SkillEngine.MAX_HAND_SIZE-2,"presentation must leave immediate discard resolution intact")
	await _capture("manual-discard-in-flight.png")
	for ghost in ghosts:
		_assert(ghost.row_progress(1.0)>ghost.row_progress(0.0), "lower edge must enter the pile before the upper edge")
		var top_width: float=ghost.row_point(0.0,-1).distance_to(ghost.row_point(0.0,1))
		var bottom_width: float=ghost.row_point(1.0,-1).distance_to(ghost.row_point(1.0,1))
		_assert(bottom_width<top_width*0.8,"leading edge narrows into the pile")
		_assert(ghost.get_global_rect().get_center().distance_to(drop_point)<2,"absorption stays at the release position without an orbit")
	await get_tree().create_timer(0.16).timeout
	await _capture("manual-discard-absorb-tail.png")
	await get_tree().create_timer(0.9).timeout
	_assert(battle._last_pile_counts.y==4 and _count_fx(battle,"manual_discard_card")==0,"manual discard arrivals must add each card exactly once")
	_assert(battle._pile_arrivals.is_empty(),"completed card transfers must release their count holds")
	await get_tree().create_timer(0.35).timeout
	var field_discard := CardData.new("场上弃牌",0,4,1)
	battle.game.player_field.slots[3] = field_discard
	battle.update_entire_screen()
	await _settle(4)
	battle._on_card_discarded(field_discard)
	await get_tree().create_timer(0.2).timeout
	_assert(battle.game.player_field.slots[3]==null and battle._last_pile_counts.y==4,"field discard must resolve without advancing the visible count")
	await get_tree().create_timer(1.1).timeout
	_assert(battle._last_pile_counts.y==5,"field discard must increase the count only after its flight")

	# Rapid overlapping arrival pulses must always restore the pile's stable
	# style instead of capturing a red/orange in-flight tint as the next base.
	if battle._discard_pile_feedback_tween != null and battle._discard_pile_feedback_tween.is_running():
		await battle._discard_pile_feedback_tween.finished
	var discard_button: Control = battle.discard_pile_btn
	var rest_modulate := discard_button.modulate
	var rest_scale := discard_button.scale
	battle._play_discard_pile_arrival(Color(1.0, 0.25, 0.18, 1.0))
	await get_tree().create_timer(0.06).timeout
	battle._play_discard_pile_arrival(Color(1.0, 0.70, 0.42, 1.0))
	await get_tree().create_timer(0.55).timeout
	_assert(discard_button.modulate.is_equal_approx(rest_modulate), "overlapping discard pulses must restore the original color")
	_assert(discard_button.scale.is_equal_approx(rest_scale), "overlapping discard pulses must restore the original scale")

	# Hero HP stays at its old value while a wave travels, then changes per hit.
	for speed in [GamePreferences.PlaybackSpeed.FAST,GamePreferences.PlaybackSpeed.MEDIUM,GamePreferences.PlaybackSpeed.DEFAULT]:
		GamePreferences.set_battle_playback_speed(speed)
		var scale_time := GamePreferences.battle_animation_duration_scale()
		battle.game.current_player = 1
		battle.game.turn_number = 3
		battle.game.player_field.slots.fill(null)
		battle.game.player2_field.slots.fill(null)
		battle.game.player_field.slots[0] = CardData.new("第一击",0,4,2)
		battle.game.player_field.slots[1] = CardData.new("第二击",0,4,3)
		battle.game.player_field.action_points = 10
		battle.game.player_field.current_mana = 10
		battle.game.player2_field.player_hp = 30
		battle.update_entire_screen()
		await get_tree().create_timer(0.5).timeout
		var hp: ProgressBar = battle.enemy_status_hud.get_node("Margin/Content/HpBar")
		var label: Label = battle.enemy_status_hud.get_node("Margin/Content/HpLabel")
		var result: Dictionary = battle.game.end_player_turn()
		_assert(int(result.total_damage)==5,"hero strike fixture must resolve both real attacks")
		battle._show_direct_damage(result)
		battle.update_entire_screen()
		await get_tree().create_timer(0.10*scale_time).timeout
		_assert(is_equal_approx(hp.value,30),"hero HP must not drop before the first wave arrives")
		await get_tree().create_timer(0.31*scale_time).timeout
		_assert(is_equal_approx(hp.value,28) and label.text.contains("28/30"),"first impact must remove only its own two HP from bar and label")
		var damage_number := battle.get_node("CanvasLayer/StatusFxValue") as Label
		_assert(damage_number != null and damage_number.text == "-2"
			and get_viewport().get_visible_rect().encloses(damage_number.get_global_rect()),
			"the first hit's damage number must remain inside the viewport")
		if speed == GamePreferences.PlaybackSpeed.MEDIUM: await _capture("hero-first-impact-hp.png")
		await battle._wait_for_direct_damage()
		_assert(is_equal_approx(hp.value,25) and label.text.contains("25/30"),"second impact must remove its own three HP")
		_assert(battle.game.player2_field.player_hp==25,"visual hits must never apply damage a second time")
		_assert(battle._hero_hp_shown.is_empty(),"hero HP presentation overrides must clear on completion")

	# AI end-turn uses the player's HUD and must flash on every impact too.
	PlayerData.battle_mode = "practice"
	GamePreferences.set_animation_acceleration(true)
	battle.game.current_player = 2
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player2_field.slots[0] = CardData.new("AI第一击",0,4,2)
	battle.game.player2_field.slots[1] = CardData.new("AI第二击",0,4,3)
	battle.game.player2_field.action_points = 10
	battle.game.player2_field.current_mana = 10
	battle.game.player_field.player_hp = 30
	battle.update_entire_screen()
	await get_tree().create_timer(0.5).timeout
	battle._run_local_end_turn()
	await get_tree().create_timer(0.24).timeout
	var ai_bar: ProgressBar = battle.player_status_hud.get_node("Margin/Content/HpBar")
	var first_flash := ai_bar.find_child("StatusFx_Damage",false,false) as Panel
	_assert(first_flash != null and first_flash.is_visible_in_tree() and first_flash.modulate.a>0.5,"AI first hit must flash the actual player HP bar")
	await get_tree().create_timer(0.29).timeout
	_assert(ai_bar.find_children("StatusFx_Damage*","Panel",false,false).size()>=2,"AI second hit must create its own red flash")
	await _capture("hero-ai-impact-flash.png")
	await battle._wait_for_direct_damage()
	await get_tree().create_timer(0.65).timeout
	_assert(battle.game.player_field.player_hp==25,"AI hit presentation must preserve resolved HP")
	# Leaving a battlefield mid-lunge or mid-recoil must cancel callbacks that
	# reference its layer. The runner rejects engine errors after teardown.
	for interruption_time in [0.04, 0.20]:
		var layer := CanvasLayer.new()
		add_child(layer)
		var card: Control = preload("res://CardUI.tscn").instantiate()
		layer.add_child(card)
		card.set_card(CardData.new("Exit during attack", 0, 6, 1))
		BattleFx.attack_lunge(layer, card, Vector2(420, 240))
		await get_tree().create_timer(interruption_time).timeout
		layer.free()
		await get_tree().create_timer(0.4).timeout

	# Reading the log consumes inner clicks; an outer click dismisses it.
	battle._toggle_action_log()
	await _settle(3)
	await _click(battle.action_log_text.get_global_rect().get_center())
	_assert(battle.action_log_panel.visible,"clicking inside the battle log must keep it open")
	await _click(Vector2(5,get_viewport().get_visible_rect().size.y/2))
	_assert(not battle.action_log_panel.visible,"clicking outside the battle log must dismiss it")
	await _click(battle.field_rules_btn.get_global_rect().get_center())
	await get_tree().create_timer(0.3).timeout
	_assert(battle.has_node("BattleFieldRules"),"field-rules toolbar button must open the current rules")
	await _capture("battle-field-rules.png")
	await _click(Vector2(5,get_viewport().get_visible_rect().size.y/2))
	await _settle(3)
	for key in ["action_base","action_empty_slot_factor","action_empty_hand_factor","action_mana_factor"]:
		battle.game.battle_config.erase(key)
	battle.game.reset_action_budget(1)
	battle.update_entire_screen()
	await _settle(4)
	_assert(not battle.player_status_hud.get_node("Margin/Content/ActionBar").visible,"disabled action rules must hide the action bar in battle")
	await _click(battle.field_rules_btn.get_global_rect().get_center())
	await get_tree().create_timer(0.3).timeout
	var rules := battle.get_node("BattleFieldRules").find_child("FieldRuleRows",true,false)
	_assert(rules.get_child(0).get_child(1).text=="关闭","field rules must show the current match action toggle as off")
	await _capture("battle-field-rules-disabled.png")
	await _click(Vector2(5,get_viewport().get_visible_rect().size.y/2))
	await _settle(3)
	battle.queue_free()
	await _settle(4)
	PlayerData.battle_select_mode = "practice"
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	var preparation = load("res://BattleDeckSelect.tscn").instantiate()
	add_child(preparation)
	await _settle(6)
	for enabled in [false,true]:
		preparation._show_battle_config_popup()
		await get_tree().create_timer(0.3).timeout
		var toggle := preparation.advanced_layer.find_child("ActionEnabledToggle",true,false) as BaseButton
		await _click(toggle.get_global_rect().get_center())
		_assert(toggle.button_pressed==enabled,"preparation toggle must change action-point mode")
		await _capture("battle-action-toggle-%s.png" % str(enabled))
		for button in preparation.advanced_layer.find_children("*","Button",true,false):
			if button.text==Locale.t("common.confirm"):
				await _click(button.get_global_rect().get_center())
				break
		await _settle(3)
		_assert(PlayerData.battle_config.has("action_base")==enabled and MatchAgreement.valid_config(PlayerData.battle_config),"confirmed rules must preserve enabled/disabled mode in the agreed config")
	preparation.queue_free()
	GamePreferences.set_animation_acceleration(prior_acceleration)

	if failures.is_empty():
		print("TEST_CARD_FLOW_ANIMATION_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_CARD_FLOW_ANIMATION_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _count_fx(battle: Node, kind: String) -> int:
	var count := 0
	var layer: CanvasLayer = battle.get_node("CanvasLayer")
	for child in layer.get_children():
		if str(child.get_meta("battle_fx_kind", "")) == kind:
			count += 1
	return count


func _click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event,true)
		await get_tree().process_frame


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://artifacts/" + file_name)
	_assert(result == OK, "failed to save " + file_name)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _arriving_card_is_visible(battle: Node, control: Control) -> bool:
	var table = battle.get("tabletop")
	if table == null: return control.modulate.a >= 0.99
	var card: CardData = control.current_card_data
	for key in table.cards:
		var entry: Dictionary = table.cards[key]
		if key >= 10 and entry.id == card.instance_id:
			return entry.root.is_visible_in_tree() and entry.top.visible and entry.top.material_override.albedo_color.a >= 0.99
	return false

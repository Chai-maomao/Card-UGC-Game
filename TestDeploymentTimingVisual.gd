extends Node

var failures: Array[String] = []

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.FAST)
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(2.5).timeout
	var audio := not AppAudio.players.is_empty()
	for speed in [GamePreferences.PlaybackSpeed.DEFAULT, GamePreferences.PlaybackSpeed.MEDIUM, GamePreferences.PlaybackSpeed.FAST]:
		GamePreferences.set_battle_playback_speed(speed)
		battle.game.current_player = 1
		battle.game.is_player_turn = true
		battle.game.turn_number = 2
		battle.game.player_field.slots.fill(null)
		battle.game.player2_field.slots.fill(null)
		battle.game.player_field.current_mana = 10
		battle.game.player_hand.clear()
		battle.game.player2_hand.clear()
		battle.game.shared_discard.clear()
		battle.game.shared_deck = [CardData.new("情报", 0, 1, 0, [])]
		var scout: CardData = CardDatabase.beginner_deck()[0]
		battle.game.player_hand.append(scout)
		battle.reset_hand_ui_from_game_state()
		battle.update_entire_screen()
		await get_tree().process_frame
		await get_tree().process_frame
		AppAudio._last_sound.clear()
		var started := Time.get_ticks_msec()
		battle._on_card_drag_summoned(scout, null, 0)
		_check(battle.game.player_field.slots[0] == scout and battle.game.player_hand.size() == 1, "deployment and skill rules remain immediate")
		await get_tree().create_timer(0.18).timeout
		if audio: _check(not AppAudio._last_sound.has("draw_single"), "draw sound must wait after landing at speed %d" % speed)
		var arriving := battle.hand_container.get_child(0) as Control
		_check(not _hand_visible(battle, arriving), "drawn card stays hidden until its delayed flight arrives")
		if speed == GamePreferences.PlaybackSpeed.DEFAULT: await _capture("deployment-hold.png")
		await get_tree().create_timer(1.0).timeout
		if audio:
			var deploy_at := int(AppAudio._last_sound.get("summon", -1))
			var draw_at := int(AppAudio._last_sound.get("draw_single", -1))
			_check(deploy_at >= started and draw_at - deploy_at >= 300, "single draw must follow deployment by a readable beat")
			print("DEPLOY_DRAW_TIMING speed=%d separation_ms=%d" % [speed, draw_at-deploy_at])
		await get_tree().create_timer(1.0).timeout
		_check(_hand_visible(battle, arriving), "delayed drawn card eventually arrives")
		if speed == GamePreferences.PlaybackSpeed.DEFAULT: await _capture("deployment-draw-arrived.png")
	# Authority playback must use the same landing beat, including fast mode.
	AppAudio._last_sound.clear()
	battle._replay_feedback_event({"kind":"summon", "player":1, "slot":0})
	battle._replay_feedback_event({"kind":"broadcast", "event":{"kind":"summon_skill", "player":1, "source":"侦察兵", "presentation_events":[{"kind":"effect", "effect_id":SkillEngine.EFFECT_ADD_BUFF, "feedback_group":1, "targets":[{"player":1,"slot":0}]}]}})
	await get_tree().create_timer(0.18).timeout
	if audio: _check(not AppAudio._last_sound.has("dark_magic"), "remote skill feedback must wait for landing")
	await get_tree().create_timer(0.5).timeout
	if audio: _check(AppAudio._last_sound.has("dark_magic"), "remote skill feedback eventually plays")
	# Clicking the real button through a deployment resolution blocker must
	# acknowledge once, wait for the summoned skill, then run end-turn skills.
	battle.game.current_player = 1
	battle.game.is_player_turn = true
	battle.game.turn_number = 4
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.current_mana = 10
	battle.game.player_hand.clear()
	battle.game.shared_deck = [CardData.new("召唤抽牌",0,1,0)]
	var queued_card := CardData.new("等待召唤结算",0,5,0,[
		{"skill_name":"入场抽牌","trigger":"on_summon","effects":[{"effect":"draw_cards","target":"self","value":1}]},
		{"skill_name":"结束自疗","trigger":"on_turn_end","effects":[{"effect":"heal","target":"self","value":1}]}])
	battle.game.player_hand.append(queued_card)
	battle.reset_hand_ui_from_game_state()
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	battle._on_card_drag_summoned(queued_card,null,0)
	queued_card.hp = 3
	await get_tree().create_timer(.08).timeout
	_check(battle._deployment_feedback_delay()>0,"click must occur during deployment hold")
	await preload("res://tests/VisualBattleInput.gd").click(get_viewport(),battle.end_turn_button.get_global_rect().get_center())
	_check(battle.end_turn_button.disabled and battle._turn_ending,"queued end turn must immediately disable the button")
	_check(battle.game.current_player==1 and queued_card.hp==3,"end-turn healing must wait for summon feedback")
	await _capture("end-turn-queued.png")
	for frame in range(360):
		if battle.game.current_player==2: break
		await get_tree().process_frame
	_check(battle.game.current_player==2 and queued_card.hp==4,"queued request must finish once and run end-turn healing after summoning")
	await get_tree().create_timer(.6).timeout
	battle.queue_free()
	await get_tree().process_frame
	AppAudio._exit_tree()
	await get_tree().create_timer(0.2).timeout
	if failures.is_empty():
		print("TEST_DEPLOYMENT_TIMING_VISUAL_OK audio=%s" % audio)
		get_tree().quit(0)
	else:
		for message in failures: push_error("TEST_DEPLOYMENT_TIMING_VISUAL_FAILED: " + message)
		get_tree().quit(1)

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _hand_visible(battle: Node, proxy: Control) -> bool:
	if battle.tabletop == null: return proxy.modulate.a > 0.99
	return battle.tabletop.cards.has(10) and battle.tabletop.cards[10].root.visible

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/deployment-timing-20261114/" + name)

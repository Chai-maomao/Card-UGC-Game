extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	if OS.get_cmdline_user_args().has("--small"):
		AppPreferences.set_value("window_mode", 1)

func _verify() -> void:
	battle.reparent(get_tree().root)
	get_tree().current_scene = battle
	GamePreferences.set_animation_acceleration(true)
	await _win_battle()
	var result := battle.get_node("CanvasLayer/BattleResultLayer")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/battle-result.png")
	var again := _result_button(result,Locale.t("result.play_again"))
	assert(again != null and again.is_visible_in_tree(),"finished battle must offer another game")
	await _click(again.get_global_rect().get_center())
	await get_tree().scene_changed
	battle = get_tree().current_scene
	await get_tree().create_timer(1.5).timeout
	assert(battle.scene_file_path == "res://Main.tscn" and not battle.battle_finished,"play again must create a fresh battle")
	assert(battle.game.turn_number == 1 and battle.game.player2_field.player_hp == battle.game.player2_field.max_player_hp,"new battle must reset turn and health")
	await _win_battle()
	result = battle.get_node("CanvasLayer/BattleResultLayer")
	await _click(_result_button(result,Locale.t("result.back_menu")).get_global_rect().get_center())
	await get_tree().scene_changed
	await get_tree().create_timer(.5).timeout
	assert(get_tree().current_scene.scene_file_path == "res://MainMenu.tscn" and not NetworkManager.is_online,"result exit must return to an offline title page")
	assert(UIMotion.history_depth() == 0,"Back must not resurrect either finished battle")
	var practice_deck := CardDatabase.beginner_deck()
	PlayerData.configure_practice_battle(practice_deck, practice_deck)
	UIMotion.replace_scene("res://Main.tscn", true)
	await get_tree().scene_changed
	battle = get_tree().current_scene
	await get_tree().create_timer(1.5).timeout
	if not await _win_with_skill():
		get_tree().quit(1)
		return
	result = battle.get_node("CanvasLayer/BattleResultLayer")
	var summary := Locale.t("result.summary_personal", [battle.game.turn_number, battle.game.player_field.player_hp, 0])
	var result_labels := result.find_children("*", "Label", true, false).map(func(label: Label): return label.text)
	if not result_labels.has(Locale.t("result.practice_win")) or not result_labels.has(summary):
		push_error("practice results must show the player's health first")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/practice-result.png")
	await _click(_result_button(result, Locale.t("result.back_menu")).get_global_rect().get_center())
	await get_tree().scene_changed
	# Exercise the online result route without creating a network transport.
	UIMotion.replace_scene("res://Main.tscn",true)
	await get_tree().scene_changed
	battle = get_tree().current_scene
	await get_tree().create_timer(1.5).timeout
	NetworkManager.is_online = true
	NetworkManager.is_host = true
	PlayerData.battle_mode = "multiplayer"
	battle.my_player = 1
	var pause := preload("res://presentation/BattlePause.gd").new()
	pause.battle = battle
	battle.add_child(pause)
	await get_tree().process_frame
	battle.game.player2_field.player_hp = 0
	assert(battle._check_and_show_game_over(), "the online result must be produced by battle completion")
	await get_tree().create_timer(.4).timeout
	result = battle.get_node("CanvasLayer/BattleResultLayer")
	var back := _result_button(result, Locale.t("result.back_multiplayer"))
	if UIMotion.top_popup() != result or is_instance_valid(pause) or back == null or not back.has_focus():
		push_error("normal online results must close the pause overlay and focus their return action")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/online-result-keyboard.png")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().create_timer(.5).timeout
	var menu := get_tree().current_scene
	if menu.get_node_or_null("OnlineModePopup") == null or not is_instance_valid(menu.battle_hub_layer):
		push_error("Escape from a completed battle must restore connection choices above the battle hub")
		get_tree().quit(1)
		return
	assert(not NetworkManager.is_online and UIMotion.history_depth() == 0,"online result exit must close the transport and discard finished-battle navigation")
	print("TEST_BATTLE_REPLAY_JOURNEY_VISUAL_OK")
	get_tree().quit(0)

func _win_with_skill() -> bool:
	GamePreferences.set_animation_acceleration(false)
	var hit := {"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ENEMY,
		"effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
	battle.game.player_field.slots[2] = CardData.new("终结测试", 0, 5, 1, [{
		"skill_name": "最后一击", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [hit, hit.duplicate()]
	}])
	battle.game.turn_number = 3
	battle.game.player2_field.player_hp = 2
	battle.game.player_field.action_points = 20
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	battle._on_skill_activated(2, 0)
	if (battle.game.player2_field.player_hp != 0 or battle.is_my_turn()
			or battle.get_node_or_null("CanvasLayer/BattleResultLayer") != null):
		push_error("a lethal skill must resolve immediately, lock input, and finish its feedback before results")
		return false
	battle._show_abandon_confirmation()
	if battle.has_node("AbandonBattleConfirmation"):
		push_error("the battle must not offer surrender after the winning move has settled")
		return false
	var deadline := Time.get_ticks_msec() + 5000
	while battle.get_node_or_null("CanvasLayer/BattleResultLayer") == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	GamePreferences.set_animation_acceleration(true)
	if battle.get_node_or_null("CanvasLayer/BattleResultLayer") == null:
		push_error("applying lethal skill damage must finish the battle without another player action")
		return false
	await get_tree().create_timer(.5).timeout
	return true

func _win_battle() -> void:
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.slots[2] = CardData.new("收尾测试",0,5,3)
	battle.game.player2_field.player_hp = 2
	battle.game.turn_number = 3
	battle.game.player_field.action_points = 20
	battle.game.player_field.actions_taken = 0
	battle.update_entire_screen()
	await get_tree().create_timer(.3).timeout
	await _click(battle.end_turn_button.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 10000
	while battle.get_node_or_null("CanvasLayer/BattleResultLayer") == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(battle.game.player2_field.player_hp <= 0 and battle.get_node_or_null("CanvasLayer/BattleResultLayer") != null,"a real lethal end-turn attack must reach the result page")
	await get_tree().create_timer(.5).timeout

func _result_button(root: Node,label: String) -> Button:
	for child in root.find_children("*","Button",true,false):
		if child.text == label: return child
	return null

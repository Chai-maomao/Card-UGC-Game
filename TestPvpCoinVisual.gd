extends Node

const EVIDENCE := "res://artifacts/pvp-opening-coin"
var failures: Array[String] = []
var stage: SubViewport


func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)


func _ready() -> void:
	NetworkManager.close_connection()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	AppPreferences.set_value("reduced_motion", false)
	if "--interrupt-only" in OS.get_cmdline_user_args():
		await _interrupt_toss()
		_finish()
		return
	await _exercise_toss(1, "gold", true)
	stage.size = Vector2i(960, 540)
	await _exercise_toss(2, "jade", false)
	AppPreferences.set_value("reduced_motion", true)
	await _exercise_toss(2, "reduced-motion", false)
	await _check_guest_opening_art()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("TEST_PVP_COIN_VISUAL_OK")
	for failure in failures:
		push_error("TEST_PVP_COIN_VISUAL_FAILED: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _interrupt_toss() -> void:
	var coin := preload("res://presentation/PvpCoinToss.gd").new()
	var revealed: Array[bool] = []
	coin.finished.connect(func(): revealed.append(true))
	stage.add_child(coin)
	var deadline := Time.get_ticks_msec() + 1700
	while coin._coin.position.y < 0.42 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(coin._coin.position.y >= 0.42 and coin._result.text.is_empty(), "the interruption must happen during the flight")
	coin.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(coin) and revealed.is_empty(), "interrupting the toss must not publish a result")


func _exercise_toss(winner: int, label: String, take_flight_capture: bool) -> void:
	var deck := CardDatabase.beginner_deck()
	PlayerData.configure_hotseat_battle(deck, deck)
	PlayerData.hotseat_opening_player = winner
	var battle = preload("res://Main.tscn").instantiate()
	stage.add_child(battle)
	await get_tree().process_frame
	var coin = battle.get_node_or_null("PvpOpeningCoin")
	if coin == null:
		failures.append("the native battle did not present its opening coin")
		battle.queue_free()
		return
	battle._on_end_turn_pressed()
	_check(battle._opening_coin_active and not battle.is_my_turn() and battle.game.current_player == winner,
		"the reveal must block input and keep the player picked at setup")
	_check(battle.end_turn_button.disabled, "the End Turn button must look unavailable during the opening reveal")
	_check(UIMotion.top_popup() == coin and UIMotion.close_top_popup() and coin.visible and not coin.is_queued_for_deletion(),
		"Back must be consumed by the opening reveal until it finishes")
	if take_flight_capture:
		var rise_deadline := Time.get_ticks_msec() + 1400
		while coin._coin.position.y < 0.42 and Time.get_ticks_msec() < rise_deadline:
			await get_tree().process_frame
		_check(coin._coin.position.y >= 0.42, "the modeled coin must visibly rise before it lands")
		await _capture("flight.png")
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(coin) and coin._result.text.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(coin) and coin._result.text == Locale.t("battle.coin_player_first", [winner]):
		await _capture(label + ".png")
	else:
		failures.append("the coin did not display the selected player for " + label)
	while battle._opening_coin_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not battle._opening_coin_active and battle.game.current_player == winner, "the reveal must return control to the opening player")
	_check(UIMotion.top_popup() == null or UIMotion.top_popup() != coin, "the completed opening reveal must leave the popup stack")
	_check(not battle.end_turn_button.disabled, "the opening player can end the turn after the reveal")
	battle.queue_free()
	await get_tree().process_frame


func _check_guest_opening_art() -> void:
	stage.size = Vector2i(1280, 720)
	AppPreferences.set_value("reduced_motion", false)
	var local := PlayerData.prepare_deck_card(CardData.new("逆光旅人", 2, 4, 3))
	var art := Image.create(32, 32, false, Image.FORMAT_RGB8)
	art.fill(Color("2ebc9c"))
	local.art_path = "user://opening-art-fixture.png"
	_check(art.save_png(local.art_path) == OK, "save the guest's local illustration")
	var remote := PlayerData.prepare_deck_card(local)
	remote.art_path = "user://net_arts/host-only-art.png"
	var other := PlayerData.prepare_deck_card(CardData.new("行商", 1, 2, 1))
	NetworkManager.is_online = true
	NetworkManager.player_number = 2
	NetworkManager.match_opening_player = 2
	PlayerData.battle_deck = [local]
	PlayerData.opponent_battle_deck = [remote, other]
	PlayerData.battle_mode = "multiplayer"
	var battle = preload("res://Main.tscn").instantiate()
	stage.add_child(battle)
	await get_tree().process_frame
	_check(battle._opening_coin_active and battle.has_node("PvpOpeningCoin"), "the fixture must sync during the guest's opening toss")
	var snapshot: Dictionary = battle.game.export_initial_state()
	snapshot.player2_hand = [PlayerData.serialize_card(remote)]
	battle._on_rpc_initial_state(snapshot)
	await get_tree().process_frame
	_check_guest_hand_art(battle, art.get_pixel(16, 16), "during the opening toss")
	var deadline := Time.get_ticks_msec() + 3200
	while battle._opening_coin_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not battle._opening_coin_active, "the guest's opening toss must finish")
	_check_guest_hand_art(battle, art.get_pixel(16, 16), "after the opening toss")
	await _capture("guest-opening-card-art.png")
	battle.queue_free()
	await get_tree().process_frame
	NetworkManager.close_connection()


func _check_guest_hand_art(battle: Node, expected: Color, timing: String) -> void:
	var hand: Container = battle.hand_container
	var face: Texture2D = hand.get_child(0)._printed_face.art if hand.get_child_count() == 1 else null
	_check(face != null and face.get_width() == 32 and face.get_image().get_pixel(16, 16).is_equal_approx(expected),
		"the guest's hand must show the local illustration " + timing)


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(stage.get_texture().get_image().save_png(EVIDENCE.path_join(filename)) == OK, "could not save " + filename)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

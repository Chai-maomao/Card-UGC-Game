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
	_check(not battle.end_turn_button.disabled, "the opening player can end the turn after the reveal")
	battle.queue_free()
	await get_tree().process_frame


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(stage.get_texture().get_image().save_png(EVIDENCE.path_join(filename)) == OK, "could not save " + filename)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

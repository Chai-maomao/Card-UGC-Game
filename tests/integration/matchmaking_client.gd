extends Node

var _deadline := 0
var _capture_dir := ""
var _opening_view: Dictionary


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_deadline = Time.get_ticks_msec() + 26000
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--language="):
			Locale.set_language(argument.get_slice("=", 1))
		elif argument.begins_with("--capture="):
			_capture_dir = argument.substr("--capture=".length())
		elif argument.begins_with("--window-size="):
			var dimensions := argument.get_slice("=", 1).split("x")
			get_window().size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument == "--light":
			AppPreferences.set_value("appearance", 1)
	var mode := "ranked" if OS.get_cmdline_user_args().has("--ranked") else "random"
	var retry_entry := OS.get_cmdline_user_args().has("--retry-entry")
	if retry_entry:
		PlayerData.matchmaking_endpoint = "127.0.0.1:1"
	var surrender := OS.get_cmdline_user_args().has("--surrender")
	var cards: Array = []
	for index in 8:
		var attack := (0 if index % 2 == 0 else 8) if surrender else 4
		var prefix := "Variable" if surrender else "Stable"
		cards.append(CardData.new("%s %d" % [prefix, index + 1], 2, 1, attack, []))
	var custom_deck := PlayerData.create_deck("Matchmaking Custom", cards)
	get_tree().current_scene = null
	assert(get_tree().change_scene_to_file("res://MainMenu.tscn") == OK)
	await get_tree().scene_changed
	var menu = get_tree().current_scene
	menu._show_battle_hub_popup()
	menu._show_battle_mode_popup(true)
	menu._show_online_match_choices(true)
	menu._title_choices.back().find_choice(Locale.t("matchmaking." + mode)).pressed.emit()
	await get_tree().scene_changed
	var lobby = get_tree().current_scene
	assert(lobby.scene_file_path == "res://MatchmakingLobby.tscn")
	if retry_entry and mode == "random":
		lobby._action.pressed.emit()
	while lobby._action.disabled:
		await _pause()
	if retry_entry:
		assert(lobby._status.text == Locale.t("matchmaking.unavailable"))
		assert(lobby._action.text == Locale.t("launch.retry_search"))
		await _capture("connection-error")
		lobby._server_settings.pressed.emit()
		assert(lobby._server.visible)
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--matchmaking-endpoint="):
				lobby._server.text = argument.trim_prefix("--matchmaking-endpoint=")
		lobby._server_settings.pressed.emit()
	elif mode == "ranked":
		assert(lobby._rank_row.visible and lobby._rating.text.contains("1000"))
		assert(lobby._rank_name.text == Locale.t("matchmaking.rank_silver"))
		lobby._rank_badge.grab_focus()
		lobby._rank_badge.pressed.emit()
		await get_tree().process_frame
		var ladder: Node = lobby.get_node_or_null("RankLadder")
		assert(ladder != null and UIMotion.top_popup() == ladder)
		var labels := ladder.find_children("*", "Label", true, false)
		assert(labels.any(func(label): return label.text == Locale.t("matchmaking.ladder_current")))
		assert(labels.any(func(label): return label.text == Locale.t("matchmaking.ladder_top", [1750])))
		await _capture("rank-ladder")
		var back := ladder.find_children("*", "Button", true, false)[0] as Button
		back.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		assert(UIMotion.top_popup() == null and get_viewport().gui_get_focus_owner() == lobby._rank_badge)
	assert(lobby._preparation == null)
	await _capture("entry")
	var room := NetworkManager.team_room
	var opponent := {"seated": false, "ready": false, "cancelled": false}
	room.changed.connect(func():
		if room.local_seat == 0 or room.started:
			return
		if room.occupied.size() == 2:
			opponent.seated = true
		if room.ready_seats.has(3 - room.local_seat):
			opponent.ready = true
		elif opponent.ready:
			opponent.cancelled = true)
	room.battle_started.connect(func(): _opening_view = room.view.duplicate(true), CONNECT_ONE_SHOT)
	lobby._action.pressed.emit()
	while not lobby._queued:
		await _pause()
	print("TEST_MATCHMAKING_WAITING ", mode)
	if retry_entry:
		await _pause()
		assert(lobby._phase == "join" and lobby._status.text.begins_with(Locale.t("matchmaking.searching", [0]).get_slice("0", 0)))
		await _capture("search")
	if OS.get_cmdline_user_args().has("--cancel-only"):
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--cancel-pending-in="):
				var directory := argument.trim_prefix("--cancel-pending-in=")
				while not Array(DirAccess.get_files_at(directory)).any(func(file): return file.ends_with(".pending")):
					await _pause()
				assert(lobby._queued)
		assert(lobby._action.text == Locale.t("matchmaking.cancel"))
		lobby._action.pressed.emit()
		assert(not lobby._queued and not NetworkManager.is_online and not NetworkManager.team_room.is_open())
		assert(lobby._action.text == Locale.t("matchmaking.start"))
		if mode == "ranked":
			_verify_rating_journal()
		print("TEST_MATCHMAKING_CANCEL_OK ", mode)
		get_tree().quit()
		return
	while not is_instance_valid(lobby._preparation):
		await _pause()
	var preparation = lobby._preparation
	assert(room.local_seat > 0 and not room.started and not room.ready_seats.has(room.local_seat))
	for tile in preparation.deck_tiles:
		if tile.deck_id == custom_deck.id:
			tile.pressed.emit()
	assert(preparation.selected_deck_id == custom_deck.id)
	var preview := 0.0
	if mode == "ranked":
		preview = float(preparation._room_coefficient.text.get_slice("×", 1))
		assert(preview == (0.95 if surrender else 1.13), preparation._room_coefficient.text)
	else:
		assert(not preparation._room_coefficient.visible)
	await _capture("preparation")
	var leave_test := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--leave-room-marker="):
			leave_test = argument.trim_prefix("--leave-room-marker=")
	if not leave_test.is_empty():
		while not opponent.seated:
			await _pause()
		if surrender:
			while not FileAccess.file_exists(leave_test):
				await _pause()
			preparation.back_button.pressed.emit()
			assert(is_instance_valid(lobby._leave_dialog) and lobby._leave_dialog.visible)
			lobby._leave_dialog.canceled.emit()
			assert(room.is_open() and is_instance_valid(lobby._preparation))
			preparation.back_button.pressed.emit()
			await _capture("leave-room")
			lobby._leave_dialog.confirmed.emit()
		else:
			var marker := FileAccess.open(leave_test, FileAccess.WRITE)
			assert(marker != null)
			marker.close()
		while is_instance_valid(lobby._preparation):
			await _pause()
		assert(not room.is_open() and not lobby._action.disabled)
		if not surrender:
			assert(lobby._status.text == Locale.t("matchmaking.opponent_left_room"))
		assert(PlayerData.match_history.is_empty())
		print("TEST_MATCHMAKING_CLIENT_OK ", mode)
		get_tree().quit()
		return
	if surrender:
		while not opponent.cancelled:
			await _pause()
	else:
		preparation.confirm_button.pressed.emit()
		while not room.ready_seats.has(room.local_seat):
			await _pause()
		assert(not room.started and preparation.confirm_button.text == Locale.t("team.cancel_ready"))
		await _capture("ready")
		var double_click := InputEventMouseButton.new()
		double_click.button_index = MOUSE_BUTTON_LEFT
		double_click.pressed = true
		double_click.double_click = true
		for tile in preparation.deck_tiles:
			if tile.deck_id != custom_deck.id:
				tile.gui_input.emit(double_click)
		assert(preparation.selected_deck_id == custom_deck.id and not is_instance_valid(preparation.details_layer))
		preparation.confirm_button.pressed.emit()
		while room.ready_seats.has(room.local_seat):
			await _pause()
		assert(not preparation.confirm_button.disabled and preparation.confirm_button.text == Locale.t("team.ready"))
	preparation.confirm_button.pressed.emit()
	while get_tree().current_scene != null and get_tree().current_scene.scene_file_path != "res://TeamBattle.tscn":
		await _pause()
	if get_tree().current_scene == null:
		await get_tree().scene_changed
	var battle = get_tree().current_scene
	assert(battle.scene_file_path == "res://TeamBattle.tscn")
	assert(room.view.players.size() == 2 and room.matchmaking_mode == mode)
	assert(_opening_view.hand.size() == 3)
	var pool: Array = _opening_view.match_pool
	assert(pool.size() == 16 and int(_opening_view.deck_count) == 10)
	var names := {}
	for card: Dictionary in pool:
		assert(not names.has(card.name))
		names[card.name] = true
	for index in range(1, 9):
		assert(names.has("Stable %d" % index) and names.has("Variable %d" % index))
	assert(battle._result_mode_text() == Locale.t("matchmaking." + mode))
	if DisplayServer.get_name() != "headless":
		await _verify_opening_coin(battle, room)
	await _capture("opening")
	var ended := false
	while int(room.view.revision) < 1:
		if battle.is_my_turn() and not battle.end_turn_button.disabled and not ended:
			ended = true
			battle.end_turn_button.pressed.emit()
		await _pause()
	assert(not room.view.players[2 - room.local_seat].has("hand"))
	for player: Dictionary in room.view.players:
		if player.seat == room.view.active:
			assert(int(player.mana) == 7)
	if surrender:
		room.rpc_id(1, "_leave_match")
	while int(room.view.winner) == 0:
		await _pause()
	var mine: Dictionary = room.view.players.filter(func(p: Dictionary): return p.seat == room.local_seat)[0]
	var won := int(room.view.winner) == int(mine.team)
	assert(won != surrender)
	var expected_rating := 1018 if won else 984
	if mode == "ranked":
		var result: Dictionary = room.view.get("ranked_rating")
		assert(result.rating == expected_rating and result.change == expected_rating - 1000)
		assert(is_equal_approx(result.multiplier, preview))
	else:
		assert(not room.view.has("ranked_rating"))
	while not battle.battle_finished:
		await _pause()
	assert(battle._online_result_back_btn.text == Locale.t("matchmaking.back"))
	assert(PlayerData.match_history[0].mode == mode)
	assert(PlayerData.match_history[0].deck_name == custom_deck.name)
	assert(int(PlayerData.match_history[0].player_max_hp) == int(mine.max_hp))
	if mode == "ranked":
		while not PlayerData.match_history[0].has("ranked_settlement"):
			await _pause()
		var recorded: Dictionary = PlayerData.match_history[0].ranked_settlement
		assert(int(recorded.before) == 1000 and int(recorded.after) == expected_rating)
		assert(is_equal_approx(float(recorded.multiplier), preview))
		# Verify that the authenticated lobby can recover a receipt for a client
		# whose result scene closed before it received the settled snapshot.
		PlayerData.match_history[0].erase("ranked_settlement")
	assert(battle.match_info_cards().size() == 16)
	await _capture("result")
	battle._online_result_back_btn.pressed.emit()
	await get_tree().scene_changed
	lobby = get_tree().current_scene
	assert(lobby.scene_file_path == "res://MatchmakingLobby.tscn")
	if mode == "ranked":
		while lobby._action.disabled:
			await _pause()
		assert(lobby._rating.text == Locale.t("matchmaking.record", [expected_rating, 1, int(won)]))
		assert(int(PlayerData.match_history[0].ranked_settlement.after) == expected_rating)
		PlayerData._load_match_history()
		assert(PlayerData.match_history.size() == 1)
		assert(int(PlayerData.match_history[0].ranked_settlement.after) == expected_rating)
	print("TEST_MATCHMAKING_CLIENT_OK ", mode)
	get_tree().quit()


func _verify_opening_coin(battle: Node, room: Node) -> void:
	await get_tree().process_frame
	var toss := battle.get_node_or_null("PvpOpeningCoin")
	assert(toss != null and battle._opening_coin_active and not battle.is_my_turn())
	assert(room.team_reveal_pending() and battle.end_turn_button.disabled)
	var first_turn_ms: int = room.action_clock.remaining_ms
	var result := toss.find_child("OpeningPlayerResult", true, false) as Label
	while result.text.is_empty():
		await _pause()
	var text_key := "battle.coin_you_first" if int(_opening_view.active) == room.local_seat else "battle.coin_opponent_first"
	assert(result.text == Locale.t(text_key))
	assert(room.action_clock.remaining_ms == first_turn_ms and int(room.view.revision) == 0)
	await _capture("coin-result")
	while battle._opening_coin_active or room.team_reveal_pending():
		await _pause()
	assert(int(room.view.active) == int(_opening_view.active))


func _verify_rating_journal() -> void:
	var rating = preload("res://RankedRating.gd")
	var path := "user://rating-replay-fixture.jsonl"
	var legacy := FileAccess.open(path, FileAccess.WRITE)
	assert(legacy != null)
	assert(legacy.store_line('{"match_id":"previous","first":"A","second":"B","winner":1}'))
	legacy.close()
	var journal = rating.new(path)
	assert(journal.profile("A").rating == 1016 and journal.profile("B").rating == 984)
	assert(journal.settle("current", "A", "C", 1, [1.13, 0.95]))
	var reopened = rating.new(path)
	assert(reopened.profile("A").rating == 1033 and reopened.profile("C").rating == 985)
	assert(reopened.settle("current", "A", "C", 1, [1.00, 1.00]))
	assert(reopened.profile("A").played == 2 and reopened.profile("A").rating == 1033)


func _pause() -> void:
	if Time.get_ticks_msec() >= _deadline:
		push_error("Matchmaking integration timed out")
		get_tree().quit(1)
	await get_tree().create_timer(0.05).timeout


func _capture(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await get_tree().create_timer(0.32).timeout
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(name + ".png")) == OK)

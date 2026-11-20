extends Node

var role := ""
var address := "127.0.0.1"
var lobby_port := 4567
var room_proxy_port := 0
var code := ""
var leave_gate := ""
var lobby: Control
var joined := false
var finished := false
var old_peer: MultiplayerPeer
var match_count := 0
var current_battle: Node
var returned := false
var submitted := false
var confirmed := false
var checked_cancellation := false
var started_editing := false
var saw_editor_status := false
var screenshot_path := ""
var disconnect_checked := false
var checking_disconnected_entry := false
var draft_rules_opened := false
var rules_locked_verified := false
var prior_turn: Dictionary = {}
var prior_snapshot: Dictionary = {}
var prior_match_id := ""
var art_confirmation_checked := false
var art_fallback_accepted := false
var waiting_outage_armed := false
var waiting_outage_verified := false
var confirmation_outage_armed := false
var confirmation_outage_verified := false
var cancelled_offer: Dictionary = {}
var replaying_cancelled_offer := false
var cancelled_offer_verified := false
var _last_preparation_trace := ""
var _offer_mismatch_injected := false
var _offer_mismatch_recovered := false
var _start_suppressed := false
var _start_timeout_checked := false
var _start_timeout_reset := false
var _start_timeout_race := ""
var _held_start_id := ""
var _held_start_generation := 0
var _held_start_sent := false
var _late_start_checked := false
var _handoff_rejection := ""
var _checking_local_deck := false
var _checked_local_deck := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.get_slice("=", 1)
		if arg.begins_with("--address="): address = arg.get_slice("=", 1)
		if arg.begins_with("--lobby-port="): lobby_port = int(arg.get_slice("=", 1))
		if arg.begins_with("--room-proxy-port="): room_proxy_port = int(arg.get_slice("=", 1))
		if arg.begins_with("--code="): code = arg.get_slice("=", 1)
		if arg.begins_with("--leave-gate="): leave_gate = arg.trim_prefix("--leave-gate=")
		if arg.begins_with("--screenshot="): screenshot_path = arg.trim_prefix("--screenshot=")
		if arg.begins_with("--language="): Locale.set_language(arg.trim_prefix("--language="))
		if arg.begins_with("--start-timeout-race="): _start_timeout_race = arg.get_slice("=", 1)
		if arg.begins_with("--reject-room-handoff="): _handoff_rejection = arg.get_slice("=", 1)
	if not screenshot_path.is_empty():
		AppPreferences.set_value("window_mode", 1)
		get_window().size = Vector2i(1280, 720)
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	PlayerData.prepare_online_selection("res://DedicatedLobby.tscn")
	if OS.get_cmdline_user_args().has("--invalid-local-deck"):
		var invalid := CardData.new("QA Legacy Card", 1, 2, 1)
		invalid.gender = "invalid-fixture"
		PlayerData.deck_library.append({"id": "qa-legacy", "name": "QA Legacy Deck", "cards": [invalid]})
	if OS.get_cmdline_user_args().has("--room-deck-keyboard"):
		var cards := PlayerData.get_cards_for_deck(PlayerData.current_deck_id)
		if not cards.is_empty():
			var long_deck: Array = []
			for index in range(40):
				long_deck.append(cards[index % cards.size()].duplicate_card())
			PlayerData.deck_library.append({"id": "keyboard-long", "name": "QA Vanguard", "cards": long_deck})
			PlayerData.deck_library.append({"id": "keyboard-other", "name": "QA Reserve", "cards": long_deck.duplicate()})
	get_tree().create_timer(150 if _tests_long_outage() or OS.get_cmdline_user_args().has("--terminal-cancel-outage") else 90).timeout.connect(func(): _fail("scenario timed out"))
	if (room_proxy_port == 0 or (role == "survivor" and not _handoff_rejection.is_empty())) and role in ["owner", "survivor", "replacement", "rejoin", "unreachable", "cancelling_guest", "full", "in_progress", "reserved"]:
		_open_room_entry.call_deferred()
		return
	NetworkManager.lobby_connected.connect(_request)
	NetworkManager.lobby_connection_failed.connect(func(): _fail("lobby connection failed"))
	NetworkManager.game_connection_failed.connect(func(): _fail("room authentication failed"))
	NetworkManager.room_authenticated.connect(_authenticated)
	# Optional port is used for local server isolation; public smoke uses 4567.
	var result: int
	if lobby_port == 4567:
		result = NetworkManager.connect_to_lobby(address, _response)
	else:
		result = NetworkManager.connect_to_lobby(address, _response, lobby_port)
	if result != OK: _fail("could not create lobby transport")

func _open_room_entry() -> void:
	_make_lobby()
	lobby.lobby_port = lobby_port
	lobby.server_input.text = address
	NetworkManager.room_authenticated.connect(_authenticated)
	lobby.room_input.text = code
	if role == "cancelling_guest":
		await _cancel_assigned_room()
		return
	if role == "survivor" and not _handoff_rejection.is_empty():
		await _check_rejected_room_handoff()
		return
	if role in ["full", "in_progress", "reserved"]:
		await _check_unavailable_room()
		return
	if role == "unreachable":
		lobby.server_input.text = "invalid server address"
		lobby.check_server_btn.pressed.emit()
		if (lobby.status_label.text != Locale.t("lobby.invalid_server_address")
			or not lobby.server_input.is_visible_in_tree() or not lobby.server_input.has_focus()
			or lobby.server_input.get_selected_text() != "invalid server address" or NetworkManager.is_online):
			_fail("invalid server address did not open settings and focus the address"); return
		lobby.server_input.text = address
		lobby.join_btn.grab_focus()
		lobby.join_btn.pressed.emit()
		while lobby.join_btn.disabled:
			await get_tree().process_frame
		if not _room_entry_recovered(Locale.t("lobby.could_not_reach"), code):
			_fail("connection timeout did not restore the focused join form"); return
		_finish("DEDICATED_ENTRY_TIMEOUT_OK")
		return
	if role == "owner":
		lobby.get_node("Panel/VBoxContainer/ServerSettingsButton").button_pressed = true
		lobby.check_server_btn.grab_focus()
		lobby.check_server_btn.pressed.emit()
		if not lobby.back_btn.has_focus() or not lobby.check_server_btn.disabled:
			_fail("checking the server must move keyboard focus to cancellation"); return
		lobby.back_btn.pressed.emit()
		if (lobby.status_label.text != Locale.t("lobby.connection_cancelled") or not lobby.server_input.has_focus()
				or lobby.server_input.text != address or lobby.room_input.text != code or NetworkManager.is_online):
			_fail("cancelling a server check must preserve the form and restore address focus"); return
		lobby.server_input.grab_focus()
		_press_enter()
		while lobby.check_server_btn.disabled:
			await get_tree().process_frame
		if (not lobby.status_label.text.begins_with(Locale.t("lobby.server_status", [0, 0, 0]).get_slice("|", 0))
				or not lobby.check_server_btn.has_focus() or not lobby.server_input.editable or NetworkManager.is_online):
			_fail("Enter in the address field must check the server and restore keyboard focus for retry"); return
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			var evidence := screenshot_path.get_base_dir().path_join("server-status-keyboard.png")
			if get_viewport().get_texture().get_image().save_png(evidence) != OK:
				_fail("could not capture the server check result"); return
		print("DEDICATED_STATUS_FOCUS_OK")
		await _check_lobby_protocol_feedback()
		if finished:
			return
		lobby.room_input.text = code + "?"
		lobby.join_btn.grab_focus()
		lobby.join_btn.pressed.emit()
		if not _room_entry_recovered(Locale.t("lobby.invalid_code"), code + "?") or lobby.room_input.get_selected_text() != code + "?":
			_fail("invalid room code did not return focus and select the code for correction"); return
		lobby.room_input.text = code + "X"
		lobby.join_btn.pressed.emit()
		if lobby.back_btn.text != Locale.t("lobby.cancel_connection") or not lobby.back_btn.has_focus():
			_fail("connecting form does not offer focused cancellation"); return
		lobby.back_btn.pressed.emit()
		if lobby.join_btn.disabled or lobby.room_input.text != code + "X" or NetworkManager.is_online:
			_fail("connection cancellation did not restore the room form"); return
		print("DEDICATED_ENTRY_CANCEL_OK")
		lobby.join_btn.grab_focus()
		lobby.join_btn.pressed.emit()
		while lobby.join_btn.disabled:
			await get_tree().process_frame
		if not _room_entry_recovered(Locale.t("lobby.room_not_found", [code + "X"]), code + "X") or lobby.room_input.get_selected_text() != code + "X":
			_fail("room-not-found did not restore focus and select the code for correction"); return
		print("DEDICATED_ENTRY_RETRY_OK")
		lobby.room_input.text = code
		lobby.create_btn.pressed.emit()
	else:
		lobby.join_btn.pressed.emit()
		while lobby.join_btn.disabled:
			await get_tree().process_frame
		if not is_instance_valid(lobby.waiting_ui):
			_fail("room entry failed: " + lobby.status_label.text)


func _press_enter() -> void:
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter, true)


func _check_lobby_protocol_feedback() -> void:
	lobby.get_node("Panel/VBoxContainer/ServerSettingsButton").button_pressed = false
	var missing_code := code + "X"
	lobby.room_input.text = missing_code
	lobby.join_btn.pressed.emit()
	var callback := NetworkManager._lobby_callback
	var remote_protocol := AppVersion.PROTOCOL_VERSION - 1
	NetworkManager._lobby_callback = func(response: Dictionary):
		if response.get("status") == "not_found":
			response = {"status": "protocol_mismatch", "remote_protocol": remote_protocol}
		callback.call(response)
	while lobby.join_btn.disabled:
		await get_tree().process_frame
	var message := Locale.t("lobby.protocol_mismatch", [AppVersion.PROTOCOL_VERSION, remote_protocol])
	if (not _room_entry_recovered(message, missing_code, true)
			or not lobby.server_input.is_visible_in_tree() or lobby.server_input.get_selected_text() != address):
		_fail("lobby protocol mismatch did not reopen settings with the full address selected"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("lobby-protocol-mismatch.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the lobby protocol mismatch"); return
	print("DEDICATED_LOBBY_PROTOCOL_FOCUS_OK")


func _room_entry_recovered(message: String, expected_code: String, address_focus: bool = false) -> bool:
	var focus_ok: bool = lobby.server_input.has_focus() if address_focus else lobby.room_input.has_focus()
	return (lobby.lobby_panel.is_visible_in_tree() and not is_instance_valid(lobby.waiting_ui)
		and lobby.status_label.text == message and lobby.room_input.text == expected_code
		and lobby.server_input.text == address and lobby.room_input.editable and focus_ok
		and not lobby.join_btn.disabled and not lobby.create_btn.disabled and not NetworkManager.is_online)


func _check_rejected_room_handoff() -> void:
	var assigned_at := [0]
	lobby.join_btn.pressed.emit()
	var callback := NetworkManager._lobby_callback
	NetworkManager._lobby_callback = func(response: Dictionary):
		if response.get("status") == "ok":
			assigned_at[0] = Time.get_ticks_msec()
			if room_proxy_port > 0:
				response["port"] = room_proxy_port
			if _handoff_rejection == "invalid_token":
				response["reconnect_token"] = "expired-test-assignment"
			elif _handoff_rejection == "slot_in_use":
				var fixture_path := leave_gate + ".local-occupied-slot"
				response["player"] = 1
				response["reconnect_token"] = FileAccess.get_file_as_string(fixture_path)
				DirAccess.remove_absolute(fixture_path)
		callback.call(response)
		if response.get("status") == "ok" and _handoff_rejection == "protocol_mismatch":
			var room_peer := NetworkManager.peer
			room_peer.peer_connected.disconnect(NetworkManager._on_peer_connected.bind(room_peer))
			room_peer.peer_connected.connect(func(id: int):
				if id == 1:
					NetworkManager.rpc_id(1, "rpc_room_auth", code, NetworkManager.player_number,
						NetworkManager.reconnect_token, AppVersion.PROTOCOL_VERSION + 1))
	while lobby.join_btn.disabled:
		await get_tree().process_frame
	var message_key := "lobby.room_assignment_expired"
	match _handoff_rejection:
		"slot_in_use": message_key = "lobby.room_slot_in_use"
		"protocol_mismatch": message_key = "lobby.room_protocol_mismatch"
	if not _room_entry_recovered(Locale.t(message_key), code, _handoff_rejection == "protocol_mismatch"):
		_fail("the rejected room assignment did not restore the expected form: " + lobby.status_label.text); return
	var recovery_ms := Time.get_ticks_msec() - int(assigned_at[0])
	if assigned_at[0] == 0 or recovery_ms >= int(NetworkManager.CONNECT_TIMEOUT * 1000):
		_fail("the room returned to the entry form only after the connection deadline"); return
	print("DEDICATED_HANDOFF_REJECTION_TIME_MS ", recovery_ms)
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var screenshot_name := "room-assignment-expired.png" if _handoff_rejection == "invalid_token" else "room-admission-%s.png" % _handoff_rejection
		var evidence := screenshot_path.get_base_dir().path_join(screenshot_name)
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the expired room assignment"); return
	print("DEDICATED_HANDOFF_REJECTION_RECOVERED")
	lobby.room_input.grab_focus()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter, true)
	if not lobby.join_btn.disabled:
		_fail("Enter did not retry the original room"); return
	if room_proxy_port > 0:
		var retry_callback := NetworkManager._lobby_callback
		NetworkManager._lobby_callback = func(response: Dictionary):
			if response.get("status") == "ok":
				response["port"] = room_proxy_port
			retry_callback.call(response)

func _check_unavailable_room() -> void:
	if role == "full":
		lobby.create_btn.grab_focus()
		lobby.create_btn.pressed.emit()
		while lobby.create_btn.disabled:
			await get_tree().process_frame
		if not _room_entry_recovered(Locale.t("lobby.room_taken", [code]), code) or lobby.room_input.get_selected_text() != code:
			_fail("a taken creation code did not restore the form for correction"); return
		# Continue from the same field with Enter, using the room that already exists.
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		get_viewport().push_input(enter, true)
		if not lobby.join_btn.disabled:
			_fail("Enter in the recovered field did not submit a join request"); return
	else:
		lobby.join_btn.grab_focus()
		lobby.join_btn.pressed.emit()
	while lobby.join_btn.disabled:
		await get_tree().process_frame
	var message := Locale.t("lobby.in_progress")
	if role == "full":
		message = Locale.t("lobby.room_full", [code])
	elif role == "reserved":
		message = Locale.t("lobby.room_seat_reserved", [code])
	if not _room_entry_recovered(message, code) or lobby.room_input.has_selection():
		_fail("room rejection did not restore the room code for a direct retry"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the failed room entry"); return
	_finish("DEDICATED_" + role.to_upper() + "_OK")


func _cancel_assigned_room() -> void:
	lobby.join_btn.pressed.emit()
	while lobby.join_btn.disabled and not lobby._connecting_to_room:
		await get_tree().process_frame
	if not lobby._connecting_to_room or is_instance_valid(lobby.waiting_ui):
		_fail("join did not reach room handoff before cancellation"); return
	var stall_authentication := OS.get_cmdline_user_args().has("--stall-entry-authentication")
	var started := Time.get_ticks_msec()
	if stall_authentication:
		get_tree().multiplayer_poll = false
	lobby.back_btn.pressed.emit()
	if not lobby.join_btn.disabled or lobby.status_label.text != Locale.t("lobby.cancelling_connection"):
		_fail("a pending room reservation did not show the cancellation in progress"); return
	while lobby.join_btn.disabled:
		await get_tree().process_frame
	get_tree().multiplayer_poll = true
	if stall_authentication and Time.get_ticks_msec() - started < 2800:
		_fail("blocked authentication did not exercise the cancellation timeout"); return
	if is_instance_valid(lobby.waiting_ui) or NetworkManager.is_online or lobby.room_input.text != code:
		_fail("cancellation did not restore the room entry with its code"); return
	if lobby.status_label.text != Locale.t("lobby.connection_cancelled"):
		_fail("room entry did not confirm that the connection was cancelled"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		if not lobby.room_input.has_focus():
			_fail("cancelling the connection did not return keyboard focus to the room code"); return
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the cancelled room entry"); return
	if stall_authentication and not await _retry_after_reservation():
		return
	_finish("DEDICATED_ASSIGNED_JOIN_CANCELLED")

func _retry_after_reservation() -> bool:
	print("DEDICATED_RESERVATION_ACTIVE")
	var gate := leave_gate + ".reservation-checked"
	while not FileAccess.file_exists(gate):
		await get_tree().process_frame
	PlayerData.battle_config["starting_hp"] = 73
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter, true)
	while lobby.join_btn.disabled:
		await get_tree().process_frame
	if not is_instance_valid(lobby.waiting_ui):
		_fail("the original guest could not retry the reserved room: " + lobby.status_label.text)
		return false
	var deadline := Time.get_ticks_msec() + 5000
	while lobby.start_btn.disabled and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if lobby.start_btn.disabled or int(PlayerData.battle_config.get("starting_hp", 0)) != 30:
		_fail("the returning guest did not receive the host rules before Ready unlocked")
		return false
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-entry-retried.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the room after retry")
			return false
	await lobby._exit_waiting_room()
	if not _room_entry_recovered(Locale.t("lobby.room_left"), code):
		_fail("leaving after retry did not restore the room form")
		return false
	print("DEDICATED_RESERVATION_RETRY_OK")
	return true

func _request() -> void:
	if role == "probe": NetworkManager.request_lobby_status(_response)
	elif role == "owner": NetworkManager.create_room(code)
	else: NetworkManager.join_room(code)

func _response(data: Dictionary) -> void:
	if role == "probe":
		print("PUBLIC_SERVER_STATUS: ", JSON.stringify(data))
		if data.get("status") != "server_status": _fail("server not compatible"); return
		_finish("SERVER_STATUS_OK")
		return
	if role in ["full", "in_progress"]:
		if data.get("status") != role:
			_fail("join returned %s instead of %s" % [str(data.get("status")), role]); return
		_finish("DEDICATED_" + role.to_upper() + "_OK")
		return
	if data.get("status") != "ok": _fail("lobby rejected request: " + str(data.get("status"))); return
	var player := int(data.get("player", 0))
	if (role == "owner" and player != 1) or (role != "owner" and player != 2):
		_fail("incorrect assigned seat"); return
	NetworkManager.server_allows_card_art = bool(data.get("card_art", false))
	# Give a freshly spawned child time to bind; production lobby has this same delay.
	await get_tree().create_timer(0.5).timeout
	var game_port := room_proxy_port if room_proxy_port > 0 else int(data.port)
	if NetworkManager.connect_to_game_room(address, game_port, player, code, str(data.reconnect_token)) != OK:
		_fail("could not create room transport")

func _authenticated(_player: int, reconnecting: bool) -> void:
	if has_meta("terminal_cancel_retrying"):
		await get_tree().process_frame
		if not is_instance_valid(lobby.waiting_ui) or NetworkManager.peer == old_peer or NetworkManager.room_code != code or reconnecting:
			_fail("rejoining after the cancellation timed out did not reopen the room with a fresh connection"); return
		old_peer = NetworkManager.peer
		remove_meta("terminal_cancel_retrying")
		submitted = false
		confirmed = false
		confirmation_outage_verified = true
		print("DEDICATED_OUTAGE_CANCEL_REJOINED")
		return
	if role == "cancelling_guest":
		if is_instance_valid(lobby.waiting_ui):
			if not OS.get_cmdline_user_args().has("--stall-entry-authentication"):
				_fail("cancelling a handoff opened the waiting room")
				return
			var panel: Control = lobby.waiting_ui
			if not panel.start_button.disabled or not panel._rules_button.disabled or panel.status.text != Locale.t("wait.syncing_room_status"):
				_fail("fresh guest should see room synchronization with rules and Ready locked, got: " + panel.status.text)
				return
			print("DEDICATED_INITIAL_ROOM_SYNC_OK")
		return
	if reconnecting: _fail("fresh room join was marked as match reconnect"); return
	if not is_instance_valid(lobby):
		_make_lobby()
		lobby._show_waiting_room()
	if not is_instance_valid(lobby.waiting_ui):
		_fail("successful authentication did not enter the waiting room"); return
	var selected_cards := PlayerData.get_cards_for_deck(PlayerData.current_deck_id)
	if selected_cards.is_empty() or PlayerData.battle_deck != selected_cards:
		_fail("entering the room did not select the current library deck"); return
	if role == "owner" and OS.get_cmdline_user_args().has("--ready-before-rules"):
		lobby.waiting_ui.set_process(false)
	if OS.get_cmdline_user_args().has("--room-deck-keyboard"):
		if not await _check_room_deck_keyboard(lobby.waiting_ui):
			return
	if OS.get_cmdline_user_args().has("--room-invite"):
		if not await _check_room_invite(lobby.waiting_ui):
			return
	var room := lobby.waiting_ui as Control
	var is_host := NetworkManager.is_authority()
	if room.local_host_badge.is_visible_in_tree() != is_host or room.remote_host_badge.is_visible_in_tree() == is_host:
		_fail("the room must mark only the host seat"); return
	if not is_host and role == "replacement" and not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-guest-host-badge.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the opponent's host badge"); return
	joined = true
	old_peer = NetworkManager.peer
	if role == "owner" and _handoff_rejection == "slot_in_use":
		var fixture := FileAccess.open(leave_gate + ".local-occupied-slot", FileAccess.WRITE)
		if fixture == null:
			_fail("could not prepare the local duplicate-seat fixture"); return
		fixture.store_string(NetworkManager.reconnect_token)
		fixture.close()
	print("DEDICATED_JOINED_", role.to_upper())


func _check_room_invite(panel: Control) -> bool:
	var share := panel.find_child("CopyRoomCodeButton", true, false) as Button
	var original_peer := NetworkManager.peer
	var native := DisplayServer.get_name() != "headless"
	var before := DisplayServer.clipboard_get() if native else ""
	var original_text := share.text
	share.grab_focus()
	share.pressed.emit()
	if native:
		var copied := DisplayServer.clipboard_get()
		if copied == code:
			DisplayServer.clipboard_set(before)
		if copied != code or not share.text.contains(code) or not share.text.contains(Locale.t("lobby.code_copied")):
			_fail("copying must put the exact room code on the clipboard and leave it visible"); return false
		await get_tree().create_timer(1.25).timeout
		if share.text != original_text:
			_fail("copy confirmation did not restore the original share button"); return false
		# Render the same fallback in a native window. Headless mode drives the failed copy itself.
		panel._show_manual_invite(code)
	await get_tree().process_frame
	await get_tree().process_frame
	var dialog := panel.get_node_or_null("ManualRoomInvite") as ConfirmationDialog
	if not is_instance_valid(dialog) or not dialog.visible or not share.text.contains(code):
		_fail("unavailable clipboard did not offer a manual room invite"); return false
	var input := dialog.find_child("InviteValue", true, false) as LineEdit
	if input == null or input.editable or input.text != code or input.get_selected_text() != code:
		_fail("manual sharing must expose the entire room code as selected, read-only text"); return false
	if native:
		if dialog.size.y > get_viewport().get_visible_rect().size.y:
			_fail("the manual sharing controls did not fit the window"); return false
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			var evidence := screenshot_path.get_base_dir().path_join("room-invite-manual.png")
			if get_viewport().get_texture().get_image().save_png(evidence) != OK:
				_fail("could not capture the manual invite"); return false
		dialog.confirmed.emit()
		var retried := DisplayServer.clipboard_get()
		if retried == code:
			DisplayServer.clipboard_set(before)
		if retried != code:
			_fail("retry did not copy the room code"); return false
	else:
		dialog.confirmed.emit()
		await get_tree().process_frame
		if not is_instance_valid(dialog) or not dialog.visible or input.get_selected_text() != code:
			_fail("another clipboard failure closed the manual invite"); return false
		dialog.canceled.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(dialog) or NetworkManager.peer != original_peer or not share.has_focus():
		_fail("closing the invite changed the room or lost the share button focus"); return false
	print("DEDICATED_ROOM_INVITE_OK")
	return true


func _check_room_deck_keyboard(panel: Control) -> bool:
	var choice: OptionButton = panel.deck_choice
	var original := choice.selected
	if choice.item_count < 3:
		_fail("missing deck navigation fixtures"); return false
	choice.item_selected.emit(choice.item_count - 2)
	await get_tree().create_timer(0.15).timeout
	var cards: Array[Node] = panel.grid.find_children("InspectRoomCard", "Button", true, false)
	if cards.size() < 2:
		_fail("the selected deck did not render its cards"); return false
	var next_card := cards[-1] as Button
	var previous_card := cards[-2] as Button
	previous_card.grab_focus()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	get_viewport().push_input(tab, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = panel.deck_scroll
	if (not next_card.has_focus() or scroll.scroll_vertical == 0
			or not scroll.get_global_rect().encloses(next_card.get_global_rect())):
		var bar := scroll.get_v_scroll_bar()
		_fail("Tab did not reveal the focused card: focused=%s scroll=%d range=%s page=%s viewport=%s card=%s" % [
			next_card.has_focus(), scroll.scroll_vertical, bar.max_value, bar.page,
			scroll.get_global_rect(), next_card.get_global_rect()]); return false
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-deck-keyboard.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture room card keyboard focus"); return false
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter, true)
	enter.pressed = false
	get_viewport().push_input(enter, true)
	await get_tree().process_frame
	if panel.find_child("TabletopCardInspector", true, false) == null:
		_fail("Enter did not open the focused card"); return false
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().process_frame
	await get_tree().process_frame
	if panel.find_child("TabletopCardInspector", true, false) != null or not next_card.has_focus():
		_fail("Escape did not close the card and return focus to it"); return false
	choice.grab_focus()
	choice.item_selected.emit(choice.item_count - 1)
	await get_tree().process_frame
	if scroll.scroll_vertical != 0 or choice.get_selected_metadata() != "keyboard-other":
		_fail("the newly selected deck inherited the old scroll position"); return false
	choice.item_selected.emit(original)
	print("DEDICATED_ROOM_DECK_KEYBOARD_OK")
	return true

func _make_lobby() -> void:
	if role == "replacement" and OS.get_cmdline_user_args().has("--offer-deck-mismatch"):
		NetworkManager.match_offer_received.connect(_inject_offer_deck_mismatch)
	lobby = preload("res://DedicatedLobby.tscn").instantiate()
	get_tree().root.add_child(lobby)
	get_tree().current_scene = lobby
	if role == "survivor" and OS.get_cmdline_user_args().has("--ready-before-rules"):
		EventBus.rpc_ready_received.connect(_verify_ready_before_rules, CONNECT_ONE_SHOT)

func _process(_delta: float) -> void:
	if not joined or finished or checking_disconnected_entry: return
	var scene := get_tree().current_scene
	if scene == null: return
	if scene.scene_file_path == "res://CardEditor.tscn":
		if FileAccess.file_exists(leave_gate + ".edited") and not has_meta("editor_closed"):
			if PlayerData.editing_deck_id != PlayerData.online_room_deck_id or PlayerData.online_room_deck_id.is_empty():
				_fail("card creation did not offer to save to the room's selected deck"); return
			set_meta("editor_closed", true)
			if OS.get_cmdline_user_args().has("--editor-outage"):
				await _verify_editor_outage(scene)
				return
			scene.get_node("BackButton").pressed.emit()
		return
	if scene.scene_file_path == "res://Main.tscn":
		if scene != current_battle:
			current_battle = scene
			match_count += 1
			if match_count == 1:
				_play_first_match(scene)
			else:
				_check_rematch(scene)
		return
	if scene.scene_file_path != "res://DedicatedLobby.tscn": return
	if checked_cancellation and is_instance_valid(scene.waiting_ui):
		_trace_match_preparation(scene)
	if role == "rejoin":
		if _tests_join_during_results():
			finished = true
			await _verify_join_during_result()
			return
		if lobby._can_submit_ready():
			if NetworkManager.room_code != code or NetworkManager.player_number != 2 or lobby.i_am_ready:
				_fail("the new player did not receive a fresh guest seat"); return
			print("DEDICATED_LONG_OUTAGE_NEW_PLAYER_READY_OK")
			# Stay connected until the surviving player's UI also observed the join.
			finished = true
			var gate := FileAccess.open(leave_gate + ".terminal-rejoin-ready", FileAccess.WRITE)
			gate.store_string("new player ready")
			gate.close()
			while not FileAccess.file_exists(leave_gate + ".terminal-room-ready"):
				await get_tree().process_frame
			_finish("DEDICATED_LONG_OUTAGE_JOIN_COMPLETE")
		return
	if scene != lobby:
		lobby = scene
		if NetworkManager.peer != old_peer or NetworkManager.room_code != code or NetworkManager.room_match_started:
			_fail("return to room lost connection or retained old match"); return
		# The new lobby is already listening before we observe it here. An opponent
		# can legitimately submit its next deck before this process callback.
		if lobby.i_am_ready or lobby.match_agreement.pending:
			_fail("rematch inherited previous match readiness"); return
		submitted = false
		confirmed = false
		if match_count > 0:
			returned = true
			print("DEDICATED_BACK_IN_ROOM_", role.to_upper())
			if match_count == 2 and role == "replacement":
				if not disconnect_checked or not NetworkManager.is_authority() or (not _tests_join_during_results() and lobby._can_submit_ready()):
					_fail("surviving player did not retain the room after the live match ended"); return
				if _tests_join_during_results():
					finished = true
					await _verify_result_host_saw_guest()
				elif _tests_long_outage():
					if NetworkManager.room_wait_reason != "opponent_connection_lost":
						_fail("the retained room lost the reason the opponent departed"); return
					print("DEDICATED_LONG_OUTAGE_ROOM_RETAINED_OK")
				else:
					var panel := lobby.waiting_ui as Control
					if panel.status.text != Locale.t("wait.you_became_room_host") or panel._share_button.disabled:
						_fail("returning after host forfeited lost the host-transfer notice or room invitation"); return
					if not screenshot_path.is_empty():
						set_process(false)
						await RenderingServer.frame_post_draw
						var evidence := screenshot_path.get_base_dir().path_join("room-host-transfer-after-match.png")
						if get_viewport().get_texture().get_image().save_png(evidence) != OK:
							_fail("could not capture host transfer after returning from a match"); return
					_finish("DEDICATED_LIVE_HOST_LEFT_OK")
				return
			if role == "survivor" and match_count == 1 and not screenshot_path.is_empty() and not (_tests_long_outage() or _tests_card_art_stall()):
				_capture_after_return()
	if _tests_long_outage() and role == "replacement" and match_count == 2:
		if lobby._can_submit_ready() and FileAccess.file_exists(leave_gate + ".terminal-rejoin-ready"):
			var gate := FileAccess.open(leave_gate + ".terminal-room-ready", FileAccess.WRITE)
			gate.store_string("retained room ready")
			gate.close()
			_finish("DEDICATED_LONG_OUTAGE_ROOM_READY_OK")
		return
	if role == "survivor" and match_count == 0 and not NetworkManager.is_authority() and OS.get_cmdline_user_args().has("--room-card-overlays"):
		return
	if NetworkManager.room_wait_reason == "cancelled" and not checked_cancellation:
		if lobby.i_am_ready or lobby.match_agreement.pending:
			_fail("match confirmation cancellation retained preparation"); return
		checked_cancellation = true
		submitted = false
		confirmed = false
		print("DEDICATED_CANCELLED_", role.to_upper(), "_OK")
	var outage_cancel_gate := leave_gate + ".cancel-during-outage"
	if (role == "survivor" and OS.get_cmdline_user_args().has("--cancel-during-confirmation-outage")
			and not has_meta("outage_cancel_received") and NetworkManager.room_wait_reason == "cancelled"
			and FileAccess.file_exists(outage_cancel_gate)
			and NetworkManager.room_preparation_generation > int(FileAccess.get_file_as_string(outage_cancel_gate))):
		if lobby.i_am_ready or lobby.opponent_ready or lobby.match_agreement.pending:
			_fail("the other player did not return to unready after the interrupted cancellation"); return
		set_meta("outage_cancel_received", true)
		submitted = false
		confirmed = false
		print("DEDICATED_OUTAGE_CANCEL_RECEIVED")
	if (role == "survivor" and OS.get_cmdline_user_args().has("--terminal-cancel-outage")
			and not has_meta("terminal_cancel_room_retained") and NetworkManager.room_wait_reason == "opponent_connection_lost"
			and lobby.waiting_ui.status.text == Locale.t("wait.opponent_connection_lost")):
		if not NetworkManager.has_live_server_room() or NetworkManager.peer != old_peer or lobby.i_am_ready or lobby.match_agreement.pending:
			_fail("the host did not keep the same room after the guest's permanent disconnect"); return
		set_meta("terminal_cancel_room_retained", true)
		submitted = false
		confirmed = false
		print("DEDICATED_OUTAGE_CANCEL_ROOM_RETAINED")
	if NetworkManager.room_wait_reason == "offer_mismatch" and not _offer_mismatch_recovered:
		_offer_mismatch_recovered = true
		submitted = false
		confirmed = false
		await _check_offer_mismatch_recovery()
		return
	if _offer_mismatch_recovered and not has_meta("mismatch_checked"):
		return
	if checked_cancellation and match_count == 0 and OS.get_cmdline_user_args().has("--no-match-start"):
		if role == "survivor" and not _start_suppressed and lobby._battle_starting:
			_start_suppressed = true
			_held_start_id = lobby.match_agreement.offer.get("id", "")
			_held_start_generation = NetworkManager.room_preparation_generation
			lobby._battle_starting = false
			print("DEDICATED_START_SUPPRESSED")
		if role == "survivor" and _start_timeout_race == "start-first" and _start_suppressed and not _held_start_sent and FileAccess.file_exists(leave_gate + ".release-timeout-start"):
			_held_start_sent = true
			lobby._start_battle()
		if role == "replacement" and not _start_timeout_checked and lobby.match_agreement.completed:
			_start_timeout_checked = true
			await _check_start_timeout_action()
			return
		if not _start_timeout_reset and NetworkManager.room_wait_reason == "start_timeout":
			_start_timeout_reset = true
			submitted = false
			confirmed = false
			await get_tree().process_frame
			if lobby.start_btn.disabled or lobby.match_agreement.completed or NetworkManager.peer != old_peer:
				_fail("returning to preparation did not unlock Ready in the same room"); return
			set_meta("start_timeout_reset_checked", true)
			print("DEDICATED_START_TIMEOUT_RESET_", role.to_upper())
		if _start_timeout_reset and not has_meta("start_timeout_reset_checked"):
			return
	if (role == "replacement" and has_meta("leave_decision_verified") and not has_meta("leave_decision_resolved")):
		return
	if role == "owner" and lobby._can_submit_ready():
		finished = true
		if OS.get_cmdline_user_args().has("--ready-before-rules"):
			lobby.start_btn.pressed.emit()
			if not lobby.i_am_ready:
				_fail("could not ready the host before the preview"); return
			while not FileAccess.file_exists(leave_gate + ".early-ready-received"):
				await get_tree().process_frame
			lobby.waiting_ui.set_process(true)
			if OS.get_cmdline_user_args().has("--room-card-overlays"):
				while not FileAccess.file_exists(leave_gate + ".opponent-deck-open"):
					await get_tree().process_frame
				lobby.start_btn.pressed.emit()
		if OS.get_cmdline_user_args().has("--live-rule-view"):
			while not FileAccess.file_exists(leave_gate + ".rules-view-open"):
				await get_tree().process_frame
			lobby.waiting_ui._rules_button.pressed.emit()
			var editor = lobby.waiting_ui.get_node_or_null("AdvancedSettings")
			if editor == null:
				_fail("owner could not edit rules while the guest viewed them"); return
			editor.find_child("starting_hp", true, false).value = 38
			var recovery := editor.find_child("ManaRecoveryMode", true, false) as OptionButton
			recovery.select(1)
			recovery.item_selected.emit(1)
			editor.find_child("mana_increment", true, false).value = 2
			for button in editor.find_children("*", "Button", true, false):
				if button.text == Locale.t("common.confirm"):
					button.pressed.emit()
					break
		while not FileAccess.file_exists(leave_gate):
			await get_tree().process_frame
		if not await _request_owner_exit(): return
		while is_instance_valid(lobby) and is_instance_valid(lobby.waiting_ui):
			await get_tree().process_frame
		var entry := get_tree().current_scene
		if (entry.scene_file_path != "res://DedicatedLobby.tscn" or not entry.lobby_panel.is_visible_in_tree()
			or entry.room_input.text != code or entry.server_input.text != address or entry.join_btn.disabled
			or not entry.room_input.editable or not entry.room_input.has_focus()):
			_fail("leaving a live room lost the editable room code or server address"); return
		if NetworkManager.is_online or not NetworkManager.room_code.is_empty():
			_fail("returning to the form after leaving kept the live room session"); return
		if entry.status_label.text != Locale.t("lobby.room_left"):
			_fail("the form did not confirm the successful departure"); return
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
				_fail("could not capture the returned room entry"); return
		print("DEDICATED_OWNER_LEFT_OK")
		get_tree().quit(0)
	elif (role == "survivor" and not NetworkManager.is_authority() and lobby._can_submit_ready()
			and OS.get_cmdline_user_args().has("--live-rule-view") and not has_meta("live_rules_view_started")):
		set_meta("live_rules_view_started", true)
		_verify_live_rules_view()
	elif role == "survivor" and NetworkManager.player_number == 1:
		if not NetworkManager.is_online or NetworkManager.peer != old_peer or not NetworkManager.is_authority():
			_fail("promotion lost room transport or authority"); return
		if not has_meta("promoted"):
			set_meta("promoted", true)
			var room := lobby.waiting_ui as Control
			if (room.status.text != Locale.t("wait.you_became_room_host") or room.room_code != code
					or room._share_button.disabled or not lobby.start_btn.disabled
					or room.local_title.text != ("你" if Locale.language == "zh" else "You")
					or not room.local_host_badge.is_visible_in_tree() or room.remote_host_badge.is_visible_in_tree()):
				_fail("the room did not confirm the host transfer or offer to reuse the current code"); return
			if not screenshot_path.is_empty():
				set_process(false)
				await RenderingServer.frame_post_draw
				var evidence := screenshot_path.get_base_dir().path_join("room-host-transfer.png")
				if get_viewport().get_texture().get_image().save_png(evidence) != OK:
					_fail("could not capture the room host transfer"); return
				set_process(true)
			print("DEDICATED_PROMOTED_OK")
		if not started_editing:
			started_editing = true
			lobby.waiting_ui._show_rules()
			var rules = lobby.waiting_ui.get_node_or_null("AdvancedSettings")
			if rules == null: _fail("host could not edit rules while waiting for a player"); return
			rules.find_child("starting_hp", true, false).value = 37
			rules.find_child("ManaRecoveryMode", true, false).select(0)
			if OS.get_cmdline_user_args().has("--discard-rejection"):
				rules.find_child("draw_per_turn", true, false).value = 7
			for button in rules.find_children("*", "Button", true, false):
				if button.text == Locale.t("common.confirm"):
					button.pressed.emit()
					break
			if int(PlayerData.battle_config.get("starting_hp", 0)) != 37:
				_fail("host rule edits were not committed"); return
			lobby.create_card_btn.pressed.emit()
			return
		if lobby._can_submit_ready() and not draft_rules_opened:
			draft_rules_opened = true
			lobby.waiting_ui._show_rules()
			var draft = lobby.waiting_ui.get_node_or_null("AdvancedSettings")
			if draft == null: _fail("host could not open rule draft after editing card"); return
			draft.find_child("starting_hp", true, false).value = 73
			var draft_gate := FileAccess.open(leave_gate + ".rules-draft", FileAccess.WRITE)
			draft_gate.store_string("rule draft open")
			draft_gate.close()
		if lobby._can_submit_ready() and lobby.opponent_ready:
			if not rules_locked_verified:
				if lobby.waiting_ui.get_node_or_null("AdvancedSettings") != null or NetworkManager.room_link_waiting(): return
				if int(PlayerData.battle_config.get("starting_hp", 0)) != 37 or lobby.waiting_ui.status.text != Locale.t("wait.rules_became_locked"):
					_fail("opponent readiness did not lock rules and discard the unsaved draft"); return
				rules_locked_verified = true
				print("DEDICATED_RULE_DRAFT_LOCKED_OK")
			if not submitted and lobby.i_am_ready: _fail("old preparation survived replacement"); return
			_prepare_match()
		elif checked_cancellation and _tests_cancelled_offer() and not cancelled_offer_verified:
			_prepare_match()
	elif role == "replacement":
		if NetworkManager.room_wait_reason == "editing" and not saw_editor_status:
			saw_editor_status = true
			if lobby._can_submit_ready(): _fail("could ready while other player was editing"); return
			var gate := FileAccess.open(leave_gate + ".edited", FileAccess.WRITE)
			gate.store_string("editor status verified")
			gate.close()
			print("DEDICATED_EDITOR_STATUS_OK")
		if not submitted and int(PlayerData.battle_config.get("starting_hp", 0)) != 37:
			return
		if not FileAccess.file_exists(leave_gate + ".rules-draft"):
			return
		if OS.get_cmdline_user_args().has("--waiting-outage") and not waiting_outage_verified:
			if not waiting_outage_armed and not lobby.start_btn.disabled:
				waiting_outage_armed = true
				_verify_waiting_room_outage()
			return
		_prepare_match()

func _verify_editor_outage(editor: Node) -> void:
	var card_name := "断线编辑验收"
	editor.name_input.text = card_name
	editor.name_input.text_changed.emit(card_name)
	editor.name_input.grab_focus()
	print("DEDICATED_EDITOR_OUTAGE_ARMED")
	while not NetworkManager.room_link_waiting():
		await get_tree().process_frame
	await get_tree().process_frame
	var notice := editor.get_node_or_null("RoomConnectionNotice") as Label
	if notice == null or not notice.is_visible_in_tree() or notice.text != Locale.t("editor.room_link_recovering"):
		_fail("card editor did not explain its room interruption"); return
	if not editor.name_input.has_focus() or editor.name_input.text != card_name or UIMotion.top_popup() != null:
		_fail("the room interruption interrupted editing or lost its content"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("editor-room-outage.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the card editor during room recovery"); return
	editor.save_button.pressed.emit()
	var save := _find_editor_dialog_action(editor, "editor.save_card")
	if save == null:
		_fail("save targets did not open during interruption"); return
	save.pressed.emit()
	var saved_card: CardData = PlayerData.find_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id)
	if saved_card == null or saved_card.card_name != card_name or not NetworkManager.room_link_waiting():
		_fail("could not save local edits to the selected deck during room interruption"); return
	print("DEDICATED_EDITOR_OUTAGE_SAVED")
	var close_notice := _find_editor_dialog_action(editor, "editor.after_save_return")
	if close_notice == null:
		_fail("saving locally did not open a confirmation"); return
	close_notice.pressed.emit()
	while NetworkManager.room_link_waiting():
		await get_tree().process_frame
	await get_tree().process_frame
	if notice.visible or NetworkManager.peer != old_peer or editor.name_input.text != card_name:
		_fail("room recovery changed or still covered the saved form"); return
	print("DEDICATED_EDITOR_OUTAGE_RECOVERED")
	editor.get_node("BackButton").pressed.emit()

func _find_editor_dialog_action(editor: Node, label_key: String) -> Button:
	for layer in editor.get_children():
		if layer is CanvasLayer and layer.visible and not layer.is_queued_for_deletion():
			for button: Button in layer.find_children("*", "Button", true, false):
				if button.text == Locale.t(label_key):
					return button
	return null

func _verify_ready_before_rules(_cards: Array) -> void:
	if not lobby.waiting_ui.waiting_for_host_rules() or lobby._can_submit_ready() or not lobby.start_btn.disabled:
		_fail("the early-ready fixture did not hold back the host rules"); return
	if not lobby.opponent_ready or PlayerData.opponent_battle_deck.is_empty():
		_fail("the guest discarded the host's ready deck while waiting for rules"); return
	var gate := FileAccess.open(leave_gate + ".early-ready-received", FileAccess.WRITE)
	gate.store_string("guest retained ready deck before rules")
	gate.close()
	var deadline := Time.get_ticks_msec() + 5000
	while lobby.start_btn.disabled and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if lobby.start_btn.disabled or not lobby.opponent_ready or lobby.waiting_ui.waiting_for_host_rules():
		_fail("rule synchronization did not unlock Ready with the host's deck still available"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-host-ready-before-rules.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the synchronized guest room"); return
	if OS.get_cmdline_user_args().has("--room-card-overlays") and not await _verify_opponent_deck_closed_on_cancel():
		return
	print("DEDICATED_EARLY_OPPONENT_READY_OK")

func _verify_opponent_deck_closed_on_cancel() -> bool:
	var panel: Control = lobby.waiting_ui
	var view := panel.find_child("ViewOpponentDeck", true, false) as Button
	view.pressed.emit()
	var collection := panel.find_child("CardCollectionPanel", true, false)
	if collection == null:
		_fail("the ready opponent's deck did not open")
		return false
	var inspect := collection.find_child("InspectCard", true, false) as Button
	if inspect == null:
		_fail("the opponent's deck has no inspectable cards")
		return false
	inspect.pressed.emit()
	var details := panel.find_child("TabletopCardInspector", true, false)
	if details == null:
		_fail("the opponent card's details did not open")
		return false
	var gate := FileAccess.open(leave_gate + ".opponent-deck-open", FileAccess.WRITE)
	gate.store_string("the opponent deck and its card details are open")
	gate.close()
	var deadline := Time.get_ticks_msec() + 5000
	while (is_instance_valid(collection) or is_instance_valid(details)) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if lobby.opponent_ready or not view.disabled or is_instance_valid(collection) or is_instance_valid(details):
		_fail("withdrawing readiness left the opponent's old deck or a card detail open")
		return false
	print("DEDICATED_OPPONENT_OVERLAYS_CLOSED_OK")
	return true

func _verify_live_rules_view() -> void:
	var panel: Control = lobby.waiting_ui
	panel._rules_button.pressed.emit()
	var dialog: AcceptDialog
	for child in panel.get_children():
		if child is AcceptDialog and child.find_child("FieldRuleRows", true, false) != null:
			dialog = child
			break
	if dialog == null or _read_viewed_starting_hp(dialog) != "30":
		_fail("guest did not open the original host's rules"); return
	var scroll: ScrollContainer = dialog.find_children("*", "ScrollContainer", true, false)[0]
	await get_tree().process_frame
	scroll.scroll_vertical = 60
	if scroll.scroll_vertical != 60:
		_fail("guest could not scroll the rules before the host edit"); return
	var gate := FileAccess.open(leave_gate + ".rules-view-open", FileAccess.WRITE)
	gate.store_string("guest is viewing the room rules")
	gate.close()
	var deadline := Time.get_ticks_msec() + 6000
	while _read_viewed_starting_hp(dialog) != "38" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not dialog.visible or _read_viewed_starting_hp(dialog) != "38":
		_fail("the open rules dialog kept old HP %s after the host set HP to %s" % [
			_read_viewed_starting_hp(dialog), PlayerData.battle_config.get("starting_hp")]); return
	if not panel._rule_summary.text.contains("38"):
		_fail("the room summary and open rules did not refresh together"); return
	if PlayerData.battle_config.get("mana_increment") != 2 or panel._rule_summary.text != BattleRulesHelp.room_summary(PlayerData.battle_config):
		_fail("the guest did not receive the growing Elixir recovery rule"); return
	await get_tree().process_frame
	if scroll.scroll_vertical != 60:
		_fail("refreshing the open rules reset the guest's scroll position"); return
	if not screenshot_path.is_empty():
		scroll.scroll_vertical = 0
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-live-rules.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the updated rules"); return
	dialog.get_ok_button().pressed.emit()
	print("DEDICATED_LIVE_RULE_VIEW_OK")

func _read_viewed_starting_hp(dialog: AcceptDialog) -> String:
	var rows := dialog.find_child("FieldRuleRows", true, false)
	for row in rows.get_children():
		if row is HBoxContainer and row.get_child(0).text == Locale.t("battle_config.starting_hp"):
			return row.get_child(1).text
	return ""

func _verify_waiting_room_outage() -> void:
	var room_panel: Control = lobby.waiting_ui
	var deck := PlayerData.battle_deck.duplicate()
	print("DEDICATED_WAITING_OUTAGE_ARMED")
	while not FileAccess.file_exists(leave_gate + ".waiting-outage"):
		await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 6700
	while room_panel.status.text != Locale.t("wait.room_link_waiting") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if room_panel.status.text != Locale.t("wait.room_link_waiting") or not lobby.start_btn.disabled or not lobby.create_card_btn.disabled:
		_fail("a waiting-room outage left Ready or Create Card enabled without a recovery notice"); return
	if room_panel.find_child("ExitButton", true, false).disabled:
		_fail("the waiting room could not be left during the outage"); return
	lobby.start_btn.pressed.emit()
	lobby.create_card_btn.pressed.emit()
	if lobby.i_am_ready or get_tree().current_scene != lobby or PlayerData.return_to_waiting_room:
		_fail("a blocked preparation action was still submitted during the outage"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the waiting room outage"); return
	print("DEDICATED_WAITING_OUTAGE_PAUSE_OK")
	while lobby.start_btn.disabled:
		await get_tree().process_frame
	if NetworkManager.peer != old_peer or NetworkManager.room_code != code or lobby.i_am_ready or PlayerData.battle_deck != deck:
		_fail("the short outage changed the seat, selected deck, or readiness"); return
	waiting_outage_verified = true
	print("DEDICATED_WAITING_OUTAGE_RECOVERY_OK")


func _verify_confirmation_outage(dialog: ConfirmationDialog) -> void:
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		dialog.get_ok_button().grab_focus()
		if not dialog.get_ok_button().has_focus():
			_fail("could not focus confirmation before interrupting the connection"); return
	print("DEDICATED_CONFIRMATION_OUTAGE_ARMED")
	while not FileAccess.file_exists(leave_gate + ".confirmation-outage"):
		await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 6700
	while is_instance_valid(dialog) and not dialog.get_ok_button().disabled and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(dialog):
		_fail("the confirmation closed during the outage"); return
	var notice := dialog.get_node_or_null("MatchContent/ConfirmationStatus") as Label
	if not dialog.get_ok_button().disabled or dialog.get_cancel_button().disabled or notice == null or not notice.is_visible_in_tree() or notice.text != Locale.t("wait.room_link_confirming"):
		_fail("the confirmation did not explain the outage and preserve cancellation"); return
	if DisplayServer.get_name() != "headless" and not dialog.get_cancel_button().has_focus():
		_fail("connection loss did not move keyboard focus to the available Cancel action"); return
	# A queued confirmation event must also be ignored by the handler.
	dialog.get_ok_button().pressed.emit()
	if lobby.match_agreement.local_accepted or not dialog.visible:
		_fail("the match confirmation was accepted or dismissed while disconnected"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		if dialog.position.y < 0 or dialog.position.y + dialog.size.y > get_window().size.y:
			_fail("the confirmation window places its actions outside the game window"); return
		var evidence := screenshot_path.get_base_dir().path_join("confirmation-outage.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the confirmation outage"); return
	print("DEDICATED_CONFIRMATION_OUTAGE_PAUSE_OK")
	if OS.get_cmdline_user_args().has("--cancel-during-confirmation-outage"):
		await _cancel_during_confirmation_outage(dialog)
		return
	while is_instance_valid(dialog) and dialog.get_ok_button().disabled:
		await get_tree().process_frame
	if not is_instance_valid(dialog) or not dialog.visible or notice.text == Locale.t("wait.room_link_confirming") or NetworkManager.peer != old_peer:
		_fail("recovery did not restore the same match confirmation"); return
	confirmation_outage_verified = true
	print("DEDICATED_CONFIRMATION_OUTAGE_RECOVERY_OK")

func _cancel_during_confirmation_outage(dialog: ConfirmationDialog) -> void:
	var generation := NetworkManager.room_preparation_generation
	var gate := FileAccess.open(leave_gate + ".cancel-during-outage", FileAccess.WRITE)
	gate.store_string(str(generation))
	gate.close()
	set_meta("outage_cancel_requested", true)
	dialog.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	var panel: Control = lobby.waiting_ui
	if (not NetworkManager.room_link_waiting() or not lobby.cancelling_preparation or not lobby.start_btn.disabled
			or (is_instance_valid(dialog) and dialog.visible) or panel.status.text != Locale.t("wait.cancel_ready_reconnecting")):
		_fail("cancel during the outage did not show a queued cancellation"); return
	print("DEDICATED_OUTAGE_CANCEL_QUEUED")
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-cancel-ready-reconnecting.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture cancellation during the outage"); return
	if OS.get_cmdline_user_args().has("--terminal-cancel-outage"):
		await _retry_terminal_cancellation()
		return
	while NetworkManager.room_link_waiting() or NetworkManager.room_preparation_generation == generation:
		await get_tree().process_frame
	await get_tree().create_timer(0.16).timeout
	if (NetworkManager.peer != old_peer or lobby.match_agreement.pending or lobby.i_am_ready
			or lobby.cancelling_preparation or lobby.start_btn.disabled or not lobby.start_btn.has_focus()
			or panel.status.text != Locale.t("wait.ready_cancelled")):
		_fail("the recovered cancellation did not restore focused Ready in the same room"); return
	submitted = false
	confirmed = false
	confirmation_outage_verified = true
	print("DEDICATED_CONFIRMATION_OUTAGE_RECOVERY_OK")

func _retry_terminal_cancellation() -> void:
	while is_instance_valid(lobby.waiting_ui):
		await get_tree().process_frame
	var message := Locale.t("lobby.cancel_ready_connection_lost")
	if not _room_entry_recovered(message, code) or not NetworkManager.room_code.is_empty():
		_fail("a terminal disconnect during cancellation did not restore the retry form: " + lobby.status_label.text); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-cancel-ready-disconnected.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the terminal cancellation result"); return
	print("DEDICATED_OUTAGE_CANCEL_DISCONNECTED")
	while not FileAccess.file_exists(leave_gate + ".terminal-cancel-retry"):
		await get_tree().process_frame
	set_meta("terminal_cancel_retrying", true)
	if NetworkManager.lobby_connected.is_connected(_request):
		NetworkManager.lobby_connected.disconnect(_request)
	lobby.lobby_port = lobby_port
	_press_enter()
	if not lobby.join_btn.disabled:
		_fail("the restored join form did not accept Enter"); return
	var callback := NetworkManager._lobby_callback
	NetworkManager._lobby_callback = func(response: Dictionary):
		if response.get("status") == "ok" and room_proxy_port > 0:
			response["port"] = room_proxy_port
		callback.call(response)

func _request_owner_exit() -> bool:
	var panel: Control = lobby.waiting_ui
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	var dialog := panel.get_node_or_null("LeaveRoomConfirmation") as ConfirmationDialog
	if dialog == null or not dialog.visible:
		_fail("escape did not request room departure confirmation")
		return false
	dialog.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	if panel.get_node_or_null("LeaveRoomConfirmation") != null or NetworkManager.peer != old_peer:
		_fail("cancelled departure changed the room or its connection")
		return false
	print("DEDICATED_EXIT_CANCEL_OK")
	panel.find_child("ExitButton", true, false).pressed.emit()
	dialog = panel.get_node_or_null("LeaveRoomConfirmation") as ConfirmationDialog
	if dialog == null or not dialog.visible:
		_fail("leave button did not use the same confirmation as escape")
		return false
	dialog.get_ok_button().pressed.emit()
	return true

func _check_invalid_local_deck(panel: Control) -> void:
	var choice: OptionButton = panel.deck_choice
	var original := choice.selected
	choice.item_selected.emit(choice.item_count - 1)
	var generation := NetworkManager.room_preparation_generation
	lobby.start_btn.pressed.emit()
	if lobby.i_am_ready or choice.disabled or lobby.start_btn.disabled:
		_fail("an invalid local deck changed readiness or locked deck selection"); return
	var message := Locale.t("wait.invalid_local_card", ["QA Legacy Card"])
	if panel.status.text != message:
		_fail("the deck validation did not identify the card and recovery action"); return
	await get_tree().create_timer(0.2).timeout
	if NetworkManager.room_preparation_generation != generation or not lobby.opponent_ready or panel.status.text != message:
		_fail("the local rejection changed room preparation or lost its feedback"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-invalid-local-deck.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the local deck warning"); return
	choice.item_selected.emit(original)
	await get_tree().process_frame
	if choice.get_selected_metadata() == "qa-legacy" or lobby.start_btn.disabled or panel.status.text == message:
		_fail("changing decks did not restore preparation"); return
	_checked_local_deck = true
	print("DEDICATED_LOCAL_DECK_VALIDATION_OK")


func _prepare_match() -> void:
	if has_meta("outage_cancel_requested") and not confirmation_outage_verified:
		return
	if OS.get_cmdline_user_args().has("--invalid-local-deck") and not _checked_local_deck:
		if not _checking_local_deck and lobby.opponent_ready and lobby._can_submit_ready() and not lobby.start_btn.disabled:
			_checking_local_deck = true
			await _check_invalid_local_deck(lobby.waiting_ui)
		return
	if checked_cancellation and _tests_cancelled_offer() and not cancelled_offer_verified:
		if role == "replacement" and not submitted:
			if lobby.start_btn.disabled:
				return
			lobby.start_btn.pressed.emit()
			if not lobby.i_am_ready:
				_fail("could not ready again before receiving the cancelled offer"); return
			submitted = true
		if not replaying_cancelled_offer:
			replaying_cancelled_offer = true
			_verify_cancelled_offer()
		return
	if not lobby._can_submit_ready(): return
	if not submitted:
		if lobby.start_btn.disabled:
			return
		if _tests_card_art_stall() and not checked_cancellation:
			if not NetworkManager.server_allows_card_art:
				_fail("the room server did not enable art transfer"); return
			if role == "survivor":
				var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
				image.fill(Color.DARK_CYAN)
				var path := "user://integration-card-art.png"
				if image.save_png(path) != OK:
					_fail("could not save the card art fixture"); return
				var card: CardData = PlayerData.battle_deck[0].duplicate_card()
				card.art_path = path
				PlayerData.battle_deck[0] = card
			else:
				# Let the transport deliver the image but omit the guest's receipt.
				EventBus.rpc_card_art_received.disconnect(lobby._on_card_art_received)
		lobby.start_btn.pressed.emit()
		if not lobby.i_am_ready: _fail("cannot ready"); return
		submitted = true
		if (role == "replacement" and not checked_cancellation and OS.get_cmdline_user_args().has("--room-card-overlays")
				and not OS.get_cmdline_user_args().has("--leave-during-confirmation")):
			lobby.waiting_ui.find_child("InspectRoomCard", true, false).pressed.emit()
			if lobby.waiting_ui.find_child("TabletopCardInspector", true, false) == null:
				_fail("could not open a card detail while waiting for the opponent to ready"); return
		if not checked_cancellation and OS.get_cmdline_user_args().has("--leave-during-confirmation"):
			lobby.waiting_ui.find_child("ExitButton", true, false).pressed.emit()
			if not is_instance_valid(lobby.waiting_ui._leave_dialog) or not lobby.waiting_ui._leave_dialog.visible:
				_fail("ready guest could not open the leave decision"); return
		if (role == "replacement" and not checked_cancellation and OS.get_cmdline_user_args().has("--live-rule-view")
				and not OS.get_cmdline_user_args().has("--leave-during-confirmation")):
			lobby.waiting_ui._rules_button.pressed.emit()
			if not is_instance_valid(lobby.waiting_ui._rules_view) or not lobby.waiting_ui._rules_view.visible:
				_fail("ready guest could not open the rule summary before match confirmation"); return
	if confirmed: return
	if (not checked_cancellation and OS.get_cmdline_user_args().has("--leave-during-confirmation")
			and not has_meta("leave_decision_verified") and lobby.match_agreement.pending
			and not lobby.match_agreement.offer.is_empty()):
		set_meta("leave_decision_verified", true)
		_verify_leave_decision_priority()
		return
	if (not checked_cancellation and OS.get_cmdline_user_args().has("--leave-during-confirmation")
			and not has_meta("leave_decision_resolved")):
		return
	if _tests_card_art_stall() and not checked_cancellation and lobby.waiting_ui.find_child("StartNowButton", true, false) != null:
		_fail("art timeout required an extra enter-game click before match confirmation"); return
	for dialog in lobby.match_agreement.get_children():
		if dialog is ConfirmationDialog and dialog.visible:
			if not checked_cancellation:
				if role == "survivor" and OS.get_cmdline_user_args().has("--cancel-while-leave-open"):
					if FileAccess.file_exists(leave_gate + ".leave-cancel-armed"):
						dialog.get_cancel_button().pressed.emit()
					return
				if _tests_cancelled_offer():
					cancelled_offer = lobby.match_agreement.offer.duplicate(true)
					var captured_path := leave_gate + ".cancelled-offer-captured"
					if role == "survivor" and not FileAccess.file_exists(captured_path):
						var captured := FileAccess.open(captured_path, FileAccess.WRITE)
						captured.store_string("first offer saved")
						captured.close()
					if not FileAccess.file_exists(captured_path):
						return
				if _tests_card_art_stall():
					_check_art_confirmation(dialog)
					if not FileAccess.file_exists(leave_gate + ".art-confirmed-survivor"):
						return
				if role == "replacement":
					if OS.get_cmdline_user_args().has("--room-card-overlays") and not OS.get_cmdline_user_args().has("--leave-during-confirmation"):
						var details: Node = lobby.waiting_ui.find_child("TabletopCardInspector", true, false)
						if (details != null and details.get_parent().visible) or not dialog.get_ok_button().has_focus():
							_fail("open card details did not yield to the match confirmation"); return
						if not screenshot_path.is_empty():
							await RenderingServer.frame_post_draw
							var evidence := screenshot_path.get_base_dir().path_join("room-confirmation-after-card-details.png")
							if get_viewport().get_texture().get_image().save_png(evidence) != OK:
								_fail("could not capture confirmation after card details"); return
					if OS.get_cmdline_user_args().has("--live-rule-view"):
						var rules_view: AcceptDialog = lobby.waiting_ui._rules_view
						if is_instance_valid(rules_view) and rules_view.visible:
							_fail("match confirmation left the guest's previous rules dialog open"); return
						if not dialog.get_ok_button().has_focus():
							_fail("match confirmation did not take keyboard focus"); return
						if lobby.waiting_ui.status.text != Locale.t("wait.confirming_rules"):
							_fail("room feedback did not enter confirmation with the dialog"); return
						if not screenshot_path.is_empty():
							await RenderingServer.frame_post_draw
							var evidence := screenshot_path.get_base_dir().path_join("room-match-confirmation.png")
							if get_viewport().get_texture().get_image().save_png(evidence) != OK:
								_fail("could not capture match confirmation"); return
					dialog.get_cancel_button().pressed.emit()
				return
			if match_count == 0 and OS.get_cmdline_user_args().has("--waiting-outage") and not confirmation_outage_verified:
				if not confirmation_outage_armed:
					confirmation_outage_armed = true
					_verify_confirmation_outage(dialog)
				return
			if dialog.get_ok_button().disabled:
				return
			if match_count == 0 and _start_timeout_race == "reset-first" and _start_timeout_reset and not FileAccess.file_exists(leave_gate + ".late-start-checked"):
				if role == "survivor" and not _late_start_checked:
					_late_start_checked = true
					await _check_late_start_after_reset(dialog)
				return
			if match_count == 0 and OS.get_cmdline_user_args().has("--confirmation-progress"):
				var modal_status := dialog.get_node_or_null("MatchContent/ConfirmationStatus") as Label
				if modal_status == null or not modal_status.is_visible_in_tree():
					_fail("the open confirmation does not show the other player's status"); return
				if (dialog.get_ok_button().text != Locale.t("wait.confirm_match")
						or dialog.get_cancel_button().text != Locale.t("wait.cancel_preparation")):
					_fail("the confirmation actions do not describe what they do"); return
				if role == "replacement" and not has_meta("confirmation_dialog_waiting"):
					if modal_status.text != Locale.t("wait.modal_opponent_pending"):
						_fail("the confirmation did not show that the opponent has yet to confirm"); return
					set_meta("confirmation_dialog_waiting", true)
					var gate := FileAccess.open(leave_gate + ".guest-confirmation-open", FileAccess.WRITE)
					gate.close()
				if role == "survivor" and not FileAccess.file_exists(leave_gate + ".guest-confirmation-open"):
					return
				if role == "replacement" and (not lobby.match_agreement.remote_accepted or not FileAccess.file_exists(leave_gate + ".host-confirmation-checked")):
					return
				confirmed = true
				if role == "replacement":
					if modal_status.text != Locale.t("wait.modal_opponent_confirmed") or not dialog.get_ok_button().has_focus():
						_fail("the other player confirmed but the modal did not update in place"); return
					if not screenshot_path.is_empty():
						await RenderingServer.frame_post_draw
						var evidence := screenshot_path.get_base_dir().path_join("room-confirmation-opponent-confirmed.png")
						if get_viewport().get_texture().get_image().save_png(evidence) != OK:
							_fail("could not capture the open match confirmation"); return
				await _check_confirmation_progress(dialog)
				return
			if _tests_cancelled_offer() and match_count == 0 and lobby.match_agreement.offer.get("id") == cancelled_offer.get("id"):
				_fail("the next confirmation reused the cancelled offer"); return
			if _tests_card_art_stall() and match_count == 0:
				if not _reports_art_fallback(dialog):
					_fail("the second preparation did not retain the card-art fallback"); return
				art_fallback_accepted = true
			confirmed = true
			if _tests_cancelled_offer() and match_count == 0 and not screenshot_path.is_empty():
				await RenderingServer.frame_post_draw
				if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
					_fail("could not capture the new confirmation"); return
			dialog.get_ok_button().pressed.emit()
			return

func _check_confirmation_progress(dialog: ConfirmationDialog) -> void:
	dialog.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.14).timeout
	var panel: Control = lobby.waiting_ui
	if panel.local_state.text != Locale.t("wait.rules_confirmed"):
		_fail("the room still presents a confirmed player as only ready"); return
	if role == "survivor":
		if panel.status.text != Locale.t("wait.opponent_confirming") or lobby.start_btn.disabled or not lobby.can_cancel_preparation():
			_fail("the first confirmation did not retain cancellation while waiting for the opponent"); return
		var gate := FileAccess.open(leave_gate + ".host-confirmation-checked", FileAccess.WRITE)
		gate.close()
		print("DEDICATED_WAITING_FOR_CONFIRMATION_OK")
		return
	if not lobby.match_agreement.completed or panel.remote_state.text != Locale.t("wait.rules_confirmed"):
		_fail("the guest did not show both confirmed slots"); return
	if panel.status.text != Locale.t("wait.starting_match") or not lobby.start_btn.disabled or lobby.start_btn.text != Locale.t("wait.rules_confirmed") or lobby.can_cancel_preparation():
		_fail("the guest still offers cancellation or says it is waiting for the opponent after both confirmed"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-both-confirmed.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture both players confirmed"); return
	print("DEDICATED_BOTH_CONFIRMED_OK")

func _verify_leave_decision_priority() -> void:
	var leave: ConfirmationDialog = lobby.waiting_ui._leave_dialog
	if not is_instance_valid(leave) or not leave.visible or not leave.get_cancel_button().has_focus():
		_fail("receiving a match offer interrupted the leave decision"); return
	for child in lobby.match_agreement.get_children():
		if child is ConfirmationDialog and child.visible:
			_fail("match confirmation opened before the guest resolved the leave decision"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-leave-decision.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the leave decision"); return
	if OS.get_cmdline_user_args().has("--cancel-while-leave-open"):
		await _verify_cancelled_confirmation_during_leave(leave)
		return
	leave.get_cancel_button().pressed.emit()
	for dialog in lobby.match_agreement.get_children():
		if dialog is ConfirmationDialog and dialog.visible and dialog.get_ok_button().has_focus():
			set_meta("leave_decision_resolved", true)
			print("DEDICATED_LEAVE_DECISION_PRIORITY_OK")
			return
	_fail("cancelling departure did not reveal the pending match confirmation with keyboard focus")

func _verify_cancelled_confirmation_during_leave(leave: ConfirmationDialog) -> void:
	var gate := FileAccess.open(leave_gate + ".leave-cancel-armed", FileAccess.WRITE)
	gate.store_string("the guest is deciding whether to leave")
	gate.close()
	while not checked_cancellation:
		await get_tree().process_frame
	if not leave.visible or not leave.get_cancel_button().has_focus():
		_fail("opponent cancelling preparation interrupted the leave decision"); return
	leave.get_cancel_button().pressed.emit()
	if not lobby.match_agreement.offer.is_empty() or lobby.match_agreement.pending:
		_fail("cancelling departure restored a withdrawn match request"); return
	for child in lobby.match_agreement.get_children():
		if child is ConfirmationDialog and child.visible:
			_fail("the withdrawn confirmation reopened"); return
	if not lobby.start_btn.has_focus() or lobby.start_btn.disabled or lobby.waiting_ui.status.text != Locale.t("wait.ready_cancelled"):
		_fail("cancelling departure did not restore the updated Ready action and keyboard focus"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-ready-after-remote-cancel.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the restored Ready action"); return
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter, true)
	enter.pressed = false
	get_viewport().push_input(enter, true)
	if not lobby.i_am_ready:
		_fail("Enter could not ready the guest from the restored focus"); return
	submitted = true
	set_meta("leave_decision_resolved", true)
	print("DEDICATED_NO_STALE_CONFIRMATION_OK")

func _tests_cancelled_offer() -> bool:
	return OS.get_cmdline_user_args().has("--replay-prior-offer")


func _verify_cancelled_offer() -> void:
	if cancelled_offer.is_empty():
		_fail("the first confirmation did not produce an offer"); return
	var armed_path := leave_gate + ".cancelled-offer-armed"
	var verified_path := leave_gate + ".cancelled-offer-verified"
	if role == "survivor":
		while not FileAccess.file_exists(armed_path):
			await get_tree().process_frame
		if NetworkManager.rpc("rpc_match_offer", cancelled_offer) != OK:
			_fail("the cancelled offer could not be sent through the room link"); return
		while not FileAccess.file_exists(verified_path):
			await get_tree().process_frame
	else:
		# Current readiness and the old cancellation travel on the same link, in
		# that order. The stale cancellation must not undo the new ready action.
		var generation := int(cancelled_offer.get("preparation", 0))
		if NetworkManager.rpc_id(1, "rpc_room_control", "cancel", [], generation) != OK:
			_fail("the cancelled preparation command could not be resent to the room"); return
		var armed := FileAccess.open(armed_path, FileAccess.WRITE)
		armed.store_string("guest readied again and resent the old cancellation")
		armed.close()
		var delivered: Dictionary = await NetworkManager.match_offer_received
		if delivered.get("id") != cancelled_offer.get("id"):
			_fail("the guest did not receive the cancelled offer"); return
		if not lobby.match_agreement.offer.is_empty() or lobby.match_agreement.pending or not lobby.i_am_ready:
			_fail("a late cancelled offer or action changed the next preparation"); return
		var verified := FileAccess.open(verified_path, FileAccess.WRITE)
		verified.store_string("guest ignored the cancelled offer")
		verified.close()
		print("DEDICATED_CANCELLED_OFFER_IGNORED")
	cancelled_offer_verified = true

func _tests_card_art_stall() -> bool:
	return OS.get_cmdline_user_args().has("--stall-card-art")

func _check_art_confirmation(dialog: ConfirmationDialog) -> void:
	if art_confirmation_checked:
		return
	art_confirmation_checked = true
	var incomplete: bool = lobby._my_arts_acked < lobby._my_arts_total if role == "survivor" else lobby._opponent_arts_received < lobby._opponent_arts_total
	if not incomplete or not _reports_art_fallback(dialog) or NetworkManager.room_match_started:
		_fail("automatic confirmation did not report pending card art before starting"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the card-art confirmation"); return
	print("DEDICATED_ART_CONFIRMATION_", role.to_upper())
	if role == "survivor":
		var gate := FileAccess.open(leave_gate + ".art-confirmed-survivor", FileAccess.WRITE)
		gate.store_string("host confirmed fallback visible")

func _reports_art_fallback(dialog: ConfirmationDialog) -> bool:
	return dialog.find_children("*", "Label", true, false).any(func(item: Label):
		return item.text.contains(Locale.t("wait.art_fallback"))
	)

func _timed_out_action_fixture() -> String:
	if OS.get_cmdline_user_args().has("--end-turn-timeout"):
		return "end_turn"
	if OS.get_cmdline_user_args().has("--discard-timeout"):
		return "discard"
	return ""


func _hold_timed_out_guest_action(battle: Node) -> void:
	while not FileAccess.file_exists(leave_gate + ".arm-turn-timeout"):
		await get_tree().process_frame
	EventBus.rpc_game_intent_received.disconnect(battle._on_rpc_game_intent)
	EventBus.rpc_initial_state_requested.disconnect(battle._on_rpc_initial_state_requested)
	var gate := FileAccess.open(leave_gate + ".hold-turn-timeout", FileAccess.WRITE)
	gate.close()
	while not FileAccess.file_exists(leave_gate + ".release-turn-timeout"):
		await get_tree().process_frame
	EventBus.rpc_game_intent_received.connect(battle._on_rpc_game_intent)
	EventBus.rpc_initial_state_requested.connect(battle._on_rpc_initial_state_requested)
	battle._on_rpc_initial_state_requested(0)


func _check_timed_out_guest_action(battle: Node, kind: String) -> void:
	var revision: int = battle.game.state_revision
	var hand_size: int = battle._my_hand().size()
	var card: CardData = battle._my_hand()[0] if kind == "discard" and hand_size > 0 else null
	if kind == "discard" and card == null:
		_fail("the guest began the turn without a card to discard"); return
	var gate := FileAccess.open(leave_gate + ".arm-turn-timeout", FileAccess.WRITE)
	gate.close()
	while not FileAccess.file_exists(leave_gate + ".hold-turn-timeout"):
		await get_tree().process_frame
	if kind == "discard":
		battle._on_card_discarded(card)
		if NetworkManager.pending_game_command_count() != 1 or battle._my_hand().size() != hand_size - 1:
			_fail("the discarded card did not enter local prediction"); return
	else:
		battle._on_end_turn_pressed()
	while battle._network_command_phase != "timeout":
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var message := "battle.end_turn_sync_pending" if kind == "end_turn" else "battle.action_sync_pending"
	if (battle.game.state_revision != revision or NetworkManager.pending_game_command_count() != 0
			or not battle.end_turn_button.disabled or battle.is_my_turn() or not battle.turn_wait_hint.visible
			or battle.turn_wait_hint.get_node("Label").text != Locale.t(message)):
		_fail("the timed-out guest action did not retain its lock and explain the pending synchronization"); return
	battle._on_end_turn_pressed()
	await get_tree().process_frame
	if NetworkManager.pending_game_command_count() != 0:
		_fail("ending the turn submitted a second action before the snapshot arrived"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("guest-%s-timeout.png" % kind.replace("_", "-"))
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the timed-out action"); return
	gate = FileAccess.open(leave_gate + ".release-turn-timeout", FileAccess.WRITE)
	gate.close()
	while battle.end_turn_button.disabled:
		await get_tree().process_frame
	if battle.game.state_revision != revision or battle.turn_wait_hint.visible or not battle.is_my_turn():
		_fail("the unchanged host snapshot did not restore the guest's turn"); return
	if kind == "discard":
		if battle._my_hand().size() != hand_size:
			_fail("the host snapshot did not restore the discarded card"); return
		battle._on_card_discarded(battle._my_hand()[0])
		while NetworkManager.pending_game_command_count() > 0:
			await get_tree().process_frame
		if battle.game.state_revision != revision + 1 or battle._my_hand().size() != hand_size - 1:
			_fail("the retried discard did not settle exactly once"); return
	print("DEDICATED_%s_TIMEOUT_RETRY_OK" % kind.to_upper())


func _arm_stale_discard(battle: Node) -> void:
	EventBus.rpc_game_intent_received.disconnect(battle._on_rpc_game_intent)
	var reject_stale := func(kind: String, payload: Dictionary, player: int, command_id: String, revision: int):
		EventBus.rpc_game_intent_received.connect(battle._on_rpc_game_intent)
		if kind != "discard" or battle.game.state_revision != revision:
			_fail("the host did not receive the expected first discard"); return
		var same_revision := OS.get_cmdline_user_args().has("--checkpoint-same-revision")
		if same_revision:
			payload = payload.duplicate()
			payload["index"] = -1
		else:
			battle.game.state_revision += 1
		battle._on_rpc_game_intent(kind, payload, player, command_id, revision)
		# Opponent playback can queue the action for a later frame.
		while not battle._processed_command_ids.has(command_id):
			await get_tree().process_frame
		if battle._processed_command_ids[command_id] != ("rejected" if same_revision else "stale_revision"):
			_fail("the normal host handler did not reject the discard"); return
		print("DEDICATED_STALE_DISCARD_REJECTED")
	EventBus.rpc_game_intent_received.connect(reject_stale, CONNECT_ONE_SHOT)
	var armed := FileAccess.open(leave_gate + ".stale-discard-armed", FileAccess.WRITE)
	armed.close()


func _check_discard_rejection(battle: Node) -> void:
	while not FileAccess.file_exists(leave_gate + ".stale-discard-armed"):
		await get_tree().process_frame
	var initial_revision: int = battle.game.state_revision
	var same_revision := OS.get_cmdline_user_args().has("--checkpoint-same-revision")
	var rejected_chain := OS.get_cmdline_user_args().has("--checkpoint-rejected-chain")
	var rejection_revision := initial_revision + (0 if same_revision else 1)
	var initial_hand: Array = battle._my_hand().map(func(card: CardData): return card.instance_id)
	var initial_mana: int = battle._my_field().get_total_mana()
	if initial_hand.size() < (2 if rejected_chain else 1):
		_fail("the guest has no card to discard"); return
	var mana_bar: ProgressBar = battle.player_status_hud.get_node("Margin/Content/ManaBar")
	var mana_label: Label = battle.player_status_hud.get_node("Margin/Content/ManaLabel")
	var mana_gains: Array[Node] = []
	var record_mana_gain := func(child: Node):
		if str(child.name).begins_with("StatusFx_Mana"):
			mana_gains.append(child)
	mana_bar.child_entered_tree.connect(record_mana_gain)
	var deferred_state: Array[Dictionary] = []
	var same_revision_rejections: Array[String] = []
	var record_rejection := func(command_id: String, kind: String, status: String, _latency: int):
		if kind == "discard" and status in ["rejected", "stale_revision"]:
			same_revision_rejections.append(command_id)
	if same_revision:
		NetworkManager.game_command_status.connect(record_rejection)
	var defer_rejection := func(state: Dictionary):
		if same_revision and int(state.get("state_revision", -1)) == rejection_revision:
			deferred_state.append(state)
			battle._on_rpc_authority_state(state)
		elif battle._network_command_phase == "stale_revision":
			deferred_state.append(state)
		else:
			battle._on_rpc_authority_state(state)
	EventBus.rpc_authority_state_received.disconnect(battle._on_rpc_authority_state)
	EventBus.rpc_authority_state_received.connect(defer_rejection)
	var checkpoint_first := OS.get_cmdline_user_args().has("--checkpoint-before-rejection")
	var checkpoint_after_timeout := OS.get_cmdline_user_args().has("--checkpoint-after-action-timeout")
	if checkpoint_after_timeout:
		# Exercise the room recovery path while normal initial-state RPCs
		# can still be queued alongside the delayed rejection.
		EventBus.rpc_initial_state_received.disconnect(battle._on_rpc_initial_state)
	if checkpoint_first:
		print("DEDICATED_STALE_DISCARD_READY")
		while not FileAccess.file_exists(leave_gate + ".hold-stale-discard-reply"):
			await get_tree().process_frame
	battle._on_card_discarded(battle._my_hand()[0])
	if rejected_chain:
		battle._on_card_discarded(battle._my_hand()[0])
	var submitted := 2 if rejected_chain else 1
	if battle._my_hand().size() != initial_hand.size() - submitted or NetworkManager.pending_game_command_count() != submitted:
		_fail("the first discard did not visibly enter prediction"); return
	if checkpoint_after_timeout:
		while battle._network_command_phase != "timeout" or NetworkManager.pending_game_command_count() > 0:
			await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		if (NetworkManager.pending_game_command_count() != 0 or battle.is_my_turn()
				or not battle.end_turn_button.disabled or not battle.turn_wait_hint.visible
				or battle.turn_wait_hint.get_node("Label").text != Locale.t("battle.action_sync_pending")):
			_fail("the timed-out discard must show synchronization and keep input locked"); return
		print("DEDICATED_TIMEOUT_SYNC_VISIBLE")
	if same_revision:
		while battle._waiting_for_action_state():
			await get_tree().process_frame
	else:
		while deferred_state.is_empty():
			await get_tree().process_frame
	await get_tree().process_frame
	if not mana_gains.is_empty():
		_fail("an unconfirmed discard played mana gain feedback"); return
	if not checkpoint_first and mana_label.text != Locale.t("battle.mana_value", [initial_mana + 1, battle._my_field().max_mana]):
		_fail("the discard prediction stopped updating the visible mana total"); return
	if checkpoint_first and battle._room_checkpoint_revision != rejection_revision:
		_fail("the ordinary rejection arrived before the room checkpoint"); return
	if not same_revision:
		if (battle.is_my_turn() or not battle.end_turn_button.disabled or not battle.turn_wait_hint.visible
				or battle.turn_wait_hint.get_node("Label").text != Locale.t("battle.action_sync_pending")):
			_fail("the real rejection unlocked input before its battle snapshot was displayed"); return
		battle._on_end_turn_pressed()
		if NetworkManager.pending_game_command_count() != 0:
			_fail("the guest submitted a new action before the correction was displayed"); return
	print("DEDICATED_DISCARD_REJECTION_WAITED_FOR_STATE")
	if not same_revision:
		EventBus.rpc_authority_state_received.disconnect(defer_rejection)
		EventBus.rpc_authority_state_received.connect(battle._on_rpc_authority_state)
		for state in deferred_state:
			battle._on_rpc_authority_state(state)
	if checkpoint_after_timeout:
		EventBus.rpc_initial_state_received.connect(battle._on_rpc_initial_state)
	while battle._waiting_for_action_state():
		await get_tree().process_frame
	await get_tree().process_frame
	var restored_hand: Array = battle._my_hand().map(func(card: CardData): return card.instance_id)
	var hints: Array[Node] = battle._toast_feed.find_children("*", "Label", true, false) if is_instance_valid(battle._toast_feed) else []
	if (restored_hand != initial_hand or battle._my_field().get_total_mana() != initial_mana or not mana_gains.is_empty()
			or battle.game.state_revision != rejection_revision or not battle.is_my_turn()
			or battle.turn_wait_hint.visible or hints.is_empty() or hints.back().text != Locale.t("tip.command_resynced")):
		_fail("the host rejection did not restore the hand and make the retry prompt actionable"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("guest-discard-rejected.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the corrected hand after rejection"); return
	if same_revision:
		while deferred_state.size() < submitted:
			await get_tree().process_frame
		await get_tree().process_frame
		EventBus.rpc_authority_state_received.disconnect(defer_rejection)
		EventBus.rpc_authority_state_received.connect(battle._on_rpc_authority_state)
		NetworkManager.game_command_status.disconnect(record_rejection)
		if same_revision_rejections.size() != 1 or not battle.is_my_turn():
			_fail("the delayed ordinary rejection must not relock the recovered battle or announce rejection again"); return
	battle._on_card_discarded(battle._my_hand()[0])
	while NetworkManager.pending_game_command_count() > 0:
		await get_tree().process_frame
	await get_tree().process_frame
	if battle.game.state_revision != rejection_revision + 1 or battle._my_hand().size() != initial_hand.size() - 1:
		_fail("the discarded card did not settle exactly once after retry"); return
	# A checkpoint presents the confirmed total and log without replaying resource effects.
	var expected_gain_fx := 0 if battle._room_checkpoint_revision == rejection_revision + 1 else 1
	if (battle._my_field().get_total_mana() != initial_mana + 1 or mana_gains.size() != expected_gain_fx
			or battle.combat_broadcast_label.tooltip_text != Locale.t("tip.discard_mana")):
		_fail("the confirmed retry did not show the appropriate mana gain feedback"); return
	var retry_labels: Array[Node] = battle._toast_feed.find_children("*", "Label", true, false)
	if retry_labels.any(func(label: Label): return label.is_visible_in_tree() and label.text == Locale.t("tip.command_resynced")):
		_fail("the retry prompt remained visible after the discard was accepted"); return
	mana_bar.child_entered_tree.disconnect(record_mana_gain)
	print("DEDICATED_DISCARD_REJECTION_RETRY_OK")


func _check_discard_at_mana_cap(battle: Node) -> int:
	var before_revision: int = battle.game.state_revision
	var field: BattleField = battle._my_field()
	var discard_count := field.max_mana - field.current_mana + 1
	if discard_count <= 0 or battle._my_hand().size() < discard_count:
		_fail("the mana cap fixture cannot reach maximum mana by discarding")
		return 0
	var checkpoint_first := OS.get_cmdline_user_args().has("--checkpoint-before-rejection")
	if checkpoint_first and discard_count < 2:
		_fail("the checkpoint fixture needs one refund before the capped discard")
		return 0
	var cap_revision := before_revision + discard_count
	var late_cap_replies: Array[Dictionary] = []
	var record_cap_reply := func(state: Dictionary):
		if int(state.get("state_revision", -1)) == cap_revision and not state.get("_feedback_events", []).is_empty():
			late_cap_replies.append(state)
	var batch_count := discard_count - (1 if checkpoint_first else 0)
	for index in range(batch_count):
		var at_cap := index == batch_count - 1
		var submitted := 1
		var prior_log_count: int = battle._action_log_entries.size()
		if at_cap and checkpoint_first:
			submitted = 2
			EventBus.rpc_authority_state_received.connect(record_cap_reply)
			print("DEDICATED_CAP_DISCARD_READY")
			while not FileAccess.file_exists(leave_gate + ".hold-cap-discard-reply"):
				await get_tree().process_frame
		var hand_size: int = battle._my_hand().size()
		var mana_before: int = battle._my_field().get_total_mana()
		for command in range(submitted):
			battle._on_card_discarded(battle._my_hand()[0])
		if submitted == 2 and NetworkManager.pending_game_command_count() != 2:
			_fail("the guest did not submit both consecutive discards")
			return 0
		while battle.game.state_revision < before_revision + index + submitted or NetworkManager.pending_game_command_count() > 0:
			await get_tree().process_frame
		await get_tree().process_frame
		if (battle._my_hand().size() != hand_size - submitted
				or battle._my_field().get_total_mana() != mana_before + submitted - (1 if at_cap else 0)):
			_fail("discard did not settle with the expected hand and mana")
			return 0
		if at_cap and checkpoint_first:
			if battle._room_checkpoint_revision != cap_revision or not late_cap_replies.is_empty():
				_fail("the capped discard did not settle from the checkpoint first")
				return 0
			print("DEDICATED_CAP_DISCARD_CHECKPOINT_APPLIED")
			if (battle._action_log_entries.size() != prior_log_count + 2
					or battle._action_log_entries[0].text != Locale.t("tip.discard_mana_full")
					or battle._action_log_entries[1].text != Locale.t("tip.discard_mana")):
				_fail("the checkpoint did not show both settled discards in order")
				return 0
		if at_cap and battle.combat_broadcast_label.tooltip_text != Locale.t("tip.discard_mana_full"):
			_fail("the guest did not see the settled discard at full mana in the battle feed")
			return 0
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path.get_base_dir().path_join("guest-discard-mana-cap.png")) != OK:
			_fail("could not capture the capped discard feedback")
			return 0
	if checkpoint_first:
		while late_cap_replies.is_empty():
			await get_tree().process_frame
		await get_tree().process_frame
		EventBus.rpc_authority_state_received.disconnect(record_cap_reply)
		var cap_entries: Array = battle._action_log_entries.filter(func(entry): return entry.text == Locale.t("tip.discard_mana_full"))
		var refund_entries: Array = battle._action_log_entries.filter(func(entry): return entry.text == Locale.t("tip.discard_mana"))
		if cap_entries.size() != 1 or refund_entries.size() != discard_count or battle.game.state_revision != cap_revision:
			_fail("the late discard result duplicated its log entry or reapplied the action")
			return 0
		print("DEDICATED_CAP_DISCARD_LATE_REPLY_OK")
	return discard_count


func _observe_guest_targeting(battle: Node) -> bool:
	var packets: Array[Vector3i] = []
	var record_packet := func(source: int, target: int, player: int): packets.append(Vector3i(source, target, player))
	EventBus.rpc_targeting_arrow_received.connect(record_packet)
	var deadline := Time.get_ticks_msec() + 8500
	while not battle.attack_arrow.visible and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not battle.attack_arrow.visible:
		_fail("the host did not see the guest start aiming: packets=%s turn=%d" % [packets, battle.game.current_player])
		return false
	var hold_until := Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < hold_until:
		await get_tree().process_frame
		if not battle.attack_arrow.visible or battle.remote_arrow_source != 0 or battle.remote_arrow_target != 0:
			_fail("the guest's stationary aim disappeared before cancellation")
			return false
	var gate := FileAccess.open(leave_gate + ".stationary-aim-seen", FileAccess.WRITE)
	gate.close()
	deadline = Time.get_ticks_msec() + 2500
	while battle.attack_arrow.visible and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if battle.attack_arrow.visible:
		_fail("the guest's cancelled aim still appears on the host")
		return false
	EventBus.rpc_targeting_arrow_received.disconnect(record_packet)
	print("DEDICATED_STATIONARY_AIM_OK")
	return true


func _hold_then_cancel_targeting(battle: Node) -> bool:
	battle._on_attack_requested(0)
	var original_pointer := get_viewport().get_mouse_position()
	var target: Vector2 = battle._their_slots_ui()[0].get_global_rect().get_center()
	get_viewport().warp_mouse(target)
	await get_tree().process_frame
	await get_tree().process_frame
	if battle.current_attacker_idx != 0 or battle.last_hovered_target != 0:
		get_viewport().warp_mouse(original_pointer)
		_fail("the guest could not enter aim: source=%d target=%d cursor=%s expected=%s" % [
			battle.current_attacker_idx, battle.last_hovered_target, battle.get_global_mouse_position(), target])
		return false
	var deadline := Time.get_ticks_msec() + 7000
	while not FileAccess.file_exists(leave_gate + ".stationary-aim-seen") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not FileAccess.file_exists(leave_gate + ".stationary-aim-seen"):
		get_viewport().warp_mouse(original_pointer)
		_fail("the guest could not sustain targeting on the host")
		return false
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	escape = escape.duplicate()
	escape.pressed = false
	get_viewport().push_input(escape, true)
	get_viewport().warp_mouse(original_pointer)
	if battle.current_attacker_idx >= 0 or UIMotion.top_popup() != null:
		_fail("Escape did not cancel the guest's aim in battle")
		return false
	return true


func _check_guest_combat(battle: Node) -> bool:
	var check_stationary_aim := OS.get_cmdline_user_args().has("--stationary-aim")
	var board_gate := leave_gate + ".combat-checkpoint-board"
	var done_gate := leave_gate + ".combat-checkpoint-done"
	if role == "survivor":
		while not FileAccess.file_exists(board_gate):
			await get_tree().process_frame
		var medic := CardData.new("医护兵", 1, 6, 1, [{
			"skill_name": "战地治疗", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
			"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 2}],
		}])
		medic.hp = 3
		var guest: BattleField = battle.game.player2_field
		guest.slots[0] = CardData.new("先锋", 1, 6, 3)
		guest.slots[1] = medic
		guest.current_mana = 4
		guest.temp_mana = 0
		guest.action_points = 1
		guest.action_budget = 1
		guest.actions_taken = 1
		battle.game.player_field.slots[0] = CardData.new("守卫", 1, 8, 1)
		battle.game.current_player = 2
		battle._refresh_hand_ui()
		battle.update_entire_screen()
		battle._commit_authority_state("combat checkpoint fixture")
		if check_stationary_aim:
			return await _observe_guest_targeting(battle)
		while not FileAccess.file_exists(done_gate):
			await get_tree().process_frame
		if (not battle.turn_label.text.contains(Locale.t("battle.opponent_turn")) or battle.turn_wait_hint.visible
				or battle.combat_broadcast_label.self_modulate.a < 0.9
				or not battle.combat_broadcast_label.tooltip_text.contains("战地治疗")):
			_fail("the host did not see the guest's resolved skill while waiting on the guest's turn")
			return false
		return true

	var gate := FileAccess.open(board_gate, FileAccess.WRITE)
	gate.close()
	while battle._my_field().slots[1] == null or not battle.is_my_turn():
		await get_tree().process_frame
	if check_stationary_aim:
		return await _hold_then_cancel_targeting(battle)
	var revision: int = battle.game.state_revision
	var log_count: int = battle._action_log_entries.size()
	var late_replies: Array[int] = []
	var record_reply := func(state: Dictionary):
		var reported_revision := int(state.get("state_revision", -1))
		if reported_revision in [revision + 1, revision + 2] and not state.get("_feedback_events", []).is_empty():
			late_replies.append(reported_revision)
	EventBus.rpc_authority_state_received.connect(record_reply)
	print("DEDICATED_COMBAT_CHECKPOINT_READY")
	while not FileAccess.file_exists(leave_gate + ".hold-combat-replies"):
		await get_tree().process_frame
	battle._on_attack_requested(0)
	battle._on_enemy_slot_clicked(0)
	battle._on_skill_activated(1, 0)
	if NetworkManager.pending_game_command_count() != 2:
		_fail("the guest did not submit both combat actions through the battle controls")
		return false
	await get_tree().process_frame
	await get_tree().process_frame
	var local_splash: Tween = battle.splash_tween
	if local_splash == null:
		_fail("the locally submitted actions did not show a combat splash")
		return false
	while battle.game.state_revision < revision + 2 or NetworkManager.pending_game_command_count() > 0:
		await get_tree().process_frame
	await get_tree().process_frame
	var field: BattleField = battle._my_field()
	var entries: Array = battle._action_log_entries
	if (battle._room_checkpoint_revision != revision + 2 or not late_replies.is_empty()
			or field.slots[1].hp != 5 or not field.slots[1].skills_used.has(0) or battle._their_field().slots[0].hp != 5
			or field.action_points != 0 or field.get_total_mana() != 2 or field.actions_taken != 3
			or entries.size() != log_count + 2 or entries[0].kind != "skill" or entries[1].kind != "attack"
			or not entries[0].text.contains("战地治疗") or not entries[1].text.contains("守卫") or battle.splash_tween != local_splash):
		_fail("combat checkpoint did not show both action results, resources and logs without replaying the splash")
		return false
	if not screenshot_path.is_empty():
		battle._toggle_action_log()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path.get_base_dir().path_join("guest-combat-checkpoint.png")) != OK:
			_fail("could not capture the combat checkpoint log")
			return false
		battle._close_action_log()
	print("DEDICATED_COMBAT_CHECKPOINT_APPLIED")
	while late_replies.size() < 2:
		await get_tree().process_frame
	await get_tree().process_frame
	EventBus.rpc_authority_state_received.disconnect(record_reply)
	if (late_replies != [revision + 1, revision + 2] or battle.game.state_revision != revision + 2
			or battle._action_log_entries.size() != log_count + 2 or battle.splash_tween != local_splash):
		_fail("late attack or skill reply replayed the action, splash or battle log")
		return false
	gate = FileAccess.open(done_gate, FileAccess.WRITE)
	gate.close()
	print("DEDICATED_COMBAT_CHECKPOINT_LATE_REPLIES_OK")
	return true


func _play_first_match(battle: Node) -> void:
	if _tests_card_art_stall():
		if not art_fallback_accepted:
			_fail("battle started without accepting the fallback in the rules confirmation"); return
		print("DEDICATED_ART_FALLBACK_STARTED_", role.to_upper())
	prior_match_id = NetworkManager.battle_match_id
	if _start_timeout_race == "start-first":
		if NetworkManager.room_wait_reason == "start_timeout" or not NetworkManager.room_match_started or NetworkManager.peer != old_peer:
			_fail("the return request displaced the committed match"); return
		if role == "survivor" and NetworkManager.battle_match_id != _held_start_id:
			_fail("the server replaced the committed match identifier"); return
		print("DEDICATED_COMMITTED_START_PRESERVED")
	var opener: int = battle.game.starting_player
	if opener != NetworkManager.match_opening_player or battle.game.current_player != opener or opener not in [1, 2]:
		_fail("the opening turn did not match the server's toss"); return
	print("DEDICATED_OPENING_PLAYER ", opener)
	var guest_revision := 1 if opener == 2 else 2
	var timeout_action := _timed_out_action_fixture()
	var discard_rejection := OS.get_cmdline_user_args().has("--discard-rejection")
	var guest_fault := OS.get_cmdline_user_args().has("--hold-gameplay-replies") or _tests_short_outage() or not timeout_action.is_empty() or discard_rejection
	if role == "survivor":
		if not timeout_action.is_empty():
			_hold_timed_out_guest_action(battle)
		elif discard_rejection:
			_arm_stale_discard(battle)
		while not battle.is_my_turn() or battle.end_turn_button.disabled:
			await get_tree().process_frame
		if opener == 2 and guest_fault:
			while not FileAccess.file_exists(leave_gate + ".guest-action-checked"):
				await get_tree().process_frame
		battle._on_end_turn_pressed()
	if role == "replacement":
		while not battle.is_my_turn() or battle.end_turn_button.disabled:
			await get_tree().process_frame
		if _tests_short_outage():
			# Start the interruption while this client can issue a command and its
			# last server reply is fresh. Earlier random loss may precede the outage.
			while not battle.is_my_turn() or NetworkManager._now() - NetworkManager._last_room_link_reply > 1.0:
				await get_tree().process_frame
		if not timeout_action.is_empty():
			await _check_timed_out_guest_action(battle, timeout_action)
			if finished:
				return
			if timeout_action == "discard":
				guest_revision += 1
		elif discard_rejection:
			await _check_discard_rejection(battle)
			if finished:
				return
			var rejection_steps := 1 if OS.get_cmdline_user_args().has("--checkpoint-same-revision") else 2
			guest_revision += rejection_steps + await _check_discard_at_mana_cap(battle)
			if finished:
				return
		elif guest_fault:
			print("DEDICATED_GUEST_TURN_READY")
			while not FileAccess.file_exists(leave_gate + ".guest-turn"):
				await get_tree().process_frame
		if _tests_prior_match():
			NetworkManager.game_command_status.connect(_capture_prior_turn)
		battle._on_end_turn_pressed()
		if _tests_short_outage() and not await _check_short_outage_pause(battle):
			return
		while battle.game.state_revision < guest_revision or NetworkManager.pending_game_command_count() > 0:
			await get_tree().process_frame
		if _tests_short_outage():
			# An authoritative result can arrive ahead of the next link probe.
			# Sample the HUD after the probe and its deferred UI refresh.
			var recovery_deadline := Time.get_ticks_msec() + int(NetworkManager.ROOM_LINK_PROBE_INTERVAL * 1000) + 1000
			while NetworkManager.room_link_waiting() and Time.get_ticks_msec() < recovery_deadline:
				await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			if battle.battle_finished or NetworkManager.peer != old_peer or battle.game.state_revision != guest_revision:
				_fail("traffic restoration changed the room or advanced the submitted turn more than once"); return
			if (NetworkManager.room_link_waiting() or not battle.end_turn_button.disabled
					or not battle.turn_label.text.contains(Locale.t("battle.opponent_turn"))
					or battle.turn_wait_hint.visible):
				_fail("recovered battle did not return to the fixed opponent-turn label"); return
			print("DEDICATED_SHORT_OUTAGE_RECOVERY_OK")
		NetworkManager._network_diag("test_guest_turn_visible", {"revision": guest_revision})
		if opener == 2 and guest_fault:
			var checked := FileAccess.open(leave_gate + ".guest-action-checked", FileAccess.WRITE)
			checked.store_string("guest confirmed their first turn")
			checked.close()
	while battle.game.current_player != opener or battle.game.turn_number != 2 or NetworkManager.pending_game_command_count() > 0:
		await get_tree().process_frame
	if discard_rejection and not battle._action_log_entries.any(func(entry):
			return entry.text == Locale.t("tip.discard_mana_full")):
		_fail("the settled discard at full mana was missing from the battle log"); return
	if (OS.get_cmdline_user_args().has("--combat-checkpoint") or OS.get_cmdline_user_args().has("--stationary-aim")) and not await _check_guest_combat(battle):
		return
	print("DEDICATED_GUEST_TURN_SYNC_", role.to_upper(), " revision=", battle.game.state_revision)
	print("DEDICATED_GUEST_TURN_STATE ", battle._web_turn_hash())
	# Keep the authoritative state intact while the guest receives any late turn replies.
	var turn_verified := leave_gate + ".guest-turn-verified"
	if role == "replacement":
		var gate := FileAccess.open(turn_verified, FileAccess.WRITE)
		gate.close()
	else:
		while not FileAccess.file_exists(turn_verified):
			await get_tree().process_frame
	if _tests_prior_match() and role == "survivor":
		prior_snapshot = battle.game.export_initial_state()
	var skill_result_host := OS.get_cmdline_user_args().has("--skill-result=host")
	var skill_result_guest := OS.get_cmdline_user_args().has("--skill-result=guest")
	if skill_result_host or skill_result_guest:
		if not await _finish_with_lethal_skill(battle, 2 if skill_result_guest else 1):
			return
	else:
		# Set up the same terminal state on both clients, then use the normal result screen.
		battle.game.player2_field.player_hp = 0
		if not battle._check_and_show_game_over(): _fail("result not shown"); return
	var result := battle.get_node("CanvasLayer/BattleResultLayer")
	await get_tree().process_frame
	if UIMotion.top_popup() != result:
		_fail("normal results did not take over the modal stack"); return
	var won := (role == "survivor") != skill_result_guest
	var summary := Locale.t("result.summary_personal", [battle.game.turn_number, battle._my_field().player_hp, battle._their_field().player_hp])
	var result_labels := result.find_children("*", "Label", true, false).filter(func(label: Label): return label.is_visible_in_tree())
	var visible_text := result_labels.map(func(label: Label): return label.text)
	var expected_title := Locale.t("result.online_win" if won else "result.online_loss")
	if visible_text != [expected_title, Locale.t("result.mode_online"), summary]:
		_fail("the result did not show a single outcome and both health totals from the player's perspective"); return
	if not screenshot_path.is_empty() and role == "replacement":
		while result.modulate.a < 1.0:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("result-guest-perspective.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the guest's perspective on the result"); return
	if role == "replacement" and OS.get_cmdline_user_args().has("--return-during-outage"):
		await _check_return_during_outage()
		return
	var buttons: Array[Node] = result.find_children("*", "Button", true, false)
	for button in buttons:
		if button.text != Locale.t("result.back_room"): continue
		if role == "replacement":
			await get_tree().create_timer(2.0).timeout
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			get_viewport().push_input(escape, true)
		else:
			if DisplayServer.get_name() == "headless":
				button.pressed.emit()
			elif not await _return_from_result_by_keyboard(result, button):
				return
		return
	_fail("result has no return-to-room button")


func _finish_with_lethal_skill(battle: Node, caster: int) -> bool:
	GamePreferences.set_animation_acceleration(false)
	var host := role == "survivor"
	var fixture_ready := leave_gate + ".lethal-skill-ready"
	var source: BattleField = battle._field_for_player(caster)
	var target: BattleField = battle._field_for_player(3 - caster)
	var hud: Control = battle.enemy_status_hud if (host == (caster == 1)) else battle.player_status_hud
	var hp_bar := hud.get_node("Margin/Content/HpBar") as ProgressBar
	if host:
		var hit := {"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ENEMY,
			"effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
		source.slots[2] = CardData.new("终结测试", 0, 5, 1, [{
			"skill_name": "最后一击", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [hit, hit.duplicate()]
		}])
		target.player_hp = 2
		battle.game.current_player = caster
		source.action_points = maxi(2, source.action_points)
		battle.update_entire_screen()
		battle._commit_authority_state("lethal skill fixture")
		while not is_equal_approx(hp_bar.value, 2.0) or (caster == 1 and not FileAccess.file_exists(fixture_ready)):
			await get_tree().process_frame
		if caster == 1:
			battle._on_skill_activated(2, 0)
	else:
		while battle._field_for_player(3 - caster).player_hp != 2 or not is_equal_approx(hp_bar.value, 2.0):
			await get_tree().process_frame
		var gate := FileAccess.open(fixture_ready, FileAccess.WRITE)
		gate.close()
	var follow_up := ""
	var receipts := {}
	var record_receipt := func(id: String, _kind: String, status: String, _ms: int): receipts[id] = status
	var revision: int = battle.game.state_revision
	var hand: Array = battle._hand_for_player(caster)
	var hand_size := hand.size()
	if not host and caster == 2:
		NetworkManager.game_command_status.connect(record_receipt)
		battle._on_skill_activated(2, 0)
		follow_up = NetworkManager.send_game_intent("discard", {"location": "hand", "index": 0}, caster, revision + 1)
		if follow_up.is_empty() or NetworkManager.pending_game_command_count() != 2:
			_fail("the lethal skill and follow-up did not both go in flight"); return false
		await get_tree().process_frame
		await get_tree().process_frame
		var hp_label := hud.get_node("Margin/Content/HpLabel") as Label
		if battle._confirmed_game != null and hp_label.text != Locale.t("battle.hp_value", [2, target.max_player_hp]):
			_fail("the predicted lethal hit displayed zero before the result was confirmed"); return false
	while battle._field_for_player(3 - caster).player_hp > 0 or battle._confirmed_game != null:
		await get_tree().process_frame
	var result_path := "CanvasLayer/BattleResultLayer"
	if battle.get_node_or_null(result_path) != null or battle.is_my_turn() or hp_bar.value <= 0:
		_fail("the lethal skill must block input and present the health change before opening results"); return false
	await get_tree().process_frame
	if (battle.turn_wait_hint.visible or battle.turn_label.text != Locale.t("battle.finishing_match")
			or not battle.abandon_battle_button.disabled):
		_fail("settled lethal damage must replace pending command and turn hints with match completion"); return false
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.18).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("lethal-skill-%s.png" % role)
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the last skill before results"); return false
	while battle.get_node_or_null(result_path) == null:
		await get_tree().process_frame
	if not follow_up.is_empty():
		while receipts.get(follow_up) in ["sent", "received", "resent"]:
			await get_tree().process_frame
		NetworkManager.game_command_status.disconnect(record_receipt)
		var retry_prompt: WeakRef = battle._command_result_prompt
		if receipts.get(follow_up) != "rejected" or (retry_prompt != null and retry_prompt.get_ref() != null):
			_fail("a post-victory follow-up must be rejected without a retry prompt"); return false
	if caster == 2 and (battle.game.state_revision != revision + 1 or battle._hand_for_player(caster).size() != hand_size):
		_fail("a command sent after the lethal move changed the final board"); return false
	if not is_zero_approx(hp_bar.value) or battle.splash_panel.is_visible_in_tree():
		_fail("the result opened before the losing health bar settled or the skill card withdrew"); return false
	GamePreferences.set_animation_acceleration(true)
	print("DEDICATED_LETHAL_SKILL_PRESENTED_", role.to_upper())
	return true


func _return_from_result_by_keyboard(result: Control, room_button: Button) -> bool:
	if not room_button.has_focus():
		_fail("the finished match did not focus Return to Room"); return false
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	get_viewport().push_input(tab, true)
	var menu_button := get_viewport().gui_get_focus_owner() as Button
	if menu_button == null or not result.is_ancestor_of(menu_button) or menu_button.text != Locale.t("result.back_menu"):
		_fail("Tab did not move focus to Return to Main Menu"); return false
	if not screenshot_path.is_empty():
		while result.modulate.a < 1.0:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("keyboard-result-navigation.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture keyboard focus on the battle result"); return false
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	get_viewport().push_input(accept, true)
	accept = accept.duplicate() as InputEventKey
	accept.pressed = false
	get_viewport().push_input(accept, true)
	if not PlayerData.return_to_waiting_room or NetworkManager.room_departure_pending or NetworkManager.peer != old_peer:
		_fail("Enter on the previously focused result button interfered with Escape returning to the room"); return false
	print("DEDICATED_RESULT_TRANSITION_INPUT_OK")
	return true


func _check_return_during_outage() -> void:
	print("DEDICATED_RESULT_RETURN_OUTAGE_ARMED")
	while not NetworkManager.room_link_waiting():
		await get_tree().process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().scene_changed
	await get_tree().process_frame
	var room_page := get_tree().current_scene
	if room_page.scene_file_path != "res://DedicatedLobby.tscn" or not is_instance_valid(room_page.waiting_ui):
		_fail("returning during interruption lost the original room"); return
	var panel: Control = room_page.waiting_ui
	if not NetworkManager.room_link_waiting() or panel.status.text != Locale.t("wait.room_link_waiting") or not room_page.start_btn.disabled or not room_page.create_card_btn.disabled:
		_fail("returning from results reported a healthy room before traffic resumed"); return
	if panel.remote_state.text != Locale.t("wait.opponent_status_unavailable"):
		_fail("the recovering room implied that the other player was absent or ready"); return
	panel.request_leave()
	var leave := panel.get_node_or_null("LeaveRoomConfirmation") as ConfirmationDialog
	if leave == null or not leave.visible:
		_fail("could not ask to leave the disconnected room"); return
	leave.get_cancel_button().pressed.emit()
	if NetworkManager.peer != old_peer or not NetworkManager.room_link_waiting():
		_fail("cancelling departure during the interruption changed the connection"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the recovering room"); return
	print("DEDICATED_RESULT_RETURN_OUTAGE_OK")

func _tests_short_outage() -> bool:
	return OS.get_cmdline_user_args().has("--short-outage")

func _tests_prior_match() -> bool:
	return OS.get_cmdline_user_args().has("--replay-prior-match")

func _tests_long_outage() -> bool:
	return OS.get_cmdline_user_args().has("--long-outage")

func _tests_join_during_results() -> bool:
	return OS.get_cmdline_user_args().has("--join-during-results")


func _verify_join_during_result() -> void:
	await get_tree().create_timer(0.25).timeout
	var panel: Control = lobby.waiting_ui
	if panel.status.text != Locale.t("wait.opponent_viewing_results") or not lobby.start_btn.disabled or not lobby.create_card_btn.disabled:
		_fail("guest could not tell the host was in results: " + panel.status.text); return
	if panel._rule_summary.text != Locale.t("wait.syncing_room_rules") or not panel._rules_button.disabled:
		_fail("the waiting guest saw local defaults as the current room rules"); return
	lobby.create_card_btn.pressed.emit()
	if PlayerData.return_to_waiting_room:
		_fail("the guest's editor opened before the host returned"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the guest waiting for the result"); return
	panel.find_child("ExitButton", true, false).pressed.emit()
	var departure := panel.get_node_or_null("LeaveRoomConfirmation") as ConfirmationDialog
	if departure == null or not departure.visible:
		_fail("the guest could not choose to leave the occupied room"); return
	departure.get_cancel_button().pressed.emit()
	if NetworkManager.peer != old_peer or NetworkManager.room_code != code:
		_fail("canceling departure lost the guest's occupied room"); return
	var seen := FileAccess.open(leave_gate + ".guest-saw-result", FileAccess.WRITE)
	seen.store_string("guest saw result status before host returned")
	seen.close()
	print("DEDICATED_GUEST_WAITING_FOR_RESULT_OK")
	while lobby.start_btn.disabled or lobby.create_card_btn.disabled or panel._rules_button.disabled:
		await get_tree().process_frame
	if NetworkManager.peer != old_peer or NetworkManager.room_code != code or lobby.i_am_ready:
		_fail("the host's return changed the guest's room or readiness"); return
	if int(PlayerData.battle_config.get("starting_hp", 0)) != 37 or not panel._rule_summary.text.contains("37"):
		_fail("the guest did not receive and display the promoted host's current rules"); return
	lobby.start_btn.pressed.emit()
	if not lobby.i_am_ready:
		_fail("the guest could not ready after the host returned"); return
	while not FileAccess.file_exists(leave_gate + ".host-saw-new-ready"):
		await get_tree().process_frame
	_finish("DEDICATED_RESULT_GUEST_READY_OK")


func _verify_result_host_saw_guest() -> void:
	while not lobby.opponent_ready or lobby.start_btn.disabled:
		await get_tree().process_frame
	var seen := FileAccess.open(leave_gate + ".host-saw-new-ready", FileAccess.WRITE)
	seen.store_string("the promoted host saw the fresh guest ready")
	seen.close()
	_finish("DEDICATED_RESULT_HOST_SAW_NEW_READY")

func _capture_prior_turn(command_id: String, kind: String, status: String, _latency: int) -> void:
	if kind != "end_turn" or status != "sent":
		return
	prior_turn = (NetworkManager.pending_game_commands().back() as Dictionary).duplicate(true)
	prior_turn["command_id"] = command_id
	NetworkManager.game_command_status.disconnect(_capture_prior_turn)

func _check_short_outage_pause(battle: Node) -> bool:
	var submission_deadline := Time.get_ticks_msec() + 1800
	while NetworkManager.pending_game_command_count() == 0 and not battle.battle_finished and Time.get_ticks_msec() < submission_deadline:
		await get_tree().process_frame
	if NetworkManager.pending_game_command_count() != 1:
		_fail("the outage began before a turn could be submitted"); return false
	if not screenshot_path.is_empty():
		get_window().size = Vector2i(640, 360)
	await get_tree().create_timer(8.1).timeout
	if battle.battle_finished or NetworkManager.peer != old_peer or NetworkManager.pending_game_command_count() != 1:
		_fail("a short outage abandoned the battle or lost the submitted turn"); return false
	var hint: Label = battle.turn_wait_hint.get_node("Label")
	if not battle.end_turn_button.disabled or not battle.turn_wait_hint.visible or hint.text != Locale.t("battle.room_link_waiting"):
		_fail("the live battle did not explain the interrupted connection and lock actions"); return false
	if not battle.reconnect_leave_button.is_visible_in_tree():
		_fail("the interrupted connection offered no forfeit action"); return false
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var frame := get_viewport().get_texture().get_image()
		if frame.save_png(screenshot_path) != OK:
			_fail("could not save native short-outage screenshot"); return false
		var panel_rect: Rect2 = battle.turn_wait_hint.get_global_rect()
		var button_rect: Rect2 = battle.reconnect_leave_button.get_global_rect()
		var lines := hint.get_line_count()
		var text_height := lines * hint.get_line_height() + (lines - 1) * hint.get_theme_constant("line_spacing")
		var canvas := get_viewport().get_visible_rect().size
		var pixels_per_unit := minf(frame.get_width() / canvas.x, frame.get_height() / canvas.y)
		if (frame.get_size() != Vector2i(640, 360)
				or hint.get_theme_font_size("font_size") * pixels_per_unit < 9.99
				or battle.reconnect_leave_button.get_theme_font_size("font_size") * pixels_per_unit < 9.99
				or text_height > hint.size.y + 0.5 or not panel_rect.encloses(button_rect)
				or not panel_rect.encloses(hint.get_global_rect()) or hint.get_global_rect().intersects(button_rect)
				or panel_rect.intersects(battle.hand_area.get_global_rect())):
			_fail("compact recovery bounds: frame=%s canvas=%s font=%s button_font=%s panel=%s text=%s button=%s text_height=%d" %
				[frame.get_size(), canvas, hint.get_theme_font_size("font_size"), battle.reconnect_leave_button.get_theme_font_size("font_size"),
				panel_rect, hint.get_global_rect(), button_rect, text_height]); return false
	_press_outage_forfeit(battle.reconnect_leave_button)
	var decision: CanvasLayer = battle.get_node_or_null("AbandonBattleConfirmation")
	if decision == null or not decision.visible or NetworkManager.peer != old_peer:
		_fail("forfeit during recovery did not ask first and preserve the session"); return false
	var cancel: Button
	for button in decision.find_children("*", "Button", true, false):
		if button.text == Locale.t("common.cancel"):
			cancel = button
			break
	if cancel == null or not cancel.has_focus():
		_fail("the forfeit decision did not focus Cancel"); return false
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("outage-forfeit-confirmation.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not save the forfeit decision"); return false
	cancel.pressed.emit()
	if battle.battle_finished or NetworkManager.peer != old_peer or NetworkManager.pending_game_command_count() != 1:
		_fail("cancelling forfeit lost the match or its pending turn"); return false
	while is_instance_valid(decision):
		await get_tree().process_frame
	_press_outage_forfeit(battle.reconnect_leave_button)
	decision = battle.get_node_or_null("AbandonBattleConfirmation")
	if decision == null or not decision.visible or not NetworkManager.room_link_waiting():
		_fail("could not leave the recovery prompt open before the link restored"); return false
	NetworkManager._network_diag("test_short_outage_pause")
	print("DEDICATED_SHORT_OUTAGE_PAUSE_OK")
	var deadline := Time.get_ticks_msec() + 7000
	while NetworkManager.room_link_waiting() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame
	if NetworkManager.room_link_waiting() or battle.has_node("AbandonBattleConfirmation") or UIMotion.top_popup() != null:
		_fail("the recovery-only forfeit prompt remained open after the connection recovered"); return false
	var feed := battle.get_node_or_null("CanvasLayer/ToastStack")
	if feed == null or not feed.find_children("*", "Label", true, false).any(func(label: Label):
		return label.text == Locale.t("battle.room_link_restored")
	):
		_fail("the battle did not explain why the recovery prompt closed"); return false
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.18).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("recovered-forfeit-closed.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the restored battle"); return false
	return true

func _press_outage_forfeit(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = button.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	get_viewport().push_input(click, true)
	click = click.duplicate() as InputEventMouseButton
	click.pressed = false
	get_viewport().push_input(click, true)

func _check_rematch(battle: Node) -> void:
	if not returned or battle.game.current_player != NetworkManager.match_opening_player or NetworkManager.peer != old_peer:
		_fail("rematch did not initialize on the same room"); return
	print("DEDICATED_REMATCH_", role.to_upper(), "_OK")
	var history_size := PlayerData.match_history.size()
	if _tests_prior_match() and not await _check_prior_match_packets(battle):
		return
	var completed_result: Control
	if OS.get_cmdline_user_args().has("--outage-after-results"):
		battle.game.player2_field.player_hp = 0
		if not battle._check_and_show_game_over():
			_fail("match did not reach a completed result before the outage"); return
		completed_result = battle.get_node("CanvasLayer/BattleResultLayer")
		var notice := completed_result.find_child("RoomNotice", true, false) as Label
		if notice == null or notice.visible or battle._online_result_back_btn.text != Locale.t("result.back_room"):
			_fail("completed result did not initially offer to return to the live room"); return
		print("DEDICATED_COMPLETED_RESULT_READY")
	if role == "survivor":
		if _tests_long_outage():
			await _check_host_connection_loss(battle, completed_result)
			return
		while not FileAccess.file_exists(leave_gate + ".rematch"):
			await get_tree().process_frame
		battle._abandon_battle_now()
		if not _check_terminal_history(battle, history_size, "forfeit"):
			return
		await get_tree().scene_changed
		_finish("DEDICATED_HOST_ABANDONED_OK")
		return
	while not battle.battle_finished or not NetworkManager.is_authority():
		await get_tree().process_frame
	var result := battle.get_node_or_null("CanvasLayer/BattleResultLayer")
	if result == null: _fail("opponent left without a result screen"); return
	var history_outcome := "defeat" if completed_result else "interrupted"
	if not _check_terminal_history(battle, history_size, history_outcome):
		return
	if completed_result:
		if not _check_completed_result_notice(battle, completed_result, "result.room_opponent_disconnected", "result.back_room"):
			return
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
				_fail("could not capture the retained completed result"); return
	else:
		var body := result.find_child("BodyLabel", true, false) as Label
		if body == null or body.text != Locale.t("result.opponent_left_body"):
			_fail("disconnect result did not explain that the same room can still be used"); return
		var title := result.find_child("TitleLabel", true, false) as Label
		var title_key := "result.opponent_connection_lost_title" if _tests_long_outage() else "result.opponent_left_title"
		if title == null or title.text != Locale.t(title_key):
			_fail("the retained player's result did not distinguish a disconnect from a voluntary exit"); return
	if _tests_long_outage():
		NetworkManager._network_diag("test_long_outage_result")
	if OS.get_cmdline_user_args().has("--leave-from-results"):
		await _check_result_departure(result)
		return
	for button in result.find_children("*", "Button", true, false):
		if button.text == Locale.t("result.back_room"):
			if _tests_join_during_results():
				print("DEDICATED_RESULT_HELD_FOR_JOIN")
				while not FileAccess.file_exists(leave_gate + ".guest-saw-result"):
					await get_tree().process_frame
			disconnect_checked = true
			button.pressed.emit()
			return
	_fail("disconnect result has no return-to-room button")

func _check_result_departure(result: Control) -> void:
	await get_tree().process_frame
	while result.modulate.a < 1.0:
		await get_tree().process_frame
	var menu: Button
	var room: Button
	for button: Button in result.find_children("*", "Button", true, false):
		if button.text == Locale.t("result.back_menu"):
			menu = button
		elif button.text == Locale.t("result.back_room"):
			room = button
	if menu == null or room == null:
		_fail("retained room result is missing navigation actions"); return
	if DisplayServer.get_name() == "headless":
		menu.pressed.emit()
	else:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = menu.get_global_rect().get_center()
		click.pressed = true
		get_viewport().push_input(click, true)
		click = click.duplicate() as InputEventMouseButton
		click.pressed = false
		get_viewport().push_input(click, true)
	if not NetworkManager.room_departure_pending:
		_fail("leaving the result never requested a room acknowledgement"); return
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	if NetworkManager.peer != old_peer or not NetworkManager.room_departure_pending:
		_fail("Escape interrupted a pending departure and closed the room transport"); return
	if UIMotion.top_popup() != result:
		_fail("Escape dismissed the result during departure"); return
	if not menu.disabled or not room.disabled or menu.text != Locale.t("wait.leaving_room"):
		_fail("result did not lock navigation and show departure progress"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("result-leaving-room.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture departure progress"); return
	await get_tree().scene_changed
	var page := get_tree().current_scene
	if page.scene_file_path != "res://MainMenu.tscn" or page.has_node("OnlineModePopup") or not NetworkManager.room_code.is_empty():
		_fail("leaving the result did not return to the main menu"); return
	_finish("DEDICATED_RESULT_DEPARTURE_OK")

func _check_completed_result_notice(battle: Node, result: Control, notice_key: String, back_key: String) -> bool:
	var notice := result.find_child("RoomNotice", true, false) as Label
	if battle.get_node_or_null("CanvasLayer/BattleResultLayer") != result or not is_instance_valid(notice) or not notice.is_visible_in_tree() or notice.text != Locale.t(notice_key):
		_fail("completed result did not retain the result and explain the room change: " + notice_key); return false
	if battle._online_result_back_btn.text != Locale.t(back_key):
		_fail("completed result did not offer the correct destination: " + back_key); return false
	return true

func _check_terminal_history(battle: Node, previous_size: int, outcome: String) -> bool:
	PlayerData._load_match_history()
	if PlayerData.match_history.size() != previous_size + 1:
		_fail("the terminal outcome did not create exactly one persisted match record: " + outcome); return false
	var entry: Dictionary = PlayerData.match_history.front()
	if entry.get("outcome") != outcome or entry.get("mode") != "online" or int(entry.get("local_player", 0)) != battle.my_player:
		_fail("the saved record did not match the terminal outcome and original player slot: " + outcome); return false
	return true

func _check_host_connection_loss(battle: Node, completed_result: Control) -> void:
	var history_size := PlayerData.match_history.size() - int(completed_result != null)
	if not completed_result:
		await _arm_live_battle_outage(battle)
		if finished: return
	print("DEDICATED_TERMINAL_OUTAGE_ARMED")
	while NetworkManager.peer != null or not battle.battle_finished:
		await get_tree().process_frame
	NetworkManager._network_diag("test_long_outage_result")
	var picker: CanvasLayer = battle.get_node_or_null("OpponentHandPresentation")
	if picker != null and (picker.busy or picker.accepting or picker.dim.visible or not battle._pile_arrivals.is_empty()):
		_fail("terminal connection loss did not release the pending discard presentation"); return
	var result := battle.get_node_or_null("CanvasLayer/BattleResultLayer")
	if result == null or NetworkManager.is_online:
		_fail("the host did not reach a terminal connection-loss result"); return
	var history_outcome := "victory" if completed_result else "interrupted"
	if not _check_terminal_history(battle, history_size, history_outcome):
		return
	if completed_result:
		if not _check_completed_result_notice(battle, completed_result, "result.room_connection_lost_after_match", "result.back_multiplayer"):
			return
	else:
		var body := result.find_child("BodyLabel", true, false) as Label
		if body == null or body.text != Locale.t("result.room_connection_lost_body"):
			_fail("the disconnected host was not told that the match ended"); return
	await _check_connection_loss_return(battle, result)

func _arm_live_battle_outage(battle: Node) -> void:
	var picker: CanvasLayer = battle.get_node_or_null("OpponentHandPresentation")
	if picker != null:
		var hand: Array = battle.game.player2_hand
		if hand.is_empty():
			_fail("the native discard picker has no cards to show"); return
		var cards := [{"card": PlayerData.serialize_card(hand[0]), "index": 0}]
		picker.play({"player": battle._view_player(), "before_count": hand.size(), "cards": cards})
		while not picker.accepting:
			await get_tree().process_frame
	battle._show_abandon_confirmation()
	var menu := preload("res://presentation/BattlePause.gd").new()
	menu.battle = battle
	battle.add_child(menu)
	menu._settings()

func _check_connection_loss_return(battle: Node, result: Control) -> void:
	await get_tree().create_timer(0.35).timeout
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not capture the terminal result"); return
	for popup in get_tree().get_nodes_in_group("battle_modal"):
		if battle.is_ancestor_of(popup) and popup.visible:
			_fail("a battle popup still covers the terminal connection-loss result"); return
	if UIMotion.top_popup() != result or battle.turn_wait_hint.visible:
		_fail("the terminal result did not replace the pause menu and recovery status"); return
	for button in result.find_children("*", "Button", true, false):
		if button.text == Locale.t("result.back_multiplayer"):
			if not screenshot_path.is_empty():
				if not button.has_focus():
					_fail("the result did not focus its primary action"); return
				var mouse := InputEventMouseMotion.new()
				mouse.position = button.get_global_rect().get_center()
				get_viewport().push_input(mouse, true)
				if get_viewport().gui_get_hovered_control() != button:
					_fail("the in-battle discard picker still blocks the result button"); return
			var escape := InputEventAction.new()
			escape.action = "ui_cancel"
			escape.pressed = true
			Input.parse_input_event(escape)
			await get_tree().scene_changed
			await get_tree().process_frame
			var page := get_tree().current_scene
			if page.get_node_or_null("OnlineModePopup") == null or not NetworkManager.room_code.is_empty():
				_fail("the disconnected host could not return to the connection choices"); return
			var server_entry: Button
			for action in page.get_node("OnlineModePopup").find_children("*", "Button", true, false):
				if action.text == Locale.t("mp.dedicated"):
					server_entry = action
					break
			if server_entry == null:
				_fail("the connection choices did not offer the server room form"); return
			checking_disconnected_entry = true
			server_entry.pressed.emit()
			await get_tree().scene_changed
			await get_tree().process_frame
			var entry := get_tree().current_scene
			if entry.scene_file_path != "res://DedicatedLobby.tscn":
				_fail("reopening server rooms did not show the server room form"); return
			if entry.room_input.text != code or entry.server_input.text != address or not entry.room_input.has_focus() or NetworkManager.is_online:
				_fail("restored room form: code=%s address=%s focused=%s online=%s" % [
					entry.room_input.text == code, entry.server_input.text == address, entry.room_input.has_focus(), NetworkManager.is_online]); return
			if not screenshot_path.is_empty():
				await get_tree().create_timer(0.3).timeout
				await RenderingServer.frame_post_draw
				var evidence := screenshot_path.get_base_dir().path_join("room-entry-after-connection-loss.png")
				if get_viewport().get_texture().get_image().save_png(evidence) != OK:
					_fail("could not capture the restored room form"); return
			_finish("DEDICATED_DROPPED_BACK_TO_MULTIPLAYER_OK")
			return
	_fail("the disconnected host has no return-to-multiplayer button")

func _check_prior_match_packets(battle: Node) -> bool:
	if prior_match_id.is_empty() or NetworkManager.battle_match_id.is_empty() or prior_match_id == NetworkManager.battle_match_id:
		_fail("the rematch did not receive a fresh match identifier"); return false
	var opener: int = battle.game.starting_player
	if role == "survivor" and opener == 1:
		while not battle.is_my_turn() or battle.end_turn_button.disabled:
			await get_tree().process_frame
		battle._on_end_turn_pressed()
	while battle.game.current_player != 2:
		await get_tree().process_frame
	var revision: int = battle.game.state_revision
	var state_hash: String = battle._web_turn_hash()
	var delivered := [false]
	var watch_intent := func(_kind, _payload, _player, _id, _revision): delivered[0] = true
	var watch_state := func(state: Dictionary):
		if int(state.get("state_revision", -1)) > revision: delivered[0] = true
	if role == "survivor":
		EventBus.rpc_game_intent_received.connect(watch_intent)
	else:
		EventBus.rpc_authority_state_received.connect(watch_state)
	print("DEDICATED_PRIOR_MATCH_READY_", role.to_upper())
	while not FileAccess.file_exists(leave_gate + ".prior-match"):
		await get_tree().process_frame
	if role == "survivor":
		NetworkManager.rpc_authority_state.rpc(prior_match_id, preload("res://BattleSnapshotWire.gd").encode(prior_snapshot), "", "snapshot")
	else:
		NetworkManager.rpc_game_intent.rpc(prior_turn.match_id, prior_turn.command_id, prior_turn.expected_revision, prior_turn.player, prior_turn.kind, prior_turn.payload)
	await get_tree().create_timer(0.8).timeout
	if role == "survivor":
		EventBus.rpc_game_intent_received.disconnect(watch_intent)
	else:
		EventBus.rpc_authority_state_received.disconnect(watch_state)
	if delivered[0] or battle.game.state_revision != revision or battle._web_turn_hash() != state_hash:
		_fail("an old match message entered the live rematch"); return false
	print("DEDICATED_PRIOR_MATCH_IGNORED_", role.to_upper())
	while not FileAccess.file_exists(leave_gate + ".prior-match-checked"):
		await get_tree().process_frame
	if role == "replacement" or opener == 2:
		while not battle.is_my_turn() or battle.end_turn_button.disabled:
			await get_tree().process_frame
		battle._on_end_turn_pressed()
	while battle.game.current_player != opener or battle.game.turn_number != 2 or NetworkManager.pending_game_command_count() > 0:
		await get_tree().process_frame
	print("DEDICATED_PRIOR_MATCH_FRESH_TURN_", role.to_upper(), " ", battle._web_turn_hash())
	return true

func _check_start_timeout_action() -> void:
	await get_tree().create_timer(0.14).timeout
	if not lobby.start_btn.disabled or lobby.waiting_ui.status.text != Locale.t("wait.starting_match"):
		_fail("the room offered timeout recovery before giving the match time to start"); return
	var deadline := Time.get_ticks_msec() + 12000
	while lobby.start_btn.text != Locale.t("wait.back_to_preparation") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if lobby.start_btn.disabled or lobby.start_btn.text != Locale.t("wait.back_to_preparation") or lobby.waiting_ui.status.text != Locale.t("wait.start_timeout"):
		_fail("both players confirmed but no recovery action appeared when the match failed to start"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-start-timeout.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture start timeout recovery"); return
	print("DEDICATED_START_TIMEOUT_ACTION")
	if _start_timeout_race == "start-first":
		while not FileAccess.file_exists(leave_gate + ".submit-timeout-reset"):
			await get_tree().process_frame
	lobby.start_btn.pressed.emit()
	if not lobby.cancelling_preparation:
		_fail("the guest could not request a return to preparation"); return
	print("DEDICATED_TIMEOUT_RESET_REQUESTED")
	if _start_timeout_race == "start-first":
		await get_tree().create_timer(0.14).timeout
		if lobby.waiting_ui.status.text != Locale.t("wait.returning_to_preparation") or lobby.start_btn.text != Locale.t("wait.back_to_preparation") or not lobby.start_btn.disabled:
			_fail("the room did not keep the pending return to preparation visible and locked"); return
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			var evidence := screenshot_path.get_base_dir().path_join("room-start-timeout-pending.png")
			if get_viewport().get_texture().get_image().save_png(evidence) != OK:
				_fail("could not capture the pending return"); return

func _check_late_start_after_reset(dialog: ConfirmationDialog) -> void:
	var new_generation := NetworkManager.room_preparation_generation
	var new_offer: String = lobby.match_agreement.offer.get("id", "")
	if new_generation == _held_start_generation or new_offer == _held_start_id:
		_fail("returning to preparation reused the expired confirmation"); return
	var sent := NetworkManager.rpc_id(1, "rpc_room_control", "start", [_held_start_id], _held_start_generation)
	if sent != OK:
		_fail("could not deliver the expired start request"); return
	await get_tree().create_timer(0.75).timeout
	if not NetworkManager.room_preparation_available or lobby.match_agreement.offer.get("id", "") != new_offer or not is_instance_valid(dialog) or not dialog.visible:
		_fail("the expired start affected the new preparation"); return
	var gate := FileAccess.open(leave_gate + ".late-start-checked", FileAccess.WRITE)
	gate.close()
	print("DEDICATED_LATE_START_IGNORED")

func _inject_offer_deck_mismatch(data: Dictionary) -> void:
	if not checked_cancellation or _offer_mismatch_injected or data.get("room_preview", false):
		return
	_offer_mismatch_injected = true
	data["p1"] = "0".repeat(64)
	print("DEDICATED_MISMATCH_INJECTED")

func _check_offer_mismatch_recovery() -> void:
	await get_tree().process_frame
	var panel: Control = lobby.waiting_ui
	panel._update_state()
	if lobby.i_am_ready or lobby.opponent_ready or lobby.match_agreement.pending or lobby.start_btn.disabled:
		_fail("deck mismatch left the room locked in preparation"); return
	if panel.status.text != Locale.t("wait.offer_mismatch") or NetworkManager.peer != old_peer:
		_fail("deck mismatch recovery did not explain the reset in the same room"); return
	if role == "replacement" and not screenshot_path.is_empty():
		if not lobby.start_btn.has_focus():
			_fail("deck mismatch recovery did not focus Ready"); return
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("room-offer-mismatch.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the preparation reset"); return
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		get_viewport().push_input(enter, true)
		enter.pressed = false
		get_viewport().push_input(enter, true)
		if not lobby.i_am_ready:
			_fail("Enter could not ready the guest after the mismatched confirmation"); return
		submitted = true
	set_meta("mismatch_checked", true)
	print("DEDICATED_MISMATCH_RECOVERED_", role.to_upper())

func _trace_match_preparation(room: Control) -> void:
	var agreement: MatchAgreement = room.match_agreement
	var state := JSON.stringify({
		"generation": NetworkManager.room_preparation_generation,
		"local_ready": room.i_am_ready,
		"remote_ready": room.opponent_ready,
		"offer_pending": agreement.pending,
		"offer": agreement.offer.get("id", ""),
		"local_confirmed": agreement.local_accepted,
		"remote_confirmed": agreement.remote_accepted,
		"link_waiting": NetworkManager.room_link_waiting(),
		"submitted": submitted,
		"confirmed": confirmed,
	})
	if state != _last_preparation_trace:
		_last_preparation_trace = state
		print("[PREPARATION_TEST] ", state)

func _capture_after_return() -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
		_fail("could not save waiting room screenshot")

func _finish(marker: String) -> void:
	finished = true
	print(marker)
	NetworkManager.close_connection()
	get_tree().quit(0)

func _fail(message: String) -> void:
	finished = true
	push_error("DEDICATED_FAILED: " + role + ": " + message)
	NetworkManager.close_connection()
	get_tree().quit(1)

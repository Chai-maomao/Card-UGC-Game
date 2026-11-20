extends "res://DirectLobby.gd"

var _room_request_running := false

func _relay_url() -> String:
	return BetaRelayConfig.server_url()

func _relay_error(error: String) -> String:
	return BetaRelayConfig.error_text(error)

func _connect_relay_room(address: String, code: String, token: String, player: int) -> bool:
	NetworkManager.connect_beta_room(address, code, token, player)
	return NetworkManager.has_saved_beta_session()

func _uses_lan_discovery() -> bool:
	return false

func _apply_texts() -> void:
	super._apply_texts()
	title_label.text = Locale.t("beta.entry")
	host_btn.text = Locale.t("beta.create")
	join_btn.text = Locale.t("beta.join")
	ip_label.text = Locale.t("beta.room_code")
	ip_input.placeholder_text = "A1B2C3D4"
	ip_input.max_length = 8
	for control in [discovery_label, room_list, refresh_btn]:
		control.hide()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _on_host_pressed() -> void:
	_open_room("")

func _on_join_pressed() -> void:
	var code: String = ip_input.text.strip_edges().to_upper()
	if not BetaRelayConfig.valid_code(code):
		status_label.text = Locale.t("beta.invalid_code")
		return
	_open_room(code)

func _open_room(code: String) -> void:
	if _room_request_running:
		return
	var address := _relay_url()
	if address.is_empty():
		status_label.text = _relay_error("not_configured")
		return
	_room_request_running = true
	host_btn.disabled = true
	join_btn.disabled = true
	back_btn.disabled = true
	status_label.text = Locale.t("beta.connecting")
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.body_size_limit = 16384
	add_child(http)
	var path := "/api/rooms" if code.is_empty() else "/api/rooms/" + code + "/join"
	var result := http.request(address + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"protocol": BetaRelayConfig.PROTOCOL}))
	var error := "unavailable"
	if result == OK:
		var response: Array = await http.request_completed
		if not is_inside_tree():
			return
		var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
		if response[0] == HTTPRequest.RESULT_SUCCESS and data is Dictionary:
			if response[1] in [200, 201] and BetaRelayConfig.valid_code(str(data.get("code", ""))) and str(data.get("token", "")).length() == 64 and int(data.get("player", 0)) in [1, 2]:
				if not _connect_relay_room(address, str(data["code"]), str(data["token"]), int(data["player"])):
					http.queue_free()
					_room_request_running = false
					back_btn.disabled = false
					_on_game_connection_failed()
					return
				http.queue_free()
				_room_request_running = false
				back_btn.disabled = false
				_show_waiting_room(Locale.t("beta.waiting", [NetworkManager.room_code]))
				return
			error = str(data.get("error", "unavailable"))
		elif response[0] == HTTPRequest.RESULT_SUCCESS and response[1] in [200, 301, 302, 401, 403]:
			error = "private_site"
	http.queue_free()
	_room_request_running = false
	host_btn.disabled = false
	join_btn.disabled = false
	back_btn.disabled = false
	status_label.text = _relay_error(error)

func _show_waiting_room(initial_message: String = "") -> void:
	super._show_waiting_room(initial_message)
	var copy := Button.new()
	copy.name = "CopyBetaRoomButton"
	copy.text = Locale.t("beta.copy_code", [NetworkManager.room_code])
	copy.anchor_top = 0.9
	copy.anchor_bottom = 0.97
	copy.anchor_left = 0.03
	copy.anchor_right = 0.42
	UITheme.apply_button(copy, "secondary")
	copy.pressed.connect(func(): DisplayServer.clipboard_set(NetworkManager.room_code))
	waiting_ui.add_child(copy)

func _on_game_connection_failed() -> void:
	var reason: String = NetworkManager._last_disconnect_reason
	super._on_game_connection_failed()
	status_label.text = _relay_error(reason)

func _on_back_pressed() -> void:
	if not is_instance_valid(waiting_ui):
		NetworkManager.leave_beta_room()
	super._on_back_pressed()

func _exit_waiting_room() -> void:
	NetworkManager.leave_beta_room()
	super._exit_waiting_room()

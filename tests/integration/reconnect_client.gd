extends Node

var _role: int = 1
var _room_code: String = ""
var _elapsed: float = 0.0
var _room_ready_count: int = 0
var _disconnect_started: bool = false
var _reconnect_transport_received: bool = false
var _server_snapshot_received: bool = false
var _command_sent: bool = false
var _command_acked: bool = false
var _command_received: bool = false
var _authority_command_count: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = int(arg.get_slice("=", 1))
		elif arg.begins_with("--code="):
			_room_code = arg.get_slice("=", 1)
	if _room_code.is_empty():
		_fail("missing room code")
		return
	if not NetworkManager.use_isolated_session_storage("%s-p%d" % [_room_code, _role]):
		_fail("could not isolate integration session storage")
		return
	NetworkManager.lobby_connected.connect(_on_lobby_connected)
	NetworkManager.connected.connect(_on_room_ready)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_ready)
	NetworkManager.server_match_snapshot_received.connect(_on_server_snapshot)
	EventBus.rpc_authority_state_received.connect(_on_authority_state)
	EventBus.rpc_game_intent_received.connect(_on_game_intent)
	NetworkManager.reconnect_failed.connect(func(reason: String): _fail("reconnect failed: %s" % reason))
	NetworkManager.game_command_status.connect(_on_game_command_status)
	var error := NetworkManager.connect_to_lobby("127.0.0.1", Callable(self, "_on_lobby_response"))
	if error != OK:
		_fail("lobby connect error %d" % error)


func _process(delta: float) -> void:
	_elapsed += delta
	if _role == 2 and _room_ready_count >= 1 and _command_acked and not _disconnect_started and _elapsed >= 4.0:
		_disconnect_started = true
		NetworkManager.mark_room_match_started()
		NetworkManager.close_connection()
		if not NetworkManager.begin_saved_match_reconnect():
			_fail("saved reconnect did not start")
	if _elapsed >= 25.0:
		_fail("integration timeout")


func _on_lobby_connected() -> void:
	if _role == 1:
		NetworkManager.create_room(_room_code)
	else:
		NetworkManager.join_room(_room_code)


func _on_lobby_response(data: Dictionary) -> void:
	if str(data.get("status", "")) != "ok":
		_fail("lobby response: %s" % JSON.stringify(data))
		return
	var port := int(data.get("port", 0))
	var assigned := int(data.get("player", 0))
	var token := str(data.get("reconnect_token", ""))
	var error := NetworkManager.connect_to_game_room("127.0.0.1", port, assigned, _room_code, token)
	if error != OK:
		_fail("room connect error %d" % error)


func _on_room_ready() -> void:
	_room_ready_count += 1
	NetworkManager.mark_room_match_started()
	if _role == 1 and _room_ready_count == 1:
		NetworkManager.broadcast_authority_state({
			"player_field": {}, "player2_field": {},
			"player_hand": [], "player2_hand": [], "shared_deck": [],
			"state_revision": 42,
		})
	if _role == 1 and _room_ready_count >= 2:
		print("TEST_RECONNECT_SURVIVOR_OK")
		NetworkManager.clear_room_session()
		get_tree().quit(0)


func _on_reconnect_ready() -> void:
	if _role != 2:
		return
	_reconnect_transport_received = true
	_maybe_finish_reconnect_test()


func _on_authority_state(state: Dictionary) -> void:
	if _role != 2 or _disconnect_started:
		return
	var revision := int(state.get("state_revision", -1))
	if revision == 42 and not _command_sent:
		_command_sent = true
		NetworkManager.send_game_intent("end_turn", {}, 2, 42)
	elif revision == 43:
		if not _command_received:
			_fail("authority snapshot arrived before command receipt")
			return
		if NetworkManager.pending_game_command_count() != 0:
			_fail("authority state arrived without command ack")
			return
		_command_acked = true
		print("TEST_COMMAND_ACK_OK")


func _on_game_command_status(_command_id: String, kind: String, status: String, _latency_ms: int) -> void:
	if _role == 2 and kind == "end_turn" and status == "received" and not _command_received:
		_command_received = true
		print("TEST_COMMAND_RECEIPT_OK")


func _on_game_intent(kind: String, _payload: Dictionary, player: int, command_id: String, expected_revision: int) -> void:
	if _role != 1:
		return
	_authority_command_count += 1
	if _authority_command_count != 1 or kind != "end_turn" or player != 2 or expected_revision != 42:
		_fail("invalid or duplicate command envelope")
		return
	# Delay beyond the old ACK timeout. The lightweight receipt should keep P2
	# responsive without resending while the full authority snapshot is prepared.
	await get_tree().create_timer(1.6).timeout
	NetworkManager.set_next_authority_ack(command_id, "applied")
	NetworkManager.broadcast_authority_state({
		"player_field": {}, "player2_field": {},
		"player_hand": [], "player2_hand": [], "shared_deck": [],
		"state_revision": 43,
	})


func _on_server_snapshot(state: Dictionary) -> void:
	if _role != 2:
		return
	if int(state.get("state_revision", -1)) != 43:
		_fail("unexpected server snapshot revision")
		return
	_server_snapshot_received = true
	_maybe_finish_reconnect_test()


func _maybe_finish_reconnect_test() -> void:
	if not _reconnect_transport_received or not _server_snapshot_received:
		return
	print("TEST_RECONNECT_TRANSPORT_OK")
	NetworkManager.clear_room_session()
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("TEST_RECONNECT_INTEGRATION_FAILED: %s" % message)
	NetworkManager.clear_room_session()
	get_tree().quit(1)

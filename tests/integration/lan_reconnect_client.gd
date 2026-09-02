extends Node

var _role: int = 0
var _phase: String = ""
var _prefix: String = ""
var _port: int = NetworkManager.LAN_GAME_PORT
var _done: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = int(arg.get_slice("=", 1))
		elif arg.begins_with("--phase="):
			_phase = arg.get_slice("=", 1)
		elif arg.begins_with("--prefix="):
			_prefix = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
	if _role not in [1, 2] or _phase not in ["live", "seed", "resume"] or _prefix == "":
		_fail("invalid arguments")
		return
	if not NetworkManager.use_isolated_session_storage("%s-p%d" % [_prefix, _role]):
		_fail("isolated storage unavailable")
		return
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_ready)
	NetworkManager.reconnect_failed.connect(func(reason: String): _fail("reconnect failed: %s" % reason))
	get_tree().create_timer(20.0).timeout.connect(func(): _fail("timeout"))
	if _phase in ["live", "seed"]:
		NetworkManager.clear_room_session()
		var err := NetworkManager.host_game(_port) if _role == 1 else NetworkManager.join_game("127.0.0.1", _port)
		if err != OK:
			_fail("seed transport error %d" % err)
	else:
		if not NetworkManager.has_resumable_match_session():
			_fail("persisted session missing")
			return
		if not NetworkManager.begin_saved_match_reconnect():
			_fail("resume did not start")


func _on_connected() -> void:
	if _phase not in ["live", "seed"] or _done:
		return
	NetworkManager.mark_match_started()
	if not NetworkManager.save_match_snapshot(_state(41 + _role)):
		_fail("snapshot save failed")
		return
	if _phase == "live":
		if _role == 2:
			await get_tree().create_timer(0.5).timeout
			NetworkManager._on_opponent_vanished()
		return
	_done = true
	print("TEST_LAN_SESSION_SEEDED_P%d" % _role)
	await get_tree().create_timer(0.35).timeout
	NetworkManager.close_connection()
	get_tree().quit(0)


func _on_reconnect_ready() -> void:
	if _phase not in ["live", "resume"] or _done:
		return
	var restored := NetworkManager.load_match_snapshot()
	if int(restored.get("state_revision", -1)) != 41 + _role:
		_fail("snapshot revision mismatch")
		return
	_done = true
	if _phase == "live":
		print("TEST_LAN_LIVE_RECONNECT_OK_P%d" % _role)
	else:
		print("TEST_LAN_PROCESS_RESTART_RESUME_OK_P%d" % _role)
	# Keep the transport alive briefly so the other process can receive and
	# validate its protocol hello before either endpoint exits the test.
	await get_tree().create_timer(0.75).timeout
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	get_tree().quit(0)


func _state(revision: int) -> Dictionary:
	return {
		"player_field": {},
		"player2_field": {},
		"player_hand": [],
		"player2_hand": [],
		"shared_deck": [],
		"shared_discard": [],
		"state_revision": revision,
	}


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("TEST_LAN_RECONNECT_FAILED_P%d: %s" % [_role, message])
	NetworkManager.close_connection()
	get_tree().quit(1)

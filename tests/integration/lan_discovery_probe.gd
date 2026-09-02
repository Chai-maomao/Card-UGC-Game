extends Node

var _role := ""
var _port := NetworkManager.LAN_GAME_PORT
var _done := false


func _ready() -> void:
	var prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--prefix="):
			prefix = arg.get_slice("=", 1)
	if prefix == "" or not NetworkManager.use_isolated_session_storage("%s-%s" % [prefix, _role]):
		_fail("invalid storage prefix")
		return
	NetworkManager.clear_room_session()
	if _role == "host":
		if NetworkManager.host_game(_port) != OK:
			_fail("host failed")
			return
		print("TEST_LAN_DISCOVERY_HOST_READY")
		get_tree().create_timer(4.0).timeout.connect(_finish_host)
	elif _role == "client":
		NetworkManager.lan_rooms_updated.connect(_on_rooms)
		if NetworkManager.start_lan_room_discovery() != OK:
			_fail("scanner failed")
			return
		get_tree().create_timer(4.0).timeout.connect(func(): _fail("room not discovered"))
	else:
		_fail("invalid role")


func _on_rooms(rooms: Array) -> void:
	for room in rooms:
		if int(room.get("port", 0)) == _port:
			_done = true
			print("TEST_LAN_DISCOVERY_FOUND")
			NetworkManager.close_connection()
			NetworkManager.clear_room_session()
			get_tree().quit(0)
			return


func _finish_host() -> void:
	if _done:
		return
	_done = true
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	get_tree().quit(0)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("TEST_LAN_DISCOVERY_FAILED: %s" % message)
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	get_tree().quit(1)

extends Node

# ============================================
# Room server subprocess — pure ENet relay for one room.
# Spawned by server.gd via OS.create_process. Listens on a single port,
# accepts up to 2 player clients, and relies on Godot's default
# server-relay so the two clients' broadcast RPCs reach each other.
#
# Command line:
#   godot --headless room_server.tscn -- --room-port=5001 --room-code=1234 \
#     --p1-token=<token> --p2-token=<token>
# ============================================

const DEFAULT_ROOM_PORT := 5001
const CREATED_TIMEOUT := 60.0
const WAITING_OPPONENT_TIMEOUT := 60.0 * 60.0
const RECONNECT_TIMEOUT := 60.0 * 60.0
const EMPTY_SHUTDOWN_DELAY := 60.0
const AUTH_TIMEOUT := 10.0

enum RoomState {
	CREATED,
	WAITING,
	PLAYING,
	RECONNECTING,
	EMPTY,
}

var room_port: int = DEFAULT_ROOM_PORT
var room_code: String = ""
var p1_token: String = ""
var p2_token: String = ""

var peer: ENetMultiplayerPeer
var player_count: int = 0
var had_full_room: bool = false
var room_state: int = RoomState.CREATED
var _state_deadline: float = -1.0
var _shutting_down: bool = false
var _auth_deadlines: Dictionary = {}
var _peer_to_player: Dictionary = {}
var _player_to_peer: Dictionary = {}


func _ready() -> void:
	_parse_args()
	if not _start():
		push_error("[ROOM %s] Failed to bind port %d — exiting" % [room_code, room_port])
		get_tree().quit(1)
		return
	_enter_state(RoomState.CREATED, CREATED_TIMEOUT)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	var now := _now()
	for peer_id in _auth_deadlines.keys():
		if now >= float(_auth_deadlines[peer_id]):
			print("[ROOM %s] Peer %d authentication timed out" % [room_code, int(peer_id)])
			_auth_deadlines.erase(peer_id)
			peer.disconnect_peer(int(peer_id), true)
	if _shutting_down or _state_deadline <= 0.0:
		return
	if now < _state_deadline:
		return
	_shutting_down = true
	print("[ROOM %s] %s timed out — shutting down" % [room_code, _state_name(room_state)])
	get_tree().quit(0)


func _enter_state(next_state: int, timeout: float = -1.0) -> void:
	room_state = next_state
	_state_deadline = _now() + timeout if timeout > 0.0 else -1.0
	if timeout > 0.0:
		print("[ROOM %s] State: %s (timeout %.0fs)" % [room_code, _state_name(room_state), timeout])
	else:
		print("[ROOM %s] State: %s (no timeout)" % [room_code, _state_name(room_state)])


func _state_name(state: int) -> String:
	match state:
		RoomState.CREATED:
			return "created"
		RoomState.WAITING:
			return "waiting_for_opponent"
		RoomState.PLAYING:
			return "playing"
		RoomState.RECONNECTING:
			return "waiting_for_reconnect"
		RoomState.EMPTY:
			return "empty"
	return "unknown"


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-port="):
			room_port = int(arg.split("=")[1])
		elif arg.begins_with("--room-code="):
			room_code = arg.split("=")[1]
		elif arg.begins_with("--p1-token="):
			p1_token = arg.split("=")[1]
		elif arg.begins_with("--p2-token="):
			p2_token = arg.split("=")[1]


func _start() -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(room_port, 2)
	if err != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.room_auth_handler = Callable(self, "_handle_room_auth")
	print("[ROOM %s] Relay listening on port %d" % [room_code, room_port])
	return true


func _on_peer_connected(id: int) -> void:
	_auth_deadlines[id] = _now() + AUTH_TIMEOUT
	print("[ROOM %s] Peer %d connected; awaiting authentication" % [room_code, id])


func _handle_room_auth(sender_id: int, requested_code: String, requested_player: int, token: String) -> void:
	var expected_token := ""
	if requested_player == 1:
		expected_token = p1_token
	elif requested_player == 2:
		expected_token = p2_token
	if requested_code != room_code or expected_token == "" or token != expected_token:
		NetworkManager.send_room_auth_result(sender_id, false, requested_player, "invalid_token", false)
		print("[ROOM %s] Peer %d failed authentication" % [room_code, sender_id])
		call_deferred("_disconnect_rejected_peer", sender_id)
		return
	if _peer_to_player.has(sender_id):
		var existing_player := int(_peer_to_player[sender_id])
		if existing_player == requested_player:
			NetworkManager.send_room_auth_result(sender_id, true, requested_player, "", had_full_room)
		else:
			NetworkManager.send_room_auth_result(sender_id, false, requested_player, "already_authenticated", false)
			call_deferred("_disconnect_rejected_peer", sender_id)
		return
	if _player_to_peer.has(requested_player) and int(_player_to_peer[requested_player]) != sender_id:
		NetworkManager.send_room_auth_result(sender_id, false, requested_player, "slot_in_use", false)
		print("[ROOM %s] P%d slot is already connected" % [room_code, requested_player])
		call_deferred("_disconnect_rejected_peer", sender_id)
		return

	var was_reconnect := had_full_room
	_auth_deadlines.erase(sender_id)
	_peer_to_player[sender_id] = requested_player
	_player_to_peer[requested_player] = sender_id
	player_count = _peer_to_player.size()
	NetworkManager.send_room_auth_result(sender_id, true, requested_player, "", was_reconnect)
	print("[ROOM %s] Peer %d authenticated as P%d (%d/2)" % [room_code, sender_id, requested_player, player_count])
	_update_lifecycle_after_player_change()
	if player_count >= 2:
		# Tell both clients the room is full so they can show "opponent connected".
		NetworkManager.notify_room_ready.rpc()
		print("[ROOM %s] Room full — notified clients" % room_code)


func _disconnect_rejected_peer(peer_id: int) -> void:
	if peer:
		peer.disconnect_peer(peer_id)


func _on_peer_disconnected(id: int) -> void:
	_auth_deadlines.erase(id)
	if not _peer_to_player.has(id):
		print("[ROOM %s] Unauthenticated peer %d disconnected" % [room_code, id])
		return
	var disconnected_player := int(_peer_to_player[id])
	_peer_to_player.erase(id)
	_player_to_peer.erase(disconnected_player)
	player_count = _peer_to_player.size()
	print("[ROOM %s] P%d peer %d disconnected (%d/2)" % [room_code, disconnected_player, id, player_count])
	_update_lifecycle_after_player_change()
	if player_count > 0:
		NetworkManager.notify_player_disconnected.rpc(disconnected_player)


func _update_lifecycle_after_player_change() -> void:
	if player_count >= 2:
		had_full_room = true
		_enter_state(RoomState.PLAYING)
	elif player_count == 1 and had_full_room:
		_enter_state(RoomState.RECONNECTING, RECONNECT_TIMEOUT)
	elif player_count == 1:
		_enter_state(RoomState.WAITING, WAITING_OPPONENT_TIMEOUT)
	else:
		_shutdown_if_empty()


func _shutdown_if_empty() -> void:
	_enter_state(RoomState.EMPTY, EMPTY_SHUTDOWN_DELAY)

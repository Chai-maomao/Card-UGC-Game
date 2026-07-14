extends Node

# ============================================
# Network manager — ENet P2P RPC layer
# ============================================

signal connected()
signal game_started()
signal lobby_connected()
signal lobby_connection_failed()
signal game_connection_failed()
signal opponent_disconnected()

const LOBBY_PORT := 4567
const CONNECT_TIMEOUT := 8.0  # seconds before a pending connection is treated as failed
const HEARTBEAT_INTERVAL := 2.0  # seconds between heartbeat sends
const HEARTBEAT_TIMEOUT := 7.0  # seconds without receiving heartbeat before declaring disconnect

var peer: ENetMultiplayerPeer
var is_host: bool = false
var is_online: bool = false
var opponent_peer_id: int = 0
var player_number: int = 0
var is_dedicated_server: bool = false
var _last_heartbeat_sent: float = 0.0
var _last_heartbeat_received: float = 0.0
var _heartbeat_active: bool = false
# Set from the lobby response in relay mode: whether the server permits card-art
# transfer. Direct P2P ignores this (always allowed).
var server_allows_card_art: bool = false

var last_game_address: String = ""
var last_game_port: int = 0
var last_game_player_number: int = 0

# Lobby connection (for room-code server)
var _lobby_peer: ENetMultiplayerPeer
var _lobby_callback: Callable
var _lobby_status_callback: Callable

# Server-side: server.gd registers this so lobby_request RPCs (which always land on
# the shared NetworkManager autoload node) get forwarded to the real handler.
var lobby_request_handler: Callable

# Pending-connection timeout tracking (deadlines in seconds; <= 0 means inactive)
var _lobby_deadline: float = 0.0
var _game_deadline: float = 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	if _lobby_deadline > 0.0 and _now() > _lobby_deadline:
		_lobby_deadline = 0.0
		_fail_lobby_connection()
	if _game_deadline > 0.0 and _now() > _game_deadline:
		_game_deadline = 0.0
		_fail_game_connection()
	# Application-level heartbeat: send periodically and detect timeout
	if _heartbeat_active and is_online and opponent_peer_id > 0:
		var t: float = _now()
		if t - _last_heartbeat_sent >= HEARTBEAT_INTERVAL:
			_last_heartbeat_sent = t
			_send_heartbeat()
		# Check for timeout (only after we've been connected long enough to receive one)
		if _last_heartbeat_received > 0.0 and t - _last_heartbeat_received > HEARTBEAT_TIMEOUT:
			print("[Heartbeat] No heartbeat from opponent for %.1fs — declaring disconnect" % (t - _last_heartbeat_received))
			_on_opponent_vanished()


# ============================================
# Validation helpers
# ============================================

static func is_valid_room_code(code: String) -> bool:
	if code.length() < 1 or code.length() > 16:
		return false
	for c in code:
		# allow alphanumeric only — keeps codes safe to print/store and avoids whitespace pitfalls
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")):
			return false
	return true


static func is_valid_address(address: String) -> bool:
	return address.strip_edges() != ""


func is_authority() -> bool:
	if not is_online:
		return true  # hotseat: always authority
	if is_dedicated_server:
		return player_number == 1
	return is_host


# ============================================
# Direct host / join (classic P2P, kept for hotseat & LAN)
# ============================================

func host_game(port: int = 4568) -> int:
	close_connection()
	is_dedicated_server = false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 1)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_online = true
	player_number = 1
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	print("Hosting on port %d" % port)
	return OK


func join_game(address: String, port: int = 4568) -> int:
	close_connection()
	if not is_valid_address(address):
		return ERR_INVALID_PARAMETER
	is_dedicated_server = false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_online = true
	player_number = 2
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	_game_deadline = _now() + CONNECT_TIMEOUT
	print("Joining %s:%d" % [address, port])
	return OK


# ============================================
# Room-code lobby (connects to dedicated server)
# ============================================

func connect_to_lobby(server_ip: String, callback: Callable) -> int:
	disconnect_from_lobby()
	if not is_valid_address(server_ip):
		return ERR_INVALID_PARAMETER
	is_dedicated_server = true
	is_host = false
	_lobby_callback = callback
	_lobby_peer = ENetMultiplayerPeer.new()
	var err = _lobby_peer.create_client(server_ip, LOBBY_PORT)
	if err != OK:
		_lobby_peer = null
		return err
	multiplayer.multiplayer_peer = _lobby_peer
	is_online = true
	_lobby_peer.peer_connected.connect(_on_lobby_connected)
	_lobby_peer.peer_disconnected.connect(_on_lobby_disconnected)
	_lobby_deadline = _now() + CONNECT_TIMEOUT
	print("Connecting to lobby at %s:%d" % [server_ip, LOBBY_PORT])
	return OK


func create_room(code: String) -> void:
	if not is_valid_room_code(code):
		push_warning("create_room called with invalid room code")
		return
	_lobby_request({"action": "create", "code": code})


func join_room(code: String) -> void:
	if not is_valid_room_code(code):
		push_warning("join_room called with invalid room code")
		return
	_lobby_request({"action": "join", "code": code})


func request_lobby_status(callback: Callable) -> void:
	_lobby_status_callback = callback
	_lobby_request({"action": "status"})


func _lobby_request(data: Dictionary) -> void:
	rpc_id(1, "lobby_request", JSON.stringify(data))


@rpc("any_peer", "call_remote")
func lobby_request(json_str: String) -> void:
	# Runs on the dedicated server. The RPC always lands here (shared autoload node),
	# so forward it to server.gd's handler if one is registered.
	if lobby_request_handler.is_valid():
		lobby_request_handler.call(multiplayer.get_remote_sender_id(), json_str)


func send_lobby_response(peer_id: int, json_str: String) -> void:
	# Server-side helper: reply to a specific client through the shared node.
	rpc_id(peer_id, "lobby_response", json_str)


@rpc("authority", "call_remote")
func notify_room_ready() -> void:
	# Broadcast by the room subprocess (peer 1) once both players are connected.
	# Drives the same "opponent connected" path used by direct P2P.
	if opponent_peer_id <= 0:
		opponent_peer_id = 1  # relay mode: server (peer 1) is the relay target
	_heartbeat_active = true
	_last_heartbeat_sent = _now()
	_last_heartbeat_received = _now() + HEARTBEAT_TIMEOUT * 0.5
	connected.emit()


func _on_lobby_connected(id: int):
	if id == 1:
		_lobby_deadline = 0.0
		print("Connected to lobby server")
		lobby_connected.emit()
	else:
		print("Unknown peer connected to lobby: %d" % id)


func _on_lobby_disconnected(id: int):
	print("Disconnected from lobby")
	# If we never finished connecting, the server was unreachable / refused.
	var was_pending := _lobby_deadline > 0.0
	_lobby_deadline = 0.0
	_lobby_peer = null
	is_online = false
	if was_pending:
		lobby_connection_failed.emit()


func _fail_lobby_connection() -> void:
	print("Lobby connection timed out")
	if _lobby_peer:
		_lobby_peer.close()
		_lobby_peer = null
	multiplayer.multiplayer_peer = null
	is_online = false
	lobby_connection_failed.emit()


func _fail_game_connection() -> void:
	print("Game room connection timed out")
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_online = false
	game_connection_failed.emit()


@rpc("authority", "call_remote")
func lobby_response(json_str: String) -> void:
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return
	var data = json.get_data()
	if not data is Dictionary:
		return
	if data.get("status", "") == "server_status" and _lobby_status_callback.is_valid():
		_lobby_status_callback.call(data)
		return
	if _lobby_callback.is_valid():
		_lobby_callback.call(data)


func disconnect_from_lobby() -> void:
	_lobby_deadline = 0.0
	if _lobby_peer:
		_lobby_peer.close()
		_lobby_peer = null
	multiplayer.multiplayer_peer = null
	is_online = false


func connect_to_game_room(address: String, port: int, assigned_player: int) -> int:
	"""Reconnect to the game room port after lobby matchmaking."""
	disconnect_from_lobby()
	if not is_valid_address(address):
		return ERR_INVALID_PARAMETER
	if peer:
		peer.close()
		peer = null
	last_game_address = address
	last_game_port = port
	last_game_player_number = assigned_player
	player_number = assigned_player
	is_dedicated_server = true
	is_host = false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	_game_deadline = _now() + CONNECT_TIMEOUT
	print("Connecting to game room %s:%d (player %d)" % [address, port, player_number])
	return OK


# ============================================
# Peer events
# ============================================

func _on_peer_connected(id: int):
	if id == multiplayer.get_unique_id():
		return  # server self-ref
	# Any peer connection means the transport is established — clear the timeout.
	_game_deadline = 0.0
	if is_dedicated_server and id == 1:
		return  # dedicated server's own peer ID (not a player)
	opponent_peer_id = id
	_heartbeat_active = true
	_last_heartbeat_sent = _now()
	# Give the opponent a grace period before we start checking heartbeat timeout
	_last_heartbeat_received = _now() + HEARTBEAT_TIMEOUT * 0.5
	connected.emit()
	print("Opponent connected: %d" % id)


func _on_peer_disconnected(id: int):
	print("Opponent disconnected")
	opponent_peer_id = 0
	_heartbeat_active = false
	_last_heartbeat_received = 0.0
	is_online = false
	opponent_disconnected.emit()


# Heartbeat via raw bytes — bypasses the RPC checksum system so it works
# even when the two instances have slightly different code versions.
const _HEARTBEAT_MAGIC := "HB"

func _send_heartbeat() -> void:
	# send_bytes peer_id: 0 = broadcast to all, >0 = specific peer.
	# Relay mode broadcasts (server fans out); direct P2P targets the opponent.
	var target_peer: int = 0 if is_dedicated_server else opponent_peer_id
	multiplayer.send_bytes(_HEARTBEAT_MAGIC.to_ascii_buffer(), target_peer, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)


func _on_peer_packet(peer_id: int, data: PackedByteArray) -> void:
	if data.get_string_from_ascii() == _HEARTBEAT_MAGIC:
		_last_heartbeat_received = _now()


func _on_opponent_vanished() -> void:
	print("Opponent vanished (heartbeat timeout or no disconnect signal) — treating as disconnected")
	_heartbeat_active = false
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	opponent_peer_id = 0
	_last_heartbeat_received = 0.0
	is_online = false
	opponent_disconnected.emit()


# ============================================
# RPC calls (all @rpc("any_peer", "call_remote"))
# ============================================

@rpc("any_peer", "call_remote")
func _remote_start_game():
	game_started.emit()


@rpc("any_peer", "call_remote")
func rpc_summon(hand_index: int, slot_index: int, player: int):
	EventBus.rpc_summon_received.emit(hand_index, slot_index, player)


@rpc("any_peer", "call_remote")
func rpc_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	EventBus.rpc_summon_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote")
func rpc_attack(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_attack_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote")
func rpc_activate_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	EventBus.rpc_activate_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote")
func rpc_end_turn(player: int):
	EventBus.rpc_end_turn_received.emit(player)


@rpc("any_peer", "call_remote")
func rpc_discard(location: String, index: int, player: int):
	EventBus.rpc_discard_received.emit(location, index, player)


@rpc("any_peer", "call_remote")
func rpc_move_card(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_move_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote")
func rpc_targeting_arrow(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_targeting_arrow_received.emit(source_slot, target_slot, player)


# ============================================
# Player ready RPC
# ============================================

@rpc("any_peer", "call_remote", "reliable")
func rpc_player_ready(card_data_list: Array):
	EventBus.rpc_ready_received.emit(card_data_list)


# Card art transfer. Direct P2P always allowed; relay mode only when the
# dedicated server opted in (server_allows_card_art, sent in the lobby response).
func send_card_arts(arts: Array) -> void:
	if is_dedicated_server and not server_allows_card_art:
		return
	var target_peer := _card_art_target_peer()
	var total: int = arts.size()
	if target_peer > 0:
		rpc_id(target_peer, "rpc_card_art_manifest", total)
	else:
		rpc_card_art_manifest.rpc(total)
	for art in arts:
		var card_index := int(art.get("card_index", -1))
		var ext := str(art.get("ext", "png"))
		var bytes: PackedByteArray = art.get("bytes", PackedByteArray())
		if target_peer > 0:
			rpc_id(target_peer, "rpc_card_art", card_index, ext, bytes, total)
		else:
			rpc_card_art.rpc(card_index, ext, bytes, total)


func send_card_art_ack(card_index: int, total: int) -> void:
	if is_dedicated_server and not server_allows_card_art:
		return
	var target_peer := _card_art_target_peer()
	if target_peer > 0:
		rpc_id(target_peer, "rpc_card_art_ack", card_index, total)
	else:
		rpc_card_art_ack.rpc(card_index, total)


func _card_art_target_peer() -> int:
	# Relay mode hides the real opponent id (opponent_peer_id == -1): the room
	# server won't forward a targeted rpc_id, so broadcast (0) and let the relay
	# fan it out to the other client.
	if is_dedicated_server:
		return 0
	if opponent_peer_id > 0:
		return opponent_peer_id
	return 1 if not is_host else 0


@rpc("any_peer", "call_remote", "reliable")
func rpc_card_art_manifest(total: int):
	EventBus.rpc_card_art_manifest_received.emit(total)


@rpc("any_peer", "call_remote", "reliable")
func rpc_card_art(card_index: int, ext: String, bytes: PackedByteArray, total: int):
	EventBus.rpc_card_art_received.emit(card_index, ext, bytes, total)


@rpc("any_peer", "call_remote", "reliable")
func rpc_card_art_ack(card_index: int, total: int):
	EventBus.rpc_card_art_ack_received.emit(card_index, total)


# P2P battle splash trigger: the authority broadcasts which card just acted so the
# opponent shows the same splash art (or text fallback) animation.
@rpc("any_peer", "call_remote")
func rpc_splash(player: int, slot_index: int):
	EventBus.rpc_splash_received.emit(player, slot_index)


@rpc("any_peer", "call_remote")
func rpc_initial_state(state: Dictionary):
	EventBus.rpc_initial_state_received.emit(state)


@rpc("any_peer", "call_remote")
func rpc_request_initial_state():
	EventBus.rpc_initial_state_requested.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote")
func rpc_authority_state(state: Dictionary):
	EventBus.rpc_authority_state_received.emit(state)


@rpc("any_peer", "call_remote")
func rpc_intent_summon(hand_index: int, slot_index: int, player: int):
	EventBus.rpc_intent_summon_received.emit(hand_index, slot_index, player)


@rpc("any_peer", "call_remote")
func rpc_intent_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	EventBus.rpc_intent_summon_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote")
func rpc_intent_attack(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_intent_attack_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote")
func rpc_intent_activate_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	EventBus.rpc_intent_activate_skill_received.emit(slot_index, skill_index, target_slot, player)



@rpc("any_peer", "call_remote")
func rpc_intent_end_turn(player: int):
	EventBus.rpc_intent_end_turn_received.emit(player)


@rpc("any_peer", "call_remote")
func rpc_intent_discard(location: String, index: int, player: int):
	EventBus.rpc_intent_discard_received.emit(location, index, player)


@rpc("any_peer", "call_remote")
func rpc_intent_move_card(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_intent_move_received.emit(source_slot, target_slot, player)


# ============================================
# Cleanup
# ============================================

func close_connection():
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_heartbeat_active = false
	_last_heartbeat_received = 0.0
	if peer:
		peer.close()
		peer = null
	if _lobby_peer:
		_lobby_peer.close()
		_lobby_peer = null
	multiplayer.multiplayer_peer = null
	is_online = false
	is_host = false
	is_dedicated_server = false
	server_allows_card_art = false
	player_number = 0
	opponent_peer_id = 0

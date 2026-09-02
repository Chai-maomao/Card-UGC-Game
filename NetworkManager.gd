extends Node

# ============================================
# Network manager — ENet P2P RPC layer
# ============================================

signal connected()
signal game_started()
signal lobby_connected()
signal lobby_connection_failed()
signal game_connection_failed()
signal room_authenticated(player: int, reconnecting: bool)
signal opponent_disconnected(player: int)
signal reconnect_started()
signal reconnect_transport_ready()
signal reconnect_failed(reason: String)
signal reconnect_progress(elapsed_seconds: int, attempt: int)
signal protocol_mismatch(remote_version: int)
signal server_match_snapshot_received(state: Dictionary)
signal lan_rooms_updated(rooms: Array)
signal game_command_status(command_id: String, kind: String, status: String, latency_ms: int)

const LOBBY_PORT := 4567
const CONNECT_TIMEOUT := 8.0  # seconds before a pending connection is treated as failed
const RECONNECT_WINDOW := 60.0 * 60.0
const RECONNECT_RETRY_BASE := 0.5
const RECONNECT_RETRY_MAX := 8.0
const COMMAND_ACK_TIMEOUT := 1.25
const COMMAND_RECEIPT_TIMEOUT := 4.0
const COMMAND_TOTAL_TIMEOUT := 8.0
const COMMAND_MAX_SENDS := 4
const RECEIVED_COMMAND_CACHE_SIZE := 512
const ART_CHUNK_BYTES := 24 * 1024
const ART_CHUNKS_PER_FRAME := 2
const SESSION_PATH := "user://active_room.cfg"
const MATCH_SNAPSHOT_PATH := "user://active_match_state.json"
const MATCH_SNAPSHOT_BACKUP_PATH := "user://active_match_state.json.bak"
const MATCH_SNAPSHOT_SCHEMA := 1
const SnapshotStore = preload("res://MatchSnapshotStore.gd")
const SessionStore = preload("res://RoomSessionStore.gd")
const ProtocolGuard = preload("res://NetworkProtocolGuard.gd")
const HEARTBEAT_INTERVAL := 2.0  # seconds between heartbeat sends
const HEARTBEAT_TIMEOUT := 7.0  # seconds without receiving heartbeat before declaring disconnect
const LAN_GAME_PORT := 4568
const LAN_DISCOVERY_PORT := 4569
const LAN_DISCOVERY_INTERVAL := 1.0
const LAN_ROOM_TTL := 3.5
const LAN_DISCOVERY_MAGIC := "CARD_UGC_LAN_V1"
const GAME_CHANNEL_COUNT := 5
const SESSION_MODE_ROOM := "room"
const SESSION_MODE_LAN_HOST := "lan_host"
const SESSION_MODE_LAN_CLIENT := "lan_client"

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
var room_server_address: String = ""
var room_server_port: int = 0
var room_code: String = ""
var room_player_number: int = 0
var reconnect_token: String = ""
var room_match_started: bool = false
var session_mode: String = ""
var session_id: String = ""
var just_reconnected: bool = false
var _session_storage_path: String = SESSION_PATH
var _match_snapshot_path: String = MATCH_SNAPSHOT_PATH
var _match_snapshot_backup_path: String = MATCH_SNAPSHOT_BACKUP_PATH

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
var room_auth_handler: Callable
var authority_state_handler: Callable
var room_message_guard: Callable

# Pending-connection timeout tracking (deadlines in seconds; <= 0 means inactive)
var _lobby_deadline: float = 0.0
var _game_deadline: float = 0.0
var _reconnect_active: bool = false
var _reconnect_deadline: float = 0.0
var _reconnect_retry_at: float = 0.0
var _reconnect_attempt_running: bool = false
var _reconnect_started_at: float = 0.0
var _reconnect_attempt_count: int = 0
var _last_reconnect_progress_second: int = -1
var _direct_protocol_verified: bool = false
var _connected_emitted: bool = false
var pending_server_match_state: Dictionary = {}
var _command_sequence: int = 0
var _pending_game_commands: Dictionary = {}
var _received_game_commands: Dictionary = {}
var _next_authority_ack: Dictionary = {}
var _art_send_queue: Array[Dictionary] = []
var _art_receive_buffers: Dictionary = {}
var _last_network_phase: String = "idle"
var _last_disconnect_reason: String = ""
var _lan_discovery_responder: PacketPeerUDP
var _lan_discovery_scanner: PacketPeerUDP
var _lan_discovery_next_query: float = 0.0
var _lan_discovered_rooms: Dictionary = {}


func _ready() -> void:
	_load_room_session()


func use_isolated_session_storage(prefix: String) -> bool:
	# Integration tests run multiple game processes on one machine. Give each
	# process its own user:// files so a test can never overwrite a real resume.
	if not OS.is_debug_build():
		return false
	var safe := ""
	for character in prefix.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["-", "_"]:
			safe += character
	if safe.is_empty():
		return false
	safe = safe.left(48)
	_session_storage_path = "user://test_active_room_%s.cfg" % safe
	_match_snapshot_path = "user://test_active_match_%s.json" % safe
	_match_snapshot_backup_path = _match_snapshot_path + ".bak"
	room_server_address = ""
	room_server_port = 0
	room_code = ""
	room_player_number = 0
	reconnect_token = ""
	room_match_started = false
	session_mode = ""
	session_id = ""
	just_reconnected = false
	_load_room_session()
	return true


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _close_game_peer() -> void:
	var old_peer := peer
	peer = null
	if old_peer:
		if multiplayer.multiplayer_peer == old_peer:
			multiplayer.multiplayer_peer = null
		old_peer.close()


func _close_lobby_peer() -> void:
	var old_peer := _lobby_peer
	_lobby_peer = null
	if old_peer:
		if multiplayer.multiplayer_peer == old_peer:
			multiplayer.multiplayer_peer = null
		old_peer.close()


func _process(_delta: float) -> void:
	if _lobby_deadline > 0.0 and _now() > _lobby_deadline:
		_lobby_deadline = 0.0
		_fail_lobby_connection()
	if _game_deadline > 0.0 and _now() > _game_deadline:
		_game_deadline = 0.0
		_fail_game_connection()
	if _reconnect_active:
		var elapsed := maxi(0, int(_now() - _reconnect_started_at))
		if elapsed != _last_reconnect_progress_second:
			_last_reconnect_progress_second = elapsed
			reconnect_progress.emit(elapsed, _reconnect_attempt_count)
		if _now() >= _reconnect_deadline:
			_finish_reconnect_failure("reconnect_timeout")
		elif not _reconnect_attempt_running and _now() >= _reconnect_retry_at:
			_attempt_match_reconnect()
	_process_lan_discovery()
	# Application-level heartbeat: send periodically and detect timeout.
	if _heartbeat_active and is_online and opponent_peer_id > 0:
		var t: float = _now()
		if t - _last_heartbeat_sent >= HEARTBEAT_INTERVAL:
			_last_heartbeat_sent = t
			_send_heartbeat()
		if _last_heartbeat_received > 0.0 and t - _last_heartbeat_received > HEARTBEAT_TIMEOUT:
			if is_dedicated_server:
				# The relay owns stable player presence and sends an authenticated
				# disconnect notification. Do not freeze a live room on transient loss.
				_last_heartbeat_received = t
				print("[Heartbeat] Opponent heartbeat delayed; waiting for room server state")
			else:
				print("[Heartbeat] No heartbeat from opponent for %.1fs - declaring disconnect" % (t - _last_heartbeat_received))
				_on_opponent_vanished()
	_process_pending_game_commands()
	_process_art_send_queue()
	_cleanup_art_receive_buffers()


func _network_diag(event: String, details: Dictionary = {}) -> void:
	var fields := {
		"event": event,
		"phase": _last_network_phase,
		"online": is_online,
		"dedicated": is_dedicated_server,
		"player": player_number,
		"room": room_code,
		"attempt": _reconnect_attempt_count,
		"pending_commands": _pending_game_commands.size(),
		"heartbeat_age_ms": int(maxf(0.0, _now() - _last_heartbeat_received) * 1000.0) if _last_heartbeat_received > 0.0 else -1,
	}
	for key in details:
		fields[key] = details[key]
	print("[NET] %s" % JSON.stringify(fields))


func _sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


static func reconnect_retry_delay(attempt: int, jitter_sample: float = 0.5) -> float:
	var exponent := maxi(0, attempt - 1)
	var base_delay := minf(RECONNECT_RETRY_BASE * pow(2.0, exponent), RECONNECT_RETRY_MAX)
	var normalized_jitter := clampf(jitter_sample, 0.0, 1.0)
	return base_delay * lerpf(0.8, 1.2, normalized_jitter)


# ============================================
# Persisted room/LAN match session
# ============================================

func configure_room_session(address: String, port: int, code: String, assigned_player: int, token: String) -> void:
	var session_changed := session_mode != SESSION_MODE_ROOM or room_code != code or room_player_number != assigned_player or reconnect_token != token
	if session_changed:
		clear_match_snapshot()
	room_server_address = address
	room_server_port = port
	room_code = code
	room_player_number = assigned_player
	reconnect_token = token
	session_mode = SESSION_MODE_ROOM
	session_id = code
	room_match_started = false
	_save_room_session()


func has_saved_room_session() -> bool:
	return session_mode == SESSION_MODE_ROOM and room_server_address != "" and room_server_port > 0 and room_code != "" and room_player_number in [1, 2] and reconnect_token != ""


func configure_lan_session(address: String, port: int, assigned_player: int, lan_session_id: String = "") -> void:
	var mode := SESSION_MODE_LAN_HOST if assigned_player == 1 else SESSION_MODE_LAN_CLIENT
	var changed := session_mode != mode or room_server_address != address or room_server_port != port or (lan_session_id != "" and session_id != lan_session_id)
	if changed:
		clear_match_snapshot()
	session_mode = mode
	room_server_address = address
	room_server_port = port
	room_player_number = assigned_player
	room_code = ""
	reconnect_token = ""
	server_allows_card_art = true
	room_match_started = false
	session_id = lan_session_id
	_save_room_session()


func has_saved_lan_session() -> bool:
	if session_mode not in [SESSION_MODE_LAN_HOST, SESSION_MODE_LAN_CLIENT]:
		return false
	if room_server_port <= 0 or room_player_number not in [1, 2] or session_id == "":
		return false
	return session_mode == SESSION_MODE_LAN_HOST or room_server_address != ""


func has_saved_match_session() -> bool:
	return has_saved_room_session() or has_saved_lan_session()


func has_resumable_match_session() -> bool:
	return has_saved_match_session() and room_match_started


func mark_room_match_started() -> void:
	mark_match_started()


func mark_match_started() -> void:
	if not has_saved_match_session():
		return
	room_match_started = true
	_save_room_session()


func clear_room_session() -> void:
	clear_match_snapshot()
	room_server_address = ""
	room_server_port = 0
	room_code = ""
	room_player_number = 0
	reconnect_token = ""
	session_mode = ""
	session_id = ""
	room_match_started = false
	just_reconnected = false
	_reconnect_active = false
	_reconnect_attempt_running = false
	SessionStore.new(_session_storage_path).clear()


func save_match_snapshot(state: Dictionary) -> bool:
	if not has_resumable_match_session() or state.is_empty():
		return false
	var payload := {
		"schema": MATCH_SNAPSHOT_SCHEMA,
		"room_code": _snapshot_session_key(),
		"player": room_player_number,
		"saved_at": Time.get_unix_time_from_system(),
		"state": encode_match_state_for_snapshot(state),
	}
	return SnapshotStore.new(_match_snapshot_path, _match_snapshot_backup_path).save(payload)


func load_match_snapshot() -> Dictionary:
	if not has_resumable_match_session():
		return {}
	var payload := SnapshotStore.new(_match_snapshot_path, _match_snapshot_backup_path).load()
	if payload.is_empty():
		return {}
	if str(payload.get("room_code", "")) != _snapshot_session_key():
		return {}
	if int(payload.get("player", 0)) != room_player_number:
		return {}
	return decode_match_state_from_snapshot(payload.get("state", {}) as Dictionary)


func clear_match_snapshot() -> void:
	SnapshotStore.new(_match_snapshot_path, _match_snapshot_backup_path).clear()


static func is_valid_snapshot_payload(value: Variant) -> bool:
	return SnapshotStore.is_valid(value)


static func encode_match_state_for_snapshot(state: Dictionary) -> Dictionary:
	return SnapshotStore.encode_state(state)


static func decode_match_state_from_snapshot(state: Dictionary) -> Dictionary:
	return SnapshotStore.decode_state(state)


func _save_room_session() -> void:
	if not has_saved_match_session():
		return
	SessionStore.new(_session_storage_path).save({"mode": session_mode, "address": room_server_address, "port": room_server_port, "code": room_code, "player": room_player_number, "token": reconnect_token, "card_art": server_allows_card_art, "match_started": room_match_started, "session_id": session_id})


func _load_room_session() -> void:
	var data := SessionStore.new(_session_storage_path).load()
	if data.is_empty():
		return
	room_server_address = data["address"]
	room_server_port = data["port"]
	room_code = data["code"]
	room_player_number = data["player"]
	reconnect_token = data["token"]
	server_allows_card_art = data["card_art"]
	room_match_started = data["match_started"]
	session_mode = str(data.get("mode", SESSION_MODE_ROOM))
	session_id = str(data.get("session_id", room_code))


func _snapshot_session_key() -> String:
	return room_code if session_mode == SESSION_MODE_ROOM else session_id


func _new_lan_session_id() -> String:
	return "LAN" + Crypto.new().generate_random_bytes(12).hex_encode()


# ============================================
# Validation helpers
# ============================================

static func is_valid_room_code(code: String) -> bool:
	return ProtocolGuard.valid_room_code(code)


static func is_valid_address(address: String) -> bool:
	return ProtocolGuard.valid_address(address)


func is_authority() -> bool:
	if not is_online:
		return true  # hotseat: always authority
	if is_dedicated_server:
		return player_number == 1
	return is_host


static func is_remote_player_claim_valid(local_player: int, claimed_player: int) -> bool:
	return ProtocolGuard.valid_remote_player_claim(local_player, claimed_player)


func _accept_remote_player_claim(claimed_player: int) -> bool:
	if not is_online or not is_remote_player_claim_valid(player_number, claimed_player):
		push_warning("Rejected network message with invalid player claim P%d" % claimed_player)
		return false
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return false
	if not is_dedicated_server and opponent_peer_id > 0 and sender != opponent_peer_id:
		push_warning("Rejected network message from unexpected peer %d" % sender)
		return false
	return true


func _accept_remote_intent(claimed_player: int) -> bool:
	return is_authority() and _accept_remote_player_claim(claimed_player)


# ============================================
# LAN host / join. Public-internet traversal is intentionally left to players.
# ============================================

func host_game(port: int = LAN_GAME_PORT) -> int:
	close_connection()
	clear_room_session()
	configure_lan_session("127.0.0.1", port, 1, _new_lan_session_id())
	return _create_lan_host(port)


func _create_lan_host(port: int) -> int:
	is_dedicated_server = false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 1, GAME_CHANNEL_COUNT)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_online = true
	player_number = 1
	_last_network_phase = "direct_host_waiting"
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	_start_lan_discovery_responder()
	print("Hosting on port %d" % port)
	_network_diag("direct_host_started", {"port": port, "scope": "lan"})
	return OK


func join_game(address: String, port: int = LAN_GAME_PORT) -> int:
	close_connection()
	clear_room_session()
	if not is_valid_address(address):
		return ERR_INVALID_PARAMETER
	configure_lan_session(address, port, 2)
	return _create_lan_client(address, port)


func _create_lan_client(address: String, port: int) -> int:
	is_dedicated_server = false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port, GAME_CHANNEL_COUNT)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_online = true
	player_number = 2
	_last_network_phase = "direct_connecting"
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	_game_deadline = _now() + CONNECT_TIMEOUT
	print("Joining %s:%d" % [address, port])
	_network_diag("direct_join_started", {"address": address, "port": port, "scope": "lan"})
	return OK


func start_lan_room_discovery() -> int:
	stop_lan_room_discovery()
	_lan_discovery_scanner = PacketPeerUDP.new()
	var err := _lan_discovery_scanner.bind(0, "*")
	if err != OK:
		_lan_discovery_scanner = null
		return err
	_lan_discovery_scanner.set_broadcast_enabled(true)
	_lan_discovery_next_query = 0.0
	_lan_discovered_rooms.clear()
	lan_rooms_updated.emit([])
	return OK


func stop_lan_room_discovery() -> void:
	if _lan_discovery_scanner:
		_lan_discovery_scanner.close()
	_lan_discovery_scanner = null
	_lan_discovered_rooms.clear()


func refresh_lan_room_discovery() -> void:
	_lan_discovery_next_query = 0.0


func _start_lan_discovery_responder() -> void:
	_stop_lan_discovery_responder()
	_lan_discovery_responder = PacketPeerUDP.new()
	var err := _lan_discovery_responder.bind(LAN_DISCOVERY_PORT, "*")
	if err != OK:
		_network_diag("lan_discovery_bind_failed", {"error": err})
		_lan_discovery_responder = null


func _stop_lan_discovery_responder() -> void:
	if _lan_discovery_responder:
		_lan_discovery_responder.close()
	_lan_discovery_responder = null


func _process_lan_discovery() -> void:
	if _lan_discovery_responder:
		while _lan_discovery_responder.get_available_packet_count() > 0:
			var request := _decode_lan_discovery_packet(_lan_discovery_responder.get_packet())
			var source_ip := _lan_discovery_responder.get_packet_ip()
			var source_port := _lan_discovery_responder.get_packet_port()
			if str(request.get("kind", "")) == "query" and int(request.get("protocol", -1)) == AppVersion.PROTOCOL_VERSION and not room_match_started and opponent_peer_id == 0:
				var response := _encode_lan_discovery_packet({"kind": "room", "name": OS.get_environment("COMPUTERNAME"), "port": room_server_port, "protocol": AppVersion.PROTOCOL_VERSION})
				_lan_discovery_responder.set_dest_address(source_ip, source_port)
				_lan_discovery_responder.put_packet(response)
	if not _lan_discovery_scanner:
		return
	var now := _now()
	if now >= _lan_discovery_next_query:
		_lan_discovery_next_query = now + LAN_DISCOVERY_INTERVAL
		var query := _encode_lan_discovery_packet({"kind": "query", "protocol": AppVersion.PROTOCOL_VERSION})
		_lan_discovery_scanner.set_dest_address("255.255.255.255", LAN_DISCOVERY_PORT)
		_lan_discovery_scanner.put_packet(query)
		# Also probe loopback so two local instances (and automated tests) work
		# even when the OS suppresses broadcast loopback.
		_lan_discovery_scanner.set_dest_address("127.0.0.1", LAN_DISCOVERY_PORT)
		_lan_discovery_scanner.put_packet(query)
	var changed := false
	while _lan_discovery_scanner.get_available_packet_count() > 0:
		var response := _decode_lan_discovery_packet(_lan_discovery_scanner.get_packet())
		var address := _lan_discovery_scanner.get_packet_ip()
		if str(response.get("kind", "")) != "room" or int(response.get("protocol", -1)) != AppVersion.PROTOCOL_VERSION:
			continue
		var port := int(response.get("port", 0))
		if port <= 0 or port > 65535 or not is_valid_address(address):
			continue
		var key := "%s:%d" % [address, port]
		_lan_discovered_rooms[key] = {"address": address, "port": port, "name": str(response.get("name", "LAN Host")), "seen_at": now}
		changed = true
	for key in _lan_discovered_rooms.keys():
		if now - float(_lan_discovered_rooms[key].get("seen_at", 0.0)) > LAN_ROOM_TTL:
			_lan_discovered_rooms.erase(key)
			changed = true
	if changed:
		var rooms: Array = _lan_discovered_rooms.values()
		rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
		lan_rooms_updated.emit(rooms)


static func _encode_lan_discovery_packet(data: Dictionary) -> PackedByteArray:
	var payload := data.duplicate(true)
	payload["magic"] = LAN_DISCOVERY_MAGIC
	return JSON.stringify(payload).to_utf8_buffer()


static func _decode_lan_discovery_packet(packet: PackedByteArray) -> Dictionary:
	if packet.size() <= 0 or packet.size() > 2048:
		return {}
	var json := JSON.new()
	if json.parse(packet.get_string_from_utf8()) != OK:
		return {}
	var parsed = json.data
	if not parsed is Dictionary or str(parsed.get("magic", "")) != LAN_DISCOVERY_MAGIC:
		return {}
	return parsed


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
	_lobby_peer.peer_connected.connect(_on_lobby_connected.bind(_lobby_peer))
	_lobby_peer.peer_disconnected.connect(_on_lobby_disconnected.bind(_lobby_peer))
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


func reconnect_room(code: String, assigned_player: int, token: String) -> void:
	_lobby_request({
		"action": "reconnect",
		"code": code,
		"player": assigned_player,
		"reconnect_token": token,
	})


func request_lobby_status(callback: Callable) -> void:
	_lobby_status_callback = callback
	_lobby_request({"action": "status"})


func _lobby_request(data: Dictionary) -> void:
	data["protocol"] = AppVersion.PROTOCOL_VERSION
	rpc_id(1, "lobby_request", JSON.stringify(data))


@rpc("any_peer", "call_remote", "reliable", 0)
func lobby_request(json_str: String) -> void:
	# Runs on the dedicated server. The RPC always lands here (shared autoload node),
	# so forward it to server.gd's handler if one is registered.
	if lobby_request_handler.is_valid():
		lobby_request_handler.call(multiplayer.get_remote_sender_id(), json_str)


func send_lobby_response(peer_id: int, json_str: String) -> void:
	# Server-side helper: reply to a specific client through the shared node.
	rpc_id(peer_id, "lobby_response", json_str)


@rpc("authority", "call_remote", "reliable", 0)
func notify_room_ready() -> void:
	# Broadcast by the room subprocess (peer 1) once both players are connected.
	# Drives the same "opponent connected" path used by direct P2P.
	is_online = true
	if opponent_peer_id <= 0:
		opponent_peer_id = 1  # relay mode: server (peer 1) is the relay target
	_heartbeat_active = true
	_last_heartbeat_sent = _now()
	_last_heartbeat_received = _now() + HEARTBEAT_TIMEOUT * 0.5
	connected.emit()


@rpc("any_peer", "call_remote", "reliable", 0)
func rpc_room_auth(code: String, assigned_player: int, token: String, protocol_version: int) -> void:
	# Room subprocess only: forward authentication to room_server.gd, which owns
	# the reconnect tokens and stable P1/P2 slot mapping.
	if room_auth_handler.is_valid():
		room_auth_handler.call(multiplayer.get_remote_sender_id(), code, assigned_player, token, protocol_version)


func send_room_auth_result(peer_id: int, accepted: bool, assigned_player: int, reason: String, reconnecting: bool) -> void:
	rpc_id(peer_id, "rpc_room_auth_result", accepted, assigned_player, reason, reconnecting)


@rpc("authority", "call_remote", "reliable", 0)
func rpc_room_auth_result(accepted: bool, assigned_player: int, reason: String, reconnecting: bool) -> void:
	_game_deadline = 0.0
	if not accepted:
		if _reconnect_active:
			if reason in ["invalid_token", "invalid_reconnect"]:
				_finish_reconnect_failure(reason, true)
			elif reason == "protocol_mismatch":
				_finish_reconnect_failure(reason)
			else:
				_schedule_reconnect_retry(reason)
		else:
			_fail_game_connection()
		return

	player_number = assigned_player
	room_player_number = assigned_player
	is_online = true
	var resumed := _reconnect_active or reconnecting
	_reconnect_active = false
	_reconnect_attempt_running = false
	_reconnect_deadline = 0.0
	_reconnect_retry_at = 0.0
	just_reconnected = resumed
	_last_network_phase = "room_authenticated"
	_last_disconnect_reason = ""
	_network_diag("room_authenticated", {"reconnecting": resumed})
	room_authenticated.emit(assigned_player, resumed)
	if resumed:
		reconnect_transport_ready.emit()


@rpc("authority", "call_remote", "reliable", 0)
func notify_player_disconnected(disconnected_player: int) -> void:
	if disconnected_player == player_number:
		return
	opponent_peer_id = 0
	_heartbeat_active = false
	_last_heartbeat_received = 0.0
	is_online = true
	opponent_disconnected.emit(disconnected_player)


func _on_lobby_connected(id: int, source_peer: ENetMultiplayerPeer):
	if source_peer != _lobby_peer:
		return
	if id == 1:
		print("Connected to lobby server")
		if _reconnect_active:
			reconnect_room(room_code, room_player_number, reconnect_token)
			_lobby_deadline = _now() + CONNECT_TIMEOUT
		else:
			_lobby_deadline = 0.0
			lobby_connected.emit()
	else:
		print("Unknown peer connected to lobby: %d" % id)


func _on_lobby_disconnected(id: int, source_peer: ENetMultiplayerPeer):
	if source_peer != _lobby_peer:
		return
	print("Disconnected from lobby")
	# If we never finished connecting, the server was unreachable / refused.
	var was_pending := _lobby_deadline > 0.0
	_lobby_deadline = 0.0
	_close_lobby_peer()
	is_online = false
	if _reconnect_active:
		_schedule_reconnect_retry("lobby_disconnected")
	elif was_pending:
		lobby_connection_failed.emit()


func _fail_lobby_connection() -> void:
	print("Lobby connection timed out")
	_close_lobby_peer()
	is_online = false
	if _reconnect_active:
		_schedule_reconnect_retry("lobby_timeout")
	else:
		lobby_connection_failed.emit()


func _fail_game_connection() -> void:
	print("Game room connection timed out")
	_close_game_peer()
	is_online = false
	if _reconnect_active:
		_schedule_reconnect_retry("room_timeout")
	else:
		game_connection_failed.emit()


@rpc("authority", "call_remote", "reliable", 0)
func lobby_response(json_str: String) -> void:
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return
	var data = json.get_data()
	if not data is Dictionary:
		return
	var remote_protocol := int(data.get("protocol", AppVersion.PROTOCOL_VERSION))
	if remote_protocol != AppVersion.PROTOCOL_VERSION:
		data["status"] = "protocol_mismatch"
		data["remote_protocol"] = remote_protocol
		protocol_mismatch.emit(remote_protocol)
	if data.get("status", "") == "server_status" and _lobby_status_callback.is_valid():
		_lobby_status_callback.call(data)
		return
	if _lobby_callback.is_valid():
		_lobby_callback.call(data)


func disconnect_from_lobby() -> void:
	_lobby_deadline = 0.0
	_close_lobby_peer()
	is_online = false


func connect_to_game_room(address: String, port: int, assigned_player: int, code: String = "", token: String = "") -> int:
	"""Reconnect to the game room port after lobby matchmaking."""
	disconnect_from_lobby()
	if not is_valid_address(address):
		return ERR_INVALID_PARAMETER
	_close_game_peer()
	last_game_address = address
	last_game_port = port
	last_game_player_number = assigned_player
	player_number = assigned_player
	if code != "" and token != "":
		configure_room_session(address, port, code, assigned_player, token)
	else:
		room_server_address = address
		room_server_port = port
		room_player_number = assigned_player
	is_dedicated_server = true
	is_host = false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port, GAME_CHANNEL_COUNT)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	_game_deadline = _now() + CONNECT_TIMEOUT
	print("Connecting to game room %s:%d (player %d)" % [address, port, player_number])
	return OK


# ============================================
# Match reconnect loop
# ============================================

func begin_saved_match_reconnect() -> bool:
	if not has_resumable_match_session():
		return false
	_start_match_reconnect()
	return true


func _start_match_reconnect() -> void:
	if not has_saved_match_session():
		_finish_reconnect_failure("no_saved_session", true)
		return
	if _reconnect_active:
		return

	_reconnect_active = true
	_reconnect_started_at = _now()
	_reconnect_attempt_count = 0
	_last_reconnect_progress_second = -1
	_reconnect_deadline = _now() + RECONNECT_WINDOW
	_reconnect_retry_at = _now()
	_reconnect_attempt_running = false
	just_reconnected = false
	_last_network_phase = "reconnect_wait"
	_last_disconnect_reason = ""
	opponent_peer_id = 0
	is_online = false
	_game_deadline = 0.0
	_lobby_deadline = 0.0
	_close_game_peer()
	_close_lobby_peer()
	_network_diag("reconnect_started")
	reconnect_started.emit()


func _attempt_match_reconnect() -> void:
	if not _reconnect_active or _reconnect_attempt_running:
		return
	if _now() >= _reconnect_deadline:
		_finish_reconnect_failure("reconnect_timeout")
		return
	_reconnect_attempt_running = true
	_reconnect_attempt_count += 1
	if session_mode == SESSION_MODE_LAN_HOST:
		_last_network_phase = "reconnect_lan_host"
		_network_diag("reconnect_attempt")
		reconnect_progress.emit(maxi(0, int(_now() - _reconnect_started_at)), _reconnect_attempt_count)
		var host_err := _create_lan_host(room_server_port)
		if host_err != OK:
			_schedule_reconnect_retry("lan_host_error_%d" % host_err)
		return
	if session_mode == SESSION_MODE_LAN_CLIENT:
		_last_network_phase = "reconnect_lan_client"
		_network_diag("reconnect_attempt")
		reconnect_progress.emit(maxi(0, int(_now() - _reconnect_started_at)), _reconnect_attempt_count)
		var client_err := _create_lan_client(room_server_address, room_server_port)
		if client_err != OK:
			_schedule_reconnect_retry("lan_connect_error_%d" % client_err)
		return
	_last_network_phase = "reconnect_lobby"
	_network_diag("reconnect_attempt")
	reconnect_progress.emit(maxi(0, int(_now() - _reconnect_started_at)), _reconnect_attempt_count)
	var err := connect_to_lobby(room_server_address, Callable(self, "_on_reconnect_lobby_response"))
	if err != OK:
		_schedule_reconnect_retry("lobby_connect_error_%d" % err)


func _on_reconnect_lobby_response(data: Dictionary) -> void:
	if not _reconnect_active:
		return
	var status := str(data.get("status", ""))
	if status != "ok":
		if status in ["not_found", "invalid_reconnect"]:
			_finish_reconnect_failure(status, true)
		elif status == "protocol_mismatch":
			_finish_reconnect_failure(status)
		else:
			_schedule_reconnect_retry(status if status != "" else "invalid_response")
		return

	server_allows_card_art = bool(data.get("card_art", server_allows_card_art))
	var assigned_player := int(data.get("player", room_player_number))
	var port := int(data.get("port", room_server_port))
	_reconnect_attempt_running = true
	var err := connect_to_game_room(room_server_address, port, assigned_player)
	if err != OK:
		_schedule_reconnect_retry("room_connect_error_%d" % err)


func _schedule_reconnect_retry(reason: String) -> void:
	if not _reconnect_active:
		return
	_last_disconnect_reason = reason
	_last_network_phase = "reconnect_backoff"
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_close_game_peer()
	_close_lobby_peer()
	is_online = false
	_reconnect_attempt_running = false
	var delay := reconnect_retry_delay(_reconnect_attempt_count, randf())
	_reconnect_retry_at = min(_now() + delay, _reconnect_deadline)
	_network_diag("reconnect_retry_scheduled", {"reason": reason, "delay_ms": int(delay * 1000.0)})


func _finish_reconnect_failure(reason: String, clear_saved_session: bool = false) -> void:
	var was_active := _reconnect_active
	_reconnect_active = false
	_reconnect_attempt_running = false
	_reconnect_deadline = 0.0
	_reconnect_retry_at = 0.0
	_reconnect_started_at = 0.0
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_close_game_peer()
	_close_lobby_peer()
	_stop_lan_discovery_responder()
	is_online = false
	_last_disconnect_reason = reason
	_last_network_phase = "failed"
	_network_diag("reconnect_failed", {"reason": reason})
	if clear_saved_session:
		clear_room_session()
	if was_active or reason == "no_saved_session":
		reconnect_failed.emit(reason)


# ============================================
# Peer events
# ============================================

func _on_peer_connected(id: int, source_peer: ENetMultiplayerPeer):
	if source_peer != peer:
		return
	if id == multiplayer.get_unique_id():
		return  # server self-ref
	if is_dedicated_server:
		if id == 1:
			# The room transport is not considered ready until the room process
			# authenticates our saved player slot and reconnect token.
			rpc_id(1, "rpc_room_auth", room_code, player_number, reconnect_token, AppVersion.PROTOCOL_VERSION)
		return
	# Direct P2P still verifies the wire protocol before exposing the connection.
	opponent_peer_id = id
	_direct_protocol_verified = false
	_connected_emitted = false
	rpc_id(id, "rpc_protocol_hello", AppVersion.PROTOCOL_VERSION, player_number, session_id)
	print("Opponent connected: %d" % id)


@rpc("any_peer", "call_remote", "reliable", 0)
func rpc_protocol_hello(version: int, claimed_player: int, remote_session_id: String = "") -> void:
	if is_dedicated_server:
		return
	if version != AppVersion.PROTOCOL_VERSION:
		protocol_mismatch.emit(version)
		game_connection_failed.emit()
		_close_game_peer()
		is_online = false
		return
	if claimed_player not in [1, 2] or claimed_player == player_number:
		return
	if is_host:
		if room_match_started and remote_session_id != session_id:
			_reject_direct_protocol_peer("session_mismatch")
			return
	elif session_mode == SESSION_MODE_LAN_CLIENT:
		if remote_session_id == "" or (session_id != "" and session_id != remote_session_id):
			_reject_direct_protocol_peer("session_mismatch")
			return
		if session_id == "":
			session_id = remote_session_id
			_save_room_session()
	_direct_protocol_verified = true
	_last_network_phase = "direct_ready"
	_last_disconnect_reason = ""
	_network_diag("direct_protocol_ready", {"peer_id": multiplayer.get_remote_sender_id()})
	_game_deadline = 0.0
	_heartbeat_active = true
	_last_heartbeat_sent = _now()
	_last_heartbeat_received = _now() + HEARTBEAT_TIMEOUT * 0.5
	var resumed := _reconnect_active
	if resumed:
		_reconnect_active = false
		_reconnect_attempt_running = false
		_reconnect_deadline = 0.0
		_reconnect_retry_at = 0.0
		just_reconnected = true
	if not _connected_emitted:
		_connected_emitted = true
		connected.emit()
	if resumed:
		reconnect_transport_ready.emit()


func _reject_direct_protocol_peer(reason: String) -> void:
	_network_diag("direct_protocol_rejected", {"reason": reason})
	if _reconnect_active:
		_schedule_reconnect_retry(reason)
	else:
		game_connection_failed.emit()
		_close_game_peer()
		is_online = false


func _on_peer_disconnected(id: int, source_peer: ENetMultiplayerPeer):
	if source_peer != peer:
		return
	if is_dedicated_server:
		if id == 1:
			print("Disconnected from game room server")
			_start_match_reconnect()
		else:
			# The authenticated room server sends notify_player_disconnected with
			# the stable P1/P2 slot. Keep this client's room connection alive.
			print("Room peer %d disconnected" % id)
		return
	print("Opponent disconnected")
	opponent_peer_id = 0
	_heartbeat_active = false
	_last_heartbeat_received = 0.0
	is_online = false
	opponent_disconnected.emit(0)
	if has_resumable_match_session():
		if _reconnect_active:
			_schedule_reconnect_retry("lan_disconnected")
		else:
			_start_match_reconnect()


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
	print("Opponent vanished (heartbeat timeout or no disconnect signal) - treating as disconnected")
	_heartbeat_active = false
	opponent_peer_id = 0
	_last_heartbeat_received = 0.0
	if is_dedicated_server:
		# The room server is still the transport. Keep it connected so the missing
		# player can reclaim their stable slot and resume the existing match.
		is_online = true
	else:
		_close_game_peer()
		is_online = false
	opponent_disconnected.emit(0)
	if not is_dedicated_server and has_resumable_match_session():
		_start_match_reconnect()


# ============================================
# Gameplay command envelope. Reliable ordered channel 1 keeps combat traffic
# independent from connection/auth (channel 0), transient presentation (2), and
# bulk card art (3). Keeping intents and receipts on this established gameplay
# channel also avoids deployment-specific failures seen with higher custom
# channels. command_id makes retries idempotent; expected_revision lets the
# authority reject stale actions and return a fresh snapshot.
# ============================================

func send_game_intent(kind: String, payload: Dictionary, claimed_player: int, expected_revision: int) -> String:
	if not is_online or claimed_player not in [1, 2]:
		return ""
	_command_sequence += 1
	var command_id := "%d-%d-%d" % [claimed_player, Time.get_ticks_usec(), _command_sequence]
	var envelope := {
		"kind": kind,
		"payload": payload.duplicate(true),
		"player": claimed_player,
		"expected_revision": expected_revision,
		"sends": 1,
		"created_at": _now(),
		"retry_at": _now() + COMMAND_ACK_TIMEOUT,
	}
	_pending_game_commands[command_id] = envelope
	rpc_game_intent.rpc(command_id, expected_revision, claimed_player, kind, payload)
	_network_diag("command_sent", {"command_id": command_id, "kind": kind, "revision": expected_revision})
	game_command_status.emit(command_id, kind, "sent", 0)
	return command_id


func _process_pending_game_commands() -> void:
	if _pending_game_commands.is_empty() or not is_online:
		return
	var now := _now()
	for command_id in _pending_game_commands.keys():
		var envelope: Dictionary = _pending_game_commands.get(command_id, {})
		if now - float(envelope.get("created_at", now)) >= COMMAND_TOTAL_TIMEOUT:
			_pending_game_commands.erase(command_id)
			var timed_out_kind := str(envelope.get("kind", ""))
			_network_diag("command_timeout", {"command_id": command_id, "kind": timed_out_kind})
			game_command_status.emit(command_id, timed_out_kind, "timeout", int(COMMAND_TOTAL_TIMEOUT * 1000.0))
			rpc_request_initial_state.rpc()
			continue
		if now < float(envelope.get("retry_at", 0.0)):
			continue
		var sends := int(envelope.get("sends", 1))
		if sends >= COMMAND_MAX_SENDS:
			envelope["retry_at"] = now + COMMAND_RECEIPT_TIMEOUT
			_pending_game_commands[command_id] = envelope
			rpc_request_initial_state.rpc()
			_network_diag("command_resync_requested", {"command_id": command_id, "kind": envelope.get("kind", ""), "sends": sends})
			continue
		sends += 1
		envelope["sends"] = sends
		envelope["retry_at"] = now + COMMAND_ACK_TIMEOUT
		_pending_game_commands[command_id] = envelope
		rpc_game_intent.rpc(
			command_id,
			int(envelope.get("expected_revision", -1)),
			int(envelope.get("player", 0)),
			str(envelope.get("kind", "")),
			envelope.get("payload", {}) as Dictionary
		)
		_network_diag("command_resent", {"command_id": command_id, "kind": envelope.get("kind", ""), "sends": sends})


func acknowledge_game_command(command_id: String, revision: int, status: String) -> void:
	if command_id.is_empty() or not _pending_game_commands.has(command_id):
		return
	var envelope: Dictionary = _pending_game_commands[command_id]
	_pending_game_commands.erase(command_id)
	var latency_ms := int((_now() - float(envelope.get("created_at", _now()))) * 1000.0)
	_network_diag("command_ack", {
		"command_id": command_id,
		"kind": envelope.get("kind", ""),
		"status": status,
		"revision": revision,
		"latency_ms": latency_ms,
	})
	game_command_status.emit(command_id, str(envelope.get("kind", "")), status, latency_ms)


func pending_game_command_count() -> int:
	return _pending_game_commands.size()


func reconcile_pending_game_commands(authority_revision: int, force: bool = false) -> void:
	# A full authority snapshot is the final source of truth. If a command ACK was
	# lost, a newer revision proves that the local pending revision is obsolete;
	# an explicitly requested initial snapshot also ends a failed command cycle.
	for command_id in _pending_game_commands.keys():
		var envelope: Dictionary = _pending_game_commands.get(command_id, {})
		var expected_revision := int(envelope.get("expected_revision", -1))
		if not force and authority_revision <= expected_revision:
			continue
		_pending_game_commands.erase(command_id)
		var kind := str(envelope.get("kind", ""))
		var latency_ms := int((_now() - float(envelope.get("created_at", _now()))) * 1000.0)
		_network_diag("command_reconciled", {
			"command_id": command_id,
			"kind": kind,
			"revision": authority_revision,
			"forced": force,
		})
		game_command_status.emit(command_id, kind, "resynced", latency_ms)


func set_next_authority_ack(command_id: String, status: String) -> void:
	_next_authority_ack = {"command_id": command_id, "status": status}


func broadcast_authority_state(state: Dictionary) -> void:
	var command_id := str(_next_authority_ack.get("command_id", ""))
	var status := str(_next_authority_ack.get("status", "snapshot"))
	_next_authority_ack.clear()
	rpc_authority_state.rpc(state, command_id, status)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_game_intent(command_id: String, expected_revision: int, claimed_player: int, kind: String, payload: Dictionary) -> void:
	if not _allow_room_message("intent"):
		return
	if command_id.is_empty() or command_id.length() > 96 or not _accept_remote_intent(claimed_player):
		return
	if kind not in ["summon", "summon_skill", "attack", "activate_skill", "end_turn", "discard", "move"]:
		return
	if is_online and is_authority():
		rpc_id(multiplayer.get_remote_sender_id(), "rpc_game_command_receipt", command_id)
	if _received_game_commands.has(command_id):
		_network_diag("duplicate_command_dropped", {"command_id": command_id, "kind": kind})
	else:
		_received_game_commands[command_id] = true
		if _received_game_commands.size() > RECEIVED_COMMAND_CACHE_SIZE:
			_received_game_commands.erase(_received_game_commands.keys()[0])
	EventBus.rpc_game_intent_received.emit(kind, payload, claimed_player, command_id, expected_revision)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_game_command_receipt(command_id: String) -> void:
	if not _pending_game_commands.has(command_id):
		return
	var envelope: Dictionary = _pending_game_commands[command_id]
	var now := _now()
	envelope["received_at"] = now
	envelope["retry_at"] = now + COMMAND_RECEIPT_TIMEOUT
	_pending_game_commands[command_id] = envelope
	var latency_ms := int((now - float(envelope.get("created_at", now))) * 1000.0)
	_network_diag("command_received", {"command_id": command_id, "kind": envelope.get("kind", ""), "latency_ms": latency_ms})
	game_command_status.emit(command_id, str(envelope.get("kind", "")), "received", latency_ms)


@rpc("any_peer", "call_remote", "reliable", 1)
func _remote_start_game():
	game_started.emit()


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_summon(hand_index: int, slot_index: int, player: int):
	EventBus.rpc_summon_received.emit(hand_index, slot_index, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	EventBus.rpc_summon_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_attack(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_attack_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_activate_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	EventBus.rpc_activate_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_end_turn(player: int):
	EventBus.rpc_end_turn_received.emit(player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_discard(location: String, index: int, player: int):
	EventBus.rpc_discard_received.emit(location, index, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_move_card(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_move_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func rpc_targeting_arrow(source_slot: int, target_slot: int, player: int):
	EventBus.rpc_targeting_arrow_received.emit(source_slot, target_slot, player)


# ============================================
# Player ready RPC
# ============================================

@rpc("any_peer", "call_remote", "reliable", 1)
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
		if card_index < 0 or bytes.is_empty():
			continue
		var chunk_count := maxi(1, int(ceil(float(bytes.size()) / float(ART_CHUNK_BYTES))))
		var checksum: String = _sha256_hex(bytes)
		for chunk_index in range(chunk_count):
			var begin := chunk_index * ART_CHUNK_BYTES
			var finish := mini(begin + ART_CHUNK_BYTES, bytes.size())
			_art_send_queue.append({
				"target": target_peer,
				"card_index": card_index,
				"ext": ext,
				"chunk_index": chunk_index,
				"chunk_count": chunk_count,
				"bytes": bytes.slice(begin, finish),
				"total": total,
				"checksum": checksum,
			})
	_network_diag("art_transfer_queued", {"cards": total, "chunks": _art_send_queue.size()})


func _process_art_send_queue() -> void:
	if _art_send_queue.is_empty() or not is_online:
		return
	for _index in range(mini(ART_CHUNKS_PER_FRAME, _art_send_queue.size())):
		var item: Dictionary = _art_send_queue.pop_front()
		var args := [
			int(item["card_index"]), str(item["ext"]), int(item["chunk_index"]),
			int(item["chunk_count"]), item["bytes"], int(item["total"]), str(item["checksum"]),
		]
		if int(item["target"]) > 0:
			rpc_id(int(item["target"]), "rpc_card_art_chunk", args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		else:
			rpc_card_art_chunk.rpc(args[0], args[1], args[2], args[3], args[4], args[5], args[6])


func _cleanup_art_receive_buffers() -> void:
	if _art_receive_buffers.is_empty():
		return
	var now := _now()
	for key in _art_receive_buffers.keys():
		var buffer: Dictionary = _art_receive_buffers[key]
		if now - float(buffer.get("created_at", now)) > 30.0:
			_art_receive_buffers.erase(key)


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


@rpc("any_peer", "call_remote", "reliable", 3)
func rpc_card_art_manifest(total: int):
	if not _allow_room_message("art") or total < 0 or total > 256:
		return
	EventBus.rpc_card_art_manifest_received.emit(total)


@rpc("any_peer", "call_remote", "reliable", 3)
func rpc_card_art(card_index: int, ext: String, bytes: PackedByteArray, total: int):
	if not _allow_room_message("art") or bytes.size() > ART_CHUNK_BYTES:
		return
	EventBus.rpc_card_art_received.emit(card_index, ext, bytes, total)


@rpc("any_peer", "call_remote", "reliable", 3)
func rpc_card_art_chunk(card_index: int, ext: String, chunk_index: int, chunk_count: int, bytes: PackedByteArray, total: int, checksum: String) -> void:
	if not _allow_room_message("art"):
		return
	if card_index < 0 or chunk_count < 1 or chunk_count > 1024 or chunk_index < 0 or chunk_index >= chunk_count:
		return
	if bytes.size() > ART_CHUNK_BYTES or checksum.length() != 64 or ext.length() > 8:
		return
	var sender := multiplayer.get_remote_sender_id()
	var key := "%d:%d:%s" % [sender, card_index, checksum]
	if not _art_receive_buffers.has(key):
		var chunks: Array = []
		chunks.resize(chunk_count)
		_art_receive_buffers[key] = {
			"chunks": chunks, "received": 0, "ext": ext, "total": total,
			"created_at": _now(), "checksum": checksum,
		}
	var buffer: Dictionary = _art_receive_buffers[key]
	var chunks: Array = buffer["chunks"]
	if chunks.size() != chunk_count:
		_art_receive_buffers.erase(key)
		return
	if chunks[chunk_index] == null:
		chunks[chunk_index] = bytes
		buffer["received"] = int(buffer["received"]) + 1
	buffer["chunks"] = chunks
	_art_receive_buffers[key] = buffer
	if int(buffer["received"]) != chunk_count:
		return
	var assembled := PackedByteArray()
	for chunk in chunks:
		assembled.append_array(chunk as PackedByteArray)
	_art_receive_buffers.erase(key)
	if _sha256_hex(assembled) != checksum:
		_network_diag("art_checksum_failed", {"card_index": card_index, "bytes": assembled.size()})
		return
	EventBus.rpc_card_art_received.emit(card_index, ext, assembled, total)


@rpc("any_peer", "call_remote", "reliable", 3)
func rpc_card_art_ack(card_index: int, total: int):
	if not _allow_room_message("art"):
		return
	EventBus.rpc_card_art_ack_received.emit(card_index, total)


# P2P battle splash trigger: the authority broadcasts which card just acted so the
# opponent shows the same splash art (or text fallback) animation.
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func rpc_splash(player: int, slot_index: int):
	EventBus.rpc_splash_received.emit(player, slot_index)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_initial_state(state: Dictionary):
	EventBus.rpc_initial_state_received.emit(state)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_request_initial_state():
	EventBus.rpc_initial_state_requested.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_authority_state(state: Dictionary, ack_command_id: String, ack_status: String):
	if not _allow_room_message("authority_state"):
		return
	if authority_state_handler.is_valid():
		authority_state_handler.call(multiplayer.get_remote_sender_id(), state)
	acknowledge_game_command(ack_command_id, int(state.get("state_revision", -1)), ack_status)
	EventBus.rpc_authority_state_received.emit(state)


func send_server_match_snapshot(peer_id: int, state: Dictionary) -> void:
	rpc_id(peer_id, "rpc_server_match_snapshot", state)


@rpc("authority", "call_remote", "reliable", 1)
func rpc_server_match_snapshot(state: Dictionary) -> void:
	pending_server_match_state = state.duplicate(true)
	server_match_snapshot_received.emit(pending_server_match_state)


func take_pending_server_match_state() -> Dictionary:
	var state := pending_server_match_state.duplicate(true)
	pending_server_match_state = {}
	return state


func _allow_room_message(kind: String) -> bool:
	if room_message_guard.is_valid():
		return bool(room_message_guard.call(multiplayer.get_remote_sender_id(), kind))
	return true


# Reconnect recovery is deliberately independent of P1 authority. Whichever
# player stayed connected owns the surviving in-memory snapshot and can return
# it to the stable P1/P2 slot that rejoined.
@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_request_resume_state(requesting_player: int, known_revision: int, nonce: String):
	if not _allow_room_message("resume"):
		return
	if nonce.is_empty() or not _accept_remote_player_claim(requesting_player):
		return
	EventBus.rpc_resume_state_requested.emit(requesting_player, known_revision, nonce)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_resume_state(state: Dictionary, source_player: int, target_player: int, nonce: String):
	if not _allow_room_message("resume"):
		return
	if nonce.is_empty() or target_player != player_number or not _accept_remote_player_claim(source_player):
		return
	EventBus.rpc_resume_state_received.emit(state, source_player, target_player, nonce)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_resume_state_ack(player: int, revision: int, nonce: String):
	if not _allow_room_message("resume"):
		return
	if nonce.is_empty() or not _accept_remote_player_claim(player):
		return
	EventBus.rpc_resume_state_ack_received.emit(player, revision, nonce)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_resume_complete(revision: int, source_player: int, nonce: String):
	if not _allow_room_message("resume"):
		return
	if nonce.is_empty() or not _accept_remote_player_claim(source_player):
		return
	EventBus.rpc_resume_complete_received.emit(revision, nonce)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_summon(hand_index: int, slot_index: int, player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_summon_received.emit(hand_index, slot_index, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_summon_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_attack(source_slot: int, target_slot: int, player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_attack_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_activate_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_activate_skill_received.emit(slot_index, skill_index, target_slot, player)



@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_end_turn(player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_end_turn_received.emit(player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_discard(location: String, index: int, player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_discard_received.emit(location, index, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_move_card(source_slot: int, target_slot: int, player: int):
	if not _allow_room_message("intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_move_received.emit(source_slot, target_slot, player)


# ============================================
# Cleanup
# ============================================

func close_connection():
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_reconnect_active = false
	_reconnect_attempt_running = false
	_reconnect_deadline = 0.0
	_reconnect_retry_at = 0.0
	just_reconnected = false
	_direct_protocol_verified = false
	_connected_emitted = false
	pending_server_match_state = {}
	_pending_game_commands.clear()
	_received_game_commands.clear()
	_next_authority_ack.clear()
	_art_send_queue.clear()
	_art_receive_buffers.clear()
	_heartbeat_active = false
	_last_heartbeat_sent = 0.0
	_last_heartbeat_received = 0.0
	_close_game_peer()
	_close_lobby_peer()
	stop_lan_room_discovery()
	_stop_lan_discovery_responder()
	is_online = false
	is_host = false
	is_dedicated_server = false
	server_allows_card_art = false
	player_number = 0
	opponent_peer_id = 0
	_last_network_phase = "idle"
	_last_disconnect_reason = ""

extends Node

# Reserved recovery interfaces remain available behind this release switch.
const MATCH_RECONNECT_ENABLED := false

# ============================================
# Network manager — ENet P2P RPC layer
# ============================================

signal connected()
signal game_started(match_id: String, starting_player: int)
signal lobby_connected()
signal lobby_connection_failed()
signal game_connection_failed()
signal room_authenticated(player: int, reconnecting: bool)
signal room_host_changed()
signal room_preparation_reset(reason: String)
signal direct_preparation_reset_received()
signal lan_opponent_editing_changed(editing: bool)
signal opponent_disconnected(player: int)
signal reconnect_started()
signal reconnect_transport_ready()
signal reconnect_failed(reason: String)
signal reconnect_progress(elapsed_seconds: int, attempt: int)
signal protocol_mismatch(remote_version: int)
signal server_match_snapshot_received(state: Dictionary)
signal room_command_checkpoint_received(state: Dictionary)
signal room_link_wait_changed()
signal lan_rooms_updated(rooms: Array)
signal game_command_status(command_id: String, kind: String, status: String, latency_ms: int)

const LOBBY_PORT := 4567
const CONNECT_TIMEOUT := 8.0  # seconds before a pending connection is treated as failed
const ROOM_LEAVE_TIMEOUT := 3.0
const MAX_ROOM_DECK_BYTES := 2 * 1024 * 1024
const RECONNECT_WINDOW := 60.0 * 60.0
const RECONNECT_RETRY_BASE := 0.5
const RECONNECT_RETRY_MAX := 8.0
const COMMAND_ACK_TIMEOUT := 1.25
const RECOVERY_COMMAND_RETRY_INTERVAL := 0.4
const COMMAND_RECEIPT_TIMEOUT := 4.0
const COMMAND_TOTAL_TIMEOUT := 8.0
const COMMAND_MAX_SENDS := 4
const ROOM_COMMAND_CHECKPOINT_INTERVAL := 1.0
const ROOM_LINK_PROBE_INTERVAL := 1.0
const ROOM_LINK_PROBE_FALLBACK_DELAY := 1.5
const ROOM_LINK_STALL_SECONDS := 4.25
# Reliable retransmits back off across an outage. Give the ordinary channel
# time to drain after the recovery channel has already confirmed the turn.
const ROOM_ENET_MIN_TIMEOUT_MS := 20000
const RECEIVED_COMMAND_CACHE_SIZE := 512
const RECONCILED_COMMAND_CACHE_SIZE := 64
const ART_CHUNK_BYTES := 24 * 1024
const ART_CHUNKS_PER_FRAME := 2
const SESSION_PATH := "user://active_room.cfg"
const MATCH_SNAPSHOT_PATH := "user://active_match_state.json"
const MATCH_SNAPSHOT_BACKUP_PATH := "user://active_match_state.json.bak"
const MATCH_SNAPSHOT_SCHEMA := 1
const SnapshotStore = preload("res://MatchSnapshotStore.gd")
const SnapshotWire = preload("res://BattleSnapshotWire.gd")
const SessionStore = preload("res://RoomSessionStore.gd")
const ProtocolGuard = preload("res://NetworkProtocolGuard.gd")
const HEARTBEAT_INTERVAL := 2.0  # seconds between heartbeat sends
const HEARTBEAT_TIMEOUT := 7.0  # seconds without receiving heartbeat before declaring disconnect
const LAN_GAME_PORT := 4568
const LAN_DISCOVERY_PORT := 4569
const PARTY_DISCOVERY_PORT := 4570
const DEFAULT_LOBBY_ADDRESS := "103.236.54.24"
const LAN_DISCOVERY_INTERVAL := 1.0
const LAN_ROOM_TTL := 3.5
const LAN_DISCOVERY_MAGIC := "CARD_UGC_LAN_V1"
const GAME_CHANNEL_COUNT := 5
const BATTLE_CHAT_PHRASES := ["hello", "bye", "here", "oh_no", "well_played", "wait", "your_turn", "good_game"]
const BATTLE_CHAT_COOLDOWN_MS := 1200
const BATTLE_CHAT_HELLO := 255
const BATTLE_CHAT_ACK := 254
const _BATTLE_CHAT_MAGIC := "CXQ1"
const _BATTLE_CURSOR_MAGIC := "CXP1"
const _CURSOR_GRID := 4096.0
const CURSOR_HIDDEN := Vector2(-1, -1)
const SESSION_MODE_ROOM := "room"
const SESSION_MODE_LAN_HOST := "lan_host"
const SESSION_MODE_LAN_CLIENT := "lan_client"
const SESSION_MODE_BETA := "beta_https"
const SESSION_MODE_CLOUDFLARE := "cloudflare_https"
const BetaPeer = preload("res://BetaRelayPeer.gd")
var _beta_instance := ""
var _beta_keep_instance := false

var peer: MultiplayerPeer
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
var battle_match_id := ""
var match_opening_player := 0
var room_preparation_available := false
var room_preparation_generation := 0
var _returning_to_room := false
var room_departure_pending := false
var room_wait_reason := ""
var room_host_transfer_pending := false
var lan_opponent_editing := false
var lan_room_return_pending := false
var _lan_rematch_supported := false
var _lan_host_match_finished := false
var _lan_local_returned := false
var _lan_opponent_returned := false
var _lan_room_editing := false
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
var room_command_checkpoint_handler: Callable
var room_message_guard: Callable
var room_battle_chat_handler: Callable
signal battle_chat_received(phrase: int)
var room_battle_cursor_handler: Callable
signal battle_cursor_received(point: Vector2)
var _next_battle_chat_at := 0
var _next_incoming_battle_chat_at := 0
var _next_battle_chat_probe_at := 0
var _battle_chat_transport: MultiplayerPeer
var battle_chat_supported := false
var room_control_handler: Callable

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
var _reconciled_game_commands: Dictionary = {}
var _timed_out_checkpoint: Dictionary = {}
var _next_command_resync_at := 0.0
var _next_command_checkpoint_at := 0.0
var _room_link_stalled := false
var _room_link_waiting := false
var _last_room_link_reply := 0.0
var _next_room_link_probe := 0.0
var _received_game_commands: Dictionary = {}
var _next_authority_ack: Dictionary = {}
var _art_send_queue: Array[Dictionary] = []
var _art_receive_buffers: Dictionary = {}
var _last_network_phase: String = "idle"
var _last_disconnect_reason: String = ""
var _lan_discovery_responder: PacketPeerUDP
var _lan_discovery_scanner: PacketPeerUDP
var _lan_discovery_next_query: float = 0.0
var _lan_discovery_scan_port := LAN_DISCOVERY_PORT
var _party_discovery_game_port := 0
var _lan_discovered_rooms: Dictionary = {}
var team_room: Node


func _ready() -> void:
	# A local card test may pause its scene while the room transport stays alive.
	process_mode = Node.PROCESS_MODE_ALWAYS
	team_room = load("res://TeamRoom.gd").new()
	team_room.name = "TeamRoom"
	add_child(team_room)
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
	battle_match_id = ""
	_reset_room_link()
	var old_peer := peer
	peer = null
	if old_peer:
		if multiplayer.multiplayer_peer == old_peer:
			multiplayer.multiplayer_peer = null
		old_peer.close()


func _close_lobby_peer() -> void:
	_lobby_status_callback = Callable()
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
	_process_room_link(_now())
	_process_pending_game_commands()
	_process_art_send_queue()
	_cleanup_art_receive_buffers()


func _network_diag(event: String, details: Dictionary = {}) -> void:
	var fields := {
		"event": event,
		"unix_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
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
	return session_mode == SESSION_MODE_ROOM and room_server_address != "" and room_server_address != CloudRelayConfig.RETIRED_ENET_ADDRESS and room_server_port > 0 and room_code != "" and room_player_number in [1, 2] and reconnect_token != ""


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
	return has_saved_room_session() or has_saved_lan_session() or has_saved_beta_session() or has_saved_cloud_session()


func has_saved_beta_session() -> bool:
	return session_mode == SESSION_MODE_BETA and BetaRelayConfig.valid_code(room_code) and room_player_number in [1, 2] and reconnect_token.length() == 64 and (room_server_address == BetaRelayConfig.DEFAULT_URL or (OS.is_debug_build() and room_server_address == BetaRelayConfig.server_url()))


func connect_beta_room(address: String, code: String, token: String, assigned_player: int) -> void:
	_configure_http_room(address, code, token, assigned_player, SESSION_MODE_BETA)


func has_saved_cloud_session() -> bool:
	return session_mode == SESSION_MODE_CLOUDFLARE and CloudRelayConfig.accepts_saved_url(room_server_address) and BetaRelayConfig.valid_code(room_code) and room_player_number in [1, 2] and reconnect_token.length() == 64


func connect_cloud_room(address: String, code: String, token: String, assigned_player: int) -> void:
	if not CloudRelayConfig.accepts_saved_url(address) or not BetaRelayConfig.valid_code(code) or token.length() != 64 or assigned_player not in [1, 2]:
		return
	_configure_http_room(address, code, token, assigned_player, SESSION_MODE_CLOUDFLARE)


func _configure_http_room(address: String, code: String, token: String, assigned_player: int, mode: String) -> void:
	close_connection()
	clear_room_session()
	room_server_address = address
	room_server_port = 443
	room_code = code
	room_player_number = assigned_player
	reconnect_token = token
	session_mode = mode
	session_id = ("BETA:" if mode == SESSION_MODE_BETA else "CF:") + code
	_beta_instance = ""
	server_allows_card_art = true
	_save_room_session()
	_create_beta_peer()


func _create_beta_peer() -> void:
	is_dedicated_server = false
	is_host = room_player_number == 1
	player_number = room_player_number
	is_online = true
	_direct_protocol_verified = false
	_connected_emitted = false
	if _beta_instance.is_empty():
		_beta_instance = Crypto.new().generate_random_bytes(16).hex_encode()
	var transport := BetaPeer.new()
	transport.setup(self, room_server_address, room_code, reconnect_token, player_number, _beta_instance)
	peer = transport
	multiplayer.multiplayer_peer = peer
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
	if not multiplayer.peer_packet.is_connected(_on_peer_packet):
		multiplayer.peer_packet.connect(_on_peer_packet)
	_last_network_phase = "beta_connecting"
	# Hosts may wait in an empty room. The HTTP peer owns transport timeouts.
	_game_deadline = 0.0


func leave_beta_room() -> void:
	if not has_saved_beta_session() and not has_saved_cloud_session():
		return
	var request := HTTPRequest.new()
	request.timeout = 5.0
	add_child(request)
	request.request_completed.connect(func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray): request.queue_free())
	if request.request(room_server_address + "/api/rooms/" + room_code + "/leave", ["Authorization: Bearer " + reconnect_token, "Content-Type: application/json"], HTTPClient.METHOD_POST, "{}") != OK:
		request.queue_free()


func has_resumable_match_session() -> bool:
	return MATCH_RECONNECT_ENABLED and has_saved_match_session() and room_match_started


static func roll_opening_player() -> int:
	return 1 + (Crypto.new().generate_random_bytes(1)[0] & 1)


func mark_room_match_started(match_id: String = "") -> void:
	mark_match_started(match_id)


func mark_match_started(match_id: String = "", starting_player: int = 0) -> void:
	if not has_saved_match_session():
		return
	if battle_match_id != match_id:
		_reset_battle_chat()
	battle_match_id = match_id
	match_opening_player = starting_player
	room_match_started = true
	_reset_room_link()
	_last_room_link_reply = _now()
	enable_match_relay_polling()
	_save_room_session()


func enable_match_relay_polling() -> void:
	if peer is BetaPeer:
		peer.set_match_active()


func clear_room_session() -> void:
	clear_match_snapshot()
	room_host_transfer_pending = false
	battle_match_id = ""
	match_opening_player = 0
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
	var game_peer := ENetMultiplayerPeer.new()
	peer = game_peer
	var err = game_peer.create_server(port, 1, GAME_CHANNEL_COUNT)
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


func has_live_lan_room() -> bool:
	return session_mode in [SESSION_MODE_LAN_HOST, SESSION_MODE_LAN_CLIENT] and is_online and peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _can_keep_lan_waiting_room() -> bool:
	return session_mode == SESSION_MODE_LAN_HOST and has_live_lan_room() and (not room_match_started or _lan_host_match_finished or _lan_local_returned)


func lan_room_preparation_paused() -> bool:
	return _lan_room_editing or lan_opponent_editing or _lan_local_returned


func can_return_to_lan_room() -> bool:
	if has_vacant_lan_room_after_match():
		return true
	return (
		_lan_rematch_supported
		and _direct_protocol_verified
		and room_match_started
		and valid_battle_match_id(battle_match_id)
		and has_live_lan_room()
		and is_game_rpc_ready(opponent_peer_id)
	)


func has_vacant_lan_room_after_match() -> bool:
	return _lan_host_match_finished and opponent_peer_id == 0 and has_live_lan_room() and session_mode == SESSION_MODE_LAN_HOST


func mark_lan_match_finished() -> void:
	if session_mode == SESSION_MODE_LAN_HOST and can_return_to_lan_room():
		_lan_host_match_finished = true


func arrive_in_lan_room() -> void:
	if not can_return_to_lan_room():
		return
	if opponent_peer_id == 0:
		_clear_lan_finished_match()
		return
	_lan_local_returned = true
	room_wait_reason = "returning"
	# Return and Ready use the same ordered channel, so the other lobby always
	# sees our arrival before it can receive our new deck or rule messages.
	rpc_player_ready.rpc_id(opponent_peer_id, [], battle_match_id)
	_finish_lan_return()


func _finish_lan_return() -> void:
	if not _lan_local_returned or not _lan_opponent_returned:
		return
	_clear_lan_finished_match()
	room_wait_reason = ""


func _clear_lan_finished_match() -> void:
	if _lan_host_match_finished and has_live_lan_room():
		peer.refuse_new_connections = false
	_lan_host_match_finished = false
	_lan_local_returned = false
	_lan_opponent_returned = false
	room_match_started = false
	battle_match_id = ""
	match_opening_player = 0
	_clear_outgoing_game_commands()
	_received_game_commands.clear()
	_next_authority_ack.clear()
	_next_command_resync_at = 0.0
	clear_room_art_transfers()
	clear_match_snapshot()
	_save_room_session()


func set_lan_room_editing(editing: bool) -> bool:
	if not has_live_lan_room() or room_match_started or lan_room_return_pending:
		return false
	if editing == _lan_room_editing:
		return true
	if opponent_peer_id > 0 and is_game_rpc_ready(opponent_peer_id):
		if rpc_id(opponent_peer_id, "rpc_lan_room_editing", editing) != OK:
			return false
		if not editing:
			# Wait for the peer to finish processing any readiness messages
			# sent before seeing us enter the editor.
			lan_room_return_pending = true
			return true
	_lan_room_editing = editing
	return true


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_lan_room_editing(editing: bool, return_ack: bool = false) -> void:
	if not has_live_lan_room() or room_match_started or not _direct_protocol_verified or multiplayer.get_remote_sender_id() != opponent_peer_id:
		return
	if return_ack:
		if not editing and lan_room_return_pending:
			lan_room_return_pending = false
			_lan_room_editing = false
		return
	if lan_opponent_editing != editing:
		lan_opponent_editing = editing
		lan_opponent_editing_changed.emit(editing)
	if not editing:
		rpc_lan_room_editing.rpc_id(opponent_peer_id, false, true)


func _create_lan_client(address: String, port: int) -> int:
	is_dedicated_server = false
	var game_peer := ENetMultiplayerPeer.new()
	peer = game_peer
	var err = game_peer.create_client(address, port, GAME_CHANNEL_COUNT)
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


func start_lan_room_discovery(party: bool = false) -> int:
	stop_lan_room_discovery()
	_lan_discovery_scanner = PacketPeerUDP.new()
	var err := _lan_discovery_scanner.bind(0, "*")
	if err != OK:
		_lan_discovery_scanner = null
		return err
	_lan_discovery_scanner.set_broadcast_enabled(true)
	_lan_discovery_scan_port = PARTY_DISCOVERY_PORT if party else LAN_DISCOVERY_PORT
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


func _start_lan_discovery_responder(party_game_port: int = 0) -> void:
	_stop_lan_discovery_responder()
	_lan_discovery_responder = PacketPeerUDP.new()
	_party_discovery_game_port = party_game_port
	var err := _lan_discovery_responder.bind(PARTY_DISCOVERY_PORT if party_game_port > 0 else LAN_DISCOVERY_PORT, "*")
	if err != OK:
		_network_diag("lan_discovery_bind_failed", {"error": err})
		_lan_discovery_responder = null


func _stop_lan_discovery_responder() -> void:
	if _lan_discovery_responder:
		_lan_discovery_responder.close()
	_lan_discovery_responder = null
	_party_discovery_game_port = 0


func _process_lan_discovery() -> void:
	if _lan_discovery_responder:
		while _lan_discovery_responder.get_available_packet_count() > 0:
			var request := _decode_lan_discovery_packet(_lan_discovery_responder.get_packet())
			var source_ip := _lan_discovery_responder.get_packet_ip()
			var source_port := _lan_discovery_responder.get_packet_port()
			var party := _party_discovery_game_port > 0
			var available: bool = (team_room.is_host() and not team_room.started and team_room.occupied.size() < team_room.seat_count) if party else (not room_match_started and opponent_peer_id == 0)
			if str(request.get("kind", "")) == "query" and int(request.get("protocol", -1)) == AppVersion.PROTOCOL_VERSION and available:
				var port := _party_discovery_game_port if party else room_server_port
				var response := _encode_lan_discovery_packet({"kind": "room", "name": OS.get_environment("COMPUTERNAME"), "port": port, "protocol": AppVersion.PROTOCOL_VERSION})
				_lan_discovery_responder.set_dest_address(source_ip, source_port)
				_lan_discovery_responder.put_packet(response)
	if not _lan_discovery_scanner:
		return
	var now := _now()
	if now >= _lan_discovery_next_query:
		_lan_discovery_next_query = now + LAN_DISCOVERY_INTERVAL
		var query := _encode_lan_discovery_packet({"kind": "query", "protocol": AppVersion.PROTOCOL_VERSION})
		_lan_discovery_scanner.set_dest_address("255.255.255.255", _lan_discovery_scan_port)
		_lan_discovery_scanner.put_packet(query)
		# Also probe loopback so two local instances (and automated tests) work
		# even when the OS suppresses broadcast loopback.
		_lan_discovery_scanner.set_dest_address("127.0.0.1", _lan_discovery_scan_port)
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
		var room_name := str(response.get("name", "LAN Host"))
		var previous: Dictionary = _lan_discovered_rooms.get(key, {})
		if previous.is_empty() or previous["name"] != room_name:
			changed = true
		_lan_discovered_rooms[key] = {"address": address, "port": port, "name": room_name, "seen_at": now}
	for key in _lan_discovered_rooms.keys():
		if now - float(_lan_discovered_rooms[key].get("seen_at", 0.0)) > LAN_ROOM_TTL:
			_lan_discovered_rooms.erase(key)
			changed = true
	if changed:
		var rooms: Array = _lan_discovered_rooms.values()
		rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["name"] != b["name"]:
				return a["name"] < b["name"]
			if a["address"] != b["address"]:
				return a["address"] < b["address"]
			return a["port"] < b["port"]
		)
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

func connect_to_lobby(server_ip: String, callback: Callable, port: int = LOBBY_PORT) -> int:
	# This retired IP may be reassigned after the owner's Aliyun release.
	if server_ip == CloudRelayConfig.RETIRED_ENET_ADDRESS:
		return ERR_UNAVAILABLE
	disconnect_from_lobby()
	if not is_valid_address(server_ip):
		return ERR_INVALID_PARAMETER
	is_dedicated_server = true
	is_host = false
	_lobby_callback = callback
	_lobby_peer = ENetMultiplayerPeer.new()
	var err = _lobby_peer.create_client(server_ip, port)
	if err != OK:
		_lobby_peer = null
		return err
	multiplayer.multiplayer_peer = _lobby_peer
	is_online = true
	_lobby_peer.peer_connected.connect(_on_lobby_connected.bind(_lobby_peer))
	_lobby_peer.peer_disconnected.connect(_on_lobby_disconnected.bind(_lobby_peer))
	_lobby_deadline = _now() + CONNECT_TIMEOUT
	print("Connecting to lobby at %s:%d" % [server_ip, port])
	return OK


func create_room(code: String) -> void:
	if not is_valid_room_code(code):
		push_warning("create_room called with invalid room code")
		return
	_lobby_request({"action": "create", "code": code})


func join_room(code: String, attempt_id: String = "") -> void:
	if not is_valid_room_code(code):
		push_warning("join_room called with invalid room code")
		return
	var request := {"action": "join", "code": code}
	if not attempt_id.is_empty():
		request["attempt_id"] = attempt_id
	_lobby_request(request)


func reconnect_room(code: String, assigned_player: int, token: String) -> void:
	if not MATCH_RECONNECT_ENABLED: return
	_lobby_request({
		"action": "reconnect",
		"code": code,
		"player": assigned_player,
		"reconnect_token": token,
	})


func request_lobby_status(callback: Callable) -> void:
	_lobby_status_callback = callback
	_lobby_request({"action": "status"})


func request_party_room(code: String, seats: int, create: bool) -> void:
	_lobby_request({"action": "party_create" if create else "party_join", "code": code, "seats": seats})


func request_matchmaking(action: String, mode: String, proof: Dictionary = {}) -> void:
	_lobby_request({"action": "matchmaking_" + action, "mode": mode, "proof": proof,
		"pack_protocol": preload("res://MatchmakingQueue.gd").PACK_PROTOCOL})


func _lobby_request(data: Dictionary) -> void:
	_lobby_deadline = _now() + CONNECT_TIMEOUT
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
func notify_room_ready(generation: int = 1) -> void:
	# Broadcast by the room subprocess (peer 1) once both players are connected.
	# Drives the same "opponent connected" path used by direct P2P.
	is_online = true
	room_preparation_generation = generation
	room_preparation_available = true
	room_wait_reason = ""
	room_host_transfer_pending = false
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


func send_room_auth_result(peer_id: int, accepted: bool, assigned_player: int, status: String, reconnecting: bool) -> void:
	rpc_id(peer_id, "rpc_room_auth_result", accepted, assigned_player, status, reconnecting)


@rpc("authority", "call_remote", "reliable", 0)
func rpc_room_auth_result(accepted: bool, assigned_player: int, status: String, reconnecting: bool) -> void:
	_game_deadline = 0.0
	if not accepted:
		if _reconnect_active:
			if status in ["invalid_token", "invalid_reconnect"]:
				_finish_reconnect_failure(status, true)
			elif status == "protocol_mismatch":
				_finish_reconnect_failure(status)
			else:
				_schedule_reconnect_retry(status)
		else:
			_fail_game_connection(status)
		return

	player_number = assigned_player
	room_player_number = assigned_player
	is_online = true
	if status in ["returning", "syncing_preparation", "editing"]:
		room_wait_reason = status
		room_preparation_available = false
		opponent_peer_id = 1
	if peer is ENetMultiplayerPeer:
		peer.get_peer(1).set_timeout(32, ROOM_ENET_MIN_TIMEOUT_MS, 30000)
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
func notify_player_disconnected(disconnected_player: int, left_by_choice: bool) -> void:
	if disconnected_player == player_number:
		return
	_reset_battle_chat()
	if not MATCH_RECONNECT_ENABLED:
		battle_match_id = ""
		room_match_started = false
		_reset_room_link()
		_clear_outgoing_game_commands()
	opponent_peer_id = 0
	room_preparation_available = false
	room_preparation_generation = 0
	room_wait_reason = "opponent_left" if left_by_choice else "opponent_connection_lost"
	_heartbeat_active = false
	_last_heartbeat_received = 0.0
	is_online = true
	opponent_disconnected.emit(disconnected_player)


@rpc("authority", "call_remote", "reliable", 0)
func notify_room_host_changed(token: String) -> void:
	if not is_dedicated_server or token.is_empty(): return
	player_number = 1
	room_player_number = 1
	last_game_player_number = 1
	room_host_transfer_pending = true
	reconnect_token = token
	room_match_started = false
	just_reconnected = false
	clear_match_snapshot()
	_save_room_session()
	room_host_changed.emit()


func has_live_server_room() -> bool:
	return is_dedicated_server and session_mode == SESSION_MODE_ROOM and is_game_rpc_ready(1)


func leave_online_room() -> bool:
	if room_departure_pending:
		return false
	if has_live_server_room() and rpc_id(1, "rpc_room_control", "leave", []) == OK:
		var departing_peer := peer
		room_departure_pending = true
		var deadline := _now() + ROOM_LEAVE_TIMEOUT
		while room_departure_pending and has_live_server_room() and _now() < deadline:
			await get_tree().process_frame
		if peer != departing_peer and peer != null:
			return false
	close_connection()
	clear_room_session()
	return true


func return_to_server_room() -> bool:
	if room_departure_pending or not has_live_server_room():
		return false
	_returning_to_room = true
	room_preparation_available = false
	if opponent_peer_id > 0:
		room_wait_reason = "returning"
	elif room_wait_reason != "opponent_connection_lost":
		room_wait_reason = "opponent_left"
	room_match_started = false
	battle_match_id = ""
	match_opening_player = 0
	# The waiting room uses the same transport and must retain its last link state.
	just_reconnected = false
	pending_server_match_state.clear()
	_clear_outgoing_game_commands()
	_received_game_commands.clear()
	_next_authority_ack.clear()
	_next_command_resync_at = 0.0
	_next_command_checkpoint_at = 0.0
	clear_match_snapshot()
	_save_room_session()
	return true


func arrive_in_server_room() -> void:
	if _returning_to_room and has_live_server_room():
		_returning_to_room = false
		if room_wait_reason == "editing":
			room_wait_reason = ""
		rpc_room_control.rpc_id(1, "return", [])


func edit_card_from_server_room() -> bool:
	if _room_link_waiting or room_wait_reason == "returning" or not has_live_server_room() or rpc_id(1, "rpc_room_control", "edit", []) != OK:
		return false
	_returning_to_room = true
	room_preparation_available = false
	return true


@rpc("any_peer", "call_remote", "reliable", 0)
func rpc_room_control(action: String, data: Array, generation: int = 0) -> void:
	if room_control_handler.is_valid():
		room_control_handler.call(multiplayer.get_remote_sender_id(), action, data, generation)
	elif action == "lan_rematch_supported" and has_live_lan_room() and multiplayer.get_remote_sender_id() == opponent_peer_id:
		_lan_rematch_supported = true


func send_room_preparation(action: String, data: Array = []) -> Error:
	return rpc_id(1, "rpc_room_control", action, data, room_preparation_generation)


@rpc("authority", "call_remote", "reliable", 0)
func notify_room_preparation_reset(reason: String, generation: int) -> void:
	if not has_live_server_room():
		return
	if reason == "left":
		room_departure_pending = false
		_network_diag("room_leave_confirmed")
		return
	room_preparation_generation = generation
	room_wait_reason = reason
	if reason == "editing":
		room_preparation_available = false
	clear_room_art_transfers()
	room_preparation_reset.emit(reason)


@rpc("authority", "call_remote", "reliable", 0)
func notify_room_deck_ready(cards: Array) -> void:
	if has_live_server_room() and room_preparation_available:
		EventBus.rpc_ready_received.emit(cards)


func clear_room_art_transfers() -> void:
	_art_send_queue.clear()
	_art_receive_buffers.clear()


@rpc("authority", "call_remote", "reliable", 0)
func notify_room_match_started(match_id: String, starting_player: int) -> void:
	if not has_live_server_room() or not room_preparation_available or not valid_battle_match_id(match_id) or starting_player not in [1, 2]:
		return
	room_preparation_available = false
	room_preparation_generation = 0
	game_started.emit(match_id, starting_player)


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


func last_game_connection_failure() -> String:
	return _last_disconnect_reason


func _fail_game_connection(reason: String = "room_timeout") -> void:
	_last_disconnect_reason = reason
	_last_network_phase = "failed"
	_network_diag("room_connection_failed", {"reason": reason})
	_close_game_peer()
	is_online = false
	if _reconnect_active:
		_schedule_reconnect_retry(reason)
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
	_lobby_deadline = 0.0
	var remote_protocol := int(data.get("protocol", AppVersion.PROTOCOL_VERSION))
	if remote_protocol != AppVersion.PROTOCOL_VERSION:
		data["status"] = "protocol_mismatch"
		data["remote_protocol"] = remote_protocol
		protocol_mismatch.emit(remote_protocol)
	if _lobby_status_callback.is_valid():
		var callback := _lobby_status_callback
		_lobby_status_callback = Callable()
		callback.call(data)
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
	_last_disconnect_reason = ""
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
	room_preparation_available = false
	room_preparation_generation = 0
	var game_peer := ENetMultiplayerPeer.new()
	peer = game_peer
	var err = game_peer.create_client(address, port, GAME_CHANNEL_COUNT)
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
	if not MATCH_RECONNECT_ENABLED:
		_heartbeat_active = false
		_close_game_peer()
		is_online = false
		opponent_peer_id = 0
		room_match_started = false
		_clear_outgoing_game_commands()
		opponent_disconnected.emit(0)
		return
	if not has_saved_match_session():
		_finish_reconnect_failure("no_saved_session", true)
		return
	if _reconnect_active:
		return
	if session_mode in [SESSION_MODE_BETA, SESSION_MODE_CLOUDFLARE]:
		if not _beta_keep_instance:
			_beta_instance = Crypto.new().generate_random_bytes(16).hex_encode()
		_beta_keep_instance = false

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
	if session_mode in [SESSION_MODE_BETA, SESSION_MODE_CLOUDFLARE]:
		_last_network_phase = "reconnect_beta"
		_create_beta_peer()
		return
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

func _on_peer_connected(id: int, source_peer: MultiplayerPeer):
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
	_reset_battle_chat()
	opponent_peer_id = id
	_lan_rematch_supported = false
	_direct_protocol_verified = false
	_connected_emitted = false
	rpc_id(id, "rpc_protocol_hello", AppVersion.PROTOCOL_VERSION, player_number, session_id)
	if has_live_lan_room():
		rpc_room_control.rpc_id(id, "lan_rematch_supported", [])
	if _lan_room_editing:
		rpc_lan_room_editing.rpc_id(id, true)
	print("Opponent connected: %d" % id)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_protocol_hello(version: int, claimed_player: int, remote_session_id: String = "") -> void:
	if is_dedicated_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	var lan_room := has_live_lan_room()
	if lan_room and (sender <= 0 or sender != opponent_peer_id or _direct_protocol_verified):
		return
	if version != AppVersion.PROTOCOL_VERSION:
		protocol_mismatch.emit(version)
		if lan_room:
			if is_host:
				room_wait_reason = "incompatible_guest"
			# Let each side receive the already queued version notice before leaving.
			peer.get_peer(sender).peer_disconnect_later()
			return
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
	if session_mode == SESSION_MODE_LAN_HOST and room_wait_reason in ["opponent_left", "incompatible_guest"]:
		room_wait_reason = ""
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


func _on_peer_disconnected(id: int, source_peer: MultiplayerPeer):
	if source_peer != peer:
		return
	if source_peer is BetaPeer:
		var reason: String = source_peer.failure_reason
		_beta_keep_instance = reason == "generation_changed"
		if not has_resumable_match_session() or reason in ["room_expired", "unauthorized", "protocol_mismatch", "private_site"]:
			_last_disconnect_reason = reason
			_heartbeat_active = false
			_close_game_peer()
			is_online = false
			if _reconnect_active or has_resumable_match_session():
				_reconnect_active = true
				_finish_reconnect_failure(reason, reason in ["room_expired", "unauthorized"])
			else:
				game_connection_failed.emit()
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
	var keep_lan_room := _can_keep_lan_waiting_room() and id == opponent_peer_id
	print("Opponent disconnected")
	opponent_peer_id = 0
	_heartbeat_active = false
	_last_heartbeat_received = 0.0
	if keep_lan_room:
		if _lan_local_returned:
			_clear_lan_finished_match()
		elif _lan_host_match_finished:
			# Keep the same listener, but reopen admissions when the host returns.
			peer.refuse_new_connections = true
		_direct_protocol_verified = false
		_connected_emitted = false
		lan_opponent_editing = false
		if lan_room_return_pending:
			_lan_room_editing = false
			lan_room_return_pending = false
		clear_room_art_transfers()
		if room_wait_reason != "incompatible_guest":
			room_wait_reason = "opponent_left"
		_last_network_phase = "direct_host_waiting"
		opponent_disconnected.emit(0)
		return
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
	if data.size() == 2 and data.get_string_from_ascii() == _HEARTBEAT_MAGIC:
		_last_heartbeat_received = _now()
	elif data.size() == 17 and data.slice(0, 4).get_string_from_ascii() == _BATTLE_CHAT_MAGIC:
		_receive_battle_chat(peer_id, data.slice(4, 16).hex_encode(), data[16])
	elif data.size() == 20 and data.slice(0, 4).get_string_from_ascii() == _BATTLE_CURSOR_MAGIC:
		_receive_battle_cursor(peer_id, data)


func _on_opponent_vanished() -> void:
	print("Opponent vanished (heartbeat timeout or no disconnect signal) - treating as disconnected")
	_heartbeat_active = false
	if _can_keep_lan_waiting_room() and multiplayer.get_peers().has(opponent_peer_id):
		# Retire this guest. ENet emits its disconnect on the next poll.
		var guest: ENetPacketPeer = peer.get_peer(opponent_peer_id)
		peer.disconnect_peer(opponent_peer_id)
		guest.reset()
		return
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


func room_link_waiting() -> bool:
	return _room_link_waiting


func _reset_room_link() -> void:
	_room_link_stalled = false
	_room_link_waiting = false
	_last_room_link_reply = 0.0
	_next_room_link_probe = 0.0


func _process_room_link(now: float) -> void:
	if _game_deadline > 0.0 or not has_live_server_room():
		return
	if _last_room_link_reply <= 0.0:
		_last_room_link_reply = now
	var reply_age := now - _last_room_link_reply
	if now >= _next_room_link_probe:
		_next_room_link_probe = now + ROOM_LINK_PROBE_INTERVAL
		var sent_at_ms := Time.get_ticks_msec()
		if room_match_started:
			rpc_room_link_probe.rpc_id(1, battle_match_id, sent_at_ms)
			if reply_age >= ROOM_LINK_PROBE_FALLBACK_DELAY:
				rpc_waiting_room_probe.rpc_id(1, sent_at_ms)
		else:
			rpc_waiting_room_probe.rpc_id(1, sent_at_ms)
			if reply_age >= ROOM_LINK_PROBE_FALLBACK_DELAY:
				# Keep sampling while the reliable lane catches up after an outage.
				rpc_room_link_probe.rpc_id(1, "", sent_at_ms)
	var stalled := reply_age >= ROOM_LINK_STALL_SECONDS
	if stalled != _room_link_stalled:
		_room_link_stalled = stalled
		var event := "room_link_interrupted" if stalled else "room_link_restored"
		_network_diag(event if room_match_started else "waiting_" + event, {"room_reply_age_ms": roundi(reply_age * 1000.0)})
		if not stalled:
			for envelope: Dictionary in _pending_game_commands.values():
				envelope["expires_at"] = now + COMMAND_TOTAL_TIMEOUT
				envelope["retry_at"] = now
				envelope["sends"] = 0
				envelope.erase("recovering")
	var waiting := stalled or (_room_link_waiting and not _pending_game_commands.is_empty())
	if waiting != _room_link_waiting:
		_room_link_waiting = waiting
		room_link_wait_changed.emit()


@rpc("any_peer", "call_remote", "unreliable", 0)
func rpc_room_link_probe(match_id: String, sent_at_ms: int) -> void:
	if not room_message_guard.is_valid():
		return
	if match_id.is_empty():
		if not _allow_room_message("waiting_link_recovery"):
			return
	elif not _battle_message_matches(match_id, "link_probe") or not _allow_room_message("link_probe"):
		return
	rpc_room_link_reply.rpc_id(multiplayer.get_remote_sender_id(), match_id, sent_at_ms)


@rpc("authority", "call_remote", "unreliable", 0)
func rpc_room_link_reply(match_id: String, sent_at_ms: int) -> void:
	var expected_id := battle_match_id if room_match_started else ""
	if match_id == expected_id:
		_record_room_link_reply(sent_at_ms)


# The reliable probe verifies the room transport in the lobby and during a
# match. Its channel is separate from deck, card art and gameplay traffic.
@rpc("any_peer", "call_remote", "reliable", 2)
func rpc_waiting_room_probe(sent_at_ms: int) -> void:
	if room_message_guard.is_valid() and _allow_room_message("waiting_link_probe"):
		rpc_waiting_room_reply.rpc_id(multiplayer.get_remote_sender_id(), sent_at_ms)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_waiting_room_reply(sent_at_ms: int) -> void:
	_record_room_link_reply(sent_at_ms)


func _record_room_link_reply(sent_at_ms: int) -> void:
	var age_ms := Time.get_ticks_msec() - sent_at_ms
	if _game_deadline <= 0.0 and has_live_server_room() and age_ms >= 0 and age_ms < ROOM_LINK_STALL_SECONDS * 1000:
		_last_room_link_reply = _now()


# ============================================
# Gameplay command envelope. Reliable ordered channel 1 keeps combat traffic
# independent from connection/auth (channel 0), transient presentation (2), and
# bulk card art (3). Keeping intents and receipts on this established gameplay
# channel also avoids deployment-specific failures seen with higher custom
# channels. command_id makes retries idempotent; expected_revision lets the
# authority reject stale actions and return a fresh snapshot.
# ============================================

func send_game_intent(kind: String, payload: Dictionary, claimed_player: int, expected_revision: int) -> String:
	if not is_game_rpc_ready() or claimed_player not in [1, 2] or _room_link_waiting:
		return ""
	payload = payload.duplicate(true)
	if not _pending_game_commands.is_empty():
		payload["after_move"] = _pending_game_commands.keys().back()
	_command_sequence += 1
	var command_id := "%d-%d-%d" % [claimed_player, Time.get_ticks_usec(), _command_sequence]
	var now := _now()
	var envelope := {
		"match_id": battle_match_id,
		"kind": kind,
		"payload": payload,
		"player": claimed_player,
		"expected_revision": expected_revision,
		"after_move": str(payload.get("after_move", "")),
		"sends": 1,
		"created_at": now,
		"expires_at": now + COMMAND_TOTAL_TIMEOUT,
		"retry_at": now + COMMAND_ACK_TIMEOUT,
	}
	_pending_game_commands[command_id] = envelope
	_send_pending_game_intent(command_id, envelope, false)
	_network_diag("command_sent", {"command_id": command_id, "kind": kind, "revision": expected_revision})
	game_command_status.emit(command_id, kind, "sent", 0)
	return command_id


func _process_pending_game_commands() -> void:
	if (_pending_game_commands.is_empty() and _timed_out_checkpoint.is_empty()) or _room_link_stalled or not is_game_rpc_ready():
		return
	var now := _now()
	if _pending_game_commands.is_empty():
		_request_room_command_checkpoint(now)
		_request_command_resync(now)
		return
	var recovering := _room_link_waiting and has_live_server_room()
	var command_ids := _pending_game_commands.keys()
	if recovering:
		# Keep dependent predicted commands behind the earliest unconfirmed action.
		command_ids.resize(1)
		var first: Dictionary = _pending_game_commands[command_ids[0]]
		if not first.get("recovering", false):
			first["recovering"] = true
			first["expires_at"] = now + COMMAND_TOTAL_TIMEOUT
			first["retry_at"] = now
	_request_room_command_checkpoint(now)
	for command_id in command_ids:
		var envelope: Dictionary = _pending_game_commands.get(command_id, {})
		if now >= float(envelope["expires_at"]):
			_pending_game_commands.erase(command_id)
			_remember_command_receipt(command_id, envelope)
			if _timed_out_checkpoint.is_empty() and player_number == 2 and room_match_started and has_live_server_room():
				_timed_out_checkpoint = {
					"command_id": command_id, "match_id": envelope["match_id"],
					"expected_revision": envelope["expected_revision"],
				}
			var timed_out_kind := str(envelope.get("kind", ""))
			_network_diag("command_timeout", {"command_id": command_id, "kind": timed_out_kind})
			game_command_status.emit(command_id, timed_out_kind, "timeout", int(COMMAND_TOTAL_TIMEOUT * 1000.0))
			_request_command_resync(now)
			continue
		if now < float(envelope.get("retry_at", 0.0)):
			continue
		var sends := int(envelope.get("sends", 1))
		if not recovering and sends >= COMMAND_MAX_SENDS:
			envelope["retry_at"] = now + COMMAND_RECEIPT_TIMEOUT
			_pending_game_commands[command_id] = envelope
			_request_command_resync(now)
			_network_diag("command_resync_requested", {"command_id": command_id, "kind": envelope.get("kind", ""), "sends": sends})
			continue
		sends += 1
		envelope["sends"] = sends
		envelope["retry_at"] = now + (RECOVERY_COMMAND_RETRY_INTERVAL if recovering else COMMAND_ACK_TIMEOUT)
		_pending_game_commands[command_id] = envelope
		_send_pending_game_intent(command_id, envelope, recovering)
		_network_diag("command_resent", {"command_id": command_id, "kind": envelope.get("kind", ""), "sends": sends, "recovery_channel": recovering})


func _send_pending_game_intent(command_id: String, envelope: Dictionary, recovering: bool) -> void:
	# Application retries on the recovery channel avoid ENet's reliable backlog.
	var method := "rpc_recovery_game_intent" if recovering else "rpc_game_intent"
	rpc(method, str(envelope["match_id"]), command_id, int(envelope["expected_revision"]),
		int(envelope["player"]), str(envelope["kind"]), envelope["payload"] as Dictionary)


func _request_room_command_checkpoint(now: float) -> void:
	if now < _next_command_checkpoint_at or player_number != 2 or not room_match_started or not has_live_server_room():
		return
	var command_id: String
	var envelope: Dictionary
	if _timed_out_checkpoint.is_empty():
		command_id = _pending_game_commands.keys().front()
		envelope = _pending_game_commands[command_id]
		var age := now - float(envelope["created_at"])
		if age < ROOM_COMMAND_CHECKPOINT_INTERVAL or now >= float(envelope["expires_at"]):
			return
	else:
		command_id = _timed_out_checkpoint["command_id"]
		envelope = _timed_out_checkpoint
	_next_command_checkpoint_at = now + ROOM_COMMAND_CHECKPOINT_INTERVAL
	rpc_request_room_command_checkpoint.rpc_id(1, str(envelope["match_id"]), command_id, int(envelope["expected_revision"]))


@rpc("any_peer", "call_remote", "unreliable", 4)
func rpc_request_room_command_checkpoint(match_id: String, command_id: String, known_revision: int) -> void:
	if not room_command_checkpoint_handler.is_valid() or command_id.is_empty() or command_id.length() > 96 or known_revision < 0:
		return
	if not _battle_message_matches(match_id, "checkpoint_request"):
		return
	room_command_checkpoint_handler.call(multiplayer.get_remote_sender_id(), command_id, known_revision)


func send_room_command_checkpoint(peer_id: int, command_id: String, state: Dictionary) -> void:
	rpc_room_command_checkpoint.rpc_id(peer_id, battle_match_id, command_id, SnapshotWire.encode(state))


@rpc("authority", "call_remote", "reliable", 4)
func rpc_room_command_checkpoint(match_id: String, command_id: String, payload: Dictionary) -> void:
	if not room_match_started or not has_live_server_room():
		return
	if not _battle_message_matches(match_id, "checkpoint"):
		return
	var envelope: Dictionary = _pending_game_commands.get(command_id, {})
	if envelope.is_empty() and _timed_out_checkpoint.get("command_id") == command_id:
		envelope = _timed_out_checkpoint
	if envelope.is_empty():
		return
	var state := SnapshotWire.decode(payload)
	var revision := int(state.get("state_revision", -1))
	var expected_revision := int(envelope["expected_revision"])
	if revision < expected_revision:
		return
	state.erase("_checkpoint_command_id")
	if revision == expected_revision:
		var rejection := str(state.get("_checkpoint_rejection", ""))
		if rejection not in ["rejected", "stale_revision"]:
			return
		state["_checkpoint_command_id"] = command_id
	room_command_checkpoint_received.emit(state)


func _request_command_resync(now: float) -> void:
	if not is_game_rpc_ready() or now < _next_command_resync_at:
		return
	_next_command_resync_at = now + COMMAND_RECEIPT_TIMEOUT
	request_initial_state()


func acknowledge_game_command(command_id: String, revision: int, status: String) -> void:
	if command_id.is_empty():
		return
	var envelope: Dictionary = _pending_game_commands.get(command_id, {})
	if _pending_game_commands.has(command_id):
		_pending_game_commands.erase(command_id)
	else:
		envelope = _reconciled_game_commands.get(command_id, {})
		_reconciled_game_commands.erase(command_id)
		if envelope.is_empty() or status not in ["rejected", "stale_revision"]:
			return
	if status in ["rejected", "stale_revision"]:
		_discard_dependent_commands(command_id)
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


func _clear_outgoing_game_commands() -> void:
	_pending_game_commands.clear()
	_reconciled_game_commands.clear()
	finish_timed_out_command_sync()


func finish_timed_out_command_sync() -> void:
	_timed_out_checkpoint.clear()


func _remember_command_receipt(command_id: String, envelope: Dictionary) -> void:
	_reconciled_game_commands[command_id] = {
		"kind": str(envelope.get("kind", "")), "created_at": envelope.get("created_at", _now()),
		"after_move": str(envelope.get("after_move", "")),
	}
	if _reconciled_game_commands.size() > RECONCILED_COMMAND_CACHE_SIZE:
		_reconciled_game_commands.erase(_reconciled_game_commands.keys()[0])


func _discard_dependent_commands(rejected_id: String) -> void:
	# The authority only applies a dependent command after its predecessor applies.
	var commands := _reconciled_game_commands.duplicate()
	commands.merge(_pending_game_commands, true)
	var rejected: Array[String] = [rejected_id]
	while not rejected.is_empty():
		var predecessor: String = rejected.pop_back()
		for command_id in commands.keys():
			if commands[command_id].get("after_move", "") == predecessor:
				rejected.append(command_id)
				commands.erase(command_id)
				_pending_game_commands.erase(command_id)
				_reconciled_game_commands.erase(command_id)


func pending_game_commands() -> Array:
	return _pending_game_commands.values()


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
		# A checkpoint confirms the board, but cannot say why this command ended.
		_remember_command_receipt(command_id, envelope)
		var latency_ms := int((_now() - float(envelope.get("created_at", _now()))) * 1000.0)
		_network_diag("command_reconciled", {
			"command_id": command_id,
			"kind": kind,
			"revision": authority_revision,
			"forced": force,
			"latency_ms": latency_ms,
		})
		game_command_status.emit(command_id, kind, "resynced", latency_ms)


func set_next_authority_ack(command_id: String, status: String) -> void:
	_next_authority_ack = {"command_id": command_id, "status": status}


func broadcast_authority_state(state: Dictionary) -> void:
	var command_id := str(_next_authority_ack.get("command_id", ""))
	var status := str(_next_authority_ack.get("status", "snapshot"))
	_next_authority_ack.clear()
	var payload := SnapshotWire.encode(state)
	rpc_authority_state.rpc(battle_match_id, payload, command_id, status)
	if not command_id.is_empty():
		var payload_bytes := var_to_bytes(payload).size()
		_network_diag("command_state_sent", {"command_id": command_id, "status": status,
			"revision": state.get("state_revision", -1), "snapshot_bytes": payload.get("raw_bytes", payload_bytes),
			"payload_bytes": payload_bytes})


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_game_intent(match_id: String, command_id: String, expected_revision: int, claimed_player: int, kind: String, payload: Dictionary) -> void:
	_receive_game_intent(match_id, command_id, expected_revision, claimed_player, kind, payload, "intent")


@rpc("any_peer", "call_remote", "unreliable", 5)
func rpc_recovery_game_intent(match_id: String, command_id: String, expected_revision: int, claimed_player: int, kind: String, payload: Dictionary) -> void:
	if is_dedicated_server or room_message_guard.is_valid():
		_receive_game_intent(match_id, command_id, expected_revision, claimed_player, kind, payload, "recovery_intent")


func _receive_game_intent(match_id: String, command_id: String, expected_revision: int, claimed_player: int, kind: String, payload: Dictionary, message_kind: String) -> void:
	if not _battle_message_matches(match_id, message_kind) or not _allow_room_message(message_kind):
		return
	if command_id.is_empty() or command_id.length() > 96 or not _accept_remote_intent(claimed_player):
		return
	if kind not in ["summon", "summon_skill", "attack", "activate_skill", "end_turn", "discard", "move"]:
		return
	if is_online and is_authority():
		rpc_id(multiplayer.get_remote_sender_id(), "rpc_game_command_receipt", match_id, command_id)
	if _received_game_commands.has(command_id):
		_network_diag("duplicate_command_dropped", {"command_id": command_id, "kind": kind})
	else:
		_received_game_commands[command_id] = true
		_network_diag("command_arrived", {"command_id": command_id, "kind": kind, "revision": expected_revision, "recovery_channel": message_kind == "recovery_intent"})
		if _received_game_commands.size() > RECEIVED_COMMAND_CACHE_SIZE:
			_received_game_commands.erase(_received_game_commands.keys()[0])
	EventBus.rpc_game_intent_received.emit(kind, payload, claimed_player, command_id, expected_revision)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_game_command_receipt(match_id: String, command_id: String) -> void:
	if not _pending_game_commands.has(command_id) or not _battle_message_matches(match_id, "receipt"):
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
func _remote_start_game(match_id: String, starting_player: int):
	if is_dedicated_server: return
	if not _accept_remote_player_claim(1) or not valid_battle_match_id(match_id) or starting_player not in [1, 2]: return
	game_started.emit(match_id, starting_player)


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
func rpc_targeting_arrow(match_id: String, source_slot: int, target_slot: int, player: int):
	if match_id == battle_match_id:
		EventBus.rpc_targeting_arrow_received.emit(source_slot, target_slot, player)


func _battle_presence_peer() -> int:
	if not room_match_started or room_departure_pending or not valid_battle_match_id(battle_match_id):
		return 0
	if is_dedicated_server:
		return 1
	return opponent_peer_id if _direct_protocol_verified else 0


func can_send_battle_chat() -> bool:
	var target := _battle_presence_peer()
	return battle_chat_supported and target > 0 and is_game_rpc_ready(target) and Time.get_ticks_msec() >= _next_battle_chat_at


func send_battle_chat(phrase: int) -> bool:
	if phrase < 0 or phrase >= BATTLE_CHAT_PHRASES.size() or not can_send_battle_chat():
		return false
	if send_battle_chat_packet(_battle_presence_peer(), phrase) != OK:
		return false
	_next_battle_chat_at = Time.get_ticks_msec() + BATTLE_CHAT_COOLDOWN_MS
	return true


func poll_battle_chat() -> void:
	if _battle_chat_transport != peer:
		_reset_battle_chat()
		_battle_chat_transport = peer
	var target := _battle_presence_peer()
	var now := Time.get_ticks_msec()
	if not battle_chat_supported and now >= _next_battle_chat_probe_at and target > 0 and is_game_rpc_ready(target):
		_next_battle_chat_probe_at = now + 1000
		send_battle_chat_packet(target, BATTLE_CHAT_HELLO)


func send_battle_chat_packet(target: int, phrase: int) -> Error:
	var packet := _BATTLE_CHAT_MAGIC.to_ascii_buffer()
	packet.append_array(battle_match_id.hex_decode())
	packet.append(phrase)
	return multiplayer.send_bytes(packet, target, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 2)


func _receive_battle_chat(sender: int, match_id: String, phrase: int) -> void:
	if match_id != battle_match_id or (phrase >= BATTLE_CHAT_PHRASES.size() and phrase != BATTLE_CHAT_HELLO and phrase != BATTLE_CHAT_ACK):
		return
	if room_battle_chat_handler.is_valid():
		room_battle_chat_handler.call(sender, phrase)
		return
	if sender <= 0 or sender != _battle_presence_peer() or not is_game_rpc_ready(sender):
		return
	_battle_chat_transport = peer
	battle_chat_supported = true
	if phrase == BATTLE_CHAT_HELLO:
		send_battle_chat_packet(sender, BATTLE_CHAT_ACK)
	if phrase >= BATTLE_CHAT_PHRASES.size():
		return
	var now := Time.get_ticks_msec()
	if now < _next_incoming_battle_chat_at:
		return
	_next_incoming_battle_chat_at = now + 300
	battle_chat_received.emit(phrase)


func send_battle_cursor(point: Vector2) -> void:
	var target := _battle_presence_peer()
	if battle_chat_supported and target > 0 and is_game_rpc_ready(target):
		send_battle_cursor_packet(target, point)


func send_battle_cursor_packet(target: int, point: Vector2) -> void:
	var packet := _BATTLE_CURSOR_MAGIC.to_ascii_buffer()
	packet.append_array(battle_match_id.hex_decode())
	packet.resize(20)
	var x := 65535 if point == CURSOR_HIDDEN else roundi(point.x * _CURSOR_GRID)
	var y := 65535 if point == CURSOR_HIDDEN else roundi(point.y * _CURSOR_GRID)
	packet.encode_u16(16, x)
	packet.encode_u16(18, y)
	multiplayer.send_bytes(packet, target, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 3)


func _receive_battle_cursor(sender: int, packet: PackedByteArray) -> void:
	if packet.slice(4, 16).hex_encode() != battle_match_id:
		return
	var x := packet.decode_u16(16)
	var y := packet.decode_u16(18)
	var point := CURSOR_HIDDEN
	if x != 65535 or y != 65535:
		if x > _CURSOR_GRID or y > _CURSOR_GRID:
			return
		point = Vector2(x, y) / _CURSOR_GRID
	if room_battle_cursor_handler.is_valid():
		room_battle_cursor_handler.call(sender, point)
	elif battle_chat_supported and sender > 0 and sender == _battle_presence_peer() and is_game_rpc_ready(sender):
		battle_cursor_received.emit(point)


func _reset_battle_chat() -> void:
	battle_chat_supported = false
	_next_battle_chat_at = 0
	_next_incoming_battle_chat_at = 0
	_next_battle_chat_probe_at = 0


# ============================================
# Player ready RPC
# ============================================

@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_player_ready(card_data_list: Array, returning_from_match: String = ""):
	if is_dedicated_server or not _accept_remote_player_claim(3 - player_number):
		return
	if not returning_from_match.is_empty():
		if card_data_list.is_empty() and can_return_to_lan_room() and returning_from_match == battle_match_id:
			_lan_opponent_returned = true
			_finish_lan_return()
		return
	if room_match_started or lan_room_preparation_paused():
		return
	# Empty decks are never submitted as ready. On direct transports the host
	# uses this ordered message to clear readiness on both sides.
	if card_data_list.is_empty():
		direct_preparation_reset_received.emit()
		return
	EventBus.rpc_ready_received.emit(card_data_list)


signal match_offer_received(offer: Dictionary)
signal match_offer_accepted(hash_value: String)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_match_offer(offer: Dictionary) -> void:
	if lan_room_preparation_paused() or not _accept_remote_player_claim(1) or JSON.stringify(offer).length() > 2048:
		return
	match_offer_received.emit(offer)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_match_offer_accept(hash_value: String, player: int) -> void:
	if lan_room_preparation_paused() or not _accept_remote_player_claim(player) or hash_value.length() != 64:
		return
	match_offer_accepted.emit(hash_value)


# Card art transfer. Direct P2P always allowed; relay mode only when the
# dedicated server opted in (server_allows_card_art, sent in the lobby response).
func send_card_arts(arts: Array) -> void:
	if not is_online or (is_dedicated_server and not server_allows_card_art):
		return
	var target_peer := _card_art_target_peer()
	var total: int = arts.size()
	_art_send_queue.append({"target": target_peer, "method": "rpc_card_art_manifest", "args": [total]})
	var queued_chunks := 0
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
				"method": "rpc_card_art_chunk",
				"args": [card_index, ext, chunk_index, chunk_count, bytes.slice(begin, finish), total, checksum],
			})
			queued_chunks += 1
	_network_diag("art_transfer_queued", {"cards": total, "chunks": queued_chunks})


func is_game_rpc_ready(target_peer: int = 0) -> bool:
	# is_online also stays true while a replacement transport is connecting.
	# Only the peer currently installed in SceneMultiplayer can carry RPCs.
	if not is_online or peer == null or multiplayer.multiplayer_peer != peer:
		return false
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	var recipients := multiplayer.get_peers()
	return recipients.has(target_peer) if target_peer > 0 else not recipients.is_empty()


func _process_art_send_queue() -> void:
	for _index in range(mini(ART_CHUNKS_PER_FRAME, _art_send_queue.size())):
		var item: Dictionary = _art_send_queue[0]
		var target_peer := int(item["target"])
		if not is_game_rpc_ready(target_peer):
			return
		if peer is BetaPeer and peer.queued_packets() > 16:
			return
		var args: Array = item["args"]
		var error: Error = rpc_id.callv([target_peer, item["method"]] + args) if target_peer > 0 else rpc.callv([item["method"]] + args)
		if error != OK:
			return
		# Keep order and retain the head until Godot accepts the complete RPC.
		_art_send_queue.pop_front()


func _cleanup_art_receive_buffers() -> void:
	if _art_receive_buffers.is_empty():
		return
	var now := _now()
	for key in _art_receive_buffers.keys():
		var buffer: Dictionary = _art_receive_buffers[key]
		if now - float(buffer.get("created_at", now)) > 30.0:
			_art_receive_buffers.erase(key)


func send_card_art_ack(card_index: int, total: int) -> void:
	if not is_online or (is_dedicated_server and not server_allows_card_art):
		return
	var target_peer := _card_art_target_peer()
	# Acknowledge received art before a potentially long local upload backlog.
	_art_send_queue.push_front({"target": target_peer, "method": "rpc_card_art_ack", "args": [card_index, total]})


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
	if not _allow_room_message("art") or total < 0 or total > DataSchema.MAX_CARDS_PER_DECK * 2:
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
func rpc_splash(match_id: String, player: int, slot_index: int):
	if match_id == battle_match_id:
		EventBus.rpc_splash_received.emit(player, slot_index)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_initial_state(match_id: String, payload: Dictionary):
	if not _battle_message_matches(match_id, "initial_state") or not _allow_room_message("authority_state"):
		return
	var state := SnapshotWire.decode(payload)
	if not state.is_empty():
		EventBus.rpc_initial_state_received.emit(state)


func send_initial_state(state: Dictionary) -> void:
	rpc_initial_state.rpc(battle_match_id, SnapshotWire.encode(state))


func request_initial_state() -> void:
	rpc_request_initial_state.rpc(battle_match_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_request_initial_state(match_id: String):
	if _battle_message_matches(match_id, "state_request") and _allow_room_message("state_request"):
		EventBus.rpc_initial_state_requested.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_authority_state(match_id: String, payload: Dictionary, ack_command_id: String, ack_status: String):
	if not _battle_message_matches(match_id, "authority_state") or not _allow_room_message("authority_state"):
		return
	var state := SnapshotWire.decode(payload)
	if state.is_empty():
		return
	if authority_state_handler.is_valid():
		authority_state_handler.call(multiplayer.get_remote_sender_id(), state, ack_command_id, ack_status)
	var envelope: Dictionary = _pending_game_commands.get(ack_command_id, {})
	var local_feedback := str(envelope.get("payload", {}).get("local_feedback", ""))
	if ack_status == "applied" and not local_feedback.is_empty() and is_online:
		# Keep authoritative combat details, but don't play the same primary
		# animation twice when the guest already predicted it.
		state = state.duplicate()
		var events: Array = state.get("_feedback_events", []).duplicate()
		for index in range(events.size()):
			var event: Dictionary = events[index]
			if event.get("kind") == local_feedback and int(event.get("player", 0)) == player_number:
				events.remove_at(index)
				break
		state["_feedback_events"] = events
	acknowledge_game_command(ack_command_id, int(state.get("state_revision", -1)), ack_status)
	EventBus.rpc_authority_state_received.emit(state)


func send_server_match_snapshot(peer_id: int, state: Dictionary) -> void:
	rpc_id(peer_id, "rpc_server_match_snapshot", battle_match_id, state)


@rpc("authority", "call_remote", "reliable", 1)
func rpc_server_match_snapshot(match_id: String, state: Dictionary) -> void:
	if not _battle_message_matches(match_id, "server_snapshot"):
		return
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


static func valid_battle_match_id(match_id: String) -> bool:
	return match_id.length() == 24 and match_id.is_valid_hex_number()


func _battle_message_matches(match_id: String, kind: String) -> bool:
	if match_id == battle_match_id and (not match_id.is_empty() or not is_dedicated_server and not room_message_guard.is_valid()):
		return true
	if valid_battle_match_id(match_id):
		_network_diag("prior_match_message_ignored", {"kind": kind})
	return false


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
func rpc_intent_summon(match_id: String, hand_index: int, slot_index: int, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_summon_received.emit(hand_index, slot_index, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_summon_skill(match_id: String, slot_index: int, skill_index: int, target_slot: int, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_summon_skill_received.emit(slot_index, skill_index, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_attack(match_id: String, source_slot: int, target_slot: int, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_attack_received.emit(source_slot, target_slot, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_activate_skill(match_id: String, slot_index: int, skill_index: int, target_slot: int, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_activate_skill_received.emit(slot_index, skill_index, target_slot, player)



@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_end_turn(match_id: String, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_end_turn_received.emit(player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_discard(match_id: String, location: String, index: int, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_discard_received.emit(location, index, player)


@rpc("any_peer", "call_remote", "reliable", 1)
func rpc_intent_move_card(match_id: String, source_slot: int, target_slot: int, player: int):
	if not _allow_room_message("intent") or not _battle_message_matches(match_id, "intent"):
		return
	if not _accept_remote_intent(player):
		return
	EventBus.rpc_intent_move_received.emit(source_slot, target_slot, player)


# ============================================
# Cleanup
# ============================================

func close_connection():
	_reset_battle_chat()
	_battle_chat_transport = null
	match_opening_player = 0
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_reconnect_active = false
	_reconnect_attempt_running = false
	_reconnect_deadline = 0.0
	_reconnect_retry_at = 0.0
	just_reconnected = false
	room_preparation_available = false
	room_preparation_generation = 0
	_returning_to_room = false
	room_departure_pending = false
	room_wait_reason = ""
	room_host_transfer_pending = false
	lan_opponent_editing = false
	lan_room_return_pending = false
	_lan_rematch_supported = false
	_lan_host_match_finished = false
	_lan_local_returned = false
	_lan_opponent_returned = false
	_lan_room_editing = false
	_direct_protocol_verified = false
	_connected_emitted = false
	pending_server_match_state = {}
	_clear_outgoing_game_commands()
	_next_command_resync_at = 0.0
	_next_command_checkpoint_at = 0.0
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

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

const LOBBY_PORT := 4567
const CONNECT_TIMEOUT := 8.0  # seconds before a pending connection is treated as failed
const RECONNECT_WINDOW := 60.0 * 60.0
const RECONNECT_RETRY_DELAY := 5.0
const SESSION_PATH := "user://active_room.cfg"

var peer: ENetMultiplayerPeer
var is_host: bool = false
var is_online: bool = false
var opponent_peer_id: int = 0
var player_number: int = 0
var is_dedicated_server: bool = false
# Set from the lobby response in relay mode: whether the server permits card-art
# transfer. Direct P2P ignores this (always allowed).
var server_allows_card_art: bool = false
var room_server_address: String = ""
var room_server_port: int = 0
var room_code: String = ""
var room_player_number: int = 0
var reconnect_token: String = ""
var room_match_started: bool = false
var just_reconnected: bool = false

# Lobby connection (for room-code server)
var _lobby_peer: ENetMultiplayerPeer
var _lobby_callback: Callable
var _lobby_status_callback: Callable

# Server-side: server.gd registers this so lobby_request RPCs (which always land on
# the shared NetworkManager autoload node) get forwarded to the real handler.
var lobby_request_handler: Callable
var room_auth_handler: Callable

# Pending-connection timeout tracking (deadlines in seconds; <= 0 means inactive)
var _lobby_deadline: float = 0.0
var _game_deadline: float = 0.0
var _reconnect_active: bool = false
var _reconnect_deadline: float = 0.0
var _reconnect_retry_at: float = 0.0
var _reconnect_attempt_running: bool = false


func _ready() -> void:
	_load_room_session()


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
		if _now() >= _reconnect_deadline:
			_finish_reconnect_failure("reconnect_timeout")
		elif not _reconnect_attempt_running and _now() >= _reconnect_retry_at:
			_attempt_match_reconnect()


# ============================================
# Persisted room session
# ============================================

func configure_room_session(address: String, port: int, code: String, assigned_player: int, token: String) -> void:
	room_server_address = address
	room_server_port = port
	room_code = code
	room_player_number = assigned_player
	reconnect_token = token
	room_match_started = false
	_save_room_session()


func has_saved_room_session() -> bool:
	return room_server_address != "" and room_server_port > 0 and room_code != "" and room_player_number in [1, 2] and reconnect_token != ""


func has_resumable_match_session() -> bool:
	return has_saved_room_session() and room_match_started


func mark_room_match_started() -> void:
	if not has_saved_room_session():
		return
	room_match_started = true
	_save_room_session()


func clear_room_session() -> void:
	room_server_address = ""
	room_server_port = 0
	room_code = ""
	room_player_number = 0
	reconnect_token = ""
	room_match_started = false
	just_reconnected = false
	_reconnect_active = false
	_reconnect_attempt_running = false
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))


func _save_room_session() -> void:
	if not has_saved_room_session():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("room", "address", room_server_address)
	cfg.set_value("room", "port", room_server_port)
	cfg.set_value("room", "code", room_code)
	cfg.set_value("room", "player", room_player_number)
	cfg.set_value("room", "token", reconnect_token)
	cfg.set_value("room", "card_art", server_allows_card_art)
	cfg.set_value("room", "match_started", room_match_started)
	cfg.save(SESSION_PATH)


func _load_room_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	room_server_address = str(cfg.get_value("room", "address", ""))
	room_server_port = int(cfg.get_value("room", "port", 0))
	room_code = str(cfg.get_value("room", "code", ""))
	room_player_number = int(cfg.get_value("room", "player", 0))
	reconnect_token = str(cfg.get_value("room", "token", ""))
	server_allows_card_art = bool(cfg.get_value("room", "card_art", false))
	room_match_started = bool(cfg.get_value("room", "match_started", false))


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
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
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
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
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


@rpc("authority", "call_remote", "reliable")
func notify_room_ready() -> void:
	# Broadcast by the room subprocess (peer 1) once both players are connected.
	# Drives the same "opponent connected" path used by direct P2P.
	is_online = true
	if opponent_peer_id == 0:
		opponent_peer_id = -1  # marker: opponent present (relay hides real id)
	connected.emit()


@rpc("any_peer", "call_remote", "reliable")
func rpc_room_auth(code: String, assigned_player: int, token: String) -> void:
	# Room subprocess only: forward authentication to room_server.gd, which owns
	# the reconnect tokens and stable P1/P2 slot mapping.
	if room_auth_handler.is_valid():
		room_auth_handler.call(multiplayer.get_remote_sender_id(), code, assigned_player, token)


func send_room_auth_result(peer_id: int, accepted: bool, assigned_player: int, reason: String, reconnecting: bool) -> void:
	rpc_id(peer_id, "rpc_room_auth_result", accepted, assigned_player, reason, reconnecting)


@rpc("authority", "call_remote", "reliable")
func rpc_room_auth_result(accepted: bool, assigned_player: int, reason: String, reconnecting: bool) -> void:
	_game_deadline = 0.0
	if not accepted:
		if _reconnect_active:
			if reason in ["invalid_token", "invalid_reconnect"]:
				_finish_reconnect_failure(reason, true)
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
	room_authenticated.emit(assigned_player, resumed)
	if resumed:
		reconnect_transport_ready.emit()


@rpc("authority", "call_remote", "reliable")
func notify_player_disconnected(disconnected_player: int) -> void:
	if disconnected_player == player_number:
		return
	opponent_peer_id = 0
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
	_close_lobby_peer()
	is_online = false


func connect_to_game_room(address: String, port: int, assigned_player: int, code: String = "", token: String = "") -> int:
	"""Reconnect to the game room port after lobby matchmaking."""
	disconnect_from_lobby()
	if not is_valid_address(address):
		return ERR_INVALID_PARAMETER
	_close_game_peer()
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
	var err = peer.create_client(address, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	peer.peer_connected.connect(_on_peer_connected.bind(peer))
	peer.peer_disconnected.connect(_on_peer_disconnected.bind(peer))
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
	if not has_saved_room_session():
		_finish_reconnect_failure("no_saved_session", true)
		return
	if _reconnect_active:
		return

	_reconnect_active = true
	_reconnect_deadline = _now() + RECONNECT_WINDOW
	_reconnect_retry_at = _now()
	_reconnect_attempt_running = false
	just_reconnected = false
	opponent_peer_id = 0
	is_online = false
	_game_deadline = 0.0
	_lobby_deadline = 0.0
	_close_game_peer()
	_close_lobby_peer()
	reconnect_started.emit()


func _attempt_match_reconnect() -> void:
	if not _reconnect_active or _reconnect_attempt_running:
		return
	if _now() >= _reconnect_deadline:
		_finish_reconnect_failure("reconnect_timeout")
		return
	_reconnect_attempt_running = true
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
	print("Reconnect attempt failed (%s); retrying" % reason)
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_close_game_peer()
	_close_lobby_peer()
	is_online = false
	_reconnect_attempt_running = false
	_reconnect_retry_at = min(_now() + RECONNECT_RETRY_DELAY, _reconnect_deadline)


func _finish_reconnect_failure(reason: String, clear_saved_session: bool = false) -> void:
	var was_active := _reconnect_active
	_reconnect_active = false
	_reconnect_attempt_running = false
	_reconnect_deadline = 0.0
	_reconnect_retry_at = 0.0
	_lobby_deadline = 0.0
	_game_deadline = 0.0
	_close_game_peer()
	_close_lobby_peer()
	is_online = false
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
			rpc_id(1, "rpc_room_auth", room_code, player_number, reconnect_token)
		return
	# Direct P2P has no room-authentication handshake.
	_game_deadline = 0.0
	opponent_peer_id = id
	connected.emit()
	print("Opponent connected: %d" % id)


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
	is_online = false


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


# Reconnect recovery is deliberately independent of P1 authority. Whichever
# player stayed connected owns the surviving in-memory snapshot and can return
# it to the stable P1/P2 slot that rejoined.
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_resume_state(requesting_player: int, known_revision: int):
	EventBus.rpc_resume_state_requested.emit(requesting_player, known_revision)


@rpc("any_peer", "call_remote", "reliable")
func rpc_resume_state(state: Dictionary, source_player: int, target_player: int):
	EventBus.rpc_resume_state_received.emit(state, source_player, target_player)


@rpc("any_peer", "call_remote", "reliable")
func rpc_resume_state_ack(player: int, revision: int):
	EventBus.rpc_resume_state_ack_received.emit(player, revision)


@rpc("any_peer", "call_remote", "reliable")
func rpc_resume_complete(revision: int):
	EventBus.rpc_resume_complete_received.emit(revision)


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
	_reconnect_active = false
	_reconnect_attempt_running = false
	_reconnect_deadline = 0.0
	_reconnect_retry_at = 0.0
	just_reconnected = false
	_close_game_peer()
	_close_lobby_peer()
	is_online = false
	is_host = false
	is_dedicated_server = false
	server_allows_card_art = false
	player_number = 0
	opponent_peer_id = 0

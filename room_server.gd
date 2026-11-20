extends Node

const RoomPresenceStore = preload("res://RoomPresenceStore.gd")

# ============================================
# Room server subprocess — pure ENet relay for one room.
# Spawned by server.gd via OS.create_process. Listens on a single port,
# accepts up to 2 player clients, and relies on Godot's default
# server-relay so the two clients' broadcast RPCs reach each other.
#
# Command line:
#   CardGame.exe --headless -- --room-server --room-port=5001 --room-code=1234 \
#     --p1-token=<token> --p2-token=<token>
# ============================================

const DEFAULT_ROOM_PORT := 5001
const CREATED_TIMEOUT := 60.0
const WAITING_OPPONENT_TIMEOUT := 60.0 * 60.0
const RECONNECT_TIMEOUT := 60.0 * 60.0
const EMPTY_SHUTDOWN_DELAY := 60.0
const AUTH_TIMEOUT := 10.0
const MAX_AUTH_ATTEMPTS := 5
const MAX_SNAPSHOT_BYTES := 2 * 1024 * 1024
const MAX_CHECKPOINT_SUMMARIES := 60
const MAX_CHECKPOINT_SUMMARY_BYTES := 4096
const MAX_CHECKPOINT_REJECTIONS := 64
const MAX_ROOM_TRANSPORTS := 3 # Two player seats and one connection finishing handoff.

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
var presence_path: String = ""
var match_active := false
var _preparation_generation := 1

var peer: ENetMultiplayerPeer
var player_count: int = 0
var room_state: int = RoomState.CREATED
var _state_deadline: float = -1.0
var _shutting_down: bool = false
var _auth_deadlines: Dictionary = {}
var _departure_deadlines: Dictionary = {}
var _peer_to_player: Dictionary = {}
var _player_to_peer: Dictionary = {}
var _auth_attempts: Dictionary = {}
var _rate_windows: Dictionary = {}
var _latest_match_state: Dictionary = {}
var _latest_revision: int = -1
var _checkpoint_summaries: Array[Dictionary] = []
var _checkpoint_rejections: Dictionary = {}
var _players_in_battle: Dictionary = {}
var _editors: Dictionary = {}
var _ready_peers: Dictionary = {}


func _ready() -> void:
	_parse_args()
	if not _start():
		push_error("[ROOM %s] Failed to bind port %d — exiting" % [room_code, room_port])
		get_tree().quit(1)
		return
	_enter_state(RoomState.CREATED, CREATED_TIMEOUT)
	_publish_presence()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	var now := _now()
	for peer_id in _departure_deadlines.keys():
		if now >= float(_departure_deadlines[peer_id]):
			_departure_deadlines.erase(peer_id)
			if multiplayer.get_peers().has(int(peer_id)):
				peer.get_peer(int(peer_id)).reset()
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
		elif arg.begins_with("--presence-file="):
			presence_path = arg.trim_prefix("--presence-file=")


func _start() -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(room_port, MAX_ROOM_TRANSPORTS, NetworkManager.GAME_CHANNEL_COUNT)
	if err != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.room_auth_handler = Callable(self, "_handle_room_auth")
	NetworkManager.authority_state_handler = Callable(self, "_handle_authority_state")
	NetworkManager.room_command_checkpoint_handler = Callable(self, "_handle_command_checkpoint")
	NetworkManager.room_message_guard = Callable(self, "_guard_room_message")
	NetworkManager.room_battle_chat_handler = Callable(self, "_relay_battle_chat")
	NetworkManager.room_battle_cursor_handler = Callable(self, "_relay_battle_cursor")
	multiplayer.peer_packet.connect(NetworkManager._on_peer_packet)
	NetworkManager.room_control_handler = Callable(self, "_handle_room_control")
	print("[ROOM %s] Relay listening on port %d" % [room_code, room_port])
	return true


func _on_peer_connected(id: int) -> void:
	_auth_deadlines[id] = _now() + AUTH_TIMEOUT
	print("[ROOM %s] Peer %d connected; awaiting authentication" % [room_code, id])


func _handle_room_auth(sender_id: int, requested_code: String, requested_player: int, token: String, protocol_version: int) -> void:
	if _departure_deadlines.has(sender_id):
		return
	_auth_attempts[sender_id] = int(_auth_attempts.get(sender_id, 0)) + 1
	if int(_auth_attempts[sender_id]) > MAX_AUTH_ATTEMPTS:
		print("[SECURITY room=%s peer=%d kind=auth attempts=%d action=disconnect]" % [room_code, sender_id, int(_auth_attempts[sender_id])])
		call_deferred("_disconnect_rejected_peer", sender_id)
		return
	if protocol_version != AppVersion.PROTOCOL_VERSION:
		_reject_room_admission(sender_id, requested_player, "protocol_mismatch")
		print("[SECURITY room=%s peer=%d kind=protocol client=%d server=%d]" % [room_code, sender_id, protocol_version, AppVersion.PROTOCOL_VERSION])
		return
	var expected_token := ""
	if requested_player == 1:
		expected_token = p1_token
	elif requested_player == 2:
		expected_token = p2_token
	if requested_code != room_code or expected_token == "" or token != expected_token:
		_reject_room_admission(sender_id, requested_player, "invalid_token")
		print("[ROOM %s] Peer %d failed authentication" % [room_code, sender_id])
		return
	if _peer_to_player.has(sender_id):
		var existing_player := int(_peer_to_player[sender_id])
		if existing_player == requested_player:
			NetworkManager.send_room_auth_result(sender_id, true, requested_player, _room_admission_status(sender_id), match_active)
		else:
			_reject_room_admission(sender_id, requested_player, "already_authenticated")
		return
	if _player_to_peer.has(requested_player) and int(_player_to_peer[requested_player]) != sender_id:
		_reject_room_admission(sender_id, requested_player, "slot_in_use")
		print("[ROOM %s] P%d slot is already connected" % [room_code, requested_player])
		return

	var was_reconnect := match_active
	peer.get_peer(sender_id).set_timeout(32, NetworkManager.ROOM_ENET_MIN_TIMEOUT_MS, 30000)
	_auth_deadlines.erase(sender_id)
	_peer_to_player[sender_id] = requested_player
	_player_to_peer[requested_player] = sender_id
	player_count = _peer_to_player.size()
	NetworkManager.send_room_auth_result(sender_id, true, requested_player, _room_admission_status(sender_id), was_reconnect)
	if was_reconnect and not _latest_match_state.is_empty():
		NetworkManager.send_server_match_snapshot(sender_id, _latest_match_state)
	print("[ROOM %s] Peer %d authenticated as P%d (%d/2)" % [room_code, sender_id, requested_player, player_count])
	_update_lifecycle_after_player_change()
	_publish_presence()
	_notify_if_waiting()


func _room_admission_status(peer_id: int) -> String:
	# A player whose match ended after a departure may still be on the result screen.
	if not match_active and not _players_in_battle.is_empty() and not _players_in_battle.has(peer_id):
		return "returning"
	if _room_can_prepare():
		return "syncing_preparation"
	if player_count == 2 and not _editors.is_empty():
		return "editing"
	return ""


func _reject_room_admission(peer_id: int, player: int, reason: String) -> void:
	NetworkManager.send_room_auth_result(peer_id, false, player, reason, false)
	_auth_deadlines.erase(peer_id)
	# Flush the reliable result before closing the unauthenticated transport.
	peer.get_peer(peer_id).peer_disconnect_later()
	_departure_deadlines[peer_id] = _now() + NetworkManager.ROOM_LEAVE_TIMEOUT


func _disconnect_rejected_peer(peer_id: int) -> void:
	if peer:
		peer.disconnect_peer(peer_id)


func _on_peer_disconnected(id: int) -> void:
	_departure_deadlines.erase(id)
	_auth_deadlines.erase(id)
	_auth_attempts.erase(id)
	_rate_windows.erase(id)
	if not _peer_to_player.has(id):
		print("[ROOM %s] Unauthenticated peer %d disconnected" % [room_code, id])
		return
	_release_player(id)


func _release_player(id: int, left_by_choice: bool = false) -> void:
	var disconnected_player := int(_peer_to_player[id])
	_peer_to_player.erase(id)
	_player_to_peer.erase(disconnected_player)
	_players_in_battle.erase(id)
	_editors.erase(id)
	_ready_peers.clear()
	_preparation_generation += 1
	player_count = _peer_to_player.size()
	print("[ROOM %s] P%d peer %d disconnected (%d/2)" % [room_code, disconnected_player, id, player_count])
	if not NetworkManager.MATCH_RECONNECT_ENABLED:
		_reset_match()
	_update_lifecycle_after_player_change()
	if player_count > 0:
		NetworkManager.notify_player_disconnected.rpc(disconnected_player, left_by_choice)
	if not match_active:
		# Waiting-room seats are disposable. Keep the remaining connection and
		# promote its owner; the departed player's credential must not work again.
		if disconnected_player == 1 and _player_to_peer.has(2):
			var remaining_peer := int(_player_to_peer[2])
			_player_to_peer.erase(2)
			_player_to_peer[1] = remaining_peer
			_peer_to_player[remaining_peer] = 1
			p1_token = p2_token
			p2_token = Crypto.new().generate_random_bytes(24).hex_encode()
			NetworkManager.notify_room_host_changed.rpc_id(remaining_peer, p1_token)
			print("[ROOM %s] Remaining player became host" % room_code)
		elif disconnected_player == 2:
			p2_token = Crypto.new().generate_random_bytes(24).hex_encode()
		else:
			p1_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_publish_presence()


func _update_lifecycle_after_player_change() -> void:
	peer.refuse_new_connections = player_count >= 2
	if player_count >= 2:
		_enter_state(RoomState.PLAYING if match_active else RoomState.WAITING)
	elif player_count == 1 and match_active:
		_enter_state(RoomState.RECONNECTING, RECONNECT_TIMEOUT)
	elif player_count == 1:
		_enter_state(RoomState.WAITING, WAITING_OPPONENT_TIMEOUT)
	else:
		_shutdown_if_empty()


func _publish_presence() -> void:
	if not RoomPresenceStore.write(presence_path, {
		"occupied": _player_to_peer.keys(), "match_active": match_active,
		"tokens": {"1": p1_token, "2": p2_token},
	}):
		push_error("[ROOM %s] Could not publish room presence" % room_code)


func _handle_room_control(sender_id: int, action: String, data: Array, generation: int) -> void:
	var player := int(_peer_to_player.get(sender_id, 0))
	if player == 0 or not _guard_room_message(sender_id, "room_control"):
		return
	if action in ["ready", "cancel", "start", "invalid_deck"] and generation != _preparation_generation:
		if action == "start" or (action == "cancel" and data == ["start_timeout"]):
			print("[ROOM %s] Ignored stale %s from preparation %d (current %d)" % [room_code, action, generation, _preparation_generation])
		return
	if action == "leave":
		_release_player(sender_id, true)
		NetworkManager.notify_room_preparation_reset.rpc_id(sender_id, "left", _preparation_generation)
		# Finish sending the confirmation before closing the transport. A lost
		# final disconnect packet must not keep blocking the vacated seat.
		peer.get_peer(sender_id).peer_disconnect_later()
		_departure_deadlines[sender_id] = _now() + NetworkManager.ROOM_LEAVE_TIMEOUT
	elif action == "start" and player == 1 and _room_can_prepare() and _ready_peers.size() == 2:
		if data.size() != 1 or not data[0] is String or not NetworkManager.valid_battle_match_id(data[0]):
			return
		NetworkManager.battle_match_id = data[0]
		match_active = true
		_preparation_generation += 1
		_ready_peers.clear()
		for client_id in _peer_to_player:
			_players_in_battle[client_id] = true
		_update_lifecycle_after_player_change()
		_publish_presence()
		var starting_player := NetworkManager.roll_opening_player()
		for client_id in _peer_to_player:
			NetworkManager.notify_room_match_started.rpc_id(client_id, NetworkManager.battle_match_id, starting_player)
	elif action == "return":
		var returned_from_battle := _players_in_battle.erase(sender_id)
		var returned_from_editor := _editors.erase(sender_id)
		if returned_from_battle and _players_in_battle.is_empty():
			_reset_match()
			_update_lifecycle_after_player_change()
			_publish_presence()
		if returned_from_battle or returned_from_editor:
			_notify_if_waiting()
	elif action == "edit" and _players_in_battle.is_empty():
		_editors[sender_id] = true
		_reset_preparation("editing")
	elif action == "cancel" and _room_can_prepare() and _ready_peers.has(sender_id):
		var reason := "cancelled"
		if _ready_peers.size() == 2:
			if player == 2 and data == ["offer_mismatch"]:
				reason = "offer_mismatch"
			elif data == ["start_timeout"]:
				reason = "start_timeout"
		_reset_preparation(reason)
	elif action == "invalid_deck" and _room_can_prepare() and _ready_peers.has(_player_to_peer[3 - player]):
		_reset_preparation("invalid_deck")
	elif action == "ready" and _room_can_prepare() and not _ready_peers.has(sender_id):
		if data.is_empty() or data.size() > DataSchema.MAX_CARDS_PER_DECK * 2 or var_to_bytes(data).size() > NetworkManager.MAX_ROOM_DECK_BYTES:
			_reset_preparation("invalid_deck")
			return
		_ready_peers[sender_id] = true
		var opponent := int(_player_to_peer[3 - player])
		NetworkManager.notify_room_deck_ready.rpc_id(opponent, data)


func _reset_preparation(reason: String) -> void:
	_ready_peers.clear()
	_preparation_generation += 1
	for client_id in _peer_to_player:
		NetworkManager.notify_room_preparation_reset.rpc_id(client_id, reason, _preparation_generation)


func _room_can_prepare() -> bool:
	return player_count == 2 and _players_in_battle.is_empty() and _editors.is_empty()


func _notify_if_waiting() -> void:
	if _room_can_prepare():
		for client_id in _peer_to_player:
			NetworkManager.notify_room_ready.rpc_id(client_id, _preparation_generation)
	elif player_count == 2 and not _editors.is_empty():
		_reset_preparation("editing")


func _reset_match() -> void:
	match_active = false
	NetworkManager.battle_match_id = ""
	_latest_revision = -1
	_latest_match_state.clear()
	_checkpoint_summaries.clear()
	_checkpoint_rejections.clear()


func _shutdown_if_empty() -> void:
	_enter_state(RoomState.EMPTY, EMPTY_SHUTDOWN_DELAY)


func _handle_authority_state(sender_id: int, state: Dictionary, command_id: String, status: String) -> void:
	if not match_active or not _players_in_battle.has(sender_id):
		return
	if int(_peer_to_player.get(sender_id, 0)) != 1:
		print("[SECURITY room=%s peer=%d kind=authority_state action=rejected_non_authority]" % [room_code, sender_id])
		return
	var revision := int(state.get("state_revision", -1))
	if revision < 0 or not state.has("player_field") or not state.has("player2_field"):
		return
	var reports_rejection := not command_id.is_empty() and command_id.length() <= 96 and status in ["rejected", "stale_revision"]
	if revision <= _latest_revision and not reports_rejection:
		return
	var encoded := JSON.stringify(state)
	if encoded.length() > MAX_SNAPSHOT_BYTES:
		print("[SECURITY room=%s peer=%d kind=authority_state bytes=%d action=rejected_oversize]" % [room_code, sender_id, encoded.length()])
		return
	if reports_rejection:
		_checkpoint_rejections[command_id] = {"revision": revision, "status": status}
		if _checkpoint_rejections.size() > MAX_CHECKPOINT_REJECTIONS:
			_checkpoint_rejections.erase(_checkpoint_rejections.keys()[0])
	if revision <= _latest_revision:
		return
	_latest_revision = revision
	_latest_match_state = state.duplicate(true)
	_remember_checkpoint_summaries(state)
	print("[ROOM %s] Stored authoritative snapshot revision %d" % [room_code, revision])


func _handle_command_checkpoint(sender_id: int, command_id: String, known_revision: int) -> void:
	if not match_active or not _players_in_battle.has(sender_id) or int(_peer_to_player.get(sender_id, 0)) != 2:
		return
	if not _guard_room_message(sender_id, "checkpoint") or _latest_revision < known_revision:
		return
	var rejection: Dictionary = _checkpoint_rejections.get(command_id, {})
	if _latest_revision == known_revision and (rejection.is_empty() or int(rejection["revision"]) > _latest_revision):
		return
	var checkpoint := _latest_match_state.duplicate()
	checkpoint["_feedback_events"] = _checkpoint_summaries.filter(func(summary): return summary["checkpoint_revision"] > known_revision)
	checkpoint.erase("_hp_events")
	checkpoint.erase("_checkpoint_rejection")
	if _latest_revision == known_revision:
		checkpoint["_checkpoint_rejection"] = rejection["status"]
	NetworkManager.send_room_command_checkpoint(sender_id, command_id, checkpoint)


func _remember_checkpoint_summaries(state: Dictionary) -> void:
	var feedback: Variant = state.get("_feedback_events", [])
	if not feedback is Array:
		return
	for event in feedback:
		if not event is Dictionary:
			continue
		var summary: Dictionary
		if event.get("kind") == "broadcast_text" and event.get("text_key") is String:
			summary = {"kind": "broadcast_text", "text_key": event["text_key"]}
		elif event.get("kind") == "broadcast" and event.get("event") is Dictionary:
			var action: Dictionary = event["event"].duplicate()
			for key in ["hp_events", "presentation_events", "damage_events", "parasite_events", "failed_events"]:
				action.erase(key)
			summary = {"kind": "broadcast", "event": action}
		else:
			continue
		summary["checkpoint_revision"] = _latest_revision
		summary["checkpoint_turn"] = maxi(1, int(state.get("turn_number", 1)))
		if var_to_bytes(summary).size() > MAX_CHECKPOINT_SUMMARY_BYTES:
			continue
		_checkpoint_summaries.append(summary)
		if _checkpoint_summaries.size() > MAX_CHECKPOINT_SUMMARIES:
			_checkpoint_summaries.pop_front()


func _relay_battle_chat(sender_id: int, phrase: int) -> void:
	var recipient := _battle_presence_recipient(sender_id, "battle_chat")
	if recipient > 0:
		NetworkManager.send_battle_chat_packet(recipient, phrase)


func _relay_battle_cursor(sender_id: int, point: Vector2) -> void:
	var recipient := _battle_presence_recipient(sender_id, "battle_cursor")
	if recipient > 0:
		NetworkManager.send_battle_cursor_packet(recipient, point)


func _battle_presence_recipient(sender_id: int, kind: String) -> int:
	if not _guard_room_message(sender_id, kind):
		return 0
	var player := int(_peer_to_player[sender_id])
	var recipient := int(_player_to_peer.get(3 - player, 0))
	return recipient if _players_in_battle.has(recipient) else 0


func _guard_room_message(sender_id: int, kind: String) -> bool:
	if not _peer_to_player.has(sender_id):
		return false
	if kind in ["intent", "recovery_intent", "authority_state", "state_request", "link_probe", "battle_chat", "battle_cursor"] and (not match_active or not _players_in_battle.has(sender_id)):
		return false
	var now := _now()
	var entry: Dictionary = _rate_windows.get(sender_id, {"started": now, "intent": 0, "resume": 0, "authority_state": 0, "art": 0})
	if now - float(entry.get("started", now)) >= 1.0:
		entry = {"started": now, "intent": 0, "resume": 0, "authority_state": 0, "art": 0}
	entry[kind] = int(entry.get(kind, 0)) + 1
	_rate_windows[sender_id] = entry
	if kind == "battle_chat":
		return int(entry[kind]) <= 3
	if kind == "battle_cursor":
		return int(entry[kind]) <= 16
	if kind in ["checkpoint", "link_probe", "waiting_link_probe", "waiting_link_recovery"]:
		# After a stall, ENet can deliver several legitimate retries at once.
		return int(entry[kind]) <= 3
	var limit := 60
	if kind == "resume":
		limit = 20
	elif kind == "authority_state":
		limit = 12
	elif kind == "art":
		limit = 180
	if int(entry[kind]) <= limit:
		return true
	print("[SECURITY room=%s peer=%d player=%d kind=%s rate=%d limit=%d action=disconnect]" % [room_code, sender_id, int(_peer_to_player.get(sender_id, 0)), kind, int(entry[kind]), limit])
	call_deferred("_disconnect_rejected_peer", sender_id)
	return false

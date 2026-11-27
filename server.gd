extends Node

const RoomPresenceStore = preload("res://RoomPresenceStore.gd")
const Matchmaking = preload("res://MatchmakingQueue.gd")
const Rating = preload("res://RankedRating.gd")
const MatchIdentity = preload("res://MatchmakingIdentity.gd")

# ============================================
# Multi-room lobby server
# Clients connect to lobby port 4567, create/join a room code, then
# connect to a room-specific port (5001-5020) served by a dedicated
# room_server.tscn subprocess (one process per room).
#
# Port range can be overridden from the command line:
#   CardGame.exe --headless -- --lobby-port=4567 --port-start=5001 --port-end=5020
# ============================================

const DEFAULT_LOBBY_PORT := 4567
const DEFAULT_GAME_PORT_START := 5001
const DEFAULT_GAME_PORT_END := 5020
const MAX_ROOM_CODE_LEN := 16
const ROOM_REAP_INTERVAL := 2.0  # seconds between checks for exited room subprocesses
const ROOM_SPAWN_GRACE := 8.0    # seconds a new room is protected from reaping while it binds its port
const JOIN_RESERVATION_TTL := 15.0
const MATCHMAKING_DIR := "user://matchmaking"

var lobby_port: int = DEFAULT_LOBBY_PORT
var game_port_start: int = DEFAULT_GAME_PORT_START
var game_port_end: int = DEFAULT_GAME_PORT_END
# Card-art relay is opt-in (bandwidth). Enable with --allow-card-art at launch.
var allow_card_art: bool = false

var lobby_peer: ENetMultiplayerPeer
var rooms: Dictionary = {}     # { code: {port, pid, created_at, players, tokens} }
var used_ports: Dictionary = {}  # { port: true } — ports currently allocated to a room
var _reap_accum: float = 0.0
var _matching_accum: float = 0.0
var _matchmaking := Matchmaking.new()
var _rating := Rating.new("user://ranked_matches.jsonl")
var _match_challenges: Dictionary = {}


func _ready():
	if _is_room_server_mode():
		_start_room_server_mode()
		return
	_parse_args()
	_recover_matchmaking()
	if not _start_lobby():
		push_error("[SERVER] Failed to start lobby — shutting down")
		get_tree().quit(1)


func _is_room_server_mode() -> bool:
	return OS.get_cmdline_user_args().has("--room-server")


func _start_room_server_mode() -> void:
	set_process(false)
	var room := Node.new()
	room.set_script(load("res://room_server.gd"))
	add_child(room)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lobby-port="):
			lobby_port = int(arg.split("=")[1])
		elif arg.begins_with("--port-start="):
			game_port_start = int(arg.split("=")[1])
		elif arg.begins_with("--port-end="):
			game_port_end = int(arg.split("=")[1])
		elif arg == "--allow-card-art":
			allow_card_art = true
	if game_port_end < game_port_start:
		push_warning("[SERVER] port-end < port-start; swapping")
		var tmp := game_port_start
		game_port_start = game_port_end
		game_port_end = tmp


func _start_lobby() -> bool:
	lobby_peer = ENetMultiplayerPeer.new()
	var err := lobby_peer.create_server(lobby_port, 32)
	if err != OK:
		lobby_peer = null
		push_error("[SERVER] Could not bind lobby port %d (err=%d) — is it already in use?" % [lobby_port, err])
		return false
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = lobby_peer
	lobby_peer.peer_connected.connect(_on_lobby_peer_connected)
	lobby_peer.peer_disconnected.connect(_on_lobby_peer_disconnected)
	# Lobby RPCs land on the shared NetworkManager autoload node on both ends.
	# Register our handler so those packets reach this script.
	NetworkManager.lobby_request_handler = Callable(self, "_handle_lobby_request")
	print("[SERVER] Lobby listening on port %d (game ports %d-%d)" % [lobby_port, game_port_start, game_port_end])
	print("[SERVER] Card-art relay: %s" % ("ENABLED" if allow_card_art else "DISABLED (use --allow-card-art to enable)"))
	return true


func _on_lobby_peer_connected(id: int):
	print("[SERVER] Peer %d connected to lobby" % id)


func _on_lobby_peer_disconnected(id: int):
	_matchmaking.remove(id)
	_match_challenges.erase(id)
	print("[SERVER] Peer %d disconnected from lobby" % id)


func _process(delta):
	_matching_accum += delta
	if _matching_accum >= 0.4:
		_matching_accum = 0.0
		_dispatch_match_assignments()
		_update_matchmaking()
	_reap_accum += delta
	if _reap_accum >= ROOM_REAP_INTERVAL:
		_reap_accum = 0.0
		_reap_finished_rooms()


# ============================================
# Room subprocess lifecycle
# ============================================

func _reap_finished_rooms() -> void:
	# A room subprocess holds its UDP port for as long as it runs and releases
	# it on exit. PID tracking is unreliable here because OS.get_executable_path()
	# is a console wrapper that spawns the real process as a short-lived child,
	# so we detect a dead room by probing whether its port is bindable again.
	# A freshly-spawned room gets a grace period before it's eligible for reaping.
	var now: float = Time.get_ticks_msec() / 1000.0
	var finished: Array = []
	for code in rooms:
		var room = rooms[code]
		if room.has("matchmaking") and not _collect_match_result(code, room):
			continue
		var age: float = now - float(room["created_at"])
		if age < ROOM_SPAWN_GRACE:
			continue
		if _is_port_free(room["port"]) and (not room.has("matchmaking") or _collect_match_result(code, room)):
			finished.append(code)
	for code in finished:
		_free_room(code)


func _is_port_free(port: int) -> bool:
	# Returns true if nothing is listening on the UDP port (room process gone).
	var probe := UDPServer.new()
	var err := probe.listen(port)
	if err == OK:
		probe.stop()
		return true
	return false


func _find_free_port() -> int:
	for port in range(game_port_start, game_port_end + 1):
		if used_ports.has(port):
			continue
		# Verify the port is actually bindable — an external process may hold it
		# even though our in-memory pool thinks it's free. Skipping it here avoids
		# telling a client "ok" for a room whose subprocess will fail to bind.
		if not _is_port_free(port):
			continue
		return port
	return -1


func _free_room(code: String) -> void:
	var room = rooms.get(code)
	if room:
		var presence_path := str(room.get("presence_path", ""))
		if not presence_path.is_empty() and FileAccess.file_exists(presence_path):
			DirAccess.remove_absolute(presence_path)
		if room.has("matchmaking"):
			_reject_match_assignments(code, room)
			DirAccess.remove_absolute(_match_path(code, ".pending"))
			for suffix in [".settled", ".settled.tmp"]:
				var path := _match_path(code, suffix)
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
			if FileAccess.file_exists(_match_path(code, ".ready")):
				DirAccess.remove_absolute(_match_path(code, ".ready"))
			if FileAccess.file_exists(_match_path(code, ".cancel")):
				DirAccess.remove_absolute(_match_path(code, ".cancel"))
		used_ports.erase(room["port"])
		rooms.erase(code)
		print("[SERVER] Room %s freed (port %d released)" % [code, room["port"]])


# ============================================
# Lobby request handling — invoked via NetworkManager.lobby_request_handler
# ============================================

func _handle_lobby_request(sender_id: int, json_str: String) -> void:
	var json := JSON.new()
	if json.parse(json_str) != OK:
		print("[SERVER] Malformed request from peer %d (ignored)" % sender_id)
		return
	var data = json.get_data()
	if not data is Dictionary:
		print("[SERVER] Non-dict request from peer %d (ignored)" % sender_id)
		return

	var action: String = str(data.get("action", ""))
	var code: String = str(data.get("code", ""))
	var protocol := int(data.get("protocol", 0))
	if protocol != AppVersion.PROTOCOL_VERSION:
		NetworkManager.send_lobby_response(sender_id, JSON.stringify({
			"status": "protocol_mismatch", "protocol": AppVersion.PROTOCOL_VERSION,
		}))
		print("[SERVER] Protocol mismatch from peer %d: client=%d server=%d" % [sender_id, protocol, AppVersion.PROTOCOL_VERSION])
		return

	if action == "status":
		NetworkManager.send_lobby_response(sender_id, JSON.stringify({
			"status": "server_status",
			"ok": true,
			"rooms": rooms.size(),
			"port_start": game_port_start,
			"port_end": game_port_end,
			"card_art": allow_card_art,
			"protocol": AppVersion.PROTOCOL_VERSION,
		}))
		print("[SERVER] Status requested by peer %d" % sender_id)

	elif action in ["party_create", "party_join"]:
		_handle_party_request(sender_id, action, code, data.get("seats", 3))
	elif action in ["matchmaking_challenge", "matchmaking_profile", "matchmaking_join", "matchmaking_cancel"]:
		_handle_matchmaking_request(sender_id, action, data)
	elif action == "create":
		if not _is_valid_code(code):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "invalid_code"}))
			print("[SERVER] Peer %d sent invalid room code (rejected)" % sender_id)
		elif rooms.has(code):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "taken"}))
			print("[SERVER] Room '%s' creation rejected (taken)" % code)
		else:
			var port := _find_free_port()
			if port < 0:
				NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "no_ports"}))
				print("[SERVER] Room '%s' creation failed (no free ports)" % code)
			else:
				var p1_token := _new_reconnect_token()
				var p2_token := _new_reconnect_token()
				var presence_path := ProjectSettings.globalize_path("user://room_presence_%d_%s.json" % [port, _new_reconnect_token().left(16)])
				var pid := _spawn_room(code, port, p1_token, p2_token, presence_path)
				if pid <= 0:
					NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "no_ports"}))
					print("[SERVER] Room '%s' subprocess spawn failed" % code)
				else:
					used_ports[port] = true
					rooms[code] = {
						"port": port,
						"pid": pid,
						"created_at": Time.get_ticks_msec() / 1000.0,
						"players": 1,
						"p2_reserved_until": 0.0,
						"p1_reserved_until": Time.get_ticks_msec() / 1000.0 + JOIN_RESERVATION_TTL,
						"presence_path": presence_path,
						"tokens": {1: p1_token, 2: p2_token},
					}
					NetworkManager.send_lobby_response(sender_id, JSON.stringify({
						"status": "ok", "port": port, "player": 1,
						"reconnect_token": p1_token, "card_art": allow_card_art,
						"protocol": AppVersion.PROTOCOL_VERSION,
					}))
					print("[SERVER] Room '%s' created on port %d (pid %d)" % [code, port, pid])

	elif action == "join":
		if not _is_valid_code(code):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "invalid_code"}))
			print("[SERVER] Peer %d sent invalid room code (rejected)" % sender_id)
			return
		var room = rooms.get(code)
		if room != null and room.get("party", false):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "not_found"}))
			return
		if room != null and not _refresh_room_presence(room):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "room_starting"}))
			return
		if room == null or room.get("party", false):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "not_found"}))
			print("[SERVER] Room '%s' not found" % code)
		elif bool(room.get("match_active", false)):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "in_progress"}))
		elif room.get("occupied", []).size() >= 2:
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "full"}))
			print("[SERVER] Room '%s' has no free seat (join rejected)" % code)
		else:
			var now := Time.get_ticks_msec() / 1000.0
			var attempt_id := str(data.get("attempt_id", ""))
			if attempt_id.length() != 32 or not attempt_id.is_valid_hex_number(false):
				attempt_id = ""
			var player := _reserved_player_for_attempt(room, now, attempt_id)
			if player > 0:
				_send_join_assignment(sender_id, room, player)
				print("[SERVER] Room '%s' resumed the existing P%d reservation" % [code, player])
			elif has_active_join_reservation(room, now):
				NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "full", "seat_reserved": true}))
				print("[SERVER] Room '%s' has an active P2 reservation (join rejected)" % code)
			else:
				player = 2
				if not room.get("occupied", []).has(1) and float(room.get("p1_reserved_until", 0.0)) <= now:
					player = 1
				room["p%d_reserved_until" % player] = now + JOIN_RESERVATION_TTL
				room["p%d_join_attempt" % player] = attempt_id
				_send_join_assignment(sender_id, room, player)
				print("[SERVER] Peer %d reserved P%d in room '%s' on port %d for %.0fs" % [sender_id, player, code, room["port"], JOIN_RESERVATION_TTL])

	elif action == "reconnect":
		var requested_player := int(data.get("player", 0))
		var reconnect_token := str(data.get("reconnect_token", ""))
		if not _is_valid_code(code) or requested_player not in [1, 2] or reconnect_token == "":
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "invalid_reconnect"}))
			return
		var room = rooms.get(code)
		if room == null:
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "not_found"}))
			return
		if not _refresh_room_presence(room):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "room_starting"}))
			return
		if _is_port_free(int(room.get("port", 0))):
			_free_room(code)
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "not_found"}))
			return
		var tokens: Dictionary = room.get("tokens", {})
		if reconnect_token != str(tokens.get(requested_player, "")):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "invalid_reconnect"}))
			print("[SERVER] Invalid reconnect token for room '%s' P%d" % [code, requested_player])
			return
		NetworkManager.send_lobby_response(sender_id, JSON.stringify({
			"status": "ok", "port": room["port"], "player": requested_player,
			"reconnect_token": reconnect_token, "card_art": allow_card_art,
			"protocol": AppVersion.PROTOCOL_VERSION,
		}))
		print("[SERVER] Reconnect approved for room '%s' P%d" % [code, requested_player])

	else:
		print("[SERVER] Unknown action '%s' from peer %d (ignored)" % [action, sender_id])


func _handle_party_request(sender: int, action: String, code: String, seats: Variant) -> void:
	var response := {"status": "invalid_code"}
	if _is_valid_code(code):
		var existing: Dictionary = rooms.get(code, {})
		if action == "party_join":
			response.status = "not_found"
			if existing.get("party", false):
				response = {"status": "ok", "port": existing.port, "invite": existing.invite}
		elif not existing.is_empty():
			response.status = "taken"
		elif (seats is float or seats is int) and float(seats) >= 3.0 and float(seats) <= 5.0 \
			and float(seats) == floorf(float(seats)):
			response.status = "no_ports"
			var port := _find_free_port()
			if port > 0:
				var invite := Crypto.new().generate_random_bytes(16).hex_encode()
				var owner := Crypto.new().generate_random_bytes(16).hex_encode()
				var pid := _spawn_party_room(port, int(seats), invite, owner)
				if pid > 0:
					rooms[code] = {"party": true, "port": port, "pid": pid, "invite": invite,
						"created_at": Time.get_ticks_msec() / 1000.0}
					used_ports[port] = true
					response = {"status": "ok", "port": port, "invite": owner}
					print("[SERVER] Party room '%s' created on port %d for %d players" % [code, port, int(seats)])
	NetworkManager.send_lobby_response(sender, JSON.stringify(response))


func _spawn_party_room(port: int, seats: int, invite: String, owner: String,
		mode: String = "", result_path: String = "", ratings: Array = []) -> int:
	var arguments := PackedStringArray(["--headless"])
	if OS.has_feature("editor"):
		arguments.append_array(["--path", ProjectSettings.globalize_path("res://")])
	arguments.append_array(["--", "--party-server", "--party-port=%d" % port, "--party-size=%d" % seats])
	var previous_invite := OS.get_environment("CARDEX_PARTY_INVITE")
	var previous_owner := OS.get_environment("CARDEX_PARTY_OWNER")
	var previous_mode := OS.get_environment("CARDEX_MATCHMAKING_MODE")
	var previous_result := OS.get_environment("CARDEX_MATCH_RESULT")
	var previous_ratings := OS.get_environment("CARDEX_MATCH_RATINGS")
	OS.set_environment("CARDEX_PARTY_INVITE", invite)
	OS.set_environment("CARDEX_PARTY_OWNER", owner)
	OS.set_environment("CARDEX_MATCHMAKING_MODE", mode)
	OS.set_environment("CARDEX_MATCH_RESULT", result_path)
	OS.set_environment("CARDEX_MATCH_RATINGS", JSON.stringify(ratings))
	var pid := OS.create_process(OS.get_executable_path(), arguments)
	OS.set_environment("CARDEX_PARTY_INVITE", previous_invite)
	OS.set_environment("CARDEX_PARTY_OWNER", previous_owner)
	OS.set_environment("CARDEX_MATCHMAKING_MODE", previous_mode)
	OS.set_environment("CARDEX_MATCH_RESULT", previous_result)
	OS.set_environment("CARDEX_MATCH_RATINGS", previous_ratings)
	return pid


func _handle_matchmaking_request(sender: int, action: String, data: Dictionary) -> void:
	if data.get("pack_protocol", 0) != Matchmaking.PACK_PROTOCOL:
		_matchmaking_reply(sender, "protocol_mismatch")
		return
	if action == "matchmaking_cancel":
		_matchmaking.remove(sender)
		_matchmaking_reply(sender, "cancelled")
		return
	var mode := str(data.get("mode", ""))
	if not Matchmaking.valid_mode(mode):
		_matchmaking_reply(sender, "invalid_mode")
		return
	var now := Time.get_ticks_msec()
	if action == "matchmaking_challenge":
		var nonce := Crypto.new().generate_random_bytes(32).hex_encode()
		_match_challenges[sender] = {"nonce": nonce, "expires": now + 10000}
		_matchmaking_reply(sender, "challenge", {"nonce": nonce})
		return
	var challenge: Dictionary = _match_challenges.get(sender, {})
	_match_challenges.erase(sender)
	var proof: Variant = data.get("proof")
	if challenge.is_empty() or int(challenge.expires) < now or not proof is Dictionary:
		_matchmaking_reply(sender, "invalid_profile")
		return
	var profile_id := MatchIdentity.verify(proof, challenge.nonce, action.trim_prefix("matchmaking_"), mode)
	if profile_id.is_empty():
		_matchmaking_reply(sender, "invalid_profile")
		return
	for match_id in rooms:
		var room: Dictionary = rooms[match_id]
		if profile_id in room.get("match_profiles", []):
			_collect_match_result(match_id, room)
	var profile := _rating.profile(profile_id)
	if mode == Matchmaking.RANKED:
		var ids: Variant = proof.get("history_pending", [])
		var settlements := {}
		if ids is Array:
			for value in ids.slice(0, PlayerData.MAX_MATCH_HISTORY):
				if not value is String or value.length() != 28 or not value.is_valid_hex_number(false):
					continue
				var entry := _rating.settlement_for(value, profile_id)
				if not entry.is_empty():
					settlements[value] = entry
		profile["history_settlements"] = settlements
	if action == "matchmaking_profile":
		_matchmaking_reply(sender, "profile", profile)
		return
	for room: Dictionary in rooms.values():
		if profile_id in room.get("match_profiles", []) and not room.get("settled", false):
			_matchmaking_reply(sender, "already_playing")
			return
	if mode == Matchmaking.RANKED and not _rating.can_save:
		_matchmaking_reply(sender, "rating_unavailable")
		return
	if not _matchmaking.add(sender, profile_id, mode, int(profile.rating), now):
		_matchmaking_reply(sender, "already_waiting")
		return
	_matchmaking_reply(sender, "waiting", profile)
	_update_matchmaking()


func _update_matchmaking() -> void:
	var now := Time.get_ticks_msec()
	for waiter in _matchmaking.expire(now):
		_matchmaking_reply(waiter, "expired")
	var pair := _matchmaking.find_pair(now)
	if pair.is_empty():
		return
	var port := _find_free_port()
	if port <= 0:
		return
	var code := Crypto.new().generate_random_bytes(14).hex_encode()
	var first_token := Crypto.new().generate_random_bytes(16).hex_encode()
	var second_token := Crypto.new().generate_random_bytes(16).hex_encode()
	var mode := str(pair[0].mode)
	var profiles := [pair[0].profile, pair[1].profile]
	var result_path := _match_path(code, ".result")
	if not _save_pending_match(code, port, mode, profiles):
		for entry in pair:
			_matchmaking.remove(entry.peer)
			_matchmaking_reply(entry.peer, "rating_unavailable")
		return
	var pid := _spawn_party_room(port, 2, second_token, first_token,
		mode, result_path, [pair[0].rating, pair[1].rating])
	if pid <= 0:
		DirAccess.remove_absolute(_match_path(code, ".pending"))
		return
	used_ports[port] = true
	rooms[code] = {"port": port, "pid": pid, "created_at": float(now) / 1000.0,
		"matchmaking": mode, "match_profiles": profiles, "result_path": result_path,
		"assignments": {pair[0].peer: first_token, pair[1].peer: second_token},
		"waiters": pair}
	for index in pair.size():
		_matchmaking.remove(pair[index].peer)


func _dispatch_match_assignments() -> void:
	for code in rooms:
		var room: Dictionary = rooms[code]
		if not room.has("assignments"):
			continue
		var connected := multiplayer.get_peers()
		for peer_id: int in room.assignments:
			if not connected.has(peer_id):
				_reject_match_assignments(code, room, true)
				break
		var ready_path := _match_path(code, ".ready")
		if not room.has("assignments") or not FileAccess.file_exists(ready_path):
			continue
		for peer_id: int in room.assignments:
			_matchmaking_reply(peer_id, "matched", {"port": room.port, "mode": room.matchmaking,
				"invite": room.assignments[peer_id]})
		room.erase("assignments")
		room.erase("waiters")
		DirAccess.remove_absolute(ready_path)


func _reject_match_assignments(code: String, room: Dictionary, resume_queue: bool = false) -> void:
	var assignments: Dictionary = room.get("assignments", {})
	if assignments.is_empty():
		return
	var connected := multiplayer.get_peers()
	room.erase("assignments")
	room["settled"] = true
	if resume_queue:
		# The worker may still be starting. It observes this before accepting a match.
		var cancel_file := FileAccess.open(_match_path(code, ".cancel"), FileAccess.WRITE)
		if cancel_file != null:
			cancel_file.close()
	for waiter: Dictionary in room.get("waiters", []):
		var peer_id := int(waiter.peer)
		if not connected.has(peer_id):
			continue
		if not resume_queue or not _matchmaking.add(peer_id, waiter.profile, waiter.mode, waiter.rating, waiter.since):
			_matchmaking_reply(peer_id, "room_unavailable")
	room.erase("waiters")


func _matchmaking_reply(peer_id: int, status: String, data: Dictionary = {}) -> void:
	data["status"] = status
	data["pack_protocol"] = Matchmaking.PACK_PROTOCOL
	NetworkManager.send_lobby_response(peer_id, JSON.stringify(data))


func _match_path(code: String, suffix: String) -> String:
	return ProjectSettings.globalize_path(MATCHMAKING_DIR.path_join(code + suffix))


func _save_pending_match(code: String, port: int, mode: String, profiles: Array) -> bool:
	var buffer := _match_path(code, ".tmp")
	var file := FileAccess.open(buffer, FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify({"port": port, "mode": mode, "profiles": profiles})):
		return false
	file.close()
	return DirAccess.rename_absolute(buffer, _match_path(code, ".pending")) == OK


func _recover_matchmaking() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATCHMAKING_DIR))
	for filename in DirAccess.get_files_at(MATCHMAKING_DIR):
		var code := filename.get_basename()
		if filename.get_extension() != "pending" or code.length() != 28 or not code.is_valid_hex_number(false):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_match_path(code, ".pending")))
		if not data is Dictionary:
			continue
		var port := int(data.get("port", 0))
		var mode := str(data.get("mode", ""))
		var profiles: Variant = data.get("profiles")
		if not Matchmaking.valid_mode(mode) or not profiles is Array or profiles.size() != 2 or port not in range(1, 65536):
			continue
		rooms[code] = {"port": port, "created_at": -ROOM_SPAWN_GRACE,
			"matchmaking": mode, "match_profiles": profiles, "result_path": _match_path(code, ".result")}
		used_ports[port] = true


func _collect_match_result(code: String, room: Dictionary) -> bool:
	if room.get("settled", false) or not FileAccess.file_exists(room.result_path):
		return true
	var contents := FileAccess.get_file_as_string(room.result_path).strip_edges()
	var receipt: Variant = JSON.parse_string(contents)
	var winner := int(receipt.get("winner", 0)) if receipt is Dictionary else contents.to_int()
	var multipliers: Variant = receipt.get("multipliers", []) if receipt is Dictionary else []
	if winner not in [1, 2, 3]:
		push_error("[SERVER] Invalid duel result " + code)
		return true
	if room.matchmaking == Matchmaking.RANKED:
		if not _rating.settle(code, room.match_profiles[0], room.match_profiles[1], winner,
				multipliers if multipliers is Array else []):
			return false
		var temporary := _match_path(code, ".settled.tmp")
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file != null and file.store_string(JSON.stringify([
				_rating.settlement_for(code, room.match_profiles[0]),
				_rating.settlement_for(code, room.match_profiles[1]),
		])):
			file.close()
			DirAccess.rename_absolute(temporary, _match_path(code, ".settled"))
	room["settled"] = true
	DirAccess.remove_absolute(_match_path(code, ".pending"))
	DirAccess.remove_absolute(room.result_path)
	return true


func _send_join_assignment(peer_id: int, room: Dictionary, player: int) -> void:
	var tokens: Dictionary = room["tokens"]
	NetworkManager.send_lobby_response(peer_id, JSON.stringify({
		"status": "ok", "port": room["port"], "player": player,
		"reconnect_token": str(tokens.get(player, "")), "card_art": allow_card_art,
		"protocol": AppVersion.PROTOCOL_VERSION,
	}))


func _reserved_player_for_attempt(room: Dictionary, now: float, attempt_id: String) -> int:
	if attempt_id.is_empty():
		return 0
	for player in [1, 2]:
		if float(room.get("p%d_reserved_until" % player, 0.0)) > now and room.get("p%d_join_attempt" % player) == attempt_id:
			return player
	return 0


func _spawn_room(code: String, port: int, p1_token: String, p2_token: String, presence_path: String = "") -> int:
	# Launch a dedicated relay subprocess for this room.
	var exe := OS.get_executable_path()
	var args := PackedStringArray([
		"--headless",
	])
	if OS.has_feature("editor"):
		args.append_array(PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]))
	args.append_array(PackedStringArray([
		"--",
		"--room-server", "--room-port=%d" % port, "--room-code=%s" % code,
		"--p1-token=%s" % p1_token, "--p2-token=%s" % p2_token,
		"--presence-file=%s" % presence_path,
	]))
	var pid := OS.create_process(exe, args)
	return pid


func _refresh_room_presence(room: Dictionary) -> bool:
	var presence := RoomPresenceStore.read(str(room.get("presence_path", "")))
	if presence.is_empty(): return false
	var tokens: Dictionary = room.get("tokens", {})
	var occupied: Array = []
	for seat in presence.occupied:
		occupied.append(int(seat))
	for player in [1, 2]:
		var token := str(presence.tokens.get(str(player), ""))
		if token.is_empty(): return false
		if token != str(tokens.get(player, "")) or occupied.has(player):
			room["p%d_reserved_until" % player] = 0.0
			room.erase("p%d_join_attempt" % player)
		tokens[player] = token
	room["tokens"] = tokens
	room["occupied"] = occupied
	room["match_active"] = bool(presence.get("match_active", false))
	return true


func _new_reconnect_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(24).hex_encode()


static func has_active_join_reservation(room: Dictionary, now: float) -> bool:
	return float(room.get("p2_reserved_until", 0.0)) > now


func _is_valid_code(code: String) -> bool:
	if code.length() < 1 or code.length() > MAX_ROOM_CODE_LEN:
		return false
	for c in code:
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")):
			return false
	return true

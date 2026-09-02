extends Node

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

var lobby_port: int = DEFAULT_LOBBY_PORT
var game_port_start: int = DEFAULT_GAME_PORT_START
var game_port_end: int = DEFAULT_GAME_PORT_END
# Card-art relay is opt-in (bandwidth). Enable with --allow-card-art at launch.
var allow_card_art: bool = false

var lobby_peer: ENetMultiplayerPeer
var rooms: Dictionary = {}     # { code: {port, pid, created_at, players, tokens} }
var used_ports: Dictionary = {}  # { port: true } — ports currently allocated to a room
var _reap_accum: float = 0.0


func _ready():
	if _is_room_server_mode():
		_start_room_server_mode()
		return
	_parse_args()
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
	print("[SERVER] Peer %d disconnected from lobby" % id)


func _process(delta):
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
		var age: float = now - float(room["created_at"])
		if age < ROOM_SPAWN_GRACE:
			continue
		if _is_port_free(room["port"]):
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
				var pid := _spawn_room(code, port, p1_token, p2_token)
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
		if room == null:
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "not_found"}))
			print("[SERVER] Room '%s' not found" % code)
		elif has_active_join_reservation(room, Time.get_ticks_msec() / 1000.0):
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({"status": "full"}))
			print("[SERVER] Room '%s' has an active P2 reservation (join rejected)" % code)
		else:
			var now := Time.get_ticks_msec() / 1000.0
			room["p2_reserved_until"] = now + JOIN_RESERVATION_TTL
			var tokens: Dictionary = room.get("tokens", {})
			NetworkManager.send_lobby_response(sender_id, JSON.stringify({
				"status": "ok", "port": room["port"], "player": 2,
				"reconnect_token": str(tokens.get(2, "")), "card_art": allow_card_art,
				"protocol": AppVersion.PROTOCOL_VERSION,
			}))
			print("[SERVER] Peer %d reserved P2 in room '%s' on port %d for %.0fs" % [sender_id, code, room["port"], JOIN_RESERVATION_TTL])

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


func _spawn_room(code: String, port: int, p1_token: String, p2_token: String) -> int:
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
	]))
	var pid := OS.create_process(exe, args)
	return pid


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

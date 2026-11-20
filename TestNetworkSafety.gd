extends Node

const LobbyServer = preload("res://server.gd")
const BattleMainActions = preload("res://BattleMainActions.gd")
const SnapshotWire = preload("res://BattleSnapshotWire.gd")


func _ready() -> void:
	_assert(NetworkManager.is_remote_player_claim_valid(1, 2), "P1 must accept P2 claims")
	_assert(NetworkManager.is_remote_player_claim_valid(2, 1), "P2 must accept P1 claims")
	_assert(not NetworkManager.is_remote_player_claim_valid(1, 1), "self-player spoof must be rejected")
	_assert(not NetworkManager.is_remote_player_claim_valid(0, 1), "unassigned player must be rejected")

	var state := {
		"player_field": {},
		"player2_field": {},
		"player_hand": [],
		"player2_hand": [],
		"shared_deck": [],
		"state_revision": 7,
	}
	var payload := {
		"schema": NetworkManager.MATCH_SNAPSHOT_SCHEMA,
		"room_code": "SAFE42",
		"player": 1,
		"state": state,
	}
	_assert(NetworkManager.is_valid_snapshot_payload(payload), "valid battle snapshot must be accepted")
	var invalid_payload: Dictionary = payload.duplicate(true)
	invalid_payload["state"].erase("state_revision")
	_assert(not NetworkManager.is_valid_snapshot_payload(invalid_payload), "snapshot without revision must be rejected")

	var rng_state: int = 9007199254740993
	state["rng_seed"] = -rng_state
	state["rng_state"] = rng_state
	var encoded_state := NetworkManager.encode_match_state_for_snapshot(state)
	var round_trip := NetworkManager.decode_match_state_from_snapshot(
		JSON.parse_string(JSON.stringify(encoded_state)) as Dictionary
	)
	_assert(int(round_trip["rng_seed"]) == -rng_state, "64-bit RNG seed must survive JSON")
	_assert(int(round_trip["rng_state"]) == rng_state, "64-bit RNG state must survive JSON")
	var wire_state := state.duplicate(true)
	for card in CardDatabase.beginner_deck():
		wire_state.shared_deck.append(PlayerData.serialize_card(card))
	var wire_data := SnapshotWire.encode(wire_state)
	_assert(var_to_bytes(wire_data).size() < var_to_bytes(wire_state).size(), "a full deck must produce a smaller network payload")
	_assert(SnapshotWire.decode(wire_data) == wire_state, "compressed state must preserve ordered cards and exact 64-bit integers")
	var oversized := wire_data.duplicate()
	oversized["raw_bytes"] = SnapshotWire.MAX_PACKED_RAW_BYTES + 1
	_assert(SnapshotWire.decode(oversized).is_empty(), "unpacking must reject an excessive declared size")

	_assert(is_equal_approx(NetworkManager.reconnect_retry_delay(1, 0.5), 0.5), "first reconnect retry must be fast")
	_assert(is_equal_approx(NetworkManager.reconnect_retry_delay(2, 0.5), 1.0), "reconnect retry must back off exponentially")
	_assert(is_equal_approx(NetworkManager.reconnect_retry_delay(8, 0.5), 8.0), "reconnect retry must be capped")
	_assert(NetworkManager.reconnect_retry_delay(3, 0.0) < NetworkManager.reconnect_retry_delay(3, 1.0), "reconnect jitter must vary retry timing")
	var discovery_packet := NetworkManager._encode_lan_discovery_packet({"kind": "room", "protocol": AppVersion.PROTOCOL_VERSION, "port": 4568})
	var discovery_payload := NetworkManager._decode_lan_discovery_packet(discovery_packet)
	_assert(str(discovery_payload.get("kind", "")) == "room", "LAN discovery packet must round-trip")
	_assert(NetworkManager._decode_lan_discovery_packet("not-json".to_utf8_buffer()).is_empty(), "malformed LAN discovery packet must be ignored")
	await _check_discovery_refresh()

	var room := {"p2_reserved_until": 115.0}
	_assert(LobbyServer.has_active_join_reservation(room, 114.9), "active join reservation must block duplicate joins")
	_assert(not LobbyServer.has_active_join_reservation(room, 115.0), "abandoned join reservation must expire")
	_assert(AppVersion.PROTOCOL_VERSION >= 5, "current reconnect and command envelope requires protocol version 5 or newer")
	_assert(NetworkManager.GAME_CHANNEL_COUNT >= 5, "game transport must preserve the protocol-v5 channel layout")
	_assert(NetworkManager.COMMAND_TOTAL_TIMEOUT > NetworkManager.COMMAND_RECEIPT_TIMEOUT, "pending commands need a finite recovery timeout")
	NetworkManager._pending_game_commands = {
		"same-revision": {"kind": "summon", "expected_revision": 12, "created_at": NetworkManager._now()},
	}
	NetworkManager.reconcile_pending_game_commands(12)
	_assert(NetworkManager.pending_game_command_count() == 1, "same-revision broadcasts must not silently consume a pending command")
	NetworkManager.reconcile_pending_game_commands(12, true)
	_assert(NetworkManager.pending_game_command_count() == 0, "full resync must release a stuck pending command")
	NetworkManager._pending_game_commands = {
		"older-command": {"kind": "end_turn", "expected_revision": 12, "created_at": NetworkManager._now()},
	}
	NetworkManager.reconcile_pending_game_commands(13)
	_assert(NetworkManager.pending_game_command_count() == 0, "newer authority state must release an obsolete pending command")
	_check_rejected_command_chain()
	_assert(BattleMainActions.end_turn_execution_path(false, true) == "local", "offline end turn must use the local path")
	_assert(BattleMainActions.end_turn_execution_path(true, true) == "authority", "online authority must not fall through into the local end-turn path")
	_assert(BattleMainActions.end_turn_execution_path(true, false) == "remote", "online subordinate must send an intent instead of mutating locally")

	print("TEST_NETWORK_SAFETY_OK")
	get_tree().quit(0)


func _check_rejected_command_chain() -> void:
	NetworkManager._clear_outgoing_game_commands()
	NetworkManager._pending_game_commands = {
		"head": {"kind": "discard", "expected_revision": 12},
		"middle": {"kind": "discard", "expected_revision": 13, "after_move": "head"},
		"tail": {"kind": "discard", "expected_revision": 14, "after_move": "middle"},
		"independent": {"kind": "end_turn", "expected_revision": 14},
	}
	NetworkManager.reconcile_pending_game_commands(14)
	var rejection_notices: Array[String] = []
	var record := func(command_id: String, _kind: String, status: String, _latency: int):
		if status == "rejected" or status == "stale_revision":
			rejection_notices.append(command_id)
	NetworkManager.game_command_status.connect(record)
	NetworkManager.acknowledge_game_command("head", 14, "rejected")
	_assert(NetworkManager.pending_game_command_count() == 1, "rejecting the first command must release its dependent commands")
	NetworkManager.acknowledge_game_command("middle", 14, "stale_revision")
	NetworkManager.acknowledge_game_command("tail", 14, "stale_revision")
	NetworkManager.acknowledge_game_command("independent", 14, "rejected")
	_assert(rejection_notices == ["head", "independent"], "late dependent rejections must not hide an independent rejection or announce the same failure again")
	NetworkManager.game_command_status.disconnect(record)
	NetworkManager._clear_outgoing_game_commands()


func _check_discovery_refresh() -> void:
	if NetworkManager.start_lan_room_discovery() != OK:
		_assert(false, "the LAN discovery scanner must bind"); return
	var responder := PacketPeerUDP.new()
	var scanner_port: int = NetworkManager._lan_discovery_scanner.get_local_port()
	if responder.set_dest_address("127.0.0.1", scanner_port) != OK:
		_assert(false, "the fixture must reach the LAN scanner"); return
	var reports: Array[String] = []
	var listener := func(rooms: Array) -> void:
		for room in rooms:
			if room["address"] == "127.0.0.1" and room["port"] == 61424:
				reports.append(room["name"])
				return
		if not reports.is_empty():
			reports.append("")
	NetworkManager.lan_rooms_updated.connect(listener)
	var room := {"kind": "room", "protocol": AppVersion.PROTOCOL_VERSION, "port": 61424, "name": "Discovery test"}
	var packet := NetworkManager._encode_lan_discovery_packet(room)
	_assert(responder.put_packet(packet) == OK, "the first discovery datagram must send")
	await get_tree().create_timer(0.25).timeout
	_assert(reports == ["Discovery test"], "the first advertisement must publish a room")
	_assert(responder.put_packet(packet) == OK, "the repeated discovery datagram must send")
	await get_tree().create_timer(0.25).timeout
	_assert(reports == ["Discovery test"], "an unchanged advertisement must not republish the room list")
	room["name"] = "Renamed discovery test"
	_assert(responder.put_packet(NetworkManager._encode_lan_discovery_packet(room)) == OK, "the changed discovery datagram must send")
	await get_tree().create_timer(0.25).timeout
	_assert(reports == ["Discovery test", "Renamed discovery test"], "a changed room name must republish the list")
	NetworkManager.lan_rooms_updated.disconnect(listener)
	NetworkManager.stop_lan_room_discovery()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_NETWORK_SAFETY_FAILED: %s" % message)
	get_tree().quit(1)

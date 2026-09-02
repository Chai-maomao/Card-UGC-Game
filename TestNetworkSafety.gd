extends Node

const LobbyServer = preload("res://server.gd")
const BattleMainActions = preload("res://BattleMainActions.gd")


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

	_assert(is_equal_approx(NetworkManager.reconnect_retry_delay(1, 0.5), 0.5), "first reconnect retry must be fast")
	_assert(is_equal_approx(NetworkManager.reconnect_retry_delay(2, 0.5), 1.0), "reconnect retry must back off exponentially")
	_assert(is_equal_approx(NetworkManager.reconnect_retry_delay(8, 0.5), 8.0), "reconnect retry must be capped")
	_assert(NetworkManager.reconnect_retry_delay(3, 0.0) < NetworkManager.reconnect_retry_delay(3, 1.0), "reconnect jitter must vary retry timing")
	var discovery_packet := NetworkManager._encode_lan_discovery_packet({"kind": "room", "protocol": AppVersion.PROTOCOL_VERSION, "port": 4568})
	var discovery_payload := NetworkManager._decode_lan_discovery_packet(discovery_packet)
	_assert(str(discovery_payload.get("kind", "")) == "room", "LAN discovery packet must round-trip")
	_assert(NetworkManager._decode_lan_discovery_packet("not-json".to_utf8_buffer()).is_empty(), "malformed LAN discovery packet must be ignored")

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
	_assert(BattleMainActions.end_turn_execution_path(false, true) == "local", "offline end turn must use the local path")
	_assert(BattleMainActions.end_turn_execution_path(true, true) == "authority", "online authority must not fall through into the local end-turn path")
	_assert(BattleMainActions.end_turn_execution_path(true, false) == "remote", "online subordinate must send an intent instead of mutating locally")

	print("TEST_NETWORK_SAFETY_OK")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_NETWORK_SAFETY_FAILED: %s" % message)
	get_tree().quit(1)

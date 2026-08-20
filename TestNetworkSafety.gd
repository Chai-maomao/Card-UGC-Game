extends Node


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

	print("TEST_NETWORK_SAFETY_OK")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_NETWORK_SAFETY_FAILED: %s" % message)
	get_tree().quit(1)

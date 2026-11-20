extends Node

func _ready() -> void:
	assert(BetaRelayConfig.valid_code("A1B2C3D4"))
	for code in ["", "1234567", "123456789", "ABCDEFGH", "a1b2c3d4", "12/34?AB"]:
		assert(not BetaRelayConfig.valid_code(code))
	NetworkManager.use_isolated_session_storage("beta-unit")
	NetworkManager.clear_room_session()
	NetworkManager.session_mode = NetworkManager.SESSION_MODE_BETA
	NetworkManager.room_server_address = BetaRelayConfig.server_url()
	NetworkManager.room_server_port = 443
	NetworkManager.room_player_number = 1
	NetworkManager.room_code = "A1B2C3D4"
	NetworkManager.reconnect_token = "a".repeat(64)
	NetworkManager.session_id = "BETA:A1B2C3D4"
	assert(NetworkManager.has_saved_match_session())
	NetworkManager.mark_match_started()
	assert(NetworkManager.has_resumable_match_session() == NetworkManager.MATCH_RECONNECT_ENABLED,"valid saved rooms must respect the disabled reconnect feature")
	NetworkManager._load_room_session()
	assert(NetworkManager.has_saved_beta_session())
	var peer := BetaRelayPeer.new()
	peer.setup(self, BetaRelayConfig.server_url(), "A1B2C3D4", "a".repeat(64), 1, "b".repeat(32))
	peer.set_transfer_channel(2)
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	for i in range(100):
		assert(peer.put_packet(PackedByteArray([i])) == OK)
	assert(peer.queued_packets() == 1, "transient arrows must not accumulate")
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	peer.set_transfer_channel(1)
	assert(peer.put_packet(PackedByteArray([0, 255, 128])) == OK)
	assert(peer.queued_packets() == 2)
	var oversized := PackedByteArray()
	oversized.resize(BetaRelayPeer.MAX_PACKET_BYTES + 1)
	assert(peer.put_packet(oversized) == ERR_OUT_OF_MEMORY)
	peer.close()
	assert(peer._token.is_empty())
	NetworkManager.clear_room_session()
	print("TEST_BETA_RELAY_OK")
	get_tree().quit(0)

extends Node

func _ready() -> void:
	var previous_override := OS.get_environment("CARDEX_CLOUDFLARE_TEST_URL")
	OS.set_environment("CARDEX_CLOUDFLARE_TEST_URL", "http://127.0.0.1:8791")
	assert(CloudRelayConfig.server_url() == "http://127.0.0.1:8791")
	assert(CloudRelayConfig.valid_origin("https://cardex.example.com"))
	for url in ["", "http://example.com", "https://user@example.com", "https://example.com/path", "https://example.com?token=x", "https://example.com#fragment"]:
		assert(not CloudRelayConfig.valid_origin(url), "service configuration must be an HTTPS origin")
	NetworkManager.use_isolated_session_storage("cloudflare-migration")
	NetworkManager.clear_room_session()
	var store := RoomSessionStore.new(NetworkManager._session_storage_path)
	assert(store.save({"mode": "room", "address": CloudRelayConfig.RETIRED_ENET_ADDRESS, "port": 5001, "code": "OLD123", "player": 1, "token": "old", "match_started": true}))
	var old_snapshot := FileAccess.open(NetworkManager._match_snapshot_path, FileAccess.WRITE)
	old_snapshot.store_string("old recoverable snapshot")
	old_snapshot.close()
	NetworkManager._load_room_session()
	assert(not NetworkManager.has_resumable_match_session(), "released Aliyun address must not expose a resume attempt")
	assert(FileAccess.get_file_as_string(NetworkManager._match_snapshot_path) == "old recoverable snapshot", "retiring a server must preserve recoverable local data")
	assert(NetworkManager.connect_to_lobby(CloudRelayConfig.RETIRED_ENET_ADDRESS, Callable()) == ERR_UNAVAILABLE)
	assert(NetworkManager._lobby_peer == null, "retired server must not receive a connection")
	NetworkManager.clear_room_session()
	NetworkManager.session_mode = NetworkManager.SESSION_MODE_CLOUDFLARE
	NetworkManager.room_server_address = CloudRelayConfig.server_url()
	NetworkManager.room_server_port = 443
	NetworkManager.room_code = "C1D2E3F4"
	NetworkManager.room_player_number = 2
	NetworkManager.reconnect_token = "b".repeat(64)
	NetworkManager.session_id = "CF:C1D2E3F4"
	NetworkManager.mark_match_started()
	NetworkManager._load_room_session()
	assert(NetworkManager.has_saved_cloud_session())
	assert(NetworkManager.has_resumable_match_session() == NetworkManager.MATCH_RECONNECT_ENABLED,"retained room data must not enable the withdrawn reconnect feature")
	assert(not NetworkManager.has_saved_beta_session(), "Cloudflare and Sites rooms must retain separate identities")
	var state := {"player_field": {}, "player2_field": {}, "player_hand": [], "player2_hand": [], "shared_deck": [], "state_revision": 17}
	if NetworkManager.MATCH_RECONNECT_ENABLED:
		assert(NetworkManager.save_match_snapshot(state))
		assert(NetworkManager.load_match_snapshot().get("state_revision") == 17)
	else:
		assert(not NetworkManager.save_match_snapshot(state) and NetworkManager.load_match_snapshot().is_empty(),"disabled reconnection must not write or offer a resumable battle")
	NetworkManager.room_server_address = "https://untrusted.example.com"
	assert(not NetworkManager.has_saved_cloud_session(), "saved rooms cannot redirect capabilities to an unknown endpoint")
	NetworkManager.clear_room_session()
	var lobby: Control = preload("res://Lobby.tscn").instantiate()
	add_child(lobby)
	assert(lobby.get_node_or_null("Panel/VBoxContainer/ServerInput") == null)
	assert(lobby.title_label.text == Locale.t("cloud.title"))
	assert(lobby._relay_url() == CloudRelayConfig.server_url())
	lobby.queue_free()
	OS.set_environment("CARDEX_CLOUDFLARE_TEST_URL", previous_override)
	print("TEST_CLOUDFLARE_MIGRATION_OK")
	get_tree().quit(0)

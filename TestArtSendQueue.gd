extends Node

func _ready() -> void:
	NetworkManager.close_connection()
	NetworkManager.set_process(false)
	var transport := BetaRelayPeer.new()
	transport.setup(NetworkManager, "http://127.0.0.1:1", "A1B2C3D4", "a".repeat(64), 2, "b".repeat(32))
	transport._next_poll = 9223372036854775807
	NetworkManager.peer = transport
	NetworkManager.multiplayer.multiplayer_peer = transport
	NetworkManager.is_online = true
	NetworkManager.player_number = 2
	NetworkManager.opponent_peer_id = 1
	PlayerData.battle_deck = [CardData.new("Art queue probe", 0, 1, 1)]
	NetworkManager.is_dedicated_server = true
	NetworkManager.configure_room_session("127.0.0.1", 5001, "TESTROOM", 2, "a".repeat(48))
	var dedicated = preload("res://DedicatedLobby.tscn").instantiate()
	add_child(dedicated)
	dedicated._show_waiting_room()
	# Invoke the actual handler as a stale click can race with a disconnect.
	dedicated._on_start_pressed()
	assert(not dedicated.i_am_ready, "dedicated preparation must wait for a connected game peer")
	assert(dedicated.start_btn.disabled, "connecting server preparation must be disabled")
	assert(transport.queued_packets() == 0, "early server preparation must not send RPCs")
	transport._status = MultiplayerPeer.CONNECTION_DISCONNECTED
	dedicated._on_start_pressed()
	assert(not dedicated.i_am_ready and transport.queued_packets() == 0, "stale clicks after disconnect must not consume readiness or send RPCs")
	NetworkManager.is_online = false
	dedicated._on_start_pressed()
	assert(not dedicated._battle_starting, "a disconnected server lobby must not fall through to offline battle")
	NetworkManager.is_online = true
	transport._status = MultiplayerPeer.CONNECTION_CONNECTED
	transport.peer_connected.emit(1)
	NetworkManager.notify_room_ready()
	assert(not dedicated.start_btn.disabled, "room-ready notification must enable server preparation")
	var ready_packets := transport.queued_packets()
	dedicated._on_start_pressed()
	assert(dedicated.i_am_ready and dedicated.start_btn.disabled, "connected server preparation must enter the waiting state")
	assert(transport.queued_packets() > ready_packets, "connected server preparation must send its deck")
	ready_packets = transport.queued_packets()
	dedicated._on_start_pressed()
	assert(transport.queued_packets() == ready_packets + 1, "clicking again sends one cancellation request")
	NetworkManager.notify_room_preparation_reset("cancelled", 2)
	assert(not dedicated.i_am_ready, "server cancellation must release the local ready state")
	await get_tree().process_frame
	assert(not dedicated.opponent_ready, "submitting the deck must still wait for the opponent")
	dedicated.queue_free()
	await get_tree().process_frame
	var command_id := NetworkManager.send_game_intent("end_turn", {}, 2, 1)
	assert(not command_id.is_empty(), "a connected transport must queue the command before it disconnects")
	NetworkManager._pending_game_commands[command_id]["retry_at"] = 0.0
	transport._outgoing.clear()
	transport.peer_disconnected.emit(1)
	transport._status = MultiplayerPeer.CONNECTION_CONNECTING
	NetworkManager.is_dedicated_server = false
	NetworkManager.clear_room_session()
	var lobby = preload("res://BetaLobby.tscn").instantiate()
	add_child(lobby)
	lobby._show_waiting_room()
	assert(lobby.start_btn.disabled)
	lobby._on_start_pressed()
	assert(not lobby.i_am_ready, "early preparation cannot emit RPC or consume readiness")
	assert(NetworkManager.send_game_intent("end_turn", {}, 2, 1).is_empty(), "connecting transport must reject a new intent without queuing it")
	var commands_before: Dictionary = NetworkManager._pending_game_commands.duplicate(true)
	NetworkManager._process_pending_game_commands()
	NetworkManager._request_command_resync(NetworkManager._now())
	assert(NetworkManager._pending_game_commands == commands_before, "connecting transport must retain queued commands and their retry attempts")
	NetworkManager.send_card_arts([{"card_index": 0, "ext": "png", "bytes": PackedByteArray([1, 2, 3])}])
	var pending: Array = NetworkManager._art_send_queue.duplicate(true)
	NetworkManager._process_art_send_queue()
	if pending.is_empty() or NetworkManager._art_send_queue != pending:
		push_error("TEST_ART_SEND_QUEUE_FAILED: connecting transport must retain pending card art")
		NetworkManager.close_connection()
		get_tree().quit(1)
		return
	NetworkManager.send_card_art_ack(0, 1)
	var expected: int = NetworkManager._art_send_queue.size()
	assert(expected > pending.size(), "ACK must also wait for the actual connection")
	assert(NetworkManager._art_send_queue[0].method == "rpc_card_art_ack", "ACK must not wait behind a large local image upload")
	transport._status = MultiplayerPeer.CONNECTION_DISCONNECTED
	NetworkManager._process_art_send_queue()
	assert(NetworkManager._art_send_queue.size() == expected)
	transport._status = MultiplayerPeer.CONNECTION_CONNECTED
	NetworkManager._process_art_send_queue()
	assert(NetworkManager._art_send_queue.size() == expected, "a connected host with no registered recipient must wait")
	transport.peer_connected.emit(1)
	assert(NetworkManager.multiplayer.get_peers().has(1))
	var before_command_packets := transport.queued_packets()
	NetworkManager._process_pending_game_commands()
	assert(transport.queued_packets() > before_command_packets, "retry must reach the actual peer after reconnection")
	NetworkManager._pending_game_commands.clear()
	NetworkManager._direct_protocol_verified = true
	lobby._on_opponent_joined()
	assert(not lobby.start_btn.disabled, "protocol completion enables preparation")
	while not NetworkManager._art_send_queue.is_empty(): NetworkManager._process_art_send_queue()
	assert(transport.queued_packets() > 0, "after connection, art RPCs must reach the real Godot peer")
	NetworkManager.send_card_arts([])
	assert(NetworkManager._art_send_queue.size() == 1, "zero-art manifests must also be queued")
	var packets: Array[Dictionary] = transport._outgoing.duplicate(true)
	while transport.queued_packets() <= 16: transport._outgoing.append(packets[0])
	NetworkManager._process_art_send_queue()
	assert(NetworkManager._art_send_queue.size() == 1, "backpressure must retain the unsent head")
	transport._outgoing = packets
	NetworkManager._process_art_send_queue()
	assert(NetworkManager._art_send_queue.is_empty(), "the retained manifest must send once backpressure clears")
	NetworkManager.is_dedicated_server = true
	NetworkManager.server_allows_card_art = true
	NetworkManager.send_card_arts([])
	NetworkManager._process_art_send_queue()
	assert(NetworkManager._art_send_queue.is_empty(), "dedicated-relay broadcast must still work")
	NetworkManager.server_allows_card_art = false
	NetworkManager.send_card_arts([])
	assert(NetworkManager._art_send_queue.is_empty(), "servers can still disable card art")
	NetworkManager.is_dedicated_server = false
	NetworkManager.send_card_arts([])
	var replacement := BetaRelayPeer.new()
	replacement.setup(NetworkManager, "http://127.0.0.1:1", "A1B2C3D4", "a".repeat(64), 1, "b".repeat(32))
	replacement._next_poll = 9223372036854775807
	NetworkManager.peer = replacement
	NetworkManager._process_art_send_queue()
	assert(NetworkManager._art_send_queue.size() == 1, "a manager/API peer mismatch must not send on the old transport")
	NetworkManager.peer = transport
	replacement.close()
	NetworkManager.close_connection()
	assert(NetworkManager._art_send_queue.is_empty(), "leaving the room clears its deferred art")
	NetworkManager.send_card_arts([])
	NetworkManager.send_card_art_ack(0, 1)
	assert(NetworkManager._art_send_queue.is_empty(), "late callbacks after leaving cannot repopulate the queue")
	lobby.queue_free()
	print("TEST_ART_SEND_QUEUE_OK dedicated-ready,connecting,disconnected,no-recipient,peer-mismatch,resume,zero-art,backpressure,ack-priority,cleanup")
	get_tree().quit(0)

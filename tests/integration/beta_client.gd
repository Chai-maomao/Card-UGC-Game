extends "res://BetaLobby.gd"

var role := 1
var code_file := ""
var battle: Node
var phase := 0
var done := false
var _elapsed := 0.0
var _started_ready := false
var _resume_seen := false
var _resume_at := 0.0

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = int(argument.get_slice("=", 1))
		if argument.begins_with("--code-file="):
			code_file = argument.trim_prefix("--code-file=")
	NetworkManager.use_isolated_session_storage("beta-integration-p%d" % role)
	NetworkManager.clear_room_session()
	PlayerData.prepare_online_selection("res://BetaLobby.tscn")
	PlayerData.battle_deck.clear()
	for i in range(12):
		var card := CardData.new("Beta", 0, 4, 1)
		card.card_name = "Beta P%d %d" % [role, i]
		card.max_hp = 4
		card.hp = 4
		card.atk = 1
		card.cost = 0
		if i == 0 and OS.get_cmdline_user_args().has("--art"):
			card.art_path = "res://res/ui_slot_frame_240x320.png"
		PlayerData.battle_deck.append(card)
	super._ready()
	set_process(true)
	NetworkManager.reconnect_transport_ready.connect(func():
		_resume_seen = true
		_resume_at = _elapsed
	)
	if role == 1:
		_on_host_pressed()
	else:
		ip_input.text = FileAccess.get_file_as_string(code_file).strip_edges()
		_on_join_pressed()

func _physics_process(delta: float) -> void:
	# Lobby callbacks disable their idle art-timeout loop. Keep the integration
	# driver independent so agreement/reconnect assertions continue to execute.
	super._process(delta)
	_elapsed += delta
	if done:
		return
	if _elapsed > 85.0:
		_fail("timeout at phase %d, status %s" % [phase, status_label.text])
		return
	if role == 1 and code_file != "" and NetworkManager.room_code != "" and not FileAccess.file_exists(code_file):
		var file := FileAccess.open(code_file, FileAccess.WRITE)
		file.store_string(NetworkManager.room_code)
		file.close()
	if battle == null:
		if NetworkManager._direct_protocol_verified and waiting_ui != null and not _started_ready:
			_started_ready = true
			_on_start_pressed()
		for child in match_agreement.get_children():
			if child is ConfirmationDialog and not child.is_queued_for_deletion():
				child.confirmed.emit()
		return
	if battle.game == null or battle.match_paused or battle.is_resolution_locked():
		return
	if phase == 0:
		phase = 1
		if role == 1 and battle.game.current_player == 1:
			battle._on_end_turn_pressed()
	elif phase == 1 and battle.game.current_player == 2:
		phase = 2
		if role == 2:
			battle._on_end_turn_pressed()
	elif phase == 2 and battle._confirmed_game == null and battle.game.current_player == 1 and battle.game.turn_number >= 2:
		phase = 3
		print("TEST_BETA_BATTLE_TURNS_OK_P%d revision=%d" % [role, battle.game.state_revision])
		if role == 2:
			NetworkManager._on_opponent_vanished()
	elif phase == 3 and _resume_seen and _elapsed - _resume_at > 2.0:
		if battle.game.current_player not in [1, 2] or battle.game.turn_number < 2:
			_fail("resume lost battle state")
			return
		phase = 4
		if role == 1 and battle.game.current_player == 1:
			battle._on_end_turn_pressed()
	elif phase == 4 and battle.game.current_player == 2:
		done = true
		print("TEST_BETA_RELAY_INTEGRATION_OK_P%d revision=%d" % [role, battle.game.state_revision])
		await get_tree().create_timer(2.0).timeout
		NetworkManager.close_connection()
		NetworkManager.clear_room_session()
		get_tree().quit(0)

func _send_card_arts() -> void:
	super._send_card_arts()
	if not OS.get_cmdline_user_args().has("--guard-art"):
		return
	var transport = NetworkManager.peer
	var previous_status: int = transport._status
	var queued: Array = NetworkManager._art_send_queue.duplicate(true)
	transport._status = MultiplayerPeer.CONNECTION_CONNECTING
	NetworkManager._process_art_send_queue()
	transport._status = previous_status
	if queued.is_empty() or NetworkManager._art_send_queue != queued:
		_fail("connecting transport consumed pending art")
		return
	print("TEST_BETA_ART_CONNECTING_GUARD_OK_P%d" % role)

func _on_battle_start(match_id: String) -> void:
	if battle != null:
		return
	if OS.get_cmdline_user_args().has("--art"):
		var received: CardData = PlayerData.opponent_battle_deck[0]
		if not FileAccess.file_exists(received.art_path) or FileAccess.get_sha256(received.art_path) != FileAccess.get_sha256("res://res/ui_slot_frame_240x320.png"):
			_fail("card art did not survive chunked relay")
			return
		print("TEST_BETA_ART_OK_P%d" % role)
	NetworkManager.mark_match_started(match_id)
	lobby_panel.hide()
	if waiting_ui:
		waiting_ui.hide()
	battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	print("TEST_BETA_DECK_AGREEMENT_OK_P%d opponent=%d" % [role, PlayerData.opponent_battle_deck.size()])
	set_process(true)

func _on_opponent_disconnected(player: int) -> void:
	# The production scene transition frees the lobby. This integration fixture
	# keeps it alive to drive the battle, so its waiting-room handler must retire.
	if battle == null:
		super._on_opponent_disconnected(player)

func _fail(message: String) -> void:
	done = true
	push_error("TEST_BETA_RELAY_INTEGRATION_FAILED_P%d: %s" % [role, message])
	NetworkManager.close_connection()
	get_tree().quit(1)

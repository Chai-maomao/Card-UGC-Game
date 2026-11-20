extends "res://Lobby.gd"

var role := 1
var code_file := ""
var battle: Node
var phase := 0
var done := false
var _elapsed := 0.0
var _started_ready := false
var _resume_seen := false
var _resume_at := 0.0
var _check_moves := false
var _move_base_revision := 0
var _peer_finished := false

func _ready() -> void:
	_check_moves = OS.get_cmdline_user_args().has("--check-moves")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = int(argument.get_slice("=", 1))
		if argument.begins_with("--code-file="):
			code_file = argument.trim_prefix("--code-file=")
	NetworkManager.use_isolated_session_storage("cloud-integration-p%d" % role)
	if _check_moves:
		GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.DEFAULT if role == 1 else GamePreferences.PlaybackSpeed.FAST)
	NetworkManager.clear_room_session()
	PlayerData.prepare_online_selection("res://Lobby.tscn")
	PlayerData.battle_deck.clear()
	for i in range(12):
		var card := CardData.new("Beta", 0, 4, 1)
		card.card_name = "Beta P%d %d" % [role, i]
		card.max_hp = 4
		card.hp = 4
		card.atk = 1
		card.cost = 1 if _check_moves else 0
		if _check_moves:
			card.skills = [{"skill_name": "Draw fixture", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
				"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillRegistry.EFFECT_DRAW_CARDS, "value": 1}]}]
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
	# DirectLobby may disable its idle art timer after connecting; the test
	# driver must continue through agreement, prediction and reconnect.
	super._process(delta)
	_elapsed += delta
	if done:
		return
	if _elapsed > 110.0:
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
			if _check_moves:
				battle.game.player2_field.slots[0] = CardData.new("Prediction fixture", 0, 4, 1)
				battle.game.player_field.slots[0] = CardData.new("Prediction target", 0, 12, 1)
				battle.game.allow_first_turn_attacks = true
			battle._on_end_turn_pressed()
	elif phase == 1 and battle.game.current_player == 2:
		phase = 2
		if role == 2:
			if _check_moves:
				phase = 5
				_move_base_revision = battle.game.state_revision
				var card: CardData = battle.game.player2_field.slots[0]
				if card == null:
					_fail("move fixture is missing")
					return
				battle._on_card_drag_summoned(card, null, 1)
				battle._on_card_drag_summoned(battle.game.player2_field.slots[1], null, 2)
				if NetworkManager.pending_game_command_count() != 2 or battle.game.player2_field.slots[2].instance_id != card.instance_id or battle._confirmed_game.player2_field.slots[0] != card:
					_fail("two moves did not predict independently of confirmed state")
			else:
				battle._on_end_turn_pressed()
	elif phase == 5 and NetworkManager.pending_game_command_count() == 0:
		if battle.game.state_revision != _move_base_revision + 2 or battle.game.player2_field.slots[2] == null:
			_fail("host did not confirm both predicted moves")
			return
		phase = 6
		var card: CardData = battle.game.player2_field.slots[2]
		battle._send_remote_intent("move", {"source_slot": 2, "target_slot": 3, "after_move": "missing-predecessor"})
		battle._on_card_drag_summoned(battle.game.player2_field.slots[3], null, 4)
		if NetworkManager.pending_game_command_count() != 2 or battle.game.player2_field.slots[4].instance_id != card.instance_id:
			_fail("rollback fixture did not predict both moves")
	elif phase == 6 and NetworkManager.pending_game_command_count() == 0:
		if battle.game.state_revision != _move_base_revision + 2 or battle._visible_player_slots()[2] == null or battle._visible_player_slots()[4] != null:
			_fail("rejected move chain did not restore confirmed slots")
			return
		print("TEST_CLOUD_PREDICTED_MOVES_OK")
		phase = 2
		var hand: Array = battle.game.player2_hand
		var first: CardData = hand[0]
		var second: CardData = hand[1]
		var mana: int = battle.game.player2_field.get_total_mana()
		battle._on_card_drag_summoned(first, null, 3)
		battle._on_card_drag_summoned(battle.game.player2_hand[0], null, 4)
		var preview: Dictionary = battle._deployment_preview()
		if preview["slots"][3].instance_id != first.instance_id or preview["slots"][4].instance_id != second.instance_id or preview["hand"].size() != hand.size() - 2 or preview["mana"] != mana - first.cost - second.cost:
			_fail("deployment did not project board, hand and mana before confirmation")
			return
		var target_hp: int = battle.game.player_field.slots[0].hp
		var deck_size: int = battle.game.shared_deck.size()
		if battle._send_remote_intent("attack", {"source_slot": 2, "target_slot": 0}).is_empty() or battle.game.player_field.slots[0].hp != target_hp - 1:
			_fail("attack damage did not resolve locally")
			return
		if battle._send_remote_intent("activate_skill", {"slot_index": 3, "skill_index": 0, "target_slot": -1}).is_empty() or battle.game.shared_deck.size() != deck_size - 1:
			_fail("skill draw did not resolve locally")
			return
		if battle._send_remote_intent("discard", {"location": "hand", "index": 0}).is_empty() or battle.game.player2_hand.size() != hand.size() - 2:
			_fail("discard did not resolve locally")
			return
		battle._on_end_turn_pressed()
		if NetworkManager.pending_game_command_count() != 6 or battle.game.current_player != 1 or battle._confirmed_game.current_player != 2:
			_fail("end turn did not queue behind both predicted deployments")
	elif phase == 2 and battle._confirmed_game == null and battle.game.current_player == 1 and battle.game.turn_number >= 2:
		if _check_moves and (battle.game.state_revision != 9 or battle.game.player2_field.slots[4] == null or battle.game.player_field.slots[0].hp != 11):
			_fail("turn handed off without the complete move sequence")
			return
		phase = 3
		print("TEST_CLOUD_BATTLE_TURNS_OK_P%d revision=%d" % [role, battle.game.state_revision])
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
		print("TEST_CLOUD_RELAY_INTEGRATION_OK_P%d revision=%d" % [role, battle.game.state_revision])
		_test_finished.rpc_id(3-role)
		var deadline := Time.get_ticks_msec()+20000
		while not _peer_finished and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		if not _peer_finished:
			_fail("peer did not finish the final reconnect assertion")
			return
		await get_tree().create_timer(1.0).timeout
		NetworkManager.close_connection()
		NetworkManager.clear_room_session()
		get_tree().quit(0)

@rpc("any_peer","call_remote","reliable")
func _test_finished() -> void:
	_peer_finished = true

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
	print("TEST_CLOUD_ART_CONNECTING_GUARD_OK_P%d" % role)

func _on_battle_start(match_id: String) -> void:
	if battle != null:
		return
	if OS.get_cmdline_user_args().has("--art"):
		var received: CardData = PlayerData.opponent_battle_deck[0]
		if not FileAccess.file_exists(received.art_path) or FileAccess.get_sha256(received.art_path) != FileAccess.get_sha256("res://res/ui_slot_frame_240x320.png"):
			_fail("card art did not survive chunked relay")
			return
		print("TEST_CLOUD_ART_OK_P%d" % role)
	NetworkManager.mark_match_started(match_id)
	lobby_panel.hide()
	if waiting_ui:
		waiting_ui.hide()
	battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	print("TEST_CLOUD_DECK_AGREEMENT_OK_P%d opponent=%d" % [role, PlayerData.opponent_battle_deck.size()])
	set_process(true)

func _on_opponent_disconnected(player: int) -> void:
	# The production scene transition frees the lobby. This integration fixture
	# keeps it alive to drive the battle, so its waiting-room handler must retire.
	if battle == null:
		super._on_opponent_disconnected(player)

func _fail(message: String) -> void:
	done = true
	push_error("TEST_CLOUD_RELAY_INTEGRATION_FAILED_P%d: %s" % [role, message])
	NetworkManager.close_connection()
	get_tree().quit(1)

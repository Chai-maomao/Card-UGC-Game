extends Node

const BattleScene = preload("res://Main.tscn")
var _failed := false


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		AppPreferences.set_value("window_mode", 1)
		get_window().size = Vector2i(1280, 720)
	NetworkManager.close_connection()
	NetworkManager.is_online = true
	NetworkManager.is_host = true
	NetworkManager.is_dedicated_server = false
	NetworkManager.player_number = 1
	PlayerData.battle_mode = "multiplayer"

	var battle = BattleScene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	var initial_revision: int = battle.game.state_revision
	_assert(battle.game.current_player == 1, "online authority test must start on P1")

	battle._on_end_turn_pressed()
	# The old regression performed a second local end-turn after 0.5 seconds.
	# Waiting beyond that boundary proves the authority path returned instead.
	await get_tree().create_timer(0.7).timeout
	_assert(battle.game.current_player == 2, "one authority click must advance exactly once to P2")
	_assert(battle.game.turn_number == 1, "one authority click must not advance to the next round")
	_assert(battle.game.state_revision == initial_revision + 1, "one authority click must create exactly one committed revision")
	_assert(battle.end_turn_button.disabled, "the host's End Turn button must stay disabled on the guest's turn")
	var opponent_turn := Locale.t("battle.opponent_turn")
	var canvas := battle.get_node("CanvasLayer")
	_assert(battle.turn_label.text.contains(opponent_turn) and not battle.turn_wait_hint.visible,
		"an ordinary opponent turn must show its owner once in the fixed turn label")
	_assert(not canvas.get_children().any(func(child: Node): return child is Label and child.visible and child.text == opponent_turn),
		"the turn transition must not draw a separate label over the battle controls")
	_assert(battle.combat_broadcast_panel.text.is_empty() and is_zero_approx(battle.combat_broadcast_panel.self_modulate.a)
		and battle.combat_broadcast_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"an empty battle summary must reserve layout space without drawing a panel or receiving clicks")

	# The remote command handler must carry the player's AP-only choice.
	battle.game.current_player = 1
	battle.game.turn_number = 2
	battle.game.is_player_turn = true
	battle.game.player_field.slots = [CardData.new("A",1,3,2),CardData.new("B",1,3,4),null,null,null]
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.action_points = 0
	battle.game.player_field.actions_taken = 1
	battle.game.player_field.current_mana = 4
	battle.game.player2_field.player_hp = 30
	await battle._execute_network_command("end_turn",{"allow_face_mana":false},1)
	_assert(battle.game.player2_field.player_hp == 30 and battle.game.player_field.current_mana == 4,"remote AP-only choice must prevent Elixir-funded hero attacks")

	NetworkManager.game_command_status.emit("late-reply", "end_turn", "timeout", 8000)
	var toast := (battle._toast_feed as Control).find_children("*", "Label", true, false)
	if toast.is_empty() or toast.back().text != Locale.t("tip.command_timeout"):
		_assert(false, "a missing reply must report ongoing synchronization instead of asking the player to repeat an action")
	NetworkManager.is_host = false
	NetworkManager.player_number = 2
	battle.my_player = 2
	var snapshot: Dictionary = battle.game.export_initial_state()
	snapshot.is_player_turn = true
	snapshot.current_player = 2
	battle._on_server_match_snapshot(snapshot)
	await get_tree().process_frame
	battle._turn_ending = true
	battle.end_turn_button.disabled = true
	NetworkManager.game_command_status.emit("timed-out-turn", "end_turn", "timeout", 8000)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle.end_turn_button.disabled and not battle.is_my_turn() and battle.turn_wait_hint.visible,
		"an unconfirmed end turn must keep input locked and show a persistent notice until synchronization")
	_assert(battle.turn_wait_hint.get_node("Label").text == Locale.t("battle.end_turn_sync_pending"),
		"the notice must explain that the end-turn outcome is being synchronized")
	if DisplayServer.get_name() != "headless" and not _failed:
		await get_tree().create_timer(2.4).timeout
		_assert(battle.turn_wait_hint.visible and battle.end_turn_button.disabled,
			"the synchronization notice must remain after the toast expires")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/online-end-turn"))
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/end-turn-sync.png") == OK,
			"could not capture the pending end-turn outcome")
	battle._on_server_match_snapshot(snapshot)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not battle.end_turn_button.disabled and battle.is_my_turn() and not battle.turn_wait_hint.visible,
		"an authoritative snapshot with the same turn must restore input and clear the notice")
	snapshot.current_player = 1
	battle._turn_ending = true
	battle.end_turn_button.disabled = true
	battle._on_server_match_snapshot(snapshot)
	_assert(battle.end_turn_button.disabled and not battle._turn_ending,
		"settling a guest end turn must keep the button disabled on the opponent's turn")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle.end_turn_button.disabled and not battle.turn_wait_hint.visible and battle.turn_label.text.contains(opponent_turn),
		"settled guest end turn must show the opponent's turn in the fixed turn label")
	snapshot.current_player = 2
	battle._on_server_match_snapshot(snapshot)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not battle.end_turn_button.disabled and not battle.turn_wait_hint.visible,
		"the next local turn must enable the button and clear the waiting hint")
	await _check_discard_send_and_rejection(battle, snapshot)
	await _check_checkpoint_log_overlap(battle)
	await _check_late_checkpoint_during_end_turn(battle)
	await _check_opponent_combat_feedback(battle)
	await _check_remote_targeting_expiry(battle)
	await _check_manual_forfeit_survives_recovery(battle)
	await _check_terminal_checkpoint_feedback(battle)
	battle.queue_free()
	NetworkManager.close_connection()
	if _failed:
		get_tree().quit(1)
		return
	print("TEST_ONLINE_END_TURN_OK")
	get_tree().quit(0)


func _check_discard_send_and_rejection(battle: Node, snapshot: Dictionary) -> void:
	var initial_hash: String = battle._web_turn_hash()
	var initial_count: int = battle._my_hand().size()
	_assert(initial_count >= 2, "the guest needs two cards to exercise unsent predictions")
	if initial_count < 2:
		return
	battle._on_card_discarded(battle._my_hand()[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle._web_turn_hash() == initial_hash and battle._my_hand().size() == initial_count,
		"the first unsent discard must leave the hand, resources and revision intact")
	_assert(NetworkManager.pending_game_command_count() == 0 and battle._confirmed_game == null
		and battle._web_prediction_count == 0 and not battle.turn_wait_hint.visible,
		"an unsent discard must not create a pending command or a prediction")
	var hints := (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(not hints.is_empty() and hints.back().text == Locale.t("tip.command_not_sent"),
		"the guest must be told that the action was not sent")
	if DisplayServer.get_name() != "headless" and not _failed:
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/action-not-sent.png") == OK,
			"could not capture the rejected send")
	battle._on_card_discarded(battle._my_hand()[0])
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(hints.filter(func(hint: Label): return hint.text == Locale.t("tip.command_not_sent")).size() == 1,
		"repeated failed sends must update one notice instead of stacking identical warnings")
	battle._restore_confirmed_game()
	battle._on_server_match_snapshot(snapshot)
	await get_tree().process_frame
	var transport := BetaRelayPeer.new()
	transport.setup(NetworkManager, "http://127.0.0.1:1", "A1B2C3D4", "a".repeat(64), 2, "b".repeat(32))
	transport._next_poll = 9223372036854775807
	transport._status = MultiplayerPeer.CONNECTION_CONNECTED
	NetworkManager.peer = transport
	NetworkManager.multiplayer.multiplayer_peer = transport
	transport.peer_connected.emit(1)
	battle._on_card_discarded(battle._my_hand()[0])
	_assert(NetworkManager.pending_game_command_count() == 1 and battle._my_hand().size() == initial_count - 1,
		"the connected transport must accept the first predicted discard")
	await get_tree().process_frame
	await get_tree().process_frame
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(not hints.any(func(hint: Label): return hint.text == Locale.t("tip.command_not_sent"))
		and battle.turn_wait_hint.visible and battle.turn_wait_hint.get_node("Label").text == Locale.t("battle.command_sent"),
		"the accepted retry must show pending confirmation without an obsolete send failure")
	if DisplayServer.get_name() != "headless" and not _failed:
		await _verify_pending_hand_input(battle)
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/action-send-recovered.png") == OK,
			"could not capture the send after transport recovery")
	var pending_hash: String = battle._web_turn_hash()
	transport._status = MultiplayerPeer.CONNECTION_CONNECTING
	battle._on_card_discarded(battle._my_hand()[0])
	await get_tree().process_frame
	_assert(battle._web_turn_hash() == pending_hash and battle._my_hand().size() == initial_count - 1,
		"an unsent second discard must preserve the submitted prediction")
	_assert(NetworkManager.pending_game_command_count() == 1 and battle._web_prediction_count == 1,
		"an unsent second discard must leave only the submitted command pending")
	if NetworkManager.pending_game_command_count() != 1:
		return
	var command_id: String = NetworkManager._pending_game_commands.keys()[0]
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(2.4).timeout
	NetworkManager.acknowledge_game_command(command_id, int(snapshot.state_revision), "rejected")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not battle.is_my_turn() and battle.end_turn_button.disabled and battle.turn_wait_hint.visible,
		"receiving a rejection before the host snapshot must keep the battle locked and show synchronization")
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(hints.is_empty() or hints.back().text != Locale.t("tip.command_resynced"),
		"the retry prompt must wait until the rejection's host snapshot is applied")
	battle._on_rpc_authority_state(snapshot)
	await get_tree().process_frame
	await get_tree().process_frame
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(battle._web_turn_hash() == initial_hash and battle.is_my_turn() and not battle.turn_wait_hint.visible,
		"applying the rejection snapshot must restore the original hand and let the guest retry")
	_assert(not hints.is_empty() and hints.back().text == Locale.t("tip.command_resynced"),
		"the restored battle must show the retry prompt")
	if DisplayServer.get_name() != "headless" and not _failed:
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/action-rejected.png") == OK,
			"could not capture the corrected battle after rejection")
	# A response queued behind newer playback must not move the battle backwards.
	transport._status = MultiplayerPeer.CONNECTION_CONNECTED
	var newer := snapshot.duplicate(true)
	newer.state_revision = int(snapshot.state_revision) + 1
	battle._on_rpc_authority_state(newer)
	var retry_hint: Label = hints.back()
	transport._status = MultiplayerPeer.CONNECTION_CONNECTING
	battle._on_card_discarded(battle._my_hand()[0])
	_assert(NetworkManager.pending_game_command_count() == 0 and retry_hint.is_visible_in_tree(),
		"a retry that never leaves the client must keep the retry prompt")
	transport._status = MultiplayerPeer.CONNECTION_CONNECTED
	battle._show_toast("tip.insufficient_mana")
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	var unrelated_hint: Label = hints.back()
	battle._on_card_discarded(battle._my_hand()[0])
	if NetworkManager.pending_game_command_count() != 1:
		_assert(false, "the stale rejection fixture needs a pending discard")
		return
	_assert(not retry_hint.is_visible_in_tree(), "submitting a new discard must retire the previous retry prompt")
	_assert(unrelated_hint.is_visible_in_tree(), "retiring the retry prompt must preserve other battle tips")
	command_id = NetworkManager._pending_game_commands.keys()[0]
	NetworkManager.acknowledge_game_command(command_id, int(snapshot.state_revision), "stale_revision")
	battle._on_rpc_authority_state(snapshot)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle.game.state_revision == newer.state_revision and battle._my_hand().size() == initial_count
		and battle.is_my_turn() and not battle.turn_wait_hint.visible,
		"an older rejection snapshot must restore the most recent authoritative battle and unlock retry")
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(not hints.is_empty() and hints.back().text == Locale.t("tip.command_resynced"),
		"a newly rejected attempt must show a fresh retry prompt")
	battle._on_card_discarded(battle._my_hand()[0])
	if NetworkManager.pending_game_command_count() != 1:
		_assert(false, "the turn-changed rejection fixture needs a pending discard")
		return
	command_id = NetworkManager._pending_game_commands.keys()[0]
	newer.state_revision += 1
	newer.current_player = 1
	NetworkManager.acknowledge_game_command(command_id, int(newer.state_revision), "stale_revision")
	battle._on_rpc_authority_state(newer)
	await get_tree().process_frame
	await get_tree().process_frame
	hints = (battle._toast_feed as Control).find_children("*", "Label", true, false)
	_assert(battle.end_turn_button.disabled and not hints.is_empty() and hints.back().text == Locale.t("tip.command_not_applied"),
		"an updated opponent turn must report the rejection without inviting a retry")


func _verify_pending_hand_input(battle: Node) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_value: float = battle._ui_scale()
	var hand: Control = battle.hand_container
	# Sample the hand at the previous footer's coordinates.
	var point := Vector2(viewport_size.x * 0.5, viewport_size.y - 29 * scale_value)
	var card: Control
	for offset in [0, -20, 20, -45, 45, -80, 80]:
		point.x = viewport_size.x * 0.5 + offset * scale_value
		card = hand.card_at_pointer(point)
		if card != null:
			break
	_assert(card != null, "the hand must occupy the former notification area in this fixture")
	if card != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.position = point
		click.global_position = point
		click.pressed = true
		get_viewport().push_input(click, true)
		await get_tree().process_frame
		_assert(is_instance_valid(battle.card_inspector) and battle.card_inspector.visible
			and NetworkManager.pending_game_command_count() == 1,
			"the pending notification must allow inspecting the hand at its previous footer location")
		if is_instance_valid(battle.card_inspector):
			battle.card_inspector.hide()
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(12, 60)
		motion.global_position = motion.position
		get_viewport().push_input(motion, true)
	var hint_rect: Rect2 = battle.turn_wait_hint.get_global_rect()
	_assert(not hint_rect.intersects(battle.hand_area.get_global_rect()),
		"the pending notification must leave all hand card statistics visible")
	var previous_size := get_window().size
	var previous_locale := Locale.language
	get_window().size = Vector2i(960, 540)
	Locale.language = "en"
	battle.update_entire_screen()
	await get_tree().create_timer(0.2).timeout
	hint_rect = battle.turn_wait_hint.get_global_rect()
	_assert(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(hint_rect)
		and not hint_rect.intersects(battle.hand_area.get_global_rect())
		and battle.turn_wait_hint.get_node("Label").text == Locale.t("battle.command_sent"),
		"the English pending notification must remain in its lane at 960 pixels")
	if not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/action-send-pending-en-960.png") == OK,
			"could not capture the compact pending notification")
	Locale.language = previous_locale
	get_window().size = previous_size
	battle.update_entire_screen()
	await get_tree().create_timer(0.2).timeout


func _check_checkpoint_log_overlap(battle: Node) -> void:
	var displayed: Dictionary = battle.game.export_initial_state()
	var revision: int = displayed.state_revision
	var turn: int = displayed.turn_number
	displayed["_feedback_events"] = [{"kind": "broadcast_text", "text_key": "tip.discard_mana"}]
	battle._on_rpc_authority_state(displayed)
	var previous_count: int = battle._action_log_entries.size()
	var checkpoint := displayed.duplicate(true)
	checkpoint.state_revision = revision + 2
	checkpoint.turn_number = turn + 1
	checkpoint.current_player = 2
	checkpoint.player2_field.current_mana = 3
	checkpoint["_feedback_events"] = [
		{"kind": "broadcast_text", "text_key": "tip.discard_mana", "checkpoint_revision": revision, "checkpoint_turn": turn},
		{"kind": "broadcast_text", "text_key": "tip.discard_mana_full", "checkpoint_revision": revision + 1, "checkpoint_turn": turn},
		{"kind": "broadcast_text", "text_key": "tip.discard_mana", "checkpoint_revision": revision + 2, "checkpoint_turn": turn + 1},
	]
	battle._on_room_command_checkpoint(checkpoint)
	var late := checkpoint.duplicate(true)
	late["_feedback_events"] = displayed["_feedback_events"]
	battle._on_rpc_authority_state(late)
	var entries: Array = battle._action_log_entries
	_assert(entries.size() == previous_count + 2
		and entries[0].text == Locale.t("tip.discard_mana") and entries[0].turn == turn + 1
		and entries[1].text == Locale.t("tip.discard_mana_full") and entries[1].turn == turn,
		"checkpoint logs must keep their original turns and skip records already displayed")
	await get_tree().process_frame
	await get_tree().process_frame
	var same_revision: Dictionary = battle.game.export_initial_state()
	var applied := same_revision.duplicate(true)
	applied.state_revision += 1
	applied.player2_field.current_mana += 1
	battle._on_rpc_initial_state(same_revision)
	battle._on_rpc_authority_state(applied)
	await get_tree().process_frame
	await get_tree().process_frame
	var mana_bar: ProgressBar = battle.player_status_hud.get_node("Margin/Content/ManaBar")
	_assert(mana_bar.has_node("StatusFx_Mana"),
		"a redundant initial snapshot must not suppress mana feedback for a newer result in the same frame")


func _check_late_checkpoint_during_end_turn(battle: Node) -> void:
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(2.4).timeout
	var checkpoint: Dictionary = battle.game.export_initial_state()
	checkpoint.state_revision += 1
	battle._on_room_command_checkpoint(checkpoint)
	await get_tree().process_frame
	await get_tree().process_frame
	battle._deployment_feedback_until_msec = Time.get_ticks_msec() + 3000
	var turn_button: Button = battle.end_turn_button
	turn_button.pressed.emit()
	_assert(turn_button.disabled and NetworkManager.pending_game_command_count() == 0,
		"the end-turn request must wait for the local deployment animation")
	battle._on_rpc_authority_state(checkpoint)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(turn_button.disabled and not battle.is_my_turn() and NetworkManager.pending_game_command_count() == 0,
		"a delayed checkpoint duplicate must keep the new end-turn request locked while it waits")
	battle._deployment_feedback_until_msec = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var pending := NetworkManager.pending_game_commands()
	_assert(pending.size() == 1 and pending[0].kind == "end_turn", "the original end-turn click must submit after local animation")
	if pending.size() != 1:
		return
	var command_id: String = NetworkManager._pending_game_commands.keys()[0]
	battle._on_rpc_authority_state(checkpoint)
	await get_tree().process_frame
	_assert(turn_button.disabled and NetworkManager.pending_game_command_count() == 1
		and battle.turn_wait_hint.visible and battle.turn_wait_hint.get_node("Label").text == Locale.t("battle.command_sent"),
		"a delayed checkpoint duplicate must keep the in-flight end-turn request pending")
	if DisplayServer.get_name() != "headless" and not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/late-snapshot-end-turn.png") == OK,
			"could not capture the protected end-turn control")
	NetworkManager.rpc_game_command_receipt(NetworkManager.battle_match_id, command_id)
	await get_tree().process_frame
	_assert(turn_button.disabled and NetworkManager.pending_game_command_count() == 1
		and battle.turn_wait_hint.visible and battle.turn_wait_hint.get_node("Label").text == Locale.t("battle.command_received"),
		"a delivery receipt must show that the action is resolving and keep duplicate input locked")
	NetworkManager.acknowledge_game_command(command_id, checkpoint.state_revision, "rejected")
	battle._on_rpc_authority_state(checkpoint)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not turn_button.disabled and battle.is_my_turn() and not battle.turn_wait_hint.visible,
		"an explicit rejection at the same revision must unlock the button after synchronization")
	turn_button.pressed.emit()
	await get_tree().process_frame
	pending = NetworkManager.pending_game_commands()
	_assert(pending.size() == 1 and pending[0].kind == "end_turn", "the rejected end-turn request must be retryable")
	if pending.size() != 1:
		return
	command_id = NetworkManager._pending_game_commands.keys()[0]
	var settled := checkpoint.duplicate(true)
	settled.state_revision += 1
	settled.current_player = 1
	NetworkManager.acknowledge_game_command(command_id, settled.state_revision, "applied")
	battle._on_rpc_authority_state(settled)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(NetworkManager.pending_game_command_count() == 0 and turn_button.disabled
		and battle.turn_label.text.contains(Locale.t("battle.opponent_turn")),
		"the end-turn result must settle once and show the opponent's turn")


func _check_opponent_combat_feedback(battle: Node) -> void:
	var recap := BattleLogFormatter.format_event({"kind": "attack", "player": 1, "source": "先锋", "target": "守卫"}, 2)
	battle._show_combat_broadcast(recap, "attack")
	await get_tree().process_frame
	await get_tree().process_frame
	var summary: Label = battle.combat_broadcast_label
	_assert(battle.turn_label.text.contains(Locale.t("battle.opponent_turn")),
		"the turn label must show opponent ownership")
	_assert(not battle.turn_wait_hint.visible and summary.self_modulate.a > 0.9,
		"the combat result must have priority on the opponent's turn")
	_assert(not recap.is_empty() and summary.tooltip_text == recap,
		"the combat result must show the newest attack")
	if DisplayServer.get_name() != "headless" and not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/opponent-combat-feedback.png") == OK,
			"could not capture the opponent turn and its combat result")
		var click := InputEventMouseButton.new()
		click.position = summary.get_global_rect().get_center()
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		get_viewport().push_input(click, true)
		await get_tree().process_frame
		var log_text: String = battle.action_log_text.get_parsed_text()
		_assert(battle.action_log_panel.visible and "先锋" in log_text and "守卫" in log_text,
			"clicking the visible summary must open the log containing the action")
		battle._close_action_log()
	NetworkManager.game_command_status.emit("held-reply", "discard", "timeout", 8000)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle.turn_wait_hint.visible and summary.self_modulate.a == 0.0
		and battle.turn_wait_hint.get_node("Label").text == Locale.t("battle.action_sync_pending"),
		"an outstanding synchronization must take priority over the combat summary")
	battle._on_server_match_snapshot(battle.game.export_initial_state())
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not battle.turn_wait_hint.visible and summary.self_modulate.a > 0.9,
		"the combat summary must return after synchronization")


func _check_remote_targeting_expiry(battle: Node) -> void:
	var opponent: int = battle.game.current_player
	_assert(opponent != battle.my_player and battle.game.is_player_turn, "targeting feedback fixture must be on the opponent's turn")
	EventBus.rpc_targeting_arrow_received.emit(0, 0, opponent)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle.attack_arrow.visible, "receiving opponent targeting must display the arrow")
	if DisplayServer.get_name() != "headless" and not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/remote-aim-visible.png") == OK,
			"could not capture an active remote arrow")
	# Keep the same aim active, then simulate a lost final clear by going silent.
	for i in range(4):
		await get_tree().create_timer(0.34).timeout
		EventBus.rpc_targeting_arrow_received.emit(0, 0, opponent)
		await get_tree().process_frame
		_assert(battle.attack_arrow.visible, "updates must keep a stationary remote aim visible")
	await get_tree().create_timer(1.5).timeout
	_assert(not battle.attack_arrow.visible, "an abandoned remote aim must expire when its clear packet never arrives")
	if DisplayServer.get_name() != "headless" and not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/remote-aim-expired.png") == OK,
			"could not capture the board after a stale arrow expires")
	EventBus.rpc_targeting_arrow_received.emit(0, 0, opponent)
	await get_tree().process_frame
	EventBus.rpc_targeting_arrow_received.emit(-1, -1, opponent)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not battle.attack_arrow.visible, "an explicit clear must hide the arrow without waiting for expiry")
	EventBus.rpc_targeting_arrow_received.emit(999, 0, opponent)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not battle.attack_arrow.visible, "a vanished or out-of-range slot must not produce an arrow")


func _check_manual_forfeit_survives_recovery(battle: Node) -> void:
	battle.abandon_battle_button.pressed.emit()
	var prompt := battle.get_node_or_null("AbandonBattleConfirmation") as CanvasLayer
	_assert(prompt != null and prompt.visible, "manual forfeit must show its confirmation")
	NetworkManager._room_link_waiting = true
	NetworkManager.room_link_wait_changed.emit()
	NetworkManager._room_link_waiting = false
	NetworkManager.room_link_wait_changed.emit()
	await get_tree().process_frame
	_assert(is_instance_valid(prompt) and prompt.visible and UIMotion.top_popup() == prompt,
		"recovering the link must preserve a manual forfeit decision")
	if is_instance_valid(prompt):
		prompt.queue_free()
	await get_tree().process_frame


func _check_terminal_checkpoint_feedback(battle: Node) -> void:
	var native := DisplayServer.get_name() != "headless"
	if native:
		get_window().size = Vector2i(960, 540)
	Locale.language = "en"
	battle.update_entire_screen()
	await get_tree().create_timer(0.12).timeout
	var controls: Array[Control] = [battle.end_turn_button, battle.face_mana_button, battle.combat_broadcast_panel]
	var before := controls.map(func(control: Control): return control.get_global_rect())
	if native and not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/turn-controls-before-result.png") == OK,
			"could not capture the compact battle controls before results")
	var state: Dictionary = battle.game.export_initial_state()
	state.state_revision += 1
	state.player_field.player_hp = 0
	var hp_bar := battle.enemy_status_hud.get_node("Margin/Content/HpBar") as ProgressBar
	var result_path := "CanvasLayer/BattleResultLayer"
	battle._on_room_command_checkpoint(state)
	_assert(not battle.is_my_turn() and hp_bar.value > 0 and battle.get_node_or_null(result_path) == null,
		"a checkpoint-only finish must show the last health change before opening results")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(battle.turn_label.text == Locale.t("battle.finishing_match"),
		"the battle strip must show the finishing state before the result")
	for i in controls.size():
		var rect := controls[i].get_global_rect()
		var bar := battle.turn_label.get_parent().get_parent() as Control
		_assert(rect.is_equal_approx(before[i]) and bar.get_global_rect().grow(1.0).encloses(rect),
			"%s moved or overflowed during the finishing state" % controls[i].name)
	if native and not _failed:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("res://artifacts/online-end-turn/turn-controls-finishing.png") == OK,
			"could not capture compact battle controls during finishing")
	var deadline := Time.get_ticks_msec() + 2000
	while battle.get_node_or_null(result_path) == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_assert(battle.get_node_or_null(result_path) != null and is_zero_approx(hp_bar.value),
		"a checkpoint-only finish must settle the health bar and show the final result")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("TEST_ONLINE_END_TURN_FAILED: %s" % message)

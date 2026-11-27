extends "res://BattleMainPresentation.gd"

const MAX_PROCESSED_COMMANDS := 256
const ActionClock = preload("res://BattleActionClock.gd")
var _processed_command_ids: Dictionary = {}
var _opponent_playback: Array[Dictionary] = []
var _opponent_playback_due := 0
var _opponent_playback_last := -1000
var _authority_playback_running := false
var _opponent_playback_busy := false
var _room_checkpoint_revision := -1
var _action_clock := ActionClock.new()
var _action_timer: Control


func _ready() -> void:
	super._ready()
	_action_timer = preload("res://presentation/BattleActionTimer.gd").new()
	var row: HBoxContainer = end_turn_button.get_parent()
	row.add_child(_action_timer)
	row.move_child(_action_timer, end_turn_button.get_index())
	_action_timer.visibility_changed.connect(_align_turn_label)
	_action_timer.minimum_size_changed.connect(_align_turn_label)
	_apply_responsive_layout()


func _notification(what: int) -> void:
	if game != null and what in [NOTIFICATION_PAUSED, NOTIFICATION_UNPAUSED]:
		_tick_action_clock(true)


func _process(delta: float) -> void:
	_process_opponent_playback()
	super._process(delta)
	_sync_online_cost_picker()
	_process_action_timer()


func _process_action_timer() -> void:
	if game == null or _action_timer == null:
		return
	if battle_finished or (_challenge_controller != null and _challenge_controller.finished) \
		or PlayerData.battle_mode == "tutorial" or not ActionClock.enabled(game.battle_config):
		_action_timer.hide()
		return
	var paused := _action_clock_paused()
	var timed_out := _tick_action_clock(paused)
	_action_timer.present(_action_clock.remaining_ms, _action_clock.limit_ms, paused)
	if timed_out and (not PlayerData.is_online_battle() or NetworkManager.is_authority()):
		_end_timed_out_turn()


func _action_clock_paused() -> bool:
	return (_opening_coin_active or match_paused or _waiting_for_room_link() or _turn_ending
		or not game.is_player_turn or _authority_playback_running or is_resolution_locked()
		or _deployment_feedback_delay() > 0 or _result_waiting_for_feedback
		or (_challenge_controller != null and is_instance_valid(_challenge_controller.popup_layer))
		or (PlayerData.battle_mode == "practice" and game.current_player == 2))


func _tick_action_clock(paused: bool) -> bool:
	return _action_clock.tick(game.battle_config, Vector2i(game.turn_number, game.current_player),
		game.effective_actions_this_turn, paused, Time.get_ticks_msec())


func _network_battle_state() -> Dictionary:
	_tick_action_clock(_action_clock_paused())
	var state := super._network_battle_state()
	state["_action_clock_ms"] = _action_clock.remaining_ms
	return state


func _apply_authority_state(state: Dictionary, label: String = "authority") -> void:
	super._apply_authority_state(state, label)
	var remaining: Variant = state.get("_action_clock_ms")
	if (remaining is int or remaining is float) and is_finite(float(remaining)):
		_tick_action_clock(true)
		_action_clock.remaining_ms = int(clampf(float(remaining), 0, _action_clock.limit_ms))


func _end_timed_out_turn() -> void:
	if not game.is_player_turn or _turn_ending:
		return
	get_viewport().gui_cancel_drag()
	cancel_attack()
	for picker in get_tree().get_nodes_in_group("battle_timed_choice"):
		if is_ancestor_of(picker):
			picker.queue_free()
	_show_combat_broadcast(Locale.t("battle.action_timed_out"))
	if is_instance_valid(_online_cost_picker):
		_online_cost_picker.set_meta("submitted", true)
		_online_cost_picker.queue_free()
	game.pending_cost_choices.clear()
	if PlayerData.is_online_battle():
		_record_feedback_event("broadcast_text", game.current_player, -1, {"text_key": "battle.action_timed_out"})
		_turn_ending = true
		await _host_apply_end_turn(game.current_player, face_mana_button.button_pressed)
		_turn_ending = false
		_reset_face_mana_toggle()
		update_entire_screen()
	else:
		await _finish_end_turn(face_mana_button.button_pressed)


func _enqueue_opponent_playback(entry: Dictionary) -> void:
	if entry.has("id"):
		for queued in _opponent_playback:
			if queued.get("id") == entry["id"]:
				return
	if _opponent_playback.is_empty() and Time.get_ticks_msec() - _opponent_playback_last > 650:
		_opponent_playback_due = Time.get_ticks_msec() + 120
	_opponent_playback.append(entry)


func _process_opponent_playback() -> void:
	if match_paused or _authority_playback_running or _opponent_playback_busy or _opponent_playback.is_empty() or Time.get_ticks_msec() < _opponent_playback_due:
		return
	_opponent_playback_busy = true
	var entry: Dictionary = _opponent_playback.pop_front()
	if entry.has("state"):
		await _accept_authority_snapshot(entry["state"], "remote authority")
	else:
		await _apply_remote_game_intent(entry["kind"], entry["payload"], entry["player"], entry["id"], entry["revision"])
	_opponent_playback_busy = false
	# Catch up promptly if the relay delivered a burst.
	var gap := 45 if entry.has("id") or _opponent_playback.size() > 4 else roundi(80 * GamePreferences.battle_animation_duration_scale())
	_opponent_playback_last = Time.get_ticks_msec()
	_opponent_playback_due = _opponent_playback_last + gap

# ============================================
# Network
# ============================================

func is_my_turn() -> bool:
	if _opening_coin_active or battle_finished or match_paused or not game.is_player_turn or _turn_ending or _authority_playback_running or is_resolution_locked():
		return false
	return _owns_current_turn()


func _owns_current_turn() -> bool:
	if _opening_coin_active or battle_finished or _result_waiting_for_feedback or match_paused or _waiting_for_action_state() or not game.is_player_turn or _waiting_for_room_link(): return false
	if _challenge_controller != null and _challenge_controller.finished: return false
	if not game.pending_cost_choices.is_empty(): return false
	if _confirmed_game != null and not game.check_game_over().is_empty():
		return false
	if PlayerData.is_online_battle() and not NetworkManager.is_authority() and NetworkManager.pending_game_command_count() > 0 and not _can_continue_web_turn():
		return false
	if not PlayerData.is_online_battle():
		if PlayerData.battle_mode == "practice":
			return game.current_player == 1 and not practice_ai_running
		return true
	return game.current_player == my_player

func _turn_request_playback_pending() -> bool:
	return _authority_playback_running


func _init_network():
	if not PlayerData.is_online_battle():
		my_player = 0
		return
	my_player = NetworkManager.player_number
	EventBus.rpc_initial_state_received.connect(_on_rpc_initial_state)
	EventBus.rpc_initial_state_requested.connect(_on_rpc_initial_state_requested)
	EventBus.rpc_authority_state_received.connect(_on_rpc_authority_state)
	EventBus.rpc_summon_received.connect(_on_rpc_summon)
	EventBus.rpc_summon_skill_received.connect(_on_rpc_summon_skill)
	EventBus.rpc_attack_received.connect(_on_rpc_attack)
	EventBus.rpc_activate_skill_received.connect(_on_rpc_skill)
	EventBus.rpc_end_turn_received.connect(_on_rpc_end_turn)
	EventBus.rpc_discard_received.connect(_on_rpc_discard)
	EventBus.rpc_move_received.connect(_on_rpc_move)
	EventBus.rpc_intent_summon_received.connect(_on_rpc_intent_summon)
	EventBus.rpc_intent_summon_skill_received.connect(_on_rpc_intent_summon_skill)
	EventBus.rpc_intent_attack_received.connect(_on_rpc_intent_attack)
	EventBus.rpc_intent_activate_skill_received.connect(_on_rpc_intent_skill)
	EventBus.rpc_intent_end_turn_received.connect(_on_rpc_intent_end_turn)
	EventBus.rpc_intent_discard_received.connect(_on_rpc_intent_discard)
	EventBus.rpc_intent_move_received.connect(_on_rpc_intent_move)
	EventBus.rpc_game_intent_received.connect(_on_rpc_game_intent)
	EventBus.rpc_targeting_arrow_received.connect(_on_rpc_targeting_arrow)
	EventBus.rpc_splash_received.connect(_on_rpc_splash)
	EventBus.rpc_resume_state_requested.connect(_on_rpc_resume_state_requested)
	EventBus.rpc_resume_state_received.connect(_on_rpc_resume_state_received)
	EventBus.rpc_resume_state_ack_received.connect(_on_rpc_resume_state_ack)
	EventBus.rpc_resume_complete_received.connect(_on_rpc_resume_complete)
	NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.reconnect_started.connect(_on_reconnect_started)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_transport_ready)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	NetworkManager.reconnect_progress.connect(_on_reconnect_progress)
	NetworkManager.server_match_snapshot_received.connect(_on_server_match_snapshot)
	NetworkManager.room_command_checkpoint_received.connect(_on_room_command_checkpoint)
	NetworkManager.room_link_wait_changed.connect(_on_room_link_wait_changed)
	NetworkManager.game_command_status.connect(_on_game_command_status)


func _on_room_link_wait_changed() -> void:
	update_entire_screen()
	_close_recovery_forfeit_if_restored()
	if not battle_finished and not _waiting_for_room_link():
		_resume_auto_summon_targeting.call_deferred()


func _on_game_command_status(_command_id: String, kind: String, status: String, _latency_ms: int) -> void:
	_network_command_phase = status
	var online_guest := PlayerData.is_online_battle() and not NetworkManager.is_authority()
	if status == "timeout":
		if online_guest:
			if _timed_out_action != "end_turn":
				_timed_out_action = kind
		else:
			_show_toast("tip.command_timeout")
		if _confirmed_game != null:
			_rebuild_web_predictions.call_deferred()
	elif status in ["rejected", "stale_revision"]:
		if online_guest:
			_rejected_action_pending = true
		else:
			_show_toast("tip.command_resynced")
	if kind == "summon":
		_refresh_hand_ui.call_deferred()
	update_entire_screen()


func _pause_for_reconnect() -> void:
	_restore_confirmed_game()
	if not _opponent_playback.is_empty() and _opponent_playback.back().has("state"):
		var last: Dictionary = _opponent_playback.back()["state"]
		if int(last.get("state_revision", -1)) >= game.state_revision:
			game.apply_initial_state(last)
			_restore_local_art_paths()
	_opponent_playback.clear()
	if game != null:
		NetworkManager.save_match_snapshot(game.export_initial_state())
	match_paused = true
	if game != null:
		_refresh_hand_ui()
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	cancel_attack()
	remote_arrow_source = -1
	remote_arrow_target = -1
	if end_turn_button:
		end_turn_button.disabled = true
	update_entire_screen()


func _on_opponent_disconnected(_player: int) -> void:
	if battle_finished or _result_waiting_for_feedback or NetworkManager.has_vacant_lan_room_after_match():
		_refresh_online_result_destination()
		return
	if NetworkManager.has_resumable_match_session():
		_pause_for_reconnect()
		return
	# A transport without a persisted match identity cannot be recovered safely.
	battle_finished = true
	_record_match_history("interrupted", "")
	practice_ai_running = false
	cancel_attack()
	remote_arrow_source = -1
	remote_arrow_target = -1
	if attack_arrow:
		attack_arrow.visible = false
	if turn_label:
		turn_label.text = "[ %s ]" % Locale.t("result.connection_lost_title")
	if end_turn_button:
		end_turn_button.disabled = true
	_show_disconnect_result_page()


func _on_reconnect_started() -> void:
	_reset_resume_sync()
	_pause_for_reconnect()


func _on_reconnect_transport_ready() -> void:
	my_player = NetworkManager.player_number
	_local_slot_rejoined = true
	_reset_resume_sync()
	_pause_for_reconnect()
	call_deferred("_request_resume_state")


func _on_reconnect_progress(elapsed_seconds: int, attempt: int) -> void:
	_reconnect_elapsed_seconds = elapsed_seconds
	_reconnect_attempt = attempt
	_toggle_turn_cover()


func _on_server_match_snapshot(state: Dictionary) -> void:
	if game == null or state.is_empty():
		return
	if int(state.get("state_revision", -1)) < game.state_revision:
		return
	_apply_authority_state(state, "room server recovery")


func _on_room_command_checkpoint(state: Dictionary) -> void:
	if battle_finished or game == null or _authority_playback_running or not PlayerData.is_online_battle():
		return
	var confirmed: RefCounted = game if _confirmed_game == null else _confirmed_game
	var revision := int(state.get("state_revision", -1))
	var command_id := str(state.get("_checkpoint_command_id", ""))
	var confirms_rejection := not command_id.is_empty()
	if revision < confirmed.state_revision or (revision == confirmed.state_revision and not confirms_rejection):
		return
	if confirms_rejection:
		NetworkManager.acknowledge_game_command(command_id, revision, str(state["_checkpoint_rejection"]))
	# A regular update may have arrived while the checkpoint was in flight.
	# Only add summaries that advance the already displayed log.
	var confirmed_revision: int = confirmed.state_revision
	var feedback: Array = state.get("_feedback_events", [])
	state = state.duplicate()
	state["_feedback_events"] = feedback.filter(func(event):
		return int(event.get("checkpoint_revision", revision)) > confirmed_revision
	)
	_room_checkpoint_revision = revision
	_accept_authority_snapshot(state, "room checkpoint")
	NetworkManager._network_diag("room_checkpoint_applied", {"revision": revision})


func _on_reconnect_failed(_reason: String) -> void:
	UIMotion.replace_scene.call_deferred("res://MainMenu.tscn",true)


func _resume_now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _new_resume_nonce() -> String:
	return "%d-%d-%d" % [my_player, Time.get_ticks_usec(), randi()]


func _reset_resume_sync() -> void:
	_resume_nonce = ""
	_resume_waiting_nonce = ""
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	_resume_deadline = 0.0
	_resume_next_request_at = 0.0
	_resume_request_count = 0


func _ensure_resume_sync(nonce: String = "") -> void:
	if _resume_nonce.is_empty():
		_resume_nonce = nonce if not nonce.is_empty() else _new_resume_nonce()
		_resume_deadline = _resume_now() + RESUME_SYNC_TIMEOUT
		_resume_next_request_at = 0.0
		_resume_request_count = 0


func _process_resume_sync() -> void:
	if not match_paused or _resume_nonce.is_empty():
		return
	var now := _resume_now()
	if now >= _resume_deadline:
		_on_resume_sync_timeout()
		return
	if _resume_request_count < RESUME_MAX_REQUESTS and now >= _resume_next_request_at:
		_send_resume_request()


func _send_resume_request() -> void:
	if not PlayerData.is_online_battle() or my_player not in [1, 2] or _resume_nonce.is_empty():
		return
	_resume_request_count += 1
	_resume_next_request_at = _resume_now() + RESUME_REQUEST_INTERVAL
	NetworkManager.rpc_request_resume_state.rpc(my_player, game.state_revision, _resume_nonce)


func _request_resume_state() -> void:
	if not PlayerData.is_online_battle() or my_player not in [1, 2]:
		return
	match_paused = true
	_ensure_resume_sync()
	_send_resume_request()
	update_entire_screen()


func _on_rpc_resume_state_requested(requesting_player: int, known_revision: int, nonce: String) -> void:
	if not NetworkManager.MATCH_RECONNECT_ENABLED: return
	if not PlayerData.is_online_battle() or requesting_player == my_player:
		return
	_ensure_resume_sync(nonce)
	# Higher revision always wins. If both applications restarted at the same
	# revision, P1 is the deterministic source; otherwise the continuously-online
	# side supplies its in-memory state.
	if game.state_revision < known_revision or (
		game.state_revision == known_revision and _local_slot_rejoined and my_player > requesting_player
	):
		NetworkManager.rpc_request_resume_state.rpc(my_player, game.state_revision, nonce)
		return
	_pause_for_reconnect()
	_resume_waiting_for_player = requesting_player
	_resume_expected_revision = game.state_revision
	_resume_waiting_nonce = nonce
	NetworkManager.rpc_resume_state.rpc(_network_battle_state(), my_player, requesting_player, nonce)


func _on_rpc_resume_state_received(state: Dictionary, source_player: int, target_player: int, nonce: String) -> void:
	if not NetworkManager.MATCH_RECONNECT_ENABLED: return
	if target_player != my_player or source_player == my_player or nonce != _resume_nonce:
		return
	var incoming_revision := int(state.get("state_revision", -1))
	if incoming_revision < game.state_revision:
		return
	match_paused = true
	_apply_authority_state(state, "reconnect recovery")
	_resume_expected_revision = game.state_revision
	NetworkManager.rpc_resume_state_ack.rpc(my_player, game.state_revision, nonce)


func _on_rpc_resume_state_ack(player: int, revision: int, nonce: String) -> void:
	if not NetworkManager.MATCH_RECONNECT_ENABLED: return
	if player != _resume_waiting_for_player or revision != _resume_expected_revision or nonce != _resume_waiting_nonce:
		return
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	_resume_waiting_nonce = ""
	_finish_resume()
	NetworkManager.rpc_resume_complete.rpc(revision, my_player, nonce)


func _on_rpc_resume_complete(revision: int, nonce: String) -> void:
	if not NetworkManager.MATCH_RECONNECT_ENABLED: return
	if revision != game.state_revision or nonce != _resume_nonce:
		return
	_finish_resume()


func _finish_resume() -> void:
	match_paused = false
	NetworkManager.enable_match_relay_polling()
	_local_slot_rejoined = false
	NetworkManager.just_reconnected = false
	_reset_resume_sync()
	if end_turn_button:
		end_turn_button.disabled = not game.is_player_turn or not is_my_turn()
	update_entire_screen()
	_close_recovery_forfeit_if_restored()


func _on_resume_sync_timeout() -> void:
	_reset_resume_sync()
	match_paused = true
	_show_disconnect_result_page(true)
	update_entire_screen()


func _on_resume_retry_pressed() -> void:
	var old_layer := $CanvasLayer.get_node_or_null("BattleResultLayer")
	if old_layer:
		old_layer.queue_free()
	_local_slot_rejoined = true
	_reset_resume_sync()
	_pause_for_reconnect()
	if PlayerData.is_online_battle():
		call_deferred("_request_resume_state")
	else:
		NetworkManager.begin_saved_match_reconnect()


func _sync_targeting_state():
	if not PlayerData.is_online_battle():
		return
	var source := -1
	if current_attacker_idx != -1:
		source = current_attacker_idx
	elif summon_targeting:
		source = summon_source_slot
	elif activate_targeting:
		source = activate_source_slot
	# cast_targeting/parasite_targeting start from hand cards, so source stays -1.

	if source >= 0:
		NetworkManager.rpc_targeting_arrow.rpc(NetworkManager.battle_match_id, source, last_hovered_target, game.current_player)
	else:
		NetworkManager.rpc_targeting_arrow.rpc(NetworkManager.battle_match_id, -1, -1, game.current_player)


func _on_rpc_targeting_arrow(source_slot: int, target_slot: int, player: int):
	if game == null or player != game.current_player or not _can_show_remote_targeting():
		return
	if source_slot < 0 or target_slot < 0 or source_slot >= _their_slots_ui().size() or target_slot >= _my_slots_ui().size():
		remote_arrow_source = -1
		remote_arrow_target = -1
		return
	remote_arrow_source = source_slot
	remote_arrow_target = target_slot
	_remote_arrow_expires_at = Time.get_ticks_msec() + TARGETING_ARROW_REFRESH_MS * 5


func _on_rpc_splash(player: int, slot_index: int):
	# Only the authority broadcasts this RPC, and the authority never receives its
	# own call_remote, so any peer that gets here is the non-authority client and
	# must always render it (the client never shows the splash locally on its own
	# actions — it only sends an intent and waits for the authority to resolve).
	_update_remote_splash(player, slot_index)


# Authority-side: show the splash locally and tell the opponent to show the same.
# Capture the acting card before deaths are applied so its art/name still resolves.
func _authority_splash(player: int, slot_index: int) -> void:
	if slot_index < 0:
		return
	var field = game.player_field if player == 1 else game.player2_field
	var card: CardData = field.slots[slot_index]
	if card != null:
		_show_splash(card)
	if PlayerData.is_online_battle():
		NetworkManager.rpc_splash.rpc(NetworkManager.battle_match_id, player, slot_index)


func _on_rpc_initial_state(state: Dictionary):
	if NetworkManager.is_authority():
		return
	if _room_checkpoint_revision >= 0 and not _waiting_for_action_state():
		var confirmed: RefCounted = game if _confirmed_game == null else _confirmed_game
		if int(state.get("state_revision", -1)) == confirmed.state_revision:
			# A redundant recovery reply can arrive with a newer action result
			# in the same frame. Keep its silent refresh from hiding that result.
			return
	if _opponent_playback.is_empty():
		_accept_authority_snapshot(state, "initial")


func _on_rpc_initial_state_requested(_peer_id: int):
	if not NetworkManager.is_authority():
		return
	if not _has_online_prediction():
		_broadcast_authority_state("initial request")
	NetworkManager.send_initial_state(_network_battle_state())


func _on_rpc_authority_state(state: Dictionary):
	if NetworkManager.is_authority():
		return
	if _authority_playback_running:
		_enqueue_opponent_playback({"state": state})
		return
	if _has_online_prediction() and not match_paused and _confirmed_game == null and (
		not _opponent_playback.is_empty() or (game.current_player != my_player and int(state.get("state_revision", -1)) > game.state_revision)
	):
		_enqueue_opponent_playback({"state": state})
		return
	_accept_authority_snapshot(state, "remote authority")


func _accept_authority_snapshot(state: Dictionary, label: String) -> void:
	var confirmed: RefCounted = game if _confirmed_game == null else _confirmed_game
	var revision := int(state.get("state_revision", -1))
	if revision < confirmed.state_revision:
		if _rejected_action_pending:
			_rebuild_web_predictions()
			if _timed_out_action.is_empty() and NetworkManager.pending_game_command_count() == 0:
				_turn_ending = false
			_finish_rejected_action_sync()
		return
	# The checkpoint already showed this revision's outcome and action log.
	# Only a new rejection or timeout can still need this unchanged state.
	if label == "remote authority" and revision == _room_checkpoint_revision:
		if not _waiting_for_action_state():
			return
		state = state.duplicate()
		state.erase("_feedback_events")
		state.erase("_hp_events")
	# Keep the outgoing layout until every hero strike lands. State/ACK data
	# stays intact; only feedback already played here is omitted from replay.
	var feedback: Array = state.get("_feedback_events", [])
	var hero_events := feedback.filter(func(event): return event.get("kind", "") == "hero_damage")
	if not hero_events.is_empty() and label == "remote authority":
		_authority_playback_running = true
		for event in hero_events:
			_show_direct_damage(event.get("result", {}))
		await _wait_for_direct_damage()
		_authority_playback_running = false
		state = state.duplicate(true)
		state["_feedback_events"] = feedback.filter(func(event): return event.get("kind", "") != "hero_damage")
	_restore_confirmed_game()
	NetworkManager.reconcile_pending_game_commands(revision, label == "initial" and not _has_online_prediction())
	_apply_authority_state(state, label)
	_rebuild_web_predictions()


func _send_current_state_for_command(command_id: String, status: String) -> void:
	NetworkManager.set_next_authority_ack(command_id, status)
	NetworkManager.broadcast_authority_state(_network_battle_state())


func _remember_processed_command(command_id: String, status: String) -> void:
	_processed_command_ids[command_id] = status
	if _processed_command_ids.size() > MAX_PROCESSED_COMMANDS:
		_processed_command_ids.erase(_processed_command_ids.keys()[0])


func _on_rpc_game_intent(kind: String, payload: Dictionary, player: int, command_id: String, expected_revision: int) -> void:
	if _has_online_prediction() and not match_paused and player == game.current_player and player != my_player and not _processed_command_ids.has(command_id):
		_enqueue_opponent_playback({"kind": kind, "payload": payload, "player": player, "id": command_id, "revision": expected_revision})
		return
	_apply_remote_game_intent(kind, payload, player, command_id, expected_revision)


func _apply_remote_game_intent(kind: String, payload: Dictionary, player: int, command_id: String, expected_revision: int) -> void:
	if not NetworkManager.is_authority():
		return
	if _processed_command_ids.has(command_id):
		var previous: String = _processed_command_ids[command_id]
		if previous == "processing":
			return  # Retry while the original settlement is still animating.
		_send_current_state_for_command(command_id, "duplicate" if previous == "applied" else previous)
		return
	if expected_revision != game.state_revision:
		_remember_processed_command(command_id, "stale_revision")
		_send_current_state_for_command(command_id, "stale_revision")
		return
	var after_move := str(payload.get("after_move", ""))
	var checkpoint := str(payload.get("turn_slots", ""))
	var turn_hash := str(payload.get("turn_hash", ""))
	if (not after_move.is_empty() and _processed_command_ids.get(after_move) != "applied") or (
		kind == "end_turn" and ((not checkpoint.is_empty() and checkpoint != _turn_slot_checkpoint(_field_for_player(player).slots))
			or (not turn_hash.is_empty() and turn_hash != _web_turn_hash()))
	):
		_remember_processed_command(command_id, "rejected")
		_send_current_state_for_command(command_id, "rejected")
		return
	_remember_processed_command(command_id, "processing")
	NetworkManager.set_next_authority_ack(command_id, "applied")
	var old_revision: int = int(game.state_revision)
	await _execute_network_command(kind, payload, player)
	if game.state_revision == old_revision:
		_remember_processed_command(command_id, "rejected")
		_send_current_state_for_command(command_id, "rejected")
	else:
		_remember_processed_command(command_id, "applied")


func _predict_web_command(kind: String, payload: Dictionary, player: int) -> bool:
	var base: RefCounted = game
	game = base.copy_for_simulation()
	var previously_blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	_simulating_web_command = true
	_execute_network_command(kind, payload, player)
	_simulating_web_command = false
	EventBus.set_block_signals(previously_blocked)
	if game.state_revision == base.state_revision:
		game = base
		return false
	return true


func _rebuild_web_predictions() -> void:
	_restore_confirmed_game()
	if match_paused or not _has_online_prediction() or NetworkManager.is_authority() or not game.check_game_over().is_empty():
		return
	var confirmed: RefCounted = game
	for command in NetworkManager.pending_game_commands():
		if command["kind"] == "end_turn":
			break
		if int(command["expected_revision"]) != game.state_revision or int(command["player"]) != game.current_player:
			break
		if not _predict_web_command(command["kind"], command["payload"], command["player"]):
			break
		_confirmed_game = confirmed
		_web_prediction_count += 1
	_refresh_hand_ui()
	update_entire_screen()


func _execute_network_command(kind: String, payload: Dictionary, player: int) -> void:
	if battle_finished or not game.is_player_turn or not game.check_game_over().is_empty():
		return
	if kind == "activate_skill" and payload.has("cost_choice"):
		var index: Variant = payload.cost_choice
		if not _simulating_web_command and not match_paused and (index is int or index is float) \
				and index >= -1 and index < 25 and index == floor(index):
			_resolve_online_cost_choice(player, int(index))
		return
	if not game.pending_cost_choices.is_empty(): return
	match kind:
		"summon":
			_host_apply_summon(int(payload.get("hand_index", -1)), int(payload.get("slot_index", -1)), player, str(payload.get("card_instance", "")))
		"summon_skill":
			_host_apply_summon_skill(int(payload.get("slot_index", -1)), int(payload.get("skill_index", -1)), int(payload.get("target_slot", -1)), player, int(payload.get("target_player", 0)))
		"attack":
			_host_apply_attack(int(payload.get("source_slot", -1)), int(payload.get("target_slot", -1)), player)
		"activate_skill":
			var slot_index := int(payload.get("slot_index", -1))
			var skill_index := int(payload.get("skill_index", -1))
			var target_slot := int(payload.get("target_slot", -1))
			if _is_parasite_intent_source(slot_index):
				_host_apply_parasite(_parasite_hand_index_from_intent(slot_index), _parasite_target_player_from_intent(slot_index), target_slot, player)
			elif _is_spell_intent_source(slot_index):
				_host_apply_cast(_spell_hand_index_from_intent(slot_index), skill_index, target_slot, player, int(payload.get("target_player", 0)))
			else:
				_host_apply_skill(slot_index, skill_index, target_slot, player, int(payload.get("target_player", 0)))
		"end_turn":
			await _host_apply_end_turn(player, payload.get("allow_face_mana", true) == true)
		"discard":
			_host_apply_discard(str(payload.get("location", "")), int(payload.get("index", -1)), player)
		"move":
			_host_apply_move(int(payload.get("source_slot", -1)), int(payload.get("target_slot", -1)), player)


func _host_apply_summon(hand_index: int, slot_index: int, player: int, expected_instance: String = "") -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var hand = _hand_for_player(player)
	if hand_index < 0 or hand_index >= hand.size():
		return
	if not expected_instance.is_empty() and hand[hand_index].instance_id != expected_instance:
		return
	var saved = game.current_player
	game.current_player = player
	var card: CardData = hand[hand_index]
	if not game.summon_card(card, slot_index):
		game.current_player = saved
		return
	game.current_player = saved
	if _simulating_web_command:
		_host_auto_resolve_summon_skills(slot_index, player)
		_commit_authority_state("summon")
		return
	_play_summon_feedback(_slot_ui_for_player(player, slot_index))
	_record_feedback_event("summon", player, slot_index)
	_host_auto_resolve_summon_skills(slot_index, player)
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("summon")
	if player == _view_player():
		_resume_auto_summon_targeting.call_deferred(slot_index)


func _host_auto_resolve_summon_skills(slot_index: int, player: int) -> void:
	var field := _field_for_player(player)
	var card: CardData = field.slots[slot_index] if slot_index >= 0 and slot_index < field.slots.size() else null
	if card == null:
		return
	for skill_index in range(card.skills.size()):
		if not _summon_skill_is_pending(card, skill_index):
			continue
		var skill: Dictionary = card.skills[skill_index]
		if _skill_needs_targeting(skill) and _summon_skill_has_live_manual_target(skill, player, card):
			continue
		_host_apply_summon_skill(slot_index, skill_index, -1, player, 0, false)
		card = field.slots[slot_index]
		if card == null:
			break


func _host_apply_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int, target_player: int = 0, commit_state: bool = true) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var source_field := _field_for_player(player)
	if slot_index < 0 or slot_index >= source_field.slots.size():
		return
	var source_card: CardData = source_field.slots[slot_index]
	if source_card == null or skill_index < 0 or skill_index >= source_card.skills.size():
		return
	var skill: Dictionary = source_card.skills[skill_index]
	if not _summon_skill_is_pending(source_card, skill_index):
		return
	var resolved_target_player := target_player if target_player in [1, 2] else _opponent_of_player(player)
	var target_field := _field_for_player(resolved_target_player)
	var target_card: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	if target_slot >= 0 and SpellRules.needs_target(skill) and not SpellRules.can_select_unit(skill, source_card, target_field, target_slot, resolved_target_player != player, game.turn_number):
		return
	if not _simulating_web_command:
		_begin_action_broadcast("summon_skill", player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_summon_skills(slot_index, target_slot, skill_index, resolved_target_player)
	game.current_player = saved
	if _simulating_web_command:
		game.cleanup_deaths()
		if commit_state:
			_commit_authority_state("summon skill")
		return
	if SpellRules.needs_target(skill):
		_record_directed_action(player, slot_index, resolved_target_player, target_slot)
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, slot_index, skill_index)
	_record_feedback_event("skill", player, slot_index, {"skill_index":skill_index})
	# Skill feedback and its replay event own the reveal; avoid a second card reveal.
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		if commit_state:
			_commit_authority_state("game over")
		return
	if commit_state:
		_commit_authority_state("summon skill")
		if player == _view_player():
			_resume_auto_summon_targeting.call_deferred(slot_index)


func _host_apply_attack(source_slot: int, target_slot: int, player: int) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	if source_slot not in range(5) or target_slot not in range(5) or not game.can_pay_action():
		return
	var attacker: CardData = _field_for_player(player).slots[source_slot]
	var victim: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot]
	var base_damage: int = attacker.atk if attacker != null else 0
	var effective_damage: int = attacker.effective_atk() if attacker != null else 0
	if not _simulating_web_command:
		_begin_action_broadcast("attack", player, attacker.card_name if attacker != null else Locale.t("battle.log.unit"), victim.card_name if victim != null else Locale.t("battle.log.unit"), {"base_damage": base_damage, "effective_damage": effective_damage, "target_player": _opponent_of_player(player), "target_slot": target_slot})
	var saved = game.current_player
	game.current_player = player
	var result: Dictionary = game.execute_attack(source_slot, target_slot)
	game.current_player = saved
	if result.is_empty():
		if not _simulating_web_command:
			_action_broadcast.clear()
		return
	if _simulating_web_command:
		game.cleanup_deaths()
		_commit_authority_state("attack")
		return
	if victim != null and not victim.is_alive():
		_action_broadcast["kill_mana"] = true
	_record_directed_action(player, source_slot, _opponent_of_player(player), target_slot, true)
	_finish_action_broadcast()
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	_commit_authority_state("attack")


func _host_apply_skill(slot_index: int, skill_index: int, target_slot: int, player: int, target_player: int = 0) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var source_field := _field_for_player(player)
	if slot_index < 0 or slot_index >= source_field.slots.size():
		return
	var source_card: CardData = source_field.slots[slot_index]
	if source_card == null or skill_index < 0 or skill_index >= source_card.skills.size():
		return
	var skill: Dictionary = source_card.skills[skill_index]
	var directed := SpellRules.needs_target(skill)
	var side := target_player if target_player in [1, 2] else 3 - player
	var target_field := _field_for_player(side)
	var target_card: CardData = target_field.slots[target_slot] if target_slot in range(target_field.slots.size()) else null
	if directed and not SpellRules.can_select_unit(skill, source_card, target_field, target_slot, side != player, game.turn_number):
		return
	if source_card == null or source_card.skills_used.has(skill_index) \
			or str(skill.get("trigger", "")) != SkillEngine.TRIGGER_ON_ACTIVATE \
			or not SkillEngine.has_uses_remaining(source_card, skill, skill_index):
		return
	if game.turn_number <= 1 and SkillRegistry.skill_changes_enemy_hp_or_presence(skill):
		return
	if not _simulating_web_command:
		_begin_action_broadcast("skill", player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if not game.trigger_activate_skills(slot_index, target_slot, skill_index, side):
		game.current_player = saved
		if not _simulating_web_command:
			_action_broadcast.clear()
		return
	game.current_player = saved
	if _simulating_web_command:
		game.cleanup_deaths()
		_commit_authority_state("activate skill")
		return
	if directed:
		_record_directed_action(player, slot_index, side, target_slot)
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, slot_index, skill_index)
	_record_feedback_event("skill", player, slot_index, {"skill_index":skill_index})
	# Skill feedback and its replay event own the reveal; avoid a second card reveal.
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	_commit_authority_state("activate skill")


func _host_apply_parasite(hand_index: int, target_player: int, target_slot: int, player: int) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var hand := _hand_for_player(player)
	var parasite_card: CardData = hand[hand_index] if hand_index >= 0 and hand_index < hand.size() else null
	var target_field := _field_for_player(target_player)
	var target_card: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	if not _simulating_web_command:
		_begin_action_broadcast("parasite", player, parasite_card.card_name if parasite_card != null else Locale.t("battle.log.parasite"), target_card.card_name if target_card != null else "")
	var saved = game.current_player
	game.current_player = player
	var attach_ok: bool = game.attach_parasite(hand_index, target_player, target_slot)
	game.current_player = saved
	if not attach_ok:
		if not _simulating_web_command:
			_action_broadcast.clear()
			_action_hp_events.clear()
		return
	if _simulating_web_command:
		_commit_authority_state("attach parasite")
		return
	_record_directed_action(player, -1, target_player, target_slot, false, hand_index)
	_finish_action_broadcast()
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("attach parasite")


func _host_apply_cast(hand_index: int, skill_index: int, target_slot: int, player: int, target_player: int = 0) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var hand := _hand_for_player(player)
	var spell_card: CardData = hand[hand_index] if hand_index >= 0 and hand_index < hand.size() else null
	if spell_card == null:
		return
	var cast_check: Dictionary = SpellRules.can_cast(spell_card, _field_for_player(player).get_total_mana(), skill_index, game.turn_number)
	if not cast_check.get("ok", false):
		return
	var resolved_target_player := target_player
	if cast_check.get("needs_target", false):
		var skill: Dictionary = cast_check.get("skill", {})
		if resolved_target_player not in [1, 2]:
			resolved_target_player = 3 - player
		var target_field := _field_for_player(resolved_target_player)
		if not SpellRules.can_select_unit(skill, spell_card, target_field, target_slot, resolved_target_player != player, game.turn_number):
			return
	if not _simulating_web_command:
		_begin_action_broadcast("cast", player, spell_card.card_name if spell_card != null else Locale.t("battle.log.spell_word"), "")
	var saved = game.current_player
	game.current_player = player
	var cast_ok: bool = game.cast_spell(hand_index, skill_index, target_slot, resolved_target_player)
	game.current_player = saved
	if not cast_ok:
		if not _simulating_web_command:
			_action_broadcast.clear()
			_action_hp_events.clear()
		return
	if _simulating_web_command:
		game.cleanup_deaths()
		_commit_authority_state("cast spell")
		return
	if cast_check.get("needs_target", false):
		_record_directed_action(player, -1, resolved_target_player, target_slot, false, hand_index)
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, -1)
	_record_feedback_event("cast", player, -1)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	_commit_authority_state("cast spell")


func _host_apply_discard(location: String, index: int, player: int, drop_position: Vector2 = Vector2.INF) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var card: CardData = null
	if location == "hand":
		var hand = _hand_for_player(player)
		if index >= 0 and index < hand.size():
			card = hand[index]
	elif location == "field":
		var field = _field_for_player(player)
		if index >= 0 and index < field.slots.size():
			card = field.slots[index]
	if card == null:
		return
	var discard_start := drop_position if drop_position != Vector2.INF else _discard_source_position(player,location,index)
	var saved = game.current_player
	game.current_player = player
	var refund: int = game.discard_card_with_refund(card)
	game.current_player = saved
	if refund < 0:
		return
	if _simulating_web_command:
		_commit_authority_state("discard")
		return
	_play_discard_feedback(discard_start)
	_refresh_hand_ui()
	update_entire_screen()
	var text_key := _discard_broadcast_key(refund)
	_show_combat_broadcast(Locale.t(text_key))
	_record_feedback_event("broadcast_text", player, -1, {"text_key": text_key})
	_record_feedback_event("discard", player, -1, {"location":location,"index":index})
	_commit_authority_state("discard")


func _host_apply_move(source_slot: int, target_slot: int, player: int) -> void:
	if match_paused or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	var field = _field_for_player(player)
	if source_slot < 0 or source_slot >= field.slots.size() or target_slot < 0 or target_slot >= field.slots.size():
		return
	if source_slot == target_slot or field.slots[source_slot] == null:
		return
	var displaced = field.slots[target_slot]
	field.slots[target_slot] = field.slots[source_slot]
	field.slots[source_slot] = displaced
	if _simulating_web_command:
		_commit_authority_state("move")
		return
	_play_move_feedback(player, source_slot, target_slot)
	update_entire_screen()
	_record_feedback_event("move", player, source_slot, {"target_slot": target_slot})
	_commit_authority_state("move")


func _host_apply_end_turn(player: int, allow_face_mana: bool = true) -> void:
	if match_paused or not game.is_player_turn or not (_simulating_web_command or NetworkManager.is_authority()) or player != game.current_player:
		return
	if _simulating_web_command:
		game.end_player_turn(allow_face_mana)
		if game.check_game_over().is_empty():
			game.start_new_turn()
		_commit_authority_state("end turn")
		return
	remote_arrow_source = -1
	var result = game.end_player_turn(allow_face_mana)
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	await _wait_for_direct_damage()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	game.start_new_turn()
	AppAudio.play("turn")
	_record_feedback_event("turn", game.current_player, -1)
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("end turn")


func _spell_intent_source(hand_index: int) -> int:
	return -1000 - hand_index


func _parasite_intent_source(hand_index: int, target_player: int) -> int:
	return (-2000 - hand_index) if target_player == 1 else (-3000 - hand_index)


func _is_parasite_intent_source(source_slot: int) -> bool:
	return source_slot <= -2000 and source_slot > -4000


func _parasite_hand_index_from_intent(source_slot: int) -> int:
	return (-2000 - source_slot) if source_slot > -3000 else (-3000 - source_slot)


func _parasite_target_player_from_intent(source_slot: int) -> int:
	return 1 if source_slot > -3000 else 2


func _is_spell_intent_source(source_slot: int) -> bool:
	return source_slot <= -1000 and source_slot > -2000


func _spell_hand_index_from_intent(source_slot: int) -> int:
	return -1000 - source_slot


func _on_rpc_intent_summon(hand_index: int, slot_index: int, player: int):
	_host_apply_summon(hand_index, slot_index, player)


func _on_rpc_intent_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	_host_apply_summon_skill(slot_index, skill_index, target_slot, player)


func _on_rpc_intent_attack(source_slot: int, target_slot: int, player: int):
	_host_apply_attack(source_slot, target_slot, player)


func _on_rpc_intent_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	if _is_parasite_intent_source(slot_index):
		_host_apply_parasite(_parasite_hand_index_from_intent(slot_index), _parasite_target_player_from_intent(slot_index), target_slot, player)
		return
	if _is_spell_intent_source(slot_index):
		_host_apply_cast(_spell_hand_index_from_intent(slot_index), skill_index, target_slot, player)
		return
	_host_apply_skill(slot_index, skill_index, target_slot, player)


func _on_rpc_intent_end_turn(player: int):
	await _host_apply_end_turn(player)


func _on_rpc_intent_discard(location: String, index: int, player: int):
	_host_apply_discard(location, index, player)


func _on_rpc_intent_move(source_slot: int, target_slot: int, player: int):
	_host_apply_move(source_slot, target_slot, player)


func _on_rpc_summon(_hand_index: int, _slot_index: int, _player: int):
	return


func _on_rpc_summon_skill(_slot_index: int, _skill_index: int, _target_slot: int, _player: int):
	return


func _on_rpc_attack(_source_slot: int, _target_slot: int, _player: int):
	return


func _on_rpc_skill(_slot_index: int, _skill_index: int, _target_slot: int, _player: int):
	return


func _on_rpc_end_turn(_player: int):
	return


func _on_rpc_discard(_location: String, _index: int, _player: int):
	return


func _on_rpc_move(_source_slot: int, _target_slot: int, _player: int):
	return


func _update_remote_splash(player: int, slot_index: int):
	var field = game.player_field if player == 1 else game.player2_field
	var card = field.slots[slot_index]
	if card != null:
		_show_splash(card)

func _build_turn_cover():
	turn_cover = ColorRect.new()
	turn_cover.name = "TurnCover"
	turn_cover.visible = false
	turn_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_cover.anchor_right = 1.0
	turn_cover.anchor_bottom = 1.0
	turn_cover.color = Color(0.0, 0.0, 0.0, 0.34)
	$CanvasLayer.add_child(turn_cover)

	turn_wait_hint = Panel.new()
	turn_wait_hint.name = "TurnWaitHint"
	turn_wait_hint.visible = false
	turn_wait_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_wait_hint.z_index = 2
	UITheme.apply_panel(turn_wait_hint, "gold")
	var lbl = Label.new()
	lbl.name = "Label"
	lbl.text = Locale.t("battle.waiting")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_constant_override("line_spacing", 1)
	lbl.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(lbl, true)
	turn_wait_hint.add_child(lbl)
	reconnect_leave_button = Button.new()
	reconnect_leave_button.name = "LeaveButton"
	reconnect_leave_button.text = Locale.t("battle.abandon_match")
	reconnect_leave_button.anchor_left = 1.0
	reconnect_leave_button.anchor_right = 1.0
	reconnect_leave_button.anchor_bottom = 1.0
	reconnect_leave_button.mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.apply_button(reconnect_leave_button, "secondary")
	reconnect_leave_button.pressed.connect(_on_abandon_reconnect_pressed)
	reconnect_leave_button.visible = false
	turn_wait_hint.add_child(reconnect_leave_button)
	combat_broadcast_panel.add_child(turn_wait_hint)
	turn_wait_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_wait_hint_layout()


func _update_wait_hint_layout() -> void:
	if turn_wait_hint == null:
		return
	var s := _ui_scale()
	var recovering := match_paused or _waiting_for_room_link()
	var party_recovering := _is_party_battle() and recovering
	var readable_size := ceili(_screen_pixels_in_ui(10))
	var button_width := 0.0
	if reconnect_leave_button:
		reconnect_leave_button.visible = recovering
		reconnect_leave_button.add_theme_font_size_override("font_size", maxi(readable_size, int(12 * s)))
		if recovering:
			button_width = maxf(120.0 * s, reconnect_leave_button.get_combined_minimum_size().x)
			reconnect_leave_button.anchor_left = 0.0 if party_recovering else 1.0
			reconnect_leave_button.offset_left = 4.0 * s if party_recovering else -button_width - 4.0 * s
			reconnect_leave_button.offset_right = -4.0 * s
			reconnect_leave_button.offset_top = 4.0 * s
			reconnect_leave_button.offset_bottom = -4.0 * s
	var lbl := turn_wait_hint.get_node_or_null("Label")
	if lbl:
		lbl.visible = not party_recovering
		var minimum_font_size := readable_size if recovering else 10
		lbl.add_theme_font_size_override("font_size", maxi(minimum_font_size, int((14 if recovering else 15) * s)))
		lbl.offset_left = 8.0 * s
		lbl.offset_right = -button_width - (12.0 if recovering else 8.0) * s
		lbl.offset_top = 3.0 * s
		lbl.offset_bottom = -3.0 * s


func _toggle_turn_cover():
	var overlay = $CanvasLayer.get_node_or_null("TurnOverlay")
	if not turn_cover and not turn_wait_hint and not overlay:
		return
	var command_pending: bool = PlayerData.is_online_battle() and not NetworkManager.is_authority() and NetworkManager.pending_game_command_count() > 0
	var link_waiting := _waiting_for_room_link()
	var action_sync_pending := _waiting_for_action_state()
	var waiting_for_turn: bool = PlayerData.is_online_battle() and (not bool(game.is_player_turn) or int(game.current_player) != my_player)
	var practice_waiting: bool = PlayerData.battle_mode == "practice" and int(game.current_player) == 2
	var resolving_turn: bool = waiting_for_turn and not game.is_player_turn
	var show_cover: bool = match_paused or link_waiting or action_sync_pending or waiting_for_turn or practice_waiting
	var show_hint: bool = not _result_waiting_for_feedback and (
		match_paused or link_waiting or action_sync_pending or command_pending or resolving_turn
		or (practice_waiting and (not game.is_player_turn or combat_broadcast_panel.text.is_empty())))
	var wait_text := Locale.t("battle.waiting")
	if link_waiting:
		wait_text = Locale.t("battle.room_link_waiting")
	elif action_sync_pending:
		wait_text = Locale.t("battle.end_turn_sync_pending" if _timed_out_action == "end_turn" else "battle.action_sync_pending")
	elif resolving_turn:
		wait_text = Locale.t("battle.resolving_turn")
	if turn_cover:
		turn_cover.visible = show_cover
		$CanvasLayer.move_child(turn_cover, max(0, $CanvasLayer.get_child_count() - 2))
		if turn_cover.get_child_count() > 0 and turn_cover.get_child(0) is Label:
			turn_cover.get_child(0).text = Locale.t("battle.reconnecting") if match_paused else wait_text
	if turn_wait_hint:
		_update_wait_hint_layout()
		var label := turn_wait_hint.get_node_or_null("Label")
		if label:
			if match_paused and not _is_party_battle():
				label.text = Locale.t("battle.reconnecting_progress", [_reconnect_attempt, _reconnect_elapsed_seconds])
			elif command_pending and not link_waiting and not action_sync_pending:
				label.text = Locale.t("battle.command_received" if _network_command_phase == "received" else "battle.command_sent")
			else:
				label.text = wait_text
		var was_visible := turn_wait_hint.visible
		turn_wait_hint.visible = show_hint
		var show_summary := not show_hint and not combat_broadcast_panel.text.is_empty()
		combat_broadcast_panel.self_modulate.a = 1.0 if show_summary else 0.0
		combat_broadcast_panel.mouse_filter = Control.MOUSE_FILTER_PASS if show_summary else Control.MOUSE_FILTER_IGNORE
		if command_pending and not match_paused:
			turn_wait_hint.modulate.a = 1.0
		elif show_hint and not was_visible:
			var fade := create_tween()
			turn_wait_hint.modulate.a = 0.0
			fade.tween_property(turn_wait_hint, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if overlay:
		overlay.visible = show_cover


func _on_abandon_reconnect_pressed() -> void:
	if not battle_finished and (match_paused or _waiting_for_room_link()):
		_show_abandon_confirmation(140, Callable(), true)


func _close_recovery_forfeit_if_restored() -> void:
	if battle_finished or match_paused or _waiting_for_room_link():
		return
	var prompt := get_node_or_null("AbandonBattleConfirmation") as CanvasLayer
	if prompt == null or prompt.is_queued_for_deletion() or not prompt.get_meta("recovery_only", false):
		return
	prompt.hide()
	prompt.queue_free()
	_spawn_toast(Locale.t("battle.room_link_restored"))


# ============================================
# Draw/Discard pile UI
# ============================================

func _build_pile_buttons():
	draw_pile_btn = preload("res://presentation/BattlePileButton.gd").new()
	draw_pile_btn.name = "DrawPile"
	draw_pile_btn.pressed.connect(_on_draw_pile_clicked)
	pile_column.add_child(draw_pile_btn)
	discard_pile_btn = preload("res://presentation/BattlePileButton.gd").new()
	discard_pile_btn.name = "DiscardPile"
	discard_pile_btn.set("is_discard_pile",true)
	discard_pile_btn.pressed.connect(_on_discard_pile_clicked)
	discard_column.add_child(discard_pile_btn)
	discard_zone = discard_pile_btn

	help_btn = Button.new()
	help_btn.text = Locale.t("help.button")
	help_btn.pressed.connect(_on_help_clicked)
	UITheme.apply_button(help_btn, "secondary")
	$CanvasLayer.add_child(help_btn)
	field_rules_btn = Button.new()
	field_rules_btn.text = Locale.t("battle.match_info")
	field_rules_btn.pressed.connect(_show_help_popup.bind(true))
	UITheme.apply_button(field_rules_btn, "secondary")
	$CanvasLayer.add_child(field_rules_btn)
	battle_settings_btn = Button.new()
	battle_settings_btn.name = "BattleSettingsButton"
	battle_settings_btn.text = Locale.t("preferences.settings")
	battle_settings_btn.pressed.connect(_open_battle_settings)
	UITheme.apply_button(battle_settings_btn, "secondary")
	$CanvasLayer.add_child(battle_settings_btn)
	Locale.language_changed.connect(func(): battle_settings_btn.text = Locale.t("preferences.settings"))

	_update_pile_labels()
	_apply_responsive_layout()


func _open_battle_settings() -> void:
	if has_node("BattleSettingsOverlay"): return
	var settings := preload("res://presentation/BattlePause.gd").new()
	settings.name = "BattleSettingsOverlay"
	settings.settings_only = true
	settings.battle = self
	add_child(settings)


func _on_debug_state_clicked():
	_print_authority_state("button")
	if PlayerData.is_online_battle() and NetworkManager.is_authority():
		NetworkManager.broadcast_authority_state(game.export_initial_state())


func _on_help_clicked():
	_show_help_popup()


# Static rules manual — blur overlay + scrollable mechanics text.
func _show_help_popup(field_rules_only: bool = false):
	var s := _ui_scale()
	var popup_layer := CanvasLayer.new()
	popup_layer.name = "BattleFieldRules" if field_rules_only else "BattleRulesHelp"
	popup_layer.layer = 100
	popup_layer.add_to_group("battle_modal")
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var panel := Panel.new()
	panel.name = "BattleHelpPanel"
	UITheme.apply_popup_frame(panel, "gold", false, true)
	panel.clip_contents = true
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	popup_layer.add_child(panel)
	UITheme.animate_popup_enter(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(16 * s))
	margin.add_theme_constant_override("margin_bottom", int(16 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("battle.match_info" if field_rules_only else "help.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, max(16, int(24 * s)))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.name = "BattleHelpScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)
	UITheme.apply_scrollbar(scroll.get_v_scroll_bar())

	var body := Label.new()
	body.name = "BattleHelpBody"
	body.text = preload("res://BattleRulesHelp.gd").description(game)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	body.add_theme_font_size_override("font_size", max(12, int(17 * s)))
	UITheme.apply_label(body)
	if field_rules_only:
		body.free()
		scroll.free()
		preload("res://BattleFieldRules.gd").build_info(vbox, game, self, popup_layer)
	else:
		scroll.add_child(body)

	var close_btn := Button.new()
	close_btn.name = "BattleHelpClose"
	close_btn.text = Locale.t("help.close")
	close_btn.custom_minimum_size = Vector2(100, 40) * s
	close_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(popup_layer.queue_free)
	vbox.add_child(close_btn)


func _record_match_history(outcome: String, result: String) -> void:
	if _history_recorded or game == null:
		return
	_history_recorded = true
	var online_match := my_player in [1, 2]
	var mode := "online" if online_match else PlayerData.battle_mode
	var history_game: RefCounted = _confirmed_game if _confirmed_game != null else game
	var deck_faces := PlayerData.snapshot_history_cards(PlayerData.battle_deck)
	var opponent_faces := PlayerData.snapshot_history_cards(PlayerData.opponent_battle_deck)
	var local_is_p2 := my_player == 2
	PlayerData.add_match_history({
		"mode": mode,
		"outcome": outcome,
		"result": result,
		"turns": int(history_game.turn_number),
		"player_hp": int(history_game.player2_field.player_hp if local_is_p2 else history_game.player_field.player_hp),
		"opponent_hp": int(history_game.player_field.player_hp if local_is_p2 else history_game.player2_field.player_hp),
		"player_max_hp": int(history_game.player2_field.max_player_hp if local_is_p2 else history_game.player_field.max_player_hp),
		"opponent_max_hp": int(history_game.player_field.max_player_hp if local_is_p2 else history_game.player2_field.max_player_hp),
		"local_player": my_player if online_match else 1,
		"deck_name": _history_deck_name,
		"deck_cards": deck_faces.map(func(face: Dictionary): return face.name),
		"opponent_cards": opponent_faces.map(func(face: Dictionary): return face.name),
		"deck_card_faces": deck_faces,
		"opponent_card_faces": opponent_faces,
		"app_version": AppVersion.VERSION,
		"duration": int(round(Time.get_unix_time_from_system() - _battle_started_at)),
		"stats_p1": history_game.get_stats(1).duplicate(true),
		"stats_p2": history_game.get_stats(2).duplicate(true),
	})


func _update_pile_labels():
	if not draw_pile_btn or not discard_pile_btn:
		return
	draw_pile_btn.disabled = not bool(game.battle_config.get("draw_pile_visible",false))
	var field = _my_field()
	if field:
		var counts := _visible_pile_counts()
		if counts == _last_pile_counts:
			return
		_last_pile_counts = counts
		draw_pile_btn.call("set_count", counts.x)
		discard_pile_btn.call("set_count", counts.y)


func _on_draw_pile_clicked():
	if not bool(game.battle_config.get("draw_pile_visible",false)):
		UIMotion.unavailable_feedback.reject(draw_pile_btn)
		return
	var field = _my_field()
	if not field: return
	var shown: Array = game.shared_deck.duplicate()
	if not bool(game.battle_config.get("draw_pile_ordered",false)):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for index in range(shown.size()-1,0,-1):
			var other := rng.randi_range(0,index)
			var swap = shown[index]
			shown[index] = shown[other]
			shown[other] = swap
	_show_pile_viewer(shown, Locale.t("battle.draw_pile_title", [game.shared_deck.size()]))


func _on_discard_pile_clicked():
	var field = _my_field()
	if not field: return
	_show_pile_viewer(game.shared_discard, Locale.t("battle.discard_pile_title", [game.shared_discard.size()]))


func _show_pile_viewer(cards: Array, title_text: String):
	preload("res://CardCollectionDialog.gd").show_cards(self, cards, title_text)



# Capacity is now enforced at the instant every card enters a hand. Keep this
# as a defensive migration guard for old/local snapshots that may already
# contain an oversized hand; never ask the player to repair engine state.
func _check_charm_overflow() -> void:
	if PlayerData.is_online_battle() and not NetworkManager.is_authority():
		return
	for player in [1, 2]:
		var hand := _hand_for_player(player)
		while hand.size() > SkillEngine.MAX_HAND_SIZE:
			var overflow: CardData = hand.pop_back()
			game.move_card_to_shared_discard(overflow)
			EventBus.hand_entry_resolved.emit(overflow, player, "discard", "hand", {
				"source_instance_id": overflow.instance_id,
			})

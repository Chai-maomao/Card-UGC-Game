extends "res://BattleMainPresentation.gd"

const MAX_PROCESSED_COMMANDS := 256
var _processed_command_ids: Dictionary = {}

# ============================================
# Network
# ============================================

func is_my_turn() -> bool:
	if match_paused:
		return false
	if NetworkManager.is_online and not NetworkManager.is_authority() and NetworkManager.pending_game_command_count() > 0:
		return false
	if not NetworkManager.is_online:
		if PlayerData.battle_mode == "practice":
			return game.current_player == 1 and not practice_ai_running
		return true
	return game.current_player == my_player


func _init_network():
	if not NetworkManager.is_online:
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
	NetworkManager.game_command_status.connect(_on_game_command_status)


func _on_game_command_status(_command_id: String, _kind: String, status: String, _latency_ms: int) -> void:
	_network_command_phase = status
	if status in ["rejected", "stale_revision", "resynced", "timeout"]:
		_show_toast("tip.command_resynced")
	update_entire_screen()


func _pause_for_reconnect() -> void:
	if game != null:
		NetworkManager.save_match_snapshot(game.export_initial_state())
	match_paused = true
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	cancel_attack()
	remote_arrow_source = -1
	remote_arrow_target = -1
	if end_turn_button:
		end_turn_button.disabled = true
	update_entire_screen()


func _on_opponent_disconnected(_player: int) -> void:
	if battle_finished:
		return
	if NetworkManager.has_resumable_match_session():
		_pause_for_reconnect()
		return
	# A transport without a persisted match identity cannot be recovered safely.
	battle_finished = true
	practice_ai_running = false
	cancel_attack()
	remote_arrow_source = -1
	remote_arrow_target = -1
	if attack_arrow:
		attack_arrow.visible = false
	_show_combat_broadcast(Locale.t("battle.opponent_disconnected"))
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


func _on_reconnect_failed(_reason: String) -> void:
	UIMotion.change_scene.call_deferred("res://MainMenu.tscn")


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
	if not NetworkManager.is_online or my_player not in [1, 2] or _resume_nonce.is_empty():
		return
	_resume_request_count += 1
	_resume_next_request_at = _resume_now() + RESUME_REQUEST_INTERVAL
	NetworkManager.rpc_request_resume_state.rpc(my_player, game.state_revision, _resume_nonce)


func _request_resume_state() -> void:
	if not NetworkManager.is_online or my_player not in [1, 2]:
		return
	match_paused = true
	_ensure_resume_sync()
	_send_resume_request()
	update_entire_screen()


func _on_rpc_resume_state_requested(requesting_player: int, known_revision: int, nonce: String) -> void:
	if not NetworkManager.is_online or requesting_player == my_player:
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
	NetworkManager.rpc_resume_state.rpc(game.export_initial_state(), my_player, requesting_player, nonce)


func _on_rpc_resume_state_received(state: Dictionary, source_player: int, target_player: int, nonce: String) -> void:
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
	if player != _resume_waiting_for_player or revision != _resume_expected_revision or nonce != _resume_waiting_nonce:
		return
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	_resume_waiting_nonce = ""
	_finish_resume()
	NetworkManager.rpc_resume_complete.rpc(revision, my_player, nonce)


func _on_rpc_resume_complete(revision: int, nonce: String) -> void:
	if revision != game.state_revision or nonce != _resume_nonce:
		return
	_finish_resume()


func _finish_resume() -> void:
	match_paused = false
	_local_slot_rejoined = false
	NetworkManager.just_reconnected = false
	_reset_resume_sync()
	if end_turn_button:
		end_turn_button.disabled = not game.is_player_turn or not is_my_turn()
	update_entire_screen()


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
	if NetworkManager.is_online:
		call_deferred("_request_resume_state")
	else:
		NetworkManager.begin_saved_match_reconnect()


func _sync_targeting_state():
	if not NetworkManager.is_online:
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
		NetworkManager.rpc_targeting_arrow.rpc(source, last_hovered_target, game.current_player)
	else:
		NetworkManager.rpc_targeting_arrow.rpc(-1, -1, game.current_player)


func _on_rpc_targeting_arrow(source_slot: int, target_slot: int, player: int):
	if player == my_player: return
	remote_arrow_source = source_slot
	remote_arrow_target = target_slot


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
	if NetworkManager.is_online:
		NetworkManager.rpc_splash.rpc(player, slot_index)


func _on_rpc_initial_state(state: Dictionary):
	if NetworkManager.is_authority():
		return
	NetworkManager.reconcile_pending_game_commands(int(state.get("state_revision", -1)), true)
	_apply_authority_state(state, "initial")


func _on_rpc_initial_state_requested(_peer_id: int):
	if not NetworkManager.is_authority():
		return
	_broadcast_authority_state("initial request")
	NetworkManager.rpc_initial_state.rpc(game.export_initial_state())


func _on_rpc_authority_state(state: Dictionary):
	if NetworkManager.is_authority():
		return
	var incoming_revision := int(state.get("state_revision", 0))
	if incoming_revision < game.state_revision:
		return
	NetworkManager.reconcile_pending_game_commands(incoming_revision)
	_apply_authority_state(state, "remote authority")


func _send_current_state_for_command(command_id: String, status: String) -> void:
	NetworkManager.set_next_authority_ack(command_id, status)
	NetworkManager.broadcast_authority_state(game.export_initial_state())


func _remember_processed_command(command_id: String) -> void:
	_processed_command_ids[command_id] = true
	if _processed_command_ids.size() > MAX_PROCESSED_COMMANDS:
		_processed_command_ids.erase(_processed_command_ids.keys()[0])


func _on_rpc_game_intent(kind: String, payload: Dictionary, player: int, command_id: String, expected_revision: int) -> void:
	if not NetworkManager.is_authority():
		return
	if _processed_command_ids.has(command_id):
		_send_current_state_for_command(command_id, "duplicate")
		return
	if expected_revision != game.state_revision:
		_send_current_state_for_command(command_id, "stale_revision")
		return
	_remember_processed_command(command_id)
	NetworkManager.set_next_authority_ack(command_id, "applied")
	var old_revision: int = int(game.state_revision)
	match kind:
		"summon":
			_host_apply_summon(int(payload.get("hand_index", -1)), int(payload.get("slot_index", -1)), player)
		"summon_skill":
			_host_apply_summon_skill(int(payload.get("slot_index", -1)), int(payload.get("skill_index", -1)), int(payload.get("target_slot", -1)), player)
		"attack":
			_host_apply_attack(int(payload.get("source_slot", -1)), int(payload.get("target_slot", -1)), player)
		"activate_skill":
			var slot_index := int(payload.get("slot_index", -1))
			var skill_index := int(payload.get("skill_index", -1))
			var target_slot := int(payload.get("target_slot", -1))
			if _is_parasite_intent_source(slot_index):
				_host_apply_parasite(_parasite_hand_index_from_intent(slot_index), _parasite_target_player_from_intent(slot_index), target_slot, player)
			elif _is_spell_intent_source(slot_index):
				_host_apply_cast(_spell_hand_index_from_intent(slot_index), skill_index, target_slot, player)
			else:
				_host_apply_skill(slot_index, skill_index, target_slot, player)
		"end_turn":
			await _host_apply_end_turn(player)
		"discard":
			_host_apply_discard(str(payload.get("location", "")), int(payload.get("index", -1)), player)
		"move":
			_host_apply_move(int(payload.get("source_slot", -1)), int(payload.get("target_slot", -1)), player)
	if game.state_revision == old_revision:
		_send_current_state_for_command(command_id, "rejected")


func _host_apply_summon(hand_index: int, slot_index: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var hand = _hand_for_player(player)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var saved = game.current_player
	game.current_player = player
	var card: CardData = hand[hand_index]
	if not game.summon_card(card, slot_index):
		game.current_player = saved
		return
	game.current_player = saved
	# on_summon skills are activated manually by the summoning player this turn;
	# nothing auto-fires here. The summoned_this_turn flag travels in the state.
	_refresh_hand_ui()
	update_entire_screen()
	_play_summon_feedback(_slot_ui_for_player(player, slot_index))
	_record_feedback_event("summon", player, slot_index)
	_commit_authority_state("summon")


func _host_apply_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var source_card: CardData = _field_for_player(player).slots[slot_index]
	var target_card: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot] if target_slot >= 0 else null
	var skill: Dictionary = source_card.skills[skill_index] if source_card != null and skill_index < source_card.skills.size() else {}
	_begin_action_broadcast("summon_skill", player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_summon_skills(slot_index, target_slot, skill_index)
	game.current_player = saved
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, slot_index)
	_record_feedback_event("skill", player, slot_index)
	_authority_splash(player, slot_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	_commit_authority_state("summon skill")


func _host_apply_attack(source_slot: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var attacker: CardData = _field_for_player(player).slots[source_slot]
	var victim: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot]
	var base_damage: int = attacker.atk if attacker != null else 0
	var effective_damage: int = attacker.effective_atk() if attacker != null else 0
	_begin_action_broadcast("attack", player, attacker.card_name if attacker != null else Locale.t("battle.log.unit"), victim.card_name if victim != null else Locale.t("battle.log.unit"), {"base_damage": base_damage, "effective_damage": effective_damage, "target_player": _opponent_of_player(player), "target_slot": target_slot})
	var saved = game.current_player
	game.current_player = player
	var result: Dictionary = game.execute_attack(source_slot, target_slot)
	game.current_player = saved
	if victim != null and not victim.is_alive():
		_action_broadcast["kill_mana"] = true
	_finish_action_broadcast()
	if not result.is_empty():
		_play_attack_feedback(player, source_slot, target_slot)
		_record_feedback_event("attack", player, source_slot, {"target_slot": target_slot})
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	_commit_authority_state("attack")


func _host_apply_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var source_card: CardData = _field_for_player(player).slots[slot_index]
	var target_card: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot] if target_slot >= 0 else null
	var skill: Dictionary = source_card.skills[skill_index] if source_card != null and skill_index < source_card.skills.size() else {}
	_begin_action_broadcast("skill", player, source_card.card_name if source_card != null else Locale.t("battle.log.unit"), target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", Locale.t("battle.log.skill_word"))})
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_activate_skills(slot_index, target_slot, skill_index)
	game.current_player = saved
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, slot_index)
	_record_feedback_event("skill", player, slot_index)
	_authority_splash(player, slot_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	_commit_authority_state("activate skill")


func _host_apply_parasite(hand_index: int, target_player: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var hand := _hand_for_player(player)
	var parasite_card: CardData = hand[hand_index] if hand_index >= 0 and hand_index < hand.size() else null
	var target_field := _field_for_player(target_player)
	var target_card: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	_begin_action_broadcast("parasite", player, parasite_card.card_name if parasite_card != null else Locale.t("battle.log.parasite"), target_card.card_name if target_card != null else "")
	var saved = game.current_player
	game.current_player = player
	var attach_ok: bool = game.attach_parasite(hand_index, target_player, target_slot)
	game.current_player = saved
	if not attach_ok:
		_action_broadcast.clear()
		_action_hp_events.clear()
		return
	_finish_action_broadcast()
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("attach parasite")


func _host_apply_cast(hand_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var hand := _hand_for_player(player)
	var spell_card: CardData = hand[hand_index] if hand_index >= 0 and hand_index < hand.size() else null
	_begin_action_broadcast("cast", player, spell_card.card_name if spell_card != null else Locale.t("battle.log.spell_word"), "")
	var saved = game.current_player
	game.current_player = player
	var cast_ok: bool = game.cast_spell(hand_index, skill_index, target_slot)
	game.current_player = saved
	if not cast_ok:
		_action_broadcast.clear()
		_action_hp_events.clear()
		return
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


func _host_apply_discard(location: String, index: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
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
	var saved = game.current_player
	game.current_player = player
	game.discard_card(card)
	game.current_player = saved
	_refresh_hand_ui()
	update_entire_screen()
	_show_combat_broadcast(Locale.t("tip.discard_mana"))
	_play_discard_feedback()
	_record_feedback_event("broadcast_text", player, -1, {"text_key": "tip.discard_mana"})
	_record_feedback_event("discard", player, -1)
	_commit_authority_state("discard")


func _host_apply_move(source_slot: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var field = _field_for_player(player)
	if source_slot < 0 or source_slot >= field.slots.size() or target_slot < 0 or target_slot >= field.slots.size():
		return
	var displaced = field.slots[target_slot]
	field.slots[target_slot] = field.slots[source_slot]
	field.slots[source_slot] = displaced
	_play_move_feedback(player, source_slot, target_slot)
	update_entire_screen()
	_record_feedback_event("move", player, source_slot, {"target_slot": target_slot})
	_commit_authority_state("move")


func _host_apply_end_turn(player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	remote_arrow_source = -1
	var result = game.end_player_turn()
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	if _check_and_show_game_over():
		_commit_authority_state("game over")
		return
	game.start_new_turn()
	_show_turn_banner()
	_record_feedback_event("turn", game.current_player, -1)
	_refresh_hand_ui()
	end_turn_button.disabled = false
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
	turn_wait_hint.anchor_left = 0.5
	turn_wait_hint.anchor_right = 0.5
	turn_wait_hint.anchor_top = 1.0
	turn_wait_hint.anchor_bottom = 1.0
	UITheme.apply_panel(turn_wait_hint, "gold")
	var lbl = Label.new()
	lbl.name = "Label"
	lbl.text = Locale.t("battle.waiting")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(lbl, true)
	turn_wait_hint.add_child(lbl)
	reconnect_leave_button = Button.new()
	reconnect_leave_button.name = "LeaveButton"
	reconnect_leave_button.text = Locale.t("battle.abandon_match")
	reconnect_leave_button.anchor_left = 1.0
	reconnect_leave_button.anchor_right = 1.0
	reconnect_leave_button.mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.apply_button(reconnect_leave_button, "secondary")
	reconnect_leave_button.pressed.connect(_on_abandon_reconnect_pressed)
	reconnect_leave_button.visible = false
	turn_wait_hint.add_child(reconnect_leave_button)
	turn_wait_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	$CanvasLayer.add_child(turn_wait_hint)
	_update_wait_hint_layout()


func _update_wait_hint_layout() -> void:
	if turn_wait_hint == null:
		return
	var s := _ui_scale()
	var hint_size := Vector2(430 if match_paused else 260, 36) * s
	turn_wait_hint.offset_left = -hint_size.x / 2.0
	turn_wait_hint.offset_right = hint_size.x / 2.0
	turn_wait_hint.offset_top = -hint_size.y - 10.0 * s
	turn_wait_hint.offset_bottom = -10.0 * s
	var lbl := turn_wait_hint.get_node_or_null("Label")
	if lbl:
		lbl.add_theme_font_size_override("font_size", max(10, int(15 * s)))
		lbl.offset_right = -116.0 * s if match_paused else 0.0
	if reconnect_leave_button:
		reconnect_leave_button.visible = match_paused
		reconnect_leave_button.offset_left = -112.0 * s
		reconnect_leave_button.offset_right = -4.0 * s
		reconnect_leave_button.offset_top = 4.0 * s
		reconnect_leave_button.offset_bottom = -4.0 * s
		reconnect_leave_button.add_theme_font_size_override("font_size", max(9, int(12 * s)))


func _toggle_turn_cover():
	var overlay = $CanvasLayer.get_node_or_null("TurnOverlay")
	if not turn_cover and not turn_wait_hint and not overlay:
		return
	var command_pending: bool = NetworkManager.is_online and not NetworkManager.is_authority() and NetworkManager.pending_game_command_count() > 0
	var waiting_for_turn: bool = NetworkManager.is_online and (not bool(game.is_player_turn) or int(game.current_player) != my_player)
	var show_cover: bool = match_paused or waiting_for_turn or (PlayerData.battle_mode == "practice" and int(game.current_player) == 2)
	var show_hint: bool = show_cover or command_pending
	if turn_cover:
		turn_cover.visible = show_cover
		$CanvasLayer.move_child(turn_cover, max(0, $CanvasLayer.get_child_count() - 2))
		if turn_cover.get_child_count() > 0 and turn_cover.get_child(0) is Label:
			turn_cover.get_child(0).text = Locale.t("battle.reconnecting") if match_paused else Locale.t("battle.waiting")
	if turn_wait_hint:
		_update_wait_hint_layout()
		var label := turn_wait_hint.get_node_or_null("Label")
		if label:
			if match_paused:
				label.text = Locale.t("battle.reconnecting_progress", [_reconnect_attempt, _reconnect_elapsed_seconds])
			else:
				label.text = Locale.t("battle.waiting")
		turn_wait_hint.visible = show_hint
		$CanvasLayer.move_child(turn_wait_hint, $CanvasLayer.get_child_count() - 1)
		if show_hint:
			var fade := create_tween()
			turn_wait_hint.modulate.a = 0.0
			fade.tween_property(turn_wait_hint, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if overlay:
		overlay.visible = show_cover


func _on_abandon_reconnect_pressed() -> void:
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	UIMotion.change_scene("res://MainMenu.tscn")


# ============================================
# Draw/Discard pile UI
# ============================================

func _build_pile_buttons():
	draw_pile_btn = Button.new()
	draw_pile_btn.text = Locale.t("battle.draw_pile")
	draw_pile_btn.pressed.connect(_on_draw_pile_clicked)
	UITheme.apply_button(draw_pile_btn, "secondary")
	draw_pile_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pile_column.add_child(draw_pile_btn)

	discard_pile_btn = Button.new()
	discard_pile_btn.text = Locale.t("battle.discard_pile")
	discard_pile_btn.pressed.connect(_on_discard_pile_clicked)
	UITheme.apply_button(discard_pile_btn, "secondary")
	discard_pile_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pile_column.add_child(discard_pile_btn)

	help_btn = Button.new()
	help_btn.text = Locale.t("help.button")
	help_btn.pressed.connect(_on_help_clicked)
	UITheme.apply_button(help_btn, "secondary")
	$CanvasLayer.add_child(help_btn)

	_update_pile_labels()
	_apply_responsive_layout()


func _on_debug_state_clicked():
	_print_authority_state("button")
	if NetworkManager.is_online and NetworkManager.is_authority():
		NetworkManager.broadcast_authority_state(game.export_initial_state())


func _on_help_clicked():
	_show_help_popup()


# Static rules manual — blur overlay + scrollable mechanics text.
func _show_help_popup():
	var s := _ui_scale()
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
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
	title.text = Locale.t("help.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, max(16, int(24 * s)))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var body := Label.new()
	body.text = Locale.t("help.body", [SkillEngine.MAX_HAND_SIZE])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	body.add_theme_font_size_override("font_size", max(12, int(17 * s)))
	UITheme.apply_label(body)
	scroll.add_child(body)

	var close_btn := Button.new()
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
	var mode := "online" if NetworkManager.is_online else PlayerData.battle_mode
	var deck_names: Array[String] = []
	for card in PlayerData.battle_deck:
		if card is CardData:
			deck_names.append(card.card_name)
	var opponent_names: Array[String] = []
	for card in PlayerData.opponent_battle_deck:
		if card is CardData:
			opponent_names.append(card.card_name)
	var current_deck := PlayerData.get_current_deck()
	var local_is_p2 := NetworkManager.is_online and my_player == 2
	PlayerData.add_match_history({
		"mode": mode,
		"outcome": outcome,
		"result": result,
		"turns": int(game.turn_number),
		"player_hp": int(game.player2_field.player_hp if local_is_p2 else game.player_field.player_hp),
		"opponent_hp": int(game.player_field.player_hp if local_is_p2 else game.player2_field.player_hp),
		"local_player": my_player if NetworkManager.is_online else 1,
		"deck_name": str(current_deck.get("name", "")),
		"deck_cards": deck_names,
		"opponent_cards": opponent_names,
		"app_version": AppVersion.VERSION,
		"duration": int(round(Time.get_unix_time_from_system() - _battle_started_at)),
		"stats_p1": game.get_stats(1).duplicate(true),
		"stats_p2": game.get_stats(2).duplicate(true),
	})


func _update_pile_labels():
	if not draw_pile_btn or not discard_pile_btn:
		return
	var field = _my_field()
	if field:
		var counts := Vector2i(game.shared_deck.size(), game.shared_discard.size())
		if counts == _last_pile_counts:
			return
		_last_pile_counts = counts
		draw_pile_btn.text = Locale.t("battle.deck", [counts.x])
		discard_pile_btn.text = Locale.t("battle.discard", [counts.y])


func _on_draw_pile_clicked():
	var field = _my_field()
	if not field: return
	_show_pile_viewer(game.shared_deck, Locale.t("battle.draw_pile_title", [game.shared_deck.size()]))


func _on_discard_pile_clicked():
	var field = _my_field()
	if not field: return
	_show_pile_viewer(game.shared_discard, Locale.t("battle.discard_pile_title", [game.shared_discard.size()]))


func _show_pile_viewer(cards: Array, title_text: String):
	if cards.is_empty():
		return

	var s := _ui_scale()
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.clip_contents = true
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	popup_layer.add_child(panel)
	UITheme.animate_popup_enter(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", int(10 * s))
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, max(15, int(20 * s)))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(8 * s))
	grid.add_theme_constant_override("v_separation", int(8 * s))
	scroll.add_child(grid)

	for c in cards:
		var cui := card_ui_scene.instantiate()
		grid.add_child(cui)
		cui.set_card(c)
		if cui.has_method("set_skill_preview_visible"):
			cui.call("set_skill_preview_visible", true)
		else:
			cui.set_actions_visible(false)
		if cui.has_method("apply_ui_scale"):
			cui.call("apply_ui_scale", s)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	close_btn.custom_minimum_size = Vector2(100, 40) * s
	close_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(popup_layer.queue_free)
	vbox.add_child(close_btn)



# ============================================
# Charm overflow
# ============================================

func _check_charm_overflow():
	if _charm_popup_active:
		return
	var hand = _my_hand()
	if hand.size() <= SkillEngine.MAX_HAND_SIZE:
		return
	var charmed_cards = hand.filter(func(c): return c != null and c.is_charmed())
	if charmed_cards.is_empty():
		return
	var non_charmed = hand.size() - charmed_cards.size()
	var max_picks = max(0, SkillEngine.MAX_HAND_SIZE - non_charmed)
	if max_picks <= 0:
		for c in charmed_cards:
			hand.erase(c)
		_refresh_hand_ui()
		return
	if max_picks >= charmed_cards.size():
		while hand.size() > SkillEngine.MAX_HAND_SIZE:
			hand.erase(charmed_cards.pop_back())
		_refresh_hand_ui()
		return
	_show_charm_selection(charmed_cards, max_picks)


func _show_charm_selection(charmed_cards: Array, max_picks: int):
	_charm_popup_active = true
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	popup_layer.add_child(bg)

	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.15
	panel.anchor_bottom = 0.85
	popup_layer.add_child(panel)
	UITheme.animate_popup_enter(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	panel.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("battle.choose_keep")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 22)
	vbox.add_child(title)

	var info := Label.new()
	info.text = Locale.t("battle.hand_remaining", [max_picks, max_picks])
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(info, true)
	vbox.add_child(info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var card_hbox := HBoxContainer.new()
	card_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(card_hbox)

	var selected := {}
	for c in charmed_cards:
		selected[c] = false

	var card_uis := []
	for c in charmed_cards:
		var cui := card_ui_scene.instantiate()
		card_hbox.add_child(cui)
		cui.set_card(c)
		cui.modulate = Color(0.4, 0.4, 0.4)
		card_uis.append(cui)

		var click_handler = func(event: InputEvent, card_data: CardData, ui: Control):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				selected[card_data] = not selected[card_data]
				if selected[card_data]:
					ui.modulate = Color.WHITE
				else:
					ui.modulate = Color(0.4, 0.4, 0.4)
				var sel_count := 0
				for v in selected.values():
					if v: sel_count += 1
				if sel_count > max_picks:
					selected[card_data] = false
					ui.modulate = Color(0.4, 0.4, 0.4)
		cui.gui_input.connect(click_handler.bind(c, cui))

	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.confirm")
	confirm_btn.custom_minimum_size = Vector2(120, 40)
	vbox.add_child(confirm_btn)

	confirm_btn.pressed.connect(func():
		var hand = _my_hand()
		for c in charmed_cards:
			if not selected.get(c, false):
				hand.erase(c)
		_charm_popup_active = false
		popup_layer.queue_free()
		_refresh_hand_ui()
	)

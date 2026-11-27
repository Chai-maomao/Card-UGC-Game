extends Node

signal changed
signal failed(message_key: String)
signal battle_started
signal view_changed
signal action_rejected
signal returned_to_lobby

const State = preload("res://TeamBattleState.gd")
const ActionClock = preload("res://BattleActionClock.gd")
const Wire = preload("res://BattleSnapshotWire.gd")
const Matchmaking = preload("res://MatchmakingQueue.gd")
const Rating = preload("res://RankedRating.gd")
const PackRating = preload("res://MatchPackRating.gd")
const PORT := 8971
const PROTOCOL := 2
const JOIN_TIMEOUT := 8.0
const RECONNECT_TIMEOUT := 22.0
const RECONNECT_RETRY_MS := 1200
const MIN_PLAYERS := 3
const MAX_PLAYERS := 5
const AIM_COMMAND := "targeting_aim"
const AIM_LIFETIME_MS := 1250
const TEAM_REVEAL_MS := 2200
const MATCHMADE_REVEAL_TIMEOUT_MS := 8000
const REVEAL_CAPABLE := "team_reveal_capable"
const REVEAL_CONFIRMED := "team_reveal_confirmed"

var seat_count := MIN_PLAYERS
var use_dedicated_lobby := false
var lobby_room_code := ""
var local_seat := 0
var occupied: Array = []
var ready_seats: Array = []
var view: Dictionary = {}
var started := false
var interrupted := false
var waiting_for_reply := false
var absent_seats: Array = []
var reconnecting := false
var rematch_requested := false
var matchmaking_mode := ""
var contribution_name := ""
var local_art: Dictionary
var battle_rules := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
var action_clock := ActionClock.new()
var targeting_aim: Dictionary = {}
var _aim_received_at := 0
var _aim_relay_at := 0
var _team_reveal_until := 0
var _reveal_capable_seats: Dictionary = {}
var _reveal_pending_seats: Dictionary = {}
var _local_reveal_confirmed := false
var _guest_clock_timing: Dictionary = {}
var _api := SceneMultiplayer.new()
var _peer: ENetMultiplayerPeer
var _listening := false
var _seats: Dictionary = {}
var _seat_tokens: Dictionary = {}
var _missing_deadlines: Dictionary = {}
var _pending_guests: Dictionary = {}
var _returned: Dictionary = {}
var _decks: Dictionary = {}
var _state: State
var _token := ""
var _address := ""
var _port := PORT
var _recover_by := 0
var _next_attempt := 0
var _join_until := 0
var _access_code := ""
var _invite_code := ""
var _owner_code := ""
var _idle_by := 0
var _duel_invites: Dictionary = {}
var _duel_result_path := ""
var _duel_match_id := ""
var _duel_settlement_path := ""
var _duel_settlement: Array = []
var _duel_ratings: Array
var _duel_pool: Array
var _duel_multipliers: Array


func _ready() -> void:
	_api.server_relay = false
	get_tree().set_multiplayer(_api, get_path())
	_api.connected_to_server.connect(_on_connected)
	_api.connection_failed.connect(_on_connection_failed)
	_api.server_disconnected.connect(_on_host_disconnected)


func is_open() -> bool:
	return _peer != null


func is_host() -> bool:
	return is_open() and local_seat == 1


func _is_authority() -> bool:
	return _listening and is_open()


func _connected_guests() -> Array[int]:
	var connected: Array[int] = []
	for id in _api.get_peers():
		var guest := _peer.get_peer(id)
		if _seats.has(id) and guest != null and guest.get_state() == ENetPacketPeer.STATE_CONNECTED:
			connected.append(id)
	return connected


func _winner() -> int:
	return _state.winner if _is_authority() and _state != null else int(view.get("winner", 0))


func join_address() -> String:
	if _port == PORT:
		return _address
	var host := "[%s]" % _address if ":" in _address else _address
	return "%s:%d" % [host, _port]


func host(count: int = MIN_PLAYERS, port: int = PORT) -> Error:
	var error := _listen(count, port, "")
	if error == OK:
		NetworkManager._start_lan_discovery_responder(port)
	return error


func host_dedicated(count: int, port: int, access_code: String, owner_code: String = "") -> Error:
	if access_code.length() < 8 or access_code.length() > 32 or not access_code.is_valid_hex_number(false):
		return ERR_INVALID_PARAMETER
	if not owner_code.is_empty() and (owner_code.length() != 32 or not owner_code.is_valid_hex_number(false)):
		return ERR_INVALID_PARAMETER
	var error := _listen(count, port, access_code)
	if error == OK:
		_owner_code = owner_code
	return error


func host_matchmade(port: int, mode: String, invites: Dictionary, result_path: String, ratings: Array) -> Error:
	if not Matchmaking.valid_mode(mode) or invites.size() != 2 or result_path.is_empty():
		return ERR_INVALID_PARAMETER
	if mode == Matchmaking.RANKED and ratings.size() != 2:
		return ERR_INVALID_PARAMETER
	for invite: String in invites:
		if invite.length() != 32 or not invite.is_valid_hex_number(false):
			return ERR_INVALID_PARAMETER
	if not invites.values().has(1) or not invites.values().has(2):
		return ERR_INVALID_PARAMETER
	var error := _listen(2, port, "matchmade", 2)
	if error == OK:
		matchmaking_mode = mode
		_duel_invites = invites.duplicate()
		_duel_result_path = result_path
		_duel_match_id = result_path.get_file().get_basename()
		_duel_settlement_path = result_path.get_basename() + ".settled"
		_duel_ratings = ratings.duplicate()
		_idle_by = Time.get_ticks_msec() + 45000
		var ready_file := FileAccess.open(result_path.get_basename() + ".ready", FileAccess.WRITE)
		if ready_file == null:
			close()
			return ERR_FILE_CANT_WRITE
	return error


func _listen(count: int, port: int, access_code: String, minimum: int = MIN_PLAYERS) -> Error:
	if count < minimum or count > MAX_PLAYERS or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	close()
	var transport := ENetMultiplayerPeer.new()
	var local_player := int(access_code.is_empty())
	var error := transport.create_server(port, count - local_player)
	if error != OK:
		return error
	_listening = true
	seat_count = count
	_access_code = access_code
	local_seat = local_player
	if local_player == 1:
		_seats[1] = 1
	transport.peer_connected.connect(_on_guest_connected)
	transport.peer_disconnected.connect(_on_guest_disconnected)
	_install(transport)
	_publish_roster()
	return OK


func join(address: String, port: int = PORT, invite_code: String = "", mode: String = "") -> Error:
	if not NetworkManager.is_valid_address(address) or port < 1 or port > 65535 or invite_code.length() > 32:
		return ERR_INVALID_PARAMETER
	close()
	var transport := ENetMultiplayerPeer.new()
	var error := transport.create_client(address, port)
	if error != OK:
		return error
	_address = address
	_port = port
	_invite_code = invite_code
	matchmaking_mode = mode
	_install(transport)
	_join_until = Time.get_ticks_msec() + int(JOIN_TIMEOUT * 1000)
	changed.emit()
	return OK


func _install(transport: ENetMultiplayerPeer) -> void:
	_peer = transport
	_api.multiplayer_peer = transport


func close() -> void:
	if _listening and local_seat == 1:
		NetworkManager._stop_lan_discovery_responder()
	_listening = false
	_disconnect_transport()
	local_seat = 0
	seat_count = MIN_PLAYERS
	occupied.clear()
	ready_seats.clear()
	_seats.clear()
	_seat_tokens.clear()
	_missing_deadlines.clear()
	_pending_guests.clear()
	_returned.clear()
	absent_seats.clear()
	_decks.clear()
	view = {}
	targeting_aim.clear()
	_aim_relay_at = 0
	_team_reveal_until = 0
	_reveal_capable_seats.clear()
	_reveal_pending_seats.clear()
	_local_reveal_confirmed = false
	battle_rules = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	action_clock = ActionClock.new()
	_guest_clock_timing.clear()
	local_art = {}
	_state = null
	started = false
	interrupted = false
	waiting_for_reply = false
	reconnecting = false
	rematch_requested = false
	matchmaking_mode = ""
	_duel_invites.clear()
	_duel_result_path = ""
	_duel_match_id = ""
	_duel_settlement_path = ""
	_duel_settlement.clear()
	contribution_name = ""
	_duel_ratings.clear()
	_duel_pool.clear()
	_duel_multipliers.clear()
	_token = ""
	_address = ""
	_join_until = 0
	_access_code = ""
	_invite_code = ""
	_owner_code = ""
	_idle_by = 0
	lobby_room_code = ""


func _disconnect_transport() -> void:
	var transport := _peer
	_peer = null
	_api.multiplayer_peer = null
	if transport != null:
		transport.close()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _is_authority() and not matchmaking_mode.is_empty():
		if not started and FileAccess.file_exists(_duel_result_path.get_basename() + ".cancel"):
			get_tree().quit()
			return
		if _winner() != 0:
			_save_duel_result()
			if matchmaking_mode == Matchmaking.RANKED and _duel_settlement.is_empty() and FileAccess.file_exists(_duel_settlement_path):
				var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(_duel_settlement_path))
				if receipt is Array and receipt.size() == 2 and receipt[0] is Dictionary and receipt[1] is Dictionary:
					_duel_settlement = receipt
					for id in _connected_guests():
						_receive_view.rpc_id(id, Wire.encode(_clocked_player_view(_seats[id])), true)
		if _idle_by > 0 and now >= _idle_by:
			get_tree().quit()
			return
		if _winner() != 0:
			return
	if _is_authority() and not _owner_code.is_empty():
		if _seats.is_empty() or (not started and not _seats.values().has(1)):
			if _idle_by == 0:
				_idle_by = now + 45000
			elif now >= _idle_by:
				get_tree().quit()
		else:
			_idle_by = 0
	if _join_until > 0 and now >= _join_until:
		_join_until = 0
		_on_connection_failed()
	if _is_authority():
		for guest: int in _pending_guests.keys():
			if now >= int(_pending_guests[guest]):
				_pending_guests.erase(guest)
				_peer.disconnect_peer(guest)
	if not started or interrupted:
		return
	if _is_authority():
		for seat: int in _missing_deadlines:
			if now >= int(_missing_deadlines[seat]):
				_end_for_disconnect(seat)
				return
		if _team_reveal_until > 0 and now >= _team_reveal_until:
			_team_reveal_until = 0
			if not matchmaking_mode.is_empty():
				_reveal_pending_seats.clear()
			_publish_action_result(0, true)
		if _tick_authority_clock(now):
			_end_timed_out_turn()
	elif reconnecting:
		if now >= _recover_by:
			_interrupt()
		elif now >= _next_attempt:
			_attempt_reconnect(now)
	elif not _guest_clock_timing.is_empty():
		_tick_guest_clock(now, not absent_seats.is_empty())


func _tick_authority_clock(now: int) -> bool:
	if _state == null or _state.winner != 0:
		return false
	return action_clock.tick(battle_rules, Vector2i(_state.turn_number, _state.active_seat),
		_state.effective_actions_this_turn, not absent_seats.is_empty() or team_reveal_pending(), now)


func _tick_guest_clock(now: int, paused: bool) -> void:
	var timing := _guest_clock_timing
	action_clock.tick(timing.config, Vector2i(int(view.round), int(view.active)), int(timing.actions),
		paused or team_reveal_pending(), now)


func _set_player_view(snapshot: Dictionary) -> void:
	view = snapshot
	_guest_clock_timing = view.get("action_clock", {})
	view.erase("action_clock")
	_team_reveal_until = Time.get_ticks_msec() + int(_guest_clock_timing.get("team_reveal_ms", 0))
	if not _guest_clock_timing.is_empty():
		_tick_guest_clock(Time.get_ticks_msec(), true)
		action_clock.remaining_ms = clampi(int(_guest_clock_timing.remaining_ms), 0, action_clock.limit_ms)


func _clocked_player_view(seat: int) -> Dictionary:
	var snapshot := _state.player_view(seat)
	if not matchmaking_mode.is_empty():
		snapshot["match_pool"] = _duel_pool
	if matchmaking_mode == Matchmaking.RANKED:
		snapshot["ranked_match_id"] = _duel_match_id
		if not _duel_settlement.is_empty():
			snapshot["ranked_settlement"] = _duel_settlement[seat - 1]
	if matchmaking_mode == Matchmaking.RANKED and _winner() != 0 and _duel_result_path.is_empty():
		var ratings := Rating.rating_after(int(_duel_ratings[0]), int(_duel_ratings[1]), _winning_duel_seat(), _duel_multipliers)
		var previous := int(_duel_ratings[seat - 1])
		snapshot["ranked_rating"] = {"rating": ratings[seat - 1], "change": ratings[seat - 1] - previous,
			"multiplier": _duel_multipliers[seat - 1]}
	var timing := {}
	for key in ActionClock.KEYS:
		timing[key] = battle_rules.get(key, PlayerData.DEFAULT_BATTLE_CONFIG[key])
	snapshot["action_clock"] = {"config": timing, "targeting_aim": true,
		"remaining_ms": action_clock.remaining_ms, "actions": _state.effective_actions_this_turn,
		"team_reveal_ms": team_reveal_remaining_ms(), "team_confirm_pending": not _reveal_pending_seats.is_empty()}
	return snapshot


func team_reveal_remaining_ms() -> int:
	return maxi(0, _team_reveal_until - Time.get_ticks_msec())


func team_reveal_pending() -> bool:
	return team_reveal_remaining_ms() > 0 or (not _reveal_pending_seats.is_empty() if _is_authority()
		else bool(_guest_clock_timing.get("team_confirm_pending", false)))


func confirm_team_reveal() -> void:
	if not started or interrupted:
		return
	_local_reveal_confirmed = true
	if _is_authority():
		_confirm_reveal_seat(local_seat)
	elif not reconnecting and _guest_clock_timing.get("team_confirm_pending", false):
		rpc_id(1, "_play", int(view.revision), REVEAL_CONFIRMED, -1, 0, -1, -1)


func _confirm_reveal_seat(seat: int) -> void:
	if not _reveal_pending_seats.erase(seat):
		return
	if _reveal_pending_seats.is_empty():
		if not matchmaking_mode.is_empty():
			_team_reveal_until = 0
		_publish_action_result(0, true)


func _end_timed_out_turn() -> void:
	var snapshot := _state.player_view(_state.active_seat)
	while int(snapshot.chooser) != 0:
		if not _state.apply_card_choice(int(snapshot.chooser), _state.state_revision, []):
			return
		snapshot = _state.player_view(_state.active_seat)
	var opponents := _state.opponents_of(_state.active_seat)
	if not opponents.is_empty() and _state.apply_action(_state.active_seat, _state.state_revision, "end", -1, opponents[0], -1, -1):
		_publish_action_result(0, true)


func _attempt_reconnect(now: int) -> void:
	_disconnect_transport()
	var transport := ENetMultiplayerPeer.new()
	_next_attempt = now + RECONNECT_RETRY_MS
	if transport.create_client(_address, _port) == OK:
		_install(transport)


func _begin_reconnect() -> void:
	targeting_aim.clear()
	if reconnecting or interrupted:
		return
	reconnecting = true
	waiting_for_reply = false
	_recover_by = Time.get_ticks_msec() + int(RECONNECT_TIMEOUT * 1000)
	_next_attempt = Time.get_ticks_msec()
	view_changed.emit()


func _on_connected() -> void:
	if is_open():
		_peer.get_peer(1).set_timeout(8, 3000, 8000)
		_request_seat.rpc_id(1, PROTOCOL, AppVersion.PROTOCOL_VERSION, _token if reconnecting else "", _invite_code)


func _on_guest_connected(id: int) -> void:
	_peer.get_peer(id).set_timeout(8, 3000, 8000)
	_pending_guests[id] = Time.get_ticks_msec() + int(JOIN_TIMEOUT * 1000)


@rpc("any_peer", "call_remote", "reliable")
func _request_seat(version: int, battle_protocol: int, token: String, invite_code: String) -> void:
	if not _is_authority() or interrupted:
		return
	var sender := _api.get_remote_sender_id()
	if sender <= 1 or _seats.has(sender):
		return
	_pending_guests.erase(sender)
	if version != PROTOCOL or battle_protocol != AppVersion.PROTOCOL_VERSION:
		_reject_peer(sender, "team.incompatible")
		return
	if started:
		_resume_guest(sender, token)
		return
	if not matchmaking_mode.is_empty():
		var duel_seat := int(_duel_invites.get(invite_code, 0))
		if duel_seat == 0 or _seats.values().has(duel_seat):
			_reject_peer(sender, "team.bad_code")
			return
		_seats[sender] = duel_seat
		_seat_tokens[duel_seat] = Crypto.new().generate_random_bytes(16).hex_encode()
		_idle_by = Time.get_ticks_msec() + Matchmaking.PREPARATION_LIMIT_MS
		_assign_seat.rpc_id(sender, duel_seat, seat_count, _seat_tokens[duel_seat])
		_publish_roster()
		return
	var is_owner := not _owner_code.is_empty() and invite_code == _owner_code
	if _access_code != invite_code and not is_owner:
		_reject_peer(sender, "team.bad_code")
		return
	var first_seat := 2 if not _owner_code.is_empty() and not is_owner else local_seat + 1
	var last_seat := 1 if is_owner else seat_count
	for seat in range(first_seat, last_seat + 1):
		if not _seats.values().has(seat):
			_seats[sender] = seat
			_seat_tokens[seat] = Crypto.new().generate_random_bytes(16).hex_encode()
			_assign_seat.rpc_id(sender, seat, seat_count, _seat_tokens[seat])
			_publish_roster()
			return
	_reject_peer(sender)


func _reject_peer(sender: int, reason: String = "team.join_failed") -> void:
	_join_rejected.rpc_id(sender, reason)
	_peer.get_peer(sender).peer_disconnect_later()


func _resume_guest(sender: int, token: String) -> void:
	if token.length() == 32:
		for seat: int in _missing_deadlines:
			if _seat_tokens.get(seat) == token and Time.get_ticks_msec() < int(_missing_deadlines[seat]):
				_seats[sender] = seat
				_missing_deadlines.erase(seat)
				_peer.refuse_new_connections = _missing_deadlines.is_empty()
				_receive_resume.rpc_id(sender, Wire.encode(_clocked_player_view(seat)), _missing_deadlines.keys())
				_publish_link_state()
				return
	_reject_peer(sender)


@rpc("authority", "call_remote", "reliable")
func _join_rejected(reason: String) -> void:
	if is_open() and not started and (local_seat == 0 or not matchmaking_mode.is_empty()):
		_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _assign_seat(seat: int, count: int, token: String) -> void:
	var valid_count := count in range(MIN_PLAYERS, MAX_PLAYERS + 1) if matchmaking_mode.is_empty() else count == 2
	if is_open() and local_seat == 0 and token.length() == 32 and valid_count and seat in range(1, count + 1):
		seat_count = count
		local_seat = seat
		_token = token
		_join_until = 0


func _on_guest_disconnected(id: int) -> void:
	_pending_guests.erase(id)
	if _peer == null or not _seats.has(id):
		return
	var seat: int = _seats[id]
	_seats.erase(id)
	if started:
		if not interrupted and _winner() == 0:
			_missing_deadlines[seat] = Time.get_ticks_msec() + int(RECONNECT_TIMEOUT * 1000)
			_peer.refuse_new_connections = false
			_publish_link_state()
		elif _winner() > 0:
			_reveal_capable_seats.erase(seat)
			_seat_tokens.erase(seat)
			_returned.erase(seat)
			if matchmaking_mode.is_empty():
				_reopen_when_ready()
			elif _seats.is_empty() and _duel_result_path.is_empty():
				get_tree().quit()
		elif interrupted and local_seat == 0 and _seats.is_empty():
			_reset_dedicated_match()
	else:
		_decks.erase(seat)
		_reveal_capable_seats.erase(seat)
		_seat_tokens.erase(seat)
		if not matchmaking_mode.is_empty():
			_duel_invites.clear()
			_idle_by = Time.get_ticks_msec() + 1000
			for guest in _connected_guests():
				_reject_peer(guest, "matchmaking.opponent_left_room")
			return
		_publish_roster()


func _on_connection_failed() -> void:
	if is_open() and local_seat == 0:
		_fail("team.join_failed")


func _on_host_disconnected() -> void:
	if not is_open():
		return
	if started:
		if _winner() == 0:
			_begin_reconnect()
	else:
		_fail("team.join_failed" if local_seat == 0 else "team.host_left")


func _fail(message_key: String) -> void:
	close()
	failed.emit(message_key)


func _publish_link_state() -> void:
	targeting_aim.clear()
	absent_seats = _missing_deadlines.keys()
	for id in _connected_guests():
		_receive_link_state.rpc_id(id, absent_seats)
	view_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_link_state(seats: Array) -> void:
	targeting_aim.clear()
	if started and not interrupted:
		absent_seats = seats
		view_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_resume(payload: Dictionary, still_absent: Array) -> void:
	if not reconnecting or interrupted:
		return
	var snapshot := Wire.decode(payload)
	if snapshot.is_empty():
		return
	_set_player_view(snapshot)
	absent_seats = still_absent
	reconnecting = false
	waiting_for_reply = false
	if _local_reveal_confirmed:
		confirm_team_reveal()
	view_changed.emit()


func leave() -> void:
	if started and not interrupted and _winner() == 0:
		if _is_authority():
			_end_for_disconnect()
		elif is_open() and not reconnecting:
			_leave_match.rpc_id(1)
		await get_tree().create_timer(0.15).timeout
	close()


@rpc("any_peer", "call_remote", "reliable")
func _leave_match() -> void:
	if _is_authority() and started and _seats.has(_api.get_remote_sender_id()) and _winner() == 0:
		_end_for_disconnect(int(_seats[_api.get_remote_sender_id()]))


func _end_for_disconnect(seat: int = 0) -> void:
	if not matchmaking_mode.is_empty() and seat in [1, 2]:
		_state.winner = 3 if _missing_deadlines.size() == 2 else int(_state.teams[3 - seat])
		_state.state_revision += 1
		_publish_action_result(0, true)
		return
	_peer.refuse_new_connections = true
	for guest in _connected_guests():
		_match_interrupted.rpc_id(guest)
	_interrupt()
	if local_seat == 0 and _seats.is_empty():
		_reset_dedicated_match()


func _reset_dedicated_match() -> void:
	_missing_deadlines.clear()
	_reveal_capable_seats.clear()
	_reveal_pending_seats.clear()
	_seat_tokens.clear()
	absent_seats.clear()
	_state = null
	started = false
	interrupted = false
	_peer.refuse_new_connections = false
	_publish_roster()


func can_rematch() -> bool:
	return matchmaking_mode.is_empty() and is_open() and started and _winner() > 0 \
		and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not rematch_requested


func request_rematch() -> void:
	if not can_rematch():
		return
	if _is_authority():
		rematch_requested = true
		_returned[local_seat] = true
		view_changed.emit()
		_reopen_when_ready()
	elif rpc_id(1, "_request_rematch") == OK:
		rematch_requested = true
		view_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_rematch() -> void:
	var sender := _api.get_remote_sender_id()
	if _is_authority() and matchmaking_mode.is_empty() and started and _winner() > 0 and _seats.has(sender):
		_returned[_seats[sender]] = true
		_reopen_when_ready()


func _reopen_when_ready() -> void:
	if _returned.size() != _seats.size():
		return
	for id in _connected_guests():
		_return_to_lobby.rpc_id(id)
	_return_to_lobby()
	_missing_deadlines.clear()
	absent_seats.clear()
	_peer.refuse_new_connections = false
	_publish_roster()


@rpc("authority", "call_remote", "reliable")
func _return_to_lobby() -> void:
	if not started or _winner() == 0:
		return
	started = false
	rematch_requested = false
	interrupted = false
	_returned.clear()
	view = {}
	_state = null
	ready_seats.clear()
	absent_seats.clear()
	returned_to_lobby.emit()


@rpc("authority", "call_remote", "reliable")
func _match_interrupted() -> void:
	if started and _winner() == 0:
		_interrupt()


func _interrupt() -> void:
	if interrupted:
		return
	interrupted = true
	reconnecting = false
	waiting_for_reply = false
	view_changed.emit()


func _publish_roster() -> void:
	occupied = _seats.values()
	ready_seats = _decks.keys()
	for id in _connected_guests():
		_receive_roster.rpc_id(id, occupied, ready_seats, battle_rules)
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_roster(seats: Array, ready: Array, rules: Dictionary) -> void:
	if local_seat == 0 or started:
		return
	occupied = seats
	ready_seats = ready
	battle_rules = rules
	waiting_for_reply = false
	changed.emit()


func set_battle_rules(rules: Dictionary) -> void:
	if not is_host() or started:
		return
	if _is_authority():
		_apply_battle_rules(rules)
	else:
		_set_remote_battle_rules.rpc_id(1, rules)


@rpc("any_peer", "call_remote", "reliable")
func _set_remote_battle_rules(rules: Dictionary) -> void:
	if _is_authority() and matchmaking_mode.is_empty() and not started and _seats.get(_api.get_remote_sender_id(), 0) == 1:
		_apply_battle_rules(rules)


func _apply_battle_rules(rules: Dictionary) -> void:
	if not MatchAgreement.valid_config(rules) or rules == battle_rules:
		return
	battle_rules = rules.duplicate(true)
	_decks.clear()
	_publish_roster()


func can_change_ready() -> bool:
	return is_open() and local_seat != 0 and not started and not waiting_for_reply


func submit_deck(cards: Array) -> String:
	if not can_change_ready():
		return "team.wait"
	var deck: Array = []
	if not ready_seats.has(local_seat):
		if cards.is_empty():
			return "team.pick_deck"
		if not matchmaking_mode.is_empty() and cards.size() < PackRating.min_cards():
			return "matchmaking.deck_too_small"
		deck = cards.map(PlayerData.serialize_card)
		if not PlayerData.battle_deck_payload_errors(deck).is_empty():
			return "wait.invalid_local_deck"
		for data: Dictionary in deck:
			_remove_external_art(data)
		if var_to_bytes(deck).size() > NetworkManager.MAX_ROOM_DECK_BYTES:
			return "wait.local_deck_too_large"
		local_art = BattleArtResolver.local_art_index([cards, PlayerData.card_library])
	if _is_authority():
		_set_deck(local_seat, deck)
	else:
		# Advertise before the deck can make the room ready to start. Older
		# hosts ignore play commands while the room is still in the lobby.
		if matchmaking_mode.is_empty() or DisplayServer.get_name() != "headless":
			rpc_id(1, "_play", -1, REVEAL_CAPABLE, -1, 0, -1, -1)
		if rpc_id(1, "_submit_deck", deck) != OK:
			return "team.join_failed"
		waiting_for_reply = true
		changed.emit()
	return ""


static func _remove_external_art(card: Dictionary) -> void:
	card["art_path"] = ""
	card["damaged_art_path"] = ""
	for parasite: Dictionary in card.get("parasite_cards", []):
		_remove_external_art(parasite)


@rpc("any_peer", "call_remote", "reliable")
func _submit_deck(deck: Array) -> void:
	if not _is_authority() or started:
		return
	var sender := _api.get_remote_sender_id()
	var seat: int = _seats.get(sender, 0)
	if seat == 0:
		return
	if not matchmaking_mode.is_empty() and not deck.is_empty():
		if _decks.has(seat):
			return
		if deck.size() < PackRating.min_cards():
			_reject_peer(sender, "matchmaking.deck_too_small")
			return
	if not deck.is_empty():
		if (deck.size() > DataSchema.MAX_CARDS_PER_DECK or var_to_bytes(deck).size() > NetworkManager.MAX_ROOM_DECK_BYTES
				or not PlayerData.battle_deck_payload_errors(deck).is_empty()):
			if matchmaking_mode.is_empty():
				_publish_roster()
			else:
				_reject_peer(sender, "wait.invalid_local_deck")
			return
		for data: Dictionary in deck:
			_remove_external_art(data)
		if not matchmaking_mode.is_empty():
			for index in deck.size():
				deck[index] = PlayerData.serialize_card(PackRating.prepare_card(PlayerData.deserialize_card(deck[index])))
	_set_deck(seat, deck)
	if not matchmaking_mode.is_empty() and _decks.size() == seat_count:
		_start_match()


func _set_deck(seat: int, deck: Array) -> void:
	if deck.is_empty():
		_decks.erase(seat)
	else:
		_decks[seat] = deck
	_publish_roster()


func can_start() -> bool:
	return is_host() and not started and occupied.size() == seat_count and ready_seats.size() == seat_count


func start() -> void:
	if not can_start():
		return
	if _is_authority():
		_start_match()
	else:
		_request_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_start() -> void:
	if _is_authority() and _seats.get(_api.get_remote_sender_id(), 0) == 1:
		_start_match()


func _start_match() -> void:
	if started or _seats.size() != seat_count or _decks.size() != seat_count:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not matchmaking_mode.is_empty():
		_idle_by = 0
		_duel_pool = _decks[1].duplicate(true)
		_duel_pool.append_array(_decks[2].duplicate(true))
	if matchmaking_mode == Matchmaking.RANKED:
		for seat in [1, 2]:
			var cards: Array = _decks[seat].map(PlayerData.deserialize_card)
			_duel_multipliers.append(PackRating.evaluate(cards, int(_duel_ratings[seat - 1])).multiplier)
	var match_key := Crypto.new().generate_random_bytes(12).hex_encode()
	var order: Array[int] = []
	for seat in range(1, seat_count + 1):
		order.append(seat)
		var deck: Array = _decks[seat]
		for index in deck.size():
			deck[index]["instance_id"] = "team_%s_%d_%d" % [match_key, seat, index]
	_state = State.new()
	GameplayRng.shuffle(order, rng)
	_state.start_match(_decks, order, rng.randi(), battle_rules)
	action_clock = ActionClock.new()
	_local_reveal_confirmed = false
	_reveal_pending_seats = _reveal_capable_seats.duplicate()
	if local_seat > 0:
		_reveal_pending_seats[local_seat] = true
	_team_reveal_until = Time.get_ticks_msec() + TEAM_REVEAL_MS if _reveal_pending_seats.size() < seat_count else 0
	if not matchmaking_mode.is_empty():
		_team_reveal_until = 0 if _reveal_pending_seats.is_empty() else Time.get_ticks_msec() + MATCHMADE_REVEAL_TIMEOUT_MS
	_tick_authority_clock(Time.get_ticks_msec())
	_peer.refuse_new_connections = true
	_decks.clear()
	for id in _connected_guests():
		_begin_match.rpc_id(id, Wire.encode(_clocked_player_view(_seats[id])))
	started = true
	if local_seat > 0:
		view = _state.player_view(local_seat)
	battle_started.emit()


@rpc("authority", "call_remote", "reliable")
func _begin_match(payload: Dictionary) -> void:
	if local_seat == 0 or not ready_seats.has(local_seat) or started:
		return
	var initial := Wire.decode(payload)
	if initial.is_empty():
		_fail("team.join_failed")
		return
	_set_player_view(initial)
	started = true
	_local_reveal_confirmed = false
	battle_started.emit()


func is_my_turn() -> bool:
	return _can_send_action() and int(view.chooser) == 0 and int(view.active) == local_seat


func _can_send_action() -> bool:
	return (local_seat > 0 and is_open() and started and not interrupted and not waiting_for_reply and not reconnecting
		and absent_seats.is_empty() and not team_reveal_pending() and _winner() == 0)


func can_answer_choice() -> bool:
	return _can_send_action() and int(view.chooser) == local_seat


func choose_cards(indices: Array) -> void:
	if not can_answer_choice():
		return
	var revision: int = view.revision
	if _is_authority():
		_apply_choice(1, revision, indices)
	elif rpc_id(1, "_choose_cards", revision, indices) == OK:
		waiting_for_reply = true
		view_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _choose_cards(revision: int, indices: Array) -> void:
	var sender := _api.get_remote_sender_id()
	if _is_authority() and sender > 1 and _seats.has(sender):
		_apply_choice(sender, revision, indices)


func _apply_choice(peer_id: int, revision: int, indices: Array) -> void:
	if not started:
		return
	var accepted := not interrupted and absent_seats.is_empty() and not team_reveal_pending() \
		and _state.apply_card_choice(_seats[peer_id], revision, indices)
	_publish_action_result(peer_id, accepted)


func play(command: String, source: int, target_seat: int, target_slot: int, skill: int = -1) -> void:
	if not is_my_turn():
		return
	var revision: int = view["revision"]
	if _is_authority():
		_apply_action(1, revision, command, source, target_seat, target_slot, skill)
	elif rpc_id(1, "_play", revision, command, source, target_seat, target_slot, skill) == OK:
		waiting_for_reply = true
		view_changed.emit()


func publish_targeting_aim(source: int, target_seat: int, target_slot: int) -> void:
	if not is_my_turn():
		return
	var revision: int = view.revision
	if _is_authority():
		_relay_targeting_aim(1, revision, source, target_seat, target_slot)
	elif _guest_clock_timing.get(AIM_COMMAND, false):
		rpc_id(1, "_play", revision, AIM_COMMAND, source, target_seat, target_slot, -1)


func visible_targeting_aim() -> Dictionary:
	if (targeting_aim.get("revision", -1) != view.get("revision", -2)
			or Time.get_ticks_msec() - _aim_received_at >= AIM_LIFETIME_MS):
		return {}
	return targeting_aim


func _relay_targeting_aim(peer_id: int, revision: int, source: int, target_seat: int, target_slot: int) -> void:
	var seat: int = _seats[peer_id]
	if (not started or interrupted or not absent_seats.is_empty() or _state.winner != 0
			or revision != _state.state_revision or seat != _state.active_seat or not _state._choices.is_empty()):
		return
	var now := Time.get_ticks_msec()
	if target_slot >= 0:
		var from: BattleField = _state.fields.get(seat)
		var to: BattleField = _state.fields.get(target_seat)
		if (now < _aim_relay_at or from == null or to == null or to.player_hp <= 0
				or source < 0 or source >= from.slots.size() or from.slots[source] == null
				or target_slot >= to.slots.size() or to.slots[target_slot] == null):
			return
		_aim_relay_at = now + 35
	var aim := {"revision": revision, "seat": seat, "source": source, "target_seat": target_seat, "target": target_slot}
	# Older clients discard the negative snapshot revision. New clients extract
	# the aim without treating it as an action acknowledgement.
	for guest in _connected_guests():
		if guest != peer_id:
			_receive_view.rpc_id(guest, {"revision": -1, AIM_COMMAND: aim}, true)
	if local_seat > 0 and local_seat != seat:
		_store_targeting_aim(aim)


func _store_targeting_aim(aim: Dictionary) -> void:
	if int(aim.revision) != int(view.get("revision", -1)):
		return
	targeting_aim = aim if int(aim.target) >= 0 else {}
	_aim_received_at = Time.get_ticks_msec()


@rpc("any_peer", "call_remote", "reliable")
func _play(revision: int, command: String, source: int, target_seat: int, target_slot: int, skill: int) -> void:
	var sender := _api.get_remote_sender_id()
	if _is_authority() and sender > 1 and _seats.has(sender):
		if command == AIM_COMMAND:
			_relay_targeting_aim(sender, revision, source, target_seat, target_slot)
		elif command == REVEAL_CAPABLE:
			if not started:
				_reveal_capable_seats[_seats[sender]] = true
		elif command == REVEAL_CONFIRMED:
			if started and not interrupted and revision == _state.state_revision:
				_confirm_reveal_seat(_seats[sender])
		else:
			_apply_action(sender, revision, command, source, target_seat, target_slot, skill)


func _apply_action(peer_id: int, revision: int, command: String, source: int, target_seat: int, target_slot: int, skill: int) -> void:
	if not started:
		return
	var accepted := (not interrupted and absent_seats.is_empty() and not team_reveal_pending()
		and _state.apply_action(_seats[peer_id], revision, command, source, target_seat, target_slot, skill))
	_publish_action_result(peer_id, accepted)


func _publish_action_result(peer_id: int, accepted: bool) -> void:
	if not accepted:
		if peer_id == 1:
			action_rejected.emit()
		else:
			_receive_view.rpc_id(peer_id, Wire.encode(_clocked_player_view(_seats[peer_id])), false)
		return
	if not matchmaking_mode.is_empty() and _winner() != 0:
		_save_duel_result()
	_tick_authority_clock(Time.get_ticks_msec())
	for id in _connected_guests():
		_receive_view.rpc_id(id, Wire.encode(_clocked_player_view(_seats[id])), true)
	if local_seat > 0:
		view = _state.player_view(local_seat)
	view_changed.emit()


func _save_duel_result() -> void:
	if _duel_result_path.is_empty():
		return
	if _idle_by == 0:
		_idle_by = Time.get_ticks_msec() + 45000
	var temporary := _duel_result_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify({
		"winner": _winning_duel_seat(), "multipliers": _duel_multipliers,
	})):
		return
	file.close()
	if DirAccess.rename_absolute(temporary, _duel_result_path) == OK:
		_duel_result_path = ""


func _winning_duel_seat() -> int:
	var winner := _winner()
	return 3 if winner == 3 else (1 if int(_state.teams[1]) == winner else 2)


@rpc("authority", "call_remote", "reliable")
func _receive_view(payload: Dictionary, accepted: bool) -> void:
	if not started or interrupted:
		return
	if payload.has(AIM_COMMAND):
		if not reconnecting and absent_seats.is_empty():
			_store_targeting_aim(payload[AIM_COMMAND])
		return
	var snapshot := Wire.decode(payload)
	if snapshot.is_empty() or int(snapshot.get("revision", -1)) < int(view.get("revision", 0)):
		return
	_set_player_view(snapshot)
	waiting_for_reply = false
	view_changed.emit()
	if not accepted:
		action_rejected.emit()

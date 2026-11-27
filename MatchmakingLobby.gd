extends Control

const Queue = preload("res://MatchmakingQueue.gd")
const Identity = preload("res://MatchmakingIdentity.gd")
const PackRating = preload("res://MatchPackRating.gd")
const Rating = preload("res://RankedRating.gd")
const Ranks = preload("res://RankTiers.gd")
const DeckSelect = preload("res://BattleDeckSelect.tscn")
const LaunchFrame = preload("res://presentation/BattleLaunchFrame.gd")
const Ladder = preload("res://presentation/RankLadder.gd")

@onready var _room: Node = NetworkManager.team_room
var _mode := ""
var _identity: CryptoKey
var _phase := ""
var _deadline := 0
var _started := 0
var _handoff := false
var _queued := false
var _address := NetworkManager.DEFAULT_LOBBY_ADDRESS
var _port := NetworkManager.LOBBY_PORT
var _action: Button
var _rating: Label
var _rank_row: HBoxContainer
var _rank_badge: Button
var _rank_name: Label
var _status: Label
var _server: LineEdit
var _server_settings: Button
var _entry: ScrollContainer
var _launch: Control
var _back: Button
var _preparation: Control
var _leave_dialog: ConfirmationDialog
var _score := Rating.INITIAL_RATING
var _has_score := false


func _ready() -> void:
	_mode = PlayerData.matchmaking_mode if Queue.valid_mode(PlayerData.matchmaking_mode) else Queue.RANDOM
	for argument in OS.get_cmdline_user_args():
		if OS.is_debug_build() and argument.begins_with("--matchmaking-endpoint="):
			var endpoint := NetworkProtocolGuard.parse_host_address(argument.get_slice("=", 1), _port)
			_address = endpoint.address
			_port = endpoint.port
	_build_page()
	_room.close()
	NetworkManager.lobby_connected.connect(_send_request)
	NetworkManager.lobby_connection_failed.connect(_show_connection_error)
	_room.failed.connect(_room_failed)
	_room.battle_started.connect(_begin_match)
	_room.changed.connect(_on_room_changed)
	_identity = Identity.load_or_create()
	if _identity == null:
		_action.disabled = true
		_status.text = Locale.t("matchmaking.profile_error")
	elif _mode == Queue.RANKED:
		_connect_lobby("profile")


func _build_page() -> void:
	var background := Panel.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.apply_app_background(background)
	_launch = LaunchFrame.new()
	add_child(_launch)
	_launch.setup(Locale.t("matchmaking." + _mode), Locale.t("matchmaking." + _mode + "_rules"), _mode)
	_back = Button.new()
	_back.text = Locale.t("common.back")
	add_child(_back)
	UITheme.place_page_back(self, _back)
	_back.pressed.connect(_on_back_pressed)
	_entry = ScrollContainer.new()
	_entry.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_entry.follow_focus = true
	add_child(_entry)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 12)
	_entry.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("launch.ranked_profile" if _mode == Queue.RANKED else "launch.random_match")
	UITheme.apply_room_entry_title(title)
	box.add_child(title)
	_rank_row = HBoxContainer.new()
	_rank_row.add_theme_constant_override("separation", 16)
	_rank_row.visible = _mode == Queue.RANKED
	box.add_child(_rank_row)
	_rank_badge = Button.new()
	_rank_badge.custom_minimum_size = Vector2(76, 76)
	_rank_badge.text = Locale.t("matchmaking.ladder_open")
	_rank_badge.tooltip_text = Locale.t("matchmaking.ladder_tooltip")
	_rank_badge.expand_icon = true
	_rank_badge.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_badge.add_theme_constant_override("icon_max_width", 68)
	UITheme.apply_button(_rank_badge, "secondary", false)
	var badge_surface := _rank_badge.get_theme_stylebox("normal") as StyleBoxFlat
	badge_surface.bg_color = Color.TRANSPARENT
	var badge_text := _rank_badge.get_theme_color("font_color")
	for state in ["hover", "pressed", "hover_pressed"]:
		_rank_badge.add_theme_stylebox_override(state, badge_surface)
		_rank_badge.add_theme_color_override("font_" + state + "_color", badge_text)
		_rank_badge.add_theme_color_override("icon_" + state + "_color", Color.WHITE)
	_rank_badge.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_rank_badge.add_theme_color_override("font_focus_color", badge_text)
	_rank_badge.add_theme_color_override("icon_focus_color", Color.WHITE)
	_rank_badge.pressed.connect(func(): Ladder.open(self, _score if _has_score else -1))
	_rank_row.add_child(_rank_badge)
	var rank_text := VBoxContainer.new()
	rank_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank_text.add_theme_constant_override("separation", 2)
	_rank_row.add_child(rank_text)
	_rank_name = Label.new()
	_rank_name.text = Locale.t("launch.rating_loading")
	UITheme.apply_title(_rank_name, 22)
	rank_text.add_child(_rank_name)
	_rating = Label.new()
	UITheme.apply_label(_rating)
	rank_text.add_child(_rating)
	box.add_child(UITheme.separator())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 48
	UITheme.apply_label(_status, true)
	box.add_child(_status)
	_action = Button.new()
	_action.text = Locale.t("matchmaking.start")
	_action.custom_minimum_size.y = 52
	UITheme.apply_button(_action, "primary")
	_action.pressed.connect(_toggle_search)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 20)
	box.add_child(actions)
	_server_settings = Button.new()
	_server_settings.text = Locale.t("lobby.server_settings")
	UITheme.apply_button(_server_settings, "utility")
	_server_settings.pressed.connect(func():
		_server.visible = not _server.visible
		if _server.visible:
			_server.grab_focus())
	actions.add_child(_server_settings)
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_action)
	_server = LineEdit.new()
	_server.placeholder_text = _address
	_server.text = PlayerData.matchmaking_endpoint
	_server.max_length = 255
	UITheme.apply_input(_server)
	box.add_child(_server)
	_server.hide()
	_launch.bind_form(_entry)
	_action.grab_focus()


func _toggle_search() -> void:
	if _queued:
		NetworkManager.disconnect_from_lobby()
		_reset_search("")
	elif _phase.is_empty():
		_connect_lobby("join")


func _connect_lobby(action: String) -> void:
	if not _server.text.strip_edges().is_empty():
		var endpoint := NetworkProtocolGuard.parse_host_address(_server.text.strip_edges(), NetworkManager.LOBBY_PORT)
		if not NetworkManager.is_valid_address(endpoint.address) or int(endpoint.port) not in range(1, 65536):
			_status.text = Locale.t("lobby.invalid_server_address")
			_server.grab_focus()
			return
		_address = endpoint.address
		_port = endpoint.port
		PlayerData.matchmaking_endpoint = _server.text.strip_edges()
	_phase = action
	_action.disabled = true
	_server.editable = false
	_server_settings.disabled = true
	_status.remove_theme_color_override("font_color")
	UITheme.apply_label(_status, true)
	_status.text = Locale.t("lobby.connecting_lobby")
	if NetworkManager.connect_to_lobby(_address, _receive_lobby, _port) != OK:
		_show_connection_error()


func _send_request() -> void:
	if not _phase.is_empty():
		NetworkManager.request_matchmaking("challenge", _mode)


func _receive_lobby(response: Dictionary) -> void:
	if response.get("pack_protocol", 0) != Queue.PACK_PROTOCOL:
		NetworkManager.disconnect_from_lobby()
		_reset_search("team.incompatible")
		return
	match str(response.get("status", "")):
		"challenge":
			var nonce := str(response.get("nonce", ""))
			if nonce.length() != 64 or not nonce.is_valid_hex_number(false):
				_show_connection_error()
				return
			var proof := Identity.prove(_identity, nonce, _phase, _mode)
			if _mode == Queue.RANKED:
				proof["history_pending"] = PlayerData.pending_ranked_history_ids()
			NetworkManager.request_matchmaking(_phase, _mode, proof)
		"profile", "waiting":
			if _mode == Queue.RANKED:
				var settlements: Variant = response.get("history_settlements", {})
				if settlements is Dictionary:
					PlayerData.apply_ranked_history_settlements(settlements)
				_score = int(response.rating)
				_has_score = true
				_rating.text = Locale.t("matchmaking.record", [_score, int(response.played), int(response.won)])
				var tier_index := Ranks.tier_index(_score)
				var tier: Dictionary = Ranks.TIERS[tier_index]
				_rank_badge.icon = tier.badge
				_rank_badge.text = ""
				_rank_name.text = Locale.t("matchmaking.rank_" + str(tier.id))
				_rank_row.tooltip_text = Locale.t("matchmaking.rank_next", [Ranks.TIERS[tier_index + 1].minimum]) \
					if tier_index + 1 < Ranks.TIERS.size() else ""
				_rank_row.show()
			if response.status == "waiting":
				_queued = true
				_started = Time.get_ticks_msec()
				_deadline = _started + Queue.SEARCH_LIMIT_MS + 3000
				_action.text = Locale.t("matchmaking.cancel")
				_action.disabled = false
			else:
				NetworkManager.disconnect_from_lobby()
				_reset_search("")
		"matched":
			if response.get("mode") != _mode:
				_show_connection_error()
				return
			_queued = false
			_phase = "room"
			NetworkManager.disconnect_from_lobby()
			_status.text = Locale.t("lobby.waiting_room_connecting")
			_action.disabled = true
			_deadline = Time.get_ticks_msec() + Queue.PREPARATION_LIMIT_MS
			if _room.join(_address, int(response.get("port", 0)), str(response.get("invite", "")), _mode) != OK:
				_room_failed("team.join_failed")
		"expired":
			NetworkManager.disconnect_from_lobby()
			_reset_search("matchmaking.expired")
		"already_playing", "already_waiting", "rating_unavailable", "room_unavailable":
			NetworkManager.disconnect_from_lobby()
			_reset_search("matchmaking." + str(response.status))
		"protocol_mismatch":
			NetworkManager.disconnect_from_lobby()
			_reset_search("team.incompatible")
		_:
			_show_connection_error()


func _show_connection_error() -> void:
	NetworkManager.disconnect_from_lobby()
	_reset_search("matchmaking.unavailable")


func _room_failed(reason: String) -> void:
	_phase = ""
	_close_leave_dialog()
	_room.close()
	_reset_search(reason)


func _reset_search(message_key: String) -> void:
	_phase = ""
	_queued = false
	if is_instance_valid(_preparation):
		_preparation.hide()
		_preparation.queue_free()
		_preparation = null
	_entry.show()
	_back.show()
	_deadline = 0
	var failed := message_key in ["matchmaking.unavailable", "matchmaking.expired", "matchmaking.room_unavailable",
		"matchmaking.preparation_expired", "team.join_failed"]
	_action.text = Locale.t("launch.retry_search" if failed else "matchmaking.start")
	UITheme.apply_label(_status, true)
	if failed:
		_status.add_theme_color_override("font_color", UITheme.Tokens.WARNING)
	if _mode == Queue.RANKED and not _has_score:
		_rank_name.text = Locale.t("launch.rating_unavailable")
	_action.disabled = false
	_server.editable = true
	_server_settings.disabled = false
	var arguments := [PackRating.min_cards()] if message_key == "matchmaking.deck_too_small" else []
	_status.text = "" if message_key.is_empty() else Locale.t(message_key, arguments)
	_action.grab_focus()


func _on_room_changed() -> void:
	if _phase != "room" or _room.local_seat == 0 or _room.started:
		return
	if not is_instance_valid(_preparation):
		_preparation = DeckSelect.instantiate()
		_preparation.room_mode = _mode
		_preparation.room_rating = _score
		_preparation.room_confirm = _ready_pack
		_preparation.room_back = _on_back_pressed
		_entry.hide()
		_back.hide()
		add_child(_preparation)
	var ready: bool = _room.ready_seats.has(_room.local_seat)
	var message := "matchmaking.waiting_opponent" if ready else ("matchmaking.sending_deck" if _room.waiting_for_reply else "")
	if message.is_empty() and not _room.ready_seats.is_empty():
		message = "matchmaking.opponent_ready"
	_preparation.update_room_status(Locale.t(message) if not message.is_empty() else "", ready, _room.waiting_for_reply)


func _ready_pack(deck_id: String, cards: Array) -> void:
	var was_ready: bool = _room.ready_seats.has(_room.local_seat)
	var error: String = _room.submit_deck([] if was_ready else cards.map(PackRating.prepare_card))
	if error.is_empty() and not was_ready:
		PlayerData.matchmaking_deck_id = deck_id
		_room.contribution_name = PlayerData.deck_display_name(PlayerData.get_deck(deck_id))
	elif not error.is_empty():
		var args := [PackRating.min_cards()] if error == "matchmaking.deck_too_small" else []
		_preparation.update_room_status(Locale.t(error, args), was_ready)


func _leave_room() -> void:
	_room_failed("")


func _on_back_pressed() -> void:
	if _phase != "room":
		UIMotion.go_back("res://MainMenu.tscn")
		return
	if not is_instance_valid(_preparation):
		_leave_room()
		return
	if is_instance_valid(_leave_dialog):
		return
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = Locale.t("wait.leave_room")
	_leave_dialog.dialog_text = Locale.t("wait.leave_room_body")
	add_child(_leave_dialog)
	UITheme.apply_dialog(_leave_dialog)
	UITheme.apply_destructive_confirmation(_leave_dialog, Locale.t("wait.leave_room"))
	_leave_dialog.confirmed.connect(_leave_room)
	_leave_dialog.canceled.connect(func():
		_close_leave_dialog()
		if is_instance_valid(_preparation):
			_preparation.back_button.grab_focus())
	_leave_dialog.popup_centered()


func _close_leave_dialog() -> void:
	if not is_instance_valid(_leave_dialog):
		return
	_leave_dialog.hide()
	_leave_dialog.queue_free()
	_leave_dialog = null


func _process(_delta: float) -> void:
	if _deadline == 0 or _handoff:
		return
	var now := Time.get_ticks_msec()
	if _queued:
		if now >= _deadline or not NetworkManager.is_online:
			_show_connection_error()
		else:
			_status.text = Locale.t("matchmaking.searching", [floori(float(now - _started) / 1000.0)])
	elif now >= _deadline:
		_room_failed("matchmaking.preparation_expired" if is_instance_valid(_preparation) else "team.join_failed")


func _begin_match() -> void:
	if UIMotion.is_transitioning():
		return
	_handoff = true
	PlayerData.clear_battle_preparation()
	UIMotion.replace_scene("res://TeamBattle.tscn")


func _exit_tree() -> void:
	NetworkManager.disconnect_from_lobby()
	if not _handoff:
		_room.close()

extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const LaunchFrame = preload("res://presentation/BattleLaunchFrame.gd")

static var _entry_draft: Dictionary = {}

var lobby_port: int = NetworkManager.LOBBY_PORT

@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var server_input = $Panel/VBoxContainer/ServerInput
@onready var room_input = $Panel/VBoxContainer/RoomInput
@onready var create_btn = $Panel/VBoxContainer/CreateButton
@onready var join_btn = $Panel/VBoxContainer/JoinButton
@onready var check_server_btn = $Panel/VBoxContainer/CheckServerButton
@onready var back_btn = $Panel/VBoxContainer/BackButton
@onready var lobby_panel = $Panel
@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var server_label = $Panel/VBoxContainer/ServerLabel
@onready var room_label = $Panel/VBoxContainer/RoomLabel
@onready var default_server_address: String = NetworkManager.DEFAULT_LOBBY_ADDRESS
@onready var _cancel_handoff_timer: Timer = $CancelHandoffTimer
@onready var _start_confirmation_timer: Timer = $StartConfirmationTimer


func _apply_texts() -> void:
	title_label.text = Locale.t("launch.friend_room")
	server_label.text = Locale.t("lobby.server")
	room_label.text = Locale.t("lobby.room_code").trim_suffix(":")
	room_input.placeholder_text = Locale.t("launch.room_code_hint")
	create_btn.text = Locale.t("lobby.create")
	join_btn.text = Locale.t("lobby.join")
	check_server_btn.text = Locale.t("lobby.check_server")
	back_btn.text = Locale.t("common.back")

var card_ui_scene = preload("res://CardUI.tscn")
var opponent_ready: bool = false
var i_am_ready: bool = false
var _opponent_arts_received: int = 0
var _opponent_arts_total: int = -1
var _my_arts_acked: int = 0
var _my_arts_total: int = -1
var _acked_my_art_indices: Dictionary = {}
var _pending_opponent_art_paths: Dictionary = {}
var _battle_starting: bool = false
var _art_wait_deadline: float = 0.0
const ART_WAIT_TIMEOUT := 10.0
const CANCEL_HANDOFF_TIMEOUT := 3.0
var waiting_ui: Control
var start_btn: Button
var create_card_btn: Button
var _my_player: int = 0
var _pending_room_code: String = ""
var _pending_lobby_action: String = ""
var _generated_room_code := false
var _room_code_retries := 0
var _request_server_address := ""
var _join_attempt_target: Array = []
var _join_attempt_id := ""
var _server_settings: Button
var _connection_attempt := 0
var _connecting_to_room := false
var _reservation_request_pending := false
var _cancelling_connection := false
var cancelling_preparation := false
var _focus_ready_on_recovery := false
var _launch: Control


func _apply_theme() -> void:
	var bg := Panel.new()
	bg.name = "ThemeBackground"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(bg)
	add_child(bg)
	move_child(bg, 0)
	lobby_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_launch = LaunchFrame.new()
	add_child(_launch)
	move_child(_launch, 1)
	_launch.setup(Locale.t("lobby.title"), Locale.t("launch.friend_room_intro"), "room")
	_launch.bind_form(lobby_panel)
	var form := $Panel/VBoxContainer
	form.move_child(join_btn, room_input.get_index() + 1)
	var action_divider := UITheme.separator()
	form.add_child(action_divider)
	form.move_child(action_divider, create_btn.get_index())
	form.move_child(_server_settings, create_btn.get_index() + 1)
	UITheme.apply_room_entry_title(title_label, _ui_scale())
	UITheme.apply_separator($Panel/VBoxContainer/Separator)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.get_parent().move_child(status_label, -1)
	for label in [status_label, server_label, room_label]:
		UITheme.apply_label(label, label == status_label)
	for input in [server_input, room_input]:
		UITheme.apply_input(input)
	_style_room_entry_actions()
	UITheme.apply_button(check_server_btn, "outlined")
	UITheme.place_page_back(self, back_btn)


func _style_room_entry_actions() -> void:
	var entering_code: bool = not room_input.text.strip_edges().is_empty()
	UITheme.apply_button(create_btn, "outlined" if entering_code else "primary", false)
	UITheme.apply_button(join_btn, "primary" if entering_code else "outlined", false)


func _theme_waiting_label(label: Label, title: bool = false) -> void:
	if title:
		UITheme.apply_title(label, max(14, int(18 * _ui_scale())))
	else:
		UITheme.apply_label(label, true)


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var vbox := $Panel/VBoxContainer
	vbox.add_theme_constant_override("separation", int(12 * s))

	for child in vbox.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", maxi(14, roundi(15 * s)))
			UITheme.apply_label(child, child.name == "StatusLabel")
			if child.name == "TitleLabel":
				UITheme.apply_room_entry_title(child, s)
			elif child.name == "StatusLabel":
				# Long error messages must wrap instead of stretching the panel wide.
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				child.custom_minimum_size = Vector2(360 * s, 0)
				child.size_flags_horizontal = Control.SIZE_FILL
		elif child is Button:
			child.add_theme_font_size_override("font_size", max(14, int(16 * s)))
			if child != create_btn and child != join_btn:
				UITheme.apply_button(child, "utility" if child == _server_settings else "outlined")
		elif child is LineEdit:
			child.custom_minimum_size = Vector2(200 * s, 0)
			UITheme.apply_input(child)

	# Size the panel to fit its contents (avoids buttons overflowing the dark panel).
	_resize_panel_to_content.call_deferred(s)

	if waiting_ui:
		_scale_waiting_room(s)


func _resize_panel_to_content(s: float) -> void:
	var vbox := $Panel/VBoxContainer
	_launch.place_form(lobby_panel)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = maxf(12.0, 30.0 * s)
	vbox.offset_bottom = 0


func _scale_waiting_room(s: float) -> void:
	if is_instance_valid(waiting_ui) and waiting_ui.has_method("apply_scale"):
		waiting_ui.apply_scale(s)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


var match_agreement: MatchAgreement
var preparation_reset_reason := ""


func _ready():
	match_agreement = MatchAgreement.new()
	add_child(match_agreement)
	match_agreement.setup(self)
	match_agreement.confirmation_completed.connect(_start_confirmation_timer.start)
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	check_server_btn.pressed.connect(_on_check_server_pressed)
	room_input.text_submitted.connect(func(_value: String):
		if not join_btn.disabled:
			_on_join_pressed()
	)
	room_input.text_changed.connect(func(_value: String): _style_room_entry_actions())
	server_input.text_submitted.connect(func(_value: String):
		_on_check_server_pressed()
	)
	back_btn.pressed.connect(_on_back_pressed)
	_cancel_handoff_timer.timeout.connect(_on_cancel_handoff_timeout)
	NetworkManager.connected.connect(_on_opponent_joined)
	NetworkManager.lobby_connected.connect(_on_lobby_connected)
	NetworkManager.lobby_connection_failed.connect(_on_lobby_connection_failed)
	NetworkManager.game_connection_failed.connect(_on_game_connection_failed)
	NetworkManager.room_authenticated.connect(_on_room_authenticated)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.room_host_changed.connect(_on_room_host_changed)
	NetworkManager.room_preparation_reset.connect(_on_room_preparation_reset)
	NetworkManager.room_link_wait_changed.connect(_on_room_link_wait_changed)
	EventBus.rpc_ready_received.connect(_on_rpc_ready)
	NetworkManager.game_started.connect(_on_battle_start)
	EventBus.rpc_card_art_received.connect(_on_card_art_received)
	EventBus.rpc_card_art_manifest_received.connect(_on_card_art_manifest)
	EventBus.rpc_card_art_ack_received.connect(_on_card_art_ack)
	_apply_texts()
	_setup_server_settings()
	if not _entry_draft.is_empty():
		_server_settings.button_pressed = _entry_draft.server_settings_open
		if not PlayerData.return_to_waiting_room:
			room_input.text = _entry_draft.room_code
			server_input.text = _entry_draft.server_address
			_focus_room_code()
	_apply_theme()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_process(false)
	if PlayerData.return_to_waiting_room:
		PlayerData.return_to_waiting_room = false
		if NetworkManager.has_live_server_room():
			_show_waiting_room()
			NetworkManager.arrive_in_server_room()
		else:
			_return_to_room_entry(Locale.t("lobby.lost_game_room"))


# ============================================
# Create / Join room
# ============================================

func _setup_server_settings() -> void:
	var form := $Panel/VBoxContainer
	_server_settings = Button.new()
	_server_settings.name = "ServerSettingsButton"
	_server_settings.text = Locale.t("lobby.server_settings")
	_server_settings.toggle_mode = true
	form.add_child(_server_settings)
	form.move_child(_server_settings, join_btn.get_index() + 1)
	for control in [server_label, server_input, check_server_btn]:
		form.move_child(control, form.get_child_count() - 1)
		control.hide()
	server_input.placeholder_text = default_server_address
	_server_settings.toggled.connect(func(open: bool):
		for control in [server_label, server_input, check_server_btn]:
			control.visible = open
		_resize_panel_to_content.call_deferred(_ui_scale())
	)


func _selected_server_address() -> String:
	var address: String = server_input.text.strip_edges()
	return default_server_address if address.is_empty() else address


func _on_create_pressed():
	if create_btn.disabled: return
	var code: String = room_input.text.strip_edges()
	_generated_room_code = code.is_empty()
	_room_code_retries = 0
	if _generated_room_code:
		code = _new_room_code()
		room_input.text = code
	if not NetworkManager.is_valid_room_code(code):
		_show_entry_message(Locale.t("lobby.invalid_code"))
		_focus_room_code(true)
		return
	_pending_room_code = code
	_connect_to_lobby("create", _on_lobby_response_create)



func _new_room_code() -> String:
	return str(randi_range(10000000, 99999999))


func _on_lobby_connected():
	if _pending_lobby_action == "create":
		_reservation_request_pending = true
		status_label.text = Locale.t("lobby.creating_room")
		NetworkManager.create_room(_pending_room_code)
	elif _pending_lobby_action == "join":
		_reservation_request_pending = true
		status_label.text = Locale.t("lobby.joining_room")
		var target := [_request_server_address, lobby_port, _pending_room_code]
		if _join_attempt_target != target:
			_join_attempt_target = target
			_join_attempt_id = Crypto.new().generate_random_bytes(16).hex_encode()
		NetworkManager.join_room(_pending_room_code, _join_attempt_id)
	elif _pending_lobby_action == "status":
		status_label.text = Locale.t("lobby.checking_status")
		NetworkManager.request_lobby_status(Callable(self, "_on_lobby_status_response"))


func _reset_lobby_buttons():
	_cancel_handoff_timer.stop()
	_connection_attempt += 1
	_connecting_to_room = false
	_reservation_request_pending = false
	_cancelling_connection = false
	_pending_lobby_action = ""
	create_btn.disabled = false
	join_btn.disabled = false
	check_server_btn.disabled = false
	server_input.editable = true
	room_input.editable = true
	back_btn.disabled = false
	back_btn.text = Locale.t("common.back")
	_style_room_entry_actions()
	_resize_panel_to_content.call_deferred(_ui_scale())


func _connect_to_lobby(action: String, response: Callable) -> void:
	_request_server_address = _selected_server_address()
	if _request_server_address.contains(" ") or _request_server_address.contains("\t") or _request_server_address.contains("://"):
		_show_entry_message(Locale.t("lobby.invalid_server_address"))
		_focus_server_address()
		return
	_connection_attempt += 1
	_pending_lobby_action = action
	status_label.text = Locale.t("lobby.connecting_lobby")
	create_btn.disabled = true
	join_btn.disabled = true
	check_server_btn.disabled = true
	server_input.editable = false
	room_input.editable = false
	back_btn.text = Locale.t("lobby.cancel_connection")
	if NetworkManager.connect_to_lobby(_request_server_address, response, lobby_port) != OK:
		_return_to_room_entry(Locale.t("lobby.could_not_reach"))
	else:
		back_btn.grab_focus()
		_resize_panel_to_content.call_deferred(_ui_scale())


func _show_entry_message(message: String) -> void:
	status_label.text = message
	_resize_panel_to_content.call_deferred(_ui_scale())


func _focus_room_code(select_code: bool = false) -> void:
	room_input.grab_focus()
	if select_code:
		room_input.select_all()
	else:
		room_input.deselect()
		room_input.caret_column = room_input.text.length()


func _focus_server_address() -> void:
	_server_settings.button_pressed = true
	server_input.grab_focus()
	server_input.select_all()


func _finish_lobby_protocol_mismatch(data: Dictionary) -> void:
	NetworkManager.disconnect_from_lobby()
	_reset_lobby_buttons()
	var server_protocol := int(data.get("remote_protocol", data.get("protocol", 0)))
	_show_entry_message(Locale.t("lobby.protocol_mismatch", [AppVersion.PROTOCOL_VERSION, server_protocol]))
	_focus_server_address()


func _finish_room_code_request(message: String, select_code: bool) -> void:
	NetworkManager.disconnect_from_lobby()
	status_label.text = message
	_reset_lobby_buttons()
	_focus_room_code(select_code)


func _on_lobby_connection_failed():
	if not _pending_lobby_action.is_empty() and not _connecting_to_room:
		_return_to_room_entry(Locale.t("lobby.could_not_reach"))


func _on_game_connection_failed():
	var message := _lost_room_message_key() if waiting_ui else "lobby.could_not_reach_port"
	if _connecting_to_room:
		match NetworkManager.last_game_connection_failure():
			"invalid_token", "already_authenticated": message = "lobby.room_assignment_expired"
			"slot_in_use": message = "lobby.room_slot_in_use"
			"protocol_mismatch": message = "lobby.room_protocol_mismatch"
	var focus_server_settings := message == "lobby.room_protocol_mismatch" and not _cancelling_connection
	_return_to_room_entry(Locale.t(message))
	if focus_server_settings:
		_focus_server_address()


func _on_reconnect_failed(_reason: String) -> void:
	NetworkManager.clear_room_session()
	_on_game_connection_failed()


func _lost_room_message_key() -> String:
	if cancelling_preparation and preparation_reset_reason.is_empty():
		return "lobby.cancel_ready_connection_lost"
	return "lobby.lost_game_room"


func _on_opponent_disconnected(_player: int) -> void:
	if waiting_ui:
		if not NetworkManager.has_live_server_room():
			_return_to_room_entry(Locale.t(_lost_room_message_key()))
			return
		_reset_room_preparation()
		waiting_ui.get_node("WaitLabel").text = "对手已离开，可邀请新玩家加入" if Locale.language == "zh" else "Opponent left. Invite another player."


func _on_room_host_changed() -> void:
	_my_player = 1
	if waiting_ui:
		_reset_room_preparation()
		waiting_ui._update_state()


func _reset_room_preparation() -> void:
	_start_confirmation_timer.stop()
	i_am_ready = false
	cancelling_preparation = false
	_focus_ready_on_recovery = false
	preparation_reset_reason = ""
	opponent_ready = false
	_battle_starting = false
	_art_wait_deadline = 0.0
	_opponent_arts_received = 0
	_opponent_arts_total = -1
	_my_arts_acked = 0
	_my_arts_total = -1
	_acked_my_art_indices.clear()
	_pending_opponent_art_paths.clear()
	NetworkManager.clear_room_art_transfers()
	PlayerData.set_online_opponent_deck([])
	match_agreement.reset()
	set_process(false)


func _on_room_preparation_reset(reason: String) -> void:
	if waiting_ui:
		var requested_cancel := reason == "cancelled" and cancelling_preparation
		_reset_room_preparation()
		if requested_cancel and NetworkManager.room_link_waiting():
			_focus_ready_on_recovery = true
		elif requested_cancel or reason in ["offer_mismatch", "start_timeout"]:
			_focus_ready_after_preparation_reset.call_deferred()


func _on_room_link_wait_changed() -> void:
	if _focus_ready_on_recovery and not NetworkManager.room_link_waiting():
		_focus_ready_on_recovery = false
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or focus == start_btn:
			_focus_ready_after_preparation_reset.call_deferred()


func _focus_ready_after_preparation_reset() -> void:
	if not is_instance_valid(waiting_ui) or waiting_ui._blocks_match_confirmation() or UIMotion.top_popup() != null:
		return
	waiting_ui._update_state()
	if not start_btn.disabled:
		start_btn.grab_focus()


func cancel_match_preparation(reason: String = "") -> void:
	if can_cancel_preparation():
		_request_preparation_reset(reason)


func _request_preparation_reset(reason: String) -> void:
	var details := [reason] if not reason.is_empty() else []
	if NetworkManager.send_room_preparation("cancel", details) == OK:
		cancelling_preparation = true
		preparation_reset_reason = reason
		start_btn.disabled = true
		waiting_ui._update_state()


func can_cancel_preparation() -> bool:
	return i_am_ready and _can_submit_ready() and not cancelling_preparation and not match_agreement.completed


func can_return_to_preparation() -> bool:
	return (match_agreement.completed and _start_confirmation_timer.is_stopped()
		and _room_allows_preparation() and not NetworkManager.room_link_waiting()
		and not NetworkManager.room_departure_pending and not cancelling_preparation)


func _return_to_room_entry(message: String) -> void:
	var previous_code := NetworkManager.room_code
	var previous_address := NetworkManager.room_server_address
	var checking_server := _pending_lobby_action == "status"
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	_show_room_entry(message, previous_code, previous_address, checking_server)


func _exit_waiting_room() -> void:
	var previous_code := NetworkManager.room_code
	var previous_address := NetworkManager.room_server_address
	PlayerData.return_to_waiting_room = false
	if not await NetworkManager.leave_online_room() or not is_inside_tree():
		return
	_show_room_entry(Locale.t("lobby.room_left"), previous_code, previous_address)


func _show_room_entry(message: String, previous_code: String, previous_address: String, checking_server: bool = false) -> void:
	_reset_room_preparation()
	var was_waiting := is_instance_valid(waiting_ui)
	if was_waiting:
		waiting_ui.hide()
		waiting_ui.queue_free()
		waiting_ui = null
	start_btn = null
	create_card_btn = null
	if not previous_code.is_empty():
		room_input.text = previous_code
	if not previous_address.is_empty():
		server_input.text = previous_address
	lobby_panel.visible = true
	back_btn.visible = true
	status_label.text = Locale.t("lobby.connection_cancelled") if _cancelling_connection else message
	_reset_lobby_buttons()
	if checking_server:
		var focus_target: Control = server_input if server_input.is_visible_in_tree() else _server_settings
		focus_target.grab_focus()
	else:
		_focus_room_code()
	if was_waiting:
		UIMotion.reveal_view(self)


func _connect_assigned_room(data: Dictionary, wait_for_start: bool) -> void:
	_connecting_to_room = true
	if not _cancelling_connection:
		status_label.text = Locale.t("lobby.waiting_room_connecting")
	_resize_panel_to_content.call_deferred(_ui_scale())
	var attempt := _connection_attempt
	if wait_for_start:
		await get_tree().create_timer(0.3).timeout
	if not is_inside_tree() or attempt != _connection_attempt:
		return
	_my_player = int(data.get("player", 0))
	NetworkManager.server_allows_card_art = bool(data.get("card_art", false))
	var error := NetworkManager.connect_to_game_room(_request_server_address, int(data.get("port", 0)), _my_player, _pending_room_code, str(data.get("reconnect_token", "")))
	if error != OK:
		_on_game_connection_failed()


func _on_room_authenticated(_player: int, _resumed: bool) -> void:
	if not _connecting_to_room:
		return
	_join_attempt_target.clear()
	_join_attempt_id = ""
	_reservation_request_pending = false
	if _cancelling_connection:
		_cancel_handoff_timer.stop()
		var attempt := _connection_attempt
		await NetworkManager.leave_online_room()
		if is_inside_tree() and attempt == _connection_attempt:
			_return_to_room_entry(Locale.t("lobby.connection_cancelled"))
		return
	_reset_lobby_buttons()
	_show_waiting_room()


func _on_lobby_response_create(data: Dictionary):
	var status: String = data.get("status", "")
	if status == "ok":
		_connect_assigned_room(data, true)
		return
	elif _cancelling_connection:
		_return_to_room_entry(Locale.t("lobby.connection_cancelled"))
		return
	if status == "taken" and _generated_room_code and _room_code_retries < 4:
		_room_code_retries += 1
		var previous := _pending_room_code
		while _pending_room_code == previous:
			_pending_room_code = _new_room_code()
		room_input.text = _pending_room_code
		NetworkManager.create_room(_pending_room_code)
		return
	var message: String
	match status:
		"taken": message = Locale.t("lobby.room_taken", [_pending_room_code])
		"invalid_code": message = Locale.t("lobby.invalid_code")
		"no_ports": message = Locale.t("lobby.server_full")
		"protocol_mismatch":
			_finish_lobby_protocol_mismatch(data)
			return
		_: message = Locale.t("lobby.unknown_response", [status])
	_finish_room_code_request(message, status in ["taken", "invalid_code"])



func _on_join_pressed():
	if join_btn.disabled: return
	var code: String = room_input.text.strip_edges()
	if code == "":
		_show_entry_message(Locale.t("lobby.enter_room_first"))
		_focus_room_code()
		return
	if not NetworkManager.is_valid_room_code(code):
		_show_entry_message(Locale.t("lobby.invalid_code"))
		_focus_room_code(true)
		return
	_pending_room_code = code
	_connect_to_lobby("join", _on_lobby_response_join)



func _on_lobby_response_join(data: Dictionary):
	var status: String = data.get("status", "")
	if status == "ok":
		_connect_assigned_room(data, false)
		return
	elif _cancelling_connection:
		_return_to_room_entry(Locale.t("lobby.connection_cancelled"))
		return
	var message: String
	match status:
		"full":
			var key := "lobby.room_seat_reserved" if data.get("seat_reserved", false) == true else "lobby.room_full"
			message = Locale.t(key, [_pending_room_code])
		"not_found": message = Locale.t("lobby.room_not_found", [_pending_room_code])
		"in_progress", "room_starting": message = Locale.t("lobby." + status)
		"invalid_code": message = Locale.t("lobby.invalid_code")
		"protocol_mismatch":
			_finish_lobby_protocol_mismatch(data)
			return
		_: message = Locale.t("lobby.unknown_response", [status])
	_finish_room_code_request(message, status in ["not_found", "invalid_code"])



func _on_check_server_pressed():
	if not check_server_btn.disabled:
		_connect_to_lobby("status", _on_lobby_status_response)


func _on_lobby_status_response(data: Dictionary):
	if str(data.get("status", "")) == "protocol_mismatch":
		_finish_lobby_protocol_mismatch(data)
		return
	status_label.text = Locale.t("lobby.server_status", [
		int(data.get("rooms", 0)), int(data.get("port_start", 0)), int(data.get("port_end", 0)),
	])
	NetworkManager.disconnect_from_lobby()
	_reset_lobby_buttons()
	var focus_target: Control = check_server_btn if check_server_btn.is_visible_in_tree() else _server_settings
	focus_target.grab_focus()


# ============================================
# Existing: opponent joined → waiting room → start → battle
# ============================================

func _on_opponent_joined():
	if waiting_ui and start_btn and not i_am_ready:
		start_btn.disabled = NetworkManager.room_link_waiting() or not _can_submit_ready()


func _show_waiting_room(initial_message: String = ""):
	var was_entry: bool = lobby_panel.visible
	if _pending_room_code.is_empty(): _pending_room_code=NetworkManager.room_code
	if NetworkManager.has_live_server_room() and not _pending_room_code.is_empty():
		_remember_entry_draft(_pending_room_code, NetworkManager.room_server_address)
	if is_instance_valid(waiting_ui): waiting_ui.queue_free()
	lobby_panel.hide()
	back_btn.hide()
	var room := preload("res://presentation/OnlineRoomPanel.gd").new()
	waiting_ui=room
	add_child(room)
	room.setup(self,_pending_room_code,initial_message)
	start_btn=room.start_button
	create_card_btn=room.create_button
	if was_entry:
		UIMotion.reveal_view(self)


func _on_create_card_pressed():
	if not NetworkManager.edit_card_from_server_room():
		return
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = PlayerData.online_room_deck_id
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft.clear()
	PlayerData.card_editor_return_scene = "res://DedicatedLobby.tscn"
	PlayerData.return_to_waiting_room = true
	UIMotion.change_scene("res://CardEditor.tscn")


func _room_allows_preparation() -> bool:
	return NetworkManager.is_game_rpc_ready() and NetworkManager.room_preparation_available


func _can_submit_ready() -> bool:
	return _room_allows_preparation() and (not is_instance_valid(waiting_ui) or not waiting_ui.waiting_for_host_rules())


func _on_start_pressed():
	if can_return_to_preparation():
		_request_preparation_reset("start_timeout")
		return
	if i_am_ready:
		cancel_match_preparation()
		return
	if PlayerData.battle_deck.is_empty() or _battle_starting:
		return
	if NetworkManager.room_link_waiting() or not _can_submit_ready():
		if start_btn:
			start_btn.disabled = true
		return
	var card_data_list: Array = waiting_ui.serialize_ready_deck()
	if card_data_list.is_empty():
		return
	i_am_ready = true
	start_btn.disabled = true
	var wait_label = waiting_ui.get_node_or_null("WaitLabel")
	if wait_label: wait_label.text = Locale.t("wait.waiting_opponent")

	if NetworkManager.is_online:
		NetworkManager.send_room_preparation("ready", card_data_list)
		await get_tree().process_frame
		if not i_am_ready:
			return
		if _card_art_disabled():
			_opponent_arts_total = 0
		else:
			_send_card_arts()
	else:
		_start_battle()

	_check_both_ready()


# True when no card-art transfer will happen: relay mode where the server
# didn't opt in. Direct P2P and art-enabled relay both transfer art.
func _card_art_disabled() -> bool:
	return NetworkManager.is_dedicated_server and not NetworkManager.server_allows_card_art


func _send_card_arts() -> void:
	var arts := PlayerData.card_art_transfers(PlayerData.battle_deck)
	_my_arts_total = arts.size()
	_my_arts_acked = 0
	_acked_my_art_indices.clear()
	NetworkManager.send_card_arts(arts)


func card_data_list_indices() -> Array:
	var result: Array = []
	for idx in range(PlayerData.battle_deck.size()):
		result.append(idx)
	return result


func _on_rpc_ready(card_data_list: Array):
	# The host may ready up before its rules reach the guest.
	if not _room_allows_preparation():
		return
	var decoded := PlayerData.deserialize_battle_deck_payload(card_data_list)
	if not bool(decoded.get("ok", false)):
		opponent_ready = false
		NetworkManager.send_room_preparation("invalid_deck")
		push_warning("Rejected unsafe opponent deck: %s" % [decoded.get("errors", [])])
		return
	opponent_ready = true
	PlayerData.set_online_opponent_deck(decoded.get("cards", []))
	_apply_pending_opponent_arts()
	_check_both_ready()


func _apply_pending_opponent_arts() -> void:
	for index in _pending_opponent_art_paths:
		PlayerData.apply_received_art(PlayerData.opponent_battle_deck,int(index),str(_pending_opponent_art_paths[index]))


func _on_card_art_manifest(total: int):
	_opponent_arts_total = total
	if _opponent_arts_total >= 0 and _opponent_arts_received >= _opponent_arts_total:
		_art_wait_deadline = 0.0
		_check_both_ready()


func _on_card_art_received(card_index: int, ext: String, bytes: PackedByteArray, total: int):
	_opponent_arts_total = total
	var saved_path := PlayerData.save_net_art(bytes, ext)
	if saved_path != "" and card_index >= 0:
		_pending_opponent_art_paths[card_index] = saved_path
		PlayerData.apply_received_art(PlayerData.opponent_battle_deck,card_index,saved_path)
		NetworkManager.send_card_art_ack(card_index, total)
	_opponent_arts_received += 1
	if _art_transfer_complete():
		_art_wait_deadline = 0.0
		_check_both_ready()


func _on_card_art_ack(card_index: int, total: int) -> void:
	_my_arts_total = total
	if card_index >= 0 and not _acked_my_art_indices.has(card_index):
		_acked_my_art_indices[card_index] = true
		_my_arts_acked += 1
	if _art_transfer_complete():
		_art_wait_deadline = 0.0
		_check_both_ready()


func _art_transfer_complete() -> bool:
	var opponent_done := _opponent_arts_total >= 0 and _opponent_arts_received >= _opponent_arts_total
	var mine_done := _my_arts_total >= 0 and _my_arts_acked >= _my_arts_total
	return opponent_done and mine_done


func _check_both_ready():
	if not (i_am_ready and opponent_ready) or _battle_starting or match_agreement.pending:
		return
	if _card_art_disabled():
		_begin_start()
		return
	if not _art_transfer_complete():
		if _art_wait_deadline <= 0.0:
			_art_wait_deadline = (Time.get_ticks_msec() / 1000.0) + ART_WAIT_TIMEOUT
			set_process(true)
		return
	_begin_start()


func _process(_delta: float) -> void:
	if _art_wait_deadline > 0.0 and (Time.get_ticks_msec() / 1000.0) >= _art_wait_deadline:
		_begin_start(true)


func _begin_start(card_art_pending: bool = false) -> void:
	_art_wait_deadline = 0.0
	set_process(false)
	if NetworkManager.is_online:
		match_agreement.begin(card_art_pending)
	else:
		_continue_agreed_start()


func _continue_agreed_start() -> void:
	if _battle_starting:
		return
	_battle_starting = true
	_art_wait_deadline = 0.0
	set_process(false)
	await get_tree().create_timer(0.3).timeout
	if not _battle_starting or not _can_submit_ready():
		return
	_start_battle()


func _start_battle():
	if NetworkManager.is_authority() and _can_submit_ready():
		NetworkManager.send_room_preparation("start", [match_agreement.offer.get("id", "")])


func _on_battle_start(match_id: String, starting_player: int):
	if not waiting_ui or not match_agreement.local_accepted or NetworkManager.room_departure_pending:
		return
	if match_id != match_agreement.offer.get("id", ""):
		return
	_start_confirmation_timer.stop()
	NetworkManager.mark_match_started(match_id, starting_player)
	UIMotion.change_scene("res://Main.tscn")


func _on_back_pressed():
	if is_instance_valid(waiting_ui):
		waiting_ui.request_leave()
		return
	if not _pending_lobby_action.is_empty():
		if not _cancelling_connection:
			if _reservation_request_pending:
				_cancel_room_handoff()
			else:
				_return_to_room_entry(Locale.t("lobby.connection_cancelled"))
		return
	_remember_entry_draft(room_input.text, server_input.text)
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	UIMotion.go_back("res://MainMenu.tscn")


func _remember_entry_draft(code: String, address: String) -> void:
	_entry_draft = {
		"room_code": code,
		"server_address": address,
		"server_settings_open": _server_settings.button_pressed,
	}


func _cancel_room_handoff() -> void:
	_cancelling_connection = true
	back_btn.disabled = true
	status_label.text = Locale.t("lobby.cancelling_connection")
	_resize_panel_to_content.call_deferred(_ui_scale())
	_cancel_handoff_timer.start(CANCEL_HANDOFF_TIMEOUT)


func _on_cancel_handoff_timeout() -> void:
	if _cancelling_connection and _reservation_request_pending:
		_return_to_room_entry(Locale.t("lobby.connection_cancelled"))

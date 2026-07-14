extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)

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


func _apply_texts() -> void:
	title_label.text = Locale.t("lobby.title")
	server_label.text = Locale.t("lobby.server")
	room_label.text = Locale.t("lobby.room_code")
	room_input.placeholder_text = Locale.t("lobby.room_placeholder")
	create_btn.text = Locale.t("lobby.create")
	join_btn.text = Locale.t("lobby.join")
	check_server_btn.text = Locale.t("lobby.check_server")
	back_btn.text = Locale.t("common.back")

var card_ui_scene = preload("res://CardUI.tscn")
var selected_indices: Array = []
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
var waiting_ui: Control
var start_btn: Button
var create_card_btn: Button
var start_now_btn: Button
var _my_player: int = 0
var _pending_room_code: String = ""
var _pending_lobby_action: String = ""


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
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
			if child.name == "TitleLabel":
				child.add_theme_font_size_override("font_size", max(14, int(24 * s)))
			elif child.name == "StatusLabel":
				# Long error messages must wrap instead of stretching the panel wide.
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				child.custom_minimum_size = Vector2(360 * s, 0)
				child.size_flags_horizontal = Control.SIZE_FILL
		elif child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is LineEdit:
			child.custom_minimum_size = Vector2(200 * s, 0)

	# Size the panel to fit its contents (avoids buttons overflowing the dark panel).
	_resize_panel_to_content.call_deferred(s)

	if waiting_ui:
		_scale_waiting_room(s)


func _resize_panel_to_content(s: float) -> void:
	var vbox := $Panel/VBoxContainer
	var content: Vector2 = vbox.get_combined_minimum_size()
	var pad := 24.0 * s
	var half_w: float = max(200.0 * s, content.x * 0.5 + pad)
	var half_h: float = max(150.0 * s, content.y * 0.5 + pad)
	lobby_panel.offset_left = -half_w
	lobby_panel.offset_top = -half_h
	lobby_panel.offset_right = half_w
	lobby_panel.offset_bottom = half_h


func _scale_waiting_room(s: float) -> void:
	for child in waiting_ui.get_children():
		if child is Button and child.name == "ExitButton":
			child.offset_left = 10.0 * s
			child.offset_top = 10.0 * s
			child.offset_right = child.offset_left + 120.0 * s
			child.offset_bottom = child.offset_top + 40.0 * s
			child.custom_minimum_size = Vector2(120, 40) * s
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is Button and child.name == "CreateCardButton":
			child.offset_left = 140.0 * s
			child.offset_top = 10.0 * s
			child.offset_right = child.offset_left + 120.0 * s
			child.offset_bottom = child.offset_top + 40.0 * s
			child.custom_minimum_size = Vector2(120, 40) * s
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is Label and child.name == "WaitLabel":
			child.offset_bottom = 60.0 * s
			child.custom_minimum_size = Vector2(0, 60.0 * s)
			child.add_theme_font_size_override("font_size", max(12, int(18 * s)))
		elif child is ScrollContainer:
			for grid_child in child.get_children():
				if grid_child is GridContainer:
					grid_child.add_theme_constant_override("h_separation", int(8 * s))
					grid_child.add_theme_constant_override("v_separation", int(8 * s))
					for card_box in grid_child.get_children():
						if card_box is VBoxContainer:
							card_box.custom_minimum_size = Vector2(160, 220) * s
							for box_child in card_box.get_children():
								if box_child.has_method("apply_ui_scale"):
									box_child.apply_ui_scale(s)
								elif box_child is CheckBox:
									box_child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is Button and child.name == "StartButton":
			child.custom_minimum_size = Vector2(120, 50) * s
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is Button and child.name == "StartNowButton":
			child.offset_bottom = 56.0 * s
			child.custom_minimum_size = Vector2(160, 56) * s
			child.add_theme_font_size_override("font_size", max(12, int(18 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	check_server_btn.pressed.connect(_on_check_server_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	NetworkManager.connected.connect(_on_opponent_joined)
	NetworkManager.lobby_connected.connect(_on_lobby_connected)
	NetworkManager.lobby_connection_failed.connect(_on_lobby_connection_failed)
	NetworkManager.game_connection_failed.connect(_on_game_connection_failed)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	EventBus.rpc_ready_received.connect(_on_rpc_ready)
	NetworkManager.game_started.connect(_on_battle_start)
	EventBus.rpc_card_art_received.connect(_on_card_art_received)
	EventBus.rpc_card_art_manifest_received.connect(_on_card_art_manifest)
	EventBus.rpc_card_art_ack_received.connect(_on_card_art_ack)
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_process(false)
	if PlayerData.return_to_waiting_room:
		PlayerData.return_to_waiting_room = false
		_show_waiting_room()


# ============================================
# Create / Join room
# ============================================

func _on_create_pressed():
	var code: String = room_input.text.strip_edges()
	if code == "":
		status_label.text = Locale.t("lobby.enter_room_first")
		return
	if not NetworkManager.is_valid_room_code(code):
		status_label.text = Locale.t("lobby.invalid_code")
		return
	_pending_room_code = code
	_pending_lobby_action = "create"

	var server_ip: String = server_input.text.strip_edges()
	if server_ip == "":
		server_ip = "127.0.0.1"

	status_label.text = Locale.t("lobby.connecting_lobby")
	create_btn.disabled = true
	join_btn.disabled = true
	check_server_btn.disabled = true

	var err = NetworkManager.connect_to_lobby(server_ip, Callable(self, "_on_lobby_response_create"))
	if err != OK:
		status_label.text = Locale.t("lobby.failed_connect_lobby", [err])
		_reset_lobby_buttons()


func _on_lobby_connected():
	if _pending_lobby_action == "create":
		status_label.text = Locale.t("lobby.creating_room")
		NetworkManager.create_room(_pending_room_code)
	elif _pending_lobby_action == "join":
		status_label.text = Locale.t("lobby.joining_room")
		NetworkManager.join_room(_pending_room_code)
	elif _pending_lobby_action == "status":
		status_label.text = Locale.t("lobby.checking_status")
		NetworkManager.request_lobby_status(Callable(self, "_on_lobby_status_response"))


func _reset_lobby_buttons():
	create_btn.disabled = false
	join_btn.disabled = false
	check_server_btn.disabled = false


func _on_lobby_connection_failed():
	# Fired when the lobby server is unreachable / timed out / refused.
	# Don't clobber a successful status message that may have already shown.
	if _pending_lobby_action != "":
		status_label.text = Locale.t("lobby.could_not_reach")
	_pending_lobby_action = ""
	_reset_lobby_buttons()
	_resize_panel_to_content.call_deferred(_ui_scale())


func _on_game_connection_failed():
	# Fired when reconnecting to the assigned game room port fails.
	if waiting_ui:
		var wait_label = waiting_ui.get_node_or_null("WaitLabel")
		if wait_label:
			wait_label.text = Locale.t("lobby.lost_game_room")
	else:
		status_label.text = Locale.t("lobby.could_not_reach_port")
		_resize_panel_to_content.call_deferred(_ui_scale())
	_pending_lobby_action = ""
	_reset_lobby_buttons()


func _on_reconnect_failed(_reason: String) -> void:
	NetworkManager.clear_room_session()
	_on_game_connection_failed()


func _on_lobby_response_create(data: Dictionary):
	var status: String = data.get("status", "")
	if status == "ok":
		var port: int = data.get("port", 0)
		var player: int = data.get("player", 1)
		var token := str(data.get("reconnect_token", ""))
		_my_player = player
		NetworkManager.server_allows_card_art = bool(data.get("card_art", false))
		var server_ip: String = server_input.text.strip_edges()
		if server_ip == "": server_ip = "127.0.0.1"
		status_label.text = Locale.t("lobby.room_created", [_pending_room_code])
		await get_tree().create_timer(0.3).timeout
		var err = NetworkManager.connect_to_game_room(server_ip, port, player, _pending_room_code, token)
		if err != OK:
			status_label.text = Locale.t("lobby.failed_join_room", [err])
			_reset_lobby_buttons()
		else:
			_show_waiting_room()
	elif status == "taken":
		status_label.text = Locale.t("lobby.room_taken", [_pending_room_code])
		_reset_lobby_buttons()
	elif status == "invalid_code":
		status_label.text = Locale.t("lobby.server_rejected_code")
		_reset_lobby_buttons()
	elif status == "no_ports":
		status_label.text = Locale.t("lobby.server_full")
		_reset_lobby_buttons()
	else:
		status_label.text = Locale.t("lobby.unknown_response", [status])
		_reset_lobby_buttons()


func _on_join_pressed():
	var code: String = room_input.text.strip_edges()
	if code == "":
		status_label.text = Locale.t("lobby.enter_room_first")
		return
	if not NetworkManager.is_valid_room_code(code):
		status_label.text = Locale.t("lobby.invalid_code")
		return
	_pending_room_code = code
	_pending_lobby_action = "join"

	var server_ip: String = server_input.text.strip_edges()
	if server_ip == "":
		server_ip = "127.0.0.1"

	status_label.text = Locale.t("lobby.connecting_lobby")
	create_btn.disabled = true
	join_btn.disabled = true
	check_server_btn.disabled = true

	var err = NetworkManager.connect_to_lobby(server_ip, Callable(self, "_on_lobby_response_join"))
	if err != OK:
		status_label.text = Locale.t("lobby.failed_connect_lobby", [err])
		_reset_lobby_buttons()


func _on_lobby_response_join(data: Dictionary):
	var status: String = data.get("status", "")
	if status == "ok":
		var port: int = data.get("port", 0)
		var player: int = data.get("player", 2)
		var token := str(data.get("reconnect_token", ""))
		_my_player = player
		NetworkManager.server_allows_card_art = bool(data.get("card_art", false))
		var server_ip: String = server_input.text.strip_edges()
		if server_ip == "": server_ip = "127.0.0.1"
		status_label.text = Locale.t("lobby.joined_room", [_pending_room_code])
		await get_tree().create_timer(0.3).timeout
		var err = NetworkManager.connect_to_game_room(server_ip, port, player, _pending_room_code, token)
		if err != OK:
			status_label.text = Locale.t("lobby.failed_join_room", [err])
			_reset_lobby_buttons()
		else:
			_show_waiting_room()
	elif status == "not_found":
		status_label.text = Locale.t("lobby.room_not_found", [_pending_room_code])
		_reset_lobby_buttons()
	elif status == "full":
		status_label.text = Locale.t("lobby.room_full", [_pending_room_code])
		_reset_lobby_buttons()
	elif status == "invalid_code":
		status_label.text = Locale.t("lobby.server_rejected_code")
		_reset_lobby_buttons()
	else:
		status_label.text = Locale.t("lobby.unknown_response", [status])
		_reset_lobby_buttons()


func _on_check_server_pressed():
	var server_ip: String = server_input.text.strip_edges()
	if server_ip == "":
		server_ip = "127.0.0.1"
	_pending_lobby_action = "status"
	status_label.text = Locale.t("lobby.connecting_server")
	create_btn.disabled = true
	join_btn.disabled = true
	check_server_btn.disabled = true
	var err = NetworkManager.connect_to_lobby(server_ip, Callable(self, "_ignore_lobby_response"))
	if err != OK:
		status_label.text = Locale.t("lobby.server_disconnected", [err])
		_reset_lobby_buttons()


func _ignore_lobby_response(_data: Dictionary):
	pass


func _on_lobby_status_response(data: Dictionary):
	var rooms: int = int(data.get("rooms", 0))
	var port_start: int = int(data.get("port_start", 0))
	var port_end: int = int(data.get("port_end", 0))
	status_label.text = Locale.t("lobby.server_status", [rooms, port_start, port_end])
	_pending_lobby_action = ""
	NetworkManager.disconnect_from_lobby()
	_reset_lobby_buttons()


# ============================================
# Existing: opponent joined → waiting room → start → battle
# ============================================

func _on_opponent_joined():
	if waiting_ui:
		var wait_label = waiting_ui.get_node_or_null("WaitLabel")
		if wait_label:
			wait_label.text = Locale.t("lobby.opponent_joined_pick", [_pending_room_code])
		return
	status_label.text = Locale.t("lobby.opponent_connected")
	await get_tree().create_timer(0.5).timeout
	_show_waiting_room()


func _show_waiting_room():
	var s := _ui_scale()
	lobby_panel.visible = false
	back_btn.visible = false

	waiting_ui = Control.new()
	waiting_ui.anchor_right = 1.0
	waiting_ui.anchor_bottom = 1.0
	add_child(waiting_ui)

	var exit_btn := Button.new()
	exit_btn.text = Locale.t("wait.exit")
	exit_btn.name = "ExitButton"
	exit_btn.anchor_left = 0.0
	exit_btn.anchor_top = 0.0
	exit_btn.anchor_right = 0.0
	exit_btn.anchor_bottom = 0.0
	exit_btn.offset_left = 10.0 * s
	exit_btn.offset_top = 10.0 * s
	exit_btn.offset_right = exit_btn.offset_left + 120.0 * s
	exit_btn.offset_bottom = exit_btn.offset_top + 40.0 * s
	exit_btn.custom_minimum_size = Vector2(120, 40) * s
	exit_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	exit_btn.pressed.connect(func():
		NetworkManager.close_connection()
		NetworkManager.clear_room_session()
		get_tree().change_scene_to_file("res://MainMenu.tscn")
	)
	waiting_ui.add_child(exit_btn)

	create_card_btn = Button.new()
	create_card_btn.text = Locale.t("wait.create_card")
	create_card_btn.name = "CreateCardButton"
	create_card_btn.anchor_left = 0.0
	create_card_btn.anchor_top = 0.0
	create_card_btn.anchor_right = 0.0
	create_card_btn.anchor_bottom = 0.0
	create_card_btn.offset_left = 140.0 * s
	create_card_btn.offset_top = 10.0 * s
	create_card_btn.offset_right = create_card_btn.offset_left + 120.0 * s
	create_card_btn.offset_bottom = create_card_btn.offset_top + 40.0 * s
	create_card_btn.custom_minimum_size = Vector2(120, 40) * s
	create_card_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	create_card_btn.pressed.connect(_on_create_card_pressed)
	waiting_ui.add_child(create_card_btn)

	var wait_label := Label.new()
	wait_label.text = Locale.t("wait.select_start")
	wait_label.name = "WaitLabel"
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Anchor a top band and give it explicit offsets/height. Without offsets a
	# partially-anchored Label collapses to zero height and the text never shows.
	wait_label.anchor_left = 0.2
	wait_label.anchor_right = 0.8
	wait_label.anchor_top = 0.05
	wait_label.anchor_bottom = 0.05
	wait_label.offset_top = 0.0
	wait_label.offset_bottom = 60.0 * s
	wait_label.custom_minimum_size = Vector2(0, 60.0 * s)
	wait_label.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	wait_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	waiting_ui.add_child(wait_label)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.05
	scroll.anchor_right = 0.95
	scroll.anchor_top = 0.1
	scroll.anchor_bottom = 0.85
	waiting_ui.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(8 * s))
	grid.add_theme_constant_override("v_separation", int(8 * s))
	scroll.add_child(grid)

	for i in range(PlayerData.card_library.size()):
		var card_data: CardData = PlayerData.card_library[i]
		var idx: int = i

		var card_box := VBoxContainer.new()
		card_box.custom_minimum_size = Vector2(160, 220) * s

		var cui := card_ui_scene.instantiate()
		grid.add_child(card_box)
		card_box.add_child(cui)
		cui.set_card(card_data)
		cui.set_actions_visible(false)
		cui.apply_ui_scale(s)

		var check := CheckBox.new()
		check.text = Locale.t("wait.select")
		check.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		check.pressed.connect(func():
			if not selected_indices.has(idx):
				selected_indices.append(idx)
			else:
				selected_indices.erase(idx)
		)
		card_box.add_child(check)

	start_btn = Button.new()
	start_btn.text = Locale.t("wait.start_game")
	start_btn.name = "StartButton"
	start_btn.anchor_left = 0.8
	start_btn.anchor_top = 0.9
	start_btn.anchor_right = 0.97
	start_btn.anchor_bottom = 0.97
	start_btn.custom_minimum_size = Vector2(120, 50) * s
	start_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	start_btn.pressed.connect(_on_start_pressed)
	waiting_ui.add_child(start_btn)


func _on_create_card_pressed():
	PlayerData.editing_index = -1
	PlayerData.card_draft.clear()
	PlayerData.card_editor_return_scene = "res://Lobby.tscn"
	PlayerData.return_to_waiting_room = true
	get_tree().change_scene_to_file("res://CardEditor.tscn")


func _on_start_pressed():
	if selected_indices.is_empty():
		return
	i_am_ready = true
	start_btn.disabled = true
	var wait_label = waiting_ui.get_node_or_null("WaitLabel")
	if wait_label: wait_label.text = Locale.t("wait.waiting_opponent")

	PlayerData.battle_deck.clear()
	for idx in selected_indices:
		if idx >= 0 and idx < PlayerData.card_library.size():
			PlayerData.battle_deck.append(PlayerData.card_library[idx].duplicate_card())

	if NetworkManager.is_online:
		var card_data_list: Array = []
		for idx in selected_indices:
			if idx >= 0 and idx < PlayerData.card_library.size():
				card_data_list.append(PlayerData.serialize_card(PlayerData.card_library[idx]))
		NetworkManager.rpc_player_ready.rpc(card_data_list)
		await get_tree().process_frame
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
	var arts: Array = []
	var indices: Array = card_data_list_indices()
	for i in range(indices.size()):
		var card: CardData = PlayerData.card_library[indices[i]]
		var bytes := PlayerData.read_art_bytes(card.art_path)
		if bytes.is_empty():
			continue
		arts.append({
			"card_index": i,
			"ext": card.art_path.get_extension(),
			"bytes": bytes,
		})
	_my_arts_total = arts.size()
	_my_arts_acked = 0
	_acked_my_art_indices.clear()
	NetworkManager.send_card_arts(arts)


func card_data_list_indices() -> Array:
	var result: Array = []
	for idx in selected_indices:
		if idx >= 0 and idx < PlayerData.card_library.size():
			result.append(idx)
	return result


func _on_rpc_ready(card_data_list: Array):
	opponent_ready = true
	PlayerData.opponent_battle_deck.clear()
	for data in card_data_list:
		PlayerData.opponent_battle_deck.append(PlayerData.deserialize_card(data))
	_apply_pending_opponent_arts()
	_check_both_ready()


func _apply_pending_opponent_arts() -> void:
	for card_index in _pending_opponent_art_paths.keys():
		var idx := int(card_index)
		if idx >= 0 and idx < PlayerData.opponent_battle_deck.size():
			PlayerData.opponent_battle_deck[idx].art_path = str(_pending_opponent_art_paths[card_index])


func _on_card_art_manifest(total: int):
	_opponent_arts_total = total
	_update_art_progress_label()
	if _opponent_arts_total >= 0 and _opponent_arts_received >= _opponent_arts_total:
		_art_wait_deadline = 0.0
		_check_both_ready()


func _on_card_art_received(card_index: int, ext: String, bytes: PackedByteArray, total: int):
	_opponent_arts_total = total
	var saved_path := PlayerData.save_net_art(bytes, ext)
	if saved_path != "" and card_index >= 0:
		_pending_opponent_art_paths[card_index] = saved_path
		if card_index < PlayerData.opponent_battle_deck.size():
			PlayerData.opponent_battle_deck[card_index].art_path = saved_path
		NetworkManager.send_card_art_ack(card_index, total)
	_opponent_arts_received += 1
	_update_art_progress_label()
	if _art_transfer_complete():
		_art_wait_deadline = 0.0
		_check_both_ready()


func _on_card_art_ack(card_index: int, total: int) -> void:
	_my_arts_total = total
	if card_index >= 0 and not _acked_my_art_indices.has(card_index):
		_acked_my_art_indices[card_index] = true
		_my_arts_acked += 1
	_update_art_progress_label()
	if _art_transfer_complete():
		_art_wait_deadline = 0.0
		_check_both_ready()


func _update_art_progress_label() -> void:
	if not waiting_ui or not (i_am_ready and opponent_ready):
		return
	var wait_label = waiting_ui.get_node_or_null("WaitLabel")
	if not wait_label:
		return
	if _opponent_arts_total > 0 or _my_arts_total > 0:
		wait_label.text = Locale.t("wait.transfer_arts", [_opponent_arts_received, max(_opponent_arts_total, 0), _my_arts_acked, max(_my_arts_total, 0)])
	elif _opponent_arts_total == 0 and _my_arts_total == 0:
		wait_label.text = Locale.t("wait.no_arts")
	else:
		wait_label.text = Locale.t("wait.waiting_ready")


func _art_transfer_complete() -> bool:
	var opponent_done := _opponent_arts_total >= 0 and _opponent_arts_received >= _opponent_arts_total
	var mine_done := _my_arts_total >= 0 and _my_arts_acked >= _my_arts_total
	return opponent_done and mine_done


func _check_both_ready():
	if not (i_am_ready and opponent_ready) or _battle_starting:
		return
	if _card_art_disabled():
		_begin_start()
		return
	if not _art_transfer_complete():
		if _art_wait_deadline <= 0.0:
			_art_wait_deadline = (Time.get_ticks_msec() / 1000.0) + ART_WAIT_TIMEOUT
			set_process(true)
		_update_art_progress_label()
		return
	_begin_start()


func _process(_delta: float) -> void:
	if _art_wait_deadline > 0.0 and (Time.get_ticks_msec() / 1000.0) >= _art_wait_deadline:
		_art_wait_deadline = 0.0
		set_process(false)
		_show_start_now_button()


func _show_start_now_button() -> void:
	if _battle_starting or start_now_btn != null or not waiting_ui:
		return
	var s := _ui_scale()
	var wait_label = waiting_ui.get_node_or_null("WaitLabel")
	if wait_label:
		wait_label.text = Locale.t("wait.arts_slow", [_opponent_arts_received, max(_opponent_arts_total, 0)])
	start_now_btn = Button.new()
	start_now_btn.text = Locale.t("wait.enter_game")
	start_now_btn.name = "StartNowButton"
	start_now_btn.anchor_left = 0.4
	start_now_btn.anchor_right = 0.6
	start_now_btn.anchor_top = 0.5
	start_now_btn.anchor_bottom = 0.5
	start_now_btn.offset_top = 0.0
	start_now_btn.offset_bottom = 56.0 * s
	start_now_btn.custom_minimum_size = Vector2(160, 56) * s
	start_now_btn.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	start_now_btn.pressed.connect(_begin_start)
	waiting_ui.add_child(start_now_btn)


func _begin_start() -> void:
	if _battle_starting:
		return
	_battle_starting = true
	_art_wait_deadline = 0.0
	set_process(false)
	if start_now_btn != null:
		start_now_btn.disabled = true
	await get_tree().create_timer(0.3).timeout
	_start_battle()


func _start_battle():
	if NetworkManager.is_online and NetworkManager.is_authority():
		NetworkManager.rpc("_remote_start_game")
	NetworkManager.game_started.emit()


func _on_battle_start():
	NetworkManager.mark_room_match_started()
	NetworkManager.get_tree().change_scene_to_file("res://Main.tscn")


func _on_back_pressed():
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

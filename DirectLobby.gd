extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
static var _entry_draft := ""

@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var host_btn = $Panel/VBoxContainer/HostButton
@onready var join_btn = $Panel/VBoxContainer/JoinButton
@onready var ip_input = $Panel/VBoxContainer/IPInput
@onready var back_btn = $Panel/VBoxContainer/BackButton
@onready var lobby_panel = $Panel
@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var ip_label = $Panel/VBoxContainer/IPLabel
@onready var discovery_label: Label = $Panel/VBoxContainer/DiscoveryLabel
@onready var room_list: OptionButton = $Panel/VBoxContainer/RoomList
@onready var refresh_btn: Button = $Panel/VBoxContainer/RefreshButton


func _apply_texts() -> void:
	title_label.text = Locale.t("direct.title")
	host_btn.text = Locale.t("lobby.host")
	ip_label.text = Locale.t("direct.join_by_ip")
	ip_input.placeholder_text = Locale.t("direct.address_example")
	join_btn.text = Locale.t("direct.join_game")
	discovery_label.text = Locale.t("direct.rooms")
	refresh_btn.text = Locale.t("direct.refresh")
	back_btn.text = Locale.t("common.back")

var card_ui_scene = preload("res://CardUI.tscn")
var opponent_ready: bool = false
var i_am_ready: bool = false
var cancelling_preparation := false
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
var _discovered_rooms: Array = []
var _deferred_rooms: Variant = null
var _auto_pick_room := true
var _joining := false
var _join_failure_message := ""


func _apply_theme() -> void:
	# Full-screen dark backdrop, matching every other scene (the lobby's
	# content panel is centered and fixed-size, so it can't double as the bg).
	var bg := Panel.new()
	bg.name = "ThemeBackground"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(bg)
	add_child(bg)
	move_child(bg, 0)
	UITheme.apply_panel(lobby_panel, "dark")
	UITheme.apply_title(title_label, max(18, int(24 * _ui_scale())))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.get_parent().move_child(status_label, -1)
	for label in [status_label, ip_label]:
		UITheme.apply_label(label, label == status_label)
	UITheme.apply_input(ip_input)
	UITheme.apply_button(host_btn, "primary")
	UITheme.apply_button(join_btn, "secondary")
	UITheme.apply_button(refresh_btn, "secondary")
	UITheme.place_page_back(self, back_btn)


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
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
			UITheme.apply_label(child, child.name == "StatusLabel")
			if child.name == "TitleLabel":
				UITheme.apply_title(child, max(14, int(24 * s)))
			elif child.name == "StatusLabel":
				# Long error messages must wrap instead of stretching the panel wide.
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				child.custom_minimum_size = Vector2(360 * s, 0)
				child.size_flags_horizontal = Control.SIZE_FILL
		elif child is OptionButton:
			child.custom_minimum_size = Vector2(260 * s, 0)
			UITheme.apply_button(child, "secondary")
		elif child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
			UITheme.apply_button(child, "primary" if child == host_btn else "secondary")
		elif child is LineEdit:
			child.custom_minimum_size = Vector2(200 * s, 0)
			UITheme.apply_input(child)

	# Size the panel to fit its contents (avoids buttons overflowing the dark panel).
	_resize_panel_to_content.call_deferred(s)

	if waiting_ui:
		_scale_waiting_room(s)


func _resize_panel_to_content(s: float) -> void:
	var vbox := $Panel/VBoxContainer
	var content: Vector2 = vbox.get_combined_minimum_size()
	var pad := maxf(16.0, 24.0 * s)
	# Panel does not inset its children using StyleBox content margins.
	vbox.offset_left = pad
	vbox.offset_right = -pad
	vbox.offset_top = pad
	vbox.offset_bottom = -pad
	var half_w: float = max(200.0 * s, content.x * 0.5 + pad)
	var half_h: float = max(150.0 * s, content.y * 0.5 + pad)
	lobby_panel.offset_left = -half_w
	lobby_panel.offset_top = -half_h
	lobby_panel.offset_right = half_w
	lobby_panel.offset_bottom = half_h


func _scale_waiting_room(s: float) -> void:
	if is_instance_valid(waiting_ui) and waiting_ui.has_method("apply_scale"):
		waiting_ui.apply_scale(s)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


var match_agreement: MatchAgreement


func _ready():
	match_agreement = MatchAgreement.new()
	add_child(match_agreement)
	match_agreement.setup(self)
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	ip_input.text_submitted.connect(func(_value: String):
		if not join_btn.disabled:
			_on_join_pressed()
	)
	ip_input.text_changed.connect(_on_address_changed)
	back_btn.pressed.connect(_on_back_pressed)
	refresh_btn.pressed.connect(NetworkManager.refresh_lan_room_discovery)
	room_list.item_selected.connect(_on_room_selected)
	room_list.get_popup().popup_hide.connect(_apply_deferred_rooms, CONNECT_DEFERRED)
	NetworkManager.connected.connect(_on_opponent_joined)
	NetworkManager.game_connection_failed.connect(_on_game_connection_failed)
	NetworkManager.protocol_mismatch.connect(_on_protocol_mismatch)
	NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.direct_preparation_reset_received.connect(_on_direct_preparation_reset_received)
	NetworkManager.lan_opponent_editing_changed.connect(_on_lan_opponent_editing_changed)
	EventBus.rpc_ready_received.connect(_on_rpc_ready)
	EventBus.rpc_card_art_received.connect(_on_card_art_received)
	EventBus.rpc_card_art_manifest_received.connect(_on_card_art_manifest)
	EventBus.rpc_card_art_ack_received.connect(_on_card_art_ack)
	NetworkManager.game_started.connect(_on_battle_start)
	NetworkManager.lan_rooms_updated.connect(_on_lan_rooms_updated)
	_apply_texts()
	_apply_theme()
	_apply_responsive_layout()
	ip_input.text = _entry_draft
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_process(false)  # only enabled while waiting out the art-transfer timeout
	if PlayerData.return_to_waiting_room:
		PlayerData.return_to_waiting_room = false
		if NetworkManager.can_return_to_lan_room():
			_show_waiting_room()
			NetworkManager.arrive_in_lan_room()
		elif not _uses_lan_discovery() or NetworkManager.set_lan_room_editing(false):
			_show_waiting_room()
		else:
			_return_from_lost_lan_room()
			return
	if _uses_lan_discovery():
		_start_lan_discovery()
	if lobby_panel.visible and not _entry_draft.is_empty():
		ip_input.grab_focus()


func _start_lan_discovery() -> void:
	if NetworkManager.start_lan_room_discovery() != OK and status_label.text.is_empty():
		status_label.text = Locale.t("direct.discovery_unavailable")


func _on_host_pressed():
	NetworkManager.clear_room_session()
	status_label.text = Locale.t("lobby.hosting")
	host_btn.disabled = true
	join_btn.disabled = true
	var err = NetworkManager.host_game()
	if err != OK:
		status_label.text = Locale.t("lobby.failed_host", [err])
		host_btn.disabled = false
		join_btn.disabled = false
	else:
		_show_waiting_room()


func _uses_lan_discovery() -> bool:
	return true


func _on_join_pressed():
	if _joining or is_instance_valid(waiting_ui):
		return
	var ip: String = ip_input.text.strip_edges()
	if ip == "":
		_show_room_entry(Locale.t("direct.choose_room_or_address"))
		return
	NetworkManager.clear_room_session()
	var parsed := _parse_host_address(ip)
	ip = str(parsed["address"])
	var port := int(parsed["port"])
	if port < 1 or port > 65535:
		_show_room_entry(Locale.t("direct.invalid_port"))
		return
	_entry_draft = _format_host_address(ip, port)
	ip_input.text = _entry_draft
	var err = NetworkManager.join_game(ip, port)
	if err != OK:
		_finish_join_attempt(Locale.t("lobby.could_not_connect"))
		return
	_set_join_pending(true)
	status_label.text = Locale.t("lobby.joining", [_entry_draft])
	_resize_panel_to_content.call_deferred(_ui_scale())
	back_btn.grab_focus()


func _set_join_pending(pending: bool) -> void:
	_joining = pending
	host_btn.disabled = pending
	join_btn.disabled = pending
	refresh_btn.disabled = pending
	room_list.disabled = pending or _discovered_rooms.is_empty()
	ip_input.editable = not pending
	back_btn.text = Locale.t("lobby.cancel_connection" if pending else "common.back")
	if not pending:
		_join_failure_message = ""


func _on_lan_rooms_updated(rooms: Array) -> void:
	if room_list.get_popup().visible:
		_deferred_rooms = rooms.duplicate(true)
		return
	_deferred_rooms = null
	_discovered_rooms = rooms.duplicate(true)
	room_list.clear()
	for room in _discovered_rooms:
		var label := "%s（%s:%d）" % [str(room.get("name", Locale.t("direct.unnamed_host"))), str(room.get("address", "")), int(room.get("port", NetworkManager.LAN_GAME_PORT))]
		room_list.add_item(label)
	room_list.disabled = _joining or _discovered_rooms.is_empty()
	if _discovered_rooms.is_empty():
		room_list.add_item(Locale.t("direct.no_rooms"))
		room_list.select(0)
	elif _auto_pick_room and ip_input.text.strip_edges().is_empty():
		ip_input.text = _discovered_endpoint(_discovered_rooms[0])
		room_list.select(0)
	else:
		_sync_room_selection()


func _apply_deferred_rooms() -> void:
	if _deferred_rooms != null:
		_on_lan_rooms_updated(_deferred_rooms)


func _on_address_changed(_value: String) -> void:
	_auto_pick_room = false
	_sync_room_selection()


func _sync_room_selection() -> void:
	if _discovered_rooms.is_empty():
		return
	var address := _parse_host_address(ip_input.text)
	var endpoint := _format_host_address(address["address"], address["port"])
	for index in range(_discovered_rooms.size()):
		if _discovered_endpoint(_discovered_rooms[index]) == endpoint:
			room_list.select(index)
			return
	room_list.select(-1)
	room_list.text = Locale.t("direct.select_room")


func _on_room_selected(index: int) -> void:
	if index < 0 or index >= _discovered_rooms.size():
		return
	_auto_pick_room = false
	ip_input.text = _discovered_endpoint(_discovered_rooms[index])


func _discovered_endpoint(room: Dictionary) -> String:
	return _format_host_address(str(room.get("address", "")), int(room.get("port", NetworkManager.LAN_GAME_PORT)))


func _format_host_address(address: String, port: int) -> String:
	if port == NetworkManager.LAN_GAME_PORT:
		return address
	var host := "[%s]" % address if ":" in address else address
	return "%s:%d" % [host, port]


func _parse_host_address(value: String) -> Dictionary:
	var address := value.strip_edges()
	var port := NetworkManager.LAN_GAME_PORT
	var separator := address.rfind("]:") + 1 if address.begins_with("[") and "]:" in address else -1
	if separator < 0 and address.count(":") == 1:
		separator = address.find(":")
	if separator > 0:
		var suffix := address.substr(separator + 1)
		port = int(suffix) if suffix.is_valid_int() else 0
		address = address.left(separator).trim_prefix("[").trim_suffix("]")
	return {"address": address, "port": port}


func _on_opponent_joined():
	if waiting_ui:
		if start_btn and not i_am_ready:
			start_btn.disabled = not _can_submit_ready()
		var wait_label = waiting_ui.get_node_or_null("WaitLabel")
		if wait_label:
			wait_label.text = Locale.t("wait.opponent_pick")
		return
	if _joining:
		_set_join_pending(false)
		_show_waiting_room()


func _on_game_connection_failed():
	var message := _join_failure_message if not _join_failure_message.is_empty() else Locale.t("lobby.could_not_connect")
	_finish_join_attempt(message)


func _on_protocol_mismatch(remote_version: int) -> void:
	if _joining:
		_join_failure_message = Locale.t("direct.protocol_mismatch", [AppVersion.PROTOCOL_VERSION, remote_version])


func _finish_join_attempt(message: String) -> void:
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	_show_room_entry(message)
	if _uses_lan_discovery():
		_start_lan_discovery()


func _show_room_entry(message: String) -> void:
	_reset_room_preparation()
	var was_waiting := is_instance_valid(waiting_ui)
	if was_waiting:
		waiting_ui.hide()
		waiting_ui.queue_free()
		waiting_ui = null
	lobby_panel.visible = true
	back_btn.visible = true
	status_label.text = message
	_set_join_pending(false)
	ip_input.grab_focus()
	_resize_panel_to_content.call_deferred(_ui_scale())
	if was_waiting:
		UIMotion.reveal_view(self)


func _on_opponent_disconnected(_player: int) -> void:
	if _joining:
		_on_game_connection_failed()
		return
	if not is_instance_valid(waiting_ui) or PlayerData.return_to_waiting_room:
		return
	if _uses_lan_discovery():
		if NetworkManager.is_host and NetworkManager.has_live_lan_room():
			var reason := NetworkManager.room_wait_reason
			_reset_room_preparation(reason if reason == "incompatible_guest" else "opponent_left")
		else:
			_return_from_lost_lan_room()
		return
	NetworkManager.close_connection()
	_show_room_entry(Locale.t("lobby.opponent_left_waiting"))


func _return_from_lost_lan_room() -> void:
	var was_guest := NetworkManager.session_mode == NetworkManager.SESSION_MODE_LAN_CLIENT
	var address := NetworkManager.room_server_address
	var port := NetworkManager.room_server_port
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	if was_guest and not address.is_empty() and port > 0:
		_entry_draft = _format_host_address(address, port)
		ip_input.text = _entry_draft
	_show_room_entry(Locale.t("lobby.lan_host_disconnected" if was_guest else "lobby.lost_game_room"))
	_start_lan_discovery()


func _show_waiting_room(initial_message: String = ""):
	var was_entry: bool = lobby_panel.visible
	if is_instance_valid(waiting_ui): waiting_ui.queue_free()
	lobby_panel.hide()
	back_btn.hide()
	var room := preload("res://presentation/OnlineRoomPanel.gd").new()
	waiting_ui=room
	add_child(room)
	room.setup(self,"",initial_message)
	start_btn=room.start_button
	create_card_btn=room.create_button
	if was_entry:
		UIMotion.reveal_view(self)


func _on_create_card_pressed():
	if i_am_ready or _battle_starting:
		return
	if _uses_lan_discovery():
		if not NetworkManager.set_lan_room_editing(true):
			return
		_reset_room_preparation()
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = PlayerData.online_room_deck_id
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft.clear()
	PlayerData.card_editor_return_scene = scene_file_path
	PlayerData.return_to_waiting_room = true
	UIMotion.change_scene("res://CardEditor.tscn")


func _can_submit_ready() -> bool:
	return not NetworkManager.lan_room_preparation_paused() and NetworkManager.is_game_rpc_ready() and (NetworkManager.is_dedicated_server or NetworkManager._direct_protocol_verified)


func _on_start_pressed():
	if i_am_ready:
		cancel_match_preparation()
		return
	if _battle_starting or PlayerData.battle_deck.is_empty():
		return
	if not _can_submit_ready():
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
		NetworkManager.rpc_player_ready.rpc(card_data_list)
		await get_tree().process_frame
		if i_am_ready:
			_send_card_arts()
	else:
		_start_battle()

	_check_both_ready()


func can_cancel_preparation() -> bool:
	return i_am_ready and _can_submit_ready() and not cancelling_preparation and not match_agreement.completed


func cancel_match_preparation() -> void:
	if not can_cancel_preparation() or NetworkManager.rpc("rpc_player_ready", []) != OK:
		return
	if NetworkManager.is_authority():
		_reset_room_preparation("cancelled")
	else:
		cancelling_preparation = true
		start_btn.disabled = true


func _on_direct_preparation_reset_received() -> void:
	if not is_instance_valid(waiting_ui) or not _can_submit_ready():
		return
	if NetworkManager.is_authority():
		if not opponent_ready or match_agreement.completed:
			return
		NetworkManager.rpc_player_ready.rpc([])
	_reset_room_preparation("cancelled")


func _on_lan_opponent_editing_changed(editing: bool) -> void:
	if editing and is_instance_valid(waiting_ui):
		_reset_room_preparation()


func _reset_room_preparation(reason := "") -> void:
	i_am_ready = false
	opponent_ready = false
	cancelling_preparation = false
	_battle_starting = false
	_art_wait_deadline = 0.0
	_opponent_arts_received = 0
	_opponent_arts_total = -1
	_my_arts_acked = 0
	_my_arts_total = -1
	_acked_my_art_indices.clear()
	_pending_opponent_art_paths.clear()
	NetworkManager.room_wait_reason = reason
	NetworkManager.clear_room_art_transfers()
	PlayerData.set_online_opponent_deck([])
	match_agreement.reset()
	set_process(false)


# P2P-only: send each selected card's art bytes (named/dedup'd by content hash on receive).
# One RPC per art so the receiver can show per-card progress.
func _send_card_arts() -> void:
	var arts := PlayerData.card_art_transfers(PlayerData.battle_deck)
	_my_arts_total = arts.size()
	_my_arts_acked = 0
	_acked_my_art_indices.clear()
	NetworkManager.send_card_arts(arts)


# The ordered list of library indices that map 1:1 to the ready card_data_list.
func card_data_list_indices() -> Array:
	var result: Array = []
	for idx in range(PlayerData.battle_deck.size()):
		result.append(idx)
	return result


func _on_rpc_ready(card_data_list: Array):
	var decoded := PlayerData.deserialize_battle_deck_payload(card_data_list)
	if not bool(decoded.get("ok", false)):
		opponent_ready = false
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
	# Manifest arrives before the art bytes (and is the only message when the
	# opponent has 0 arts), so it's what lets us know when waiting can end.
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
		PlayerData.apply_received_art(PlayerData.opponent_battle_deck,card_index,saved_path)
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


# Card art transfer is best-effort and must never block the battle from starting.
# Once both players are ready: if arts have fully arrived (or there are none) we
# start automatically. If they're still in flight we wait up to ART_WAIT_TIMEOUT
# seconds, then surface a manual "enter game" button instead of forcing the start.
func _art_transfer_complete() -> bool:
	var opponent_done := _opponent_arts_total >= 0 and _opponent_arts_received >= _opponent_arts_total
	var mine_done := _my_arts_total >= 0 and _my_arts_acked >= _my_arts_total
	return opponent_done and mine_done


func _check_both_ready():
	if not (i_am_ready and opponent_ready) or _battle_starting or match_agreement.pending:
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
	if not is_inside_tree() or not _battle_starting or not _can_submit_ready():
		return
	_start_battle()


func _start_battle():
	var match_id := str(match_agreement.offer.get("id", ""))
	var starting_player := NetworkManager.roll_opening_player()
	if NetworkManager.is_online and NetworkManager.is_authority():
		NetworkManager.rpc("_remote_start_game", match_id, starting_player)
	NetworkManager.game_started.emit(match_id, starting_player)


func _on_battle_start(match_id: String, starting_player: int):
	if NetworkManager.is_online and (not match_agreement.local_accepted or match_id != match_agreement.offer.get("id", "")):
		return
	NetworkManager.mark_match_started(match_id, starting_player)
	UIMotion.change_scene("res://Main.tscn")


func _on_back_pressed():
	if _joining:
		_finish_join_attempt(Locale.t("direct.connection_cancelled"))
		return
	if is_instance_valid(waiting_ui):
		waiting_ui.request_leave()
		return
	_entry_draft = ip_input.text
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	UIMotion.go_back("res://MainMenu.tscn")


func _exit_waiting_room() -> void:
	PlayerData.return_to_waiting_room=false
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	UIMotion.replace_scene("res://MainMenu.tscn",true,"online")

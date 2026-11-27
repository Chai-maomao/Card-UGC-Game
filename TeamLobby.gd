extends Control

const LaunchFrame = preload("res://presentation/BattleLaunchFrame.gd")

@onready var room: Node = NetworkManager.team_room
var _entry: VBoxContainer
var _waiting: Control
var _entry_panel: ScrollContainer
var _back: Button
var _count: OptionButton
var _address: LineEdit
var _server_address: LineEdit
var _rooms: OptionButton
var _scan: Button
var _host: Button
var _join: Button
var _start: Button
var _status: Label
var _request := ""
var _waiting_for_assignment := false
var _request_code := ""
var _endpoint: Dictionary


func _ready() -> void:
	var background := Panel.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.apply_app_background(background)
	_back = _button(Locale.t("common.back"), _on_back_pressed, "secondary")
	add_child(_back)
	UITheme.place_page_back(self, _back)
	var launch := LaunchFrame.new()
	add_child(launch)
	move_child(launch, 1)
	launch.setup(Locale.t("team.title"), Locale.t("launch.party_intro"), "party")
	_entry_panel = ScrollContainer.new()
	_entry_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_entry_panel.follow_focus = true
	add_child(_entry_panel)
	launch.bind_form(_entry_panel)
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_top", 32)
	padding.add_theme_constant_override("margin_right", 12)
	_entry_panel.add_child(padding)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	padding.add_child(box)
	var title := Label.new()
	title.text = Locale.t("launch.party_heading")
	UITheme.apply_room_entry_title(title)
	box.add_child(title)
	box.add_child(UITheme.separator())
	_entry = _column(box)
	_count = OptionButton.new()
	for count in range(3, 6):
		_count.add_item(Locale.t("team.room_size", [count, floori(count / 2.0), ceili(count / 2.0)]), count)
	_count.select(0)
	UITheme.apply_button(_count, "secondary")
	_entry.add_child(_count)
	_address = LineEdit.new()
	_address.placeholder_text = Locale.t("lobby.room_placeholder" if room.use_dedicated_lobby else "direct.join_by_ip").trim_suffix(":")
	_address.max_length = 16 if room.use_dedicated_lobby else 255
	UITheme.apply_input(_address)
	if not room.use_dedicated_lobby:
		_build_lan_search()
	else:
		var code_label := Label.new()
		code_label.text = Locale.t("lobby.room_code")
		UITheme.apply_label(code_label)
		_entry.add_child(code_label)
	_entry.add_child(_address)
	_host = _button(Locale.t("lobby.create"), _open_room, "primary")
	_join = _button(Locale.t("lobby.join"), _join_room, "outlined")
	for button in [_host, _join]:
		_entry.add_child(button)
	if room.use_dedicated_lobby:
		_build_server_settings()
	_address.text_changed.connect(func(_text: String): _refresh())
	_address.text_submitted.connect(func(_text: String):
		if not _join.disabled: _join_room())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(_status, true)
	box.add_child(_status)
	room.changed.connect(_refresh)
	room.failed.connect(_on_failure)
	room.battle_started.connect(_begin_match)
	if room.use_dedicated_lobby:
		NetworkManager.lobby_connected.connect(_send_lobby_request)
		NetworkManager.lobby_connection_failed.connect(_on_lobby_connection_failed)
	else:
		NetworkManager.lan_rooms_updated.connect(_update_lan_rooms)
		NetworkManager.start_lan_room_discovery(true)
	_refresh()
	if _entry_panel.visible:
		_host.grab_focus()


func _column(parent: VBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	parent.add_child(column)
	return column


func _button(title: String, action: Callable, style: String) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 37
	UITheme.apply_button(button, style)
	button.pressed.connect(action)
	return button


func _build_lan_search() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_entry.add_child(row)
	_rooms = OptionButton.new()
	_rooms.fit_to_longest_item = false
	_rooms.clip_text = true
	_rooms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(_rooms, "secondary")
	_rooms.item_selected.connect(func(index: int):
		_address.text = str(_rooms.get_item_metadata(index))
		_refresh())
	row.add_child(_rooms)
	_scan = _button(Locale.t("direct.refresh"), NetworkManager.refresh_lan_room_discovery, "secondary")
	row.add_child(_scan)


func _update_lan_rooms(rooms: Array) -> void:
	_rooms.clear()
	_rooms.add_item(Locale.t("direct.no_rooms" if rooms.is_empty() else "direct.select_room"), -1)
	_rooms.set_item_disabled(0, true)
	for item: Dictionary in rooms:
		var endpoint := str(item.address)
		if int(item.port) != room.PORT:
			endpoint = "[%s]:%d" % [endpoint, item.port] if ":" in endpoint else "%s:%d" % [endpoint, item.port]
		_rooms.add_item("%s  %s" % [item.name, endpoint])
		_rooms.set_item_metadata(_rooms.item_count - 1, endpoint)
		if _address.text == endpoint:
			_rooms.select(_rooms.item_count - 1)
	_refresh()


func _build_server_settings() -> void:
	_server_address = LineEdit.new()
	_server_address.placeholder_text = NetworkManager.DEFAULT_LOBBY_ADDRESS
	_server_address.max_length = 255
	UITheme.apply_input(_server_address)
	var settings := _button(Locale.t("lobby.server_settings"), func():
		_server_address.visible = not _server_address.visible
		if _server_address.visible: _server_address.grab_focus(), "secondary")
	_entry.add_child(settings)
	_entry.add_child(_server_address)
	_server_address.hide()


func _request_dedicated_room(create: bool) -> void:
	if not _request.is_empty() or room.is_open():
		return
	var code := _address.text.strip_edges()
	if create and code.is_empty():
		code = str(randi_range(10000000, 99999999))
	if not NetworkManager.is_valid_room_code(code):
		_on_failure("lobby.invalid_code")
		return
	var address := _server_address.text.strip_edges()
	_endpoint = preload("res://NetworkProtocolGuard.gd").parse_host_address(
		NetworkManager.DEFAULT_LOBBY_ADDRESS if address.is_empty() else address, NetworkManager.LOBBY_PORT)
	if not NetworkManager.is_valid_address(_endpoint.address) or int(_endpoint.port) not in range(1, 65536):
		_on_failure("lobby.invalid_server_address")
		return
	_request = "create" if create else "join"
	_waiting_for_assignment = false
	_request_code = code
	_address.text = code
	_status.text = Locale.t("lobby.connecting_lobby")
	if NetworkManager.connect_to_lobby(_endpoint.address, _on_lobby_response, _endpoint.port) != OK:
		_on_lobby_connection_failed()
	_refresh()


func _send_lobby_request() -> void:
	if not _request.is_empty():
		_waiting_for_assignment = true
		_status.text = Locale.t("lobby.creating_room" if _request == "create" else "lobby.joining_room")
		NetworkManager.request_party_room(_request_code, _count.get_selected_id(), _request == "create")


func _on_lobby_response(response: Dictionary) -> void:
	if _request.is_empty():
		return
	_request = ""
	_waiting_for_assignment = false
	NetworkManager.disconnect_from_lobby()
	match response.get("status", ""):
		"ok":
			_status.text = Locale.t("lobby.waiting_room_connecting")
			var error: Error = room.join(_endpoint.address, int(response.get("port", 0)), str(response.get("invite", "")))
			if error == OK:
				room.lobby_room_code = _request_code
			else:
				_on_failure("team.join_failed")
		"taken":
			_status.text = Locale.t("lobby.room_taken", [_request_code])
		"not_found":
			_status.text = Locale.t("lobby.room_not_found", [_request_code])
		"no_ports":
			_status.text = Locale.t("lobby.server_full")
		"protocol_mismatch":
			_status.text = Locale.t("lobby.room_protocol_mismatch")
		_:
			_status.text = Locale.t("lobby.server_rejected_code")
	_refresh()


func _on_lobby_connection_failed() -> void:
	if not _request.is_empty():
		_request = ""
		var message := "team.lobby_no_assignment" if _waiting_for_assignment else "lobby.could_not_reach"
		_waiting_for_assignment = false
		_on_failure(message)


func _open_room() -> void:
	if room.use_dedicated_lobby:
		_request_dedicated_room(true)
		return
	_status.text = ""
	if room.host(_count.get_selected_id()) != OK:
		_status.text = Locale.t("team.host_failed")
		_refresh()


func _join_room() -> void:
	if room.use_dedicated_lobby:
		_request_dedicated_room(false)
		return
	_status.text = Locale.t("team.connecting")
	var endpoint := preload("res://NetworkProtocolGuard.gd").parse_host_address(_address.text, room.PORT)
	if room.join(endpoint.address, endpoint.port) != OK:
		_on_failure("team.join_failed")


func _on_failure(message: String) -> void:
	_status.text = Locale.t(message)
	_refresh()
	if _entry_panel.visible:
		_address.grab_focus()


func _refresh() -> void:
	var in_room: bool = room.local_seat > 0
	_entry_panel.visible = not in_room
	_back.visible = not in_room
	if in_room:
		if not is_instance_valid(_waiting):
			_show_waiting_room()
		return
	if is_instance_valid(_waiting):
		_waiting.queue_free()
		_waiting = null
	var pending: bool = room.is_open() or not _request.is_empty()
	var has_address := not _address.text.strip_edges().is_empty()
	_host.disabled = pending
	_count.disabled = pending
	_join.disabled = pending or not has_address
	UITheme.apply_button(_host, "outlined" if has_address else "primary", false)
	UITheme.apply_button(_join, "primary" if has_address else "outlined", false)
	_address.editable = not pending
	if is_instance_valid(_server_address): _server_address.editable = not pending
	if is_instance_valid(_scan): _scan.disabled = pending
	if is_instance_valid(_rooms): _rooms.disabled = pending or _rooms.item_count < 2
	_status.visible = not _status.text.is_empty()


func _show_waiting_room() -> void:
	_waiting = preload("res://presentation/OnlineRoomPanel.gd").new()
	add_child(_waiting)
	_waiting.setup(self, room.lobby_room_code, "", room)
	_start = _waiting.party_start_button
	_waiting.deck_choice.grab_focus()


func _exit_waiting_room() -> void:
	room.close()
	_status.text = ""
	_refresh()
	_host.grab_focus()


func _open_battle_settings() -> void:
	var settings := preload("res://presentation/BattleRulesEditor.gd").open(self, room.battle_rules.duplicate(true),
		func(): return not room.is_host() or room.started, room.set_battle_rules, Callable(), false, true)
	UIMotion.register_popup(settings)


func party_join_address() -> String:
	var connected_address: String = room.join_address()
	if not connected_address.is_empty():
		return connected_address
	for address in IP.get_local_addresses():
		if "." in address and not address.begins_with("127.") and not address.begins_with("169.254."):
			return address
	return "127.0.0.1"


func _begin_match() -> void:
	_refresh()
	_show_team_reveal()


func _show_team_reveal() -> void:
	var popup := UITheme.make_popup_layer(self, 165)
	var layer: CanvasLayer = popup.layer
	layer.name = "TeamReveal"
	layer.set_meta("popup_close_locked", true)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "PopupPanel"
	UITheme.apply_popup_frame(panel, "gold", false, true)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	var title := Label.new()
	title.text = Locale.t("team.reveal")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 24)
	content.add_child(title)
	var separator := HSeparator.new()
	UITheme.apply_separator(separator)
	content.add_child(separator)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 26)
	content.add_child(teams)
	var animate := not bool(AppPreferences.get_value("reduced_motion"))
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) if animate else null
	for team in [1, 2]:
		var accent := UITheme.party_team_accent(team)
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 174
		column.add_theme_constant_override("separation", 8)
		teams.add_child(column)
		var heading := Label.new()
		heading.text = Locale.t("team.side_%d" % team)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_title(heading, 20)
		heading.add_theme_color_override("font_color", accent)
		column.add_child(heading)
		var seat_row := 0
		for member: Dictionary in room.view.players:
			if int(member.team) != team:
				continue
			var seat := int(member.seat)
			var local: bool = seat == room.local_seat
			var row := Control.new()
			row.custom_minimum_size.y = 46
			column.add_child(row)
			var tile := Panel.new()
			var tone := accent if local else accent.lerp(UITheme.COLOR_PANEL_DARK, 0.45)
			tile.add_theme_stylebox_override("panel", UITheme.panel_style(
				UITheme.COLOR_PANEL_DARK.lerp(accent, 0.13 if local else 0.06), tone, 2 if local else 1, 6))
			row.add_child(tile)
			tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var name_label := Label.new()
			name_label.text = Locale.t("team.seat", [seat])
			if local:
				name_label.text = Locale.t("team.your_seat", [name_label.text])
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UITheme.apply_label(name_label)
			tile.add_child(name_label)
			name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if tween != null:
				var offset := 32.0 if team == 1 else -32.0
				tile.offset_left = offset
				tile.offset_right = offset
				tile.modulate.a = 0.0
				var delay: float = 0.2 + 0.14 * seat_row + 0.08 * (team - 1)
				tween.tween_property(tile, "offset_left", 0.0, 0.46).set_delay(delay)
				tween.tween_property(tile, "offset_right", 0.0, 0.46).set_delay(delay)
				tween.tween_property(tile, "modulate:a", 1.0, 0.3).set_delay(delay)
			seat_row += 1
	var confirm := Button.new()
	confirm.name = "TeamRevealConfirm"
	confirm.text = Locale.t("common.confirm")
	confirm.custom_minimum_size = Vector2(132, 38)
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(confirm, "primary")
	content.add_child(confirm)
	confirm.pressed.connect(func():
		if not room.started or UIMotion.is_transitioning():
			return
		confirm.disabled = true
		room.confirm_team_reveal()
		UIMotion.replace_scene("res://TeamBattle.tscn"))
	UIMotion.register_popup(layer, confirm)


func _on_back_pressed() -> void:
	if not _request.is_empty():
		_request = ""
		NetworkManager.disconnect_from_lobby()
	room.close()
	UIMotion.go_back("res://MainMenu.tscn")


func _exit_tree() -> void:
	if not room.use_dedicated_lobby:
		NetworkManager.stop_lan_room_discovery()

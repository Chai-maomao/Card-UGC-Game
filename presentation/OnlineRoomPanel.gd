extends Control

var lobby: Control
var room_code := ""
var start_button: Button
var create_button: Button
var status: Label
var local_state: Label
var local_title: Label
var local_host_badge: PanelContainer
var local_deck: Label
var remote_state: Label
var remote_title: Label
var remote_host_badge: PanelContainer
var remote_deck: Label
var deck_choice: OptionButton
var grid: GridContainer
var deck_scroll: ScrollContainer
var footer: HBoxContainer
var content: HBoxContainer
var sidebar: VBoxContainer
var sidebar_scroll: ScrollContainer
var margin: MarginContainer
var _last_status := ""
var _clock := 0.0
var _card_scale := 0.85
var _rules_sent := ""
var _rule_summary: Label
var _rules_button: Button
var _awaiting_host_rules := false
var _rules_view: AcceptDialog
var _rules_editor: CanvasLayer
var _opponent_deck: CanvasLayer
var _card_inspector: CanvasLayer
var _rules_notice := ""
var _leave_dialog: ConfirmationDialog
var _leaving := false
var _selected_deck_index := -1
var _deck_submission_error := ""
var _share_button: Button
var _share_button_text := ""
var _share_feedback: Timer
var _invite_dialog: ConfirmationDialog

func _t(zh: String, en: String) -> String:
	return zh if Locale.language=="zh" else en

func setup(owner_lobby: Control, code: String, initial_message: String) -> void:
	lobby=owner_lobby
	room_code=code
	_awaiting_host_rules = (NetworkManager.session_mode == NetworkManager.SESSION_MODE_ROOM
		and not NetworkManager.is_authority()
		and NetworkManager.room_wait_reason in ["returning", "syncing_preparation", "editing"])
	name="OnlineRoom"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sink := Label.new()
	sink.name="WaitLabel"
	sink.text=initial_message
	sink.hide()
	add_child(sink)
	margin=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",18)
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",16)
	box.add_child(header)
	var exit := _button(Locale.t("wait.leave_room"),header)
	exit.name="ExitButton"
	exit.pressed.connect(request_leave)
	var title := _label(_t("联机房间","Online Room"),header,true)
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if not code.is_empty():
		var copy := _button(Locale.t("wait.room_code_copy", [code]), header)
		copy.name="CopyRoomCodeButton"
		_setup_share_feedback(copy)
		copy.pressed.connect(func(): _copy_invite_value(room_code))
	else:
		var mode := _label(_t("局域网","Local Network"),header)
		mode.autowrap_mode=TextServer.AUTOWRAP_OFF
		mode.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		if NetworkManager.session_mode == NetworkManager.SESSION_MODE_LAN_HOST:
			var copy := MenuButton.new()
			copy.name = "CopyLanAddressButton"
			copy.text = Locale.t("wait.copy_lan_address")
			copy.flat = false
			copy.custom_minimum_size.y = 40
			copy.set_meta("room_font_size", 14)
			UITheme.apply_button(copy, "secondary", false)
			header.add_child(copy)
			_setup_share_feedback(copy)
			var popup := copy.get_popup()
			UITheme.apply_popup_menu(popup)
			copy.about_to_popup.connect(_populate_lan_address_menu.bind(popup))
			popup.id_pressed.connect(func(id: int): _copy_invite_value(str(popup.get_item_metadata(popup.get_item_index(id)))))
	box.add_child(HSeparator.new())
	content=HBoxContainer.new()
	content.add_theme_constant_override("separation",24)
	content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(content)
	var deck_box := VBoxContainer.new()
	deck_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	deck_box.add_theme_constant_override("separation",12)
	content.add_child(deck_box)
	var deck_header := HBoxContainer.new()
	deck_header.add_theme_constant_override("separation",12)
	deck_box.add_child(deck_header)
	deck_choice=OptionButton.new()
	deck_choice.name="RoomDeckChoice"
	deck_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UITheme.apply_button(deck_choice,"secondary",false)
	deck_header.add_child(deck_choice)
	_populate_deck_choices()
	create_button=_button(Locale.t("wait.create_card"),deck_header)
	create_button.name="CreateCardButton"
	create_button.pressed.connect(lobby._on_create_card_pressed)
	deck_scroll=ScrollContainer.new()
	deck_scroll.name="RoomDeckScroll"
	deck_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	deck_scroll.follow_focus = true
	UITheme.pad_scroll_content(deck_scroll,10)
	deck_box.add_child(deck_scroll)
	grid=GridContainer.new()
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",16)
	deck_scroll.add_child(grid)
	sidebar=VBoxContainer.new()
	sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation",16)
	sidebar_scroll=ScrollContainer.new()
	sidebar_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.pad_scroll_content(sidebar_scroll,6)
	content.add_child(sidebar_scroll)
	sidebar_scroll.add_child(sidebar)
	var you := _seat(_t("你","You"))
	local_state=you[0]
	local_deck=you[1]
	local_title=you[2]
	local_host_badge=you[3]
	var opponent := _seat(_t("对手","Opponent"))
	remote_state=opponent[0]
	remote_deck=opponent[1]
	remote_title=opponent[2]
	remote_host_badge=opponent[3]
	var view := _button(_t("查看对手卡组","View opponent deck"),sidebar)
	view.name="ViewOpponentDeck"
	view.pressed.connect(_show_opponent_deck)
	sidebar.add_child(HSeparator.new())
	_label(_t("本局规则","Match Rules"),sidebar,true)
	_rule_summary = _label(BattleRulesHelp.room_summary(PlayerData.battle_config),sidebar)
	box.add_child(HSeparator.new())
	footer=HBoxContainer.new()
	footer.add_theme_constant_override("separation",16)
	box.add_child(footer)
	status=_label("",footer)
	status.name="RoomStatus"
	status.set_meta("keyword_literal", true)
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_rules_button = _button(Locale.t("wait.view_rules"), footer)
	_rules_button.name="RoomRulesButton"
	_rules_button.pressed.connect(_show_rules)
	start_button=_button(_t("准备","Ready"),footer,"primary")
	start_button.name="StartButton"
	start_button.custom_minimum_size.x=160
	start_button.pressed.connect(lobby._on_start_pressed)
	get_viewport().size_changed.connect(apply_scale.bind(1.0))
	_rebuild_cards()
	apply_scale(1.0)
	NetworkManager.match_offer_received.connect(_receive_room_rules)
	NetworkManager.connected.connect(_on_opponent_available)
	lobby.match_agreement.confirmation_blocked = _blocks_match_confirmation
	lobby.match_agreement.confirmation_opening.connect(_on_match_confirmation_opening)
	lobby.match_agreement.preparation_reset.connect(_on_preparation_reset)
	_update_state()


func _setup_share_feedback(button: Button) -> void:
	_share_button = button
	_share_button_text = button.text
	_share_feedback = Timer.new()
	_share_feedback.one_shot = true
	add_child(_share_feedback)
	_share_feedback.timeout.connect(func():
		_share_button.text = _share_button_text
		_share_button.custom_minimum_size.x = 0
	)


func _copy_invite_value(value: String) -> void:
	if value.is_empty() or _leaving:
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(value)
		if DisplayServer.clipboard_get() == value:
			_close_invite_dialog()
			if _share_feedback.is_stopped():
				_share_button.custom_minimum_size.x = _share_button.size.x
			_share_button.text = Locale.t("lobby.code_copied") if room_code.is_empty() else Locale.t("wait.room_code_copied", [room_code])
			_share_feedback.start(1.2)
			return
	_show_manual_invite(value)


func _show_manual_invite(value: String) -> void:
	if is_instance_valid(_invite_dialog):
		var current := _invite_dialog.get_node("InviteContent/InviteValue") as LineEdit
		current.grab_focus()
		current.select_all()
		return
	_invite_dialog = ConfirmationDialog.new()
	_invite_dialog.name = "ManualRoomInvite"
	_invite_dialog.title = Locale.t("wait.copy_failed")
	_invite_dialog.dialog_hide_on_ok = false
	var content_box := VBoxContainer.new()
	content_box.name = "InviteContent"
	content_box.add_theme_constant_override("separation", 10)
	_invite_dialog.add_child(content_box)
	var hint := _label(Locale.t("wait.share_room_manual"), content_box)
	hint.set_meta("keyword_literal", true)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	var input := LineEdit.new()
	input.name = "InviteValue"
	input.text = value
	input.editable = false
	input.custom_minimum_size = Vector2(minf(360.0, get_viewport_rect().size.x * 0.65), 40)
	content_box.add_child(input)
	_invite_dialog.confirmed.connect(_copy_invite_value.bind(value))
	_invite_dialog.canceled.connect(_close_invite_dialog)
	add_child(_invite_dialog)
	UITheme.apply_dialog(_invite_dialog, true)
	_invite_dialog.get_ok_button().text = Locale.t("wait.copy_invite_retry")
	_invite_dialog.get_cancel_button().text = Locale.t("common.close")
	_invite_dialog.popup_centered()
	input.grab_focus()
	input.select_all()


func _close_invite_dialog() -> void:
	if is_instance_valid(_invite_dialog):
		_invite_dialog.hide()
		_invite_dialog.queue_free()
		_invite_dialog = null


func _populate_lan_address_menu(popup: PopupMenu) -> void:
	popup.clear()
	var options: Dictionary = {}
	for adapter in IP.get_local_interfaces():
		var label := str(adapter.get("friendly", "")).strip_edges()
		if label.is_empty():
			label = str(adapter.get("name", ""))
		for address: String in adapter.get("addresses", []):
			if not address.is_valid_ip_address() or ":" in address or address.begins_with("127.") or address.begins_with("0.") or address.begins_with("169.254."):
				continue
			var endpoint := "%s:%d" % [address, NetworkManager.room_server_port]
			options[endpoint] = "%s (%s)" % [label, endpoint] if not label.is_empty() else endpoint
	var endpoints := options.keys()
	endpoints.sort()
	for endpoint in endpoints:
		popup.add_item(options[endpoint])
		popup.set_item_metadata(popup.item_count - 1, endpoint)
	if popup.item_count == 0:
		popup.add_item(Locale.t("wait.no_lan_address"))
		popup.set_item_disabled(0, true)


func _populate_deck_choices() -> void:
	var selected := -1
	var preferred := -1
	var room_deck_id := PlayerData.online_room_deck_id
	var has_custom_deck := room_deck_id.is_empty() and not PlayerData.battle_deck.is_empty()
	for deck in PlayerData.deck_library:
		var deck_id := str(deck.id)
		var cards := PlayerData.get_cards_for_deck(deck_id)
		if cards.is_empty():
			continue
		deck_choice.add_item("%s  (%d)" % [deck.get("name", ""), cards.size()])
		var index := deck_choice.item_count - 1
		deck_choice.set_item_metadata(index, deck_id)
		if deck_id == PlayerData.current_deck_id:
			preferred = index
		if deck_id == room_deck_id or (has_custom_deck and cards == PlayerData.battle_deck):
			selected = index
	if selected < 0 and has_custom_deck:
		deck_choice.add_item(_t("当前卡组", "Current deck") + "  (%d)" % PlayerData.battle_deck.size())
		selected = deck_choice.item_count - 1
		deck_choice.set_item_metadata(selected, PlayerData.battle_deck.duplicate())
	elif selected < 0 and deck_choice.item_count > 0:
		selected = preferred if preferred >= 0 else 0
	_apply_deck_choice(selected)
	deck_choice.item_selected.connect(func(index: int):
		if not _can_change_deck():
			deck_choice.select(_selected_deck_index)
			return
		_apply_deck_choice(index)
		_deck_submission_error = ""
		_rebuild_cards()
		_update_state()
	)


func serialize_ready_deck() -> Array:
	_deck_submission_error = ""
	var cards := PlayerData.battle_deck
	if cards.size() > DataSchema.MAX_CARDS_PER_DECK:
		_deck_submission_error = Locale.t("wait.local_deck_card_limit", [DataSchema.MAX_CARDS_PER_DECK])
	else:
		var payload := cards.map(PlayerData.serialize_card)
		var errors := PlayerData.battle_deck_payload_errors(payload)
		if not errors.is_empty():
			var path: Array = errors[0].get("path", [])
			if path.size() >= 2 and path[0] == "cards" and path[1] is int and path[1] >= 0 and path[1] < cards.size():
				_deck_submission_error = Locale.t("wait.invalid_local_card", [cards[path[1]].card_name])
			else:
				_deck_submission_error = Locale.t("wait.invalid_local_deck")
		elif NetworkManager.is_dedicated_server and var_to_bytes(payload).size() > NetworkManager.MAX_ROOM_DECK_BYTES:
			_deck_submission_error = Locale.t("wait.local_deck_too_large")
		else:
			return payload
	_update_state()
	return []


func _apply_deck_choice(index: int) -> void:
	_selected_deck_index = index
	if index < 0:
		deck_choice.text = Locale.t("wait.no_playable_deck")
		PlayerData.online_room_deck_id = ""
		PlayerData.battle_deck = []
		return
	deck_choice.select(index)
	var source: Variant = deck_choice.get_item_metadata(index)
	PlayerData.online_room_deck_id = source if source is String else ""
	var cards: Array = PlayerData.get_cards_for_deck(source) if source is String else source
	PlayerData.battle_deck = cards.duplicate()


func _on_opponent_available() -> void:
	# A replacement player needs the current rules even if the host never edited them again.
	_rules_sent = ""

func _receive_room_rules(offer: Dictionary) -> void:
	if NetworkManager.is_authority() or not offer.get("room_preview", false): return
	var config: Dictionary = offer.get("rules", {})
	if MatchAgreement.valid_config(config):
		var changed := PlayerData.battle_config != config
		PlayerData.battle_config = config.duplicate(true)
		_awaiting_host_rules = false
		if changed and is_instance_valid(_rules_view) and not _rules_view.is_queued_for_deletion():
			_render_rules_view(_rules_view.get_node("RuleScroll"))
		_update_state()

func waiting_for_host_rules() -> bool:
	return _awaiting_host_rules and not NetworkManager.is_authority()

func _seat(title: String) -> Array:
	var panel := PanelContainer.new()
	UITheme.apply_panel(panel,"soft")
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel",style)
	sidebar.add_child(panel)
	var inset := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_"+edge,14)
	panel.add_child(inset)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	inset.add_child(box)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	box.add_child(heading)
	var title_label := _label(title, heading, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var host_badge := _make_host_badge(heading)
	return [_label("",box),_label("",box),title_label,host_badge]

func _make_host_badge(parent: Control) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "HostBadge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UITheme.panel_style(Color("2c2c24"), Color("786747"), 1, 7)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	badge.add_theme_stylebox_override("panel", style)
	parent.add_child(badge)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	badge.add_child(row)
	var crown := Control.new()
	crown.custom_minimum_size = Vector2(16, 16)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(crown)
	var brass := Color("d6b67c")
	crown.draw.connect(func():
		crown.draw_colored_polygon(PackedVector2Array([Vector2(1, 4), Vector2(5, 7), Vector2(8, 2),
			Vector2(11, 7), Vector2(15, 4), Vector2(13, 11), Vector2(3, 11)]), brass)
		crown.draw_line(Vector2(3, 13), Vector2(13, 13), brass, 1.0, true)
	)
	var label := _label(_t("房主", "Host"), row)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.set_meta("room_font_size", 12)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", brass)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.hide()
	return badge

func _button(text: String, parent: Node, variant: String="secondary") -> Button:
	var button := Button.new()
	button.text=text
	button.custom_minimum_size.y=40
	button.set_meta("room_font_size",14)
	UITheme.apply_button(button,variant,false)
	parent.add_child(button)
	return button

func _label(text: String, parent: Node, title: bool=false) -> Label:
	var label := Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.set_meta("room_font_size",20 if title else 14)
	if title: UITheme.apply_title(label,20)
	else: UITheme.apply_label(label)
	parent.add_child(label)
	return label

func apply_scale(_value: float) -> void:
	if not is_instance_valid(grid): return
	var s := clampf(minf(get_viewport_rect().size.x/1280.0,get_viewport_rect().size.y/720.0),0.75,1.5)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,roundi(24*s))
	sidebar_scroll.custom_minimum_size.x=280*s
	_card_scale=0.85*s
	for node in find_children("*","Control",true,false):
		if node.has_meta("room_font_size"): node.add_theme_font_size_override("font_size",roundi(float(node.get_meta("room_font_size"))*s))
	deck_choice.add_theme_font_size_override("font_size",roundi(14*s))
	for cell in grid.get_children():
		cell.get_child(0).apply_ui_scale(_card_scale)
	_reflow()
	_reflow.call_deferred()

func _reflow() -> void:
	var available := get_viewport_rect().size.x-margin.get_theme_constant("margin_left")-margin.get_theme_constant("margin_right")-sidebar_scroll.custom_minimum_size.x-24
	grid.columns=maxi(1,int((available-28)/(120*_card_scale+16)))

func _rebuild_cards() -> void:
	for child in grid.get_children(): child.free()
	deck_scroll.scroll_vertical = 0
	for card in PlayerData.battle_deck:
		var center := CenterContainer.new()
		center.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(center)
		var ui := preload("res://CardUI.tscn").instantiate()
		center.add_child(ui)
		ui.set_card(card)
		ui.set_battle_layout_preview(true)
		ui.apply_ui_scale(_card_scale)
		ui.set_meta("suppress_hover_hint",true)
		ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
		for child in ui.find_children("*","Control",true,false): child.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var inspect := Button.new()
		inspect.name="InspectRoomCard"
		# Draw the focus outline above the printed card face.
		inspect.z_index = 6
		inspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for state in ["normal","hover","pressed"]: inspect.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		inspect.add_theme_stylebox_override("focus", UITheme.panel_style(Color.TRANSPARENT, UITheme.COLOR_ACCENT.lightened(0.25), 3, 7))
		ui.add_child(inspect)
		inspect.pressed.connect(inspect_collection_card.bind(card,ui,self))
	_reflow.call_deferred()

func _show_opponent_deck() -> void:
	if _leaving or not lobby.opponent_ready or is_instance_valid(_opponent_deck):
		return
	_opponent_deck = preload("res://CardCollectionDialog.gd").show_cards(
		self, PlayerData.opponent_battle_deck, _t("对手卡组", "Opponent deck"))


func inspect_collection_card(card: CardData, source: Control, dialog: Node) -> void:
	if _leaving or is_instance_valid(_card_inspector):
		return
	var parent: Node = _opponent_deck if is_instance_valid(_opponent_deck) and dialog == _opponent_deck else self
	_card_inspector = preload("res://presentation/ReadOnlyCardInspector.gd").show_card(parent, card, source)


func _close_card_inspector() -> void:
	if is_instance_valid(_card_inspector):
		_card_inspector.visible = false
		_card_inspector.queue_free()
		_card_inspector = null


func _close_opponent_deck() -> void:
	if not is_instance_valid(_opponent_deck):
		return
	if is_instance_valid(_card_inspector) and _card_inspector.get_parent() == _opponent_deck:
		_close_card_inspector()
	_opponent_deck.visible = false
	_opponent_deck.queue_free()
	_opponent_deck = null


func _on_preparation_reset() -> void:
	_close_opponent_deck()
	_update_state()


func _process(delta: float) -> void:
	_clock+=delta
	if _clock<0.1: return
	_clock=0
	_update_state()

func _update_state() -> void:
	if _leaving:
		return
	var server_room := NetworkManager.session_mode == NetworkManager.SESSION_MODE_ROOM
	var connected: bool = (NetworkManager.room_preparation_available and NetworkManager.is_game_rpc_ready()) if server_room else lobby._can_submit_ready()
	var link_waiting := server_room and NetworkManager.room_link_waiting()
	var rules_pending := waiting_for_host_rules()
	var hash_value := MatchAgreement.digest(PlayerData.battle_config)
	if connected and not link_waiting and NetworkManager.is_authority() and hash_value != _rules_sent:
		_rules_sent = hash_value
		NetworkManager.rpc_match_offer.rpc({"room_preview":true,"rules":PlayerData.battle_config.duplicate(true)})
	if rules_pending:
		_rule_summary.text = Locale.t("wait.syncing_room_rules")
	else:
		_rule_summary.text = BattleRulesHelp.room_summary(PlayerData.battle_config)
	var local_connected := NetworkManager.is_online and NetworkManager.peer!=null and NetworkManager.peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED
	var is_room_host := local_connected and NetworkManager.is_authority()
	local_host_badge.visible = is_room_host
	remote_host_badge.visible = local_connected and not is_room_host
	local_state.text=(_t("已准备","Ready") if lobby.i_am_ready else _t("未准备","Not ready")) if local_connected else (_t("连接中…","Connecting…") if NetworkManager.is_online else _t("已断开","Disconnected"))
	if local_connected and lobby.match_agreement.local_accepted:
		local_state.text = Locale.t("wait.rules_confirmed")
	if link_waiting:
		local_state.text = Locale.t("wait.room_link_recovering")
	local_deck.text=_t("%d 张卡牌","%d cards")%PlayerData.battle_deck.size()
	local_state.modulate=UITheme.COLOR_ACCENT if lobby.i_am_ready else Color.WHITE
	remote_state.text=_t("已准备","Ready") if lobby.opponent_ready else (_t("未准备","Not ready") if connected else _t("等待加入","Waiting to join"))
	if local_connected and lobby.match_agreement.remote_accepted:
		remote_state.text = Locale.t("wait.rules_confirmed")
	remote_state.modulate=UITheme.COLOR_ACCENT if lobby.opponent_ready else Color.WHITE
	remote_deck.text=_t("%d 张卡牌","%d cards")%PlayerData.opponent_battle_deck.size() if lobby.opponent_ready else _t("对手准备后可查看卡组","Deck available after opponent is ready")
	sidebar.get_node("ViewOpponentDeck").disabled=not lobby.opponent_ready
	deck_choice.disabled = deck_choice.item_count == 0 or not _can_change_deck()
	create_button.disabled=lobby.i_am_ready or lobby._battle_starting or NetworkManager.lan_room_return_pending or NetworkManager.room_wait_reason == "returning" or (server_room and (link_waiting or not NetworkManager.has_live_server_room()))
	var rules_editable := _can_edit_rules()
	_rules_button.text = Locale.t("wait.edit_rules" if rules_editable else "wait.view_rules")
	_rules_button.disabled = rules_pending
	if not rules_editable and is_instance_valid(_rules_editor) and not _rules_editor.is_queued_for_deletion():
		_rules_editor.queue_free()
		_rules_notice = Locale.t("wait.rules_became_locked")
	elif rules_editable:
		_rules_notice = ""
	var can_cancel: bool = lobby.has_method("can_cancel_preparation") and lobby.can_cancel_preparation()
	var can_return: bool = server_room and lobby.can_return_to_preparation()
	var returning_to_preparation: bool = server_room and lobby.cancelling_preparation and lobby.preparation_reset_reason == "start_timeout"
	start_button.disabled=not connected or rules_pending or (link_waiting and not can_cancel) or (lobby.i_am_ready and not can_cancel) or lobby._battle_starting or PlayerData.battle_deck.is_empty()
	start_button.text = Locale.t("wait.cancel_preparation") if can_cancel or lobby.cancelling_preparation else (_t("已准备", "Ready") if lobby.i_am_ready else _t("准备", "Ready"))
	if can_return:
		start_button.disabled = false
		start_button.text = Locale.t("wait.back_to_preparation")
	elif returning_to_preparation:
		start_button.text = Locale.t("wait.back_to_preparation")
	elif lobby.match_agreement.completed:
		start_button.text = Locale.t("wait.rules_confirmed")
	if link_waiting:
		remote_state.text = Locale.t("wait.opponent_status_unavailable")
		remote_state.modulate = Color.WHITE
		if lobby.cancelling_preparation and not returning_to_preparation:
			status.text = Locale.t("wait.cancel_ready_reconnecting")
		elif NetworkManager.room_wait_reason == "cancelled" and not lobby.i_am_ready and not lobby.opponent_ready:
			status.text = Locale.t("wait.ready_cancelled_reconnecting")
		else:
			status.text = Locale.t("wait.room_link_waiting")
	elif NetworkManager.room_wait_reason == "returning" and local_connected:
		remote_state.text = Locale.t("wait.viewing_results")
		status.text = Locale.t("wait.opponent_viewing_results")
	elif local_connected and (NetworkManager.lan_opponent_editing or (server_room and NetworkManager.room_wait_reason == "editing")):
		remote_state.text = _t("编辑卡牌中", "Editing a card")
		status.text = Locale.t("wait.opponent_editing")
	elif server_room and local_connected and NetworkManager.room_wait_reason == "syncing_preparation":
		remote_state.text = _t("正在同步…", "Synchronizing…")
		status.text = Locale.t("wait.syncing_room_status")
	elif local_connected and NetworkManager.lan_room_return_pending:
		status.text = Locale.t("wait.resuming_preparation")
	elif connected and not _deck_submission_error.is_empty():
		status.text = _deck_submission_error
	elif server_room and NetworkManager.room_host_transfer_pending and is_room_host and NetworkManager.opponent_peer_id <= 0:
		status.text = Locale.t("wait.you_became_room_host")
	elif server_room and NetworkManager.room_wait_reason == "opponent_connection_lost" and local_connected:
		status.text = Locale.t("wait.opponent_connection_lost")
	elif server_room and NetworkManager.room_wait_reason == "opponent_left" and local_connected:
		status.text = _t("对手已离开，可以分享房间号邀请新玩家", "Opponent left. Share the room code to invite another player.")
	elif local_connected and NetworkManager.room_wait_reason == "opponent_left" and NetworkManager.has_live_lan_room():
		status.text = Locale.t("wait.lan_guest_left")
	elif local_connected and NetworkManager.room_wait_reason == "incompatible_guest" and NetworkManager.has_live_lan_room():
		status.text = Locale.t("wait.lan_incompatible_guest")
	elif NetworkManager.room_wait_reason == "cancelled" and not lobby.i_am_ready and not lobby.opponent_ready:
		status.text = Locale.t("wait.ready_cancelled")
	elif server_room and NetworkManager.room_wait_reason == "offer_mismatch" and not lobby.i_am_ready and not lobby.opponent_ready:
		status.text = Locale.t("wait.offer_mismatch")
	elif server_room and NetworkManager.room_wait_reason == "start_timeout" and not lobby.i_am_ready and not lobby.opponent_ready:
		status.text = Locale.t("wait.preparation_restored")
	elif server_room and NetworkManager.room_wait_reason == "invalid_deck" and not lobby.i_am_ready and not lobby.opponent_ready:
		status.text = _t("卡组无法用于这局，请换一副卡组再准备", "A deck could not be used. Choose another deck and ready up again.")
	elif returning_to_preparation: status.text=Locale.t("wait.returning_to_preparation")
	elif lobby.cancelling_preparation: status.text=Locale.t("wait.cancelling_ready")
	elif can_return: status.text=Locale.t("wait.start_timeout")
	elif lobby._battle_starting or lobby.match_agreement.completed: status.text=Locale.t("wait.starting_match")
	elif lobby.match_agreement.local_accepted: status.text=Locale.t("wait.opponent_confirming")
	elif lobby.match_agreement.pending: status.text=Locale.t("wait.confirming_rules")
	elif lobby.i_am_ready and lobby.opponent_ready: status.text=get_node("WaitLabel").text
	elif connected and rules_pending: status.text = Locale.t("wait.syncing_room_rules")
	elif not _rules_notice.is_empty(): status.text = _rules_notice
	elif local_connected and PlayerData.battle_deck.is_empty():
		status.text = Locale.t("wait.need_library_deck" if PlayerData.deck_library.is_empty() else "wait.need_room_card")
	elif connected: status.text=_t("等待对手准备","Waiting for opponent to ready") if lobby.i_am_ready else _t("选择卡组后点击准备","Choose your deck, then Ready")
	elif NetworkManager.is_online: status.text=_t("等待对手加入房间","Waiting for an opponent") if local_connected else _t("正在连接房间…","Connecting to room…")
	else: status.text=_t("房间连接已断开","Room disconnected")

func _can_change_deck() -> bool:
	return not _leaving and not lobby.i_am_ready and not lobby._battle_starting


func _can_edit_rules() -> bool:
	if not _can_change_deck() or lobby.opponent_ready or not NetworkManager.is_online or not NetworkManager.is_authority() or NetworkManager.room_wait_reason == "returning":
		return false
	return not NetworkManager.is_dedicated_server or NetworkManager.has_live_server_room()


func _show_rules() -> void:
	if _leaving or waiting_for_host_rules() or is_instance_valid(_rules_editor) or is_instance_valid(_rules_view):
		return
	if _can_edit_rules():
		_rules_editor = preload("res://presentation/RoomRulesEditor.gd").open(self, _can_edit_rules)
		return
	_rules_view = AcceptDialog.new()
	_rules_view.title = _t("本局规则","Match Rules")
	var scroll := ScrollContainer.new()
	scroll.name = "RuleScroll"
	scroll.custom_minimum_size=Vector2(520,300)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_rules_view.add_child(scroll)
	_render_rules_view(scroll)
	UITheme.apply_dialog(_rules_view)
	add_child(_rules_view)
	_rules_view.confirmed.connect(_close_rules_view)
	_rules_view.canceled.connect(_close_rules_view)
	_rules_view.popup_centered()


func _close_rules_view() -> void:
	if is_instance_valid(_rules_view):
		_rules_view.hide()
		_rules_view.queue_free()
		_rules_view = null


func _on_match_confirmation_opening() -> void:
	_close_invite_dialog()
	_close_rules_view()
	_close_card_inspector()
	_close_opponent_deck()
	_update_state()


func _render_rules_view(scroll: ScrollContainer) -> void:
	var position := scroll.scroll_vertical
	for child in scroll.get_children():
		scroll.remove_child(child)
		child.queue_free()
	var game := preload("res://GameState.gd").new()
	game.initialize_fields(PlayerData.battle_config)
	BattleFieldRules.build(scroll, game)
	scroll.set_deferred("scroll_vertical", position)


func request_leave() -> void:
	if _leaving or is_instance_valid(_leave_dialog):
		return
	if NetworkManager.opponent_peer_id <= 0 and not lobby.opponent_ready and NetworkManager.room_wait_reason != "editing":
		_leave()
		return
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.name = "LeaveRoomConfirmation"
	_leave_dialog.title = Locale.t("wait.leave_room")
	var transferring_host := NetworkManager.is_dedicated_server and NetworkManager.is_authority()
	_leave_dialog.dialog_text = Locale.t("wait.leave_host_body" if transferring_host else "wait.leave_room_body")
	_leave_dialog.confirmed.connect(func():
		_close_leave_dialog()
		_leave())
	_leave_dialog.canceled.connect(_on_leave_cancelled)
	add_child(_leave_dialog)
	UITheme.apply_dialog(_leave_dialog)
	_leave_dialog.get_ok_button().text = Locale.t("wait.leave_room")
	_leave_dialog.get_cancel_button().text = Locale.t("common.cancel")
	UITheme.apply_button(_leave_dialog.get_ok_button(), "danger")
	_leave_dialog.popup_centered()
	_leave_dialog.get_cancel_button().grab_focus.call_deferred()


func _close_leave_dialog() -> void:
	if is_instance_valid(_leave_dialog):
		_leave_dialog.hide()
		_leave_dialog.queue_free()
		_leave_dialog = null


func _on_leave_cancelled() -> void:
	_close_leave_dialog()
	lobby.match_agreement.resume_deferred_confirmation()
	if NetworkManager.room_wait_reason == "cancelled" and not lobby.match_agreement.pending:
		_update_state()
		if start_button.is_visible_in_tree() and not start_button.disabled:
			start_button.grab_focus()


func _blocks_match_confirmation() -> bool:
	return _leaving or is_instance_valid(_leave_dialog)


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	for button in find_children("*", "BaseButton", true, false):
		button.disabled = true
	status.text = Locale.t("wait.leaving_room")
	lobby._exit_waiting_room()

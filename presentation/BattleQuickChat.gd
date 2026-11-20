extends Button

const CHOICES_PER_GROUP := 4
const PICK_TIME := 3.5

var can_chat: Callable
var _notice: PanelContainer
var _message: Label
var _expiry: Timer
var _phrase := -1
var _incoming := false
var _group := -1
var _picker: CanvasLayer
var _tags: Array[PanelContainer] = []
var _pointer := Vector2.ZERO


func _ready() -> void:
	name = "BattleQuickChat"
	set_meta("keyword_literal", true)
	UITheme.apply_button(self, "secondary")
	pressed.connect(_open_picker.bind(0))
	NetworkManager.battle_chat_received.connect(_receive)
	Locale.language_changed.connect(_localize)
	_notice = PanelContainer.new()
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_panel(_notice, "tooltip")
	add_child(_notice)
	_message = _add_label(_notice, "")
	_notice.hide()
	_expiry = Timer.new()
	_expiry.one_shot = true
	_expiry.wait_time = 5.0
	_expiry.timeout.connect(_notice.hide)
	add_child(_expiry)
	var refresh := Timer.new()
	refresh.wait_time = 0.25
	refresh.autostart = true
	refresh.timeout.connect(_refresh)
	add_child(refresh)
	resized.connect(_place_notice)
	_localize()
	_refresh()
	set_process(false)


func _localize() -> void:
	text = Locale.t("chat.button")
	_close_picker()
	if _phrase >= 0:
		_update_notice_text()


func _refresh() -> void:
	NetworkManager.poll_battle_chat()
	disabled = not can_chat.call() or not NetworkManager.can_send_battle_chat()
	tooltip_text = Locale.t("chat.shortcuts" if NetworkManager.battle_chat_supported else "chat.unavailable")
	if disabled:
		_close_picker()


func _send(id: int) -> void:
	_close_picker()
	if can_chat.call() and NetworkManager.send_battle_chat(id) and (not _incoming or not _notice.visible):
		_show_phrase(id, false)
	_refresh()


func _receive(id: int) -> void:
	if can_chat.call():
		_refresh()
		_show_phrase(id, true)


func _show_phrase(id: int, incoming: bool) -> void:
	_phrase = id
	_incoming = incoming
	_update_notice_text()
	_notice.show()
	_expiry.start()


func _update_notice_text() -> void:
	_message.text = Locale.t("chat.received" if _incoming else "chat.sent", [_phrase_text(_phrase)])
	_place_notice.call_deferred()


func _place_notice() -> void:
	_notice.reset_size()
	_notice.position = Vector2(size.x - _notice.size.x, size.y + 8)


func _phrase_text(id: int) -> String:
	return Locale.t("chat." + NetworkManager.BATTLE_CHAT_PHRASES[id])


func _add_label(panel: PanelContainer, copy: String) -> Label:
	var label := Label.new()
	label.text = copy
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("keyword_literal", true)
	label.add_theme_font_size_override("font_size", 14)
	UITheme.apply_label(label)
	panel.add_child(label)
	return label


func _open_picker(group: int) -> void:
	if disabled or is_instance_valid(_picker) or UIMotion.top_popup() != null:
		return
	_group = group
	var popup := UITheme.make_popup_layer(self, 112)
	_picker = popup["layer"]
	_picker.name = "QuickChatChoices"
	_picker.set_meta("popup_close", _close_picker)
	var input_cover: ColorRect = popup["bg"]
	input_cover.color = Color.TRANSPARENT
	input_cover.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_picker())
	for item in CHOICES_PER_GROUP:
		var tag := PanelContainer.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UITheme.apply_panel(tag, "tooltip")
		_picker.add_child(tag)
		var id := group * CHOICES_PER_GROUP + item
		_add_label(tag, "%d  %s" % [item + 1, _phrase_text(id)])
		if OS.has_feature("mobile"):
			tag.mouse_filter = Control.MOUSE_FILTER_STOP
			tag.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					tag.accept_event()
					_send(id))
		_tags.append(tag)
	var timer := Timer.new()
	timer.wait_time = PICK_TIME
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_close_picker)
	_picker.add_child(timer)
	if OS.has_feature("mobile"):
		_pointer = get_viewport().get_visible_rect().size * 0.5
	set_process(true)
	_process(0.0)


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	var bounds := viewport.get_visible_rect().size
	var pointer := _pointer
	var widest := maxf(_tags[2].get_combined_minimum_size().x, _tags[3].get_combined_minimum_size().x)
	var side_space := minf(widest + 37.0, bounds.x * 0.5 - 10.0)
	var center := Vector2(clampf(pointer.x, side_space, bounds.x - side_space), clampf(pointer.y, 72, bounds.y - 72))
	for index in _tags.size():
		var tag := _tags[index]
		var extent := tag.get_combined_minimum_size()
		tag.size = extent
		match index:
			0: tag.position = center + Vector2(-extent.x * 0.5, -26.0 - extent.y)
			1: tag.position = center + Vector2(-extent.x * 0.5, 26.0)
			2: tag.position = center + Vector2(-30.0 - extent.x, -extent.y * 0.5)
			3: tag.position = center + Vector2(30.0, -extent.y * 0.5)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer = event.position
	if not event is InputEventKey or DevConsole.is_open() or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var id: int = event.keycode - KEY_1
	if event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_4:
		id = event.keycode - KEY_KP_1
	if id < 0 or id >= CHOICES_PER_GROUP:
		return
	var picking := is_instance_valid(_picker)
	if not picking and (id >= NetworkManager.BATTLE_CHAT_PHRASES.size() / CHOICES_PER_GROUP or disabled or UIMotion.top_popup() != null):
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if picking:
		_send(_group * CHOICES_PER_GROUP + id)
	else:
		_open_picker(id)


func _close_picker() -> void:
	if is_instance_valid(_picker):
		_picker.hide()
		_picker.queue_free()
	_picker = null
	_group = -1
	_tags.clear()
	set_process(false)

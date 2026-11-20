extends Control

var client: WorkshopBackend
var _items: GridContainer
var _status: Label
var _search: LineEdit
var _sort: OptionButton
var _account: Button
var _offset := 0
var _more: Button
var _loading := false
var _mine := false
var _discover_tab: Button
var _mine_tab: Button
var _empty: VBoxContainer
var _empty_title: Label
var _retry: Button
var _progress: ProgressBar
var _after_login: Callable
var _search_button: Button
var _catalog_scroll: ScrollContainer

func _ready() -> void:
	client = WorkshopProviders.create()
	add_child(client)
	var available := client.ready_for_use()
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.apply_app_background(background)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	margin.add_theme_constant_override("margin_top",80)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",16)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	layout.add_child(header)
	var title := Label.new()
	title.text = _t("创意工坊")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(title,28)
	header.add_child(title)
	_account = _button(_t("登录"),header,_account_pressed)
	UITheme.apply_button(_account, "utility")
	_account.visible = available
	var publish := _button(_t("上传卡包"),header,_upload_pressed)
	UITheme.apply_button(publish,"primary")
	publish.visible = available
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation",12)
	filters.visible = available
	layout.add_child(filters)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	filters.add_child(navigation)
	_discover_tab = _button(_t("发现"),navigation,func(): _show_mine(false))
	_mine_tab = _button(_t("我的上传"),navigation,func(): _show_mine(true))
	for tab in [_discover_tab, _mine_tab]:
		tab.toggle_mode = true
		UITheme.apply_button(tab, "navigation")
	_discover_tab.set_pressed_no_signal(true)
	_search = LineEdit.new()
	_search.placeholder_text = _t("搜索卡包")
	_search.max_length = 80
	_search.custom_minimum_size = Vector2(144, 44)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_input(_search)
	filters.add_child(_search)
	_search.text_submitted.connect(func(_text): _reload())
	_search_button = _button(_t("搜索"),filters,_reload)
	_sort = OptionButton.new()
	for text in [_t("最新上传"),_t("最多下载")]: _sort.add_item(text)
	UITheme.apply_button(_sort,"secondary")
	filters.add_child(_sort)
	_sort.item_selected.connect(func(_index): _reload())
	var divider := UITheme.separator()
	divider.visible = available
	layout.add_child(divider)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(_status)
	_status.hide()
	layout.add_child(_status)
	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 3
	layout.add_child(_progress)
	_empty = VBoxContainer.new()
	_empty.add_theme_constant_override("separation", 12)
	_empty.hide()
	layout.add_child(_empty)
	_empty_title = Label.new()
	_empty_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(_empty_title, true)
	_empty.add_child(_empty_title)
	_retry = _button(_t("重新加载"),_empty,_reload)
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	_catalog_scroll = ScrollContainer.new()
	_catalog_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.pad_scroll_content(_catalog_scroll,12)
	content.add_child(_catalog_scroll)
	_items = GridContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("h_separation",20)
	_items.add_theme_constant_override("v_separation",20)
	_catalog_scroll.add_child(_items)
	_more = _button(_t("加载更多"),layout,_load_more)
	_more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_more.hide()
	var back := _button(_t("返回"),self,func(): UIMotion.go_back("res://MainMenu.tscn"))
	UITheme.place_page_back(self,back)
	get_viewport().size_changed.connect(_fit_catalog)
	_fit_catalog()
	await client.restore_session()
	_refresh_account()
	_reload()

func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	UITheme.apply_button(button,"secondary")
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _fit_catalog() -> void:
	if _items == null: return
	var available := get_viewport_rect().size.x-88
	_items.columns = 3 if available >= 1120 else (2 if available >= 700 else 1)
	for tile in _items.get_children():
		tile.custom_minimum_size.x = maxf(310,(available-20*(_items.columns-1))/_items.columns)

func _refresh_account() -> void:
	_account.text = _t("登录") if not client.authenticated() else client.display_name()

func _show_mine(mine: bool) -> void:
	if _loading: return
	if mine and not client.authenticated():
		_discover_tab.set_pressed_no_signal(not _mine)
		_mine_tab.set_pressed_no_signal(_mine)
		_after_login = func(): _show_mine(true)
		_account_pressed()
		return
	_mine = mine
	_discover_tab.set_pressed_no_signal(not mine)
	_mine_tab.set_pressed_no_signal(mine)
	_reload()

func _reload() -> void:
	if _loading: return
	_offset = 0
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	_catalog_scroll.scroll_vertical = 0
	_load_page()

func _load_more() -> void:
	if not _loading: _load_page()

func _set_catalog_busy(busy: bool) -> void:
	for button in [_discover_tab,_mine_tab,_sort,_search_button]: button.disabled = busy

func _load_page() -> void:
	_loading = true
	_set_catalog_busy(true)
	_progress.show()
	_empty.hide()
	_status.hide()
	_more.disabled = true
	var result := await client.browse(_search.text,"popular" if _sort.selected == 1 else "new",_offset,_mine)
	_loading = false
	_set_catalog_busy(false)
	_progress.hide()
	_more.disabled = false
	_refresh_account()
	if not result.get("ok",false):
		var message := _t(str(result.get("error",_t("加载失败，请重试"))))
		if _offset == 0:
			_empty_title.text = message
			_retry.visible = client.ready_for_use()
			_empty.show()
		else:
			_status.text = message
			_status.show()
		_more.visible = _offset > 0
		return
	var entries: Array = result.get("items",[])
	for entry in entries: _add_entry(entry)
	_offset += entries.size()
	_more.visible = bool(result.get("has_more",false))
	if _offset == 0:
		_empty_title.text = _t("还没有上传卡包") if _mine else (_t("没有找到相关卡包") if not _search.text.is_empty() else _t("还没有卡包"))
		_retry.hide()
		_empty.show()
	_fit_catalog()

func _add_entry(entry: Dictionary) -> void:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_panel(tile, "dark")
	_items.add_child(tile)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,20)
	tile.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",20)
	margin.add_child(row)
	var preview := WorkshopCardPreview.new()
	row.add_child(preview)
	preview.bind_preview(entry.get("preview",{}))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation",10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := Label.new()
	title.text = str(entry.title)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	UITheme.apply_title(title,20)
	info.add_child(title)
	var author := Label.new()
	author.text = str(entry.author)
	author.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_label(author)
	info.add_child(author)
	var count := Label.new()
	count.text = _t("%d 张卡牌") % int(entry.count)
	UITheme.apply_label(count)
	info.add_child(count)
	if _mine:
		var state := Label.new()
		state.text = str({"pending":_t("待审核"),"published":_t("已发布"),"hidden":_t("已下架")}.get(str(entry.status),""))
		UITheme.apply_label(state)
		state.add_theme_color_override("font_color",UITheme.COLOR_GOLD if str(entry.status)=="pending" else UITheme.COLOR_BLUE)
		info.add_child(state)
	else:
		var downloads := Label.new()
		downloads.text = _t("下载 %d") % int(entry.downloads)
		UITheme.apply_label(downloads)
		info.add_child(downloads)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	var open := _button(_t("查看卡包"),info,func(): _view_package(entry))
	open.size_flags_horizontal = Control.SIZE_FILL
func _account_pressed() -> void:
	if not client.password_login():
		if client.authenticated(): client.open_account()
		else:
			_status.text = _t("请先登录 Steam 客户端")
			_status.show()
		return
	if not client.authenticated():
		_login_dialog()
		return
	var dialog := _dialog(_t("账号"),Vector2i(400,180))
	dialog.dialog_text = client.display_name()
	dialog.get_ok_button().text = _t("退出登录")
	dialog.confirmed.connect(func():
		await client.sign_out()
		_refresh_account()
		dialog.queue_free()
		if _mine: _show_mine(false))
	dialog.popup_centered()

func _dialog(title: String, minimum: Vector2i) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.min_size = minimum
	add_child(dialog)
	UITheme.apply_dialog(dialog,true)
	dialog.canceled.connect(dialog.queue_free)
	return dialog

func _text_field(label_text: String, box: Node, secret: bool = false, maximum: int = 128) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	UITheme.apply_label(label)
	box.add_child(label)
	var input := LineEdit.new()
	input.max_length = maximum
	input.secret = secret
	input.custom_minimum_size = Vector2(360,40)
	UITheme.apply_input(input)
	box.add_child(input)
	return input

func _login_dialog() -> void:
	var dialog := _dialog(_t("登录工坊"),Vector2i(460,400))
	dialog.canceled.connect(func(): _after_login = Callable())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	dialog.add_child(box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",12)
	box.add_child(tabs)
	var state := {"register":false}
	var group := ButtonGroup.new()
	var login_tab := _button(_t("登录"),tabs,func(): pass)
	var register_tab := _button(_t("注册"),tabs,func(): pass)
	register_tab.name = "RegisterTab"
	for tab in [login_tab,register_tab]:
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login_tab.set_pressed_no_signal(true)
	var name_input := _text_field(_t("用户名"),box,false,24)
	name_input.name = "UsernameInput"
	var password := _text_field(_t("密码"),box,true)
	password.name = "PasswordInput"
	password.placeholder_text = _t("输入密码")
	var invite := _text_field(_t("邀请码"),box,false,128)
	invite.name = "InviteCodeInput"
	invite.placeholder_text = _t("向邀请你的人索取")
	invite.hide()
	var invite_label: Label = box.get_child(invite.get_index()-1)
	invite_label.hide()
	var remember := CheckButton.new()
	remember.name = "RememberLogin"
	remember.text = _t("记住登录")
	box.add_child(remember)
	var notice := Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(notice)
	box.add_child(notice)
	dialog.get_ok_button().text = _t("登录")
	var switch_mode := func(registering: bool):
		state.register = registering
		invite.visible = registering
		invite_label.visible = registering
		password.placeholder_text = _t("至少 12 个字符") if registering else _t("输入密码")
		dialog.title = _t("注册工坊账号") if registering else _t("登录工坊")
		dialog.get_node("DialogCaption").queue_redraw()
		dialog.get_ok_button().text = _t("注册") if registering else _t("登录")
		notice.text = ""
	login_tab.pressed.connect(switch_mode.bind(false))
	register_tab.pressed.connect(switch_mode.bind(true))
	dialog.dialog_hide_on_ok = false
	dialog.confirmed.connect(func():
		if name_input.text.strip_edges().length() < 3:
			notice.text = _t("用户名至少 3 个字符")
			UITheme.reject_button(dialog.get_ok_button())
			return
		if password.text.length() < 12:
			notice.text = _t("密码至少 12 个字符")
			UITheme.reject_button(dialog.get_ok_button())
			return
		if state.register and invite.text.strip_edges().is_empty():
			notice.text = _t("请填写邀请码")
			UITheme.reject_button(dialog.get_ok_button())
			return
		dialog.get_ok_button().disabled = true
		notice.text = _t("正在连接…")
		var result := await client.sign_in(name_input.text,password.text,state.register,invite.text,remember.button_pressed)
		if not is_instance_valid(dialog): return
		dialog.get_ok_button().disabled = false
		password.clear()
		if result.get("ok",false):
			dialog.hide()
			dialog.queue_free()
			_refresh_account()
			var continuation := _after_login
			_after_login = Callable()
			if continuation.is_valid(): continuation.call_deferred()
			else: _reload()
		else: notice.text = _t(str(result.get("error",_t("登录失败，请重试")))))
	dialog.popup_centered()

func _upload_pressed() -> void:
	if not client.authenticated():
		_after_login = _upload_pressed
		_account_pressed()
		return
	var dialog := _dialog(_t("上传卡包"),Vector2i(720,500))
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 640
	box.add_theme_constant_override("separation",14)
	dialog.add_child(box)
	var selector := OptionButton.new()
	selector.name = "DeckPicker"
	selector.fit_to_longest_item = false
	selector.clip_text = true
	selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selector.custom_minimum_size.y = 42
	for deck in PlayerData.deck_library: selector.add_item(_t("%s（%d 张）") % [str(deck.get("name",_t("未命名"))),deck.get("cards",[]).size()])
	UITheme.apply_button(selector,"secondary")
	box.add_child(selector)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	box.add_child(row)
	var preview := WorkshopCardPreview.new()
	preview.custom_minimum_size = Vector2(156,216)
	row.add_child(preview)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation",10)
	row.add_child(form)
	var title := _text_field(_t("卡包名称"),form,false,80)
	title.name = "PackNameInput"
	title.custom_minimum_size.x = 0
	var description_label := Label.new()
	description_label.text = _t("介绍（选填）")
	UITheme.apply_label(description_label)
	form.add_child(description_label)
	var description := TextEdit.new()
	description.name = "PackDescriptionInput"
	description.custom_minimum_size = Vector2(0,104)
	description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	UITheme.apply_input(description)
	form.add_child(description)
	var consent := CheckButton.new()
	consent.name = "RightsConfirmation"
	consent.text = _t("我有权分享这些卡牌和图片")
	UITheme.apply_button(consent,"secondary",false)
	box.add_child(consent)
	var notice := Label.new()
	notice.custom_minimum_size.x = 640
	notice.text = _t("审核通过后，卡包会出现在工坊。")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(notice)
	box.add_child(notice)
	var select_deck := func(index: int):
		var deck: Dictionary = PlayerData.deck_library[index]
		title.text = str(deck.get("name",""))
		preview.visible = not deck.get("cards",[]).is_empty()
		if preview.visible: preview.bind_card(deck.cards[0])
	selector.item_selected.connect(select_deck)
	if not PlayerData.deck_library.is_empty():
		var selected := 0
		for index in range(PlayerData.deck_library.size()):
			if str(PlayerData.deck_library[index].get("id","")) == PlayerData.current_deck_id: selected = index
		selector.select(selected)
		select_deck.call(selected)
	dialog.dialog_hide_on_ok = false
	dialog.get_ok_button().text = _t("上传")
	dialog.confirmed.connect(func():
		if not consent.button_pressed:
			notice.text = _t("请先确认你有权分享这些卡牌和图片")
			UITheme.reject_button(consent)
			return
		if selector.selected < 0 or title.text.strip_edges().is_empty():
			notice.text = _t("请选择卡组并填写名称")
			UITheme.reject_button(dialog.get_ok_button())
			return
		if description.text.length() > 1200:
			notice.text = _t("介绍最多 1200 字")
			UITheme.reject_button(dialog.get_ok_button())
			return
		var deck: Dictionary = PlayerData.deck_library[selector.selected]
		var package := WorkshopClient.package_for_upload(deck)
		if package.get("cards",[]).is_empty():
			notice.text = _t("这个卡组还没有卡牌")
			return
		dialog.get_ok_button().disabled = true
		dialog.get_cancel_button().disabled = true
		notice.text = _t("正在上传…")
		var result := await client.publish(title.text,description.text,package,WorkshopClient.cover_for_deck(deck))
		if not is_instance_valid(dialog): return
		dialog.get_ok_button().disabled = false
		dialog.get_cancel_button().disabled = false
		if result.get("ok",false):
			dialog.queue_free()
			_show_mine(true)
		else: notice.text = _t(str(result.get("error",_t("上传失败，请重试")))))
	dialog.popup_centered(Vector2i(720,500))

func _view_package(entry: Dictionary) -> void:
	_status.text = _t("正在下载…")
	_status.show()
	var result := await client.download(str(entry.id))
	if not result.get("ok",false):
		_status.text = _t(str(result.get("error",_t("下载失败，请重试"))))
		return
	var parsed := PlayerData.parse_share_package(JSON.stringify(result.get("package",{})))
	if not parsed.get("ok",false):
		_status.text = _t("这个卡包无法导入，可能需要更新游戏")
		return
	_status.text = ""
	_status.hide()
	var package: Dictionary = parsed.package
	var dialog := WorkshopPackPreview.new()
	add_child(dialog)
	dialog.build(entry,package,_mine)
	dialog.canceled.connect(dialog.queue_free)
	dialog.report_requested.connect(func():
		dialog.hide()
		dialog.queue_free()
		_report(entry))
	dialog.withdraw_requested.connect(func():
		dialog.hide()
		dialog.queue_free()
		_confirm_remove(entry))
	dialog.confirmed.connect(func():
		var imported := PlayerData.import_package_as_new_deck(package,str(entry.title))
		_status.set_meta("keyword_literal",true)
		if imported.get("ok", false):
			_status.text = Locale.t("share.import_deck_done") % [imported["deck_name"], imported["added"]]
		else:
			_status.text = Locale.t("share.import_failed" if imported.get("invalid", false) else "share.import_save_failed")
		_status.show()
		dialog.queue_free())
	var viewport := get_viewport_rect().size
	dialog.popup_centered(Vector2i(mini(980,int(viewport.x)-64),mini(600,int(viewport.y)-64)))

func _confirm_remove(entry: Dictionary) -> void:
	var dialog := _dialog(_t("下架卡包"),Vector2i(420,180))
	dialog.dialog_text = _t("下架后，其他玩家将无法再下载这个卡包。")
	dialog.get_ok_button().text = _t("下架")
	dialog.confirmed.connect(func():
		var result := await client.withdraw(str(entry.id))
		if is_instance_valid(dialog): dialog.queue_free()
		if result.get("ok",false): _reload()
		else:
			_status.text = _t(str(result.get("error",_t("操作失败，请重试"))))
			_status.show())
	dialog.popup_centered()

func _report(entry: Dictionary) -> void:
	if not client.authenticated():
		_after_login = _report.bind(entry)
		_account_pressed()
		return
	var dialog := _dialog(_t("举报卡包"),Vector2i(440,220))
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var reason := _text_field(_t("举报原因"),box,false,500)
	var notice := Label.new()
	box.add_child(notice)
	dialog.dialog_hide_on_ok = false
	dialog.confirmed.connect(func():
		dialog.get_ok_button().disabled = true
		var result := await client.report(str(entry.id),reason.text)
		if not is_instance_valid(dialog): return
		dialog.get_ok_button().disabled = false
		if result.get("ok",false):
			_status.text = _t("已收到举报")
			_status.show()
			dialog.queue_free()
		else: notice.text = _t(str(result.get("error",_t("提交失败，请重试")))))
	dialog.popup_centered()


func _t(text: String) -> String:
	return WorkshopText.t(text)

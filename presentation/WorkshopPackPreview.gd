class_name WorkshopPackPreview
extends ConfirmationDialog

signal report_requested
signal withdraw_requested
const Descriptions = preload("res://presentation/SkillDescription.gd")
var _cards: Array[CardData] = []
var _details: VBoxContainer
var _grid: GridContainer
var _selection := ButtonGroup.new()

func build(entry: Dictionary, package: Dictionary, own: bool, local: bool = false) -> void:
	UITheme.apply_dialog(self,true)
	title = str(entry.get("title",_t("卡包")))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	add_child(box)
	var byline := Label.new()
	byline.set_meta("keyword_literal",true)
	byline.text = _t("%s    %d 张卡牌") % [str(entry.get("author","")),package.get("cards",[]).size()]
	UITheme.apply_label(byline)
	box.add_child(byline)
	var description := Label.new()
	description.set_meta("keyword_literal",true)
	description.text = str(entry.get("description",""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 650
	description.max_lines_visible = 3
	UITheme.apply_label(description)
	description.visible = not description.text.is_empty()
	box.add_child(description)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390,280)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.pad_scroll_content(scroll,12)
	row.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation",12)
	_grid.add_theme_constant_override("v_separation",12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	var divider := VSeparator.new()
	UITheme.apply_separator(divider)
	row.add_child(divider)
	var info_scroll := ScrollContainer.new()
	info_scroll.custom_minimum_size.x = 250
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.pad_scroll_content(info_scroll,8)
	row.add_child(info_scroll)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override("separation",14)
	info_scroll.add_child(_details)
	for data in package.get("cards",[]):
		var card := PlayerData.deserialize_card(data)
		PlayerData._restore_shared_art(card,data)
		_cards.append(card)
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _selection
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(164,224)
		var style := UITheme.panel_style(Color.TRANSPARENT,Color.TRANSPARENT,1,4)
		for edge in ["left","right","top","bottom"]: style.set("content_margin_"+edge,8)
		button.add_theme_stylebox_override("normal",style)
		var hover: StyleBoxFlat = style.duplicate()
		hover.border_color = Color(UITheme.COLOR_BLUE,0.6)
		button.add_theme_stylebox_override("hover",hover)
		var selected: StyleBoxFlat = style.duplicate()
		selected.border_color = UITheme.COLOR_GOLD
		selected.set_border_width_all(2)
		button.add_theme_stylebox_override("pressed",selected)
		button.add_theme_stylebox_override("hover_pressed",selected)
		_grid.add_child(button)
		var preview := WorkshopCardPreview.new()
		button.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_left = 8
		preview.offset_top = 8
		preview.offset_right = -8
		preview.offset_bottom = -8
		preview.bind_card(card)
		button.pressed.connect(func(): _show_card(card))
	if not _cards.is_empty():
		_grid.get_child(0).set_pressed_no_signal(true)
		_show_card(_cards[0])
	get_ok_button().text = _t("导入为新卡组")
	get_cancel_button().text = _t("返回")
	if local: return
	var extra := add_button(_t("下架") if own else _t("举报"),true,"withdraw" if own else "report")
	UITheme.apply_button(extra,"secondary")
	custom_action.connect(func(action: String):
		if action == "withdraw": withdraw_requested.emit()
		elif action == "report": report_requested.emit())

func _show_card(card: CardData) -> void:
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.set_meta("keyword_literal",true)
	title.text = card.card_name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(title,22)
	_details.add_child(title)
	if not card.is_spell():
		var stats := Label.new()
		stats.text = Locale.t("tabletop.stats", [card.effective_atk(), card.hp, card.max_hp])
		UITheme.apply_label(stats)
		_details.add_child(stats)
	var abilities := Descriptions.build_read_only_abilities(card)
	if abilities.get_child_count() == 0:
		abilities.free()
		return
	var frame := Descriptions.make_abilities_frame()
	frame.add_child(abilities)
	_details.add_child(frame)


func _t(text: String) -> String:
	return WorkshopText.t(text)

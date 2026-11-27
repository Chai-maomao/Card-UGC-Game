extends Control

# ============================================
# My Cards — deck manager + card/deck sharing
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const OPEN_DECK_ROUTE := "collection_deck:"
const DECK_MANAGER_ROUTE := "collection_manager:"
enum CardSort { DECK_ORDER, COST, MODIFIED, ATTACK, DEFENSE }

static var _sort_by := CardSort.DECK_ORDER
static var _sort_descending := false

var card_ui_scene = preload("res://CardUI.tscn")

@onready var panel = $Panel
@onready var root_box = $Panel/VBoxContainer
@onready var top_bar = $Panel/VBoxContainer/TopBar
@onready var title_label = $Panel/VBoxContainer/TopBar/TitleLabel
@onready var scroll_container = $Panel/VBoxContainer/ScrollContainer
@onready var card_grid = $Panel/VBoxContainer/ScrollContainer/CardGrid

var _page_back: Button
var _create_card_button: Button
var _sort_direction: Button
var _selection_count: Label
var _selection_actions: Array[Button] = []
var _collection_tools: VBoxContainer
var _content_margin: MarginContainer
var action_bar: HFlowContainer
var mode: String = "decks"
var selected_deck_id: String = ""
var selected_instance_ids: Dictionary = {}
var pending_export_text: String = ""
var pending_export_name: String = "Cardex-Cards.json"
var pending_import_mode: String = ""
var pending_import_package: Dictionary = {}
var pending_import_prepared: Dictionary = {}
var pending_conflicts: Array = []


func _ready():
	var restore_state := UIMotion.consume_restore_state()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	scroll_container.follow_focus = true
	_apply_theme()
	var collection_list := VBoxContainer.new()
	collection_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	collection_list.add_theme_constant_override("separation", 0)
	root_box.add_child(collection_list)
	_collection_tools = VBoxContainer.new()
	_collection_tools.add_theme_constant_override("separation", UITheme.Tokens.SPACING[2])
	collection_list.add_child(_collection_tools)
	scroll_container.reparent(collection_list, false)
	_content_margin = MarginContainer.new()
	scroll_container.add_child(_content_margin)
	card_grid.reparent(_content_margin, false)
	action_bar = HFlowContainer.new()
	action_bar.name = "CollectionActions"
	action_bar.add_theme_constant_override("h_separation", 10)
	action_bar.add_theme_constant_override("v_separation", 8)
	_collection_tools.add_child(action_bar)
	var divider := UITheme.separator()
	divider.add_theme_constant_override("separation", 1)
	_collection_tools.add_child(divider)
	_ensure_deck_state()
	var deck_id := PlayerData.return_to_deck_id
	PlayerData.return_to_deck_id = ""
	if restore_state.begins_with(OPEN_DECK_ROUTE):
		deck_id = restore_state.trim_prefix(OPEN_DECK_ROUTE)
	if not deck_id.is_empty() and not PlayerData.get_deck(deck_id).is_empty():
		_show_deck_cards(deck_id)
		if restore_state.begins_with("collection_create:"):
			_create_card_button.grab_focus()
	else:
		var focus_deck_id := restore_state.trim_prefix(DECK_MANAGER_ROUTE) if restore_state.begins_with(DECK_MANAGER_ROUTE) else ""
		_show_deck_manager(focus_deck_id)


func _apply_theme() -> void:
	UITheme.apply_app_background(self)
	UITheme.apply_app_background(panel)
	UITheme.apply_title(title_label, max(18, int(24 * _ui_scale())))


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ensure_deck_state() -> void:
	if PlayerData.deck_library.is_empty() and not PlayerData.card_library.is_empty():
		PlayerData.create_deck(Locale.t("deck.default_name"), PlayerData.card_library)


func _clear_top_bar() -> void:
	_selection_count = null
	_selection_actions.clear()
	if is_instance_valid(_page_back): _page_back.queue_free()
	for child in top_bar.get_children():
		child.queue_free()
	if action_bar:
		for child in action_bar.get_children(): child.queue_free()


func _clear_grid() -> void:
	for child in card_grid.get_children():
		child.queue_free()


func _add_top_button(text: String, callback: Callable, variant: String = "secondary") -> Button:
	var btn := Button.new()
	btn.text = text
	UITheme.apply_button(btn, variant)
	btn.pressed.connect(callback)
	btn.custom_minimum_size = Vector2(110, 40) * _ui_scale()
	action_bar.add_child(btn)
	if text == Locale.t("common.back"):
		UITheme.place_page_back(self, btn)
		_page_back = btn
	return btn


func _set_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_title(label, max(14, int(24 * _ui_scale())))
	top_bar.add_child(label)
	title_label = label


func _show_deck_manager(focus_deck_id := "") -> void:
	mode = "decks"
	_collection_tools.hide()
	selected_deck_id = ""
	selected_instance_ids.clear()
	_clear_top_bar()
	_clear_grid()
	_set_title(Locale.t("deck.manager_title"))
	_add_top_button(Locale.t("share.import_deck"), _on_import_deck_pressed, "utility").reparent(top_bar, false)
	_add_top_button(Locale.t("deck.new"), _on_create_deck_pressed, "primary").reparent(top_bar, false)
	_add_top_button(Locale.t("common.back"), _on_back_to_menu_pressed)
	card_grid.columns = 2
	for deck in PlayerData.deck_library:
		_add_deck_slot(deck, deck.get("id", "") == focus_deck_id)
	_apply_responsive_layout()


func _show_deck_cards(deck_id: String) -> void:
	var entering := mode != "cards" or selected_deck_id != deck_id
	mode = "cards"
	_collection_tools.show()
	selected_deck_id = deck_id
	PlayerData.current_deck_id = deck_id
	selected_instance_ids.clear()
	_clear_top_bar()
	_clear_grid()
	var deck := PlayerData.get_deck(deck_id)
	_set_title(Locale.t("deck.cards_title") % PlayerData.deck_display_name(deck))
	_add_deck_file_buttons()
	_create_card_button = _add_top_button(Locale.t("mycards.create_new"), _on_create_new_pressed, "primary")
	_create_card_button.reparent(top_bar, false)
	_selection_count = Label.new()
	_selection_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_label(_selection_count, true)
	action_bar.add_child(_selection_count)
	_selection_actions.append(_add_top_button(Locale.t("mycards.delete_selected"), _on_delete_selected_pressed, "utility"))
	var copy_button := _add_top_button(Locale.t("deck.copy_to"), _on_copy_selected_pressed, "utility")
	copy_button.set_meta("keyword_literal", true)
	_selection_actions.append(copy_button)
	for button in _selection_actions:
		button.custom_minimum_size.x = 0
		button.add_theme_color_override("font_disabled_color", UITheme.COLOR_TEXT_MUTED.darkened(0.20))
	_refresh_selection_actions()
	_add_top_button(Locale.t("common.back"), _on_back_pressed)
	_add_sort_controls()
	card_grid.columns = 4
	for card in PlayerData.get_cards_for_deck(deck_id):
		_add_card_box(card)
	_sort_card_grid()
	_apply_responsive_layout()
	if entering:
		UITheme.animate_list_enter(card_grid, UITheme.Tokens.SPACING[4] * _ui_scale())


func _add_deck_file_buttons() -> void:
	var import_button := _add_top_button(Locale.t("share.import_append"), _on_import_append_pressed, "utility")
	var export_deck := _add_top_button(Locale.t("share.export_deck"), _on_export_current_deck_pressed, "utility")
	var export_selected := _add_top_button(Locale.t("share.export_selected"), _on_export_selected_pressed, "utility")
	for button in [import_button, export_deck, export_selected]:
		button.custom_minimum_size.x = 0
		button.reparent(top_bar, false)
	_selection_actions.append(export_selected)


func _refresh_selection_actions() -> void:
	_selection_count.text = Locale.t("mycards.selected_count") % selected_instance_ids.size()
	for button in _selection_actions:
		button.disabled = selected_instance_ids.is_empty()


func _add_sort_controls() -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_bar.add_child(spacer)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	action_bar.add_child(controls)
	var field := OptionButton.new()
	field.name = "CardSortField"
	field.tooltip_text = Locale.t("mycards.sort_tooltip")
	for key in ["deck_order", "cost", "modified", "attack", "defense"]:
		field.add_item(Locale.t("mycards.sort_" + key))
	field.select(_sort_by)
	field.custom_minimum_size.y = 40 * _ui_scale()
	UITheme.apply_button(field, "secondary")
	controls.add_child(field)
	_sort_direction = Button.new()
	_sort_direction.name = "CardSortDirection"
	UITheme.apply_button(_sort_direction, "secondary")
	controls.add_child(_sort_direction)
	field.item_selected.connect(func(index: int):
		_sort_by = index as CardSort
		_update_sort_direction()
		_sort_card_grid())
	_sort_direction.pressed.connect(func():
		_sort_descending = not _sort_descending
		_update_sort_direction()
		_sort_card_grid())
	_update_sort_direction()


func _update_sort_direction() -> void:
	_sort_direction.disabled = _sort_by == CardSort.DECK_ORDER
	_sort_direction.text = Locale.t("mycards.sort_descending" if _sort_descending else "mycards.sort_ascending")


func _sort_card_grid() -> void:
	var ranked: Array = []
	for tile in card_grid.get_children():
		if not tile.is_queued_for_deletion():
			var card: CardData = tile.get_child(0).current_card_data
			ranked.append({"tile": tile, "value": _card_sort_value(card), "position": tile.get_meta("deck_position")})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.value == b.value: return a.position < b.position
		if _sort_by == CardSort.MODIFIED and (a.value == 0 or b.value == 0): return a.value != 0
		return a.value > b.value if _sort_descending else a.value < b.value)
	for index in ranked.size():
		card_grid.move_child(ranked[index].tile, index)


func _card_sort_value(card: CardData) -> int:
	match _sort_by:
		CardSort.COST: return card.base_cost
		CardSort.MODIFIED: return PlayerData.card_modified_at(card)
		CardSort.ATTACK: return card.base_atk
		CardSort.DEFENSE: return card.base_max_hp
	return 0


func _add_deck_slot(deck: Dictionary, restore_focus := false) -> void:
	var s := _ui_scale()
	var slot := PanelContainer.new()
	slot.custom_minimum_size.x = 440 * s
	card_grid.add_child(slot)
	UITheme.apply_panel(slot, "dark")
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	slot.add_child(content)
	var cover := TextureRect.new()
	cover.name = "DeckCover"
	cover.custom_minimum_size = Vector2(96, 96) * s
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.texture = CardArtwork.deck_cover(deck)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cover.texture != null:
		content.add_child(cover)
	else:
		cover.free()
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", max(4, int(8 * s)))
	content.add_child(box)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	box.add_child(heading)
	var name_label := Label.new()
	name_label.set_meta("keyword_literal",true)
	name_label.text = PlayerData.deck_display_name(deck)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_title(name_label, max(14, int(22 * s)))
	heading.add_child(name_label)
	var count_label := Label.new()
	count_label.text = Locale.t("deck.card_count") % deck.get("cards", []).size()
	count_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_label(count_label, true)
	heading.add_child(count_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", max(2, int(6 * s)))
	box.add_child(row)
	var open := _add_row_button(row, Locale.t("deck.open"), _open_deck.bind(deck.get("id", "")))
	open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UITheme.apply_button(open, "outlined", false)
	if restore_focus:
		open.grab_focus.call_deferred()
	row.add_spacer(false)
	var more := MenuButton.new()
	more.text = Locale.t("common.more_actions")
	more.icon = more.get_theme_icon("arrow", "OptionButton")
	more.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.apply_button(more, "utility")
	row.add_child(more)
	var menu := more.get_popup()
	menu.add_item(Locale.t("deck.rename"), 0)
	menu.add_item(Locale.t("deck.set_cover"), 3)
	menu.set_item_disabled(menu.get_item_index(3), deck.get("cards", []).is_empty())
	menu.add_item(Locale.t("share.export_deck"), 1)
	menu.add_separator()
	menu.add_item(Locale.t("mycards.delete"), 2)
	var deck_id: String = deck.get("id", "")
	menu.id_pressed.connect(func(id: int):
		var current := PlayerData.get_deck(deck_id)
		if current.is_empty(): return
		match id:
			0:
				_show_rename_deck_popup(current)
			1:
				_export_deck(current)
			2:
				_delete_deck(deck_id)
			3:
				_choose_deck_cover(current, cover)
	)

func _choose_deck_cover(deck: Dictionary, preview: TextureRect) -> void:
	var deck_id: String = deck["id"]
	var dialog := preload("res://CardCollectionDialog.gd").new()
	dialog.cards = deck.get("cards", []).duplicate()
	dialog.heading = Locale.t("deck.set_cover")
	dialog.pick_limit = 1
	dialog.allow_empty_selection = true
	dialog.replace_single_selection = true
	dialog.empty_selection_text = Locale.t("deck.auto_cover")
	dialog.on_confirm = func(chosen: Array):
		var cover_id: String = "" if chosen.is_empty() else chosen[0].instance_id
		if not PlayerData.set_deck_cover(deck_id, cover_id):
			_show_message(Locale.t("deck.cover_save_failed"))
		elif is_instance_valid(preview):
			preview.texture = CardArtwork.deck_cover(PlayerData.get_deck(deck_id))
	add_child(dialog)
	var current: String = deck.get("cover_instance_id", "")
	if current.is_empty(): return
	var index := PlayerData.find_deck_card_index(deck_id, current)
	if index >= 0:
		dialog._select(true, index)
		dialog.scroll.ensure_control_visible.call_deferred(dialog.card_uis[index])


func _add_row_button(row: HBoxContainer, text: String, callback: Callable, variant: String = "utility") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(btn, variant)
	btn.pressed.connect(callback)
	row.add_child(btn)
	return btn


func _add_card_box(card_data: CardData) -> void:
	var s := _ui_scale()
	var card_width: float = 120.0 * s
	var row_gap: int = max(1, int(2 * s))
	var card_box := VBoxContainer.new()
	card_box.custom_minimum_size = Vector2(card_width, 224 * s)
	card_box.add_theme_constant_override("separation", max(2, int(4 * s)))
	card_grid.add_child(card_box)
	card_box.set_meta("deck_position", card_box.get_index())

	var card_ui_instance = card_ui_scene.instantiate()
	card_box.add_child(card_ui_instance)
	card_ui_instance.set_card(card_data)
	card_ui_instance.set_battle_layout_preview(true)
	card_ui_instance.apply_ui_scale(s)
	var selection := preload("res://presentation/CardSelectionOverlay.gd").new()
	card_ui_instance.add_child(selection)
	selection.set_pressed_no_signal(selected_instance_ids.has(card_data.instance_id))
	selection.toggled.connect(func(pressed: bool):
		if pressed: selected_instance_ids[card_data.instance_id] = true
		else: selected_instance_ids.erase(card_data.instance_id)
		_refresh_selection_actions())

	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size = Vector2(card_width, 28 * s)
	btn_row.add_theme_constant_override("separation", row_gap)
	card_box.add_child(btn_row)
	_add_row_button(btn_row, Locale.t("mycards.edit"), func(): _on_edit_card(card_data.instance_id))
	_add_row_button(btn_row, Locale.t("mycards.delete"), func(): _on_delete_card(card_data.instance_id))


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var margin: int = max(16, int(36 * s))
	panel.offset_left = margin
	panel.offset_top = maxf(80, margin)
	panel.offset_right = -margin
	panel.offset_bottom = 0
	var inset := maxi(16, int(24 * s))
	root_box.offset_left = inset
	root_box.offset_top = 0
	root_box.offset_right = -inset
	root_box.offset_bottom = -maxi(10, roundi(12 * s))
	var section_gap := maxi(12, int(20 * s))
	root_box.add_theme_constant_override("separation", section_gap)
	_content_margin.add_theme_constant_override("margin_top", section_gap if mode == "cards" else 0)
	card_grid.add_theme_constant_override("h_separation", int(24 * s))
	card_grid.add_theme_constant_override("v_separation", int(24 * s))
	card_grid.columns = maxi(1, int((get_viewport_rect().size.x - margin * 2 - inset * 2) / ((160 if mode == "cards" else 464) * s)))
	scroll_container.custom_minimum_size = Vector2.ZERO
	top_bar.add_theme_constant_override("separation", max(4, int(8 * s)))
	for child in top_bar.get_children():
		if child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	if action_bar:
		for child in action_bar.get_children():
			if child is Button: child.add_theme_font_size_override("font_size", maxi(13, int(15 * s)))


func _on_create_deck_pressed() -> void:
	_show_text_input_popup(Locale.t("deck.new"), Locale.t("deck.name"), Locale.t("deck.default_name"), func(new_name: String):
		var deck := PlayerData.create_deck(new_name)
		_open_deck(deck.get("id", ""))
	)


func _open_deck(deck_id: String) -> void:
	UIMotion.replace_scene(scene_file_path, false, OPEN_DECK_ROUTE + deck_id)


func _show_rename_deck_popup(deck: Dictionary) -> void:
	_show_text_input_popup(Locale.t("deck.rename"), Locale.t("deck.name"), deck.get("name", ""), func(new_name: String):
		deck["name"] = new_name
		PlayerData.save_library()
		_show_deck_manager()
	)


func _delete_deck(deck_id: String) -> void:
	if PlayerData.deck_library.size() <= 1:
		_show_message(Locale.t("deck.keep_one"))
		return
	_show_confirm_dialog(Locale.t("mycards.confirm_delete_deck"), func():
		for i in range(PlayerData.deck_library.size()):
			if PlayerData.deck_library[i].get("id", "") == deck_id:
				PlayerData.deck_library.pop_at(i)
				break
		PlayerData.save_library()
		_show_deck_manager()
	)


func _on_create_new_pressed() -> void:
	var page := preload("res://SelectionMenu.gd").new()
	page.name = "CollectionCardType"
	page.layer = 110
	page.heading = Locale.t("editor.create_new_card")
	page.backdrop = Color(Color.BLACK, 0.68)
	page.blur_backdrop = true
	_create_card_button.grab_focus()
	add_child(page)
	var first_choice := page.add_choice(Locale.t("editor.create_minion"), _create_card_in_deck.bind(PlayerData.init_card_draft, "editor.create_minion"),
		SkillHelp.description("card_type", "minion"))
	page.add_choice(Locale.t("editor.create_spell"), _create_card_in_deck.bind(PlayerData.init_spell_draft, "editor.create_spell"),
		SkillHelp.description("card_type", "spell"))
	page.add_choice(Locale.t("editor.create_parasite"), _create_card_in_deck.bind(PlayerData.init_parasite_draft, "editor.create_parasite"),
		SkillHelp.description("card_type", "parasite"))
	UIMotion.register_popup(page, first_choice)
	page.finish()
	UITheme.fade_enter(page.surface, 0.16)


func _create_card_in_deck(initialize: Callable, entry: String) -> void:
	PlayerData.current_deck_id = selected_deck_id
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_editor_return_scene = "res://MyCards.tscn"
	PlayerData.return_to_deck_id = selected_deck_id
	initialize.call()
	UIMotion.change_scene("res://CardEditor.tscn", "collection_create:" + entry)


func _on_edit_card(instance_id: String):
	if UIMotion.is_transitioning():
		return
	var index := PlayerData.find_deck_card_index(selected_deck_id, instance_id)
	if index < 0:
		return
	var card: CardData = PlayerData.get_cards_for_deck(selected_deck_id)[index]
	PlayerData.editing_deck_id = selected_deck_id
	PlayerData.editing_instance_id = instance_id
	PlayerData.editing_index = index
	PlayerData.card_editor_return_scene = "res://MyCards.tscn"
	PlayerData.return_to_deck_id = selected_deck_id
	PlayerData.load_card_to_draft(card)
	UIMotion.change_scene("res://CardEditor.tscn")


func _on_delete_card(instance_id: String):
	_show_confirm_dialog(Locale.t("mycards.confirm_delete_card"), func():
		if PlayerData.remove_deck_card(selected_deck_id, instance_id):
			_show_deck_cards(selected_deck_id)
	)


func _on_delete_selected_pressed() -> void:
	var ids := selected_instance_ids.keys().filter(func(id): return PlayerData.find_deck_card(selected_deck_id,id) != null)
	if ids.is_empty():
		_show_message("请先勾选要删除的卡牌。" if Locale.language == "zh" else "Select cards to delete first.")
		return
	var deck_id := selected_deck_id
	_show_confirm_dialog(Locale.t("mycards.confirm_delete_selected",[ids.size()]),func():
		if PlayerData.remove_deck_cards(deck_id,ids)>0:
			_show_deck_cards(deck_id)
		else:
			_show_message("未能删除卡牌，请重试。" if Locale.language == "zh" else "Could not delete the cards. Please try again."))


func _on_back_to_menu_pressed():
	UIMotion.go_back("res://MainMenu.tscn")


func _on_back_pressed() -> void:
	if mode == "cards":
		UIMotion.replace_scene(scene_file_path, false, DECK_MANAGER_ROUTE + selected_deck_id)
	else:
		_on_back_to_menu_pressed()


func _on_export_selected_pressed() -> void:
	var cards: Array = []
	for instance_id in selected_instance_ids.keys():
		var card := PlayerData.find_deck_card(selected_deck_id, instance_id)
		if card != null:
			cards.append(card)
	if cards.is_empty():
		_show_message(Locale.t("share.no_selection"))
		return
	pending_export_text = PlayerData.serialize_cards_for_share(cards)
	pending_export_name = "Cardex-Cards.json"
	_show_save_dialog()


func _on_export_current_deck_pressed() -> void:
	_export_deck(PlayerData.get_deck(selected_deck_id))


func _on_copy_selected_pressed() -> void:
	if selected_instance_ids.is_empty():
		_show_message(Locale.t("share.no_selection"))
		return
	_show_copy_to_decks_popup()


func _show_copy_to_decks_popup() -> void:
	var popup := UITheme.make_popup_layer(self, 115)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -220
	panel_box.offset_top = -180
	panel_box.offset_right = 220
	panel_box.offset_bottom = 180
	UITheme.apply_popup_frame(panel_box, "gold")
	layer.add_child(panel_box)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel_box.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("deck.copy_to")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	var target_ids: Dictionary = {}
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(deck_scroll)
	var deck_box := VBoxContainer.new()
	deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_box.add_theme_constant_override("separation", 6)
	deck_scroll.add_child(deck_box)
	for deck in PlayerData.deck_library:
		var deck_id: String = deck.get("id", "")
		if deck_id == selected_deck_id:
			continue
		var check := CheckBox.new()
		check.text = PlayerData.deck_display_name(deck)
		UITheme.apply_button(check, "secondary")
		check.toggled.connect(func(pressed: bool):
			if pressed:
				target_ids[deck_id] = true
			else:
				target_ids.erase(deck_id)
		)
		deck_box.add_child(check)
	var row := HBoxContainer.new()
	box.add_child(row)
	_add_row_button(row, Locale.t("battle.confirm"), func():
		layer.queue_free()
		var batch := PlayerData.prepare_card_copies(selected_deck_id, selected_instance_ids.keys(), target_ids.keys())
		_show_next_copy_conflict(batch)
	)
	_add_row_button(row, Locale.t("skill_editor.cancel"), layer.queue_free)


func _show_next_copy_conflict(batch: Dictionary) -> void:
	var conflicts: Array = batch.conflicts
	while not conflicts.is_empty():
		var conflict: Dictionary = conflicts.pop_front()
		var deck_id: String = conflict.target_deck_id
		var incoming: CardData = conflict.incoming
		var cards: Array = batch.card_lists[deck_id]
		var current := PlayerData.find_card_conflict(cards, incoming)
		match current.kind:
			"none":
				cards.append(PlayerData.prepare_deck_card(incoming))
				batch.added += 1
			"same":
				batch.skipped += 1
			"conflict":
				var local: CardData = current.card
				conflict["local"] = local
				_show_card_conflict_popup(conflict, false, _apply_copy_choice.bind(batch, cards, local, incoming), batch)
				return
	if batch.added + batch.overwritten > 0 and not PlayerData.save_deck_card_lists(batch.card_lists):
		_show_message(Locale.t("deck.copy_failed"))
		return
	_show_message(Locale.t("deck.copy_done") % [batch.added, batch.overwritten, batch.skipped])


func _apply_copy_choice(action: String, new_name: String, batch: Dictionary, cards: Array, local: CardData, incoming: CardData) -> void:
	var copy := PlayerData.prepare_deck_card(incoming)
	if action == "replace":
		copy.instance_id = local.instance_id
		copy.set_meta(&"modified_at", int(Time.get_unix_time_from_system()))
		cards[cards.find(local)] = copy
		batch.overwritten += 1
	else:
		copy.card_name = new_name
		cards.append(copy)
		batch.added += 1
	_show_next_copy_conflict(batch)


func _copy_name_taken(card_name: String, batch: Dictionary, deck_id: String) -> bool:
	for card: CardData in batch.card_lists[deck_id]:
		if card.card_name == card_name:
			return true
	return false


func _export_deck(deck: Dictionary) -> void:
	if deck.is_empty():
		return
	pending_export_text = PlayerData.serialize_deck_for_share(deck)
	pending_export_name = "Cardex-Deck-%s.json" % deck.get("name", "Deck")
	_show_save_dialog()


func _on_import_deck_pressed() -> void:
	pending_import_mode = "deck_manager"
	_show_open_dialog()


func _on_import_append_pressed() -> void:
	pending_import_mode = "deck_append"
	_show_open_dialog()


func _show_save_dialog() -> void:
	var package: Dictionary = JSON.parse_string(pending_export_text)
	SharePackage.edit_metadata(self, package, func(updated: Dictionary):
		pending_export_text = JSON.stringify(updated, "\t")
		_show_export_file_dialog()
	)


func _show_export_file_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON"])
	dialog.current_file = pending_export_name
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_show_message(Locale.t("share.export_failed"))
		else:
			file.store_string(pending_export_text)
			file.close()
			_show_message(Locale.t("share.export_done"))
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	UITheme.apply_dialog(dialog, true)
	dialog.popup_centered_ratio(0.75)


func _show_open_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON"])
	dialog.file_selected.connect(func(path: String):
		_import_from_file(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	UITheme.apply_dialog(dialog, true)
	dialog.popup_centered_ratio(0.75)


func _import_from_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_message(Locale.t("share.import_failed"))
		return
	var text := file.get_as_text()
	file.close()
	var parsed := PlayerData.parse_share_package(text)
	if not parsed.get("ok", false):
		_show_message(Locale.t("share.import_failed"))
		return
	pending_import_package = parsed.get("package", {})
	var preview := ConfirmationDialog.new()
	preview.title = "导入预览" if Locale.language == "zh" else "Import preview"
	preview.dialog_text = SharePackage.summary(pending_import_package)
	preview.get_ok_button().text = "继续导入" if Locale.language == "zh" else "Continue"
	preview.get_cancel_button().text = "取消" if Locale.language == "zh" else "Cancel"
	preview.confirmed.connect(func():
		preview.queue_free()
		_accept_import_preview(path)
	)
	preview.canceled.connect(preview.queue_free)
	add_child(preview)
	UITheme.apply_dialog(preview, true)
	preview.popup_centered(Vector2i(650, 300))


func _accept_import_preview(path: String) -> void:
	if pending_import_mode == "deck_manager":
		_finish_deck_manager_import(path)
		return
	pending_import_prepared = PlayerData.prepare_import_cards(pending_import_package, selected_deck_id)
	pending_conflicts = pending_import_prepared.get("conflicts", [])
	if not pending_conflicts.is_empty():
		_show_next_conflict()
		return
	_finish_import()


func _finish_deck_manager_import(path: String) -> void:
	var deck_name := path.get_file().get_basename()
	if path.begins_with("content://"):
		# A document provider may expose an opaque ID instead of a filename.
		deck_name = str(pending_import_package.get("deck", {}).get("name", ""))
	var result := PlayerData.import_package_as_new_deck(pending_import_package, deck_name)
	_clear_pending_import()
	if not result.get("ok", false):
		_show_message(Locale.t("share.import_failed" if result.get("invalid", false) else "share.import_save_failed"))
		return
	_show_message(Locale.t("share.import_deck_done") % [result["deck_name"], result["added"]])
	_show_deck_manager()


func _show_next_conflict() -> void:
	while not pending_conflicts.is_empty():
		var conflict: Dictionary = pending_conflicts.pop_front()
		var incoming: CardData = conflict["incoming"]
		var staged := _pending_import_entry(incoming.card_name)
		var local: CardData = staged.get("card")
		if local == null:
			for card in _import_target_cards():
				if card.card_name == incoming.card_name:
					local = card
					break
		if local == null:
			pending_import_prepared["incoming"].append({"card": incoming, "share_id": conflict["share_id"]})
			continue
		if PlayerData.cards_have_same_content(local, incoming):
			pending_import_prepared["skipped"].append(incoming)
			if staged.is_empty():
				pending_import_prepared["id_map"][conflict["share_id"]] = local.instance_id
			continue
		conflict["local"] = local
		_show_card_conflict_popup(conflict, not staged.is_empty(), func(action: String, new_name: String):
			_apply_import_choice(conflict, staged, action, new_name)
			_show_next_conflict()
		)
		return
	_finish_import()


func _pending_import_entry(card_name: String) -> Dictionary:
	for item: Dictionary in pending_import_prepared.get("incoming", []):
		if item["card"].card_name == card_name:
			return item
	return {}


func _apply_import_choice(conflict: Dictionary, staged: Dictionary, action: String, new_name: String) -> void:
	var incoming: CardData = conflict["incoming"]
	var local: CardData = conflict["local"]
	if action == "replace":
		if staged.is_empty():
			incoming.instance_id = local.instance_id
			if incoming.card_id.is_empty():
				incoming.card_id = local.card_id
			pending_import_prepared["updates"][local.instance_id] = incoming
		else:
			staged["card"] = incoming
			staged["share_id"] = conflict["share_id"]
		return
	if action != "rename_local":
		incoming.card_name = new_name
	elif not staged.is_empty():
		local.card_name = new_name
	else:
		var renamed := local.duplicate_card()
		renamed.card_name = new_name
		pending_import_prepared["updates"][local.instance_id] = renamed
	pending_import_prepared["incoming"].append({"card": incoming, "share_id": conflict["share_id"]})


func _finish_import() -> void:
	var result := PlayerData.apply_prepared_import(pending_import_prepared, pending_import_package, false, true)
	_clear_pending_import()
	if not result.get("ok", false):
		_show_message(Locale.t("share.import_save_failed"))
		return
	_show_message(Locale.t("share.import_done") % [result["added"], result["updated"], result["skipped"]])
	if mode == "cards" and selected_deck_id != "":
		_show_deck_cards(selected_deck_id)
	else:
		_show_deck_manager()


func _clear_pending_import() -> void:
	pending_import_package = {}
	pending_import_prepared = {}
	pending_conflicts = []


func _import_target_cards() -> Array:
	var updates: Dictionary = pending_import_prepared.get("updates", {})
	var cards := PlayerData.get_cards_for_deck(str(pending_import_prepared.get("deck_id", "")))
	return cards.map(func(card: CardData): return updates.get(card.instance_id, card))


func _import_name_taken(card_name: String) -> bool:
	for card in _import_target_cards():
		if card.card_name == card_name:
			return true
	for item in pending_import_prepared.get("incoming", []):
		if item["card"].card_name == card_name:
			return true
	for conflict in pending_conflicts:
		if conflict["incoming"].card_name == card_name:
			return true
	return false


func _show_card_conflict_popup(conflict: Dictionary, replace_pending: bool, callback: Callable, copy_batch: Dictionary = {}) -> void:
	var local: CardData = conflict.get("local")
	var incoming: CardData = conflict.get("incoming")
	var copying := not copy_batch.is_empty()
	var name_taken := _import_name_taken
	if copying:
		name_taken = _copy_name_taken.bind(copy_batch, str(conflict.target_deck_id))
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -330
	panel_box.offset_top = -240
	panel_box.offset_right = 330
	panel_box.offset_bottom = 240
	if copying:
		for index in range(mini(2, copy_batch.conflicts.size()), 0, -1):
			var behind := panel_box.duplicate() as Panel
			var offset := Vector2(10, 8) * index
			behind.offset_left += offset.x
			behind.offset_right += offset.x
			behind.offset_top += offset.y
			behind.offset_bottom += offset.y
			UITheme.apply_popup_frame(behind, "gold", false, false)
			layer.add_child(behind)
	UITheme.apply_popup_frame(panel_box, "gold")
	layer.add_child(panel_box)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel_box.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("share.name_conflict")
	if copying:
		var deck_name := PlayerData.deck_display_name(PlayerData.get_deck(conflict.target_deck_id))
		title.text = Locale.t("deck.copy_conflict_title") % deck_name
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	if copying and not copy_batch.conflicts.is_empty():
		var remaining := Label.new()
		remaining.text = Locale.t("deck.copy_conflicts_left") % copy_batch.conflicts.size()
		remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_label(remaining, true)
		box.add_child(remaining)
	box.add_child(preload("res://CardCollectionDialog.gd").make_comparison(
		Locale.t("share.pending_card" if replace_pending else "share.local_card"), local,
		Locale.t("share.incoming_card"), incoming))
	var name_edit := LineEdit.new()
	name_edit.text = PlayerData.available_card_copy_name(incoming.card_name, name_taken)
	UITheme.apply_input(name_edit)
	box.add_child(name_edit)
	var name_error := Label.new()
	name_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(name_error)
	name_error.add_theme_color_override("font_color", UITheme.COLOR_WARNING)
	name_error.hide()
	box.add_child(name_error)
	name_edit.text_changed.connect(func(_value): name_error.hide())
	var rename := func(action: String) -> void:
		if layer.is_queued_for_deletion():
			return
		var new_name := name_edit.text.strip_edges()
		if new_name.is_empty() or name_taken.call(new_name):
			name_error.text = Locale.t("share.rename_empty" if new_name.is_empty() else ("editor.sync_name_conflict" if copying else "share.rename_taken"))
			name_error.show()
			name_edit.grab_focus()
			return
		layer.queue_free()
		callback.call(action, new_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	if not copying:
		_add_row_button(row, Locale.t("share.rename_pending" if replace_pending else "share.rename_local"), rename.bind("rename_local"), "outlined")
	_add_row_button(row, Locale.t("share.rename_incoming"), rename.bind("rename_incoming"), "outlined")
	var overwrite_key := "share.overwrite" if copying else ("share.replace_pending" if replace_pending else "share.replace_local")
	var replace := func():
		if layer.is_queued_for_deletion():
			return
		layer.queue_free()
		callback.call("replace", "")
	_add_row_button(row, Locale.t(overwrite_key), replace, "danger")
	var cancel := func():
		if layer.is_queued_for_deletion():
			return
		layer.queue_free()
		if not copying:
			_clear_pending_import()
			_show_message(Locale.t("share.import_cancelled"))
	layer.set_meta("popup_close", cancel)
	var cancel_row := HBoxContainer.new()
	cancel_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(cancel_row)
	var cancel_button := _add_row_button(cancel_row, Locale.t("common.cancel" if copying else "share.cancel_import"), cancel, "outlined")
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	name_edit.grab_focus()


func _show_text_input_popup(title_text: String, label_text: String, default_text: String, callback: Callable) -> void:
	var popup := UITheme.make_popup_layer(self, 110)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -190
	panel_box.offset_top = -105
	panel_box.offset_right = 190
	panel_box.offset_bottom = 105
	UITheme.apply_popup_frame(panel_box, "gold")
	layer.add_child(panel_box)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel_box.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	var input := LineEdit.new()
	input.placeholder_text = label_text
	input.text = default_text
	UITheme.apply_input(input)
	box.add_child(input)
	var row := HBoxContainer.new()
	box.add_child(row)
	_add_row_button(row, Locale.t("battle.confirm"), func():
		var value := input.text.strip_edges()
		if value != "":
			callback.call(value)
		layer.queue_free()
	)
	_add_row_button(row, Locale.t("common.back"), layer.queue_free)


func _compact_popup(text: String) -> Dictionary:
	var popup := UITheme.make_popup_layer(self,120)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.layer.add_child(center)
	var frame := PanelContainer.new()
	frame.name = "CollectionConfirmPanel"
	frame.custom_minimum_size.x = minf(480,get_viewport_rect().size.x-48)
	UITheme.apply_popup_frame(frame, "gold", false)
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,18)
	frame.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",20)
	margin.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",12)
	box.add_child(buttons)
	return {"layer":popup.layer,"buttons":buttons}


func _show_message(text: String) -> void:
	var popup := _compact_popup(text)
	var ok := Button.new()
	ok.text = Locale.t("common.confirm")
	ok.custom_minimum_size = Vector2(120,40)
	UITheme.apply_button(ok,"primary")
	ok.pressed.connect(popup.layer.queue_free)
	popup.buttons.add_child(ok)


func _show_confirm_dialog(text: String, on_confirm: Callable) -> void:
	var popup := _compact_popup(text)
	var cancel := Button.new()
	cancel.text = Locale.t("common.cancel")
	cancel.custom_minimum_size = Vector2(120,40)
	UITheme.apply_button(cancel, "secondary")
	cancel.pressed.connect(popup.layer.queue_free)
	popup.buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = Locale.t("common.confirm")
	confirm.custom_minimum_size = Vector2(120,40)
	UITheme.apply_button(confirm,"danger")
	confirm.pressed.connect(func():
		popup.layer.queue_free()
		on_confirm.call())
	popup.buttons.add_child(confirm)

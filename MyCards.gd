extends Control

# ============================================
# My Cards — deck manager + card/deck sharing
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

var card_ui_scene = preload("res://CardUI.tscn")

@onready var panel = $Panel
@onready var root_box = $Panel/VBoxContainer
@onready var top_bar = $Panel/VBoxContainer/TopBar
@onready var title_label = $Panel/VBoxContainer/TopBar/TitleLabel
@onready var scroll_container = $Panel/VBoxContainer/ScrollContainer
@onready var card_grid = $Panel/VBoxContainer/ScrollContainer/CardGrid

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
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_theme()
	_ensure_deck_state()
	if PlayerData.return_to_deck_id != "" and not PlayerData.get_deck(PlayerData.return_to_deck_id).is_empty():
		var deck_id := PlayerData.return_to_deck_id
		PlayerData.return_to_deck_id = ""
		_show_deck_cards(deck_id)
	else:
		_show_deck_manager()


func _apply_theme() -> void:
	UITheme.apply_app_background(panel)
	UITheme.apply_panel(panel, "dark")
	UITheme.apply_title(title_label, max(18, int(24 * _ui_scale())))
	UITheme.title_breathe(title_label)


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
	for child in top_bar.get_children():
		child.queue_free()


func _clear_grid() -> void:
	for child in card_grid.get_children():
		child.queue_free()


func _add_top_button(text: String, callback: Callable, variant: String = "secondary") -> Button:
	var btn := Button.new()
	btn.text = text
	UITheme.apply_button(btn, variant)
	btn.pressed.connect(callback)
	top_bar.add_child(btn)
	return btn


func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)


func _set_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	UITheme.apply_title(label, max(14, int(24 * _ui_scale())))
	top_bar.add_child(label)
	title_label = label
	UITheme.title_breathe(label)


func _show_deck_manager() -> void:
	mode = "decks"
	selected_deck_id = ""
	selected_instance_ids.clear()
	_clear_top_bar()
	_clear_grid()
	_set_title(Locale.t("deck.manager_title"))
	_add_spacer()
	_add_top_button(Locale.t("deck.new"), _on_create_deck_pressed, "primary")
	_add_top_button(Locale.t("share.import_deck"), _on_import_deck_pressed)
	_add_top_button(Locale.t("common.back"), _on_back_to_menu_pressed)
	card_grid.columns = 2
	for deck in PlayerData.deck_library:
		_add_deck_slot(deck)
	_apply_responsive_layout()
	UITheme.animate_list_enter(top_bar, 0.04, 8.0)
	UITheme.animate_list_enter(card_grid, 0.03, 0.0)


func _show_deck_cards(deck_id: String) -> void:
	mode = "cards"
	selected_deck_id = deck_id
	PlayerData.current_deck_id = deck_id
	selected_instance_ids.clear()
	_clear_top_bar()
	_clear_grid()
	var deck := PlayerData.get_deck(deck_id)
	_set_title(Locale.t("deck.cards_title") % deck.get("name", Locale.t("deck.default_name")))
	_add_spacer()
	_add_top_button(Locale.t("mycards.create_new"), _on_create_new_pressed, "primary")
	_add_top_button(Locale.t("share.export_selected"), _on_export_selected_pressed)
	_add_top_button(Locale.t("deck.copy_to"), _on_copy_selected_pressed)
	_add_top_button(Locale.t("share.export_deck"), _on_export_current_deck_pressed)
	_add_top_button(Locale.t("share.import_append"), _on_import_append_pressed)
	_add_top_button(Locale.t("common.back"), _show_deck_manager)
	card_grid.columns = 4
	for card in PlayerData.get_cards_for_deck(deck_id):
		_add_card_box(card)
	_apply_responsive_layout()
	UITheme.animate_list_enter(top_bar, 0.04, 8.0)
	UITheme.animate_list_enter(card_grid, 0.03, 0.0)


func _add_deck_slot(deck: Dictionary) -> void:
	var s := _ui_scale()
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(420, 150) * s
	UITheme.apply_panel(slot, "gold")
	card_grid.add_child(slot)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", max(10, int(16 * s)))
	margin.add_theme_constant_override("margin_right", max(10, int(16 * s)))
	margin.add_theme_constant_override("margin_top", max(8, int(14 * s)))
	margin.add_theme_constant_override("margin_bottom", max(8, int(14 * s)))
	slot.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", max(4, int(8 * s)))
	margin.add_child(box)
	var name_label := Label.new()
	name_label.text = deck.get("name", Locale.t("deck.default_name"))
	UITheme.apply_title(name_label, max(14, int(22 * s)))
	box.add_child(name_label)
	var count_label := Label.new()
	count_label.text = Locale.t("deck.card_count") % deck.get("cards", []).size()
	count_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_label(count_label, true)
	box.add_child(count_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", max(2, int(6 * s)))
	box.add_child(row)
	_add_row_button(row, Locale.t("deck.open"), func(): _show_deck_cards(deck.get("id", "")))
	_add_row_button(row, Locale.t("deck.rename"), func(): _show_rename_deck_popup(deck))
	_add_row_button(row, Locale.t("share.export_deck"), func(): _export_deck(deck))
	_add_row_button(row, Locale.t("mycards.delete"), func(): _delete_deck(deck.get("id", "")), "danger")


func _add_row_button(row: HBoxContainer, text: String, callback: Callable, variant: String = "secondary") -> Button:
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
	card_box.custom_minimum_size = Vector2(card_width, 280 * s)
	card_box.add_theme_constant_override("separation", max(2, int(4 * s)))
	card_grid.add_child(card_box)

	var check := CheckBox.new()
	check.text = Locale.t("share.select")
	UITheme.apply_button(check, "secondary")
	check.toggled.connect(func(pressed: bool):
		if pressed:
			selected_instance_ids[card_data.instance_id] = true
		else:
			selected_instance_ids.erase(card_data.instance_id)
	)
	card_box.add_child(check)

	var card_ui_instance = card_ui_scene.instantiate()
	card_box.add_child(card_ui_instance)
	card_ui_instance.set_card(card_data)
	card_ui_instance.set_actions_visible(false)
	card_ui_instance.apply_ui_scale(s)

	var skill_box := VBoxContainer.new()
	skill_box.custom_minimum_size = Vector2(card_width, 54 * s)
	skill_box.add_theme_constant_override("separation", row_gap)
	card_box.add_child(skill_box)
	for s_idx in range(card_data.skills.size()):
		var skill: Dictionary = card_data.skills[s_idx]
		var skill_btn := Button.new()
		var fallback := Locale.t("mycards.skill_fallback") % (s_idx + 1)
		var skill_name: String = skill.get("skill_name", "")
		skill_btn.text = skill_name if skill_name != "" else fallback
		skill_btn.tooltip_text = _TextFormatter.format_skill_tooltip(skill)
		skill_btn.disabled = true
		UITheme.apply_button(skill_btn, "secondary")
		skill_btn.clip_text = true
		skill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_btn.custom_minimum_size = Vector2(card_width, 26 * s)
		skill_box.add_child(skill_btn)

	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size = Vector2(card_width, 28 * s)
	btn_row.add_theme_constant_override("separation", row_gap)
	card_box.add_child(btn_row)
	_add_row_button(btn_row, Locale.t("mycards.edit"), func(): _on_edit_card(card_data.instance_id))
	_add_row_button(btn_row, Locale.t("mycards.delete"), func(): _on_delete_card(card_data.instance_id))


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var margin: int = max(12, int(24 * s))
	panel.offset_left = margin
	panel.offset_top = margin
	panel.offset_right = -margin
	panel.offset_bottom = -margin
	root_box.add_theme_constant_override("separation", max(6, int(10 * s)))
	top_bar.add_theme_constant_override("separation", max(4, int(8 * s)))
	for child in top_bar.get_children():
		if child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	if mode == "cards":
		scroll_container.custom_minimum_size = Vector2(0, 560 * s)


func _on_create_deck_pressed() -> void:
	_show_text_input_popup(Locale.t("deck.new"), Locale.t("deck.name"), Locale.t("deck.default_name"), func(new_name: String):
		var deck := PlayerData.create_deck(new_name)
		_show_deck_cards(deck.get("id", ""))
	)


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


func _on_create_new_pressed():
	var popup := UITheme.make_popup_layer(self, 110)
	var layer: CanvasLayer = popup["layer"]
	var bg: ColorRect = popup["bg"]
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			layer.queue_free()
	)
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -180
	panel_box.offset_top = -135
	panel_box.offset_right = 180
	panel_box.offset_bottom = 135
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
	title.text = Locale.t("editor.create_new_card")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 22)
	box.add_child(title)
	var minion_btn := Button.new()
	minion_btn.text = Locale.t("editor.create_minion")
	minion_btn.custom_minimum_size = Vector2(280, 42)
	UITheme.apply_button(minion_btn, "primary")
	minion_btn.pressed.connect(func():
		PlayerData.init_card_draft()
		PlayerData.current_deck_id = selected_deck_id
		PlayerData.editing_index = -1
		PlayerData.editing_deck_id = ""
		PlayerData.editing_instance_id = ""
		layer.queue_free()
		UIMotion.change_scene("res://CardEditor.tscn")
	)
	box.add_child(minion_btn)
	var spell_btn := Button.new()
	spell_btn.text = Locale.t("editor.create_spell")
	spell_btn.custom_minimum_size = Vector2(280, 42)
	UITheme.apply_button(spell_btn, "primary")
	spell_btn.pressed.connect(func():
		PlayerData.init_spell_draft()
		PlayerData.current_deck_id = selected_deck_id
		PlayerData.editing_index = -1
		PlayerData.editing_deck_id = ""
		PlayerData.editing_instance_id = ""
		layer.queue_free()
		UIMotion.change_scene("res://CardEditor.tscn")
	)
	box.add_child(spell_btn)
	var parasite_btn := Button.new()
	parasite_btn.text = Locale.t("editor.create_parasite")
	parasite_btn.custom_minimum_size = Vector2(280, 42)
	UITheme.apply_button(parasite_btn, "primary")
	parasite_btn.pressed.connect(func():
		PlayerData.init_parasite_draft()
		PlayerData.current_deck_id = selected_deck_id
		PlayerData.editing_index = -1
		PlayerData.editing_deck_id = ""
		PlayerData.editing_instance_id = ""
		layer.queue_free()
		UIMotion.change_scene("res://CardEditor.tscn")
	)
	box.add_child(parasite_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("skill_editor.cancel")
	cancel_btn.custom_minimum_size = Vector2(280, 36)
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(layer.queue_free)
	box.add_child(cancel_btn)


func _on_edit_card(instance_id: String):
	PlayerData.editing_deck_id = selected_deck_id
	PlayerData.editing_instance_id = instance_id
	PlayerData.editing_index = PlayerData.find_deck_card_index(selected_deck_id, instance_id)
	PlayerData.card_editor_return_scene = "res://MyCards.tscn"
	PlayerData.return_to_deck_id = selected_deck_id
	UIMotion.change_scene("res://CardEditor.tscn")


func _on_delete_card(instance_id: String):
	_show_confirm_dialog(Locale.t("mycards.confirm_delete_card"), func():
		if PlayerData.remove_deck_card(selected_deck_id, instance_id):
			_show_deck_cards(selected_deck_id)
	)


func _on_back_to_menu_pressed():
	UIMotion.go_back("res://MainMenu.tscn")


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
		check.text = deck.get("name", Locale.t("deck.default_name"))
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
		var result := PlayerData.copy_cards_between_decks(selected_deck_id, selected_instance_ids.keys(), target_ids.keys())
		_show_message(Locale.t("deck.copy_done") % [result.get("added", 0), result.get("skipped", 0)])
		layer.queue_free()
	)
	_add_row_button(row, Locale.t("skill_editor.cancel"), layer.queue_free)


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
	var result := PlayerData.import_package_as_new_deck(pending_import_package, path.get_file().get_basename())
	_show_message(Locale.t("share.import_deck_done") % [result.get("deck_name", ""), result.get("added", 0)])
	_show_deck_manager()


func _show_next_conflict() -> void:
	if pending_conflicts.is_empty():
		_finish_import()
		return
	var conflict: Dictionary = pending_conflicts.pop_front()
	_show_card_conflict_popup(conflict, func(action: String, new_name: String):
		var incoming: CardData = conflict.get("incoming")
		var local: CardData = conflict.get("local")
		if action == "replace":
			PlayerData.update_deck_card(selected_deck_id, local.instance_id, incoming)
		elif action == "rename_local":
			local.card_name = new_name
			pending_import_prepared["incoming"].append({"card": incoming, "share_id": conflict.get("share_id", "")})
		else:
			incoming.card_name = new_name
			pending_import_prepared["incoming"].append({"card": incoming, "share_id": conflict.get("share_id", "")})
		_show_next_conflict()
	)


func _finish_import() -> void:
	PlayerData.current_deck_id = selected_deck_id
	var result := PlayerData.apply_prepared_import(pending_import_prepared, pending_import_package, false, true)
	_show_message(Locale.t("share.import_done") % [result.get("added", 0), result.get("skipped", 0)])
	if mode == "cards" and selected_deck_id != "":
		_show_deck_cards(selected_deck_id)
	else:
		_show_deck_manager()


func _show_card_conflict_popup(conflict: Dictionary, callback: Callable) -> void:
	var local: CardData = conflict.get("local")
	var incoming: CardData = conflict.get("incoming")
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
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 16)
	box.add_child(cards_row)
	cards_row.add_child(_make_conflict_summary(Locale.t("share.local_card"), local))
	cards_row.add_child(_make_conflict_summary(Locale.t("share.incoming_card"), incoming))
	var name_edit := LineEdit.new()
	name_edit.text = incoming.card_name + " 2"
	UITheme.apply_input(name_edit)
	box.add_child(name_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_add_row_button(row, Locale.t("share.rename_local"), func():
		callback.call("rename_local", name_edit.text.strip_edges())
		layer.queue_free()
	)
	_add_row_button(row, Locale.t("share.rename_incoming"), func():
		callback.call("rename_incoming", name_edit.text.strip_edges())
		layer.queue_free()
	)
	_add_row_button(row, Locale.t("share.replace_local"), func():
		callback.call("replace", "")
		layer.queue_free()
	)


func _make_conflict_summary(label_text: String, card: CardData) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var preview_holder := CenterContainer.new()
	preview_holder.custom_minimum_size = Vector2(120, 150)
	box.add_child(preview_holder)
	var card_ui = card_ui_scene.instantiate()
	preview_holder.add_child(card_ui)
	card_ui.set_card(card)
	card_ui.apply_ui_scale(0.82)
	card_ui.set_actions_visible(false)
	card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


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


func _show_message(text: String) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -190
	panel_box.offset_top = -90
	panel_box.offset_right = 190
	panel_box.offset_bottom = 90
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
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var ok := Button.new()
	ok.text = Locale.t("skill_editor.ok")
	ok.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(ok, "primary")
	ok.pressed.connect(layer.queue_free)
	box.add_child(ok)


func _show_confirm_dialog(text: String, on_confirm: Callable) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel_box := Panel.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -210
	panel_box.offset_top = -100
	panel_box.offset_right = 210
	panel_box.offset_bottom = 100
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
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(btn_row)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.cancel")
	cancel_btn.custom_minimum_size = Vector2(120, 36)
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(layer.queue_free)
	btn_row.add_child(cancel_btn)
	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("common.confirm")
	confirm_btn.custom_minimum_size = Vector2(120, 36)
	UITheme.apply_button(confirm_btn, "primary")
	confirm_btn.pressed.connect(func():
		layer.queue_free()
		on_confirm.call()
	)
	btn_row.add_child(confirm_btn)

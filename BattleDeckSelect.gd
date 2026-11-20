extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const DeckTile = preload("res://BattleDeckTile.gd")
var card_ui_scene = preload("res://CardUI.tscn")

@onready var back_button: Button = $Panel/VBoxContainer/TopBar/BackButton
@onready var panel: Panel = $Panel
@onready var root_box: VBoxContainer = $Panel/VBoxContainer
@onready var top_bar: HBoxContainer = $Panel/VBoxContainer/TopBar
@onready var title_label: Label = $Panel/VBoxContainer/TopBar/TitleLabel
@onready var content: HBoxContainer = $Panel/VBoxContainer/Content
@onready var deck_column: VBoxContainer = $Panel/VBoxContainer/Content/DeckColumn
@onready var scroll_container: ScrollContainer = deck_column.get_node("ScrollContainer")
@onready var deck_grid: GridContainer = scroll_container.get_node("DeckGrid")
@onready var settings_panel: PanelContainer = $Panel/VBoxContainer/Content/SettingsPanel
@onready var settings_layout: VBoxContainer = $Panel/VBoxContainer/Content/SettingsPanel/Margin/Layout
@onready var settings_scroll: ScrollContainer = settings_layout.get_node("Scroll")
@onready var settings_box: VBoxContainer = settings_scroll.get_node("SettingsBox")
@onready var footer: HBoxContainer = deck_column.get_node("Footer")
@onready var selection_label: Label = deck_column.get_node("SelectionLabel")
@onready var confirm_button: Button = footer.get_node("ConfirmButton")
@onready var view_button: Button = footer.get_node("ViewButton")

var selected_deck_id := ""
var deck_tiles: Array[Button] = []
var basic_controls: Dictionary = {}
var advanced_button: Button
var advanced_layer: CanvasLayer
var details_layer: CanvasLayer
var details_grid: GridContainer
var details_scroll: ScrollContainer
var _deck_review: VBoxContainer
var _deck_cover: TextureRect
var _deck_name: Label

func _ready() -> void:
	get_viewport().size_changed.connect(_apply_responsive_layout)
	UITheme.apply_app_background(self)
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	UITheme.apply_panel(settings_panel, "dark")
	UITheme.apply_title(title_label, 26)
	UITheme.apply_label(selection_label, true)
	UITheme.place_page_back(self, back_button)
	UITheme.apply_button(confirm_button, "primary", false)
	UITheme.apply_button(view_button, "utility")
	scroll_container.follow_focus = true
	back_button.text = Locale.t("common.back")
	view_button.text = Locale.t("prep.view_cards")
	view_button.pressed.connect(func(): _show_deck_details(selected_deck_id))
	_build_deck_review()
	_build_settings()
	_setup_deck_select()
	_apply_texts()
	_apply_responsive_layout()

func _ui_scale() -> float:
	var dimensions := get_viewport_rect().size
	return minf(dimensions.x / BASE_VIEWPORT_SIZE.x, dimensions.y / BASE_VIEWPORT_SIZE.y) if dimensions.x > 0 and dimensions.y > 0 else 1.0

func _rules_locked() -> bool:
	return PlayerData.battle_select_mode == "hotseat_p2"

func _apply_texts() -> void:
	match PlayerData.battle_select_mode:
		"hotseat_p2":
			title_label.text = Locale.t("select.player2_title")
			confirm_button.text = Locale.t("battle_config.start_battle")
		"online":
			title_label.text = Locale.t("select.online_title")
			confirm_button.text = Locale.t("common.confirm")
		"practice":
			title_label.text = Locale.t("select.practice_title")
			confirm_button.text = Locale.t("prep.start_practice")
		_:
			title_label.text = Locale.t("select.player1_title")
			confirm_button.text = Locale.t("prep.next_player")

func _setup_deck_select() -> void:
	for deck in PlayerData.deck_library:
		var tile := DeckTile.new()
		deck_grid.add_child(tile)
		tile.configure(deck, _ui_scale())
		tile.deck_selected.connect(_select_deck)
		tile.deck_inspected.connect(_show_deck_details)
		deck_tiles.append(tile)
	if deck_tiles.is_empty():
		scroll_container.hide()
		_update_selection()
		back_button.grab_focus()
		return
	var preferred := PlayerData.current_deck_id
	_select_deck(preferred if not PlayerData.get_deck(preferred).is_empty() else deck_tiles[0].deck_id)
	for tile in deck_tiles:
		if tile.chosen:
			tile.grab_focus()
			break

func _select_deck(deck_id: String) -> void:
	if PlayerData.get_deck(deck_id).is_empty():
		return
	selected_deck_id = deck_id
	_update_selection()

func _update_selection() -> void:
	for tile in deck_tiles:
		tile.set_selected(tile.deck_id == selected_deck_id)
	var deck := PlayerData.get_deck(selected_deck_id)
	var count := PlayerData.get_cards_for_deck(selected_deck_id).size()
	selection_label.text = Locale.t("select.need_deck") if count == 0 else ""
	confirm_button.disabled = count == 0
	view_button.disabled = deck.is_empty()
	_deck_name.text = PlayerData.deck_display_name(deck) if not deck.is_empty() else Locale.t("prep.selected_deck")
	_deck_cover.texture = CardArtwork.deck_cover(deck.get("cards", []))
	selection_label.visible = count == 0
	_apply_responsive_layout()

func _build_deck_review() -> void:
	_deck_review = VBoxContainer.new()
	_deck_review.add_theme_constant_override("separation", UITheme.Tokens.SPACING[1])
	settings_layout.add_child(_deck_review)
	settings_layout.move_child(_deck_review, 0)
	_deck_cover = TextureRect.new()
	_deck_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_deck_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_deck_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_review.add_child(_deck_cover)
	_deck_name = Label.new()
	_deck_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_title(_deck_name, 20)
	_deck_review.add_child(_deck_name)
	footer.reparent(_deck_review, false)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_review.add_child(UITheme.separator())

func _build_settings() -> void:
	var heading := Label.new()
	heading.text = Locale.t("prep.battlefield")
	UITheme.apply_title(heading, 20)
	settings_box.add_child(heading)
	if PlayerData.battle_select_mode == "practice":
		var difficulty := Label.new()
		difficulty.text = Locale.t("prep.difficulty", [Locale.t("prep.difficulty_" + PlayerData.practice_ai_difficulty)])
		UITheme.apply_label(difficulty, true)
		settings_box.add_child(difficulty)
	for spec in [["starting_hp", 1, 99], ["mana_per_turn", 0, 10], ["draw_per_turn", 1, SkillEngine.MAX_HAND_SIZE]]:
		var key: String = spec[0]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		settings_box.add_child(box)
		var label := Label.new()
		label.set_meta("keyword_literal",true)
		label.text = Locale.t("battle_config.mana_initial" if key == "mana_per_turn" and PlayerData.battle_config.has("mana_increment") else "prep." + key)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_label(label)
		box.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = spec[1]
		spin.max_value = spec[2]
		spin.value = PlayerData.battle_config.get(key, PlayerData.DEFAULT_BATTLE_CONFIG[key])
		spin.editable = not _rules_locked()
		spin.custom_minimum_size = Vector2(76, 32)
		UITheme.apply_input(spin)
		box.add_child(spin)
		spin.value_changed.connect(func(value: float, setting: String = key):
			if not _rules_locked(): PlayerData.battle_config[setting] = int(value)
		)
		basic_controls[key] = spin
	advanced_button = Button.new()
	advanced_button.name = "AdvancedSettingsButton"
	advanced_button.text = Locale.t("prep.rules_link")
	UITheme.apply_selection_entry(advanced_button)
	advanced_button.pressed.connect(_show_battle_config_popup)
	settings_layout.add_child(advanced_button)
	var notice := Label.new()
	notice.text = Locale.t("prep.rules_locked") if _rules_locked() else (Locale.t("prep.online_rules") if PlayerData.battle_select_mode == "online" else Locale.t("prep.rules_hint"))
	notice.visible = _rules_locked()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(notice, true)
	settings_box.add_child(notice)

func _sync_basic_controls() -> void:
	for key in basic_controls:
		basic_controls[key].set_value_no_signal(PlayerData.battle_config.get(key, PlayerData.DEFAULT_BATTLE_CONFIG[key]))
	var mana_label: Label = basic_controls["mana_per_turn"].get_parent().get_child(0)
	mana_label.text = Locale.t("battle_config.mana_initial" if PlayerData.battle_config.has("mana_increment") else "prep.mana_per_turn")

func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var height := get_viewport_rect().size.y
	var compact := height < BASE_VIEWPORT_SIZE.y
	var edge := maxi(20, int(54 * s))
	var bottom := 20 if compact else edge
	panel.offset_left = edge
	panel.offset_top = maxf(80, edge)
	panel.offset_right = -edge
	panel.offset_bottom = -bottom
	var inset := maxi(12, int(20 * s))
	root_box.offset_left = inset
	root_box.offset_top = inset
	root_box.offset_right = -inset
	root_box.offset_bottom = -inset
	root_box.add_theme_constant_override("separation", maxi(8, int(14 * s)))
	content.add_theme_constant_override("separation", maxi(24, int(36 * s)))
	footer.add_theme_constant_override("separation", maxi(8, int(12 * s)))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", maxi(20, int(26 * s)))
	settings_panel.custom_minimum_size.x = maxf(292, 322 * s)
	_deck_cover.custom_minimum_size.y = roundf(78 * s)
	_deck_cover.visible = not compact and _deck_cover.texture != null
	var settings_margin := $Panel/VBoxContainer/Content/SettingsPanel/Margin
	for side in ["left", "right", "top", "bottom"]:
		settings_margin.add_theme_constant_override("margin_" + side, 8)
	settings_layout.add_theme_constant_override("separation", maxi(10, int(12 * s)))
	settings_box.add_theme_constant_override("separation", 5 if compact else maxi(8, int(12 * s)))
	deck_grid.add_theme_constant_override("v_separation", 4)
	for tile in deck_tiles: tile.apply_ui_scale(s)
	for button in [confirm_button, view_button, advanced_button]:
		button.custom_minimum_size = Vector2(0, maxf(34, roundf(42 * s)))
		button.add_theme_font_size_override("font_size", maxi(13, int(16 * s)))
	var available_height := height - panel.offset_top - bottom - inset * 2 - title_label.get_combined_minimum_size().y - root_box.get_theme_constant("separation")
	var selection_height := selection_label.get_combined_minimum_size().y + deck_column.get_theme_constant("separation") if selection_label.visible else 0.0
	scroll_container.custom_minimum_size.y = ceilf(minf(deck_grid.get_combined_minimum_size().y, maxf(48, available_height - selection_height)))
	var frame_insets := settings_panel.get_theme_stylebox("panel").get_minimum_size().y + 16
	var fixed_height := _deck_review.get_combined_minimum_size().y + advanced_button.custom_minimum_size.y + 2 * settings_layout.get_theme_constant("separation") + frame_insets
	settings_scroll.custom_minimum_size.y = ceilf(minf(settings_box.get_combined_minimum_size().y, maxf(56, available_height - fixed_height)))
	for popup_layer in [details_layer, advanced_layer]:
		if is_instance_valid(popup_layer):
			var frame: Panel = popup_layer.get_node("PopupPanel")
			var half := get_viewport_rect().size * Vector2(0.44, 0.43)
			if popup_layer == advanced_layer: half.x = minf(370, half.x)
			frame.offset_left = -half.x
			frame.offset_right = half.x
			frame.offset_top = -half.y
			frame.offset_bottom = half.y
	if is_instance_valid(details_grid):
		var preview_scale := maxf(1.5, s * 1.45)
		details_grid.columns = maxi(1, int((get_viewport_rect().size.x * 0.88 - 52) / (120 * preview_scale + 40)))
		for holder in details_grid.get_children():
			holder.get_child(0).get_child(0).apply_ui_scale(preview_scale)

func _selected_cards() -> Array:
	var result: Array = []
	for card in PlayerData.get_cards_for_deck(selected_deck_id): result.append(card.duplicate_card())
	return result

func _on_confirm_pressed() -> void:
	var cards := _selected_cards()
	if cards.is_empty():
		_show_message(Locale.t("select.need_deck"))
		return
	_start_battle_with_cards(cards)

func _show_deck_details(deck_id: String) -> void:
	if is_instance_valid(details_layer) or PlayerData.get_deck(deck_id).is_empty(): return
	var popup := UITheme.make_popup_layer(self, 116)
	details_layer = popup["layer"]
	details_layer.name = "DeckDetails"
	details_layer.set_meta("popup_close", _close_details)
	var frame := Panel.new()
	frame.name = "PopupPanel"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	UITheme.apply_popup_frame(frame, "dark", false)
	details_layer.add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	frame.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.set_meta("keyword_literal", true)
	title.text = PlayerData.deck_display_name(PlayerData.get_deck(deck_id))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(title, 22)
	header.add_child(title)
	var close := Button.new()
	close.name = "BackToPreparation"
	close.text = Locale.t("common.back")
	UITheme.apply_selection_entry(close)
	close.pressed.connect(_close_details)
	header.add_child(close)
	details_scroll = ScrollContainer.new()
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(details_scroll)
	details_grid = GridContainer.new()
	details_grid.add_theme_constant_override("h_separation", 16)
	details_grid.add_theme_constant_override("v_separation", 16)
	details_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details_grid)
	for card in PlayerData.get_cards_for_deck(deck_id):
		var holder := PanelContainer.new()
		UITheme.apply_panel(holder, "soft")
		details_grid.add_child(holder)
		var center := CenterContainer.new()
		holder.add_child(center)
		var preview = card_ui_scene.instantiate()
		center.add_child(preview)
		preview.set_card(card)
		preview.set_battle_layout_preview(true)
		preview.apply_ui_scale(maxf(1.5, _ui_scale() * 1.45))
	_apply_responsive_layout()
	UIMotion.register_popup(details_layer, close)

func _close_details() -> void:
	if is_instance_valid(details_layer): details_layer.queue_free()
	details_layer = null
	details_grid = null
	details_scroll = null

func _close_advanced() -> void:
	if is_instance_valid(advanced_layer): advanced_layer.queue_free()
	advanced_layer = null

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(details_layer): _close_details()
		elif is_instance_valid(advanced_layer): _close_advanced()
		else: return
		get_viewport().set_input_as_handled()

func _start_battle_with_cards(cards: Array) -> void:
	match PlayerData.battle_select_mode:
		"practice":
			var opponent_cards: Array = []
			for card in CardDatabase.starter_library():
				opponent_cards.append(card.duplicate_card())
			PlayerData.configure_practice_battle(cards, opponent_cards, PlayerData.practice_ai_difficulty)
			UIMotion.change_scene("res://Main.tscn")
		"hotseat_p1":
			PlayerData.begin_hotseat_battle_selection(cards)
			UIMotion.replace_scene(scene_file_path)
		"hotseat_p2":
			PlayerData.configure_hotseat_battle(PlayerData.pending_hotseat_p1_deck, cards)
			PlayerData.hotseat_opening_player = NetworkManager.roll_opening_player()
			UIMotion.change_scene("res://Main.tscn")
		"online":
			PlayerData.configure_online_battle(cards, PlayerData.battle_select_next_scene, selected_deck_id)
			UIMotion.change_scene(PlayerData.battle_select_next_scene)


func _on_back_pressed() -> void:
	if PlayerData.battle_select_mode == "online":
		UIMotion.go_back("res://MultiplayerMenu.tscn")
	else:
		UIMotion.go_back("res://MainMenu.tscn")


func _show_battle_config_popup(_cards: Array = []) -> void:
	if is_instance_valid(advanced_layer): return
	advanced_layer = preload("res://presentation/BattleRulesEditor.gd").open(self,PlayerData.battle_config.duplicate(true),_rules_locked,func(config):
		PlayerData.battle_config = config
		_sync_basic_controls(),_close_advanced)


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

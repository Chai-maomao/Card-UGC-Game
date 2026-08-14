extends Control

# ============================================
# 主菜单
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const BLUR_SHADER := preload("res://blur.gdshader")
const UITheme = preload("res://UITheme.gd")

@onready var start_battle_btn = $CenterContainer/VBoxContainer/StartBattleButton
@onready var resume_battle_btn = $CenterContainer/VBoxContainer/ResumeBattleButton
@onready var card_editor_btn = $CenterContainer/VBoxContainer/CardEditorButton
@onready var my_cards_btn = $CenterContainer/VBoxContainer/MyCardsButton
@onready var online_btn = $CenterContainer/VBoxContainer/OnlineButton
@onready var settings_btn = $CenterContainer/VBoxContainer/SettingsButton
@onready var version_label = $VersionLabel

var menu_panel: PanelContainer
var title_label: Label
var subtitle_label: Label

func _apply_texts() -> void:
	resume_battle_btn.text = Locale.t("menu.resume")
	start_battle_btn.text = Locale.t("menu.start")
	card_editor_btn.text = Locale.t("menu.card_editor")
	my_cards_btn.text = Locale.t("menu.my_cards")
	online_btn.text = Locale.t("menu.online")
	settings_btn.text = Locale.t("menu.settings")
	version_label.text = Locale.t("settings.version", [AppVersion.VERSION])


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var btn_size := Vector2(220, 52) * s
	for btn in [resume_battle_btn, start_battle_btn, card_editor_btn, my_cards_btn, online_btn]:
		if btn:
			btn.custom_minimum_size = btn_size
			btn.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	if settings_btn:
		settings_btn.custom_minimum_size = btn_size
		settings_btn.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	var vbox := start_battle_btn.get_parent() as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", int(18 * s))
	if menu_panel:
		menu_panel.custom_minimum_size = Vector2(360, 500) * s
	if title_label:
		UITheme.apply_title(title_label, max(28, int(42 * s)))
	if subtitle_label:
		subtitle_label.add_theme_font_size_override("font_size", max(12, int(15 * s)))
	if version_label:
		version_label.add_theme_font_size_override("font_size", max(10, int(13 * s)))


func _apply_theme() -> void:
	var bg := Panel.new()
	bg.name = "ThemeBackground"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(bg)
	add_child(bg)
	move_child(bg, 0)

	var center := $CenterContainer
	var buttons_box := $CenterContainer/VBoxContainer
	menu_panel = PanelContainer.new()
	menu_panel.name = "MenuPanel"
	UITheme.apply_panel(menu_panel, "gold")
	center.remove_child(buttons_box)
	center.add_child(menu_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	menu_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	title_label = Label.new()
	title_label.text = "CARDEX"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.text = "UGC Card Battle"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(subtitle_label, true)
	box.add_child(subtitle_label)
	box.add_child(buttons_box)
	for btn in [start_battle_btn, card_editor_btn, my_cards_btn, online_btn, settings_btn]:
		UITheme.apply_button(btn, "primary" if btn == start_battle_btn else "secondary")
	UITheme.apply_label(version_label, true)
	# Entrance motion: panel spring-in, breathing title, staggered buttons.
	UITheme.animate_popup_enter(menu_panel)
	UITheme.title_breathe(title_label)
	UITheme.animate_list_enter(buttons_box, 0.05, 12.0)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	resume_battle_btn.visible = NetworkManager.has_resumable_match_session()
	resume_battle_btn.pressed.connect(_on_resume_battle_pressed)
	_apply_theme()
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	card_editor_btn.pressed.connect(_on_card_editor_pressed)
	my_cards_btn.pressed.connect(_on_my_cards_pressed)
	online_btn.pressed.connect(_on_online_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	Locale.language_changed.connect(_apply_texts)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_transport_ready)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# "继续编辑"后自动显示卡牌类型选择弹窗
	if PlayerData.continue_editing_flag:
		PlayerData.continue_editing_flag = false
		_show_card_type_popup.call_deferred()


func _on_start_battle_pressed():
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	_show_battle_mode_popup()


func _show_battle_mode_popup() -> void:
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(1, 1, 1, 1)
	var blur_material := ShaderMaterial.new()
	blur_material.shader = BLUR_SHADER
	blur_material.set_shader_parameter("strength", 5.0)
	bg.material = blur_material
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var dim := ColorRect.new()
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.32)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_layer.add_child(dim)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -180
	panel.offset_top = -130
	panel.offset_right = 180
	panel.offset_bottom = 130
	UITheme.apply_panel(panel, "gold")
	popup_layer.add_child(panel)
	UITheme.animate_popup_enter(panel)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("menu.battle_mode")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 22)
	vbox.add_child(title)

	var hotseat_btn := Button.new()
	hotseat_btn.text = Locale.t("menu.hotseat")
	hotseat_btn.custom_minimum_size = Vector2(240, 44)
	UITheme.apply_button(hotseat_btn, "primary")
	hotseat_btn.pressed.connect(func():
		popup_layer.queue_free()
		_start_hotseat_battle()
	)
	vbox.add_child(hotseat_btn)

	var practice_btn := Button.new()
	practice_btn.text = Locale.t("menu.practice")
	practice_btn.custom_minimum_size = Vector2(240, 44)
	UITheme.apply_button(practice_btn, "primary")
	practice_btn.pressed.connect(func():
		popup_layer.queue_free()
		_show_practice_difficulty_popup()
	)
	vbox.add_child(practice_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.back")
	cancel_btn.custom_minimum_size = Vector2(240, 36)
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(popup_layer.queue_free)
	vbox.add_child(cancel_btn)


func _show_practice_difficulty_popup() -> void:
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0, 0, 0, 0.36)
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -210
	panel.offset_top = -170
	panel.offset_right = 210
	panel.offset_bottom = 170
	UITheme.apply_panel(panel, "gold")
	popup_layer.add_child(panel)
	UITheme.animate_popup_enter(panel)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("menu.practice_difficulty")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 22)
	vbox.add_child(title)

	for difficulty in ["easy", "normal", "hard"]:
		var btn := Button.new()
		btn.text = Locale.t("menu.ai_%s" % difficulty)
		btn.custom_minimum_size = Vector2(270, 42)
		UITheme.apply_button(btn, "primary" if difficulty == "normal" else "secondary")
		btn.pressed.connect(func(id: String = difficulty):
			popup_layer.queue_free()
			_start_practice_battle(id)
		)
		vbox.add_child(btn)
		var hint := Label.new()
		hint.text = Locale.t("menu.ai_%s_hint" % difficulty)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 12)
		UITheme.apply_label(hint, true)
		vbox.add_child(hint)

	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.back")
	cancel_btn.custom_minimum_size = Vector2(270, 36)
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(func():
		popup_layer.queue_free()
		_show_battle_mode_popup()
	)
	vbox.add_child(cancel_btn)


func _start_hotseat_battle() -> void:
	PlayerData.battle_select_mode = "hotseat_p1"
	PlayerData.battle_select_next_scene = "res://Main.tscn"
	PlayerData.pending_hotseat_p1_deck.clear()
	UIMotion.change_scene("res://BattleDeckSelect.tscn")


func _start_practice_battle(difficulty: String = "normal") -> void:
	PlayerData.practice_ai_difficulty = difficulty
	PlayerData.battle_select_mode = "practice"
	PlayerData.battle_select_next_scene = "res://Main.tscn"
	UIMotion.change_scene("res://BattleDeckSelect.tscn")


func _on_card_editor_pressed():
	# Show type-selection popup (same as MyCards)
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	PlayerData.return_to_deck_id = ""
	_show_card_type_popup()


func _show_card_type_popup():
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


func _on_my_cards_pressed():
	UIMotion.change_scene("res://MyCards.tscn")


func _on_online_pressed():
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	UIMotion.change_scene("res://MultiplayerMenu.tscn")


func _on_settings_pressed() -> void:
	UIMotion.change_scene("res://SettingsMenu.tscn")


func _on_resume_battle_pressed() -> void:
	resume_battle_btn.disabled = true
	resume_battle_btn.text = Locale.t("menu.reconnecting")
	if not NetworkManager.begin_saved_match_reconnect():
		_on_reconnect_failed("no_saved_session")


func _on_reconnect_transport_ready() -> void:
	UIMotion.change_scene("res://Main.tscn")


func _on_reconnect_failed(_reason: String) -> void:
	resume_battle_btn.disabled = false
	resume_battle_btn.visible = NetworkManager.has_resumable_match_session()
	resume_battle_btn.text = Locale.t("menu.reconnect_failed")

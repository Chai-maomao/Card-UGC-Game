extends Control

# ============================================
# 主菜单
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)

@onready var start_battle_btn = $CenterContainer/VBoxContainer/StartBattleButton
@onready var resume_battle_btn = $CenterContainer/VBoxContainer/ResumeBattleButton
@onready var card_editor_btn = $CenterContainer/VBoxContainer/CardEditorButton
@onready var my_cards_btn = $CenterContainer/VBoxContainer/MyCardsButton
@onready var online_btn = $CenterContainer/VBoxContainer/OnlineButton
@onready var language_option = $CenterContainer/VBoxContainer/LanguageOption

const LANGUAGE_CODES := ["zh", "en"]
const LANGUAGE_LABELS := ["简体中文", "English"]


func _language_prompt() -> String:
	return Locale.t("menu.language_prompt")


func _setup_language_option() -> void:
	language_option.clear()
	for label in LANGUAGE_LABELS:
		language_option.add_item(label)
	language_option.selected = max(0, LANGUAGE_CODES.find(Locale.language))
	language_option.text = _language_prompt()


func _apply_texts() -> void:
	resume_battle_btn.text = Locale.t("menu.resume")
	start_battle_btn.text = Locale.t("menu.start")
	card_editor_btn.text = Locale.t("menu.card_editor")
	my_cards_btn.text = Locale.t("menu.my_cards")
	online_btn.text = Locale.t("menu.online")
	if language_option:
		language_option.text = _language_prompt()


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var btn_size := Vector2(200, 50) * s
	for btn in [resume_battle_btn, start_battle_btn, card_editor_btn, my_cards_btn, online_btn]:
		if btn:
			btn.custom_minimum_size = btn_size
			btn.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	if language_option:
		language_option.custom_minimum_size = Vector2(200, 40) * s
		language_option.add_theme_font_size_override("font_size", max(11, int(15 * s)))
	var vbox := $CenterContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", int(20 * s))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	resume_battle_btn.visible = NetworkManager.has_resumable_match_session()
	resume_battle_btn.pressed.connect(_on_resume_battle_pressed)
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	card_editor_btn.pressed.connect(_on_card_editor_pressed)
	my_cards_btn.pressed.connect(_on_my_cards_pressed)
	online_btn.pressed.connect(_on_online_pressed)
	_setup_language_option()
	language_option.item_selected.connect(_on_language_selected)
	Locale.language_changed.connect(_apply_texts)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_transport_ready)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LANGUAGE_CODES.size():
		Locale.set_language(LANGUAGE_CODES[index])
	else:
		language_option.text = _language_prompt()


func _on_start_battle_pressed():
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	PlayerData.battle_deck.clear()
	PlayerData.opponent_battle_deck.clear()
	for card in PlayerData.card_library:
		PlayerData.battle_deck.append(card.duplicate_card())
		PlayerData.opponent_battle_deck.append(card.duplicate_card())
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_card_editor_pressed():
	get_tree().change_scene_to_file("res://CardEditor.tscn")


func _on_my_cards_pressed():
	get_tree().change_scene_to_file("res://MyCards.tscn")


func _on_online_pressed():
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	get_tree().change_scene_to_file("res://MultiplayerMenu.tscn")


func _on_resume_battle_pressed() -> void:
	resume_battle_btn.disabled = true
	resume_battle_btn.text = Locale.t("menu.reconnecting")
	if not NetworkManager.begin_saved_match_reconnect():
		_on_reconnect_failed("no_saved_session")


func _on_reconnect_transport_ready() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_reconnect_failed(_reason: String) -> void:
	resume_battle_btn.disabled = false
	resume_battle_btn.visible = NetworkManager.has_resumable_match_session()
	resume_battle_btn.text = Locale.t("menu.reconnect_failed")

extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")

@onready var server_btn = $CenterContainer/VBoxContainer/ServerButton
@onready var server_hint_label = $CenterContainer/VBoxContainer/ServerHintLabel
@onready var direct_btn = $CenterContainer/VBoxContainer/DirectButton
@onready var direct_hint_label = $CenterContainer/VBoxContainer/DirectHintLabel
@onready var back_btn = $CenterContainer/VBoxContainer/BackButton
@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel
@onready var beta_btn = $CenterContainer/VBoxContainer/BetaButton
@onready var beta_hint_label = $CenterContainer/VBoxContainer/BetaHintLabel
@onready var dedicated_btn = $CenterContainer/VBoxContainer/DedicatedButton
@onready var dedicated_hint_label = $CenterContainer/VBoxContainer/DedicatedHintLabel


func _apply_texts() -> void:
	title_label.text = Locale.t("mp.title")
	dedicated_btn.text = Locale.t("mp.dedicated")
	dedicated_hint_label.text = Locale.t("mp.dedicated_hint")
	server_btn.text = Locale.t("mp.connect_server")
	server_hint_label.text = Locale.t("mp.server_hint")
	direct_btn.text = Locale.t("mp.direct")
	direct_hint_label.text = Locale.t("mp.direct_hint")
	back_btn.text = Locale.t("common.back")
	beta_btn.text = Locale.t("beta.entry")
	beta_hint_label.text = Locale.t("beta.hint")
	for label in [dedicated_hint_label,server_hint_label,direct_hint_label,beta_hint_label]: label.hide()


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_theme() -> void:
	var bg := Panel.new()
	bg.name = "ThemeBackground"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(bg)
	add_child(bg)
	move_child(bg, 0)

	$CenterContainer.anchor_right = 0.55
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.apply_title(title_label, 22)
	for button in [dedicated_btn, server_btn, direct_btn, beta_btn, back_btn]:
		UITheme.apply_selection_entry(button)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var btn_size := Vector2(270, 36) * s
	for btn in [dedicated_btn, server_btn, direct_btn, beta_btn, back_btn]:
		if btn:
			btn.custom_minimum_size = btn_size
			btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
	for label in [dedicated_hint_label, server_hint_label, direct_hint_label, beta_hint_label]:
		if label:
			label.custom_minimum_size = Vector2(500 * s, 0)
			label.add_theme_font_size_override("font_size", max(10, int(13 * s)))
			UITheme.apply_label(label, true)
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	var vbox := server_btn.get_parent() as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", int(10 * s))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	_apply_theme()
	dedicated_btn.pressed.connect(func():
		PlayerData.prepare_online_selection("res://DedicatedLobby.tscn")
		UIMotion.change_scene("res://BattleDeckSelect.tscn")
	)
	# Web relay entries are temporarily withdrawn; keep their implementation
	# and scene nodes for a future reopening, without active navigation hooks.
	direct_btn.pressed.connect(func():
		PlayerData.prepare_online_selection("res://DirectLobby.tscn")
		UIMotion.change_scene("res://BattleDeckSelect.tscn")
	)
	back_btn.pressed.connect(func(): UIMotion.go_back("res://MainMenu.tscn"))
	_apply_texts()
	_apply_responsive_layout()
	dedicated_btn.grab_focus()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _on_server_pressed() -> void:
	PlayerData.prepare_online_selection("res://Lobby.tscn")
	UIMotion.change_scene("res://BattleDeckSelect.tscn")

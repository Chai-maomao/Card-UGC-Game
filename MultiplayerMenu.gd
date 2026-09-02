extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")

@onready var server_btn = $CenterContainer/VBoxContainer/ServerButton
@onready var server_hint_label = $CenterContainer/VBoxContainer/ServerHintLabel
@onready var direct_btn = $CenterContainer/VBoxContainer/DirectButton
@onready var direct_hint_label = $CenterContainer/VBoxContainer/DirectHintLabel
@onready var back_btn = $CenterContainer/VBoxContainer/BackButton
@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel


func _apply_texts() -> void:
	title_label.text = Locale.t("mp.title")
	server_btn.text = Locale.t("mp.connect_server")
	server_hint_label.text = Locale.t("mp.server_hint")
	direct_btn.text = Locale.t("mp.direct")
	direct_hint_label.text = Locale.t("mp.direct_hint")
	back_btn.text = Locale.t("common.back")


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

	var center := $CenterContainer
	var buttons_box := server_btn.get_parent()
	var panel := PanelContainer.new()
	panel.name = "MultiplayerPanel"
	panel.custom_minimum_size = Vector2(430, 430) * _ui_scale()
	UITheme.apply_panel(panel, "gold")
	center.remove_child(buttons_box)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	margin.add_child(buttons_box)
	UITheme.apply_title(title_label, 28)
	UITheme.apply_button(server_btn, "primary")
	UITheme.apply_button(direct_btn, "primary")
	UITheme.apply_button(back_btn, "secondary")
	UITheme.apply_label(server_hint_label, true)
	UITheme.apply_label(direct_hint_label, true)
	# Entrance motion: panel spring-in, breathing title, staggered buttons.
	UITheme.animate_popup_enter(panel)
	UITheme.title_breathe(title_label)
	UITheme.animate_list_enter(buttons_box, 0.06, 12.0)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var btn_size := Vector2(240, 50) * s
	for btn in [server_btn, direct_btn, back_btn]:
		if btn:
			btn.custom_minimum_size = btn_size
			btn.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	for label in [server_hint_label, direct_hint_label]:
		if label:
			label.custom_minimum_size = Vector2(360 * s, 0)
			label.add_theme_font_size_override("font_size", max(10, int(13 * s)))
			UITheme.apply_label(label, true)
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	var vbox := server_btn.get_parent() as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", int(16 * s))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	_apply_theme()
	server_btn.pressed.connect(func():
		PlayerData.prepare_online_selection("res://Lobby.tscn")
		UIMotion.change_scene("res://BattleDeckSelect.tscn")
	)
	direct_btn.pressed.connect(func():
		PlayerData.prepare_online_selection("res://DirectLobby.tscn")
		UIMotion.change_scene("res://BattleDeckSelect.tscn")
	)
	back_btn.pressed.connect(func(): UIMotion.go_back("res://MainMenu.tscn"))
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")

@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel
@onready var language_label = $CenterContainer/VBoxContainer/LanguageLabel
@onready var language_option = $CenterContainer/VBoxContainer/LanguageOption
@onready var resolution_label = $CenterContainer/VBoxContainer/ResolutionLabel
@onready var resolution_option = $CenterContainer/VBoxContainer/ResolutionOption
@onready var back_button = $CenterContainer/VBoxContainer/BackButton
@onready var version_label = $VersionLabel

const LANGUAGE_CODES := ["zh", "en"]
const LANGUAGE_LABELS := ["简体中文", "English"]


func _ready() -> void:
	_apply_theme()
	_setup_options()
	_apply_texts()
	_apply_responsive_layout()
	language_option.item_selected.connect(_on_language_selected)
	resolution_option.item_selected.connect(_on_resolution_selected)
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://MainMenu.tscn"))
	Locale.language_changed.connect(_apply_texts)
	get_viewport().size_changed.connect(_apply_responsive_layout)


func _setup_options() -> void:
	language_option.clear()
	for label in LANGUAGE_LABELS:
		language_option.add_item(label)
	language_option.selected = max(0, LANGUAGE_CODES.find(Locale.language))
	resolution_option.clear()
	for index in WindowSizeController.WINDOW_PRESETS.size():
		resolution_option.add_item(WindowSizeController.preset_label(index))
	resolution_option.selected = WindowSizeController.get_current_preset_index()


func _apply_texts() -> void:
	title_label.text = Locale.t("settings.title")
	language_label.text = Locale.t("settings.language")
	resolution_label.text = Locale.t("settings.resolution")
	back_button.text = Locale.t("common.back")
	version_label.text = Locale.t("settings.version", [AppVersion.VERSION])


func _apply_theme() -> void:
	var background := Panel.new()
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(background)
	add_child(background)
	move_child(background, 0)
	UITheme.apply_title(title_label, 28)
	UITheme.apply_label(language_label)
	UITheme.apply_label(resolution_label)
	UITheme.apply_label(version_label, true)
	UITheme.apply_button(language_option, "secondary")
	UITheme.apply_button(resolution_option, "secondary")
	UITheme.apply_button(back_button, "primary")


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var scale_value: float = min(viewport_size.x / BASE_VIEWPORT_SIZE.x, viewport_size.y / BASE_VIEWPORT_SIZE.y)
	for control in [language_option, resolution_option, back_button]:
		control.custom_minimum_size = Vector2(260, 42) * scale_value
		control.add_theme_font_size_override("font_size", max(12, int(16 * scale_value)))
	title_label.add_theme_font_size_override("font_size", max(18, int(28 * scale_value)))
	version_label.add_theme_font_size_override("font_size", max(10, int(13 * scale_value)))


func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LANGUAGE_CODES.size():
		Locale.set_language(LANGUAGE_CODES[index])


func _on_resolution_selected(index: int) -> void:
	WindowSizeController.apply_preset(index)

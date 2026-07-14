extends RefCounted
class_name UITheme

const COLOR_BG := Color(0.055, 0.065, 0.085)
const COLOR_PANEL := Color(0.105, 0.12, 0.155, 0.96)
const COLOR_PANEL_SOFT := Color(0.13, 0.145, 0.18, 0.9)
const COLOR_PANEL_DARK := Color(0.075, 0.085, 0.11, 0.96)
const COLOR_GOLD := Color(0.90, 0.74, 0.40)
const COLOR_GOLD_SOFT := Color(0.62, 0.50, 0.28)
const COLOR_BLUE := Color(0.30, 0.43, 0.62)
const COLOR_ACCENT := Color(0.36, 0.52, 0.72)
const COLOR_TEXT := Color(0.95, 0.94, 0.89)
const COLOR_TEXT_MUTED := Color(0.68, 0.72, 0.78)
const COLOR_BUTTON := Color(0.17, 0.22, 0.31)
const COLOR_BUTTON_HOVER := Color(0.23, 0.30, 0.42)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.16, 0.24)
const COLOR_PRIMARY := Color(0.40, 0.31, 0.14)
const COLOR_PRIMARY_HOVER := Color(0.55, 0.42, 0.18)
const COLOR_PRIMARY_PRESSED := Color(0.25, 0.19, 0.09)
const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.35)


static func apply_app_background(control: Control) -> void:
	if control == null:
		return
	control.add_theme_stylebox_override("panel", panel_style(COLOR_BG, Color(0.10, 0.12, 0.16), 0, 0))


static func apply_panel(panel: Control, variant: String = "normal") -> void:
	if panel == null:
		return
	var fill := COLOR_PANEL
	var border := COLOR_GOLD_SOFT
	var radius := 12
	var width := 1
	var shadow := COLOR_SHADOW
	var shadow_size := 4
	match variant:
		"dark":
			fill = COLOR_PANEL_DARK
			border = Color(0.20, 0.24, 0.32)
			shadow = Color(0.0, 0.0, 0.0, 0.25)
			shadow_size = 3
		"soft":
			fill = COLOR_PANEL_SOFT
			border = Color(0.26, 0.31, 0.40)
			shadow = Color(0.0, 0.0, 0.0, 0.30)
			shadow_size = 4
		"gold":
			fill = COLOR_PANEL
			border = COLOR_GOLD
			width = 2
			shadow = Color(0.0, 0.0, 0.0, 0.45)
			shadow_size = 6
		"slot":
			fill = Color(0.08, 0.095, 0.125, 0.88)
			border = Color(0.26, 0.30, 0.38)
			radius = 8
			shadow = Color(0.0, 0.0, 0.0, 0.20)
			shadow_size = 2
	panel.add_theme_stylebox_override("panel", panel_style(fill, border, width, radius, shadow, shadow_size))


static func apply_button(button: BaseButton, variant: String = "secondary") -> void:
	if button == null:
		return
	var base := COLOR_BUTTON
	var hover := COLOR_BUTTON_HOVER
	var pressed := COLOR_BUTTON_PRESSED
	var border := COLOR_BLUE
	var shadow := COLOR_SHADOW
	var shadow_size := 2
	var hover_shadow_size := 4
	if variant == "primary":
		base = COLOR_PRIMARY
		hover = COLOR_PRIMARY_HOVER
		pressed = COLOR_PRIMARY_PRESSED
		border = COLOR_GOLD
		shadow = Color(0.0, 0.0, 0.0, 0.40)
		shadow_size = 3
		hover_shadow_size = 6
	elif variant == "danger":
		base = Color(0.30, 0.11, 0.11)
		hover = Color(0.42, 0.15, 0.15)
		pressed = Color(0.20, 0.07, 0.07)
		border = Color(0.78, 0.34, 0.30)
	button.add_theme_stylebox_override("normal", panel_style(base, border, 1, 8, shadow, shadow_size))
	button.add_theme_stylebox_override("hover", panel_style(hover, border.lightened(0.25), 1, 8, shadow, hover_shadow_size))
	button.add_theme_stylebox_override("pressed", panel_style(pressed, border.darkened(0.15), 1, 8, Color(0,0,0,0), 0))
	button.add_theme_stylebox_override("disabled", panel_style(Color(0.10, 0.11, 0.13), Color(0.20, 0.21, 0.24), 1, 8, Color(0,0,0,0), 0))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.72))
	button.add_theme_color_override("font_pressed_color", Color(0.94, 0.82, 0.50))
	button.add_theme_color_override("font_disabled_color", Color(0.44, 0.46, 0.50))


static func apply_title(label: Label, size: int = 24) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.62))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	label.add_theme_constant_override("outline_size", 1)


static func apply_label(label: Label, muted: bool = false) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED if muted else COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


static func apply_input(control: Control) -> void:
	if control == null:
		return
	var normal_style := panel_style(Color(0.075, 0.085, 0.11), Color(0.30, 0.35, 0.45), 1, 6)
	var focus_style := panel_style(Color(0.075, 0.085, 0.11), COLOR_ACCENT, 1, 6, Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.35), 3)
	control.add_theme_stylebox_override("normal", normal_style)
	control.add_theme_stylebox_override("focus", focus_style)
	control.add_theme_stylebox_override("read_only", normal_style)
	control.add_theme_color_override("font_color", COLOR_TEXT)
	control.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED)


static func apply_overlay(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.color = Color(0.0, 0.0, 0.0, 0.62)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP


static func apply_popup_frame(panel: Control, variant: String = "gold") -> void:
	apply_panel(panel, variant)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP


static func theme_tree(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Label:
			apply_label(child)
		elif child is Button:
			var variant := "danger" if child.text == "X" else "secondary"
			apply_button(child, variant)
		elif child is OptionButton or child is CheckBox:
			apply_button(child, "secondary")
		elif child is LineEdit or child is SpinBox or child is TextEdit:
			apply_input(child)
		elif child is Panel or child is PanelContainer:
			apply_panel(child, "soft")
		theme_tree(child)


static func make_popup_layer(parent: Node, layer_index: int = 100) -> Dictionary:
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = layer_index
	parent.add_child(popup_layer)
	var bg := ColorRect.new()
	apply_overlay(bg)
	popup_layer.add_child(bg)
	return {"layer": popup_layer, "bg": bg}


static func panel_style(fill: Color, border: Color, width: int = 1, radius: int = 10, shadow: Color = Color(0, 0, 0, 0), shadow_size: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if shadow_size > 0:
		style.shadow_color = shadow
		style.shadow_size = shadow_size
	return style

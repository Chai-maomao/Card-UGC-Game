class_name BattleStatusHud
extends RefCounted

static func resource_color(word: String) -> Color:
	var words := preload("res://presentation/SkillDescription.gd")
	var color: String = words.KEYWORDS[word][0]
	return Color(words.LIGHT_KEYWORD_COLORS.get(color, color) if UITheme.Tokens.light_mode else color)

static func _apply_status_hud_theme(hud: Panel, enemy: bool, active: bool) -> void:
	if hud == null:
		return
	var faction_color: Color = UITheme.COLOR_ENEMY if enemy else UITheme.COLOR_PLAYER
	var border_color: Color = UITheme.COLOR_GOLD if active else faction_color
	var fill_color := Color(UITheme.COLOR_PANEL_DARK, 0.94)
	hud.add_theme_stylebox_override("panel", UITheme.panel_style(
		fill_color, Color(border_color, 1.0 if active else 0.65), 1, 6
	))

	var content := hud.get_node("Margin/Content") as HBoxContainer
	var side_label := content.get_node("SideLabel") as Label
	var hp_label := content.get_node("HpLabel") as Label
	var mana_value_label := content.get_node("ManaLabel") as Label
	var hand_label := content.get_node("HandLabel") as Label
	for label in [side_label, hp_label, mana_value_label, hand_label]:
		UITheme.apply_label(label)
	side_label.add_theme_color_override("font_color", border_color.lightened(0.22))
	hp_label.add_theme_color_override("font_color", resource_color("生命"))
	mana_value_label.add_theme_color_override("font_color", resource_color("圣水"))
	hand_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD if content.get_node("ActionBar").visible else UITheme.COLOR_TEXT_MUTED)

	var hp_bar := content.get_node("HpBar") as ProgressBar
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	_style_status_bar(hp_bar, resource_color("生命"))
	_style_status_bar(mana_bar, resource_color("圣水"))
	_style_status_bar(content.get_node("ActionBar") as ProgressBar, UITheme.COLOR_GOLD)


static func _style_status_bar(bar: ProgressBar, fill_color: Color) -> void:
	if bar == null:
		return
	bar.add_theme_stylebox_override("background", UITheme.panel_style(
		UITheme.COLOR_BG, UITheme.Tokens.BORDER, 1, 5
	))
	var fill := UITheme.panel_style(fill_color, fill_color.lightened(0.20), 1, 5)
	# Resource lengths must be proportional even at low values.
	fill.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill",fill)


static func _scale_status_hud(hud: Panel, scale_value: float) -> void:
	if hud == null:
		return
	hud.custom_minimum_size = Vector2(720, 38) * scale_value
	var margin := hud.get_node("Margin") as MarginContainer
	margin.add_theme_constant_override("margin_left", max(7, int(14 * scale_value)))
	margin.add_theme_constant_override("margin_right", max(7, int(14 * scale_value)))
	var content := hud.get_node("Margin/Content") as HBoxContainer
	content.add_theme_constant_override("separation", max(4, int(8 * scale_value)))
	var label_size: int = max(9, int(13 * scale_value))
	for label in [content.get_node("SideLabel"), content.get_node("HpLabel"), content.get_node("ManaLabel"), content.get_node("HandLabel")]:
		(label as Label).add_theme_font_size_override("font_size", label_size)
	content.get_node("SideLabel").custom_minimum_size = Vector2(64 * scale_value, 0)
	content.get_node("HpLabel").custom_minimum_size = Vector2(96 * scale_value, 0)
	content.get_node("HpBar").custom_minimum_size = Vector2(104, 14) * scale_value
	content.get_node("ManaLabel").custom_minimum_size = Vector2(100 * scale_value, 0)
	content.get_node("ManaBar").custom_minimum_size = Vector2(88, 14) * scale_value
	content.get_node("HandLabel").custom_minimum_size = Vector2(100 * scale_value, 0)
	content.get_node("ActionBar").custom_minimum_size = Vector2(88, 14) * scale_value

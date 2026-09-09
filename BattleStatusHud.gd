class_name BattleStatusHud
extends RefCounted

static func _apply_status_hud_theme(hud: Panel, enemy: bool, active: bool) -> void:
	if hud == null:
		return
	var faction_color: Color = UITheme.COLOR_ENEMY if enemy else UITheme.COLOR_PLAYER
	var border_color: Color = UITheme.COLOR_GOLD if active else faction_color
	var fill_color := Color(0.105, 0.045, 0.08, 0.94) if enemy else Color(0.025, 0.095, 0.14, 0.94)
	var glow := Color(border_color.r, border_color.g, border_color.b, 0.30 if active else 0.12)
	hud.add_theme_stylebox_override("panel", UITheme.panel_style(
		fill_color, border_color, 2 if active else 1, 9, glow, 4 if active else 2
	))

	var content := hud.get_node("Margin/Content") as HBoxContainer
	var side_label := content.get_node("SideLabel") as Label
	var hp_label := content.get_node("HpLabel") as Label
	var mana_value_label := content.get_node("ManaLabel") as Label
	var hand_label := content.get_node("HandLabel") as Label
	for label in [side_label, hp_label, mana_value_label, hand_label]:
		UITheme.apply_label(label)
	side_label.add_theme_color_override("font_color", border_color.lightened(0.22))
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.50, 0.48))
	mana_value_label.add_theme_color_override("font_color", Color(0.40, 0.86, 1.0))
	hand_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)

	var hp_bar := content.get_node("HpBar") as ProgressBar
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	_style_status_bar(hp_bar, Color(0.88, 0.24, 0.24))
	_style_status_bar(mana_bar, Color(0.20, 0.72, 0.88))


static func _style_status_bar(bar: ProgressBar, fill_color: Color) -> void:
	if bar == null:
		return
	bar.add_theme_stylebox_override("background", UITheme.panel_style(
		Color(0.025, 0.03, 0.045, 0.90), Color(0.20, 0.24, 0.31, 0.85), 1, 7
	))
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(
		fill_color, fill_color.lightened(0.20), 1, 7
	))


static func _scale_status_hud(hud: Panel, scale_value: float) -> void:
	if hud == null:
		return
	hud.custom_minimum_size = Vector2(720, 38) * scale_value
	var margin := hud.get_node("Margin") as MarginContainer
	margin.add_theme_constant_override("margin_left", max(7, int(14 * scale_value)))
	margin.add_theme_constant_override("margin_right", max(7, int(14 * scale_value)))
	var content := hud.get_node("Margin/Content") as HBoxContainer
	content.add_theme_constant_override("separation", max(4, int(10 * scale_value)))
	var label_size: int = max(9, int(13 * scale_value))
	for label in [content.get_node("SideLabel"), content.get_node("HpLabel"), content.get_node("ManaLabel"), content.get_node("HandLabel")]:
		(label as Label).add_theme_font_size_override("font_size", label_size)
	content.get_node("SideLabel").custom_minimum_size = Vector2(72 * scale_value, 0)
	content.get_node("HpLabel").custom_minimum_size = Vector2(108 * scale_value, 0)
	content.get_node("HpBar").custom_minimum_size = Vector2(128, 14) * scale_value
	content.get_node("ManaLabel").custom_minimum_size = Vector2(108 * scale_value, 0)
	content.get_node("ManaBar").custom_minimum_size = Vector2(104, 14) * scale_value
	content.get_node("HandLabel").custom_minimum_size = Vector2(104 * scale_value, 0)

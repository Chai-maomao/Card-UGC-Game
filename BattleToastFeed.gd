extends VBoxContainer

const UITheme = preload("res://UITheme.gd")
const MAX_MESSAGES := 3
const KIND_STYLE := {
	"warn": {"border": Color(0.95, 0.58, 0.25), "text": Color(1.0, 0.86, 0.66)},
	"attack": {"border": Color(0.85, 0.32, 0.30), "text": Color(1.0, 0.82, 0.78)},
	"skill": {"border": Color(0.20, 0.72, 0.84), "text": Color(0.82, 0.95, 1.0)},
	"system": {"border": Color(0.62, 0.50, 0.28), "text": Color(0.96, 0.94, 0.88)},
}


func _init() -> void:
	name = "ToastStack"
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.14
	anchor_bottom = 0.14
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# The caller supplies only presentation data. This component owns message
# capacity, styles and node-bound animation lifetimes, without battle state.
func show_message(text: String, kind: String = "system", hold: float = 1.8, ui_scale: float = 1.0) -> PanelContainer:
	if text.strip_edges().is_empty():
		return null
	while get_child_count() >= MAX_MESSAGES:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var style_cfg: Dictionary = KIND_STYLE.get(kind, KIND_STYLE["system"])
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.045, 0.055, 0.08, 0.88), style_cfg["border"], 1, 8,
		Color(style_cfg["border"].r, style_cfg["border"].g, style_cfg["border"].b, 0.28), 5
	))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", max(11, int(17 * ui_scale)))
	label.add_theme_color_override("font_color", style_cfg["text"])
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.custom_minimum_size = Vector2(min(560, 380 * ui_scale), 0)
	panel.add_child(label)
	add_child(panel)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free)
	return panel


func reject_latest() -> void:
	if get_child_count() > 0:
		UITheme.reject_shake(get_child(get_child_count() - 1))

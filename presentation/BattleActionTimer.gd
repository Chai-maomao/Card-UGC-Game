extends Control

var _ratio := 1.0
var _seconds := 0
var _paused := false


func _ready() -> void:
	name = "BattleActionTimer"
	_refresh_metrics()
	size_flags_vertical = SIZE_SHRINK_CENTER
	mouse_filter = MOUSE_FILTER_PASS
	tooltip_text = Locale.t("battle.action_timer")
	AppPreferences.changed.connect(_on_preferences_changed)
	hide()


func _on_preferences_changed(key: String) -> void:
	if key == "text_size":
		_refresh_metrics()
	elif key == "high_contrast" or key == "appearance":
		queue_redraw()


func _refresh_metrics() -> void:
	var digits_width := UITheme.bold_font().get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
	custom_minimum_size = Vector2(maxf(86, ceilf(digits_width) + 43), 34)
	queue_redraw()


func _font_size() -> int:
	return 16 + int(AppPreferences.get_value("text_size")) * 2


func present(remaining_ms: int, limit_ms: int, paused: bool) -> void:
	visible = limit_ms > 0
	if not visible:
		return
	var fraction := float(remaining_ms) / limit_ms
	var seconds := ceili(remaining_ms / 1000.0)
	if is_equal_approx(_ratio, fraction) and _seconds == seconds and _paused == paused:
		return
	_ratio = fraction
	_seconds = seconds
	_paused = paused
	queue_redraw()


func _draw() -> void:
	var urgent := _seconds <= 5
	var high_contrast := bool(AppPreferences.get_value("high_contrast"))
	var accent := UITheme.COLOR_ENEMY if urgent else (UITheme.Tokens.CONTRAST_INK if high_contrast else UITheme.Tokens.BRASS)
	var fill := UITheme.Tokens.PANEL_DARK if UITheme.Tokens.light_mode else (Color("171614") if high_contrast else Color("251f17"))
	var frame := UITheme.panel_style(fill, Color(accent, 0.65), 1, 7)
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	var center := Vector2(18, size.y * 0.5)
	var top := -PI * 0.5
	draw_arc(center, 9, top, top + TAU, 36, Color(accent, 0.28), 2, true)
	if _ratio > 0.0:
		draw_arc(center, 9, top, top + TAU * _ratio, 36, accent, 2, true)
	if _paused:
		for offset in [-2.0, 2.0]:
			draw_line(center + Vector2(offset, -3.0), center + Vector2(offset, 3.0), accent, 1.4, true)
	else:
		draw_line(center, center + Vector2(0, -4), accent, 1.4, true)
		draw_line(center, center + Vector2(3, 1), accent, 1.4, true)
	var font := UITheme.bold_font()
	var font_size := _font_size()
	@warning_ignore("integer_division")
	var time_text := "%02d:%02d" % [_seconds / 60, _seconds % 60]
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2(33, baseline), time_text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 39, font_size, accent if urgent else UITheme.COLOR_TEXT)

extends Button

func _ready() -> void:
	name = "CardSelection"
	mouse_entered.connect(func():
		if not disabled: AppAudio.play_hover(self,true)
	)
	toggle_mode = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 110
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled"]:
		var fill := Color.TRANSPARENT
		if state == "hover": fill = Color(UITheme.Tokens.BRASS,0.12)
		if state == "pressed": fill = Color(UITheme.Tokens.TEAL,0.32)
		add_theme_stylebox_override(state,UITheme.panel_style(fill,UITheme.Tokens.BRASS,2 if state == "pressed" else 0,3,Color.TRANSPARENT,0))
	add_theme_stylebox_override("focus",UITheme.panel_style(Color.TRANSPARENT,UITheme.Tokens.TEXT,2,3,Color.TRANSPARENT,0))
	toggled.connect(func(_selected): queue_redraw())
	tooltip_text = get_parent().tooltip_text

func _draw() -> void:
	if button_pressed:
		draw_circle(Vector2(size.x-14,14),11,UITheme.Tokens.BRASS)
		draw_string(UITheme.bold_font(),Vector2(size.x-21,20),"✓",HORIZONTAL_ALIGNMENT_LEFT,-1,17,UITheme.Tokens.INK)

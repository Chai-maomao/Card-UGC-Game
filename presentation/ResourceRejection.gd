extends RefCounted

static func play(bar: ProgressBar) -> void:
	var prior: Tween = bar.get_meta("rejection_tween") if bar.has_meta("rejection_tween") else null
	var rest: Vector2 = bar.get_meta("rejection_rest",bar.position) if prior != null and prior.is_running() else bar.position
	if prior != null: prior.kill()
	bar.position = rest
	bar.set_meta("rejection_rest",rest)
	var border := bar.get_node_or_null("ResourceRejection") as Panel
	if border == null:
		border = Panel.new()
		border.name = "ResourceRejection"
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.z_index = 10
		bar.add_child(border)
		border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := bar.get_theme_stylebox("background").duplicate() as StyleBoxFlat
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color("cc6256")
	style.set_border_width_all(1)
	style.shadow_size = 0
	border.add_theme_stylebox_override("panel",style)
	border.show()
	var tween := bar.create_tween()
	bar.set_meta("rejection_tween",tween)
	if not AppPreferences.get_value("reduced_motion"):
		for offset in [-3,3,-2,2,0]: tween.tween_property(bar,"position",rest+Vector2(offset,0),0.04)
	else: tween.tween_interval(0.2)
	tween.tween_interval(0.18)
	tween.tween_callback(func(): bar.position=rest; border.hide())

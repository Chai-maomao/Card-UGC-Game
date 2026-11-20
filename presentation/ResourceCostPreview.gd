extends RefCounted

const HATCH_SHADER = preload("res://presentation/resource_forecast.gdshader")

static func update(bar: ProgressBar, cost: int, available: int, insufficient: bool, color: Color = Color(0.87,0.34,0.29)) -> void:
	var overlay := bar.get_node_or_null("ResourceCostPreview") as Control
	if cost <= 0:
		if overlay != null: overlay.hide()
		return
	if overlay == null:
		overlay = Control.new()
		overlay.name = "ResourceCostPreview"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.z_index = 5
		bar.add_child(overlay)
		var tint := ColorRect.new()
		tint.name = "TintFill"
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = HATCH_SHADER
		tint.material = material
		overlay.add_child(tint)
	var end := _fill_end(bar,float(cost) if insufficient else bar.value)
	var begin := 0.0 if insufficient else _fill_end(bar,maxf(0,bar.value-cost))
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	overlay.position = Vector2(begin,0)
	overlay.size = Vector2(maxf(0,end-begin),bar.size.y)
	var tint := overlay.get_node("TintFill") as ColorRect
	tint.size = overlay.size
	var material := tint.material as ShaderMaterial
	material.set_shader_parameter("rect_size",tint.size)
	material.set_shader_parameter("forecast_color",color)
	var style := bar.get_theme_stylebox("fill") as StyleBoxFlat
	material.set_shader_parameter("radius",float(style.corner_radius_top_right))
	overlay.set_meta("cost",cost)
	overlay.set_meta("after",available-cost)
	overlay.show()

static func _fill_end(bar: ProgressBar, value: float) -> float:
	var span := maxf(1,bar.max_value-bar.min_value)
	var ratio := clampf((value-bar.min_value)/span,0,1)
	var minimum := bar.get_theme_stylebox("fill").get_minimum_size().x
	var pixels := roundf(ratio*(bar.size.x-minimum))
	return minf(bar.size.x,pixels+minimum) if pixels>0 else 0.0

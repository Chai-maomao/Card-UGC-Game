extends Panel
var polygon := PackedVector2Array()
func _draw() -> void:
	if polygon.size() < 4: return
	var line := polygon.duplicate()
	line.append(polygon[0])
	draw_polyline(line, UITheme.COLOR_GOLD, 3.0, true)

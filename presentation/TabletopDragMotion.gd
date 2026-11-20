extends Control

var last_position := Vector2.ZERO
var initialized := false
var tilt := 0.0

func _process(delta: float) -> void:
	var foreground := get_node("TabletopDragForeground") as CanvasLayer
	foreground.offset = global_position
	if not initialized:
		last_position = global_position
		initialized = true
	var velocity := (global_position-last_position)/maxf(delta,0.001)
	last_position = global_position
	var desired := 0.0 if AppPreferences.get_value("reduced_motion") else clampf(velocity.x*0.00006,-0.055,0.055)
	tilt = lerpf(tilt,desired,1.0-exp(-22.0*delta))
	for child in foreground.get_children():
		if child is Control: child.rotation = tilt

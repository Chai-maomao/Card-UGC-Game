extends Control

var texture: Texture2D
var destination := Vector2.ZERO
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

func row_progress(row: float) -> float:
	return smoothstep(0.0,1.0,clampf(progress*1.5-(1.0-row)*0.5,0.0,1.0))

func row_point(row: float, side: float) -> Vector2:
	var pull := row_progress(row)
	var initial := Vector2(side*size.x*0.5,(row-0.5)*size.y)
	# The leading edge narrows first; the trailing edge follows into the same point.
	var point := initial.lerp(destination-size*0.5,pull)
	point.x = lerpf(point.x,(destination.x-size.x*0.5)*pull,pull*0.65)
	return point+size*0.5

func _draw() -> void:
	if texture == null: return
	for strip in range(24):
		var a := float(strip)/24.0
		var b := float(strip+1)/24.0
		var points := PackedVector2Array([row_point(a,-1),row_point(a,1),row_point(b,1),row_point(b,-1)])
		var colors := PackedColorArray()
		for row in [a,a,b,b]:
			var alpha := (1.0-smoothstep(0.88,1.0,row_progress(row)))*minf(1.0,progress/0.08)
			colors.append(Color(1,1,1,alpha))
		var uvs := PackedVector2Array([Vector2(0,a),Vector2(1,a),Vector2(1,b),Vector2(0,b)])
		# Explicit triangles remain valid as the last strips fold into a point.
		for triangle in [[0,1,2],[0,2,3]]:
			draw_primitive(PackedVector2Array([points[triangle[0]],points[triangle[1]],points[triangle[2]]]),PackedColorArray([colors[triangle[0]],colors[triangle[1]],colors[triangle[2]]]),PackedVector2Array([uvs[triangle[0]],uvs[triangle[1]],uvs[triangle[2]]]),texture)

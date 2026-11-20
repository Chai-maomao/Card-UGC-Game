extends StyleBox

const JOIN_OVERLAP := 5 # Four-pixel tab plus the shared one-pixel outline.
@export var shape := "boolean"
@export var fill := Color("173d3e")
@export var edge := Color("448783")
@export var width := 1.0
var cavities: Array[Rect2] = []
static var _number_icon: Texture2D

static func compact_number(spin: SpinBox) -> void:
	if _number_icon == null:
		_number_icon = ImageTexture.create_from_image(Image.create(1,1,false,Image.FORMAT_RGBA8))
	spin.add_theme_icon_override("updown", _number_icon)
	# A transparent icon alone leaves Godot's stepper hit regions and hover
	# materials active. Give the full width back to the editable number.
	spin.add_theme_constant_override("buttons_width", 0)
	spin.add_theme_constant_override("set_min_buttons_width_from_icons", 0)
	spin.add_theme_constant_override("field_and_buttons_separation", 0)
	for button in ["up", "down"]:
		for state in ["", "_hover", "_pressed", "_disabled"]:
			spin.add_theme_icon_override(button + state, _number_icon)
		for state in ["", "_hovered", "_pressed", "_disabled"]:
			spin.add_theme_stylebox_override(button + "_background" + state, StyleBoxEmpty.new())
	spin.add_theme_stylebox_override("field_and_buttons_separator", StyleBoxEmpty.new())
	spin.add_theme_stylebox_override("up_down_buttons_separator", StyleBoxEmpty.new())

static func from_flat(style: StyleBoxFlat, kind: String) -> StyleBox:
	var result = load("res://SkillSocketStyle.gd").new()
	result.shape = kind
	result.fill = style.bg_color
	result.edge = style.border_color
	result.width = float(style.border_width_left)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_content_margin(side, style.get_content_margin(side))
	result.content_margin_left = maxf(result.content_margin_left, 16 if kind == "boolean" else 10)
	result.content_margin_right = result.content_margin_left
	return result

func _draw(canvas: RID, rect: Rect2) -> void:
	var r := rect.grow(-width * 0.5)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	if w <= 0 or h <= 0: return
	var points: PackedVector2Array
	if shape == "hat" and w >= 70 and h >= 24:
		points = PackedVector2Array([Vector2(x,y+12),Vector2(x+6,y+6),Vector2(x+18,y+1),Vector2(x+38,y),Vector2(x+56,y+5),Vector2(x+66,y+12),Vector2(x+w-3,y+12),Vector2(x+w,y+15),Vector2(x+w,y+h-4),Vector2(x+40,y+h-4),Vector2(x+36,y+h),Vector2(x+20,y+h),Vector2(x+16,y+h-4),Vector2(x,y+h-4)])
	elif shape == "terminal" and w >= 44 and h >= 12:
		points = PackedVector2Array([Vector2(x,y),Vector2(x+16,y),Vector2(x+20,y+4),Vector2(x+36,y+4),Vector2(x+40,y),Vector2(x+w-2,y),Vector2(x+w,y+2),Vector2(x+w,y+h-2),Vector2(x+w-2,y+h),Vector2(x+2,y+h),Vector2(x,y+h-2)])
	elif shape in ["stack", "control"] and w >= 44 and h >= 12:
		points = PackedVector2Array([Vector2(x,y),Vector2(x+16,y),Vector2(x+20,y+4),Vector2(x+36,y+4),Vector2(x+40,y),Vector2(x+w,y)])
		var previous_end := y + 6
		var openings := cavities
		if shape == "control": openings = [Rect2(Vector2(x+12,y+30),Vector2(w-12,maxf(8,h-46)))]
		for gap in openings:
			var left := x+12 if shape == "control" else x+gap.position.x
			var top := maxf(previous_end, gap.position.y if shape == "control" else y+gap.position.y)
			var bottom := minf(y+h-8, gap.end.y if shape == "control" else rect.position.y+gap.end.y-width*0.5-4)
			if bottom <= top: continue
			points.append_array(PackedVector2Array([
				Vector2(x+w,top),Vector2(left+40,top),Vector2(left+36,top+4),
				Vector2(left+20,top+4),Vector2(left+16,top),Vector2(left,top),
				Vector2(left,bottom),Vector2(left+16,bottom),Vector2(left+20,bottom+4),
				Vector2(left+36,bottom+4),Vector2(left+40,bottom),Vector2(x+w,bottom)]))
			previous_end = bottom + 1
		points.append_array(PackedVector2Array([Vector2(x+w,y+h-4),Vector2(x+40,y+h-4),Vector2(x+36,y+h),Vector2(x+20,y+h),Vector2(x+16,y+h-4),Vector2(x,y+h-4)]))
	elif shape == "boolean":
		var tip := minf(h * 0.5, 14)
		points = PackedVector2Array([Vector2(x+tip,y),Vector2(x+w-tip,y),Vector2(x+w,y+h/2),Vector2(x+w-tip,y+h),Vector2(x+tip,y+h),Vector2(x,y+h/2)])
	elif shape == "side":
		points = PackedVector2Array([Vector2(x,y),Vector2(x+w,y),Vector2(x+w-7,y+h/2),Vector2(x+w,y+h),Vector2(x,y+h),Vector2(x+7,y+h/2)])
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = fill
		flat.border_color = edge
		flat.set_border_width_all(int(width))
		flat.set_corner_radius_all(4)
		flat.draw(canvas, rect)
		return
	RenderingServer.canvas_item_add_polygon(canvas, points, PackedColorArray([fill]))
	points.append(points[0])
	RenderingServer.canvas_item_add_polyline(canvas, points, PackedColorArray([edge]), width, true)

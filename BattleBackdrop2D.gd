extends Control

# A restrained, code-drawn playmat.  It gives the two card rows a shared
# physical surface without introducing art dependencies or a fake 3D camera.

const ENEMY_TINT := Color(0.56, 0.16, 0.36)
const PLAYER_TINT := Color(0.08, 0.58, 0.76)

var _last_signature := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	call_deferred("queue_redraw")


func _process(_delta: float) -> void:
	# Container layout settles after resize. Redraw only when the two lane
	# rectangles actually move, rather than invalidating the canvas every frame.
	var signature := "%s|%s|%s" % [size, _lane_rect("../MainLayout/EnemySide"), _lane_rect("../MainLayout/PlayerSide")]
	if signature != _last_signature:
		_last_signature = signature
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.022, 0.030, 0.047), true)

	# Wide low-contrast bands remove the old hard two-colour split while still
	# making ownership readable at a glance.
	_draw_lane(_lane_rect("../MainLayout/EnemySide"), ENEMY_TINT, true)
	_draw_lane(_lane_rect("../MainLayout/PlayerSide"), PLAYER_TINT, false)

	# Quiet vignette and centre glint keep the eye on the play area. Rectangles
	# are deliberately sparse so small text remains crisp on lower-end GPUs.
	for i in range(8):
		var inset := float(i) * 12.0
		var alpha := 0.018 + float(i) * 0.006
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0)), Color(0, 0, 0, alpha), false, 12.0)
	var centre_y := size.y * 0.435
	draw_line(Vector2(size.x * 0.17, centre_y), Vector2(size.x * 0.83, centre_y), Color(0.90, 0.74, 0.40, 0.10), 1.0)


func _draw_lane(rect: Rect2, tint: Color, enemy: bool) -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color(0.028, 0.039, 0.058, 0.72)
	outer.border_color = Color(tint.r, tint.g, tint.b, 0.22)
	outer.set_border_width_all(1)
	outer.set_corner_radius_all(18)
	outer.shadow_color = Color(0, 0, 0, 0.26)
	outer.shadow_size = 8
	draw_style_box(outer, rect)

	var rail_y := rect.position.y + (11.0 if enemy else rect.size.y - 11.0)
	draw_line(Vector2(rect.position.x + 24.0, rail_y), Vector2(rect.end.x - 24.0, rail_y), Color(tint.r, tint.g, tint.b, 0.26), 2.0)
	# Five subtle registration marks visually tie each row together without
	# competing with the actual slot borders.
	for i in range(5):
		var x := rect.position.x + rect.size.x * (float(i) + 0.5) / 5.0
		draw_line(Vector2(x - 9.0, rail_y), Vector2(x + 9.0, rail_y), Color(tint.r, tint.g, tint.b, 0.38), 2.0)


func _lane_rect(path: NodePath) -> Rect2:
	var row := get_node_or_null(path) as Control
	if row == null or not row.is_inside_tree():
		return Rect2()
	var local_position := row.global_position - global_position
	return Rect2(local_position - Vector2(30, 14), row.size + Vector2(60, 28))

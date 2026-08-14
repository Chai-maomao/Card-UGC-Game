extends Node2D

## Directed line segment used for targeting. Draws a shaft from points[0]
## to points[1] with an arrowhead at the end. Keeps the Line2D-style
## `points` API so existing callers keep working.
##
## The shaft uses a color gradient (fades in from the start) plus a dark
## outline; the arrowhead is filled with an outline too, so the arrow stays
## readable over any background.

@export var width: float = 8.0:
	set(value):
		width = value
		queue_redraw()

@export var default_color: Color = Color(1, 0, 0, 1):
	set(value):
		default_color = value
		queue_redraw()

@export var arrow_length: float = 28.0
@export var arrow_width: float = 26.0

var points: PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		queue_redraw()

const _OUTLINE := Color(0.04, 0.01, 0.01, 0.55)
const _SHAFT_SEGMENTS := 12


func _draw() -> void:
	if points.size() < 2:
		return
	var start: Vector2 = to_local(points[0])
	var end: Vector2 = to_local(points[1])
	var dir: Vector2 = end - start
	var dist: float = dir.length()
	if dist <= 0.001:
		return
	dir = dir / dist

	# Stop the shaft where the arrowhead begins so they don't overlap.
	var head_len: float = min(arrow_length, dist)
	var shaft_end: Vector2 = end - dir * head_len
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var base: Vector2 = end - dir * head_len

	# Shaft with a color gradient along its length, plus a dark outline.
	var grad_start: Color = Color(default_color.r, default_color.g, default_color.b, 0.20)
	var shaft_points := PackedVector2Array()
	var shaft_colors := PackedColorArray()
	for i in range(_SHAFT_SEGMENTS + 1):
		var t := float(i) / float(_SHAFT_SEGMENTS)
		shaft_points.append(start.lerp(shaft_end, t))
		shaft_colors.append(grad_start.lerp(default_color, t))
	# A wide soft "glow" pass first, then the crisp outline, then the gradient.
	draw_polyline(shaft_points, Color(default_color.r, default_color.g, default_color.b, 0.10), width + 5.0, true)
	draw_polyline(shaft_points, _OUTLINE, width + 2.0, true)
	draw_polyline_colors(shaft_points, shaft_colors, width, true)

	# Arrowhead: outline polygon underneath, colored fill on top.
	var p1: Vector2 = base + perp * (arrow_width * 0.5)
	var p2: Vector2 = base - perp * (arrow_width * 0.5)
	var outline_base: Vector2 = base - dir * 3.0
	var outline_p1: Vector2 = base + perp * (arrow_width * 0.5 + 3.0)
	var outline_p2: Vector2 = base - perp * (arrow_width * 0.5 + 3.0)
	draw_colored_polygon(PackedVector2Array([end, outline_p1, outline_p2]), _OUTLINE)
	draw_colored_polygon(PackedVector2Array([end, p1, p2]), default_color)

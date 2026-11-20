extends Node2D

var radius := 8
var fill_alpha := 0.0
var shape := ""

func _ready() -> void:
	z_index = 5
	get_parent().resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var field := get_parent() as Control
	if field == null: return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93,0.35,0.32,fill_alpha)
	style.border_color = Color("ed7772")
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	var rendered: StyleBox = style if shape == "" else preload("res://SkillSocketStyle.gd").from_flat(style, shape)
	draw_style_box(rendered,Rect2(Vector2.ZERO,field.size))

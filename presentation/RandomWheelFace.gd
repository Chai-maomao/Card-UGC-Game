extends Control

const BRASS := Color("c2a16a")
const PAPER := Color("eee4cb")
const TEAL := Color("528e87")
var outcome: Dictionary = {}
var angle := 0.0:
	set(value): angle=value; queue_redraw()
var settled := false:
	set(value): settled=value; queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _arc(radius: float,from: float,to: float,color: Color,width: float) -> void:
	draw_arc(Vector2.ZERO,radius,from,to,maxi(2,ceili(absf(to-from)*radius/3)),color,width,true)

func _sector(radius: float,from: float,to: float,color: Color) -> void:
	if to<=from: return
	if to-from>=TAU-.0001:
		draw_circle(Vector2.ZERO,radius,color,true,-1,true)
		return
	var points := PackedVector2Array([Vector2.ZERO])
	for index in range(ceili((to-from)*radius/3)+1):
		var a := lerpf(from,to,float(index)/maxi(1,ceili((to-from)*radius/3)))
		points.append(Vector2.from_angle(a)*radius)
	draw_colored_polygon(points,color)

func _text(text: String,at: Vector2,font_size: int,color: Color,font: Font=null) -> void:
	if font==null: font=UITheme.medium_font()
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	# Geometry stays crisp at every resolution; no baked symbols or emblems.
	for index in range(12,0,-1):
		draw_circle(Vector2(0,9),158+index,Color(0,0,0,.012*(13-index)),true,-1,true)
	draw_circle(Vector2(0,5),160,Color("191b19"),true,-1,true)
	draw_circle(Vector2.ZERO,158,Color("51422e"),true,-1,true)
	draw_circle(Vector2.ZERO,154,BRASS,true,-1,true)
	draw_circle(Vector2.ZERO,150,Color("6d5637"),true,-1,true)
	draw_circle(Vector2.ZERO,146,Color("d5ba80"),true,-1,true)
	draw_circle(Vector2.ZERO,142,Color("202e30"),true,-1,true)
	var chance := str(outcome.get("type","chance"))=="chance"
	if chance:
		var portion := clampf(float(outcome.get("probability",50))/100,0,1)
		_sector(140,angle-PI*.5,angle-PI*.5+TAU,Color("29383a"))
		_sector(140,angle-PI*.5,angle-PI*.5+TAU*portion,TEAL)
		for boundary in [0.0,portion]:
			var direction := Vector2.from_angle(angle-PI*.5+TAU*boundary)
			draw_line(direction*60,direction*140,Color("c5b487"),1.5,true)
		if portion>.13 and portion<.87:
			_text(("成功" if Locale.language=="zh" else "YES"),Vector2.from_angle(angle-PI*.5+TAU*portion*.5)*103+Vector2(0,6),18,PAPER)
			_text(("未触发" if Locale.language=="zh" else "NO"),Vector2.from_angle(angle-PI*.5+TAU*(portion+(1-portion)*.5))*103+Vector2(0,6),16,Color("a2b2af"))
	else:
		var minimum := int(outcome.get("minimum",1))
		var maximum := int(outcome.get("maximum",6))
		var count := maxi(1,maximum-minimum+1)
		var divisions := count if count<=24 else 12
		if count>24: draw_circle(Vector2.ZERO,140,Color("e3d8bb"),true,-1,true)
		for index in range(divisions):
			var from := angle-PI*.5+TAU*index/divisions
			var to := angle-PI*.5+TAU*(index+1)/divisions
			if count<=24:
				_sector(140,from,to,Color("e3d8bb") if index%2==0 else Color("cabe9e"))
				draw_line(Vector2.from_angle(from)*59,Vector2.from_angle(from)*140,Color("827153"),1,true)
			var value := minimum+index if count<=24 else minimum+roundi(float(index)*count/divisions)
			var label_angle := (from+to)*.5 if count<=24 else angle-PI*.5+TAU*(value-minimum+.5)/count
			var selected_angle := angle-PI*.5+TAU*(int(outcome.get("result",minimum))-minimum+.5)/count
			if count<=24 or not settled or absf(angle_difference(label_angle,selected_angle))>.5:
				_text(str(value),Vector2.from_angle(label_angle)*108+Vector2(0,7),22 if count<=12 else 14,Color("263b39"))
		if count>24 and settled:
			var selected_angle := angle-PI*.5+TAU*(int(outcome.get("result",minimum))-minimum+.5)/count
			_text(str(outcome.get("result",minimum)),Vector2.from_angle(selected_angle)*108+Vector2(0,7),20,Color("263b39"))
	# Fine scale, brushed highlights and small recessed fasteners.
	for tick in range(100):
		var a := angle-PI*.5+TAU*tick/100
		var outer := Vector2.from_angle(a)*139
		draw_line(outer,Vector2.from_angle(a)*(130 if tick%5==0 else 135),Color(BRASS,.7),1,true)
	_arc(154,-PI*.93,-PI*.2,Color("f0dfb4"),1.6)
	_arc(149,PI*.05,PI*.8,Color("5d452b"),1.5)
	for a in [PI*.25,PI*.75,PI*1.25,PI*1.75]:
		var at := Vector2.from_angle(a)*151.8
		draw_circle(at,2.1,Color("6d5433"),true,-1,true)
		draw_line(at-Vector2(1,0),at+Vector2(1,0),Color("eddaad"),.7,true)
	draw_circle(Vector2(0,3),62,Color(0,0,0,.25),true,-1,true)
	draw_circle(Vector2.ZERO,61,BRASS,true,-1,true)
	draw_circle(Vector2.ZERO,57,Color("1a292b"),true,-1,true)
	var number := ""
	if settled:
		number=("成功" if bool(outcome.get("success",false)) else "未触发") if chance and Locale.language=="zh" else (("YES" if bool(outcome.get("success",false)) else "NO") if chance else str(outcome.get("result",0)))
	else: number=("判定中" if Locale.language=="zh" else "ROLLING")
	_text(number,Vector2(0,9),28 if settled else 16,PAPER,UITheme.bold_font())
	# Stationary twelve-o'clock pointer: visually independent of the rotor.
	draw_colored_polygon(PackedVector2Array([Vector2(-10,-165),Vector2(10,-165),Vector2(0,-132)]),Color("3d3020"))
	draw_colored_polygon(PackedVector2Array([Vector2(-8,-166),Vector2(8,-166),Vector2(0,-136)]),Color("e3c68b"))
	draw_line(Vector2(-8,-166),Vector2(0,-136),Color("fff0c4"),1,true)

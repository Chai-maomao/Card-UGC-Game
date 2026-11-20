extends Node2D

var battle: Node
var effects: Dictionary = {}
var elapsed := 0.0

func _process(delta: float) -> void:
	elapsed = 0.0 if AppPreferences.get_value("reduced_motion") else elapsed+delta
	effects.clear()
	if not is_instance_valid(battle) or battle.tabletop == null: return
	for side in [1,2]:
		var field: BattleField = battle.game.player_field if side==1 else battle.game.player2_field
		for index in range(field.slots.size()):
			var card: CardData = field.slots[index]
			if card == null or not card.is_alive(): continue
			var statuses: Array[String] = []
			if card.is_silenced(): statuses.append("silence")
			if card.has_stun(): statuses.append("stun")
			for effect in card.status_effects:
				var id := str(effect.get("buff_id",""))
				if id in ["poison","regen"] and int(effect.get("value",0))>0 and int(effect.get("duration",0))>0 and not statuses.has(id): statuses.append(id)
			if statuses.is_empty(): continue
			var key: int = index+(5 if side != battle._view_player() else 0)
			var corners: PackedVector2Array = battle.tabletop.projected_slot_corners(key)
			if corners.size()==4: effects[card.get_instance_id()] = {"statuses":statuses,"corners":corners}
	queue_redraw()

func _draw() -> void:
	for state in effects.values():
		var p: PackedVector2Array = state.corners
		var width := p[0].distance_to(p[1])
		var scale_factor := clampf(width/110.0,0.65,1.6)
		for id in state.statuses:
			match id:
				"stun": _stun(p,scale_factor)
				"silence": _silence(p,scale_factor)
				"poison": _poison(p,scale_factor)
				"regen": _regen(p,scale_factor)

func _point(p: PackedVector2Array, x: float, y: float) -> Vector2:
	return p[0].lerp(p[1],x).lerp(p[3].lerp(p[2],x),y)

func _star(center: Vector2, radius: float, color: Color) -> void:
	var shape := PackedVector2Array()
	for i in range(10):
		var angle := -PI/2+i*PI/5
		shape.append(center+Vector2(cos(angle),sin(angle))*radius*(1.0 if i%2==0 else 0.43))
	draw_colored_polygon(shape,color)

func _stun(p: PackedVector2Array, s: float) -> void:
	var center := _point(p,0.5,0.17)
	draw_arc(center,20*s,0,TAU,32,Color(0.95,0.75,0.25,0.45),1.2*s,true)
	for i in range(3):
		var phase := elapsed*1.7+i*TAU/3
		var at := center+Vector2(cos(phase)*20,sin(phase)*6)*s
		_star(at,6*s,Color("33291b"))
		_star(at,4.5*s,Color("ffdf65"))

func _silence(p: PackedVector2Array, s: float) -> void:
	var project := func(offset: Vector2) -> Vector2:
		# Badge geometry uses the card face's horizontal and vertical axes.
		return _point(p, 0.78 + offset.x / 110.0, 0.36 + offset.y / 151.0)
	var ring := PackedVector2Array()
	for i in range(32):
		ring.append(project.call(Vector2.from_angle(i * TAU / 32.0) * 12))
	draw_colored_polygon(ring, Color("33263f"))
	ring.append(ring[0])
	draw_polyline(ring, Color("c3a0ef"), 1.4 * s, true)
	var bubble := PackedVector2Array()
	for vertex in [Vector2(-6, -5), Vector2(6, -5), Vector2(6, 3), Vector2(0, 3),
		Vector2(-4, 6), Vector2(-4, 3), Vector2(-6, 3), Vector2(-6, -5)]:
		bubble.append(project.call(vertex))
	draw_polyline(bubble, Color("dfc8ff"), 1.5 * s, true)
	var start: Vector2 = project.call(Vector2(-7, 7))
	var finish: Vector2 = project.call(Vector2(7, -7))
	draw_line(start, finish, Color("33263f"), 4 * s, true)
	draw_line(start, finish, Color("e4b4fc"), 2 * s, true)

func _poison(p: PackedVector2Array, s: float) -> void:
	var center := _point(p,0.22,0.71)
	draw_circle(center,10*s,Color("253b25"))
	var drop := PackedVector2Array([center+Vector2(0,-7)*s,center+Vector2(5,1)*s,center+Vector2(3,5)*s,center+Vector2(-3,5)*s,center+Vector2(-5,1)*s])
	draw_colored_polygon(drop,Color("a8db64"))
	for i in range(4):
		var phase := fmod(elapsed*0.48+i*0.25,1.0)
		var at := center+Vector2(sin(i*2.3+elapsed)*9,-10-phase*21)*s
		draw_circle(at,(1.5+i%2)*s,Color(0.65,0.88,0.32,(1-phase)*0.85),false,1.0*s,true)

func _regen(p: PackedVector2Array, s: float) -> void:
	var center := _point(p,0.78,0.71)
	var pulse := 0.75+sin(elapsed*2)*0.15
	draw_circle(center,10*s,Color("173e35"))
	draw_line(center-Vector2(5,0)*s,center+Vector2(5,0)*s,Color(0.5,1,0.78,pulse),3*s,true)
	draw_line(center-Vector2(0,5)*s,center+Vector2(0,5)*s,Color(0.5,1,0.78,pulse),3*s,true)

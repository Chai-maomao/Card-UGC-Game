extends "res://presentation/BattleTable3D.gd"

# Position within the reference viewport, followed by rotation around the table normal.
const REFERENCE_SIZE := Vector2(1280, 720)
const CARD_POSES := [
	[Vector3(0.72, 0.50, 4)],
	[Vector3(0.65, 0.49, -8), Vector3(0.79, 0.53, 6)],
	[Vector3(0.59, 0.54, -7), Vector3(0.71, 0.46, 0), Vector3(0.83, 0.53, 7)],
	[Vector3(0.64, 0.39, -10), Vector3(0.79, 0.42, 7), Vector3(0.63, 0.67, 5), Vector3(0.78, 0.69, -6)],
	[Vector3(0.59, 0.42, -9), Vector3(0.71, 0.36, 5), Vector3(0.83, 0.42, -4), Vector3(0.655, 0.68, 9), Vector3(0.775, 0.68, -7)],
]
const CARD_WIDTHS := [168.0, 150.0, 138.0, 132.0, 123.0]
const PROP_HEIGHT := -0.075

var display_slots: Array[Control] = []
var display_cards: Array = []
var _wheel: MeshInstance3D
var _dice: MeshInstance3D

func _ready() -> void:
	menu_mode = true
	super._ready()
	for socket in sockets: socket.hide()
	_wheel = _make_prop("TitleWheel", load("res://res/tabletop/title-wheel.png"), Color(0.83, 0.77, 0.67), -7.0)
	_dice = _make_prop("TitleDice", load("res://res/tabletop/title-dice.png"), Color(0.76, 0.70, 0.60), 4.0)
	for id in AppPreferences.get_value("title_card_ids"):
		for card in PlayerData.card_library:
			if card is CardData and card.card_id == id:
				display_cards.append(card)
				break
	if display_cards.is_empty():
		var library: Array = CardDatabase.beginner_deck()
		for index in [0,4,8]: display_cards.append(library[index])
	for i in range(display_cards.size()):
		var slot := Control.new()
		slot.visible = false
		add_child(slot)
		display_slots.append(slot)
	get_viewport().size_changed.connect(_layout_cards)
	_layout_cards()

func _layout_cards() -> void:
	var screen := get_viewport().get_visible_rect().size
	var factor := minf(screen.x / REFERENCE_SIZE.x, screen.y / REFERENCE_SIZE.y)
	if factor <= 0.0:
		return
	var count := display_cards.size()
	var poses: Array = CARD_POSES[count - 1]
	var width: float = CARD_WIDTHS[count - 1]
	var reference_area := REFERENCE_SIZE * factor
	var reference_origin := (screen - reference_area) * 0.5
	_place_prop(_wheel, reference_origin + Vector2(0.535, 0.76) * reference_area, 166.0 * factor, 0.88)
	_place_prop(_dice, reference_origin + Vector2(0.445, 0.705) * reference_area, 100.0 * factor)
	for i in range(count):
		var slot := display_slots[i]
		var pose: Vector3 = poses[i]
		slot.size = Vector2(width, width * 214.0 / 155.0) * factor
		slot.position = reference_origin + Vector2(pose.x, pose.y) * reference_area - slot.size * 0.5
		sync_slot(slot,i,display_cards[i],false)
		var card_root: Node3D = cards[i].root
		card_root.rotation_degrees.y = pose.z

func _make_prop(node_name: String, artwork: Texture2D, tint: Color, angle: float) -> MeshInstance3D:
	var prop := MeshInstance3D.new()
	prop.name = node_name
	prop.mesh = PlaneMesh.new()
	prop.rotation_degrees.y = angle
	prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink := ShaderMaterial.new()
	ink.shader = preload("res://presentation/TabletopProp.gdshader")
	ink.set_shader_parameter("artwork", artwork)
	ink.set_shader_parameter("tint", tint)
	prop.material_override = ink
	add_child(prop)
	return prop

func _place_prop(prop: MeshInstance3D, center: Vector2, projected_width: float, depth_scale := 1.0) -> void:
	var left := plane_point(center - Vector2(projected_width * 0.5, 0), PROP_HEIGHT)
	var right := plane_point(center + Vector2(projected_width * 0.5, 0), PROP_HEIGHT)
	(prop.mesh as PlaneMesh).size = Vector2(1.0, depth_scale) * left.distance_to(right)
	prop.position = plane_point(center, PROP_HEIGHT)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	camera.h_offset = sin(elapsed*0.17)*0.07

extends RefCounted
const Face = preload("res://presentation/TabletopCardFace.gd")
static func make(card: CardData, at: Vector2) -> Control:
	var holder := preload("res://presentation/TabletopDragMotion.gd").new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var foreground := CanvasLayer.new()
	foreground.name = "TabletopDragForeground"
	foreground.layer = 2
	holder.add_child(foreground)
	var shadow := Panel.new()
	shadow.position = -at+Vector2(7,10)
	shadow.size = Vector2(126,168)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0,0,0,0.45)
	style.set_corner_radius_all(3)
	shadow.add_theme_stylebox_override("panel",style)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground.add_child(shadow)
	var face := Face.new()
	face.position = -at
	face.size = Vector2(384,512)
	face.scale = Vector2.ONE*(126.0/384.0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground.add_child(face)
	face.bind(card,false)
	return holder

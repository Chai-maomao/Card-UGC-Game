extends RefCounted
const Face = preload("res://presentation/ClassicBattleCardFace.gd")
const CARD_SIZE := Vector2(126,168)

static func make(card: CardData, at: Vector2, portrait: ImageTexture = null) -> Control:
	var holder := preload("res://presentation/TabletopDragMotion.gd").new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var foreground := CanvasLayer.new()
	foreground.name = "TabletopDragForeground"
	foreground.layer = 2
	holder.add_child(foreground)
	var shadow := Panel.new()
	shadow.position = -at+Vector2(7,10)
	shadow.size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0,0,0,0.45)
	style.set_corner_radius_all(3)
	shadow.add_theme_stylebox_override("panel",style)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground.add_child(shadow)
	var face: Control
	if portrait != null:
		var image := TextureRect.new()
		image.texture = portrait
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.size = CARD_SIZE
		face = image
	else:
		var printed := Face.new()
		printed.size = Vector2(384,528)
		printed.scale = CARD_SIZE / printed.size
		printed.bind(card, false)
		face = printed
	face.position = -at
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground.add_child(face)
	return holder

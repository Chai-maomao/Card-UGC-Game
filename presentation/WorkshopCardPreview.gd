class_name WorkshopCardPreview
extends Control

const Face = preload("res://presentation/ClassicBattleCardFace.gd")
var _face: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(148,204)
	_face = Face.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.size = Vector2(384,528)
	add_child(_face)
	resized.connect(_fit)
	_fit()

func bind_preview(data: Dictionary) -> void:
	var card := CardData.new(str(data.get("name","卡包")),int(data.get("cost",0)),int(data.get("max_hp",1)),int(data.get("atk",0)),[])
	card.card_type = str(data.get("card_type","minion"))
	_face.bind(card,false)
	var encoded := str(data.get("cover",""))
	if not encoded.is_empty():
		var bytes := Marshalls.base64_to_raw(encoded)
		if bytes.size() <= 67500:
			var image := Image.new()
			if image.load_jpg_from_buffer(bytes) == OK:
				_face.art = ImageTexture.create_from_image(image)
				_face.queue_redraw()

func bind_card(card: CardData) -> void:
	_face.bind(card,false)

func _fit() -> void:
	if _face == null: return
	var factor := minf(size.x/384.0,size.y/528.0)
	_face.scale = Vector2.ONE*factor
	_face.position = (size-Vector2(384,528)*factor)*0.5

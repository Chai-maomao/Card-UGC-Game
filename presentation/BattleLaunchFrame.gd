extends Control

const RANKED_ART = preload("res://res/tabletop/launch/ranked-tournament.webp")
const QUICK_ART = preload("res://res/tabletop/launch/quick-play-v2.webp")
const ROOM_ART = preload("res://res/tabletop/launch/friend-room.webp")
const ORNAMENTS := {
	"ranked": preload("res://res/tabletop/launch/ornament-ranked.svg"),
	"random": preload("res://res/tabletop/launch/ornament-random.svg"),
	"room": preload("res://res/tabletop/launch/ornament-room.svg"),
	"party": preload("res://res/tabletop/launch/ornament-party.svg"),
	"practice": preload("res://res/tabletop/launch/ornament-practice.svg"),
}

var _artwork: Control
var _caption: VBoxContainer
var _heading: Label
var _ornament: TextureRect


func setup(title: String, description: String, mode: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ornament = TextureRect.new()
	_ornament.texture = ORNAMENTS.get(mode, ORNAMENTS["room"])
	_ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ornament.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ornament.self_modulate = Color("#886b42") if UITheme.Tokens.light_mode else Color("#c3a679")
	add_child(_ornament)
	_artwork = Control.new()
	_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artwork.clip_contents = true
	add_child(_artwork)

	var art := _texture(_mode_art(mode), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shading := Gradient.new()
	shading.offsets = PackedFloat32Array([0.0, 0.38, 0.70, 1.0])
	shading.colors = PackedColorArray([Color("19150f15"), Color("19150f06"), Color("181511ba"), Color("181511")])
	var veil := GradientTexture2D.new()
	veil.gradient = shading
	veil.fill_to = Vector2(0, 1)
	var shade := _texture(veil, TextureRect.STRETCH_SCALE)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artwork.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(Color.TRANSPARENT, Color("a990616e"), 1, 0))

	_caption = VBoxContainer.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_constant_override("separation", 10)
	_artwork.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_heading = Label.new()
	_heading.text = title
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_child(_heading)
	if not description.is_empty():
		var lead := Label.new()
		lead.text = description
		lead.set_meta("keyword_literal", true)
		lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_caption.add_child(lead)
		UITheme.apply_label(lead)
		lead.add_theme_color_override("font_color", Color("ddd1b8"))
	resized.connect(_layout)
	_layout()


static func columns(dimensions: Vector2) -> Array[Rect2]:
	var edge := clampf(dimensions.x * 0.035, 18, 58)
	var top := 84.0
	var area := Vector2(maxf(1.0, dimensions.x - edge * 2), maxf(1.0, dimensions.y - top - edge))
	if dimensions.x < 700:
		var art_height := clampf(area.y * 0.33, 118, 180)
		return [Rect2(Vector2(edge, top), Vector2(area.x, art_height)),
			Rect2(Vector2(edge, top + art_height + 16), Vector2(area.x, maxf(1, area.y - art_height - 16)))]
	var gap := clampf(area.x * 0.058, 26, 78)
	var rail_width := clampf((area.x - gap) * 0.43, 296, 500)
	var art_width := area.x - gap - rail_width
	return [Rect2(Vector2(edge, top), Vector2(art_width, area.y)),
		Rect2(Vector2(edge + art_width + gap, top + 18), Vector2(rail_width, area.y - 18))]


static func add_header_art(parent: Control, header: Control, mode: String) -> void:
	var backing := Control.new()
	backing.name = "BattlePreparationArtwork"
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.clip_contents = true
	parent.add_child(backing)
	parent.move_child(backing, 0)
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = _mode_art(mode)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backing.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.anchor_left = 0.38
	var gradient := Gradient.new()
	var surface := UITheme.Tokens.BG
	gradient.offsets = PackedFloat32Array([0.38, 0.66, 1.0])
	gradient.colors = PackedColorArray([surface, Color(surface, 0.88), Color(surface, 0.63)])
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	var veil := TextureRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.texture = fade
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backing.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var align := func():
		backing.global_position = header.global_position
		backing.size = header.size
	header.item_rect_changed.connect(align)
	align.call_deferred()


static func _mode_art(mode: String) -> Texture2D:
	match mode:
		"ranked": return RANKED_ART
		"random", "practice": return QUICK_ART
		_: return ROOM_ART


func place_form(form: Control) -> void:
	var bounds := columns(size)[1]
	form.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	form.position = bounds.position
	form.size = bounds.size


func bind_form(form: Control) -> void:
	resized.connect(place_form.bind(form))
	form.visibility_changed.connect(func(): visible = form.visible)
	place_form(form)


func _texture(texture: Texture2D, stretch: TextureRect.StretchMode) -> TextureRect:
	var layer := TextureRect.new()
	layer.texture = texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = stretch
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artwork.add_child(layer)
	return layer


func _layout() -> void:
	var bounds := columns(size)
	var art_bounds := bounds[0]
	var form_bounds := bounds[1]
	var ornament_size := minf(392.0, minf(form_bounds.size.x * 0.84, form_bounds.size.y * 0.72))
	_ornament.size = Vector2(ornament_size, ornament_size)
	_ornament.position = form_bounds.end - _ornament.size
	_artwork.position = art_bounds.position
	_artwork.size = art_bounds.size
	var inset := clampf(art_bounds.size.x * 0.075, 16, 46)
	_caption.offset_left = inset
	_caption.offset_right = -inset
	_caption.offset_bottom = -inset
	_caption.grow_vertical = GROW_DIRECTION_BEGIN
	UITheme.apply_title(_heading, clampi(roundi(art_bounds.size.x * 0.092), 28, 56))
	_heading.add_theme_color_override("font_color", Color("f3e6cb"))

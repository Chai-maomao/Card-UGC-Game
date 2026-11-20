extends Control
const CardArtwork = preload("res://CardArtwork.gd")

var card_view: Control
var illustration: TextureRect
var character_name: Label
var skill_name: Label
var card: CardData
var skill_mode := false
var portrait_mode := false
var travel := 0.0:
	set(value):
		travel = value
		if illustration != null:
			illustration.position.x = 8.0+(1.0-value)*-18.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta("suppress_hover_hint",true)
	card_view = preload("res://CardUI.tscn").instantiate()
	add_child(card_view)
	illustration = TextureRect.new()
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){vec4 c=texture(TEXTURE,UV); c.a*=smoothstep(0.0,0.06,UV.x)*smoothstep(0.0,0.06,1.0-UV.x)*smoothstep(0.0,0.06,1.0-UV.y); COLOR*=c;}"
	var material := ShaderMaterial.new()
	material.shader = shader
	illustration.material = material
	add_child(illustration)
	character_name = Label.new()
	character_name.set_meta("keyword_literal",true)
	UITheme.apply_label(character_name)
	add_child(character_name)
	skill_name = Label.new()
	UITheme.apply_title(skill_name,20)
	skill_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_name.max_lines_visible = 2
	skill_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(skill_name)
	resized.connect(_layout)
	_layout()

func bind(value: CardData, ability: String = "") -> void:
	card = value
	skill_mode = not ability.is_empty()
	card_view.set_card(value)
	card_view.set_battle_layout_preview(true)
	illustration.texture = CardArtwork.texture_for(value)
	portrait_mode = false
	character_name.text = value.card_name
	skill_name.text = ability
	card_view.show()
	illustration.hide()
	character_name.hide()
	skill_name.hide()
	for child in find_children("*","Control",true,false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		child.focus_mode = Control.FOCUS_NONE
	_layout()
	queue_redraw()

func _layout() -> void:
	if card_view == null: return
	var factor := size.x/200.0
	card_view.apply_ui_scale(size.x/120.0)
	card_view.position = Vector2((size.x-card_view.size.x)*0.5,(size.y-card_view.size.y)*0.5)
	illustration.position = Vector2(8,0)*factor
	illustration.size = Vector2(184,208)*factor
	character_name.position = Vector2(12,216)*factor
	character_name.size = Vector2(176,24)*factor
	character_name.add_theme_font_size_override("font_size",maxi(12,roundi(14*factor)))
	character_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	skill_name.position = Vector2(12,240)*factor
	skill_name.size = Vector2(176,40)*factor
	skill_name.add_theme_font_size_override("font_size",maxi(14,roundi(18*factor)))
	travel = travel
	queue_redraw()

func _draw() -> void:
	if not portrait_mode: return
	var factor := size.x/200.0
	draw_colored_polygon(PackedVector2Array([Vector2(0,38)*factor,Vector2(182,12)*factor,Vector2(200,233)*factor,Vector2(0,266)*factor]),Color(Color("122124"),0.82))
	draw_line(Vector2(12,212)*factor,Vector2(188,212)*factor,Color(UITheme.Tokens.BRASS,0.75),factor,true)

extends Button

# ============================================
# Draw/discard piles share their artwork, count and native button interaction.
# ============================================

signal card_discarded(card_data, drop_position: Vector2)

const DROP_SHADER := """shader_type canvas_item;
uniform float highlight = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0,0.82,0.43,1.0);
uniform bool outline_only = false;
varying vec4 tint;
void vertex(){ tint = COLOR; }
void fragment(){
	vec4 c = texture(TEXTURE,UV);
	float center = smoothstep(0.1,0.6,c.a);
	float outer = center;
	float inner = center;
	for(int i=0;i<16;i++){
		float angle = float(i)*6.2831853/16.0;
		float a = smoothstep(0.1,0.6,texture(TEXTURE,UV+vec2(cos(angle),sin(angle))*TEXTURE_PIXEL_SIZE*16.0).a);
		outer = max(outer,a);
		inner = min(inner,a);
	}
	float rim = (outer-inner)*highlight;
	if(outline_only){ COLOR = vec4(rim_color.rgb,rim*rim_color.a)*tint; }
	else {
		c.a = c.a < 0.01 ? 0.0 : c.a;
		float alpha = max(c.a,rim);
		COLOR = vec4(mix(c.rgb,rim_color.rgb,rim/max(alpha,0.00001)),alpha)*tint;
	}
}"""
var is_discard_pile := false
var artwork: TextureRect
var count_label: Label
var _caption: Label
var _counter: HBoxContainer
var _ui_scale := 1.0
var _count := 0
var _hovered := false
var _highlighted := false
var _highlight_tween: Tween

func _ready() -> void:
	UITheme.apply_button(self,"secondary",false)
	for state in ["normal","hover","pressed","hover_pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(func(): _hovered=true; _refresh_highlight())
	mouse_exited.connect(func(): _hovered=false; _refresh_highlight())
	focus_entered.connect(_refresh_highlight)
	focus_exited.connect(_refresh_highlight)
	var atlas := AtlasTexture.new()
	atlas.atlas = preload("res://res/ui/cardex-graveyard.png") if is_discard_pile else preload("res://res/ui/cardex-pile.png")
	# Exclude transparent padding while leaving the supplied image untouched.
	atlas.region = Rect2(112,233,990,809) if is_discard_pile else Rect2(188,154,864,918)
	artwork = TextureRect.new()
	artwork.name = "GraveyardArtwork"
	artwork.texture = atlas
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ink := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = DROP_SHADER
	ink.shader = shader
	ink.set_shader_parameter("highlight",0.0)
	artwork.material = ink
	add_child(artwork)
	_counter = HBoxContainer.new()
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_counter)
	_caption = Label.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_meta("keyword_literal", true)
	UITheme.apply_label(_caption, true)
	_counter.add_child(_caption)
	count_label = Label.new()
	count_label.name = "PileCount"
	count_label.set_meta("keyword_literal",true)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.apply_label(count_label)
	var numerals := FontVariation.new()
	numerals.base_font = UITheme.medium_font()
	numerals.opentype_features = {"tnum": 1}
	count_label.add_theme_font_override("font", numerals)
	count_label.add_theme_color_override("font_color", UITheme.Tokens.CONTRAST_INK if AppPreferences.get_value("high_contrast") else UITheme.COLOR_TEXT)
	_counter.add_child(count_label)
	AppPreferences.changed.connect(_on_preferences_changed)
	apply_ui_scale(_ui_scale)
	set_count(_count)
	set_process(false)


func _on_preferences_changed(key: String) -> void:
	if key in ["appearance", "high_contrast"]:
		_caption.add_theme_color_override("font_color", UITheme.Tokens.CONTRAST_INK if AppPreferences.get_value("high_contrast") else UITheme.COLOR_TEXT_MUTED)
		count_label.add_theme_color_override("font_color", UITheme.Tokens.CONTRAST_INK if AppPreferences.get_value("high_contrast") else UITheme.COLOR_TEXT)

func apply_ui_scale(value: float) -> void:
	_ui_scale = value
	custom_minimum_size = Vector2(140,154) * value
	if artwork == null or count_label == null: return
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.offset_top = 4 * value
	artwork.offset_bottom = -24 * value
	_counter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_counter.offset_top = -23 * value
	_counter.add_theme_constant_override("separation", maxi(3, roundi(4 * value)))
	var text_size := maxi(11, roundi(14 * value))
	_caption.add_theme_font_size_override("font_size", text_size)
	count_label.add_theme_font_size_override("font_size", text_size)
	count_label.custom_minimum_size.x = ceilf(count_label.get_theme_font("font").get_string_size("000", HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x)

func set_count(value: int) -> void:
	_count = value
	if count_label != null:
		_caption.text = Locale.t("battle.discard_caption" if is_discard_pile else "battle.deck_caption")
		count_label.text = str(value)

func create_reject_outline() -> Control:
	# Unavailable feedback follows the same silhouette, excluding the count label.
	var outline := TextureRect.new()
	outline.texture = artwork.texture
	outline.expand_mode = artwork.expand_mode
	outline.stretch_mode = artwork.stretch_mode
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.offset_top = artwork.offset_top
	outline.offset_bottom = artwork.offset_bottom
	var ink := artwork.material.duplicate() as ShaderMaterial
	ink.set_shader_parameter("highlight",1.0)
	ink.set_shader_parameter("outline_only",true)
	ink.set_shader_parameter("rim_color",Color("ed7772"))
	outline.material = ink
	return outline

func get_reject_motion_target() -> Control:
	return artwork

func _refresh_highlight() -> void:
	_set_highlight(not disabled and (_hovered or has_focus()))

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		set_process(true)
	elif what == NOTIFICATION_DRAG_END:
		set_process(false)
		_refresh_highlight()

func _process(_delta: float) -> void:
	var data: Variant = get_viewport().gui_get_drag_data()
	_set_highlight(not disabled and ((_can_drop_data(Vector2.ZERO,data) and get_global_rect().grow(12).has_point(get_global_mouse_position())) or _hovered or has_focus()))

func _set_highlight(enabled: bool) -> void:
	if artwork == null or _highlighted == enabled: return
	_highlighted = enabled
	if _highlight_tween != null and _highlight_tween.is_valid(): _highlight_tween.kill()
	_highlight_tween = create_tween()
	_highlight_tween.tween_method(func(value: float): artwork.material.set_shader_parameter("highlight",value), float(artwork.material.get_shader_parameter("highlight")), 1.0 if enabled else 0.0, 0.12)


func _can_drop_data(_position: Vector2, data) -> bool:
	if not is_discard_pile or typeof(data) != TYPE_DICTIONARY or not data.get("card_data") is CardData:
		return false
	return true


func _drop_data(position: Vector2, data):
	_set_highlight(false)
	var card_data: CardData = data["card_data"] as CardData
	emit_signal("card_discarded", card_data, get_global_transform() * position)
	# UI cleanup handled by Main after confirming the discard

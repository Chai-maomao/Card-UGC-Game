extends Button

const ART = preload("res://res/ui/cardex-enemy_card.png")
const INK = """shader_type canvas_item;
varying vec4 tint;
void vertex(){ tint=COLOR; }
void fragment(){
 vec4 paper=texture(TEXTURE,(vec2(428.,45.)+UV*vec2(680.,908.))/vec2(1536.,1024.));
 vec2 p=(UV-.5)*vec2(120.,160.);
 vec2 q=abs(p)-vec2(50.5,70.5);
 float d=length(max(q,vec2(0.)))+min(max(q.x,q.y),0.)-9.5;
 paper.a*=1.-smoothstep(-.6,.6,d);
 COLOR=paper*tint;
}"""
var rim: Panel

func _ready() -> void:
	text = ""
	set_meta("suppress_hover_hint",true)
	for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shadow.position = Vector2(3,5)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0,0,0,.34)
	shade.set_corner_radius_all(4)
	shadow.add_theme_stylebox_override("panel",shade)
	add_child(shadow)
	var artwork := TextureRect.new()
	artwork.name = "CardBackArtwork"
	artwork.texture = ART
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = INK
	var ink := ShaderMaterial.new()
	ink.shader = shader
	artwork.material = ink
	add_child(artwork)
	rim = Panel.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color.TRANSPARENT
	edge.set_border_width_all(2)
	edge.border_color = Color("e1c16b")
	edge.set_corner_radius_all(4)
	rim.add_theme_stylebox_override("panel",edge)
	add_child(rim)
	rim.hide()

extends MeshInstance3D

const EDGE_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform vec4 edge_color : source_color; uniform vec2 inner_ratio; void fragment(){vec2 p=abs(UV-vec2(0.5))*2.0; if(p.x<inner_ratio.x && p.y<inner_ratio.y){discard;} ALBEDO=edge_color.rgb;}"
var _last_dimensions := Vector3.ZERO
var _last_color := Color.TRANSPARENT

func _init() -> void:
	name = "TargetOutline"
	mesh = QuadMesh.new()
	rotation.x = -PI / 2.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = EDGE_SHADER
	var ink := ShaderMaterial.new()
	ink.shader = shader
	material_override = ink
	visible = false

func update_outline(dimensions: Vector3, color: Color) -> void:
	visible = color.a > 0.0
	if not visible or (dimensions == _last_dimensions and color == _last_color): return
	_last_dimensions = dimensions
	_last_color = color
	var padding := minf(dimensions.x, dimensions.z) * 0.025
	var outer := Vector2(dimensions.x, dimensions.z) + Vector2.ONE * padding * 2.0
	(mesh as QuadMesh).size = outer
	position.y = dimensions.y * 0.5 + 0.004
	material_override.set_shader_parameter("inner_ratio", Vector2(dimensions.x, dimensions.z) / outer)
	material_override.set_shader_parameter("edge_color", color)

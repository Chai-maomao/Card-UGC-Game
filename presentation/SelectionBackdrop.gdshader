shader_type canvas_item;
render_mode unshaded;

uniform sampler2D background : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec4 focus_rect = vec4(150.0, 200.0, 240.0, 300.0);
uniform float feather = 260.0;
uniform float far_tint = 0.38;

void fragment() {
	vec2 position = UV * view_size;
	vec2 edge_distance = max(focus_rect.xy - position, position - focus_rect.xy - focus_rect.zw);
	float focus = 1.0 - smoothstep(0.0, feather, length(max(edge_distance, vec2(0.0))));
	vec3 behind = textureLod(background, SCREEN_UV, mix(0.55, 4.4, focus)).rgb;
	COLOR = vec4(mix(behind, COLOR.rgb, mix(far_tint, 0.92, focus)), COLOR.a);
}

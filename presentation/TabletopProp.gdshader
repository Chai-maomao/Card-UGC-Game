shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 shadow_color : source_color = vec4(0.06, 0.04, 0.025, 1.0);

float soft_shadow(vec2 uv) {
	vec2 spread = vec2(0.026);
	float shape = 4.0 * texture(artwork, uv).a;
	shape += 2.0 * texture(artwork, uv + vec2(spread.x, 0.0)).a;
	shape += 2.0 * texture(artwork, uv - vec2(spread.x, 0.0)).a;
	shape += 2.0 * texture(artwork, uv + vec2(0.0, spread.y)).a;
	shape += 2.0 * texture(artwork, uv - vec2(0.0, spread.y)).a;
	shape += texture(artwork, uv + spread).a;
	shape += texture(artwork, uv - spread).a;
	shape += texture(artwork, uv + vec2(spread.x, -spread.y)).a;
	shape += texture(artwork, uv + vec2(-spread.x, spread.y)).a;
	return shape / 16.0;
}

void fragment() {
	vec4 art = texture(artwork, UV);
	float art_alpha = clamp((art.a - 0.012) / 0.988, 0.0, 1.0);
	// Keep a close contact edge and a broader falloff in the light direction.
	float contact = texture(artwork, UV - vec2(0.011, 0.018)).a * 0.40;
	float soft = soft_shadow(UV - vec2(0.028, 0.038)) * 0.46;
	float shadow_alpha = max(contact, soft) * (1.0 - art_alpha);
	float alpha = art_alpha + shadow_alpha;
	ALBEDO = (art.rgb * tint.rgb * art_alpha + shadow_color.rgb * shadow_alpha) / max(alpha, 0.001);
	ALPHA = alpha;
}

shader_type canvas_item;
uniform sampler2D hand_screen : hint_screen_texture, filter_linear;
uniform float lift_phase : hint_range(0.0,1.0) = 0.0;
varying vec4 tint;
void vertex(){ tint=COLOR; }
void fragment(){
 vec4 paper=texture(TEXTURE,UV)*tint;
 vec3 lit=textureLod(hand_screen,SCREEN_UV,0.0).rgb;
 float blend=.15*smoothstep(0.0,.25,lift_phase)+.70*smoothstep(.25,.85,lift_phase)+.15*smoothstep(.85,1.0,lift_phase);
 COLOR=vec4(mix(lit,paper.rgb*.96,blend),paper.a);
}

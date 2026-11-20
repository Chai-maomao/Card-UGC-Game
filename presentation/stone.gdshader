shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 stone_color : source_color = vec4(0.032,0.043,0.05,1.0);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 a=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(a),hash(a+vec2(1,0)),f.x),mix(hash(a+vec2(0,1)),hash(a+vec2(1,1)),f.x),f.y);}
void fragment(){
 float grain=noise(UV*1100.0);
 float cloud=noise(UV*32.0)*0.5+noise(UV*95.0)*0.25;
 // Bounded analytic warping keeps each vein continuous across the surface.
 // The sin-hash noise warp produced visible tile breaks in Forward+.
 float warp=sin(UV.y*12.0+sin(UV.x*5.0)*1.2)*2.0+sin(UV.y*27.0-UV.x*4.0)*0.3;
 float vein=pow(abs(sin(UV.x*29.0+warp)),65.0);
 ALBEDO=stone_color.rgb*(0.7+cloud*0.5+grain*0.1)+vec3(0.004,0.005,0.005)*vein;
 NORMAL_MAP=vec3(0.5+(grain-0.5)*0.055,0.5+(cloud-0.35)*0.04,1.0);
 NORMAL_MAP_DEPTH=0.16;
 ROUGHNESS=0.9+grain*0.08;
 METALLIC=0.0;
}

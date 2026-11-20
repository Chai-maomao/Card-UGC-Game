shader_type canvas_item;
uniform vec2 rect_size = vec2(80.0,16.0);
uniform float radius = 2.0;
uniform vec4 forecast_color : source_color = vec4(0.87,0.34,0.29,1.0);
void fragment() {
 vec2 p = UV * rect_size;
 float r = min(radius,min(rect_size.x,rect_size.y)*0.5);
 vec2 q = abs(p-rect_size*0.5)-(rect_size*0.5-vec2(r));
 float d = length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-r;
 float inside = 1.0-smoothstep(-0.5,0.5,d);
 float border = smoothstep(-1.5,-0.5,d);
 float stripe = 1.0-smoothstep(1.0,2.0,mod(p.x+p.y,7.0));
 COLOR = vec4(forecast_color.rgb,forecast_color.a*inside*max(border,stripe*0.8));
}

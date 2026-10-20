shader_type spatial;
// 版90：街灯の下の、地面の光の輪（光を足す。本物の光は使わない＝軽い）。night（0 夕方〜1 夜）で明るくなる。
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec3 lamp_color : source_color = vec3(1.0, 0.84, 0.6);
uniform float strength = 0.04;
uniform float strength_night = 0.3;
uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(0.0, 1.0, dot(d, d));
	ALBEDO = lamp_color * (a * a) * mix(strength, strength_night, night);
}

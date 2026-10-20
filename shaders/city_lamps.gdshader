shader_type spatial;
// 版90：渋谷のマップの街灯。頂点の色 a = 1：光る頭、a = 0：柱とうで（色だけ）。
// night（0 夕方〜1 夜）で、頭の光が強くなる。
render_mode cull_back;

uniform vec3 lamp_color : source_color = vec3(1.0, 0.84, 0.6);
uniform float glow = 0.4;
uniform float glow_night = 3.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	if (COLOR.a > 0.5) {
		ALBEDO = lamp_color * 0.9;
		EMISSION = lamp_color * mix(glow, glow_night, night);
		ROUGHNESS = 0.4;
	} else {
		ALBEDO = COLOR.rgb;
		METALLIC = 0.35;
		ROUGHNESS = 0.5;
	}
}

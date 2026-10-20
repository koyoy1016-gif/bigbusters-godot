shader_type spatial;
// 版89：渋谷のマップの看板（自作の絵：assets/maps/shibuya/signs.png）。
// 頂点の色の a = 1：絵を出す（中から光る看板）。a = 0：頂点の色だけ（わく・うら・金具）。
// night（0 夕方〜1 夜）で、光の強さが変わる（版90で覚醒とつなぐ）。
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float glow = 0.35;
uniform float glow_night = 1.1;
uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	if (COLOR.a > 0.5) {
		vec3 c = texture(atlas, UV).rgb;
		ALBEDO = c * 0.85;
		EMISSION = c * mix(glow, glow_night, night);
		ROUGHNESS = 0.45;
	} else {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = 0.6;
		METALLIC = 0.2;
	}
}

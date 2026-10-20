shader_type spatial;
// 版89：渋谷のマップの大画面（ゲームの自作の絵を、順に映す。絵は signs.png の下の段の 8 まい）。
// 頂点の色 r = 最初の絵の番号 / 8、g = ずらす時間（画面ごとにちがう）。
// hold_sec ごとに、fade_sec かけて次の絵へ（点めつしない。ゆっくり切りかえる）。
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float hold_sec = 6.0;
uniform float fade_sec = 0.6;
uniform float glow = 0.9;
uniform float glow_night = 1.5;
uniform float night : hint_range(0.0, 1.0) = 0.0;

vec2 frame_uv(float k, vec2 uv) {
	float fx = mod(k, 4.0);
	float fy = floor(k / 4.0);
	// 1 まい 128×64 ピクセル（512×512 の中の y=384〜511）。ふちは 1 ピクセル内がわ
	vec2 px = vec2(fx * 128.0, 384.0 + fy * 64.0) + vec2(1.0) + uv * vec2(126.0, 62.0);
	return px / 512.0;
}

void fragment() {
	float t = TIME / hold_sec + COLOR.g * 8.0;
	float k0 = mod(floor(t) + floor(COLOR.r * 8.0 + 0.5), 8.0);
	float k1 = mod(k0 + 1.0, 8.0);
	float a = smoothstep(1.0 - fade_sec / hold_sec, 1.0, fract(t));
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	vec3 c = mix(texture(atlas, frame_uv(k0, uv)).rgb, texture(atlas, frame_uv(k1, uv)).rgb, a);
	ALBEDO = c * 0.15;
	EMISSION = c * mix(glow, glow_night, night);
	ROUGHNESS = 0.3;
}

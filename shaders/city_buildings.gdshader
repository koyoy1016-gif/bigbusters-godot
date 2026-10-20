shader_type spatial;
// 版88：渋谷のマップの建物（PLATEAU の形）。色は頂点の色（写真の模様は使わない）。
// 壁（頂点の色の a = 1）には、計算で窓を描く：階ごと・列ごとのガラス、ところどころ明かりがつく（夕方）。屋根（a = 0）は色だけ。
// 窓の位置は、世界の位置と面の向きから決めるので、画像も UV もいらない（軽い）。
render_mode cull_back;

uniform float floor_m = 3.6;      // 1階ぶんの高さ
uniform float col_m = 2.2;        // 窓の横の間かく
uniform float lit = 0.32;         // 明かりのついている窓の割合
uniform float glow = 0.9;         // 明かりの強さ
uniform vec3 glass_color : source_color = vec3(0.16, 0.2, 0.27);
uniform vec3 light_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float fade_far = 380.0;   // ここより遠い窓は、うすくする（細かすぎてちらつくため）

varying vec3 wp;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 col = base;
	vec3 emit = vec3(0.0);
	if (COLOR.a > 0.5 && abs(wn.y) < 0.5) {
		vec2 t = normalize(vec2(-wn.z, wn.x));
		float u = dot(wp.xz, t) / col_m;
		float v = wp.y / floor_m;
		vec2 cell = floor(vec2(u, v));
		vec2 f = fract(vec2(u, v));
		// 窓の四角（少しぼかして、遠くでちらつかないように）
		float aa = 0.06;
		float wx = smoothstep(0.16 - aa, 0.16 + aa, f.x) * (1.0 - smoothstep(0.84 - aa, 0.84 + aa, f.x));
		float wy = smoothstep(0.28 - aa, 0.28 + aa, f.y) * (1.0 - smoothstep(0.82 - aa, 0.82 + aa, f.y));
		float dist = length(wp - CAMERA_POSITION_WORLD);
		float win = wx * wy * (1.0 - smoothstep(fade_far * 0.6, fade_far, dist)) * step(0.6, v);
		col = mix(base, glass_color, win * 0.75);
		float h = hash(cell + floor(wp.xz / 23.0) * 7.13);
		float on = step(1.0 - lit, h);
		emit = light_color * glow * win * on * (0.55 + 0.45 * hash(cell * 1.7));
	} else {
		// 屋根・設備：上から光が当たる面を、少しだけ明るく
		col = base * (0.92 + 0.08 * clamp(wn.y, 0.0, 1.0));
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = emit;
}

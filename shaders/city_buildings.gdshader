shader_type spatial;
// 版89：渋谷のマップの建物（PLATEAU の形）。色は頂点の色（写真の模様は使わない）。
// 頂点の色の a = 材質：0 屋根・0.25 金属（屋上の設備）・0.5 タイルの壁と窓・0.75 ガラスのカーテンウォール・1 横長の窓の帯とパネル。
// UV.x = 建物の足もとの高さ（1階の店を描く高さを決める）、UV.y = 建物ごとの乱数（明かりのつき方を変える）。
// 窓は、世界の位置と面の向きから計算で描くので、画像はいらない（軽い）。
// night（0 夕方〜1 夜）で、明かりのつく窓の数・強さ、1階の店の明かりが変わる（版90で覚醒とつなぐ）。
render_mode cull_back;

uniform float floor_m = 3.6;      // 1階ぶんの高さ
uniform float col_m = 2.2;        // 窓の横の間かく（タイルの壁）
uniform float lit = 0.32;         // 明かりのついている窓の割合（夕方）
uniform float lit_night = 0.62;   // 〃（夜）
uniform float glow = 0.9;         // 明かりの強さ（夕方）
uniform float glow_night = 1.5;   // 〃（夜）
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float store_h = 3.0;      // 1階の店のガラスの高さ（足もとから）
uniform float store_glow = 0.35;
uniform float store_glow_night = 1.2;
uniform vec3 glass_color : source_color = vec3(0.16, 0.2, 0.27);
uniform vec3 light_color : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 office_color : source_color = vec3(0.86, 0.93, 1.0);
uniform vec3 store_color : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 sky_top : source_color = vec3(0.23, 0.33, 0.56);
uniform vec3 sky_horizon : source_color = vec3(0.94, 0.7, 0.54);
uniform float fade_far = 380.0;   // ここより遠い窓は、うすくする（細かすぎてちらつくため）

varying vec3 wp;
varying vec3 wn;
varying vec2 bu;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

// 0〜1 の中で、a〜b の間だけ 1（ふちを少しぼかす）
float band(float f, float a, float b, float aa) {
	return smoothstep(a - aa, a + aa, f) * (1.0 - smoothstep(b - aa, b + aa, f));
}

// くり返しの模様（x：1 ますが 1 の座標）の a〜b を 1 に。遠くて ますが小さく見える時は、ちらつかないように平均（b - a）へ
float pulse(float x, float a, float b) {
	float fw = fwidth(x);
	float v = band(fract(x), a, b, clamp(fw, 0.02, 0.25));
	return mix(v, b - a, smoothstep(0.18, 0.45, fw));
}

// 遠くて ますが小さい時の、混ぜる割合（0 近い〜1 遠い）
float far_mix(vec2 x) {
	return smoothstep(0.18, 0.45, max(fwidth(x.x), fwidth(x.y)));
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bu = UV;
}

void fragment() {
	vec3 base = COLOR.rgb;
	int m = int(COLOR.a * 4.0 + 0.5);
	vec3 col = base;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(fade_far * 0.6, fade_far, dist);
	float lit_now = mix(lit, lit_night, night);
	float glow_now = mix(glow, glow_night, night);
	if (m >= 2 && abs(wn.y) < 0.5) {
		vec2 t = normalize(vec2(-wn.z, wn.x));
		float uu = dot(wp.xz, t);
		float hy = wp.y - bu.x;
		if (hy < store_h) {
			// 1階の店：大きなガラスと、中の明かり
			float g = pulse(uu / 2.6, 0.04, 0.96) * band(hy, 0.3, store_h - 0.2, 0.05);
			col = mix(base * 0.5, vec3(0.07, 0.07, 0.08), g);
			float sg = mix(store_glow, store_glow_night, night);
			emit = store_color * g * sg * (0.65 + 0.35 * hash(vec2(floor(uu / 2.6), bu.y * 91.0)));
			rough = mix(0.8, 0.2, g);
		} else if (m == 3) {
			// ガラスのカーテンウォール：空がうつる・細い金属のわく・明かりのついた階
			float mull = max(1.0 - pulse(uu / 1.6, 0.05, 0.95), 1.0 - pulse(hy / floor_m, 0.06, 0.94)) * near;
			vec3 vdir = normalize(wp - CAMERA_POSITION_WORLD);
			vec3 r = reflect(vdir, normalize(wn));
			vec3 skyc = mix(sky_horizon, sky_top, clamp(r.y * 1.4 + 0.15, 0.0, 1.0));
			float fres = 0.3 + 0.55 * pow(1.0 - max(dot(-vdir, normalize(wn)), 0.0), 3.0);
			vec3 glassc = mix(base, skyc * 0.85, fres);
			col = mix(glassc, vec3(0.72, 0.74, 0.77), mull * 0.6);
			rough = mix(0.12, 0.55, mull);
			vec2 cell = vec2(floor(uu / 4.8), floor(hy / floor_m));
			float on = mix(step(1.0 - lit_now * 0.8, hash(cell + bu.y * 37.0)), lit_now * 0.8, far_mix(vec2(uu / 4.8, hy / floor_m)));
			emit = office_color * glow_now * 0.5 * on * (1.0 - mull) * near;
		} else if (m == 4) {
			// 横長の窓の帯と、金属のパネル
			float win = pulse(hy / floor_m, 0.4, 0.86) * near;
			float mull = 1.0 - pulse(uu / 1.4, 0.06, 0.94);
			vec3 gl = mix(glass_color, sky_horizon * 0.45, 0.25);
			col = mix(base, mix(gl, base * 0.8, mull * 0.7), win);
			metal = 0.3 * (1.0 - win);
			rough = mix(0.5, 0.25, win);
			vec2 cell = vec2(floor(uu / 3.0), floor(hy / floor_m));
			float on = mix(step(1.0 - lit_now, hash(cell + bu.y * 53.0)), lit_now, far_mix(vec2(uu / 3.0, hy / floor_m)));
			emit = light_color * glow_now * 0.8 * win * (1.0 - mull) * on;
		} else {
			// タイル・コンクリートの壁に、四角い窓
			float u = uu / col_m;
			float v = hy / floor_m;
			vec2 cell = floor(vec2(u, v));
			float win = pulse(u, 0.16, 0.84) * pulse(v, 0.28, 0.82) * near;
			col = mix(base, glass_color, win * 0.8);
			float fm = far_mix(vec2(u, v));
			float on = mix(step(1.0 - lit_now, hash(cell + bu.y * 71.0)) * (0.55 + 0.45 * hash(cell * 1.7)), lit_now * 0.78, fm);
			emit = light_color * glow_now * win * on;
			rough = mix(0.85, 0.3, win);
		}
	} else if (m == 1) {
		// 屋上の設備：金属
		col = base * (0.9 + 0.1 * clamp(wn.y, 0.0, 1.0));
		metal = 0.45;
		rough = 0.45;
	} else {
		// 屋根：上から光が当たる面を、少しだけ明るく
		col = base * (0.92 + 0.08 * clamp(wn.y, 0.0, 1.0));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}

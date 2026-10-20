shader_type sky;
// 版90：渋谷のマップの空（夕方・夜）。3つの色のグラデーション（地平線 → 中 → 上）・太陽のまわりの光・雲。
// 色は scripts/stage/time_of_day.gd が、夕方と夜の間で混ぜて入れる（data/maps.json の time_of_day）。
// 星は入れない（細かい点は、カメラが動くとちらつくため）。

uniform vec3 top_color : source_color = vec3(0.15, 0.2, 0.42);
uniform vec3 mid_color : source_color = vec3(0.61, 0.33, 0.5);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.58, 0.35);
uniform vec3 ground_color : source_color = vec3(0.23, 0.18, 0.24);
uniform vec3 sun_dir = vec3(-0.94, 0.24, -0.25);  // 太陽のある向き
uniform vec3 sun_color : source_color = vec3(1.0, 0.69, 0.44);
uniform float sun_glow = 0.7;
uniform vec3 cloud_color : source_color = vec3(0.42, 0.33, 0.45);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.69, 0.53);
uniform float cloud_amount = 0.5;
uniform float energy = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col;
	if (d.y >= 0.0) {
		float h = sqrt(clamp(d.y, 0.0, 1.0));
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.42, h));
		col = mix(col, top_color, smoothstep(0.32, 0.92, h));
		float s = max(dot(d, normalize(sun_dir)), 0.0);
		float low = 1.0 - smoothstep(0.0, 0.55, d.y);
		col += sun_color * (pow(s, 6.0) * sun_glow * 0.6 + pow(s, 48.0) * sun_glow) * low;
		// 雲（横に長い、うすい雲）
		vec2 uv = d.xz / (d.y + 0.12);
		float c = fbm(uv * vec2(0.9, 2.2) + vec2(3.1, 7.7));
		c = smoothstep(0.62 - cloud_amount * 0.25, 0.9, c) * smoothstep(0.02, 0.16, d.y) * (1.0 - smoothstep(0.55, 0.9, d.y));
		vec3 cc = mix(cloud_color, cloud_lit, clamp(pow(s, 2.0) * 1.2, 0.0, 1.0));
		col = mix(col, cc, c * 0.8);
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.12, -d.y));
	}
	COLOR = col * energy;
}

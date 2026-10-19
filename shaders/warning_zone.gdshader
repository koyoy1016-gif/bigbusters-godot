// ボスの攻撃の予告（床に置く面）。版60。
// mode 0：丸（円・扇・輪）／mode 1：四角（帯）… オレンジの面＋明るい縁＋しま模様。中から（帯は後ろから）広がる線で「いつ当たるか」を見せる
// mode 2：巨大酒瓶ライドの道 … ピンクの帯＋進む向きの矢印（流れて動く）＋明るい縁
// 色は data/boss_attacks.json の zone_style。画像は使わない（計算だけで描く）
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 fill_color : source_color = vec4(1.0, 0.42, 0.16, 0.32);
uniform vec4 rim_color : source_color = vec4(1.0, 0.8, 0.62, 0.95);
uniform int mode = 0;
uniform int grow_axis = 0;  // 0：中心から外へ／1：後ろ（ボスの側）から前へ
uniform float progress = 0.0;  // 予告の進み 0〜1（1 で当たる）
uniform float inner = 0.0;  // 輪の内側の半径（丸のとき。半径1に対する割合）
uniform vec2 size = vec2(1.0, 1.0);  // 世界での大きさ。丸：x＝半径。四角・帯：x＝幅、y＝奥行き
uniform float dir = 1.0;  // ライドの進む向き（形の x の +／-）
uniform float active = 0.0;  // 1：いま当たっている
uniform float strength = 1.0;  // 全体のこさ（害のない予告はうすく）
uniform float stripe_width = 0.7;  // しま模様の太さ（メートル）
uniform float rim_width = 0.22;  // 縁の太さ（メートル）
uniform float arrow_spacing = 3.2;  // 矢印の間かく（メートル）
uniform float arrow_speed = 1.4;  // 矢印の流れる速さ（1秒に何個分）

varying vec3 lp;
varying vec3 wp;

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col;
	float a;
	if (mode == 2) {
		float across = abs(lp.z) * 2.0;  // 0：真ん中 → 1：帯のふち
		float along = lp.x * size.x * dir;  // 進む向きに、メートル
		float half_w = size.y * 0.5;
		// 「＞」の形：進む向きに、真ん中が先に出る
		float v = fract((along + across * half_w * 0.9) / arrow_spacing - TIME * arrow_speed);
		float arrow = step(v, 0.16) * step(across, 0.8);
		float edge = smoothstep(1.0 - rim_width * 2.0 / max(size.y, 0.1), 1.0, across);
		col = mix(fill_color.rgb, rim_color.rgb, max(arrow * 0.75, edge));
		a = fill_color.a + arrow * 0.3 + edge * (rim_color.a - fill_color.a);
		a *= mix(0.65, 1.0, progress);
	} else {
		float t;  // 0：広がりの始まり → 1：いちばん外
		float edge_dist;  // 縁までの距離（メートル）
		if (mode == 0) {
			float d = length(lp.xz);
			t = inner > 0.0 ? clamp((d - inner) / max(1.0 - inner, 0.01), 0.0, 1.0) : d;
			edge_dist = (1.0 - d) * size.x;
			if (inner > 0.0) {
				edge_dist = min(edge_dist, (d - inner) * size.x);
			}
		} else {
			vec2 q = abs(lp.xz) * 2.0;
			t = grow_axis == 1 ? clamp(lp.z + 0.5, 0.0, 1.0) : max(q.x, q.y);
			edge_dist = min((1.0 - q.x) * size.x, (1.0 - q.y) * size.y) * 0.5;
		}
		float stripe = step(0.5, fract((wp.x + wp.z) / stripe_width));
		float rim = 1.0 - smoothstep(rim_width * 0.6, rim_width, edge_dist);
		float filled = step(t, progress);
		float ring = (1.0 - smoothstep(0.0, 0.035, abs(t - progress))) * step(progress, 0.995);
		col = fill_color.rgb;
		a = fill_color.a * (0.6 + 0.4 * stripe) + filled * 0.22;
		col = mix(col, rim_color.rgb, max(rim, ring * 0.8));
		a = max(a, max(rim * rim_color.a, ring * 0.7));
		if (active > 0.5) {
			col = mix(col, vec3(1.0, 0.86, 0.62), 0.55);
			a = max(a, 0.78);
		}
	}
	ALBEDO = col;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}

shader_type spatial;
// 版79：アーマーのドーム・時間停止の球。半透明の色の膜：ふちが明るく、六角形の模様がゆっくり流れる。後ろの物が透けて見える
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform float alpha = 0.22;       // 真ん中の濃さ
uniform float rim_alpha = 0.75;   // ふちの濃さ
uniform float rim_power = 2.5;
uniform float hex_scale = 9.0;
uniform float hex_alpha = 0.18;
uniform float fade = 1.0;         // 出始め・消えぎわ（0〜1）
uniform float pulse = 0.0;        // 当たったときなどに光る（0〜1）

float hex_edge(vec2 p) {
	// 六角形の格子の、ふちまでの近さ（0＝ふち）
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - ndv, rim_power);
	vec2 uv = UV * vec2(hex_scale * 2.0, hex_scale) + vec2(TIME * 0.05, TIME * 0.03);
	float e = hex_edge(uv);
	float line = 1.0 - smoothstep(0.0, 0.06, e);
	float a = alpha + rim * rim_alpha + line * hex_alpha + pulse * 0.3;
	ALBEDO = mix(color.rgb, vec3(1.0), rim * 0.5 + line * 0.3 + pulse * 0.4);
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}

shader_type spatial;
// 版84：蘇生の範囲（倒れた所の床）。白いふち・うすい中・ななめのしま。
// 外側の緑の弧＝起こす進み（progress 0〜1）、内側の白い弧＝のこり時間（time_left 0〜1）。時間が少ないと点めつ（blink）。
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float progress = 0.0;
uniform float time_left = 1.0;
uniform float blink = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 0.10);
uniform vec4 prog_color : source_color = vec4(0.45, 1.0, 0.6, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5;
	// 白いふち
	float edge = smoothstep(0.90 - aa, 0.90, r) * (1.0 - smoothstep(0.985 - aa, 0.985, r));
	// うすい中と、ななめのしま（ゆっくり流れる）
	float inner = 1.0 - smoothstep(0.86 - aa, 0.86, r);
	float stripes = smoothstep(0.45, 0.5, fract((p.x + p.y) * 3.2 - TIME * 0.35)) * (1.0 - smoothstep(0.95, 1.0, fract((p.x + p.y) * 3.2 - TIME * 0.35)));
	float a_fill = inner * (fill_color.a + stripes * 0.16);
	// 角度（上から時計回りに 0〜1）
	float ang = atan(p.x, -p.y);
	float t = fract(ang / 6.2831853 + 1.0);
	// 進みの弧（外側・緑）
	float band1 = smoothstep(0.78 - aa, 0.78, r) * (1.0 - smoothstep(0.86 - aa, 0.86, r));
	float on1 = band1 * step(t, progress);
	// のこり時間の弧（内側・白）
	float band2 = smoothstep(0.70 - aa, 0.70, r) * (1.0 - smoothstep(0.74 - aa, 0.74, r));
	float on2 = band2 * step(t, time_left) * 0.7;
	vec3 col = mix(fill_color.rgb, line_color.rgb, max(edge, on2));
	float alpha = max(a_fill, max(edge * line_color.a, on2));
	col = mix(col, prog_color.rgb, on1);
	alpha = max(alpha, on1);
	alpha *= 1.0 - blink * 0.55 * (0.5 + 0.5 * sin(TIME * 12.0));
	ALBEDO = col;
	ALPHA = alpha;
}

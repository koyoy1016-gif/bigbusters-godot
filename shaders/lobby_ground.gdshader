shader_type spatial;
// 版81b：ロビーの広場の床。うすいタイルの線と、まんなか（キャラの所）がほんのり明るい。
uniform vec4 base_color : source_color = vec4(0.23, 0.21, 0.31, 1.0);
uniform vec4 line_color : source_color = vec4(0.36, 0.33, 0.48, 1.0);
uniform vec4 glow_color : source_color = vec4(0.55, 0.38, 0.30, 1.0);
uniform vec2 glow_center = vec2(0.0, -1.5);
uniform float tile = 0.5;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(wp.xz * tile) - 0.5);
	float l = 1.0 - smoothstep(0.0, 0.025, min(g.x, g.y));
	float d = length(wp.xz - glow_center);
	float c = exp(-d * d * 0.025);
	ALBEDO = mix(base_color.rgb, line_color.rgb, l * 0.55) + glow_color.rgb * c * 0.45;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}

shader_type spatial;
// 版81b：ロビーの街の窓の明かり。窓ごとに明るさがゆっくり変わり、ときどき消える（頂点の色が窓の色）。
render_mode unshaded, cull_disabled, fog_disabled;

varying vec3 wp;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cell = floor(wp * vec3(2.0, 1.6, 2.0));
	float h = hash(cell);
	float tw = 0.7 + 0.3 * sin(TIME * (0.5 + h * 1.6) + h * 40.0);
	float off = step(0.92, fract(h * 17.0 + floor(TIME * 0.06 + h * 5.0) * 0.37));
	ALBEDO = COLOR.rgb * mix(tw, 0.22, off);
}

shader_type spatial;
// 輪郭線：モデルを少しふくらませて、裏側だけ塗る（裏返した殻）。
render_mode cull_front, unshaded;
uniform vec4 line_color : source_color = vec4(0.05, 0.06, 0.12, 1.0);
uniform float width = 0.012;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = line_color.rgb;
}

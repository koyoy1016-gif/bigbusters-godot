extends CanvasLayer
## 重さを画面に出す（実機で測るため）。URL に ?perf=1 を付けたときだけ出す（game_flow.gd が付ける）。
## 1秒ごとに：平均FPS、いちばん長かった1コマ（ミリ秒。引っかかりが分かる）、描画の回数、3Dを描いている画素の大きさ、画質。
## 版100：画像のメモリ（MB。文字の絵・マップの画像など。Godot が数えている分）と、ゲームのメモリ（数えられる時だけ。
## 公開している書き出し（release）では、Godot はメモリを数えないので出ない）も出す（実機で、戦いのあとに増えたままかを見るため）

var label: Label
var frames := 0
var elapsed := 0.0
var worst := 0.0
var quality_name := ""
var last_text := ""


static func build_text(fps: float, worst_ms: float, draws: int, res: Vector2i, quality: String, tex_mb: float = -1.0, mem_mb: float = 0.0) -> String:
	var t := "FPS %d  さいだい %d ms\nびょうが %d かい  3D %dx%d  %s" % [roundi(fps), roundi(worst_ms), draws, res.x, res.y, quality]
	if tex_mb >= 0.0:
		t += "\nがぞう %d MB" % roundi(tex_mb)
		if mem_mb > 0.0:
			t += "  メモリ %d MB" % roundi(mem_mb)
	return t


func _ready() -> void:
	layer = 100
	label = Label.new()
	label.position = Vector2(8, 8)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)


func _process(delta: float) -> void:
	frames += 1
	elapsed += delta
	worst = maxf(worst, delta)
	if elapsed < 1.0:
		return
	var vp := get_viewport()
	var px := Vector2i.ZERO
	if vp is Window:
		px = Vector2i(Vector2((vp as Window).size) * vp.scaling_3d_scale)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	last_text = build_text(frames / elapsed, worst * 1000.0, draws, px, quality_name, tex, mem)
	label.text = last_text
	frames = 0
	elapsed = 0.0
	worst = 0.0

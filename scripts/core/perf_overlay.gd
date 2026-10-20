extends CanvasLayer
## 重さを画面に出す（実機で測るため）。URL に ?perf=1 を付けたときだけ出す（game_flow.gd が付ける）。
## 1秒ごとに：平均FPS、いちばん長かった1コマ（ミリ秒。引っかかりが分かる）、描画の回数、3Dを描いている画素の大きさ、画質。
## 版100：画像のメモリ（MB。文字の絵・マップの画像など。Godot が数えている分）と、ゲームのメモリ（数えられる時だけ。
## 公開している書き出し（release）では、Godot はメモリを数えないので出ない）も出す（実機で、戦いのあとに増えたままかを見るため）
## 版101：カクつきの原因を分けるために、
##   おそい：その1秒で、1コマが slow_ms（25 ms＝60コマ/秒の1.5コマ分）より長かった回数（カクつきの回数）
##   しょり：1コマの、スクリプトと動きの計算などの CPU の時間（平均。Godot の TIME_PROCESS）
##   びょうがCPU：1コマの、絵を描く命令を作って送る CPU の時間（平均。描く前の準備＋画面を描く命令）
##   この2つの合計が 16 ms に近ければ CPU が重い。1コマ（1000/FPS）よりずっと小さければ、GPU（絵を描く部品）の方が重い見こみ

var label: Label
var frames := 0
var elapsed := 0.0
var worst := 0.0
var quality_name := ""
var last_text := ""
var slow := 0  ## 版101：おそいコマの数（この1秒）
var cpu_sum := 0.0  ## 版101：しょり（秒）の合計
var render_sum := 0.0  ## 版101：びょうがCPU（ミリ秒）の合計
const SLOW_MS := 25.0


static func build_text(fps: float, worst_ms: float, draws: int, res: Vector2i, quality: String, tex_mb: float = -1.0, mem_mb: float = 0.0, slow_n: int = -1, cpu_ms: float = -1.0, render_ms: float = -1.0) -> String:
	var t := "FPS %d  さいだい %d ms" % [roundi(fps), roundi(worst_ms)]
	if slow_n >= 0:
		t += "  おそい %d" % slow_n
	t += "\nびょうが %d かい  3D %dx%d  %s" % [draws, res.x, res.y, quality]
	if cpu_ms >= 0.0 and render_ms >= 0.0:
		t += "\nしょり %.1f ms  びょうがCPU %.1f ms" % [cpu_ms, render_ms]
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
	var bg := StyleBoxFlat.new()  # 版101：うしろの体力の表示と重なっても読めるように、うすい黒の下じき
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_content_margin_all(4.0)
	label.add_theme_stylebox_override("normal", bg)
	add_child(label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	frames += 1
	elapsed += delta
	worst = maxf(worst, delta)
	if delta * 1000.0 > SLOW_MS:
		slow += 1
	cpu_sum += Performance.get_monitor(Performance.TIME_PROCESS)
	render_sum += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
	if elapsed < 1.0:
		return
	var vp := get_viewport()
	var px := Vector2i.ZERO
	if vp is Window:
		px = Vector2i(Vector2((vp as Window).size) * vp.scaling_3d_scale)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	last_text = build_text(frames / elapsed, worst * 1000.0, draws, px, quality_name, tex, mem, slow, cpu_sum * 1000.0 / frames, render_sum / frames)
	label.text = last_text
	frames = 0
	elapsed = 0.0
	worst = 0.0
	slow = 0
	cpu_sum = 0.0
	render_sum = 0.0

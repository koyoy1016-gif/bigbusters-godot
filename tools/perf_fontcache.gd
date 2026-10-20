extends SceneTree
## 版99：文字の大きさごとに作られる「文字の絵の置き場（フォントのキャッシュ）」が、戦いでどれだけ増えるかを測る（測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_fontcache.gd -- 出力.json
## ロビー → 戦い（ダメージの数字を 3 種類・必殺技の名前を、決まった間隔で出し続ける）→ ロビー。
## それぞれで、フォントの大きさの数・文字の絵（テクスチャ）の数・メモリ（static）・画像のメモリを記録する。
## この環境の描画はとても遅い（1コマ 0.3 秒ほど）ので、戦いは止めて、数字と名前の動きだけを 1コマ＝1/60 秒で進める
## （スマホの 60 コマ/秒と同じ細かさで、はね上がりの大きさが変わる）。

const SCENE := "res://scenes/game_flow.tscn"
const FONT := "res://assets/fonts/NotoSansJP-Regular-subset.ttf"
const FRAMES := 600


func snap(tag: String, f: FontFile) -> Dictionary:
	var sizes := 0
	var tex := 0
	for c in f.get_cache_count():
		var lst: Array = f.get_size_cache_list(c)
		sizes += lst.size()
		for sz in lst:
			tex += f.get_texture_count(c, sz)
	var d := {
		"font_sizes": sizes,
		"font_textures": tex,
		"mem_static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"texture_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
	}
	print("FONT ", tag, " ", d)
	return d


func _initialize() -> void:
	var out_path := OS.get_cmdline_user_args()[0]
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 60:
		await process_frame
	var f := load(FONT) as FontFile
	var report := {}
	report["lobby"] = snap("lobby", f)
	flow.play()
	for i in 5:
		await process_frame
	var b: Node = flow.battle
	b.start_round()
	for i in 4:
		await process_frame
	b.set_process(false)  # 戦いは止める（数字と名前は下で決まった間隔で出し、1/60 秒ずつ進める）
	var dn: RefCounted = b.damage_numbers()
	var w: Vector3 = b.boss.global_position + Vector3(0.0, 4.0, 0.0)
	var kinds := ["normal", "strong", "critical"]
	var amounts := [7, 23, 158, 1240, 86, 412]
	for i in FRAMES:
		if i % 6 == 0:
			dn.add(float(amounts[(i / 6) % amounts.size()]), w, str(kinds[(i / 6) % kinds.size()]))
		if i % 90 == 0:
			b.hud._show_banner("ためし の わざ", "", 1.2)
		dn.update(1.0 / 60.0)
		b.banner["left"] = maxf(0.0, float(b.banner["left"]) - 1.0 / 60.0)
		b.overlay.queue_redraw()
		await process_frame
	report["in_battle"] = snap("in_battle", f)
	flow.goto("lobby")
	for i in 60:
		await process_frame
	report["after_battle"] = snap("after_battle", f)
	var fo := FileAccess.open(out_path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, "  "))
	fo.close()
	print("FONTCACHE ", out_path)
	quit(0)

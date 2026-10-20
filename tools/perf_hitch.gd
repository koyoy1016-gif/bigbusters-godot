extends SceneTree
## 版96：戦いの「引っかかり」（1コマだけ長い）を見つける（測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_hitch.gd -- 出力.json [コマ数] [くり返し]
## 戦いを2回する（同じ場面で）。1回目だけ長いコマ＝はじめて使う物の準備（シェーダーを作る・形を読む）。2回目も長い＝毎回の重さ。
## 長いコマ（そのくり返しのまん中の3倍以上）が出た時の、ボスの攻撃・ノードの数・覚醒かどうかを記録する。

const SCENE := "res://scenes/game_flow.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var n := int(args[1]) if args.size() > 1 else 600
	var reps := int(args[2]) if args.size() > 2 else 2
	OS.low_processor_usage_mode = false
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 60:
		await process_frame
	var report := {"runs": []}
	for r in reps:
		var t0 := Time.get_ticks_usec()
		flow.play()
		await process_frame
		var enter_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var b: Node = flow.battle
		for i in 3:
			await process_frame
		b.start_round()
		var frames := []
		var last := Time.get_ticks_usec()
		var forced_awake := false
		for i in n:
			# 半分のところで、覚醒（第2形態）にする（夜・覚醒の攻撃の、はじめての準備を見る）
			if i == n / 2 and not forced_awake:
				forced_awake = true
				b.phase.on_total(b.phase.max1 + 1.0)
			await process_frame
			var t := Time.get_ticks_usec()
			var cur: Dictionary = b.ai.current() if b.ai != null else {}
			frames.append({"i": i, "ms": (t - last) / 1000.0, "attack": str(cur.get("kind", "")), "phase": str(b.phase.phase), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
			last = t
		var ms := []
		for f in frames:
			ms.append(float(f["ms"]))
		ms.sort()
		var med := float(ms[ms.size() / 2])
		var spikes := []
		for f in frames:
			if float(f["ms"]) > med * 3.0 and float(f["ms"]) > med + 40.0:
				spikes.append(f)
		report["runs"].append({"enter_ms": enter_ms, "median_ms": med, "p99_ms": float(ms[int(ms.size() * 0.99)]), "max_ms": float(ms[-1]), "spikes": spikes})
		flow.goto("lobby")
		for i in 30:
			await process_frame
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("HITCH ", out_path)
	quit(0)

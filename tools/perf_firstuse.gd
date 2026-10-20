extends SceneTree
## 版99：はじめて使う時だけの引っかかり（シェーダー作りなど）を、ボスの攻撃・覚醒ごとに調べる（測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_firstuse.gd -- 出力.json
## 戦いを2回する。それぞれで、ボスの攻撃を1つずつ出し（force_attack）、その間のいちばん長いコマを記録。最後に覚醒（夜）。
## 1回目だけ長い物＝はじめての準備がいる物。

const SCENE := "res://scenes/game_flow.tscn"
const FRAMES := 45


func run_once(b: Node, kinds: Array) -> Dictionary:
	var out := {}
	var last := Time.get_ticks_usec()
	for i in 10:
		await process_frame
	for kind in kinds:
		b.force_attack(str(kind))
		var worst := 0.0
		last = Time.get_ticks_usec()
		for i in FRAMES:
			await process_frame
			var t := Time.get_ticks_usec()
			worst = maxf(worst, (t - last) / 1000.0)
			last = t
		out[str(kind)] = snappedf(worst, 0.1)
	# 覚醒（倒れて起きる・夜・覚醒の形）
	b.phase.on_total(b.phase.max1 + 1.0)
	var worst2 := 0.0
	last = Time.get_ticks_usec()
	for i in 150:
		await process_frame
		var t := Time.get_ticks_usec()
		worst2 = maxf(worst2, (t - last) / 1000.0)
		last = t
	out["awake"] = snappedf(worst2, 0.1)
	return out


func _initialize() -> void:
	var out_path := OS.get_cmdline_user_args()[0]
	OS.low_processor_usage_mode = false
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 30:
		await process_frame
	var report := {}
	for r in 2:
		var t0 := Time.get_ticks_usec()
		flow.play()
		await process_frame
		var enter := (Time.get_ticks_usec() - t0) / 1000.0
		for i in 3:
			await process_frame
		var b: Node = flow.battle
		var first := (Time.get_ticks_usec() - t0) / 1000.0
		b.start_round()
		b.skill_time_stop_left = 0.0
		var kinds: Array = (b.attacks_cfg["kinds"] as Dictionary).keys()
		var res := await run_once(b, kinds)
		res["_enter_ms"] = snappedf(enter, 0.1)
		res["_first_frames_ms"] = snappedf(first, 0.1)
		var ms := []
		for k in res:
			if not str(k).begins_with("_"):
				ms.append(float(res[k]))
		ms.sort()
		res["_median_worst"] = ms[ms.size() / 2]
		report["run%d" % r] = res
		flow.goto("lobby")
		for i in 20:
			await process_frame
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("FIRST ", out_path)
	quit(0)

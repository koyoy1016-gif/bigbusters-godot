extends SceneTree
## 版97：戦いの描く重さを、決まった場所で比べる（直す前と後を、同じ条件で測るため。測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_battle_fixed.gd -- 出力.json [画質]
## 自分を3つの場所（まん中・手前の左はし・奥の右はし）に置き、AI とボスを止めて、それぞれ 30 コマの
## 1コマの時間（まん中の値）・描画の回数・三角形の数を測る。夕方（ふだん）と夜（覚醒）の両方。
## 版98：毎回同じ場面になるように、戦いが始まってすぐ止め、AI の味方を決まった場所に置く。
##   3つめの引数に ab を入れると、街灯の光の輪を「出す／隠す」の両方を、同じ場面で測る（版98 の確かめ）

const SCENE := "res://scenes/game_flow.tscn"


func mon(m: int) -> float:
	return float(Performance.get_monitor(m))


func measure() -> Dictionary:
	for i in 8:
		await process_frame
	var ft := []
	var dc := 0.0
	var pr := 0.0
	var last := Time.get_ticks_usec()
	for i in 30:
		await process_frame
		var t := Time.get_ticks_usec()
		ft.append((t - last) / 1000.0)
		last = t
		dc += mon(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		pr += mon(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	ft.sort()
	return {"frame_ms": snappedf(float(ft[ft.size() / 2]), 0.1), "draw_calls": roundi(dc / 30.0), "primitives": roundi(pr / 30.0)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var qname := args[1] if args.size() > 1 else "low"
	OS.low_processor_usage_mode = false
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.quality_name = qname
	flow._apply_quality()
	flow.goto("lobby")
	for i in 30:
		await process_frame
	flow.play()
	for i in 5:
		await process_frame
	var b: Node = flow.battle
	b.start_round()
	for i in 4:
		await process_frame
	# 版98：毎回同じ場面にする（はじまってすぐ止める・AI の味方は決まった場所）
	b.ai_enabled = false
	b.set_process(false)
	var k := 0
	for slot in b.other_target.keys():
		var pos := Vector2(0.35 + 0.15 * k, 0.62)
		b.other_target[slot] = pos
		b.other_pos[slot] = pos
		k += 1
	b._update_others(0.0)
	var half := float(b.config["bounds"])
	var report := {"quality": qname}
	for tod in ["evening", "night"]:
		if b.get("tod") != null and b.tod.is_ready():
			b.tod.snap(tod == "night")
		for spot in [["center", Vector3(0, 0, 0)], ["near_left", Vector3(-half, 0, half)], ["far_right", Vector3(half, 0, -half)]]:
			b.player.position = spot[1]
			b.camera_target = Vector3(spot[1].x, 0, spot[1].z) * float(b.config["camera_follow"])
			b.camera_vel = Vector3.ZERO
			b.camera_update(0.0)
			report[tod + ":" + str(spot[0])] = await measure()
			if args.size() > 2 and args[2] == "ab":
				var pools: Array = b.map_root.get_meta("light_pools", [])
				for pm in pools:
					(pm as Node3D).visible = not (pm as Node3D).visible
				report[tod + ":" + str(spot[0]) + ":pools_toggled"] = await measure()
				for pm in pools:
					(pm as Node3D).visible = not (pm as Node3D).visible
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("FIXED ", out_path)
	quit(0)

extends SceneTree
## 版94：重さを測る（画面の流れごと：ロビー・戦い・行き来のくり返し）。見た目・動きは変えない（測るだけ）。
## 戦いだけの部品の数え方は tools/perf_probe.gd（版79）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_flow.gd -- 出力.json [画質 low/high] [測るコマ数]
## 測るもの（コマごと）：1コマの時間（壁の時計）・処理の時間（Performance.TIME_PROCESS）・描画の回数・三角形の数・描いた物の数。
##   戦いでは、_process の中の仕事ごとの時間も測る（戦いの _process を止めて、同じ順番で呼び、前後で時計を見る）。
##   最後に：メモリ・物の数・ノードの数・画像とバッファのメモリ。ロビー⇔戦いを3回くり返した時の増え方（もれ）。
## 注意：xvfb の llvmpipe は、CPU で絵を描く（スマホの GPU とはちがう）。1コマの時間は「比べる」ためだけに使う。
##   描画の回数・三角形の数・処理の時間（スクリプト）は、スマホでも同じ傾向になる。

const SCENE := "res://scenes/game_flow.tscn"
var frames_n := 240
var mark := {"start": 0, "end": 0}  ## 1コマの処理のはじめ・おわりの時刻（すべての _process をはさむ）


## すべての _process（スクリプト・動きの再生など）を、前と後ろではさむ印。その間の時間＝1コマの処理の時間（CPU）
class Bracket extends Node:
	var mark: Dictionary
	var key: String
	func _process(_d: float) -> void:
		mark[key] = Time.get_ticks_usec()


func now_us() -> int:
	return Time.get_ticks_usec()


func mon(m: int) -> float:
	return float(Performance.get_monitor(m))


func stats(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {}
	var s := arr.duplicate()
	s.sort()
	var tot := 0.0
	for v in s:
		tot += float(v)
	return {"avg": snappedf(tot / s.size(), 0.001), "p50": snappedf(float(s[s.size() / 2]), 0.001), "p95": snappedf(float(s[mini(s.size() - 1, int(s.size() * 0.95))]), 0.001), "max": snappedf(float(s[-1]), 0.001)}


## frames コマのあいだ、毎コマの数を集める
func sample(n: int) -> Dictionary:
	var ft := []
	var tp := []
	var dc := []
	var prim := []
	var objs := []
	var busy := []
	var last := now_us()
	for i in n:
		await process_frame
		var t := now_us()
		ft.append((t - last) / 1000.0)
		last = t
		tp.append(mon(Performance.TIME_PROCESS) * 1000.0)
		busy.append(maxf(0.0, (int(mark["end"]) - int(mark["start"])) / 1000.0))
		dc.append(mon(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prim.append(mon(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(mon(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	return {"frame_ms": stats(ft), "process_ms": stats(tp), "cpu_process_ms": stats(busy), "draw_calls": stats(dc), "primitives": stats(prim), "objects": stats(objs)}


func memory() -> Dictionary:
	return {"static_mb": snappedf(mon(Performance.MEMORY_STATIC) / 1048576.0, 0.1), "objects": int(mon(Performance.OBJECT_COUNT)),
			"nodes": int(mon(Performance.OBJECT_NODE_COUNT)), "resources": int(mon(Performance.OBJECT_RESOURCE_COUNT)),
			"orphan_nodes": int(mon(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"video_mb": snappedf(mon(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"texture_mb": snappedf(mon(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
			"buffer_mb": snappedf(mon(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1)}


## 戦いの _process（stick_prototype.gd）と同じ順番で呼び、仕事ごとの時間（マイクロ秒）を集める
func battle_breakdown(s: Node, n: int) -> Dictionary:
	var parts := {}
	var add := func(k: String, us: int) -> void:
		if not parts.has(k):
			parts[k] = []
		(parts[k] as Array).append(us / 1000.0)
	s.set_process(false)
	for i in n:
		await process_frame
		var delta := 1.0 / 60.0
		var t := now_us()
		s._hitstop_update()
		s.kb_guard_left = maxf(0.0, s.kb_guard_left - delta)
		var move: Vector2 = Vector2.ZERO if (s.downed or s.stun_left > 0.0) else s.stick_vec * s.actions.move_scale()
		s.player.position = s.StickMath.step_position(s.player.position, move, s.role_value("move_speed") * s.skills.speed_mult(s._my_slot()), delta, float(s.config["bounds"]))
		s.hit_flash = maxf(0.0, s.hit_flash - delta)
		s.damage_numbers().update(delta)
		add.call("misc_top", now_us() - t)
		t = now_us()
		s.net_update(delta, Time.get_ticks_msec())
		add.call("net_update", now_us() - t)
		t = now_us()
		s.combat_update(delta)
		add.call("combat_update", now_us() - t)
		t = now_us()
		s._time_of_day_update(delta)
		add.call("time_of_day", now_us() - t)
		t = now_us()
		if s.boss_model != null and s.boss.visible:
			s._pose_boss(delta)
		add.call("pose_boss", now_us() - t)
		t = now_us()
		s._record_highlight(delta)
		add.call("record_highlight", now_us() - t)
		t = now_us()
		s._actions_update(delta)
		add.call("actions_update", now_us() - t)
		t = now_us()
		s._update_character(delta)
		add.call("update_character", now_us() - t)
		t = now_us()
		var crowd_t: float = maxf(0.0, (s.server_now_ms() - s.round_start_ms) / 1000.0) if s.round_active() else 0.0
		s.crowd_state.refresh(crowd_t)
		add.call("crowd_refresh", now_us() - t)
		t = now_us()
		s.sub_crowd.update_at(crowd_t, s.crowd_state)
		add.call("sub_crowd", now_us() - t)
		t = now_us()
		s._touch_update(delta)
		s.player_material.albedo_color = s._player_color()
		s.player_marker_material.albedo_color = s._slot_color(str(s.net_state.get("slot", "")))
		s.apply_orientation(Vector2(s.get_window().size) if s.get_window() != null else Vector2(16, 9))
		add.call("misc_bottom", now_us() - t)
		t = now_us()
		s.camera_update(delta)
		add.call("camera", now_us() - t)
		s.overlay.queue_redraw()
	var out := {}
	for k in parts:
		out[k] = stats(parts[k])
	s.set_process(true)
	return out


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "user://perf.json"
	var qname := args[1] if args.size() > 1 else "low"
	frames_n = int(args[2]) if args.size() > 2 else 240
	OS.low_processor_usage_mode = false
	for k in ["start", "end"]:
		var br := Bracket.new()
		br.mark = mark
		br.key = k
		br.process_priority = -100000 if k == "start" else 100000
		br.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child.call_deferred(br)
	var report := {"quality": qname, "frames": frames_n, "window": str(DisplayServer.window_get_size()), "renderer": RenderingServer.get_video_adapter_name()}
	# ---- はじめ：画面の流れを作ってロビーへ ----
	var t0 := now_us()
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	report["flow_ready_ms"] = (now_us() - t0) / 1000.0
	flow.quality_name = qname
	flow._apply_quality()
	var t1 := now_us()
	flow.goto("lobby")
	report["lobby_goto_ms"] = (now_us() - t1) / 1000.0
	await process_frame
	report["lobby_first_frame_ms"] = (now_us() - t1) / 1000.0
	for i in 90:
		await process_frame  # 顔の絵・はじめの動きが落ちつくまで
	report["lobby_mem_after_enter"] = memory()
	report["lobby"] = await sample(frames_n)
	# ロビーの3Dの仕事（lobby_stage.step）
	var st: Node = flow.lobby_stage
	if st != null:
		st.set_process(false)
		var arr := []
		for i in 120:
			await process_frame
			var t := now_us()
			st.step(1.0 / 60.0)
			arr.append((now_us() - t) / 1000.0)
		st.set_process(true)
		report["lobby_stage_step_ms"] = stats(arr)
	var arr2 := []
	for i in 120:
		await process_frame
		var t := now_us()
		flow.lobby_ui.tick(1.0 / 60.0)
		arr2.append((now_us() - t) / 1000.0)
	report["lobby_ui_tick_ms"] = stats(arr2)

	# ---- 戦い ----
	var cycles := []
	for c in 3:
		var tb := now_us()
		flow.play()
		var play_ms := (now_us() - tb) / 1000.0
		await process_frame
		var first_ms := (now_us() - tb) / 1000.0
		var b: Node = flow.battle
		for i in 5:
			await process_frame
		if b != null and not b.round_active():
			b.start_round()
		for i in 120:
			await process_frame
		var cyc := {"play_ms": play_ms, "first_frame_ms": first_ms}
		if c == 0:
			report["battle_mem"] = memory()
			report["battle"] = await sample(frames_n)
			report["battle_breakdown_ms"] = await battle_breakdown(b, frames_n)
			# 体力の表示・ボタンの描画（_draw_overlay）の時間：同じ関数を、描く合図の中で測る
			var dsum := []
			var hook := func() -> void:
				var t := now_us()
				b.hud._draw_overlay()
				dsum.append((now_us() - t) / 1000.0)
			b.overlay.draw.disconnect(b._draw_overlay)
			b.overlay.draw.connect(hook)
			for i in 120:
				b.overlay.queue_redraw()
				await process_frame
			b.overlay.draw.disconnect(hook)
			b.overlay.draw.connect(b._draw_overlay)
			report["battle_overlay_draw_ms"] = stats(dsum)
			# 覚醒（夜）の時
			b.phase.phase = "awake"
			for i in 150:
				await process_frame
			report["battle_night"] = await sample(frames_n / 2)
			b.phase.phase = "normal"
		# ロビーへもどる
		flow.goto("lobby")
		for i in 60:
			await process_frame
		cyc["mem_back_in_lobby"] = memory()
		cycles.append(cyc)
	report["cycles"] = cycles
	report["total_ms"] = (now_us() - t0) / 1000.0
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("PERF ", out_path)
	quit(0)

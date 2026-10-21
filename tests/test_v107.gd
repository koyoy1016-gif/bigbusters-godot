extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v107.gd
## 版107（通信①：相手の動きをなめらかに）。
## 前は、届いた位置へ毎コマ少しずつ近づけていた（smooth_per_sec）。届く間隔が通信でばらつくので、速くなったり止まったりして見えた。
## いまは、送った時刻（サーバーの時計）つきで記録し、「少し前の時刻」の位置を、記録の間でなめらかにつないで見せる（snapshot_buffer.gd）。
## 確かめること：
##   1. 通信の遅れがばらつく（40〜250 ms）ときでも、相手は一定の速さで動く（1コマの動きのばらつきが、前の作りより小さい）
##   2. 見える位置は、相手が少し前（遅れ）にいた位置と同じ（ずれない）。遅れは決めた範囲（80〜350 ms）の中
##   3. 相手が止まると、行きすぎずに、止まった所で止まる
##   4. 届かない間は、最後の速さで少しだけ（extrap_ms まで）のばし、それ以上は進まない
##   5. 送った時刻が、受けた時刻とかけはなれている（時計のくるい・古い版）・時刻がない時は、受けた時刻を使う
##   6. 遅れは、急に変えず、少しずつ変える
##   7. 読み方：全部の状態は 0.1 秒ごと、位置だけは 0.05 秒ごと（位置は前と同じく 1 秒に約 20 回読む）。位置が読めなかった時は、相手を消さない
##   8. 部屋からいなくなった人の記録は消す

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const SnapshotBuffer := preload("res://scripts/network/snapshot_buffer.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


## 1コマの動きの量の、ばらつき（標準偏差 ÷ 平均）と、平均から半分以上ずれたコマの数
func jitter_of(steps: Array) -> Dictionary:
	var sum := 0.0
	for v in steps:
		sum += float(v)
	var mean := sum / maxf(1.0, float(steps.size()))
	var sq := 0.0
	var bad := 0
	for v in steps:
		sq += (float(v) - mean) * (float(v) - mean)
		if absf(float(v) - mean) > mean * 0.5:
			bad += 1
	return {"mean": mean, "cv": sqrt(sq / maxf(1.0, float(steps.size()))) / maxf(mean, 0.000001), "bad": bad}


func _initialize() -> void:
	# ---- 4・5・6：記録だけで ----
	var buf := SnapshotBuffer.new()
	for i in 6:
		buf.push(1000.0 + i * 100.0, Vector2(i * 0.01, 0.0), 1000.0 + i * 100.0 + 60.0)
	var last := Vector2(0.05, 0.0)
	var v_per_ms := 0.01 / 100.0
	var far := buf.sample(1500.0 + 600.0, 120.0, Vector2.ZERO)
	var just := buf.sample(1500.0 + 50.0, 120.0, Vector2.ZERO)
	check(absf(just.x - (last.x + v_per_ms * 50.0)) < 0.00001 and absf(far.x - (last.x + v_per_ms * 120.0)) < 0.00001,
			"届かない間は、最後の速さで 120 ms 分だけのばし、それ以上は進まない（50 ms 先 %.4f・600 ms 先 %.4f）" % [just.x, far.x])
	check(not buf.push(1300.0, Vector2(9, 9), 1700.0) and buf.samples.size() == 6, "同じか古い時刻の記録は、足さない（同じ位置を何回も読むため）")
	var skew := SnapshotBuffer.new()
	skew.push(1000.0, Vector2.ZERO, 50000.0, 3000.0)
	check(is_equal_approx(float(skew.samples[0]["t"]), 50000.0), "送った時刻が、受けた時刻と 3 秒以上ちがえば、受けた時刻を使う")
	var d := SnapshotBuffer.new()
	for i in 5:
		d.push(1000.0 + i * 100.0, Vector2.ZERO, 1000.0 + i * 100.0 + 150.0)  # とぎれる時間 250 ms
	var d0 := d.update_delay(100.0, 80.0, 350.0, 0.016, 30.0, 15.0)
	d0 = d.update_delay(100.0, 80.0, 350.0, 0.016, 30.0, 15.0)
	d.push(1500.0, Vector2.ZERO, 1500.0 + 160.0)
	var d_small := d.update_delay(100.0, 80.0, 350.0, 0.1, 30.0, 15.0)
	for i in 30:
		d.push(2000.0 + i * 100.0, Vector2.ZERO, 2000.0 + i * 100.0 + 300.0)  # 急に遅くなった（とぎれる時間 400 ms）
	var d1 := d.update_delay(100.0, 80.0, 350.0, 0.1, 30.0, 15.0)
	check(is_equal_approx(d0, 250.0) and is_equal_approx(d_small, d0) and absf(d1 - d0) <= 3.0001 and d1 > d0,
			"遅れは、とぎれる時間（250 ms）に合わせ、小さな差では変えず、大きく変わっても 1秒に 30 ms までずつ変える（%.0f → %.1f ms）" % [d0, d1])
	# 遅れて届いた記録で位置がずれても、ぱっと飛ばない。大きく飛んだ時は、そのまま飛ぶ
	var c := SnapshotBuffer.new()
	c.snap_dist = 0.1
	c.push(1000.0, Vector2(0.0, 0.0), 1100.0)
	c.push(1100.0, Vector2(0.01, 0.0), 1200.0)
	var shown := c.sample(1200.0, 120.0)  # のばして 0.02
	c.push(1150.0, Vector2(0.01, 0.0), 1210.0)  # じつは止まっていた
	var shown2 := c.sample(1200.0, 120.0)
	c.ease_correction(0.5, 10.0)
	var shown3 := c.sample(1200.0, 120.0)
	check(absf(shown.x - 0.02) < 0.00001 and absf(shown2.x - shown.x) < 0.00001 and absf(shown3.x - 0.01) < 0.0001,
			"遅れて届いた記録で位置がずれても、ぱっと飛ばず、少しずつもどす（%.3f → %.3f → %.4f）" % [shown.x, shown2.x, shown3.x])
	c.push(1300.0, Vector2(0.5, 0.0), 1310.0)  # 最初の位置へもどった（大きく飛んだ）
	var shown4 := c.sample(1400.0, 120.0)
	check(absf(shown4.x - 0.5) < 0.001, "大きく飛んだ時は、すべらせずに、そのまま飛ぶ")

	# ---- 1・2・3・7・8：戦いの画面で、通信をまねて ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = false
	s.use_network = false
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.set_process(false)  # コマはこのテストで進める
	s.sfx = null
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	var delivered := {}  # ブラウザ側に届いている、相手の位置
	var reads := {"full": 0, "pos": 0}
	var pos_fail := [false]
	var members := [["p1", "p2"]]
	var fake := func(text: String) -> Variant:
		if text == "typeof window.bbFirebase":
			return "object"
		if text.begins_with("new URLSearchParams"):
			return "2222"
		if text == "JSON.stringify(window.bbFirebase.state)":
			reads["full"] += 1
			return JSON.stringify({"status": "in_room", "slot": "p1", "members": members[0], "positions": delivered, "hits": {}, "offset": 0})
		if text.begins_with("JSON.stringify((window.bbFirebase"):
			reads["pos"] += 1
			return null if pos_fail[0] else JSON.stringify(delivered)
		return null
	s.js_eval = fake
	s._setup_network()
	var half := float(s.config["bounds"])
	var speed := 6.0  # 相手の走る速さ（m/秒）
	var t0: float = float(now[0]) + 500.0
	var t_stop: float = t0 + 3000.0
	var x0 := 0.3
	var true_x := func(t: float) -> float:
		return x0 + speed * clampf(t - t0, 0.0, t_stop - t0) / 1000.0 / (2.0 * half)
	# 相手が送る位置（100 ms ごと・少しずれる）と、届く時刻（40〜250 ms・追いこさない）
	var rng := RandomNumberGenerator.new()
	rng.seed = 107
	var queue: Array = []
	var arr_prev := 0.0
	var ts: float = float(now[0]) - 300.0
	while ts < t_stop + 2000.0:
		var st: float = ts + rng.randf_range(-8.0, 8.0)
		var arr := maxf(arr_prev, st + rng.randf_range(40.0, 250.0))
		arr_prev = arr
		queue.append({"t": st, "arr": arr, "x": float(true_x.call(st))})
		ts += 100.0
	var frame_ms := 1000.0 / 60.0
	var weight: float = load("res://scripts/network/position_sync.gd").smooth_weight(1.0 / 60.0, float(s.config["smooth_per_sec"]))
	var old_target := -1.0
	var old_x := -1.0
	var since_old_poll := 0.0
	var new_steps: Array = []
	var old_steps: Array = []
	var prev_new := -999.0
	var prev_old := -999.0
	var max_err := 0.0
	var max_x := -999.0
	var delays: Array = []
	var qi := 0
	var frames := int((t_stop + 1500.0 - float(now[0])) / frame_ms)
	var reads_1s := {}
	var behind := {"old": 0.0, "new": 0.0, "n": 0}
	for f in frames:
		now[0] += frame_ms
		while qi < queue.size() and float(queue[qi]["arr"]) <= now[0]:
			delivered["p2"] = {"x": queue[qi]["x"], "y": 0.5, "t": queue[qi]["t"]}  # 中身を入れかえる（関数は、同じ辞書を見ている）
			qi += 1
		if f == 60:
			reads_1s = reads.duplicate()
		s.net_update(1.0 / 60.0, int(now[0]))
		if not s.others.has("p2"):
			continue
		var nx: float = (s.others["p2"] as Node3D).position.x
		# 前の作り（届いた位置へ、毎コマ少しずつ近づける。0.05 秒ごとに読む）を、同じ届き方でまねる
		since_old_poll += 1.0 / 60.0
		if since_old_poll >= 0.05 and delivered.has("p2"):
			since_old_poll = 0.0
			old_target = float(delivered["p2"]["x"]) * 2.0 * half - half
		if old_target > -900.0:
			old_x = old_target if old_x < -900.0 else lerpf(old_x, old_target, weight)
		var buf2: SnapshotBuffer = s.net_buffers.get("p2")
		var rt: float = s.server_now_ms() - buf2.delay_ms
		# 動いている間（見せる時刻が、走り始めと止まりから 300 ms 以上はなれている）だけ比べる
		var steady: bool = rt > t0 + 300.0 and rt < t_stop - 300.0
		var old_steady: bool = float(now[0]) > t0 + 600.0 and float(now[0]) < t_stop
		if steady:
			if prev_new > -900.0:
				new_steps.append(nx - prev_new)
			max_err = maxf(max_err, absf(nx - (float(true_x.call(rt)) * 2.0 * half - half)))
			delays.append(buf2.delay_ms)
		if old_steady and prev_old > -900.0:
			old_steps.append(old_x - prev_old)
		if old_steady and steady:
			var true_now := float(true_x.call(float(now[0]))) * 2.0 * half - half
			behind["old"] += (true_now - old_x) / speed * 1000.0
			behind["new"] += (true_now - nx) / speed * 1000.0
			behind["n"] += 1
		prev_new = nx if steady else -999.0
		prev_old = old_x if old_steady else -999.0
		max_x = maxf(max_x, nx)
	print("     相手が、いまの本当の位置より、何 ms 分うしろに見えるか（平均）：いま %.0f ms・前 %.0f ms" % [behind["new"] / maxf(1.0, behind["n"]), behind["old"] / maxf(1.0, behind["n"])])
	var jn := jitter_of(new_steps)
	var jo := jitter_of(old_steps)
	print("     1コマの動き：いま 平均 %.3f m・ばらつき %.1f%%・ずれたコマ %d／%d  前 平均 %.3f m・ばらつき %.1f%%・ずれたコマ %d／%d" % [
			jn["mean"], float(jn["cv"]) * 100.0, jn["bad"], new_steps.size(), jo["mean"], float(jo["cv"]) * 100.0, jo["bad"], old_steps.size()])
	check(new_steps.size() > 100 and absf(float(jn["mean"]) - speed / 60.0) < 0.005, "相手は、送った人と同じ速さ（1コマ %.3f m・送った人 %.3f m）で動く" % [jn["mean"], speed / 60.0])
	check(float(jn["cv"]) < 0.05 and int(jn["bad"]) == 0, "届く遅れがばらついても、1コマの動きはそろう（ばらつき %.1f%%・半分以上ずれたコマ %d）" % [float(jn["cv"]) * 100.0, jn["bad"]])
	check(float(jo["cv"]) > float(jn["cv"]) * 5.0, "前の作り（ばらつき %.1f%%）より、ずっとなめらか" % (float(jo["cv"]) * 100.0))
	var dmin := 9999.0
	var dmax := 0.0
	for v in delays:
		dmin = minf(dmin, float(v))
		dmax = maxf(dmax, float(v))
	check(max_err < 0.05 and dmin >= 80.0 and dmax <= 350.0, "見える位置は、相手が少し前（%.0f〜%.0f ms 前）にいた所と同じ（ずれ %.3f m）" % [dmin, dmax, max_err])
	var stop_x := float(true_x.call(t_stop)) * 2.0 * half - half
	var end_x: float = (s.others["p2"] as Node3D).position.x
	check(absf(end_x - stop_x) < 0.01 and max_x < stop_x + 0.05, "相手が止まると、行きすぎずに止まった所で止まる（行きすぎ %.3f m）" % maxf(0.0, max_x - stop_x))
	check(int(reads_1s["full"]) >= 8 and int(reads_1s["full"]) <= 12 and int(reads_1s["full"]) + int(reads_1s["pos"]) >= 18,
			"1秒に、全部の状態を %d 回・位置だけを %d 回読む（位置は合わせて %d 回）" % [reads_1s["full"], reads_1s["pos"], int(reads_1s["full"]) + int(reads_1s["pos"])])
	# ---- 7. 位置が読めなかった時 ----
	pos_fail[0] = true
	var seen_fail := false
	for i in 6:
		now[0] += frame_ms
		var before := int(reads["pos"])
		s.net_update(1.0 / 60.0, int(now[0]))
		if int(reads["pos"]) > before:
			seen_fail = true
			break
	check(seen_fail and s.others.has("p2") and s.net_buffers.has("p2"), "位置が読めなかった時は、相手を消さない")
	pos_fail[0] = false
	# 時刻のない位置（古い版）
	s.apply_net_state({"slot": "p1", "members": ["p1", "p2"], "positions": {"p2": {"x": 0.9, "y": 0.5}}, "hits": {}, "offset": 0})
	var lb: SnapshotBuffer = s.net_buffers["p2"]
	check(is_equal_approx(float(lb.samples[-1]["t"]), s.server_now_ms()), "時刻のない位置は、受けた時刻で記録する")
	# ---- 8 ----
	members[0] = ["p1"]
	s.apply_net_state({"slot": "p1", "members": ["p1"], "positions": delivered, "hits": {}, "offset": 0})
	check(not s.net_buffers.has("p2") and not s.others.has("p2"), "部屋からいなくなった人の記録と箱は、消える")
	var src := FileAccess.get_file_as_string("res://web/head/10_room.js")
	check(src.contains("t: Date.now() + (this.state.offset || 0)"), "送る位置の時刻は、サーバーの時計")
	s.queue_free()
	await process_frame
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_bottle_ride.gd
## 必殺技「巨大酒瓶ライド」（版63で作り直し）：4〜6回、8方向（左右・上下・ななめ）から、ステージの外から反対の外まで突っこむか。
## 速さは版65の値（版63の36 m/秒の1.2倍）か。走る前から道を予告するか。突入1回に酒瓶を12本投げ、予告の所に落ちるか（落ちる範囲は半径2.5＝前の1.25倍）。ボスが瓶の上に座る高さか。最後はステージの中にもどるか。

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const BM := preload("res://scripts/boss/boss_model.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var cfg := Attacks.load_config()
	check(cfg["kinds"].has("bottle_ride"), "巨大酒瓶ライドがある")
	var k: Dictionary = cfg["kinds"]["bottle_ride"]
	var bounds := 15.0
	check(float(k["power"]) >= 20.0 and float(k["power"]) <= 25.0, "瓶に当たるダメージは 20〜25（%s）" % k["power"])
	check(str(k["knockback"]) == "kb_launch" and str(k["kb_mode"]) == "travel", "大きくはね飛ばす（走る向き）")
	check(bool((k["ai"] as Dictionary).get("ultimate", false)) and float((k["ai"]["forms"] as Dictionary).get("normal", 0.0)) <= 0.0, "覚醒のときだけの必殺技")
	check(is_equal_approx(float(k["ride_speed"]), 36.0 * 1.2), "速さは、版63（36 m/秒）の1.2倍（%.1f m/秒）" % float(k["ride_speed"]))
	check(int(k["bottles_per_pass"]) == 12 and is_equal_approx(float(k["throw_power"]), 12.0), "突入1回に酒瓶12本（版67で18本から戻した）、1本12ダメージ")
	check(is_equal_approx(float(k["throw_radius"]), 2.5 * 1.25), "投げた酒瓶の落ちる範囲は、版66（半径2.5）の1.25倍（%.3f）" % float(k["throw_radius"]))
	check(not bool(cfg.get("puddles_enabled", true)), "酒だまりは残さない")

	var all_dirs := {}
	var count_seen := {}
	var all_ok := true
	var throws_ok := true
	var gap_fail := 0
	var gap_total := 0
	for seed in [1.0, 777.0, 123456.0, 9.5e6, 3.3e7, 42.0]:
		for n in [1, 2, 7, 30, 55]:
			var ctx := {"boss": Vector2(2.0, -3.0), "yaw": 0.4, "target": Vector2(-1.0, 4.0), "round_start_ms": seed, "n": n, "bounds": bounds, "area": 13.0}
			var plan := Attacks.ride_plan(k, ctx)
			count_seen[plan.size()] = true
			var ok := plan.size() >= 4 and plan.size() <= 6
			var a := {"n": n, "kind": "bottle_ride", "start": 0.0, "end": 99.0}
			for i in plan.size():
				var ps: Dictionary = plan[i]
				all_dirs[int(ps["dir_i"])] = true
				if i > 0:
					var pd := int(plan[i - 1]["dir_i"])
					ok = ok and int(ps["dir_i"]) != pd and int(ps["dir_i"]) != (pd + 4) % 8
				# 外から外へ：瓶の後ろの端まで、ステージの外
				for e in [ps["from"], ps["to"]]:
					var ev: Vector2 = e
					ok = ok and maxf(absf(ev.x), absf(ev.y)) >= bounds + float(k["half_len"]) + float(k["offscreen"]) - 0.01
				var sp := float(ps["speed"])
				ok = ok and sp >= float(k["ride_speed"]) * float(k["speed_min"]) - 0.01 and sp <= float(k["ride_speed"]) * float(k["speed_max"]) + 0.01
				ok = ok and is_equal_approx((float(ps["end"]) - float(ps["start"])) * sp, (ps["from"] as Vector2).distance_to(ps["to"]))
				ok = ok and float(ps["start"]) - float(ps["tele_from"]) >= 0.6
				# 位置：走りはじめ・終わり
				var s0: Dictionary = Attacks.ride_at(float(ps["start"]) + 0.001, k, ctx)
				var s1: Dictionary = Attacks.ride_at(float(ps["end"]) - 0.001, k, ctx)
				ok = ok and str(s0["phase"]) == "pass" and Vector2((s0["bottle"] as Vector3).x, (s0["bottle"] as Vector3).z).distance_to(ps["from"]) < 0.2
				ok = ok and Vector2((s1["bottle"] as Vector3).x, (s1["bottle"] as Vector3).z).distance_to(ps["to"]) < 0.2
				# 当たり：走っている間、ステージの中では当たる。はね飛ぶ向きは走る向き
				var mid: Array = Attacks.hazards(a, (float(ps["start"]) + float(ps["end"])) * 0.5, cfg, ctx)
				var act := mid.filter(func(h: Dictionary) -> bool: return bool(h["active"]) and str(h["style"]) == "ride")
				var d: Vector2 = ps["d"]
				ok = ok and act.size() == 1 and Vector2(float(act[0]["kb_x"]), float(act[0]["kb_z"])).is_equal_approx(d)
				# 予告の帯：走る前に出ていて、走っている間も出ている
				var pre: Array = Attacks.hazards(a, float(ps["start"]) - 0.05, cfg, ctx)
				var lane := pre.filter(func(h: Dictionary) -> bool: return str(h["style"]) == "ride_lane" and str(h["id"]).ends_with("_%d" % int(ps["i"])))
				ok = ok and lane.size() == 1 and float(lane[0]["tele"]) > 0.8 and str(lane[0]["shape"]) == "obox"
				var lane_mid := mid.filter(func(h: Dictionary) -> bool: return str(h["style"]) == "ride_lane" and str(h["id"]).ends_with("_%d" % int(ps["i"])))
				ok = ok and lane_mid.size() == 1
				# 酒瓶：12本。投げる時刻は突入の間。落ちる所はステージの中、道からはなれた所。予告と落ちる所が同じ
				var bs := Attacks.ride_throws(ps, k, ctx)
				var tok := bs.size() == 12
				for bi in bs.size():
					var b: Dictionary = bs[bi]
					var to: Vector2 = b["to"]
					tok = tok and float(b["throw"]) >= float(ps["start"]) and float(b["throw"]) <= float(ps["end"])
					tok = tok and absf(to.x) <= bounds and absf(to.y) <= bounds
					tok = tok and absf((to - (ps["c"] as Vector2)).dot(Vector2(-d.y, d.x))) >= float(k["half_width"]) + float(k["throw_radius"])
					var land_h: Array = Attacks.hazards(a, float(b["land"]) + 0.01, cfg, ctx)
					var hit := land_h.filter(func(h: Dictionary) -> bool: return str(h["id"]) == str(b["id"]) and bool(h["active"]))
					tok = tok and hit.size() == 1 and Vector2(float(hit[0]["x"]), float(hit[0]["z"])).is_equal_approx(to) and is_equal_approx(float(hit[0]["power"]), 12.0)
					var tele_h: Array = Attacks.hazards(a, float(b["throw"]) + 0.05, cfg, ctx)
					tok = tok and tele_h.filter(func(h: Dictionary) -> bool: return str(h["id"]) == str(b["id"]) and not bool(h["active"]) and h.has("bottle")).size() == 1
					for bj in range(bi + 1, bs.size()):
						gap_total += 1
						if (to as Vector2).distance_to(bs[bj]["to"]) < float(k["throw_min_gap"]) - 0.01:
							gap_fail += 1
				throws_ok = throws_ok and tok
			# 最後：ステージの中に降りて、すき。攻撃の長さ（AI が使う長さ）にぴったり収まる
			var total := Attacks.ride_total_for(k, ctx)
			var fin: Dictionary = Attacks.ride_at(total - 0.01, k, ctx)
			ok = ok and str(fin["phase"]) == "recover" and absf((fin["pos"] as Vector2).x) <= 13.0 and absf((fin["pos"] as Vector2).y) <= 13.0 and absf(float(fin["y"])) < 0.01
			ok = ok and total <= Attacks.ride_total(k) + 0.01
			ok = ok and is_equal_approx(Attacks.attack_duration("bottle_ride", k, n, seed), total)
			if not ok:
				print("  失敗した組み合わせ：seed=%s n=%d" % [seed, n])
			all_ok = all_ok and ok
	check(all_ok, "4〜6回、外から外へ・同じ向きが続かない・速さ・予告・当たり・もどり（6つの乱数×5つの番号）")
	check(count_seen.has(4) and count_seen.has(5) and count_seen.has(6), "突入の回数は 4・5・6 回のどれも出る（%s）" % str(count_seen.keys()))
	check(all_dirs.size() == 8, "左右・上下・ななめの8方向がどれも出る（%d 方向）" % all_dirs.size())
	check(throws_ok, "酒瓶：12本・突入の間に投げる・ステージの中で道からはなれた所に落ちる・予告の所に12ダメージ")
	check(gap_fail * 10 <= gap_total, "酒瓶の落ちる所は、ほとんどが %.0fm 以上はなれている（近すぎ %d / %d）" % [float(k["throw_min_gap"]), gap_fail, gap_total])

	# 座る高さ：ボスの腰が、瓶の上の面（＋おしり）に来る
	var ctx2 := {"boss": Vector2.ZERO, "yaw": 0.0, "target": Vector2.ZERO, "round_start_ms": 5.0, "n": 3, "bounds": bounds, "area": 13.0}
	var p2 := Attacks.ride_plan(k, ctx2)
	var um := (float(p2[0]["start"]) + float(p2[0]["end"])) * 0.5
	var r: Dictionary = Attacks.ride_at(um, k, ctx2)
	var bc: Vector3 = r["bottle"]
	check(is_equal_approx(float(r["y"]) + float(k["seat_hip"]), bc.y + float(k["bottle_radius"]) + float(k["seat_butt"])), "ボスの腰は、瓶の上の面に来る（座る）")
	var bpos := Vector2(bc.x, bc.z)
	var dd: Vector2 = p2[0]["d"]
	check((r["pos"] as Vector2).is_equal_approx(bpos - dd * float(k["seat_back"])) and is_equal_approx(float(r["yaw"]), atan2(dd.x, dd.y)), "ボスは瓶の上（少しうしろ）に、瓶と同じ向きで乗る")
	check(BottleMesh.radius_at(-float(k["seat_back"]), float(k["half_len"]) * 2.0, float(k["bottle_radius"])) >= float(k["bottle_radius"]) * 0.99, "座る所は瓶の胴（いちばん太い所）")
	check(bc.y - float(k["bottle_radius"]) >= 0.3, "瓶は地面に埋まらない")
	var intro: Array = Attacks.hazards({"n": 3, "kind": "bottle_ride", "start": 0.0, "end": 99.0}, 0.3, cfg, ctx2)
	check(intro.is_empty(), "空へ跳んでいる間は、当たりも予告もない")
	var path: Dictionary = Attacks.boss_path("bottle_ride", um, k, ctx2)
	check(path["pos"] == r["pos"] and path.has("bottle") and path["bottle"] == r["bottle"], "ボスの道と瓶の位置が同じ（ずれない）")

	# 本物のボスのモデルで：座る姿勢の腰の高さが seat_hip と合い、脚が瓶に埋まらない（tools/measure_seat.gd と同じ計り方）
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(BM.load_config(), StandardMaterial3D.new())
	m.animate(0.0, 1.0, {"kind": "bottle_ride", "u": 3.0, "k": k, "ride_phase": "pass", "ride_phase_t": 0.0, "clock": 0.0})
	var sc := float(m.cfg["model_scale"])
	var hip_y: float = (m.anim.bone_model_pos(m.pose, "upperleg01.L").y + m.anim.bone_model_pos(m.pose, "upperleg01.R").y) * 0.5 * sc
	check(absf(hip_y - float(k["seat_hip"])) < 0.15, "座る姿勢の腰の高さが、データ（seat_hip）と合う（%.2f m）" % hip_y)
	var cy := float(k["seat_hip"]) - float(k["seat_butt"]) - float(k["bottle_radius"])
	var worst := 99.0
	for b in ["upperleg02.L", "lowerleg01.L", "lowerleg02.L", "foot.L", "upperleg02.R", "lowerleg01.R", "lowerleg02.R", "foot.R"]:
		var p: Vector3 = m.anim.bone_model_pos(m.pose, b) * sc
		var rr := BottleMesh.radius_at(p.z - float(k["seat_back"]), float(k["half_len"]) * 2.0, float(k["bottle_radius"]))
		worst = minf(worst, Vector2(p.x, p.y - cy).length() - rr)
	check(worst >= 0.25 and worst <= 1.0, "脚は瓶の横にそって、瓶に埋まらない（瓶の面から %.2f m）" % worst)
	var lk: Vector3 = m.anim.bone_model_pos(m.pose, "lowerleg01.L") * sc
	var rk2: Vector3 = m.anim.bone_model_pos(m.pose, "lowerleg01.R") * sc
	check(lk.x > float(k["bottle_radius"]) * 0.8 and rk2.x < -float(k["bottle_radius"]) * 0.8 and absf(lk.y - rk2.y) < 0.1, "またがっている（ひざが瓶の左右に、同じ高さで）")
	m.free()

	# AI：覚醒してしばらくたてば選ばれる。第1形態では選ばれない。攻撃の終わりは道の長さどおり
	var ai := BossAI.new()
	ai.reset(cfg, 1.0)
	check(not ai.candidate_weights(30.0, "normal", 5.0).has("bottle_ride"), "第1形態では出ない")
	ai.on_awake(0.0)
	check(ai.candidate_weights(30.0, "awake", 5.0).has("bottle_ride"), "覚醒したあとは出る")
	ai.nxt = {"n": 9, "kind": "bottle_ride", "start": 40.0, "feint": 0.0}
	ai.update(40.0, "awake", func(_n: int) -> float: return 5.0)
	check(is_equal_approx(float(ai.cur["end"]) - 40.0, Attacks.ride_total_for(k, {"n": 9, "round_start_ms": 1.0})), "AI の攻撃の終わりは、その回の道の長さどおり（とちゅうで止まらない・待ちすぎない）")
	# 戦いの画面で：乗っている間ずっと、ボスは瓶の上の同じ所に座っている。酒瓶が飛ぶ。最後はふつうにもどる
	var sc2: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(sc2)
	if sc2.get_node_or_null("Boss") == null:
		sc2._ready()
	var now := [8000000.0]
	sc2.clock_ms = func() -> float: return now[0]
	sc2.sfx = null
	sc2.ai_enabled = false
	sc2.start_round()
	sc2.phase.phase = "awake"
	sc2.boss_model._apply_form("awake")
	now[0] += 10000.0
	sc2.combat_update(0.02)
	var fa: Dictionary = sc2.force_attack("bottle_ride")
	var t := float(fa["start"])
	var seat_ok := true
	var seat_frames := 0
	var max_bottles := 0
	var saw_throw := false
	var hs := Attacks.ride_heights(k, 0.0)
	while t < float(fa["end"]) + 0.6:
		t += 0.03
		now[0] = sc2.round_start_ms + t * 1000.0
		sc2.player.position = Vector3(0, sc2.ground_y, 40)
		sc2.my_hp = 150.0
		sc2.combat_update(0.03)
		sc2._pose_boss(0.03)
		if sc2._ride_bottle != null and sc2._ride_bottle.visible:
			seat_frames += 1
			var bwp: Vector3 = sc2._ride_bottle.position
			var boss_p: Vector3 = sc2.boss.position
			var rel := Vector2(boss_p.x - bwp.x, boss_p.z - bwp.z)
			var fwd := Vector2(sin(sc2._ride_bottle.rotation.y), cos(sc2._ride_bottle.rotation.y))
			seat_ok = seat_ok and rel.is_equal_approx(-fwd * float(k["seat_back"])) and is_equal_approx(boss_p.y - bwp.y, float(hs["boss_y"]) - float(hs["center"]))
			seat_ok = seat_ok and is_equal_approx(wrapf(sc2.boss.rotation.y - sc2._ride_bottle.rotation.y, -PI, PI), 0.0)
		var vis := 0
		for bn in sc2._bottle_nodes:
			if (bn as Node3D).visible:
				vis += 1
		max_bottles = maxi(max_bottles, vis)
		if vis > 0:
			saw_throw = true
	check(seat_frames > 30 and seat_ok, "画面：乗っている間ずっと、ボスは瓶の上の同じ所に、同じ向きで座っている（%d コマ）" % seat_frames)
	check(saw_throw and max_bottles <= 26, "画面：酒瓶が飛ぶ（同時に最大 %d 本。多すぎない）" % max_bottles)
	check(str(sc2.current_attack.get("kind", "")) != "bottle_ride" and sc2.motion.height < 0.01 and not sc2._ride_bottle.visible, "画面：ライドが終わると、地面にもどって、ふつうの動きにもどる")
	check(sc2.field.alive(t).is_empty(), "画面：酒だまりは残らない")
	sc2._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

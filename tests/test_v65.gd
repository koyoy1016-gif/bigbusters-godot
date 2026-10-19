extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v65.gd
## 版65の変更：酒瓶の落ちる範囲が1.25倍（予告と当たりが同じ）・回転バット移動は脚を閉じてまっすぐ進む・バット投げの予告は細い線だけ。
## （巨大酒瓶ライドの速さ1.2倍・12本は tests/test_bottle_ride.gd）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const BM := preload("res://scripts/boss/boss_model.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var cfg := Attacks.load_config()
	var kinds: Dictionary = cfg["kinds"]

	# ---- 酒瓶落とし：落ちる範囲は半径2.5（前の2.0の1.25倍）。予告の円と当たりの円が同じ。ダメージは12のまま ----
	var sk: Dictionary = kinds["sake_drop"]
	check(is_equal_approx(float(sk["radius"]), 2.0 * 1.25) and is_equal_approx(float(sk["power"]), 12.0), "酒瓶落とし：落ちる範囲は前の1.25倍（半径2.5）、ダメージ12のまま")
	var ctx := {"boss": Vector2(0, 0), "yaw": 0.0, "members": [], "positions": {}, "locked": null, "round_start_ms": 7.0, "bounds": 15.0, "target": Vector2(2, 8), "area": 13.0, "n": 3}
	var a := {"n": 3, "kind": "sake_drop", "start": 0.0, "end": 9.0}
	var b0: Dictionary = Attacks.sake_bottles(a, sk, ctx)[0]
	var tele: Array = Attacks.hazards(a, float(b0["throw"]) + 0.05, cfg, ctx).filter(func(h: Dictionary) -> bool: return str(h["id"]) == str(b0["id"]))
	var hit: Array = Attacks.hazards(a, float(b0["land"]) + 0.01, cfg, ctx).filter(func(h: Dictionary) -> bool: return str(h["id"]) == str(b0["id"]))
	check(tele.size() == 1 and hit.size() == 1 and is_equal_approx(float(tele[0]["r"]), 2.5) and is_equal_approx(float(hit[0]["r"]), 2.5), "酒瓶落とし：予告の円と、当たる円の半径が同じ（2.5）")
	var rb: Dictionary = kinds["bottle_ride"]
	check(is_equal_approx(float(rb["throw_radius"]), 2.5) and is_equal_approx(float(rb["throw_power"]), 12.0), "ライドで投げる瓶も、落ちる範囲は半径2.5（1.25倍）、ダメージ12のまま")

	# 戦いの画面：落ちる所の中心から 2.3m なら当たり、2.7m なら当たらない（見た目の円＝当たり）
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [6000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.ai_enabled = false
	s.start_round()
	var res := {}
	for dist in [2.3, 2.7]:
		var h := {"id": "tv%.1f" % dist, "shape": "circle", "x": 0.0, "z": 0.0, "r": 2.5, "active": true, "tele": 1.0, "power": 12.0, "jumpable": false, "target": "", "tick": -1, "style": "bottle", "kb": "kb_light", "kb_mode": "radial"}
		s.my_hp = 150.0
		s.kb_guard_left = 0.0
		s.actions.reset()
		s.hazard_done = {}
		s.player.position = Vector3(dist, s.ground_y, 0.0)
		s.current_hazards = [h]
		s._apply_hazards([h])
		res[dist] = s.my_hp < 150.0
	check(bool(res.get(2.3, false)) and not bool(res.get(2.7, true)), "画面：円の中（2.3m）は当たり、外（2.7m）は当たらない")
	s._show_hazards([{"id": "c1", "shape": "circle", "x": 0.0, "z": 0.0, "r": 2.5, "active": false, "tele": 0.5, "power": 12.0, "style": "bottle"}])
	check(is_equal_approx((s.hazard_nodes[0] as Node3D).scale.x, 2.5), "画面：予告の円の見た目の半径も 2.5")

	# ---- 回転バット移動：脚を閉じたまま、まっすぐ進む。9／ヒット、予告なし ----
	var bk: Dictionary = kinds["spin_bat"]
	check(is_equal_approx(float(bk["power"]), 9.0), "回転バット移動：ダメージは9のまま")
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(BM.load_config(), StandardMaterial3D.new())
	var sc := float(m.cfg["model_scale"])
	var w := float(bk["windup_sec"])
	var run := float(bk["run_sec"])
	var feet_ok := true
	var max_gap := 0.0
	var u := w
	while u < w + run:
		# 歩いているとき（歩きの速さあり）でも、脚は閉じたまま
		m.animate(0.0, u, {"kind": "spin_bat", "u": u, "k": bk, "walk_speed": 3.0, "walk_dist": u * 3.0, "clock": u})
		var fl: Vector3 = m.anim.bone_model_pos(m.pose, "foot.L") * sc
		var fr: Vector3 = m.anim.bone_model_pos(m.pose, "foot.R") * sc
		max_gap = maxf(max_gap, fl.distance_to(fr))
		feet_ok = feet_ok and absf(fl.z - fr.z) < 0.15 and fl.y < 0.6 and fr.y < 0.6
		u += 0.1
	check(feet_ok and max_gap < 1.2, "回転バット移動：回っている間、足はそろえて閉じたまま（足の間 最大 %.2f m）" % max_gap)
	var tip: Vector3 = m.bat_tip_local()
	check(absf(Vector2(tip.x, tip.z).length() - float(bk["radius"])) < 0.15, "回転バット移動：当たりの丸の半径（%.1f）は、バットの先までの長さ（%.2f）と同じ" % [float(bk["radius"]), Vector2(tip.x, tip.z).length()])
	m.free()
	var c2 := {"boss": Vector2(1, -2), "yaw": 0.3, "target": Vector2(-4, 9), "round_start_ms": 5.0, "n": 4, "area": 13.0}
	var p0: Vector2 = Attacks.spin_bat_at(w, bk, c2)["pos"]
	var p1: Vector2 = Attacks.spin_bat_at(w + run, bk, c2)["pos"]
	var dir := (Vector2(-4, 9) - Vector2(1, -2)).normalized()
	var straight := true
	u = w
	while u <= w + run:
		var p: Vector2 = Attacks.spin_bat_at(u, bk, c2)["pos"]
		straight = straight and absf((p - p0).cross(dir)) < 0.01
		u += 0.1
	check(straight and (p1 - p0).normalized().dot(dir) > 0.999, "回転バット移動：はじめにねらった人の方向へ、まっすぐ進む（曲がらない・追いかけない）")
	check(Attacks.hazards({"kind": "spin_bat", "n": 4}, w * 0.5, cfg, c2).is_empty(), "回転バット移動：事前の予告はない")

	# ---- バット投げ：予告は、投げる向きにまっすぐな細い線だけ ----
	var tk: Dictionary = kinds["bat_throw"]
	var c3 := {"boss": Vector2(0, 0), "yaw": 0.7, "round_start_ms": 5.0, "n": 5, "area": 13.0}
	var pre: Array = Attacks.hazards({"kind": "bat_throw", "n": 5}, float(tk["windup_sec"]) * 0.5, cfg, c3)
	var lines := pre.filter(func(h: Dictionary) -> bool: return str(h["shape"]) == "obox")
	var circles := pre.filter(func(h: Dictionary) -> bool: return str(h["shape"]) == "circle")
	check(pre.size() == 1 and lines.size() == 1 and circles.is_empty(), "バット投げ：予告は線が1本だけ（円は出ない）")
	check(lines.size() == 1 and float(lines[0]["hx"]) <= 0.35 and float(lines[0]["hz"]) * 2.0 >= float(tk["distance"]), "バット投げ：線は細く（幅 %.1f m）、飛ぶ長さぶんある" % (float(lines[0]["hx"]) * 2.0 if lines.size() == 1 else -1.0))
	check(lines.size() == 1 and is_equal_approx(float(lines[0]["yaw"]), 0.7), "バット投げ：線の向きは、投げる向き")
	var fly: Dictionary = Attacks.bat_throw_at(float(tk["windup_sec"]) + float(tk["out_sec"]) * 0.5, tk, c3)
	var fp: Vector2 = fly["pos"]
	var on_line := absf(fp.cross(Attacks.fwd_of(0.7))) < 0.01
	check(on_line, "バット投げ：バットは、予告の線の上を飛ぶ")
	var flying_h: Array = Attacks.hazards({"kind": "bat_throw", "n": 5}, float(tk["windup_sec"]) + 0.3, cfg, c3)
	s._show_hazards(flying_h)
	var zone_vis := false
	for i in flying_h.size():
		if (s.hazard_nodes[i] as Node3D).visible:
			zone_vis = true
	check(not zone_vis, "バット投げ：飛んでいる間も、床に円は出ない")
	check(is_equal_approx(float(tk["power"]), 16.0), "バット投げ：ダメージは16のまま")
	s._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

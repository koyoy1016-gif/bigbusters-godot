extends SceneTree
## ボスの攻撃5つの計算（予定表、つかみ、台風、チラシ、必殺技A・B）のテスト

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
var failures := 0


func check(ok: bool, name: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", name)


func _init() -> void:
	var cfg := Attacks.load_config()
	var sched := Attacks.build_schedule(cfg)
	check(sched.size() > 10, "予定表ができる")
	check(str(sched[0]["kind"]) == "grab" and str(sched[1]["kind"]) == "flyers" and str(sched[2]["kind"]) == "typhoon", "最初は つかみ→チラシ→台風")
	var ults := 0
	var seen := {}
	for a in sched:
		seen[str(a["kind"])] = true
		if str(a["kind"]) in ["flyer_storm", "hand_sweep"]:
			ults += 1
			check(float(a["start"]) >= float(cfg["ultimate_first_sec"]), "必殺技は決めた時刻より前に出ない")
	check(ults >= 2 and seen.size() == 5, "5つの攻撃が全部出る")
	for i in sched.size() - 1:
		check(float(sched[i]["end"]) < float(sched[i + 1]["start"]), "攻撃が重ならない")
	check(Attacks.active_index(sched, 0.5) == -1, "最初の待ち時間は攻撃なし")
	check(Attacks.active_index(sched, 3.1) == 0, "3.1秒は1つめの攻撃")

	var members := ["p2", "p1", "p3"]
	check(Attacks.grab_target(1, members) == "p1" and Attacks.grab_target(2, members) == "p2" and Attacks.grab_target(4, members) == "p1", "つかみの的は枠の順にまわる")
	var ctx := {"boss": Vector2(0, -8), "members": members, "positions": {"p1": Vector2(3, 4), "p2": Vector2(-5, 2), "p3": Vector2(0, 0)}, "locked": null, "round_start_ms": 123456.0, "bounds": 14.0}

	# つかみ
	var g: Dictionary = sched[0]
	var gk: Dictionary = cfg["kinds"]["grab"]
	var h0 := Attacks.hazards(g, 0.5, cfg, ctx)
	check(h0.size() == 1 and not bool(h0[0]["active"]) and str(h0[0]["target"]) == "p1" and is_equal_approx(float(h0[0]["x"]), 3.0), "つかみは、的の人の位置を追う（まだ当たらない）")
	ctx["locked"] = Vector2(3, 4)
	ctx["positions"]["p1"] = Vector2(9, 9)
	var h1 := Attacks.hazards(g, float(gk["follow_sec"]) + float(gk["lock_sec"]) + 0.05, cfg, ctx)
	check(bool(h1[0]["active"]) and is_equal_approx(float(h1[0]["x"]), 3.0), "固定したあとは動かない。時間が来ると当たる")
	check(Attacks.hazards(g, float(gk["follow_sec"]) + float(gk["lock_sec"]) + float(gk["hit_sec"]) + 0.1, cfg, ctx).is_empty(), "つかみの当たりは短い")
	check(Attacks.inside(h1[0], 3.5, 4.0) and not Attacks.inside(h1[0], 6.0, 4.0), "輪の中・外の判定")

	# 台風
	var ty := {"n": 3, "kind": "typhoon", "start": 0.0, "end": 5.5}
	var tk: Dictionary = cfg["kinds"]["typhoon"]
	check(not bool(Attacks.hazards(ty, 0.5, cfg, ctx)[0]["active"]), "台風は、最初は予告")
	var t1: Array = Attacks.hazards(ty, float(tk["windup_sec"]) + 0.1, cfg, ctx)
	var t2: Array = Attacks.hazards(ty, float(tk["windup_sec"]) + 0.1 + float(tk["tick_sec"]), cfg, ctx)
	check(bool(t1[0]["active"]) and int(t1[0]["tick"]) + 1 == int(t2[0]["tick"]), "台風は、一定の間隔でダメージが入る")
	check(not bool(Attacks.hazards(ty, float(tk["duration"]) - 0.1, cfg, ctx)[0]["active"]), "台風の終わりは、当たらない")

	# チラシ：同じ種なら同じ飛び方。種が違えば違う
	var fl := {"n": 2, "kind": "flyers", "start": 0.0, "end": 6.0}
	var fa := Attacks.hazards(fl, 2.0, cfg, ctx)
	var fb := Attacks.hazards(fl, 2.0, cfg, ctx)
	check(fa.size() > 0 and fa.size() == fb.size() and is_equal_approx(float(fa[0]["x"]), float(fb[0]["x"])), "チラシは、全員の画面で同じ")
	var ctx2 := ctx.duplicate(true)
	ctx2["round_start_ms"] = 999999.0
	var fc := Attacks.hazards(fl, 2.0, cfg, ctx2)
	var diff := false
	for i in mini(fa.size(), fc.size()):
		if not is_equal_approx(float(fa[i]["x"]), float(fc[i]["x"])):
			diff = true
	check(diff, "戦いが変われば、チラシの向きも変わる")
	check(not bool(fa[0]["jumpable"]), "チラシは、ジャンプではよけられない")

	# 必殺技A
	var st := {"n": 9, "kind": "flyer_storm", "start": 0.0, "end": 10.0}
	var sk: Dictionary = cfg["kinds"]["flyer_storm"]
	var mx := 0
	var saw_active := false
	var saw_tele := false
	for u100 in range(0, 1000, 10):
		var hs := Attacks.hazards(st, float(u100) / 100.0, cfg, ctx)
		mx = maxi(mx, hs.size())
		for h in hs:
			if bool(h["active"]):
				saw_active = true
			else:
				saw_tele = true
			check(float(h["x"]) >= float(sk["area_x"][0]) and float(h["x"]) <= float(sk["area_x"][1]), "落ちる場所は範囲の中")
	check(mx >= 3 and saw_active and saw_tele, "必殺技Aは、たくさん・予告つきで落ちる")

	# 必殺技B
	var sw := {"n": 10, "kind": "hand_sweep", "start": 0.0, "end": 10.0}
	var wk: Dictionary = cfg["kinds"]["hand_sweep"]
	var e := Attacks.hazards(sw, 0.5, cfg, ctx)
	check(e.size() == 1 and not bool(e[0]["active"]) and str(e[0]["shape"]) == "box", "手の通り道が、先に帯で出る")
	var per := float(wk["telegraph_sec"]) + float(wk["pass_sec"]) + float(wk["gap_sec"])
	var xs: Array = []
	for p in 3:
		var u := p * per + float(wk["telegraph_sec"]) + float(wk["pass_sec"]) * 0.5
		var hs := Attacks.hazards(sw, u, cfg, ctx)
		check(hs.size() == 1 and bool(hs[0]["active"]) and absf(float(hs[0]["x"])) < 1.0, "手は、%d回めに画面の真ん中を通る" % (p + 1))
		var u2 := p * per + float(wk["telegraph_sec"]) + float(wk["pass_sec"]) * 0.1
		xs.append(float(Attacks.hazards(sw, u2, cfg, ctx)[0]["x"]))
	check(xs[0] < 0.0 and xs[1] > 0.0 and xs[2] < 0.0, "手は、左右交互に走る（3回）")
	check(Attacks.hazards(sw, 3.0 * per + 0.1, cfg, ctx).is_empty(), "3回で終わる")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

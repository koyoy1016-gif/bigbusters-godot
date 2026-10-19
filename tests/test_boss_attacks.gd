extends SceneTree
## ボスの攻撃5つの計算（予定表、つかみ、台風、チラシ、必殺技A・B）のテスト

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
var failures := 0


func check(ok: bool, name: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", name)


func _init() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_attacks.json"))
	var cfg := Attacks.load_config()
	var sp := float(raw["attack_speed"])
	check(sp >= 1.4, "攻撃の速さは1.5倍前後")
	check(is_equal_approx(float(cfg["kinds"]["bat_h"]["windup_sec"]), float(raw["kinds"]["bat_h"]["windup_sec"]) / sp), "速さの倍率で、予告の時間が短くなる")
	check(is_equal_approx(float(cfg["kinds"]["grab"]["hold_min_sec"]), float(raw["kinds"]["grab"]["hold_min_sec"])), "つかむ時間は、速さで変えない")
	check(is_equal_approx(float(cfg["kinds"]["bat_spin"]["spin_deg_per_sec"]), float(raw["kinds"]["bat_spin"]["spin_deg_per_sec"]) * sp), "回る速さは上がる")
	var sched := Attacks.build_schedule(cfg)
	check(sched.size() > 10, "予定表ができる")
	var normal_kinds := {}
	for a in sched:
		normal_kinds[str(a["kind"])] = true
	check(normal_kinds.has("bat_h") and normal_kinds.has("bat_v") and normal_kinds.has("bat_spin") and normal_kinds.has("tail_spin") and normal_kinds.has("walk_swing") and normal_kinds.has("grab"), "平常時は、バットの技4つ＋しっぽ回し＋つかみ")
	check(not normal_kinds.has("flyers") and not normal_kinds.has("flyer_storm") and not normal_kinds.has("hand_sweep"), "平常時は、チラシ・必殺技を使わない")
	var awake := Attacks.build_schedule(cfg, "awake_cycle")
	var ults := 0
	var seen := {}
	for a in awake:
		seen[str(a["kind"])] = true
		check(int(a["n"]) > 10000, "覚醒の攻撃の番号は、平常時と重ならない")
		if str(a["kind"]) in ["flyer_storm", "hand_sweep"]:
			ults += 1
			check(float(a["start"]) >= float(cfg["ultimate_first_sec"]), "必殺技は決めた時刻より前に出ない")
	check(ults >= 2 and seen.has("flyers") and seen.has("typhoon") and seen.has("grab") and not seen.has("bat_h"), "覚醒時は、チラシ・台風・つかみ・必殺技（バットは持たない）")
	for i in sched.size() - 1:
		check(float(sched[i]["end"]) < float(sched[i + 1]["start"]), "攻撃が重ならない")
	check(Attacks.active_index(sched, 0.5) == -1, "最初の待ち時間は攻撃なし")
	check(Attacks.active_index(sched, float(cfg["first_delay_sec"]) + 0.1) == 0, "待ち時間のあとは1つめの攻撃")

	var members := ["p2", "p1", "p3"]
	check(Attacks.grab_target(1, members) == "p1" and Attacks.grab_target(2, members) == "p2" and Attacks.grab_target(4, members) == "p1", "つかみの的は枠の順にまわる")
	var ctx := {"boss": Vector2(2, 2), "members": members, "positions": {"p1": Vector2(3, 4), "p2": Vector2(-5, 2), "p3": Vector2(0, 0)}, "locked": null, "round_start_ms": 123456.0, "bounds": 14.0}

	# つかみ
	var g: Dictionary = {}
	for a in sched:
		if str(a["kind"]) == "grab":
			g = a
			break
	g = g.duplicate()
	g["n"] = 1
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

	# つかみの輪は、ボスの手が届く所まで
	var far_ctx := ctx.duplicate(true)
	far_ctx["boss"] = Vector2(0, -8)
	var hf: Array = Attacks.hazards(g, 0.2, cfg, far_ctx)
	check(Vector2(float(hf[0]["x"]), float(hf[0]["z"])).distance_to(Vector2(0, -8)) <= float(gk["reach"]) + 0.01, "遠くの人には、つかみの輪は届かない")

	# ---- バットの技・しっぽ回し・歩きながら振る（向き yaw つき） ----
	var bctx := {"boss": Vector2(0, 0), "yaw": 0.0, "members": members, "positions": {}, "locked": null, "round_start_ms": 1.0, "bounds": 14.0}
	var bh := {"n": 5, "kind": "bat_h", "start": 0.0, "end": 2.0}
	var bk: Dictionary = cfg["kinds"]["bat_h"]
	var h_t: Array = Attacks.hazards(bh, 0.1, cfg, bctx)
	check(h_t.size() == 1 and str(h_t[0]["shape"]) == "sector" and not bool(h_t[0]["active"]), "横振り：はじめは、扇の予告（当たらない）")
	var h_a: Array = Attacks.hazards(bh, float(bk["windup_sec"]) + 0.02, cfg, bctx)
	check(bool(h_a[0]["active"]), "横振り：予告のあとで当たる")
	check(Attacks.inside(h_a[0], 0.0, 4.0) and not Attacks.inside(h_a[0], 0.0, -4.0), "横振り：前は当たり、うしろは安全")
	var turned := bctx.duplicate()
	turned["yaw"] = PI * 0.5
	var h_r: Array = Attacks.hazards(bh, float(bk["windup_sec"]) + 0.02, cfg, turned)
	check(Attacks.inside(h_r[0], 4.0, 0.0) and not Attacks.inside(h_r[0], -4.0, 0.0), "横振り：ボスの向き（右を向く）に合わせて扇も回る")
	check(Attacks.hazards(bh, float(bk["windup_sec"]) + float(bk["swing_sec"]) + 0.05, cfg, bctx).is_empty(), "横振り：振り終わると当たりは消える")
	var bv := {"n": 6, "kind": "bat_v", "start": 0.0, "end": 2.0}
	var vk: Dictionary = cfg["kinds"]["bat_v"]
	var hv: Array = Attacks.hazards(bv, float(vk["windup_sec"]) + 0.01, cfg, bctx)
	check(str(hv[0]["shape"]) == "obox" and bool(hv[0]["active"]), "縦振り：前へのびる帯")
	check(Attacks.inside(hv[0], 0.0, 5.0) and not Attacks.inside(hv[0], 3.0, 5.0) and not bool(hv[0]["jumpable"]), "縦振り：帯の中だけ当たる。ジャンプではよけられない")
	var bs := {"n": 7, "kind": "bat_spin", "start": 0.0, "end": 3.0}
	var sk2: Dictionary = cfg["kinds"]["bat_spin"]
	var s1: Array = Attacks.hazards(bs, float(sk2["windup_sec"]) + 0.05, cfg, bctx)
	var s2b: Array = Attacks.hazards(bs, float(sk2["windup_sec"]) + 0.05 + float(sk2["tick_sec"]), cfg, bctx)
	check(bool(s1[0]["active"]) and int(s1[0]["tick"]) + 1 == int(s2b[0]["tick"]), "回転斬り：回っている間、続けて当たる")
	var ts := {"n": 8, "kind": "tail_spin", "start": 0.0, "end": 2.0}
	var tk2: Dictionary = cfg["kinds"]["tail_spin"]
	var ht: Array = Attacks.hazards(ts, float(tk2["windup_sec"]) + 0.05, cfg, bctx)
	check(str(ht[0]["shape"]) == "ring" and Attacks.inside(ht[0], 0.0, 4.0) and not Attacks.inside(ht[0], 0.0, 1.0), "しっぽ回し：輪の中は当たり、体のすぐそばは安全")
	var ws := {"n": 9, "kind": "walk_swing", "start": 0.0, "end": 4.0}
	var wk2: Dictionary = cfg["kinds"]["walk_swing"]
	var first_hit := Attacks.swing_time(0, wk2)
	var last_hit := Attacks.swing_time(int(wk2["swings"]) - 1, wk2)
	var w0: Array = Attacks.hazards(ws, first_hit + 0.01, cfg, bctx)
	var w2: Array = Attacks.hazards(ws, last_hit + 0.01, cfg, bctx)
	check(w0.size() >= 1 and bool(w0[0]["active"]) and w2.size() >= 1, "歩きながら振る：何回も振る")
	check(float(w2[0]["z"]) > float(w0[0]["z"]) + 0.5, "歩きながら振る：前へ進みながら振る")
	check(not bool(Attacks.hazards(ws, first_hit - 0.1, cfg, bctx)[0]["active"]), "歩きながら振る：振る前に、当たる扇が出る")
	# チラシ：投げる前に、飛ぶ扇の予告が出る（予告そのものは当たらない）
	var flt: Array = Attacks.hazards({"n": 2, "kind": "flyers", "start": 0.0, "end": 6.0}, 0.2, cfg, ctx)
	check(flt.size() >= 1 and str(flt[0]["shape"]) == "sector" and float(flt[0]["power"]) == 0.0, "チラシ：投げる前に、扇の予告が出る")
	# つかむ時間：毎回 1〜3秒のどれか。同じ戦い・同じ番号なら、全員の画面で同じ
	var holds := {}
	for n2 in range(1, 30):
		var hs2 := Attacks.grab_hold_sec(cfg, 5555.0, n2)
		check(hs2 >= 1.0 and hs2 <= 3.0, "つかむ時間は1〜3秒")
		holds[snappedf(hs2, 0.1)] = true
	check(holds.size() > 5 and is_equal_approx(Attacks.grab_hold_sec(cfg, 5555.0, 3), Attacks.grab_hold_sec(cfg, 5555.0, 3)), "つかむ時間は毎回ちがい、同じ番号なら同じ")
	# AIのよけ方：扇・輪・帯からも逃げる向きが出る
	var e1 := Attacks.escape_of(h_a[0], 0.0, 3.0, 0.5)
	check(float(e1["depth"]) > 0.0 and (e1["dir"] as Vector2).length() > 0.5, "扇の中にいると、逃げる向きが出る")
	var e2 := Attacks.escape_of(ht[0], 0.0, 3.0, 0.5)
	check(float(e2["depth"]) > 0.0, "輪の中にいると、逃げる向きが出る")
	check(float(Attacks.escape_of(h_a[0], 0.0, -5.0, 0.5)["depth"]) <= 0.0, "扇のうしろは、逃げなくてよい")

	# ---- ボスの歩き ----
	var Motion := load("res://scripts/combat/boss_motion.gd")
	var mo = Motion.new()
	mo.reset(Vector2(0, -6))
	var mctx := {"members": ["p1"], "positions": {"p1": Vector2(0, 8)}}
	var next := {"n": 1, "kind": "bat_h", "start": 5.0, "end": 7.0}
	for i in 120:
		mo.update(1.0 / 60.0, {}, 0.0, next, cfg, mctx)
	check(mo.pos.y > -6.0 + 2.0 and mo.speed_now > 1.0, "攻撃の間は、ねらう人のほうへ歩く")
	for i in 400:
		mo.update(1.0 / 60.0, {}, 0.0, next, cfg, mctx)
	check(absf(mo.pos.distance_to(Vector2(0, 8)) - float(cfg["kinds"]["bat_h"]["stop_dist"])) < 0.3, "ねらう人の手前（技ごとの距離）で止まる")
	check(absf(mo.yaw) < 0.1, "ねらう人のほうを向く")
	mctx["positions"]["p1"] = Vector2(8, mo.pos.y)
	mo.update(1.0 / 60.0, next, 0.0, {}, cfg, mctx)
	var lk: Dictionary = mo.lock_of(1)
	check(absf(float(lk["yaw"]) - PI * 0.5) < 0.05, "攻撃の始まりで、ねらう人へ向きを固定する")
	var p_before: Vector2 = mo.pos
	mo.update(1.0 / 60.0, next, 0.1, {}, cfg, {"members": ["p1"], "positions": {"p1": Vector2(-9, -9)}})
	check(mo.pos.distance_to(p_before) < 0.05 and is_equal_approx(float(mo.lock_of(1)["yaw"]), float(lk["yaw"])), "攻撃中は、ねらう人が動いても向きは変わらない")
	mo.update(1.0 / 60.0, {}, 0.0, next, cfg, mctx, true)
	check(mo.speed_now == 0.0, "よろけ中は動かない")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

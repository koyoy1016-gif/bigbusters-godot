extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_new_attacks.gd
## 版61の新しい攻撃：移動ジャンプ落下（jump_move）と、回転バット移動（spin_bat）を確かめる。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var cfg := Attacks.load_config()
	var jk: Dictionary = cfg["kinds"]["jump_move"]
	var sk: Dictionary = cfg["kinds"]["spin_bat"]
	var sp := float(cfg.get("attack_speed", 1.0))

	# ---- 移動ジャンプ落下 ----
	check(is_equal_approx(float(jk["power"]), 18.0), "移動ジャンプ落下：ダメージ18")
	var lands := {}
	var dist_ok := true
	var moved_ok := true
	for n in range(1, 13):
		var ctx := {"boss": Vector2(0, -4), "yaw": 0.0, "target": Vector2(3, 6), "round_start_ms": 5000.0, "n": n, "area": 13.0}
		var land := Attacks.jump_move_land(jk, ctx)
		lands["%.1f,%.1f" % [land.x, land.y]] = true
		var d := (land - Vector2(0, -4)).length()
		dist_ok = dist_ok and d <= float(jk["max_jump"]) + 0.01
		moved_ok = moved_ok and d >= float(jk["min_jump"]) - 0.01
	check(dist_ok, "移動ジャンプ落下：飛ぶのは最大10mまで")
	check(moved_ok, "移動ジャンプ落下：真上ではなく、はなれた所へ動く（%.0fm 以上）" % float(jk["min_jump"]))
	check(lands.size() >= 8, "移動ジャンプ落下：着地点は毎回少しずつ変わる（12回で %d か所）" % lands.size())
	var ctx1 := {"boss": Vector2(0, -4), "yaw": 0.0, "target": Vector2(3, 6), "round_start_ms": 5000.0, "n": 3, "area": 13.0}
	var land1 := Attacks.jump_move_land(jk, ctx1)
	var land_t := float(jk["crouch_sec"]) + float(jk["air_sec"])
	var mid := Attacks.jump_move_at(float(jk["crouch_sec"]) + float(jk["air_sec"]) * 0.5, jk, ctx1)
	var end := Attacks.jump_move_at(land_t + 0.05, jk, ctx1)
	check(float(mid["y"]) > 2.0 and (mid["pos"] as Vector2).distance_to(Vector2(0, -4)) > 1.0, "移動ジャンプ落下：空中で、高く跳びながら移動する")
	check((end["pos"] as Vector2).is_equal_approx(land1) and float(end["y"]) == 0.0, "移動ジャンプ落下：予告の所に着地する")
	var a := {"kind": "jump_move", "n": 3}
	var pre: Array = Attacks.hazards(a, 0.1, cfg, ctx1)
	var at_land: Array = Attacks.hazards(a, land_t + 0.01, cfg, ctx1)
	var after: Array = Attacks.hazards(a, land_t + float(jk["hit_sec"]) + 0.05, cfg, ctx1)
	check(pre.size() == 1 and not bool(pre[0]["active"]) and (Vector2(float(pre[0]["x"]), float(pre[0]["z"]))).is_equal_approx(land1), "移動ジャンプ落下：着地点に、はじめから予告の円が出る")
	check(str(pre[0]["shape"]) == "circle" and str(pre[0]["style"]) == "zone", "移動ジャンプ落下：予告はオレンジの円（ふつうの攻撃の予告）")
	check(at_land.size() == 1 and bool(at_land[0]["active"]) and int(at_land[0]["tick"]) == -1, "移動ジャンプ落下：着地で1回だけ当たる（衝撃波なし・二重に当たらない）")
	check(after.is_empty(), "移動ジャンプ落下：着地のあとは、もう当たらない")

	# ---- 回転バット移動 ----
	check(is_equal_approx(float(sk["power"]), 9.0), "回転バット移動：ダメージ9／ヒット")
	var ctx2 := {"boss": Vector2(0, 0), "yaw": 0.0, "target": Vector2(0, 10), "round_start_ms": 5000.0, "n": 4, "area": 13.0}
	var b := {"kind": "spin_bat", "n": 4}
	var w := float(sk["windup_sec"])
	var run := float(sk["run_sec"])
	var no_tele := true
	var u := 0.0
	while u < w:
		no_tele = no_tele and Attacks.hazards(b, u, cfg, ctx2).is_empty()
		u += 0.05
	check(no_tele, "回転バット移動：事前の予告は出さない")
	var s0 := Attacks.spin_bat_at(w, sk, ctx2)
	var s1 := Attacks.spin_bat_at(w + run * 0.5, sk, ctx2)
	var s2 := Attacks.spin_bat_at(w + run, sk, ctx2)
	check((s2["pos"] as Vector2).y > (s0["pos"] as Vector2).y + 3.0 and absf((s2["pos"] as Vector2).x) < 0.01, "回転バット移動：ねらう人のほうへ、まっすぐ前進する")
	check(float(s1["spin"]) - float(s0["spin"]) > TAU * 1.0, "回転バット移動：体ごと、ぐるぐる回る（半分の時間で %.1f 回転）" % ((float(s1["spin"]) - float(s0["spin"])) / TAU))
	var hz: Array = Attacks.hazards(b, w + run * 0.5, cfg, ctx2)
	check(hz.size() == 1 and bool(hz[0]["active"]) and Vector2(float(hz[0]["x"]), float(hz[0]["z"])).is_equal_approx(s1["pos"]), "回転バット移動：当たりの丸は、動いているボスについていく")
	check(is_equal_approx(float(hz[0]["r"]), float(sk["radius"])), "回転バット移動：当たりの丸は、バットの先まで（%.1fm）" % float(sk["radius"]))
	var ticks := {}
	u = w
	while u < w + run:
		for h in Attacks.hazards(b, u, cfg, ctx2):
			ticks[int(h["tick"])] = true
		u += 0.02
	check(ticks.size() == int(sk["max_ticks"]), "回転バット移動：同じ人へは、間をあけて最大 %d 回まで（%d）" % [int(sk["max_ticks"]), ticks.size()])
	check(Attacks.hazards(b, w + run + 0.05, cfg, ctx2).is_empty(), "回転バット移動：止まったら、もう当たらない")
	check(sk.has("spin_deg_per_sec") and (cfg["kinds"] as Dictionary).has("spin_charge"), "回転突進は残っている（別の攻撃）")

	# ---- AI に入っている ----
	var ai := BossAI.new()
	ai.reset(cfg, 0.0)
	var cn: Dictionary = ai.candidate_weights(20.0, "normal", 8.0)
	var ca: Dictionary = ai.candidate_weights(20.0, "awake", 8.0)
	check(cn.has("jump_move") and cn.has("spin_bat") and ca.has("jump_move") and ca.has("spin_bat"), "新しい2つの攻撃は、平常・覚醒の両方で選ばれる")

	# ---- 戦いの画面：最後まで動いて、ふつうにもどる ----
	var sc: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(sc)
	if sc.get_node_or_null("Boss") == null:
		sc._ready()
	var now := [7000000.0]
	sc.clock_ms = func() -> float: return now[0]
	sc.sfx = null
	sc.ai_enabled = false
	sc.start_round()
	for kind in ["jump_move", "spin_bat"]:
		now[0] += 3000.0
		sc.combat_update(0.02)
		var fa: Dictionary = sc.force_attack(kind)
		var t := float(fa["start"])
		var start_pos: Vector2 = sc.motion.pos
		var max_h := 0.0
		var spun := 0.0
		var hid := true
		while t < float(fa["end"]) + 1.0:
			t += 0.03
			now[0] = sc.round_start_ms + t * 1000.0
			sc.player.position = Vector3(40, sc.ground_y, 40)
			sc.combat_update(0.03)
			max_h = maxf(max_h, sc.motion.height)
			spun = maxf(spun, absf(sc.motion.path_spin))
			for i in sc.current_hazards.size():
				if str(sc.current_hazards[i]["style"]) == "spin_bat" and (sc.hazard_nodes[i] as Node3D).visible:
					hid = false
		var moved: float = (sc.motion.pos as Vector2).distance_to(start_pos)
		if kind == "jump_move":
			check(max_h > 2.0 and moved > 3.0, "画面：移動ジャンプ落下で、ボスが跳んで移動する（%.1fm）" % moved)
		else:
			check(spun > TAU * 2.0 and moved > 3.0, "画面：回転バット移動で、ボスが回りながら進む（%.1fm）" % moved)
			check(hid, "画面：回転バット移動は、床に予告も当たりの面も出さない")
		check(sc.current_attack.is_empty() or str(sc.current_attack.get("kind", "")) != kind, "画面：%s のあと、ふつうの動きにもどる" % kind)
	sc._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

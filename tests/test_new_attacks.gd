extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_new_attacks.gd
## 版61の新しい攻撃：移動ジャンプ落下（jump_move）を確かめる。回転バット移動（spin_bat）は版66で削除した（選ばれないことを確かめる）。

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

	# ---- AI に入っている ----
	var ai := BossAI.new()
	ai.reset(cfg, 0.0)
	var cn: Dictionary = ai.candidate_weights(20.0, "normal", 8.0)
	var ca: Dictionary = ai.candidate_weights(20.0, "awake", 8.0)
	check(cn.has("jump_move") and ca.has("jump_move"), "移動ジャンプ落下は、平常・覚醒の両方で選ばれる")
	check(not cfg["kinds"].has("spin_bat") and not cn.has("spin_bat") and not ca.has("spin_bat"), "回転バット移動は、平常・覚醒のどちらでも候補にない（版66で削除）")
	check(cfg["kinds"].has("bat_spin") and cfg["kinds"].has("spin_charge"), "回転斬り・回転突進は残っている")

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
	for kind in ["jump_move"]:
		now[0] += 3000.0
		sc.combat_update(0.02)
		var fa: Dictionary = sc.force_attack(kind)
		var t := float(fa["start"])
		var start_pos: Vector2 = sc.motion.pos
		var max_h := 0.0
		while t < float(fa["end"]) + 1.0:
			t += 0.03
			now[0] = sc.round_start_ms + t * 1000.0
			sc.player.position = Vector3(40, sc.ground_y, 40)
			sc.combat_update(0.03)
			max_h = maxf(max_h, sc.motion.height)
		var moved: float = (sc.motion.pos as Vector2).distance_to(start_pos)
		check(max_h > 2.0 and moved > 3.0, "画面：移動ジャンプ落下で、ボスが跳んで移動する（%.1fm）" % moved)
		check(sc.current_attack.is_empty() or str(sc.current_attack.get("kind", "")) != kind, "画面：%s のあと、ふつうの動きにもどる" % kind)
	sc._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_sake_fire.gd
## 酒瓶落とし（放物線で落ちて割れる → 酒だまり）と、火祭り（ライターで火がつき、つながった酒だまりへ燃えうつる）

const SakeField := preload("res://scripts/combat/sake_field.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	# 酒だまり：つながっている物へ、順に燃えうつる。はなれた物は燃えない
	var f := SakeField.new()
	f.add("a", Vector2(0, 0), 2.0, 0.0, 10.0, 0.0)
	f.add("b", Vector2(4.5, 0), 2.0, 0.0, 10.0, 0.0)
	f.add("c", Vector2(9.0, 0), 2.0, 0.0, 10.0, 0.0)
	f.add("far", Vector2(0, 20), 2.0, 0.0, 10.0, 0.0)
	f.add("a", Vector2(5, 5), 2.0, 0.0, 10.0, 0.0)
	check(f.alive(1.0).size() == 4, "酒だまりを作れる（同じ id は1つだけ）")
	var n := f.ignite("x", Vector2(-1, 0), 2.0, 3.0, 0.3, 2.0, 1.0)
	check(n == 3, "火は、つながっている酒だまりにだけ燃えうつる（%d こ）" % n)
	check(f.burning(2.05).size() == 1 and f.burning(2.35).size() == 2 and f.burning(2.65).size() == 3, "火は、となりへ順に、少しおくれて燃えうつる")
	check(f.burning(4.7).size() == 0, "しばらくすると、燃えおわる")
	var far_burns := false
	for p in f.puddles:
		if str(p["id"]) == "far" and float(p["burn_start"]) >= 0.0:
			far_burns = true
	check(not far_burns, "はなれた酒だまりは燃えない（安全な所）")
	check(f.ignite("y", Vector2(50, 50), 3.0, 3.0, 0.3, 2.0, 1.0) == 0, "近くに酒だまりがなければ、火はつかない")
	f.prune(11.0)
	check(f.alive(11.0).is_empty(), "時間がたつと、酒だまりは消える")
	var k: Dictionary = Attacks.load_config()["kinds"]["fire_fest"]
	var f2 := SakeField.new()
	f2.add("a", Vector2(0, 0), 2.0, 0.0, 10.0, 0.0)
	f2.add("b", Vector2(3, 0), 2.0, 0.0, 10.0, 0.0)
	f2.ignite("ev1", Vector2(0, 0), 1.0, 3.0, 0.2, 2.0, 1.0)
	var hz := Attacks.fire_hazards(f2, 1.5, k)
	var ids := {}
	for h in hz:
		if bool(h["active"]):
			ids[str(h["id"])] = true
	check(hz.size() == 2 and ids.size() == 1, "同じ火の事件の当たりは、同じ id（ダメージは1回だけ）")

	# 酒瓶：放物線（上がって落ちる）、落ちる所と当たりの場所が同じ
	var cfg := Attacks.load_config()
	var sk: Dictionary = cfg["kinds"]["sake_drop"]
	var ctx := {"boss": Vector2(0, 0), "yaw": 0.0, "members": [], "positions": {}, "locked": null, "round_start_ms": 7.0, "bounds": 15.0, "target": Vector2(2, 8), "area": 13.0}
	var a := {"n": 3, "kind": "sake_drop", "start": 0.0, "end": 9.0}
	var bs := Attacks.sake_bottles(a, sk, ctx)
	check(bs.size() == int(sk["bottles"]) and bs.size() >= 3 and bs.size() <= 5, "瓶は3〜5本（%d本）" % bs.size())
	check((bs[0]["to"] as Vector2).is_equal_approx(Vector2(2, 8)), "1本めは、ねらう人の所へ")
	var b0: Dictionary = bs[0]
	var mid: Vector3 = Attacks.bottle_pos(b0, (float(b0["throw"]) + float(b0["land"])) * 0.5, sk)
	var start_p: Vector3 = Attacks.bottle_pos(b0, float(b0["throw"]) + 0.01, sk)
	check(mid.y > start_p.y + 2.0, "瓶は、下から上へ投げられて、高く上がる（放物線）")
	check(float(b0["land"]) - float(b0["throw"]) >= 0.7, "落ちる所の予告は、0.7秒以上前から出る（%.2f秒）" % (float(b0["land"]) - float(b0["throw"])))
	var h_land: Array = Attacks.hazards(a, float(b0["land"]) + 0.01, cfg, ctx)
	var match_ok := false
	for h in h_land:
		if str(h["id"]) == str(b0["id"]) and bool(h["active"]) and Vector2(float(h["x"]), float(h["z"])).is_equal_approx(b0["to"]):
			match_ok = true
	check(match_ok, "瓶が割れる場所と、当たりの場所が同じ")

	# 戦いの画面で：火祭り
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [6000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.ai_enabled = false
	s.start_round()
	s.phase.phase = "awake"
	s.boss_model._apply_form("awake")
	now[0] += 10000.0
	# 版61：火祭りはAIから外し、酒だまりも残さない設定にした。ここでは、しくみ自体が動くかを、設定を戻して確かめる
	s.attacks_cfg["puddles_enabled"] = true
	var fa: Dictionary = s.force_attack("fire_fest")
	var fk: Dictionary = s.attacks_cfg["kinds"]["fire_fest"]
	# 安全な所（ボスのうしろ）に立つ
	var t := float(fa["start"])
	var saw_bottle := false
	var saw_fire := false
	var max_puddles := 0
	var hp0: float = s.my_hp
	while t < float(fa["end"]) - 0.05:
		t += 0.03
		now[0] = s.round_start_ms + t * 1000.0
		var lk: Dictionary = s.motion.lock_of(int(fa["n"]))
		var back: Vector2 = (lk["pos"] as Vector2) - Attacks.fwd_of(float(lk["yaw"])) * 6.0
		s.player.position = Vector3(back.x, s.ground_y, back.y)
		s.combat_update(0.03)
		for bn in s._bottle_nodes:
			if (bn as Node3D).visible:
				saw_bottle = true
		max_puddles = maxi(max_puddles, s.field.alive(t).size())
		if not s.field.burning(t).is_empty():
			saw_fire = true
	check(saw_bottle, "火祭り：酒瓶が飛んでいるのが見える")
	check(max_puddles >= int(fk["bottles"]), "火祭り：割れた所に酒だまりができる（%dこ）" % max_puddles)
	check(saw_fire, "火祭り：ライターで火がつき、燃える")
	check(s.my_hp == hp0, "火祭り：扇の外（ボスのうしろ）は安全")
	# 燃えている酒だまりの上では、1回だけダメージ
	s.my_hp = hp0
	s.hazard_done = {}
	s.kb_guard_left = 0.0
	s.actions.reset()
	s.field.clear()
	s.field.add("z1", Vector2(0, 0), 3.0, t, 10.0, 0.0)
	s.field.add("z2", Vector2(4, 0), 3.0, t, 10.0, 0.0)
	s.field.ignite("zz", Vector2(0, 0), t, 3.0, 0.1, 2.0, 1.0)
	s.player.position = Vector3(0, s.ground_y, 0)
	var hits := 0
	for i in 30:
		t += 0.03
		now[0] = s.round_start_ms + t * 1000.0
		var before: float = s.my_hp
		s.kb_guard_left = 0.0
		s.actions.reset()
		s.player.position = Vector3(2.0 if i % 2 == 0 else 0.0, s.ground_y, 0)
		s.combat_update(0.03)
		if s.my_hp < before:
			hits += 1
	check(hits == 1, "同じ火では、ダメージは1回だけ（%d回）" % hits)
	# 倒したら、火・酒だまりは残らない
	s.my_hits = 99999.0
	s.phase.phase = "awake"
	s.phase.awake_base = 0.0
	s._recompute_boss_hp()
	check(s.won and s.field.alive(t).is_empty(), "倒したら、火・酒だまりは消える")
	# 版61：いまのデータでは、酒瓶落としで酒だまりが残らない
	var s2: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s2)
	if s2.get_node_or_null("Boss") == null:
		s2._ready()
	var now2 := [9000000.0]
	s2.clock_ms = func() -> float: return now2[0]
	s2.sfx = null
	s2.ai_enabled = false
	s2.start_round()
	s2.phase.phase = "awake"
	s2.boss_model._apply_form("awake")
	now2[0] += 10000.0
	check(not s2.puddles_enabled(), "いまのデータでは、酒だまりを残さない")
	var da: Dictionary = s2.force_attack("sake_drop")
	var t2 := float(da["start"])
	var puddle_max := 0
	var wet_seen := false
	while t2 < float(da["end"]) + 0.5:
		t2 += 0.05
		now2[0] = s2.round_start_ms + t2 * 1000.0
		s2.player.position = Vector3(40, s2.ground_y, 40)
		s2.combat_update(0.05)
		puddle_max = maxi(puddle_max, s2.field.alive(t2).size())
		for w in s2.puddles:
			if (w as Node3D).visible:
				wet_seen = true
	check(puddle_max == 0 and not wet_seen, "酒瓶落としのあと、床に酒だまりが残らない")
	s2._exit_tree()
	s._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

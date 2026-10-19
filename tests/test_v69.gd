extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v69.gd
## 版69：つかまれたら1秒（版70で、逃げる仕組みはなくした）。
## ボスの怒り：ボスの体から3m以内で当たった攻撃が、直前の5秒に20回以上ある間は怒る。
## 怒っている間は、つかみ投げの重みが2倍、始まる攻撃が1.25倍の速さ（必殺技は除く）。通信中は怒らない。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const BossRage := preload("res://scripts/combat/boss_rage.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make_scene(ai_on: bool = false) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = ai_on
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [6000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.set_meta("now", now)
	s.sfx = null
	s.start_round()
	return s


func step(s: Node, t: float, dt: float = 0.05) -> float:
	var now: Array = s.get_meta("now")
	t += dt
	now[0] = s.round_start_ms + t * 1000.0
	s.combat_update(dt)
	s._pose_boss(dt)
	return t


func _initialize() -> void:
	var acfg := Attacks.load_config()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_attacks.json"))
	var k: Dictionary = acfg["kinds"]["grab"]

	# ---- 1. つかまれたら1秒 ----
	check(is_equal_approx(float(k["hold_min_sec"]), 1.0) and is_equal_approx(float(k["hold_max_sec"]), 1.0), "つかむ時間は1秒（速さの1.5倍でも変えない）")
	check(is_equal_approx(float(k["quick_hold_sec"]), 0.25), "剣士をすぐ投げるつかみは、そのまま（0.25秒で投げる）")
	# 「にげる」7回は版70で消した（必ず投げられる。tests/test_v70.gd）

	# ---- 2. 怒りの数え方（boss_rage.gd） ----
	var rc: Dictionary = raw["ai"]["rage"]
	check(is_equal_approx(float(rc["near_m"]), 3.0) and is_equal_approx(float(rc["window_sec"]), 5.0) and int(rc["hits"]) == 20, "怒る条件：ボスの体から3m以内・5秒の間に20回")
	check(is_equal_approx(float(rc["speed"]), 1.25) and is_equal_approx(float(rc["grab_mult"]), 2.0) and not bool(rc["online"]), "怒ると：攻撃の速さ1.25倍・つかみ投げの重み2倍。通信中は怒らない")
	check(is_equal_approx(float(acfg["ai"]["rage"]["window_sec"]), 5.0), "怒りの5秒は、攻撃の速さ1.5倍で短くならない")
	var r := BossRage.new()
	r.setup(rc)
	for i in 19:
		r.add_hit(10.0 + i * 0.2, 1.0)
	check(r.count(13.8) == 19 and not r.is_angry(13.8), "5秒で19回では、怒らない")
	r.add_hit(13.9, 3.5)
	check(r.count(13.9) == 19, "ボスの体から3mより遠い当たりは、数えない")
	r.add_hit(14.0, 3.0)
	check(r.count(14.0) == 20 and r.is_angry(14.0), "20回目（3mちょうど）で怒る")
	check(r.is_angry(14.9), "まだ5秒の中に20回ある間は、怒ったまま")
	check(not r.is_angry(15.05), "5秒より古い当たりが外れて20回を下回ると、すぐ元にもどる")
	var r2 := BossRage.new()
	r2.setup(rc)
	r2.enabled = false
	for i in 30:
		r2.add_hit(1.0 + i * 0.1, 0.5)
	check(not r2.is_angry(4.0), "通信中（enabled が false）は、何回当たっても怒らない")

	# ---- 3. くじ：怒っているとつかみ投げが2倍 ----
	var ai := BossAI.new()
	ai.reset(acfg, 1000.0)
	for kind in acfg["kinds"]:
		(ai.used["normal"] as Dictionary)[kind] = true  # まだの攻撃を先に出す決まりを外して比べる
	ai.angry = false
	var w0 := ai.candidate_weights(10.0, "normal", 3.0)
	ai.angry = true
	var w1 := ai.candidate_weights(10.0, "normal", 3.0)
	check(w0.has(Attacks.GRAB) and is_equal_approx(float(w1[Attacks.GRAB]), float(w0[Attacks.GRAB]) * 2.0), "怒っていると、つかみ投げの重みが2倍（%.2f → %.2f）" % [float(w0.get(Attacks.GRAB, 0.0)), float(w1.get(Attacks.GRAB, 0.0))])
	var others_same := true
	for kind in w0:
		if kind != Attacks.GRAB and not is_equal_approx(float(w0[kind]), float(w1.get(kind, -1.0))):
			others_same = false
	check(others_same, "ほかの攻撃の重みは変わらない")

	# ---- 4. くじ：怒っている間に始まる攻撃は1.25倍の速さ（必殺技は除く） ----
	var ai2 := BossAI.new()
	ai2.reset(acfg, 1000.0)
	ai2.angry = true
	ai2.request("bat_h")
	ai2.update(10.0, "normal", func(_n: int) -> float: return 3.0)
	var c1: Dictionary = ai2.current()
	var d1 := float(acfg["kinds"]["bat_h"]["duration"])
	check(not c1.is_empty() and is_equal_approx(float(c1["speed"]), 1.25) and is_equal_approx(float(c1["end"]) - float(c1["start"]), d1 / 1.25), "怒っていると、横振りの長さが1.25分の1（%.2f → %.2f 秒）" % [d1, float(c1.get("end", 0.0)) - float(c1.get("start", 0.0))])
	var ai3 := BossAI.new()
	ai3.reset(acfg, 1000.0)
	ai3.angry = false
	ai3.request("bat_h")
	ai3.update(10.0, "normal", func(_n: int) -> float: return 3.0)
	check(is_equal_approx(float(ai3.current()["speed"]), 1.0) and is_equal_approx(float(ai3.current()["end"]) - float(ai3.current()["start"]), d1), "怒っていなければ、ふつうの速さ")
	for ult in [Attacks.BOTTLE_RIDE, Attacks.FLYER_STORM]:
		var ai4 := BossAI.new()
		ai4.reset(acfg, 1000.0)
		ai4.angry = true
		ai4.request(ult)
		ai4.update(10.0, "awake", func(_n: int) -> float: return 3.0)
		var cu: Dictionary = ai4.current()
		var full := Attacks.attack_duration(ult, acfg["kinds"][ult], int(cu["n"]), 1000.0)
		check(is_equal_approx(float(cu["speed"]), 1.0) and is_equal_approx(float(cu["end"]) - float(cu["start"]), full), "必殺技（%s）は、怒っていても速くしない" % ult)

	# ---- 5. 戦いの中：怒ると、攻撃の中の秒が1.25倍で進む ----
	var b := make_scene()
	var t := 0.0
	while b.ai.current().is_empty() and t < 10.0:
		t = step(b, t)
	check(not b.ai.current().is_empty() and is_equal_approx(float(b.ai.current().get("speed", 1.0)), 1.0), "怒っていない最初の攻撃は、ふつうの速さ")
	# 近くから25回当たったことにする → 怒る。次に始まる攻撃は速い
	for i in 25:
		b.rage.add_hit(t, 1.0)
	check(b.boss_angry(), "近くから25回当たると、ボスが怒る")
	var first_n := int(b.ai.current()["n"])
	while (b.ai.current().is_empty() or int(b.ai.current()["n"]) == first_n) and t < 30.0:
		for i in 2:
			b.rage.add_hit(t, 1.0)  # 当て続けて、怒ったままにする
		t = step(b, t)
	var ca: Dictionary = b.ai.current()
	var sp_ok := not ca.is_empty() and is_equal_approx(float(ca.get("speed", 1.0)), 1.0 if bool(((acfg["kinds"][str(ca["kind"])] as Dictionary).get("ai", {}) as Dictionary).get("ultimate", false)) else 1.25)
	check(sp_ok, "怒っている間に始まった攻撃（%s）は1.25倍の速さ" % str(ca.get("kind", "")))
	t = step(b, t)
	t = step(b, t)
	var want_u := (t - float(b.ai.current()["start"])) * float(b.ai.current()["speed"])
	check(absf(float(b.current_attack_u) - want_u) < 0.001, "攻撃の中の秒 u が、speed 倍で進む（u %.3f）" % float(b.current_attack_u))
	# 自分の攻撃：ボスの近くで当てると数える
	b.rage.reset()
	b.player.position = Vector3(b.boss.position.x, b.ground_y, b.boss.position.z + float(b.config["boss_size"]) * 0.5 + 1.0)
	b.actions.reset()
	b.stun_left = 0.0
	b.downed = false
	b.grab_state = {}
	var hits0: float = b.my_hits
	b._resolve_hit({"multiplier": 1.0, "radius_scale": 1.0, "cleave": false})
	check(b.my_hits > hits0 and b.rage.count(b._round_t()) == 1, "自分の攻撃がボスの近くで当たると、怒りに数える")
	check(absf(b._dist_to_boss_surface(Vector2(b.player.position.x, b.player.position.z)) - 1.0) < 0.01, "ボスの体の表面までの距離を測れる（1.0m）")
	root.remove_child(b)
	b.free()

	# ---- 6. AIの味方の攻撃も数える ----
	var c := make_scene(true)
	var t2 := 0.0
	var counted := false
	while t2 < 40.0 and not counted:
		t2 = step(c, t2)
		counted = c.rage.count(t2) > 0
	check(counted, "AIの味方がボスの近くで当てた攻撃も、怒りに数える（%.1f 秒で）" % t2)
	root.remove_child(c)
	c.free()

	print("")
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

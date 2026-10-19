extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v67.gd
## 版67：形態ごとに、使える攻撃を最低1回は出す（まだの攻撃を先に）。消した攻撃・知らない攻撃は出さずに切りかえる。
## 巨大酒瓶ライドの瓶は12本・落ちる範囲は半径3.125。（つかみ投げは tests/test_throw_collide.gd）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func usable(cfg: Dictionary, form: String) -> Array:
	var out: Array = []
	for kind in cfg["kinds"]:
		var ai: Dictionary = (cfg["kinds"][kind] as Dictionary).get("ai", {})
		if float((ai.get("forms", {}) as Dictionary).get(form, 0.0)) > 0.0 and not bool(ai.get("removed", false)):
			out.append(str(kind))
	out.sort()
	return out


func _initialize() -> void:
	var cfg := Attacks.load_config()
	var normal := usable(cfg, "normal")
	var awake := usable(cfg, "awake")
	check(not normal.has("spin_bat") and not awake.has("spin_bat") and normal.has("bat_spin") and normal.has("spin_charge"), "回転バット移動は使える攻撃にない。回転斬り・回転突進はある")
	print("     平常で使える攻撃 %d：%s" % [normal.size(), str(normal)])
	print("     覚醒で使える攻撃 %d：%s" % [awake.size(), str(awake)])

	# ---- 平常：はじめの数回で、全部の攻撃が1回ずつ出る（距離はいろいろ） ----
	var all_ok := true
	for seed in [1.0, 77.0, 9999.0, 3.1e6, 8.0e7]:
		var ai := BossAI.new()
		ai.reset(cfg, seed)
		var seen := []
		var t := 0.0
		var dists := [2.0, 6.0, 11.0, 16.0]
		while seen.size() < normal.size() and t < 200.0:
			t += 0.1
			ai.update(t, "normal", func(n: int) -> float: return float(dists[n % dists.size()]))
			var k := str(ai.current().get("kind", ""))
			if k != "" and not seen.has(k):
				seen.append(k)
		var first_n := seen.size()
		seen.sort()
		all_ok = all_ok and seen == normal and ai.n <= normal.size() + 2
		if not all_ok:
			print("  seed=%s 出た %s（攻撃 %d 回）" % [seed, str(seen), ai.n])
	check(all_ok, "平常：使える攻撃 %d 種類が、ほぼはじめの %d 回で全部出る（5つの乱数）" % [normal.size(), normal.size()])

	# ---- 覚醒：必殺技の待ち時間（はじめ8秒・あいだ24秒）を守りながら、全部出る ----
	var aw_ok := true
	var ult_gap_ok := true
	for seed in [2.0, 555.0, 7.7e6]:
		var ai2 := BossAI.new()
		ai2.reset(cfg, seed)
		ai2.on_awake(0.0)
		var seen2 := []
		var t2 := 0.0
		var last_ult := -999.0
		var cur_n := -1
		while t2 < 300.0:
			t2 += 0.1
			ai2.update(t2, "awake", func(_n: int) -> float: return 7.0)
			var c: Dictionary = ai2.current()
			if c.is_empty() or int(c["n"]) == cur_n:
				continue
			cur_n = int(c["n"])
			var k2 := str(c["kind"])
			if not seen2.has(k2):
				seen2.append(k2)
			if bool(((cfg["kinds"][k2] as Dictionary).get("ai", {}) as Dictionary).get("ultimate", false)):
				if float(c["start"]) < 8.0 or float(c["start"]) - last_ult < 24.0:
					ult_gap_ok = false
				last_ult = float(c["end"])
		seen2.sort()
		aw_ok = aw_ok and seen2 == awake
		if seen2 != awake:
			print("  seed=%s 覚醒で出なかった：%s" % [seed, str(awake.filter(func(x): return not seen2.has(x)))])
	check(aw_ok, "覚醒：使える攻撃 %d 種類（必殺技2つをふくむ）が全部出る（300秒、3つの乱数）" % awake.size())
	check(ult_gap_ok, "覚醒：必殺技は、はじめの8秒・あいだ24秒を守る")

	# ---- 全部出たあとは、ふつうのくじ（同じ攻撃も出る） ----
	var ai3 := BossAI.new()
	ai3.reset(cfg, 42.0)
	var cnt := {}
	var t3 := 0.0
	while t3 < 400.0:
		t3 += 0.1
		ai3.update(t3, "normal", func(_n: int) -> float: return 6.0)
	var w_after: Dictionary = ai3.candidate_weights(t3 + 10.0, "normal", 6.0)
	check(ai3.unused_in("normal").is_empty() and w_after.size() >= 5, "全部出したあとは、ふつうのくじにもどる（候補 %d 種類）" % w_after.size())

	# ---- 消した攻撃・知らない攻撃が来たら、出さずに切りかえる ----
	var ai4 := BossAI.new()
	ai4.reset(cfg, 5.0)
	ai4.nxt = {"n": 1, "kind": "spin_bat", "start": 1.0, "feint": 0.0}
	ai4.n = 1
	ai4.update(1.0, "normal", func(_n: int) -> float: return 6.0)
	check(str(ai4.current().get("kind", "")) != "spin_bat" and ai4.is_valid(str(ai4.current().get("kind", ""))), "回転バット移動が来ても、出さずに別の攻撃（%s）に切りかえる" % str(ai4.current().get("kind", "")))
	var cfg2 := cfg.duplicate(true)
	(cfg2["kinds"]["hand_sweep"] as Dictionary)["ai"] = {"forms": {"awake": 5.0}, "removed": true, "ultimate": true}
	var ai5 := BossAI.new()
	ai5.reset(cfg2, 5.0)
	ai5.on_awake(0.0)
	check(not ai5.candidate_weights(30.0, "awake", 6.0).has("hand_sweep"), "消した印のある攻撃は、重みが残っていても候補に入らない")

	# ---- 巨大酒瓶ライドの瓶 ----
	var rk: Dictionary = cfg["kinds"]["bottle_ride"]
	check(int(rk["bottles_per_pass"]) == 12 and is_equal_approx(float(rk["throw_radius"]), 3.125), "巨大酒瓶ライド：突入ごとに12本、落ちる範囲は半径3.125（2.5の1.25倍）")
	var ctx := {"n": 3, "round_start_ms": 9.0, "bounds": 15.0, "boss": Vector2.ZERO, "area": 13.0}
	var a := {"kind": "bottle_ride", "n": 3}
	var ps: Dictionary = Attacks.ride_plan(rk, ctx)[0]
	var b: Dictionary = Attacks.ride_throws(ps, rk, ctx)[0]
	var hz: Array = Attacks.hazards(a, float(b["land"]) + 0.01, cfg, ctx).filter(func(h: Dictionary) -> bool: return str(h["id"]) == str(b["id"]))
	var to: Vector2 = b["to"]
	check(hz.size() == 1 and is_equal_approx(float(hz[0]["r"]), 3.125) and Attacks.inside(hz[0], to.x + 3.0, to.y) and not Attacks.inside(hz[0], to.x + 3.3, to.y), "巨大酒瓶ライド：予告の円と当たりの半径が同じ（3.0m は当たり、3.3m は外れ）")
	check(is_equal_approx(float(cfg["kinds"]["sake_drop"]["radius"]), 2.5), "酒瓶落としの範囲（2.5）は変えていない（6番は確認待ち）")

	# ---- 戦いの画面：全部の攻撃が出る前に倒しても、ふつうに勝って終わる ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.ai_enabled = false
	s.start_round()
	var tt := 0.5
	now[0] = s.round_start_ms + tt * 1000.0
	s.combat_update(0.05)
	s.my_hits = 4000.0
	s._recompute_boss_hp()
	while not s.phase.is_awake() and tt < 10.0:
		tt += 0.05
		now[0] = s.round_start_ms + tt * 1000.0
		s.combat_update(0.05)
		s._pose_boss(0.05)
	check(not s.ai.unused_in("awake").is_empty(), "画面：覚醒した直後は、まだ出していない攻撃が残っている")
	s.my_hits = 4000.0 + 9000.0
	s._recompute_boss_hp()
	check(s.won and not s.round_active(), "画面：まだの攻撃が残っていても、倒せば勝って終わる")
	s._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

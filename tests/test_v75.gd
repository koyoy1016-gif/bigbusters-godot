extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v75.gd
## 版75：与えたダメージの数字。実際に体力から減らした量を、四捨五入して出す。外れ・無敵の間は出さない。
## 出た瞬間に大きく → 弾む → 浮きながら消える。強い攻撃（かわし斬り・必殺技）は大きい。続けて出たら、ずらす。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const DamageNumbers := preload("res://scripts/ui/damage_numbers.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make(ai_on: bool = false) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = ai_on
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	return s


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))["damage_numbers"]
	# ---- 1. 数字の部品 ----
	var dn := DamageNumbers.new(cfg)
	check(dn.add(0.0, Vector3.ZERO).is_empty() and dn.items.is_empty(), "0ダメージは出さない")
	var a: Dictionary = dn.add(22.5, Vector3.ZERO)
	check(str(a["text"]) == "23", "22.5 は「23」（四捨五入。数字だけ）")
	check(str(dn.add(346.5, Vector3.ZERO, "strong")["text"]) == "347", "346.5 は「347」")
	var l0: Dictionary = dn.look(a)
	check(float(l0["scale"]) > 1.4 and float(l0["alpha"]) == 1.0 and float(l0["rise"]) == 0.0, "出た瞬間は大きい（%.2f 倍）" % float(l0["scale"]))
	dn.update(0.2)
	var l1: Dictionary = dn.look(a)
	check(absf(float(l1["scale"]) - 1.0) < 0.1 and float(l1["rise"]) > 10.0 and float(l1["alpha"]) == 1.0, "弾んで元の大きさにもどり、上へ浮く（%.2f 倍、%.0f px）" % [float(l1["scale"]), float(l1["rise"])])
	dn.update(0.35)
	var l2: Dictionary = dn.look(a)
	check(float(l2["alpha"]) < 0.6 and float(l2["rise"]) > float(l1["rise"]), "そのあと、すきとおりながら消えていく（%.2f）" % float(l2["alpha"]))
	dn.update(0.3)
	check(not dn.items.has(a), "0.5〜0.8秒で消える（ふつう %.2f 秒）" % float(a["life"]))
	check(float(dn.kind_cfg("strong")["life"]) > float(a["life"]), "強い攻撃は、長めに出る（%.2f 秒）" % float(dn.kind_cfg("strong")["life"]))
	var dn2 := DamageNumbers.new(cfg)
	var b0: Dictionary = dn2.add(10, Vector3.ZERO)
	var b1: Dictionary = dn2.add(10, Vector3.ZERO)
	var b2: Dictionary = dn2.add(10, Vector3.ZERO)
	check(float(b0["dx"]) == 0.0 and float(b1["dx"]) != 0.0 and float(b2["dx"]) == -float(b1["dx"]) and float(b2["dy"]) < float(b1["dy"]), "続けて出たら、左右と上へずらして重なりを防ぐ")
	dn2.update(1.0)
	check(float(dn2.add(10, Vector3.ZERO)["dx"]) == 0.0, "間があけば、ずらさない")
	var dn3 := DamageNumbers.new(cfg)
	var big: Dictionary = dn3.add(10, Vector3.ZERO, "strong")
	var small: Dictionary = dn3.add(10, Vector3.ZERO, "normal")
	check(float(dn3.kind_cfg("strong")["size"]) > float(dn3.kind_cfg("normal")["size"]) and float(dn3.look(big)["scale"]) > float(dn3.look(small)["scale"]) and float(dn3.look(big)["burst"]) > 0.0, "強い攻撃は、大きく、強く弾み、衝撃線がつく")
	check(DamageNumbers.keep_on_screen(Vector2(-50, 2000), Vector2(648, 1152), Vector2(40, 20), 12) == Vector2(52, 1120), "画面の外には出さない（ふちの内側へ）")

	# ---- 2. 戦いの中：実際に減らした量と、出す数字が同じ ----
	var s := make()
	var bp: Vector3 = s.boss.position
	var br := float(s.config["boss_size"]) * 0.5
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + 1.0)
	var h0: float = s.my_hits
	s._resolve_hit({"action": "normal", "multiplier": 1.0, "radius_scale": 1.0, "cleave": false})
	var items: Array = s.damage_numbers().items
	check(items.size() == 1 and is_equal_approx(float(items[0]["amount"]), s.my_hits - h0) and str(items[0]["text"]) == "23", "当たると、減らした量（22.5）が「23」で出る")
	var wp: Vector3 = items[0]["world"]
	check(Vector2(wp.x, wp.z).distance_to(Vector2(bp.x, bp.z)) < br and wp.z > bp.z, "数字は、ボスの体の、当てた人の側に出る")
	# 外れたら出ない
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + 20.0)
	s._resolve_hit({"action": "normal", "multiplier": 1.0, "radius_scale": 1.0, "cleave": false})
	check(s.damage_numbers().items.size() == 1, "外れたら、数字は出ない")
	# 無敵の間（倒れて覚醒する間）は出ない
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + 1.0)
	s.phase.phase = "fall"
	var h1: float = s.my_hits
	s._resolve_hit({"action": "normal", "multiplier": 1.0, "radius_scale": 1.0, "cleave": false})
	check(s.damage_numbers().items.size() == 1 and is_equal_approx(s.my_hits, h1), "無敵の間は、ダメージも数字も出ない")
	s.phase.phase = "normal"
	# 五段斬り：5回とも、それぞれの数字
	s.damage_numbers().items.clear()
	s.actions.reset()
	s.stun_left = 0.0
	var h2: float = s.my_hits
	s.perform("main")
	while s.actions.busy():
		s._actions_update(0.02)
	var sum := 0.0
	for it in s.damage_numbers().items:
		sum += float(it["amount"])
	check(s.damage_numbers().items.size() == 5 and is_equal_approx(sum, s.my_hits - h2), "五段斬り：5つの数字（「18」×5）、合計は減らした量と同じ")
	# 必殺技：強い攻撃として、大きく出る
	s.damage_numbers().items.clear()
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + 6.0)
	s.gauge.charge(99999.0)
	var h3: float = s.my_hits
	s.perform("ultimate")
	while s.actions.busy():
		s._actions_update(0.02)
		Engine.time_scale = 1.0
	var ul: Array = s.damage_numbers().items
	check(ul.size() == 1 and str(ul[0]["kind"]) == "strong" and is_equal_approx(float(ul[0]["amount"]), s.my_hits - h3) and str(ul[0]["text"]) == "347", "必殺技：強い攻撃として「347」が大きく出る")
	# 体力0の最後の一撃も出る
	s.damage_numbers().items.clear()
	s.actions.reset()
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + 1.0)
	s.my_hits = float(s.phase.max1) - 5.0
	s._recompute_boss_hp()
	s._resolve_hit({"action": "normal", "multiplier": 1.0, "radius_scale": 1.0, "cleave": false})
	check(s.damage_numbers().items.size() == 1, "体力が0になる一撃でも、数字が出る")
	root.remove_child(s)
	s.free()

	# ---- 3. AIの味方の一撃ずつ ----
	var s2 := make(true)
	var t := 0.0
	var ai_dealt := 0.0
	var shown := 0.0
	while t < 20.0:
		var before := 0.0
		for slot in s2.ai_hits:
			before += float(s2.ai_hits[slot])
		var n0: int = s2.damage_numbers().items.size()
		var amt0 := 0.0
		for it in s2.damage_numbers().items:
			amt0 += float(it["amount"])
		s2.my_hp = 999.0
		s2.combat_update(0.05)
		s2._pose_boss(0.05)
		var after := 0.0
		for slot in s2.ai_hits:
			after += float(s2.ai_hits[slot])
		var amt1 := 0.0
		for it in s2.damage_numbers().items:
			amt1 += float(it["amount"])
		ai_dealt += after - before
		shown += amt1 - amt0
		s2.damage_numbers().items.clear()
		t += 0.05
		s2.clock_ms = func() -> float: return 3000000.0 + t * 1000.0
	check(ai_dealt > 100.0 and absf(shown - ai_dealt) < 0.01, "AIの味方の数字の合計が、AIが減らした量と同じ（%.1f / %.1f）" % [shown, ai_dealt])
	root.remove_child(s2)
	s2.free()
	Engine.time_scale = 1.0
	print("")
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

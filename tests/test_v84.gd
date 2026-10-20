extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v84.gd
## 版84：倒れた仲間の蘇生。
## 確かめること：
##   1. 決まり：倒れた所に輪・20秒の間・中に4秒で起きる・出たら0にもどる・20秒すぎたら起こせない・2回起きない・何人いても同じ速さ
##   2. 数値は data/prototype_stick.json の revive（20秒・4秒・30%）
##   3. 戦いの中：AIが倒れたら輪、自分が中に4秒いると30%の体力で起きる。輪の見た目（白いふち・しま・進み）と字
##   4. 自分が倒れたら輪。AIの味方が起こしに来て、起こしてくれる（攻撃より先）
##   5. ほかの方法（回復の膜）で起きたら、輪は消える

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Revive := preload("res://scripts/combat/revive.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make(char_id: String, ai_on: bool) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = char_id
	s.ai_enabled = ai_on
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.set_process(false)
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.skill_time_stop_left = 999.0  # ボスを止める（攻撃されないように）
	return s


func tick(s: Node, sec: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 0.0001:
		s._actions_update(dt)
		s.combat_update(dt)
		s._ai_update(dt)
		t += dt
	Engine.time_scale = 1.0


func _initialize() -> void:
	# ---- 1・2. 決まり ----
	var cfgj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var rc: Dictionary = cfgj["revive"]
	check(is_equal_approx(float(rc["window_sec"]), 20.0) and is_equal_approx(float(rc["hold_sec"]), 4.0) and is_equal_approx(float(rc["hp_ratio"]), 0.3), "数値：20秒・4秒・30%（data に置く）")
	var r := Revive.new(rc)
	var R := r.radius(1.0)
	check(R > 0.5 and R < 4.0, "輪の大きさは、プレイヤーの当たりの大きさから（%.1f m）" % R)
	check(r.on_down("p2", Vector2(0, 0)) and not r.on_down("p2", Vector2(5, 5)), "倒れた所に輪（2つ目は作らない）")
	var near := {"p1": Vector2(0.5, 0)}
	var far := {"p1": Vector2(9, 0)}
	var res: Dictionary = r.update(3.9, near, R)
	check(res["revived"].is_empty() and is_equal_approx(float(r.zones["p2"]["progress"]), 3.9), "中に3.9秒では、まだ起きない")
	r.update(0.2, far, R)
	check(float(r.zones["p2"]["progress"]) == 0.0, "輪から出たら、進みは0にもどる")
	r.update(2.0, {"p1": Vector2(0.2, 0), "p3": Vector2(-0.2, 0), "p4": Vector2(0, 0.3)}, R)
	check(is_equal_approx(float(r.zones["p2"]["progress"]), 2.0), "何人で入っても、進む速さは同じ")
	res = r.update(2.0, near, R)
	check(res["revived"] == ["p2"] and not r.zones.has("p2"), "4秒で起きる（輪は消える）")
	res = r.update(5.0, near, R)
	check(res["revived"].is_empty(), "2回は起きない")
	var r2 := Revive.new(rc)
	r2.on_down("p3", Vector2(0, 0))
	r2.update(19.0, far, R)
	check(r2.zones.has("p3"), "19秒では、まだ起こせる")
	res = r2.update(1.1, far, R)
	check(res["expired"] == ["p3"] and not r2.zones.has("p3"), "20秒すぎたら、輪は消える")
	res = r2.update(5.0, {"p1": Vector2(0, 0)}, R)
	check(res["revived"].is_empty() and not r2.on_down("p3", Vector2(0, 0)), "時間が過ぎた人は、もう起こせない")
	r2.clear("p3")
	check(r2.on_down("p3", Vector2(1, 1)), "ほかの方法で起きて、また倒れたら、新しい輪")
	var as1: Dictionary = Revive.assign({"p2": {"pos": Vector2(10, 0)}}, {"p3": Vector2(9, 0), "p4": Vector2(-9, 0)})
	check(as1 == {"p3": Vector2(10, 0)}, "AIの味方は、いちばん近い1人が起こしに行く")
	check(Revive.assign({"p2": {"pos": Vector2(0, 0)}}, {"p2": Vector2(0, 0)}).is_empty(), "倒れた本人は、自分を起こさない")

	# ---- 3. 戦い：自分がAIを起こす ----
	var s := await make("gunner", true)
	tick(s, 0.2)
	check(s.ai_allies.size() == 3, "AIの味方が3人")
	var slots: Array = s.ai_allies.keys()
	var target := str(slots[0])
	var a: Dictionary = s.ai_allies[target]
	# ほかのAIは、遠くで止めておく（自分で起こす）
	a["hp"] = 0.0
	a["downed"] = true
	tick(s, 0.05)
	check(s.revive_sys.logic.zones.has(target) and s.revive_sys.log.has("down:" + target), "AIが倒れたら、輪ができる")
	var n: Dictionary = s.revive_sys.nodes.get(target, {})
	check(not n.is_empty() and (n["root"] as Node3D).find_children("*", "Label3D", true, false).size() == 1, "輪の見た目（床の輪と、のこり秒の字）")
	var mat: ShaderMaterial = n["mat"]
	check(mat.shader.code.contains("stripes") and mat.shader.code.contains("progress") and mat.shader.code.contains("time_left"), "白いふち・ななめのしま・進み・のこり時間（シェーダー）")
	var zp: Vector2 = s.revive_sys.logic.zones[target]["pos"]
	for other in slots:
		if str(other) != target:
			(s.ai_allies[other] as Dictionary)["pos"] = Vector2(60, 60)
	s.player.position = Vector3(zp.x + 0.3, s.ground_y, zp.y)
	tick(s, 2.0)
	check(float(s.revive_sys.logic.zones[target]["progress"]) > 1.5 and str(s.revive_sys.logic.zones[target]["by"]) == str(s._my_slot()), "自分が輪の中にいると、進む")
	s.player.position = Vector3(zp.x + 20.0, s.ground_y, zp.y)
	for other in slots:
		if str(other) != target:
			(s.ai_allies[other] as Dictionary)["pos"] = zp + Vector2(12, 12)  # ほかのAIも、輪の外に
	tick(s, 0.05)
	check(float(s.revive_sys.logic.zones[target]["progress"]) == 0.0, "輪から出ると、0にもどる")
	s.player.position = Vector3(zp.x + 0.3, s.ground_y, zp.y)
	for other in slots:
		if str(other) != target:
			(s.ai_allies[other] as Dictionary)["pos"] = Vector2(60, 60)
	tick(s, 4.2)
	check(not bool(a["downed"]) and is_equal_approx(float(a["hp"]), float(a["max_hp"]) * 0.3) and s.revive_sys.log.has("revive:" + target), "4秒で起きる（体力30%）")
	check(not s.revive_sys.nodes.has(target), "起きたら、輪は消える")

	# ---- 4. 自分が倒れて、AIが起こしに来る ----
	s.player.position = Vector3(0, s.ground_y, 14)
	s._set_my_hp(0.0)
	tick(s, 0.05)
	var me := str(s._my_slot())
	check(s.downed and s.revive_sys.logic.zones.has(me) and not s.lost, "自分が倒れたら輪（AIが生きていれば、まだ負けない）")
	check(s.revive_sys.my_status().contains("4"), "画面に「なかまが そばに 4びょう いれば ふっかつ」：" + s.revive_sys.my_status())
	var t := 0.0
	while s.downed and t < 16.0:
		tick(s, 0.5)
		t += 0.5
	check(not s.downed and is_equal_approx(s.my_hp, s.role_value("hp") * 0.3), "AIの味方が起こしに来て、起こしてくれた（%.1f秒。体力30%%）" % t)

	# ---- 5. 回復の膜で起きたら、輪は消える ----
	var b2: Dictionary = s.ai_allies[str(slots[1])]
	b2["hp"] = 0.0
	b2["downed"] = true
	tick(s, 0.05)
	check(s.revive_sys.logic.zones.has(str(slots[1])), "また倒れた（輪）")
	b2["downed"] = false
	b2["hp"] = 50.0
	tick(s, 0.05)
	check(not s.revive_sys.logic.zones.has(str(slots[1])) and not s.revive_sys.nodes.has(str(slots[1])), "ほかの方法で起きたら、輪は消える")
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_throw_collide.gd
## 版67：つかみ投げ。ボスからいちばん遠い人のほうへ投げる。飛んでいる間と着地で、ほかの人にぶつかると、
## ぶつかった人と投げられた人の両方にダメージ、ぶつかった人は転ぶ。1回の投げで、1人には1回だけ。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make_scene() -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.set_meta("now", now)
	s.sfx = null
	s.start_round()
	s.combat_update(0.02)
	return s


## AIの味方を、決めた場所に止める（自分では歩かない）
func place(s: Node, slot: String, p: Vector2) -> void:
	var a: Dictionary = s.ai_allies[slot]
	a["pos"] = p
	a["stun"] = 99.0
	var half := float(s.config["bounds"])
	s.other_pos[slot] = Vector2((p.x + half) / (2.0 * half), (p.y + half) / (2.0 * half))


func hold_still(s: Node) -> void:
	for slot in s.ai_allies:
		var a: Dictionary = s.ai_allies[slot]
		a["stun"] = 99.0
		var half := float(s.config["bounds"])
		var p: Vector2 = a["pos"]
		s.other_pos[slot] = Vector2((p.x + half) / (2.0 * half), (p.y + half) / (2.0 * half))


func _initialize() -> void:
	var k: Dictionary = Attacks.load_config()["kinds"]["grab"]
	var s := make_scene()
	check(s.ai_allies.size() == 3, "AIの味方が3人いる（p2〜p4）")
	var bp := Vector2(s.boss.position.x, s.boss.position.z)
	var me: String = s._my_slot()

	# ---- 投げる向き：いちばん遠い人のほう（投げられる人は除く） ----
	place(s, "p2", bp + Vector2(0, 5))
	place(s, "p3", bp + Vector2(12, 0))
	place(s, "p4", bp + Vector2(-8, 0))
	s.player.position = Vector3(bp.x, s.ground_y, bp.y + 3.0)
	check((s.throw_dir(me) as Vector2).is_equal_approx(Vector2(1, 0)), "自分が投げられるとき：いちばん遠い p3（12m）のほうへ")
	s.player.position = Vector3(bp.x, s.ground_y, bp.y - 20.0)
	check((s.throw_dir("p3") as Vector2).is_equal_approx(Vector2(0, -1)), "p3 が投げられるとき：p3 自身は除いて、いちばん遠い人（自分、20m）のほうへ")
	place(s, "p4", bp + Vector2(-12, 0))
	s.player.position = Vector3(bp.x, s.ground_y, bp.y + 3.0)
	check((s.throw_dir(me) as Vector2).is_equal_approx(Vector2(1, 0)), "同じ距離の人が2人いたら、枠の名前の順で先（p3）のほう（毎回同じ）")
	for slot in s.ai_allies:
		s.ai_allies[slot]["downed"] = true
	check((s.throw_dir(me) as Vector2).is_equal_approx(Attacks.fwd_of(s.boss.rotation.y)), "ほかにだれもいなければ、ボスの正面（前のまま）")
	s._exit_tree()
	root.remove_child(s)
	s.free()

	# ---- ぶつかり：飛んでいる間（p2）と着地（p4）。両方にダメージ、転ぶ。二重に当たらない ----
	s = make_scene()
	bp = Vector2(s.boss.position.x, s.boss.position.z)
	me = s._my_slot()
	var now: Array = s.get_meta("now")
	place(s, "p3", bp + Vector2(0, 28))  # いちばん遠い人 → 向きは +z
	place(s, "p2", Vector2(-40, -40))
	place(s, "p4", Vector2(40, -40))
	s.player.position = Vector3(bp.x, s.ground_y, bp.y + 2.0)
	s.current_attack = {"kind": "grab", "n": 7}
	s._start_hold(me, Vector2(bp.x, bp.y + 2.0))
	s.grab_state["t"] = 1.0
	var p0 := Vector2(s.player.position.x, s.player.position.z)
	var path: Array = s.actions.def("thrown")["path"]
	var land_fwd := float((path[path.size() - 1] as Dictionary)["fwd"])
	place(s, "p2", p0 + Vector2(0, land_fwd - 2.5))  # 下りてくる途中（空中）
	place(s, "p4", p0 + Vector2(0, land_fwd))  # 着地点
	var hp2: float = s.ai_allies["p2"]["hp"]
	var hp3: float = s.ai_allies["p3"]["hp"]
	var hp4: float = s.ai_allies["p4"]["hp"]
	var hp_me: float = s.my_hp
	s._release_hold(false)
	check((s.throw_fly["dir"] as Vector2).is_equal_approx(Vector2(0, 1)), "ぶつかりの試し：投げる向きは、いちばん遠い p3 のほう")
	var t := 0.0
	var p2_kb_seen := false
	var p4_kb_seen := false
	var p2_hit_t := -1.0
	var p4_hit_t := -1.0
	var max_h_at_p2 := 0.0
	while t < 2.0:
		t += 0.02
		now[0] += 20.0
		hold_still(s)
		s._actions_update(0.02)
		s.combat_update(0.02)
		if p2_hit_t < 0.0 and float(s.ai_allies["p2"]["hp"]) < hp2:
			p2_hit_t = t
			max_h_at_p2 = s.player.position.y - s.ground_y
		if p4_hit_t < 0.0 and float(s.ai_allies["p4"]["hp"]) < hp4:
			p4_hit_t = t
		p2_kb_seen = p2_kb_seen or AiAlly.act(s.ai_allies["p2"]).active == "kb_heavy"
		p4_kb_seen = p4_kb_seen or AiAlly.act(s.ai_allies["p4"]).active == "kb_heavy"
	var dmg := Damage_amount(k, s)
	check(p2_hit_t > 0.0 and max_h_at_p2 > 0.3, "飛んでいる間（空中、高さ %.1fm）に p2 にぶつかる" % max_h_at_p2)
	check(p4_hit_t > 0.0 and p4_hit_t >= p2_hit_t, "着地点の p4 にもぶつかる")
	check(is_equal_approx(hp2 - float(s.ai_allies["p2"]["hp"]), dmg) and is_equal_approx(hp4 - float(s.ai_allies["p4"]["hp"]), dmg), "ぶつかられた2人は、それぞれ1回だけ %.0f ダメージ（二重にならない）" % dmg)
	check(p2_kb_seen and p4_kb_seen, "ぶつかられた2人とも、転ぶ（kb_heavy）")
	check(is_equal_approx(hp3, float(s.ai_allies["p3"]["hp"])), "ぶつからなかった p3 は、ダメージなし")
	var lost: float = hp_me - float(s.my_hp)
	check(is_equal_approx(lost, dmg + float(k["drop_power"]) * float(Attacks.load_config()["damage_multiplier"])), "投げられた自分：ぶつかったダメージ1回（%.0f）＋着地のダメージ（%.0f）＝ %.0f" % [dmg, float(k["drop_power"]), lost])
	check(s.actions.active == "" or s.actions.active == "thrown", "投げられた自分は、投げられた動き（転んで起き上がる）のまま")
	check(s.throw_fly.is_empty(), "着地のあとは、ぶつかりの判定を終える")
	s._exit_tree()
	root.remove_child(s)
	s.free()

	# ---- AIの味方が投げられて、自分にぶつかる。転んでいる人には当たらない ----
	s = make_scene()
	bp = Vector2(s.boss.position.x, s.boss.position.z)
	me = s._my_slot()
	now = s.get_meta("now")
	place(s, "p2", bp + Vector2(2.0, 0))
	place(s, "p3", Vector2(-40, 40))
	place(s, "p4", Vector2(-40, -40))
	s.current_attack = {"kind": "grab", "n": 9}
	s._start_hold("p2", bp + Vector2(2.0, 0))
	s.grab_state["t"] = 1.0
	s.combat_update(0.0)
	var a2: Dictionary = s.ai_allies["p2"]
	var q0: Vector2 = a2["pos"]
	# いちばん遠い人＝自分（+x 方向 30m）。着地点の近くに立つ。p4 は着地点にいるが、すでに転んでいる（起き上がり直後で当たらない）
	s.player.position = Vector3(bp.x + 30.0, s.ground_y, bp.y)
	var dirx: Vector2 = s.throw_dir("p2")
	s.player.position = Vector3(q0.x + dirx.x * land_fwd, s.ground_y, q0.y + dirx.y * land_fwd)
	place(s, "p4", q0 + dirx * (land_fwd - 0.5))
	s.ai_allies["p4"]["kb_guard"] = 5.0
	var hp4b: float = s.ai_allies["p4"]["hp"]
	var my_before: float = s.my_hp
	var a2_before: float = a2["hp"]
	s._release_hold(false)
	var kb_me := false
	t = 0.0
	while t < 2.0:
		t += 0.02
		now[0] += 20.0
		hold_still(s)
		s.ai_allies["p2"]["stun"] = 0.0
		s._actions_update(0.02)
		s.combat_update(0.02)
		kb_me = kb_me or s.actions.active == "kb_heavy"
	check(is_equal_approx(my_before - float(s.my_hp), dmg) and kb_me, "AIが投げられて自分にぶつかる：自分に %.0f ダメージ、転ぶ" % dmg)
	check(is_equal_approx(a2_before - float(a2["hp"]), dmg + float(k["drop_power"]) * float(s.attacks_cfg["damage_multiplier"])), "投げられたAI：ぶつかり1回＋着地のダメージ")
	check(is_equal_approx(hp4b, float(s.ai_allies["p4"]["hp"])), "転んで起き上がった直後の人（当たらない時間）には、ぶつかってもダメージなし")
	s._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)


func Damage_amount(k: Dictionary, s: Node) -> float:
	return float(k.get("collide_power", k["drop_power"])) * float(s.attacks_cfg["damage_multiplier"])

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v70.gd
## 版70：つかまれたら必ず投げられる（逃げる仕組みはない）・投げられた人はほかの人にぶつからない・
## 剣士（忍者風の剣士）の体力 190・剣士の攻撃の一覧（docs/swordsman.md）が実際のデータと合う。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make_scene(ai_on: bool = false, character: String = "") -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = ai_on
	if character != "":
		s.selected_character = character
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [6000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	return s


## つかまれてから投げられるまで、delta ずつ進める。投げられたら true
func run_until_thrown(s: Node, slot: String, mash_buttons: bool) -> bool:
	var screen := Vector2(648, 1152)
	for i in 300:
		if mash_buttons and slot == s._my_slot():
			for id in ["normal", "sub", "main", "ultimate"]:
				s.handle_press(1, s._button_center(id, screen), screen)
				s.handle_release(1)
		for k in s.ai_hits:
			s.ai_hits[k] = float(s.ai_hits[k]) + 50.0
		s.my_hits += 50.0  # みんなでたくさん当てても外れない
		s._grab_update(0.02)
		if s.grab_state.is_empty():
			break
	if slot == s._my_slot():
		return s.actions.active == "thrown"
	return str(s.AiAlly.act(s.ai_allies[slot]).active) == "thrown"


func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_attacks.json"))
	var g: Dictionary = raw["kinds"]["grab"]

	# ---- 1. 逃げる仕組みがない ----
	check(not g.has("mash_needed") and not g.has("free_damage"), "データに「にげる」の回数・みんなのダメージで外れる量がない")
	var ai_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai_allies.json"))
	check(not ai_cfg.has("escape_taps_min") and not ai_cfg.has("escape_taps_max"), "AIの連打の速さのデータもない")
	var s := make_scene(true)
	check(not s.has_method("_mash_escape") and not s.has_method("escape_progress"), "「にげる」の処理がない")
	var bz: float = s.boss.position.z
	var all_thrown := true
	for rep in 5:
		s.actions.reset()
		s.stun_left = 0.0
		s.my_hp = s.role_value("hp")
		s.player.position = Vector3(0.0, s.ground_y, bz + 6.0)
		s._start_hold(s._my_slot(), Vector2(0.0, bz + 6.0))
		all_thrown = all_thrown and run_until_thrown(s, s._my_slot(), true)
	check(all_thrown, "自分：ボタンを全部連打しても、みんなでダメージを与えても、5回とも必ず投げられる")
	var ai_thrown := true
	for slot in s.ai_allies:
		var a: Dictionary = s.ai_allies[slot]
		a["hp"] = float(a["max_hp"])
		a["downed"] = false
		a["held"] = true
		s._start_hold(str(slot), a["pos"])
		ai_thrown = ai_thrown and run_until_thrown(s, str(slot), false)
		a["held"] = false
	check(ai_thrown, "AIの味方3人とも、必ず投げられる")
	# すぐ投げるつかみ（剣士・0.25秒）も、必ず投げられる
	s.actions.reset()
	s.stun_left = 0.0
	s.my_hp = s.role_value("hp")
	s.current_attack = {"kind": "grab", "n": 99, "quick": true}
	s._start_hold(s._my_slot(), Vector2(0.0, bz + 6.0))
	check(is_equal_approx(float(s.grab_state["hold"]), 0.25), "すぐ投げるつかみは0.25秒")
	check(run_until_thrown(s, s._my_slot(), true), "すぐ投げるつかみも、必ず投げられる")
	s.current_attack = {}

	# ---- 2. 投げられた人は、ほかの人にぶつからない ----
	check(not g.has("collide_radius") and not g.has("collide_power"), "ぶつかりのデータがない")
	check(not s.has_method("_throw_fly_update") and not s.has_method("_hit_by_thrown") and not s.has_method("_thrown_self_damage"), "ぶつかりの処理がない")
	# AIを1人投げ、その飛ぶ先に自分とほかのAIを置く → だれもダメージを受けない
	var names: Array = s.ai_allies.keys()
	names.sort()
	var thrown_slot := str(names[0])
	var ta: Dictionary = s.ai_allies[thrown_slot]
	ta["hp"] = float(ta["max_hp"])
	ta["downed"] = false
	ta["held"] = true
	s.actions.reset()
	s.stun_left = 0.0
	s._start_hold(thrown_slot, ta["pos"])
	while not s.grab_state.is_empty():
		s._grab_update(0.02)
	var hp_me: float = s.my_hp
	var others_hp := {}
	for slot in names:
		if str(slot) != thrown_slot:
			others_hp[slot] = float(s.ai_allies[slot]["hp"])
	var crashed := false
	for i in 120:
		var p: Vector2 = ta["pos"]
		s.player.position = Vector3(p.x, s.ground_y, p.y)  # 飛んでいる人のすぐそばに立つ
		for slot in others_hp:
			s.ai_allies[slot]["pos"] = p
		s.AiAlly.act(ta).update(0.02)
		var mv: Vector2 = s.AiAlly.act(ta).aim * s.AiAlly.act(ta).frame_move.x
		ta["pos"] = p + mv
		if s.my_hp < hp_me - 0.001 or s.actions.active == "kb_heavy":
			crashed = true
		for slot in others_hp:
			if float(s.ai_allies[slot]["hp"]) < float(others_hp[slot]) - 0.001:
				crashed = true
	check(not crashed, "投げられた人のすぐそばにいても、ダメージも転ぶこともない")
	root.remove_child(s)
	s.free()

	# ---- 3. 剣士の体力 190 ----
	var ccfg := CharacterData.load_config()
	var hero: Dictionary = CharacterData.find(ccfg, "hero_swordsman")["stats"]
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	check(is_equal_approx(float(hero["hp"]), 190.0) and is_equal_approx(float(cfg["roles"]["p1"]["hp"]), 190.0), "剣士の体力は190（キャラを選んだとき・選ばないとき）")
	check(is_equal_approx(float(hero["attack_power"]), 22.5) and is_equal_approx(float(cfg["roles"]["p1"]["attack_power"]), 22.5), "攻撃力は22.5のまま")
	for ch in ["", "hero_swordsman"]:
		var h := make_scene(false, ch)
		check(is_equal_approx(h.my_hp, 190.0) and is_equal_approx(h.role_value("hp"), 190.0), "戦いの始まりの体力が190（%s）" % ("選ばない" if ch == "" else ch))
		h._take_damage(100.0)
		check(is_equal_approx(h.my_hp, 90.0) and not h.downed, "100ダメージで残り90、まだ倒れない")
		h._take_damage(95.0)
		check(is_equal_approx(h.my_hp, 0.0) and h.downed, "体力が0になると倒れる")
		root.remove_child(h)
		h.free()

	# ---- 4. 攻撃の一覧（docs/swordsman.md）が、実際のデータと合う ----
	var doc := FileAccess.get_file_as_string("res://docs/swordsman.md")
	var acts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actions.json"))["actions"]
	var power := float(hero["attack_power"])
	var reach := float(hero["attack_reach"])
	var rows := {"normal": "単純斬り", "main": "五段斬り", "ultimate": "切り捨て御免"}  # 版110：Y は共通の回避（攻撃ではない）
	for id in rows:
		var d: Dictionary = acts[id]
		check(str(d["name"]) == rows[id] and doc.contains(rows[id]), "一覧に「%s」がある（データの名前と同じ）" % rows[id])
		var hits: Array = d["hits"]
		var per := Damage_amount(power, float((hits[0] as Dictionary)["multiplier"]) * (float(hero.get("ultimate_scale", 1.0)) if id == "ultimate" else 1.0))
		var line := ""
		for l in doc.split("\n"):
			if l.contains(rows[id]) and l.begins_with("|"):
				line = l
		check(line != "" and line.contains("| %d |" % hits.size()) and line.contains(_num(per)) and line.contains(_num(reach * float(d["radius_scale"])) + " m"), "%s：連撃数 %d・1回 %s・範囲 %s m が一覧と同じ" % [rows[id], hits.size(), _num(per), _num(reach * float(d["radius_scale"]))])
	var total := 0
	for id in rows:
		total += (acts[id]["hits"] as Array).size()
	check(doc.contains("3つ全部で %d回" % total) and doc.contains("攻撃の種類は **3つ**"), "攻撃の種類3つ・当たる回数の合計 %d が一覧と同じ" % total)
	var y: Dictionary = acts["sub"]
	check(str(y["name"]) == "回避" and doc.contains("0.02〜0.34秒") and is_equal_approx(float(y["i_window"][0]), 0.02) and is_equal_approx(float(y["i_window"][1]), 0.34) and doc.contains("1.2 秒"), "一覧の回避（よけられる時間・待ち時間）がデータと同じ")
	check(doc.contains("**190**"), "一覧の体力は190")

	print("")
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)


func Damage_amount(attack: float, mult: float) -> float:
	return (load("res://scripts/combat/damage.gd") as GDScript).damage_amount(attack, mult)


## 一覧の書き方（小数1けた。.0 は消さずに書く物と合わせる）
func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)) and absf(x) >= 100.0:
		return str(int(roundf(x)))
	return "%.1f" % x

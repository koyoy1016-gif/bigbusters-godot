extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v68.gd
## 版68：体力（平常6000・覚醒11250・剣士288.75）と剣士の攻撃力22.5・ライドの瓶の範囲と帯の幅・
## 酒の大雨（覚醒の体力4分の1と4分の3で必ず。ステージ全体＋安全地帯6か所）・剣士をすぐ投げるつかみ（1戦に1回）。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
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


func to_awake(s: Node, t: float) -> float:
	s.my_hits = float(s.phase.max1)
	s._recompute_boss_hp()
	while not s.phase.is_awake() and t < 20.0:
		t = step(s, t)
	return t


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var acfg := Attacks.load_config()

	# ---- 1. 体力・剣士の攻撃力 ----
	check(is_equal_approx(float(cfg["boss_hp"]), 4000.0 * 1.5) and is_equal_approx(float(cfg["boss_hp_awake"]), 9000.0 * 1.25), "ボスの体力：平常 6000（4000の1.5倍）、覚醒 11250（9000の1.25倍）")
	var ccfg := CharacterData.load_config()
	var hero: Dictionary = CharacterData.find(ccfg, "hero_swordsman")["stats"]
	check(is_equal_approx(float(hero["hp"]), 190.0) and is_equal_approx(float(hero["attack_power"]), 18.0 * 1.25), "剣士：体力 190（版70で 288.75 から変更）、攻撃力 22.5（18の1.25倍）")
	var p1: Dictionary = cfg["roles"]["p1"]
	check(is_equal_approx(float(p1["hp"]), 190.0) and is_equal_approx(float(p1["attack_power"]), 22.5), "キャラを選ばないときの剣士（ファイター）も同じ")
	var others_ok := true
	var expect := {"sprinter": [105.0, 12.0], "brawler": [135.0, 15.0], "gunner": [105.0, 13.5], "bomber": [112.5, 16.5], "mage": [97.5, 18.0], "guardian": [240.0, 10.5], "summoner": [120.0, 9.0], "healer": [127.5, 7.5]}
	for id in expect:
		var st: Dictionary = CharacterData.find(ccfg, id)["stats"]
		others_ok = others_ok and is_equal_approx(float(st["hp"]), float(expect[id][0])) and is_equal_approx(float(st["attack_power"]), float(expect[id][1]))
	check(others_ok, "ほかの味方8人の体力と攻撃力は変わらない")
	var s := make_scene()
	var t := 0.5
	check(is_equal_approx(s.my_hp, 190.0) and is_equal_approx(s.phase.max_hp(), 6000.0), "画面：剣士は体力 190（版70）、ボスは平常 6000 で始まる")
	var ev := {"multiplier": 1.0, "radius_scale": 1.0}
	var dmg: float = Damage_of(s, ev)
	check(is_equal_approx(dmg, 22.5 * float(s.config["attack_multiplier"])), "画面：剣士の斬り1回のダメージは 22.5（攻撃力どおり）")
	t = to_awake(s, t)
	check(s.phase.is_awake() and is_equal_approx(s.phase.max_hp(), 11250.0) and is_equal_approx(s.boss_hp, 11250.0), "画面：覚醒すると 11250 から（ゲージの満タンも 11250）")

	# ---- 5. 酒の大雨：覚醒の体力が4分の1・4分の3減ったら必ず。1回ずつ ----
	var storms := 0
	var in_storm := false
	var marks := [0.25, 0.5, 0.75, 0.9]
	for m in marks:
		s.my_hits = float(s.phase.max1) + float(s.phase.max2) * float(m) + 1.0
		s._recompute_boss_hp()
		var limit := t + 45.0
		while t < limit:
			s.player.position = Vector3(0, s.ground_y, 40)
			s.my_hp = 288.75
			s.downed = false
			t = step(s, t)
			var now_storm := str(s.current_attack.get("kind", "")) == Attacks.FLYER_STORM
			if now_storm and not in_storm:
				storms += 1
			in_storm = now_storm
			if s.ai.forced.is_empty() and str(s.ai.next_attack().get("kind", "")) not in [Attacks.FLYER_STORM, Attacks.BOTTLE_RIDE] and str(s.current_attack.get("kind", "")) not in [Attacks.FLYER_STORM, Attacks.BOTTLE_RIDE] and s.awake_storms_done.size() >= (1 if m < 0.7 else 2):
				break
	check(s.awake_storms_done.size() == 2 and storms >= 2, "画面：覚醒の体力が4分の1と4分の3減ったとき、酒の大雨が必ず出る（記録 %d、出た %d 回）" % [s.awake_storms_done.size(), storms])
	s.my_hits += 1.0
	s._recompute_boss_hp()
	check(s.awake_storms_done.size() == 2 and s.ai.forced.filter(func(f): return str(f["kind"]) == Attacks.FLYER_STORM).is_empty(), "同じ区切りで、二重には出さない")
	s._exit_tree()
	root.remove_child(s)
	s.free()

	# ---- 6. 酒の大雨：ステージ全体＋安全地帯6か所 ----
	var fk: Dictionary = acfg["kinds"]["flyer_storm"]
	var ctx := {"boss": Vector2.ZERO, "yaw": 0.0, "round_start_ms": 77.0, "bounds": 15.0, "members": [], "positions": {}}
	var a := {"kind": Attacks.FLYER_STORM, "n": 5}
	var safe := Attacks.storm_safe(a, fk, ctx)
	var sr := float(fk["safe_radius"])
	var apart := true
	for i in safe.size():
		for j in range(i + 1, safe.size()):
			apart = apart and (safe[i] as Vector2).distance_to(safe[j]) >= 2.0 * sr
	check(safe.size() == 6 and apart, "安全地帯は6か所、重ならない")
	check(is_equal_approx(sr, 2.0 * 1.5), "安全地帯の半径は 3.0m（剣士の攻撃が届く範囲 2.0m の1.5倍）")
	var w0 := Attacks.storm_wave_time(0, fk)
	var hz: Array = Attacks.hazards(a, w0 + 0.01, acfg, ctx)
	var rain: Array = hz.filter(func(h: Dictionary) -> bool: return str(h["style"]) == "rain")
	var safes: Array = hz.filter(func(h: Dictionary) -> bool: return str(h["style"]) == "safe")
	check(rain.size() == 1 and bool(rain[0]["active"]) and safes.size() == 6, "雨の当たり（ステージ全体）が1つと、見える安全地帯の円が6つ")
	var c0: Vector2 = safe[0]
	var inside_safe := Attacks.inside(rain[0], c0.x + sr * 0.9, c0.y)
	var outside_safe := Attacks.inside(rain[0], c0.x + sr * 1.1, c0.y)
	check(not inside_safe and outside_safe, "安全地帯の円の中（ふちの内側0.9）は当たらず、外（1.1）は当たる")
	check(is_equal_approx(float(safes[0]["r"]), sr) and is_equal_approx(float(rain[0]["safe_r"]), sr), "見た目の円と、当たらない範囲の半径が同じ")
	check(is_equal_approx(float(rain[0]["power"]), float(fk["power"])) and is_equal_approx(float(fk["power"]), 18.0) and is_equal_approx(float((JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_attacks.json")) as Dictionary)["kinds"]["flyer_storm"]["duration"]), 10.0), "ダメージ18・攻撃の長さ（10秒、速さ1.5倍で %.1f 秒）は前のまま" % float(fk["duration"]))
	var waves_hit := 0
	var u := 0.0
	var seen_ids := {}
	while u < float(fk["duration"]):
		for h in Attacks.hazards(a, u, acfg, ctx):
			if str(h["style"]) == "rain" and bool(h["active"]):
				seen_ids[str(h["id"])] = true
		u += 0.02
	check(seen_ids.size() == int(fk["waves"]), "雨は %d 回の波で当たる（波ごとに1回）" % seen_ids.size())
	# 画面：中にいるとダメージなし、外にいるとダメージ。安全地帯が見える、雨が降る
	s = make_scene()
	t = 0.5
	t = to_awake(s, t)
	s.awake_storms_done = {0: true, 1: true}
	s.awake_rides_done = 99
	var fa: Dictionary = s.force_attack(Attacks.FLYER_STORM)
	var sctx: Dictionary = s._attack_ctx(fa, 0.0)
	sctx["n"] = int(fa["n"])
	var ssafe := Attacks.storm_safe(fa, fk, sctx)
	var spot: Vector2 = ssafe[0]
	s.player.position = Vector3(spot.x, s.ground_y, spot.y)
	var hp_in: float = s.my_hp
	var saw_safe := false
	var saw_rain := false
	t = float(fa["start"])
	var now: Array = s.get_meta("now")
	while t < float(fa["end"]) - 0.05:
		t += 0.03
		now[0] = s.round_start_ms + t * 1000.0
		s.player.position = Vector3(spot.x, s.ground_y, spot.y)
		s.combat_update(0.03)
		for i in s.current_hazards.size():
			if str(s.current_hazards[i]["style"]) == "safe" and (s.hazard_nodes[i] as Node3D).visible:
				saw_safe = true
		saw_rain = saw_rain or (s._rain_fx != null and s._rain_fx.emitting)
	check(is_equal_approx(s.my_hp, hp_in), "画面：安全地帯の中にいると、酒の大雨のダメージを受けない")
	check(saw_safe and saw_rain, "画面：安全地帯の円が見え、ステージ全体に雨が降る")
	s.my_hp = 288.75
	var fb: Dictionary = s.force_attack(Attacks.FLYER_STORM)
	var bctx: Dictionary = s._attack_ctx(fb, 0.0)
	bctx["n"] = int(fb["n"])
	var bsafe := Attacks.storm_safe(fb, fk, bctx)
	var out_p := Vector2(14.0, 14.0)
	for c in bsafe:
		if (c as Vector2).distance_to(out_p) < sr + 1.0:
			out_p = Vector2(-14.0, -14.0)
	t = float(fb["start"])
	var hits := 0
	while t < float(fb["end"]) - 0.05:
		t += 0.03
		now[0] = s.round_start_ms + t * 1000.0
		s.player.position = Vector3(out_p.x, s.ground_y, out_p.y)
		s.kb_guard_left = 0.0
		s.actions.reset()
		var before: float = s.my_hp
		s.combat_update(0.03)
		if s.my_hp < before:
			hits += 1
	check(hits == int(fk["waves"]), "画面：安全地帯の外にいると、波ごとに当たる（%d 回）" % hits)
	s._exit_tree()
	root.remove_child(s)
	s.free()

	# ---- 7. 剣士をつかんですぐ投げる（1戦に1回、ランダムな時刻） ----
	var qw: Array = cfg["quick_grab_window"]
	s = make_scene(true)
	check(s.quick_grab_at >= float(qw[0]) and s.quick_grab_at <= float(qw[1]), "すぐ投げるつかみの時刻は、決めた範囲のランダム（%.1f 秒）" % s.quick_grab_at)
	var me: String = s._my_slot()
	check(s.swordsman_slots().has(me), "剣士（自分）が的になる")
	s.quick_grab_at = 2.0
	t = 0.0
	var grabbed_t := -1.0
	var thrown_t := -1.0
	var quick_count := 0
	var cur_n := -1
	while t < 40.0:
		var bp: Vector3 = s.boss.position
		if not s._me_held() and s.actions.active != "thrown":
			s.player.position = Vector3(bp.x, s.ground_y, bp.z + 4.0)
		s.my_hp = 288.75
		s.downed = false
		s.my_hits = 0.0
		t = step(s, t, 0.03)
		var c: Dictionary = s.ai.current()
		if not c.is_empty() and int(c["n"]) != cur_n:
			cur_n = int(c["n"])
			if bool(c.get("quick", false)):
				quick_count += 1
		if grabbed_t < 0.0 and s._me_held():
			grabbed_t = t
		if grabbed_t > 0.0 and thrown_t < 0.0 and s.actions.active == "thrown":
			thrown_t = t
	check(quick_count == 1 and s.quick_grab_done, "1戦に1回だけ、すぐ投げるつかみが出る（%d 回）" % quick_count)
	check(grabbed_t > 0.0 and thrown_t > 0.0, "剣士（自分）がつかまれて、投げられる")
	var quick_hold := float(acfg["kinds"]["grab"]["quick_hold_sec"]) + float(acfg["kinds"]["grab"]["release_sec"])
	check(thrown_t > 0.0 and thrown_t - grabbed_t <= quick_hold + 0.2, "つかんでから投げるまでが短い（%.2f 秒。ふつうは %.1f〜%.1f 秒）" % [thrown_t - grabbed_t, float(acfg["kinds"]["grab"]["hold_min_sec"]), float(acfg["kinds"]["grab"]["hold_max_sec"])])
	s._exit_tree()
	root.remove_child(s)
	s.free()
	# 剣士が倒れていれば、出さない（待つ）
	s = make_scene(true)
	# 版84：AIの味方が起こしに来るので、この確かめでは蘇生をなくす（倒れたままにする）
	s.config["revive"] = {"window_sec": 0.01, "hold_sec": 4.0, "hp_ratio": 0.3, "radius_factor": 2.3}
	s.revive_sys.reset()
	s.downed = true
	s.quick_grab_at = 1.0
	for slot in s.ai_allies:
		if str(s.ai_allies[slot].get("id", "")) == "hero_swordsman":
			s.ai_allies[slot]["downed"] = true
	t = 0.0
	while t < 5.0:
		t = step(s, t, 0.05)
	check(not s.quick_grab_done, "剣士が倒れている間は、すぐ投げるつかみを出さない")
	s._exit_tree()

	# ---- 2・3. 巨大酒瓶ライド ----
	var rk: Dictionary = acfg["kinds"]["bottle_ride"]
	check(int(rk["bottles_per_pass"]) == 12 and is_equal_approx(float(rk["throw_radius"]), 3.125 * 1.25), "ライド：突入ごとに12本、瓶の範囲は 3.906（3.125の1.25倍）")
	check(is_equal_approx(float(rk["half_width"]), 2.3 * 1.15), "ライド：瓶にひかれる帯の半分の幅は 2.645（2.3の1.15倍）")
	var rctx := {"n": 3, "round_start_ms": 9.0, "bounds": 15.0, "boss": Vector2.ZERO, "area": 13.0}
	var ps: Dictionary = Attacks.ride_plan(rk, rctx)[0]
	var ra := {"kind": "bottle_ride", "n": 3}
	var mid := (float(ps["start"]) + float(ps["end"])) * 0.5
	var rh: Array = Attacks.hazards(ra, mid, acfg, rctx)
	var lane: Array = rh.filter(func(h: Dictionary) -> bool: return str(h["style"]) == "ride_lane")
	var body: Array = rh.filter(func(h: Dictionary) -> bool: return str(h["style"]) == "ride")
	check(lane.size() >= 1 and body.size() == 1 and is_equal_approx(float(lane[0]["hx"]), 2.645) and is_equal_approx(float(body[0]["hx"]), 2.645), "ライド：ピンクの予告の帯と、ひかれる当たりの幅が同じ（2.645）")
	var bpos := Vector2(float(body[0]["x"]), float(body[0]["z"]))
	var side := Vector2(cos(float(body[0]["yaw"])), -sin(float(body[0]["yaw"])))
	check(Attacks.inside(body[0], (bpos + side * 2.6).x, (bpos + side * 2.6).y) and not Attacks.inside(body[0], (bpos + side * 2.7).x, (bpos + side * 2.7).y), "ライド：帯の中心から横に 2.6m は当たり、2.7m は外れ")
	check(is_equal_approx(float(acfg["kinds"]["sake_drop"]["radius"]), 2.5), "酒瓶落としの範囲は変えていない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)


func Damage_of(s: Node, ev: Dictionary) -> float:
	return float(s.role_value("attack_power")) * float(s.config["attack_multiplier"]) * float(ev["multiplier"])

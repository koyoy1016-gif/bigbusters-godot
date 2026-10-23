extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v71.gd
## 版71：AIの味方が、ボスの攻撃を先読みして、Y（かわし斬り）でよける・走ってよける・すきに攻める・体力が少ないと離れて待つ。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func circle(x: float, z: float, r: float, jumpable: bool, power: float = 10.0) -> Dictionary:
	return {"id": "t", "shape": "circle", "x": x, "z": z, "r": r, "active": true, "tele": 1.0, "power": power, "jumpable": jumpable, "target": "", "tick": -1, "style": "zone"}


func make_ally(cfg: Dictionary, pos: Vector2) -> Dictionary:
	var ccfg := CharacterData.load_config()
	# 版78：Y で跳んでよける判断を調べるので、Y が跳ぶ技（かわし斬り）の剣士で調べる（たての Y は盾の体当たりになった）
	return AiAlly.make(CharacterData.find(ccfg, "hero_swordsman"), 0, pos)


func make_ctx(cfg: Dictionary, forecast: Array, next_in: float = 99.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return {"boss": Vector2(0, 0), "boss_radius": 2.6, "bounds": 13.0, "hazards": [], "cfg": cfg, "attack_multiplier": 1.0, "rng": rng,
		"can_hit_boss": true, "drop_damage": 8.0, "slot": "p2", "forecast": forecast, "forecast_age": 0.0, "next_attack_in": next_in}


func _initialize() -> void:
	var cfg := AiAlly.load_config()
	check(cfg.has("tactics") and not cfg.has("dodge_chance"), "AIの設定：tactics がある（ランダムでよける dodge_chance はなくした）")
	cfg = cfg.duplicate(true)
	cfg["tactics"]["skill"] = 1.0  # テストでは、いつも正しく読む
	cfg["tactics"]["prefer_dodge"] = 1.0

	# ---- 1. Y の跳んでいる時間と、よけられるかの判断 ----
	var a := make_ally(cfg, Vector2(0, 4))
	var span := AiAlly.airborne_span(AiAlly.act(a))
	check(span.size() == 2 and float(span[0]) > 0.05 and float(span[1]) < 1.0 and float(span[1]) > float(span[0]) + 0.3, "Y で跳んでいる時間（%.2f〜%.2f 秒）" % [float(span[0]), float(span[1])])
	var win := AiAlly.dodge_window(AiAlly.act(a))
	check(win.size() == 2 and is_equal_approx(float(win[0]), 0.0) and is_equal_approx(float(win[1]), 0.3), "版114：Y の出始めの回避の時間（0〜0.3秒）")
	var mid := (float(span[0]) + float(span[1])) * 0.5
	check(AiAlly.dodge_covers(AiAlly.act(a), [{"dt": mid, "h": circle(0, 4, 5, true)}]), "跳んでいる間に当たる、ジャンプでよけられる攻撃は、Y でよけられる")
	check(AiAlly.dodge_covers(AiAlly.act(a), [{"dt": 0.0, "h": circle(0, 4, 5, true)}]), "版114：すぐ当たる（跳ぶ前）攻撃も、出始めの回避でよけられる")
	check(AiAlly.dodge_covers(AiAlly.act(a), [{"dt": 0.15, "h": circle(0, 4, 5, false)}]), "版114：出始めの回避の時間なら、ジャンプでよけられない攻撃もよけられる")
	check(mid > 0.3 and not AiAlly.dodge_covers(AiAlly.act(a), [{"dt": mid, "h": circle(0, 4, 5, false)}]), "跳んでいる間でも、出始めのあとなら、ジャンプでよけられない攻撃はよけられない")
	check(not AiAlly.dodge_covers(AiAlly.act(a), [{"dt": 0.95, "h": circle(0, 4, 5, true)}]), "着地のころに当たる攻撃は、Y ではよけられない")
	var th := AiAlly.threats_at(Vector2(0, 4), [{"dt": 0.5, "h": circle(0, 4, 2, true)}, {"dt": 0.3, "h": circle(9, 9, 1, true)}], 0.1, 0.5, "p2")
	check(th.size() == 1 and absf(float(th[0]["dt"]) - 0.4) < 0.001, "いまの場所に当たる物だけを、作ってからの秒を引いて数える")

	# ---- 2. 大きな、ジャンプでよけられる攻撃が来る（走っても間に合わない）→ Y でよける ----
	var ctx := make_ctx(cfg, [{"dt": mid, "h": circle(0, 4, 9, true)}])
	a["think"] = 0.0
	AiAlly.step(a, 0.016, ctx)
	check(str(AiAlly.act(a).active) == "sub" and str(a["mode"]) == "dodge" and int(a["dodges"]) == 1, "走って逃げられない、ジャンプでよけられる攻撃は、Y でよける")
	# 実際に、当たる時刻には空中にいて、当たらない
	var hp0 := float(a["hp"])
	var tt := 0.0
	while tt < mid:
		AiAlly.step(a, 0.02, make_ctx(cfg, []))
		tt += 0.02
	var done := {}
	var big := circle(float((a["pos"] as Vector2).x), float((a["pos"] as Vector2).y), 9, true)
	AiAlly.take_hazards(a, "p2", [big], done, 1.0)
	check(is_equal_approx(float(a["hp"]), hp0), "当たる時刻には空中にいて、ダメージを受けない（高さ %.1f）" % float(a["height"]))

	# ---- 3. ジャンプでよけられない攻撃が少し先に来る → 走って外へ（攻撃しない） ----
	var b := make_ally(cfg, Vector2(0, 4))
	var ctx2 := make_ctx(cfg, [{"dt": 1.2, "h": circle(0, 4, 2.5, false)}])
	b["think"] = 0.0
	AiAlly.step(b, 0.016, ctx2)
	check(str(b["mode"]) == "evade" and (b["evade"] as Vector2) != Vector2.ZERO and not AiAlly.act(b).busy(), "ジャンプでよけられない攻撃は、走って外へ出る（攻撃はしない）")
	for i in 40:
		AiAlly.step(b, 0.02, ctx2)
	check(float(Attacks.escape_of(circle(0, 4, 2.5, false), (b["pos"] as Vector2).x, (b["pos"] as Vector2).y, 0.0)["depth"]) <= 0.0, "当たる前に、範囲の外へ出た")

	# ---- 4. すき：長ければ長い攻撃、短ければ攻撃しない ----
	var c := make_ally(cfg, Vector2(0, 3.5))
	cfg["use_main_chance"] = 1.0
	var ctx3 := make_ctx(cfg, [], 5.0)
	c["think"] = 0.0
	c["think_attack"] = 0.0
	AiAlly.step(c, 0.016, ctx3)
	check(str(AiAlly.act(c).active) == "main", "すきが長い（次の攻撃まで5秒）と、長い攻撃（五段斬り）を使う")
	var d := make_ally(cfg, Vector2(0, 3.5))
	var ctx4 := make_ctx(cfg, [{"dt": 0.3, "h": circle(9, 9, 1, false)}], 0.0)
	d["think"] = 0.0
	d["think_attack"] = 0.0
	AiAlly.step(d, 0.016, ctx4)
	check(not AiAlly.act(d).busy() and float(d["window"]) < AiAlly.lock_sec(d, "normal") + 0.15, "次の攻撃がすぐ来る（すきが短い）と、攻撃を始めない（すき %.2f 秒）" % float(d["window"]))
	var e := make_ally(cfg, Vector2(0, 3.5))
	var ctx5 := make_ctx(cfg, [{"dt": 0.9, "h": circle(0, 3.5, 2.0, false)}])
	e["think"] = 0.0
	e["think_attack"] = 0.0
	AiAlly.step(e, 0.016, ctx5)
	check(str(AiAlly.act(e).active) != "main", "0.9秒後に自分の場所に当たるなら、1.5秒の五段斬りは始めない")

	# ---- 5. 体力が少ないと、すきが短いときは離れて待つ ----
	var f := make_ally(cfg, Vector2(0, 3.5))
	f["hp"] = float(f["max_hp"]) * 0.2
	f["hp_prev"] = f["hp"]
	var ctx6 := make_ctx(cfg, [], 0.3)
	f["think"] = 0.0
	AiAlly.step(f, 0.016, ctx6)
	check(bool(f["hold"]) and str(f["mode"]) == "hold" and not AiAlly.act(f).busy(), "体力が2割で、すきが短いと、攻撃せずに待つ")
	for i in 60:
		AiAlly.step(f, 0.02, ctx6)
	var reach := float((f["stats"] as Dictionary).get("attack_reach", 2.0)) + 2.6
	check((f["pos"] as Vector2).length() > reach + 1.0, "届かない所まで下がる（ボスから %.1f m）" % (f["pos"] as Vector2).length())
	var g := make_ally(cfg, Vector2(0, 3.5))
	g["hp"] = float(g["max_hp"]) * 0.2
	g["hp_prev"] = g["hp"]
	g["think"] = 0.0
	g["think_attack"] = 0.0
	AiAlly.step(g, 0.016, make_ctx(cfg, [], 5.0))
	check(not bool(g["hold"]) and AiAlly.act(g).busy(), "体力が少なくても、すきが長ければ攻撃する")
	# 当たった直後は用心（立て直し）
	var h2 := make_ally(cfg, Vector2(0, 3.5))
	h2["hp"] = float(h2["max_hp"]) - 10.0
	AiAlly.step(h2, 0.016, make_ctx(cfg, [], 0.3))
	check(float(h2["regroup"]) > 1.0, "ダメージを受けると、少しのあいだ用心する（%.1f 秒）" % float(h2["regroup"]))

	# ---- 6. ボスの攻撃の先読み（戦いの中） ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [7000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	var a1: Dictionary = s.force_attack("bat_h")
	s.current_attack = a1
	s.current_attack_u = 0.0
	var fc: Array = s.boss_forecast(2.0, 0.1)
	var first := 99.0
	for x in fc:
		first = minf(first, float(x["dt"]))
	var direct := 99.0
	var uu := 0.0
	while uu < 2.0:
		for hz in Attacks.hazards(a1, uu, s.attacks_cfg, s._attack_ctx(a1, uu, true)):
			if bool(hz["active"]):
				direct = minf(direct, uu)
		uu += 0.1
	check(not fc.is_empty() and absf(first - direct) < 0.001 and first > 0.2, "横振りの、当たる時刻を先読みできる（%.1f 秒後）" % first)
	var a2: Dictionary = s.force_attack("grab")
	s.current_attack = a2
	s.current_attack_u = 0.0
	s.grab_locked = {}
	s.boss_forecast(2.0, 0.1)
	check(s.grab_locked.is_empty(), "先読みしても、つかみの位置は決めない（本当のつかみの時刻に決める）")
	var a3: Dictionary = s.force_attack("bottle_ride")
	s.current_attack = a3
	s.current_attack_u = 1.0
	s.current_hazards = [circle(0, 0, 3, false)]
	var fr: Array = s.boss_forecast(2.0, 0.1)
	check(fr.size() == 1 and is_equal_approx(float(fr[0]["dt"]), 0.0), "巨大酒瓶ライドは先読みしない（重いので。見えている予告を、すぐ当たる物として渡す）")
	root.remove_child(s)
	s.free()

	# ---- 7. 実際の戦いで：Y でよけ、走ってよけ、攻撃もする ----
	var s2: Node = (load(SCENE) as PackedScene).instantiate()
	s2.ai_enabled = true
	root.add_child(s2)
	if s2.get_node_or_null("Boss") == null:
		s2._ready()
	var now2 := [8000000.0]
	s2.clock_ms = func() -> float: return now2[0]
	s2.sfx = null
	s2.start_round()
	var t := 0.0
	while t < 120.0 and s2.round_active():
		now2[0] += 50.0
		t += 0.05
		s2.my_hp = 999.0
		s2.downed = false
		s2.combat_update(0.05)
		s2._pose_boss(0.05)
		for slot in s2.ai_allies:
			if bool(s2.ai_allies[slot]["downed"]):
				s2.ai_allies[slot]["downed"] = false
				s2.ai_allies[slot]["hp"] = float(s2.ai_allies[slot]["max_hp"])
	var dodges := 0
	var evades := 0
	var hits := 0.0
	for slot in s2.ai_allies:
		dodges += int(s2.ai_allies[slot]["dodges"])
		evades += int(s2.ai_allies[slot]["evades"])
		hits += float(s2.ai_allies[slot]["hits"])
	check(dodges >= 1, "120秒の戦いで、AIが Y でよけた（%d 回）" % dodges)
	check(evades >= 5, "走ってよけた（%d 回）" % evades)
	check(hits > 1000.0, "攻撃もしている（与えたダメージ %.0f）" % hits)
	root.remove_child(s2)
	s2.free()

	print("")
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

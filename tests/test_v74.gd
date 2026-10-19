extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v74.gd
## 版74：剣士だけ、必殺ゲージが30%速くたまる（gauge_rate 1.3）・必殺技のダメージが30%減（ultimate_scale 0.7）。ほかのキャラは変えない。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make(character: String) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = character
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [4000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	return s


func ult_damage(s: Node) -> float:
	var bp: Vector3 = s.boss.position
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + 6.0)
	s.gauge.charge(99999.0)
	var h0: float = s.my_hits
	s.perform("ultimate")
	while s.actions.busy():
		s._actions_update(0.02)
		Engine.time_scale = 1.0
	return s.my_hits - h0


func _initialize() -> void:
	var ccfg := CharacterData.load_config()
	var hero: Dictionary = CharacterData.find(ccfg, "hero_swordsman")["stats"]
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var p1: Dictionary = cfg["roles"]["p1"]
	check(is_equal_approx(float(hero["gauge_rate"]), 1.3) and is_equal_approx(float(p1["gauge_rate"]), 1.3), "剣士：ゲージのたまる速さ1.3倍（キャラを選んだとき・選ばないとき）")
	check(is_equal_approx(float(hero["ultimate_scale"]), 0.7) and is_equal_approx(float(p1["ultimate_scale"]), 0.7), "剣士：必殺技のダメージ0.7倍")
	var others_plain := true
	for c in ccfg["characters"]:
		if str(c["id"]) != "hero_swordsman" and ((c.get("stats", {}) as Dictionary).has("gauge_rate") or (c.get("stats", {}) as Dictionary).has("ultimate_scale")):
			others_plain = false
	check(others_plain, "ほかのキャラには、どちらも付けない（1倍のまま）")

	# 自分が剣士：同じダメージで、ゲージは1.3倍たまる。必殺技は 346.5
	for ch in ["", "hero_swordsman"]:
		var s := make(ch)
		var g0: float = s.gauge.value
		s._damage_boss(100.0)
		var got: float = s.gauge.value - g0
		check(is_equal_approx(got, 100.0 * float(s.gauge.gain) * 1.3), "剣士（%s）：100ダメージでゲージ %.1f（ほかのキャラの1.3倍）" % ["選ばない" if ch == "" else ch, got])
		var full_need := float(s.gauge.max_value) / (float(s.gauge.gain) * 1.3)
		check(absf(full_need - 808.0) < 2.0, "剣士は約808ダメージでゲージがいっぱい（前は約1050。%.0f）" % full_need)
		s.gauge.value = 0.0
		var d := ult_damage(s)
		check(is_equal_approx(d, 22.5 * 22.0 * 0.7), "剣士の必殺技は 346.5 ダメージ（495の0.7倍。%.1f）" % d)
		root.remove_child(s)
		s.free()

	# ほかのキャラ（ガンナー）は変わらない
	var g := make("gunner")
	var gs: Dictionary = CharacterData.find(ccfg, "gunner")["stats"]
	var g0b: float = g.gauge.value
	g._damage_boss(100.0)
	check(is_equal_approx(g.gauge.value - g0b, 100.0 * float(g.gauge.gain)), "ほかのキャラ：ゲージのたまり方は変わらない")
	g.gauge.value = 0.0
	var gd := ult_damage(g)
	# 版78：ガンナーの必殺技はキャラ専用（フルバースト：2.3倍×10回）。ultimate_scale はかからない（1倍）
	var gm := 0.0
	for h in g.actions.def("ultimate")["hits"]:
		gm += float(h["multiplier"])
	check(gd > 0.0 and gd <= float(gs["attack_power"]) * gm + 0.01, "ほかのキャラ：必殺技は ultimate_scale がかからない（%.1f ／ 最大 %.1f）" % [gd, float(gs["attack_power"]) * gm])
	root.remove_child(g)
	g.free()

	# AIの剣士も同じ（ゲージ1.3倍・必殺技0.7倍）。AIのガーディアンは変わらない
	var acfg := AiAlly.load_config()
	for id in ["hero_swordsman", "guardian"]:
		var a := AiAlly.make(CharacterData.find(ccfg, id), 0, Vector2(0, 3.5))
		var st: Dictionary = a["stats"]
		var rng := RandomNumberGenerator.new()
		var ctx := {"boss": Vector2(0, 0), "boss_radius": 2.6, "cfg": acfg, "attack_multiplier": 1.0, "can_hit_boss": true, "rng": rng}
		var gauge = a["gauge"]
		var v0: float = gauge.value
		var dmg := AiAlly._resolve_hit(a, {"action": "normal", "multiplier": 1.0, "radius_scale": 1.0}, ctx)
		var rate := 1.3 if id == "hero_swordsman" else 1.0
		check(is_equal_approx(gauge.value - v0, dmg * float(gauge.gain) * rate), "AIの%s：ゲージは %.1f 倍でたまる" % [id, rate])
		a["ult_from"] = Vector2(0, 3.5)
		var ud := AiAlly._resolve_hit(a, {"action": "ultimate", "multiplier": 22.0, "radius_scale": 2.4}, ctx)
		var want := float(st["attack_power"]) * 22.0 * float(acfg["damage_scale"]) * (0.7 if id == "hero_swordsman" else 1.0)
		check(is_equal_approx(ud, want), "AIの%s：必殺技 %.1f ダメージ" % [id, ud])

	print("")
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_ultimate.gd
## 必殺技「切り捨て御免」（ゲージ、プレイヤー、CPU、技名の表示）と、ボスの中に入りこまない動き。

const Gauge := preload("res://scripts/combat/ultimate_gauge.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const Ai := preload("res://scripts/combat/ai_ally.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0
var now := [1000000.0]


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg := Actions.load_config()
	var ult: Dictionary = cfg["actions"]["ultimate"]
	check(str(ult["name"]) == "切り捨て御免" and cfg["order"].has("ultimate"), "必殺技の名前は、切り捨て御免")
	check(str(cfg["actions"]["normal"]["name"]) == "単純斬り" and str(cfg["actions"]["sub"]["name"]) == "かわし斬り" and str(cfg["actions"]["main"]["name"]) == "五段斬り", "通常・サブ・メインの技名（仮）")
	check(float(ult["duration_sec"]) < 1.5 and (ult["hits"] as Array).size() == 1, "必殺技は、一撃で、短い")
	var dash_t := 0.0
	var path: Array = ult["path"]
	for i in range(1, path.size()):
		if float(path[i]["fwd"]) - float(path[i - 1]["fwd"]) > 1.0:
			dash_t += float(path[i]["t"]) - float(path[i - 1]["t"])
	check(dash_t <= 0.2, "斬りぬける動きは、とても速い（%.2f秒）" % dash_t)

	# ゲージ
	var g := Gauge.new(cfg)
	check(not g.is_ready() and g.ratio() == 0.0, "ゲージは空で始まる")
	g.charge(float(cfg["ultimate_gauge"]["max"]) * 0.5 / float(cfg["ultimate_gauge"]["gain_per_damage"]))
	check(is_equal_approx(g.ratio(), 0.5) and not g.consume(), "半分では、使えない")
	g.charge(99999.0)
	check(g.is_ready() and g.ratio() == 1.0, "いっぱいになる（あふれない）")
	check(g.consume() and g.value == 0.0, "使うと空になる")

	# ボスの手前で止まる
	var boss := Vector2(0, -6)
	check(is_equal_approx(HitArea.clip_forward(Vector2(0, 6), Vector2(0, -1), 5.0, boss, 3.0), 5.0), "遠ければ、そのまま進む")
	var clipped := HitArea.clip_forward(Vector2(0, -1), Vector2(0, -1), 5.0, boss, 3.0)
	check(clipped > 1.5 and clipped < 2.1, "近ければ、ボスの手前で止まる（%.2f）" % clipped)
	check(HitArea.clip_forward(Vector2(0, -3), Vector2(0, -1), 5.0, boss, 3.0) == 0.0, "すでに近いときは、進まない")
	check(HitArea.clip_forward(Vector2(0, -3), Vector2(0, 1), -2.0, boss, 3.0) == -2.0, "後ろへ下がるのは止めない")

	# プレイヤー
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	var bz := float(s.config["boss_position"][1])
	s.player.position = Vector3(0.0, s.ground_y, bz + 8.0)
	check(not s.perform("ultimate"), "ゲージが空のうちは、必殺技は出ない")
	s.gauge.charge(99999.0)
	var hp0: float = s.boss_hp
	check(s.perform("ultimate") and s.gauge.value == 0.0, "ゲージがいっぱいなら、必殺技が出て、ゲージが空になる")
	check(str(s.banner["text"]) == "切り捨て御免" and float(s.banner["left"]) > 1.0, "画面に、必殺技名が出る")
	check(s.actions.invulnerable(), "必殺技の間は、ダメージを受けない")
	var guard := 0
	while s.actions.busy() and guard < 300:
		s._process(0.016)
		now[0] += 16.0
		guard += 1
	var dealt: float = hp0 - s.boss_hp
	var power: float = s.role_value("attack_power")
	check(dealt > power * 15.0, "必殺技は、一撃でとても大きなダメージ（%.0f）" % dealt)
	var dist: float = Vector2(s.player.position.x - s.boss.position.x, s.player.position.z - s.boss.position.z).length()
	check(dist >= float(s.config["boss_size"]) * 0.5, "ボスの体の中には入りこまない（距離 %.2f）" % dist)
	# 時間がたてば、技名は消える
	for i in 200:
		s._process(0.016)
	check(float(s.banner["left"]) == 0.0, "技名は、しばらくして消える")
	# 通常攻撃では、ゲージがたまる
	s.actions.reset()
	s.player.position = Vector3(0.0, s.ground_y, bz + 3.0)
	s.attack()
	check(s.gauge.value > 0.0, "ボスに当てると、ゲージがたまる")
	root.remove_child(s)
	s.free()

	# CPU
	var chars := CharacterData.load_config()
	var hero := CharacterData.find(chars, "hero_swordsman")
	var a := Ai.make(hero, 0, Vector2(0, -6.0 + 4.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var acfg := Ai.load_config()
	var ctx := {"boss": Vector2(0, -6.0), "boss_radius": 1.7, "bounds": 14.0, "hazards": [], "cfg": acfg, "attack_multiplier": 1.0, "rng": rng, "can_hit_boss": true, "slot": "p2", "drop_damage": 8.0}
	check(str(a["banner"]) == "", "CPUの必殺技名は、はじめは空")
	(a["gauge"] as Gauge).charge(99999.0)
	var total := 0.0
	var announced := ""
	for i in 40:
		total += Ai.step(a, 0.05, ctx)
		if str(a["banner"]) != "":
			announced = str(a["banner"])
	check(announced == "切り捨て御免", "CPUも、ゲージがたまれば必殺技を使い、技名が出る")
	check((a["gauge"] as Gauge).value < float(cfg["ultimate_gauge"]["max"]), "CPUのゲージは、使うと減る")
	var one := float(hero["stats"]["attack_power"]) * float(acfg["damage_scale"])
	check(total >= one * 20.0, "CPUの必殺技も、大きなダメージ（%.0f）" % total)
	# CPUは、必殺技の名前を、使った瞬間の1コマだけ出す
	var b := Ai.make(hero, 1, Vector2(0, -2.0))
	(b["gauge"] as Gauge).charge(99999.0)
	var announce_count := 0
	for i in 40:
		Ai.step(b, 0.05, ctx)
		if str(b["banner"]) != "":
			announce_count += 1
	check(announce_count == 1, "技名は、使った1回につき1回だけ")
	# ボスの体に入りこまない
	var bpos: Vector2 = b["pos"]
	check(bpos.distance_to(Vector2(0, -6.0)) >= 1.7, "CPUも、ボスの体の中に入りこまない")

	print("")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

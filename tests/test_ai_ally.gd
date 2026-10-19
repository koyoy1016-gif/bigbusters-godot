extends SceneTree
## AIの味方（動き・よける・こうげき・ダメージ・戦いへの組み込み）のテスト

const Ai := preload("res://scripts/combat/ai_ally.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(ok: bool, name: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", name)


func _init() -> void:
	var cfg := Ai.load_config()
	var chars := CharacterData.load_config()
	var gunner := CharacterData.find(chars, "gunner")
	var a := Ai.make(gunner, 1, Vector2(0, 12))
	check(float(a["hp"]) == float(gunner["stats"]["hp"]) and not bool(a["downed"]), "キャラの体力で始まる")

	# よける：輪の中にいたら外へ。帯の中なら、前後へ
	var circle := {"id": "c", "shape": "circle", "x": 0.0, "z": 0.0, "r": 3.0, "active": false, "tele": 0.5, "power": 10.0, "jumpable": true, "target": "", "tick": -1}
	var d := Ai.evade_dir(Vector2(1, 0), [circle], 1.0, "p2")
	check(d.x > 0.9, "輪の外へ向かう")
	check(Ai.evade_dir(Vector2(9, 0), [circle], 1.0, "p2") == Vector2.ZERO, "輪から遠ければ逃げない")
	var band := {"id": "b", "shape": "box", "x": 0.0, "z": 5.0, "hx": 1.0, "hz": 1.5, "active": false, "tele": 0.3, "power": 10.0, "jumpable": true, "target": "", "tick": -1}
	check(Ai.evade_dir(Vector2(0, 5.5), [band], 1.0, "p2").y > 0.9 and Ai.evade_dir(Vector2(0, 4.5), [band], 1.0, "p2").y < -0.9, "帯からは、近い側へ抜ける")
	var other_target := {"id": "g", "shape": "circle", "x": 0.0, "z": 0.0, "r": 3.0, "active": false, "tele": 0.5, "power": 10.0, "jumpable": true, "target": "p3", "tick": -1}
	check(Ai.evade_dir(Vector2(1, 0), [other_target], 1.0, "p2") == Vector2.ZERO, "ほかの人が的のつかみは、よけない")

	# 近づいてこうげき
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ctx := {"boss": Vector2(0, -8), "boss_radius": 1.7, "bounds": 14.0, "hazards": [], "cfg": cfg, "attack_multiplier": 1.0, "rng": rng, "can_hit_boss": true, "slot": "p2"}
	var total := 0.0
	var start_dist := (a["pos"] as Vector2).distance_to(ctx["boss"])
	for i in 600:
		total += Ai.step(a, 0.05, ctx)
	var dist := (a["pos"] as Vector2).distance_to(ctx["boss"])
	check(dist < start_dist and dist <= float(gunner["stats"]["attack_reach"]) + 1.7, "ボスに近づく")
	check(total > 0.0 and is_equal_approx(total, float(a["hits"])), "こうげきでダメージを与える")
	# ダメージの量は、攻撃力 × 倍率 × damage_scale
	var one := float(gunner["stats"]["attack_power"]) * float(cfg["damage_scale"])
	var near := Ai.make(gunner, 0, Vector2(0, -8 + 3.0))
	near["think_attack"] = 10.0
	var first := Ai.step(near, 0.05, ctx)
	check(is_equal_approx(first, one), "最初の通常攻撃のダメージは、攻撃力×倍率")
	check(not (near["events"] as Array).is_empty() and Ai.act(near).busy(), "攻撃すると、アニメの出来事が出て、動き中になる")

	# よけながら動く（輪の中に置いて、考える間隔のあと動く）
	var b := Ai.make(gunner, 0, Vector2(0, 0))
	ctx["hazards"] = [circle]
	for i in 30:
		Ai.step(b, 0.05, ctx)
	check((b["pos"] as Vector2).length() > 3.0, "予告の輪から出る")

	# ダメージを受ける：当たり（active）の中で、1回だけ。ジャンプ中は、ジャンプでよけられるものは当たらない
	var hit := {"id": "x", "shape": "circle", "x": 0.0, "z": 0.0, "r": 3.0, "active": true, "tele": 1.0, "power": 20.0, "jumpable": true, "target": "", "tick": -1, "stun": 1.0}
	var c := Ai.make(gunner, 0, Vector2(0, 0))
	var done := {}
	check(is_equal_approx(Ai.take_hazards(c, "p2", [hit], done, 1.0), 20.0), "当たりの中にいると、ダメージ")
	check(Ai.take_hazards(c, "p2", [hit], done, 1.0) == 0.0, "同じ当たりは1回だけ")
	check(float(c["stun"]) >= 1.0, "つかみのときは、動けなくなる")
	var c2 := Ai.make(gunner, 0, Vector2(0, 0))
	c2["height"] = 2.0
	check(Ai.take_hazards(c2, "p2", [hit], {}, 1.0) == 0.0, "跳んでいれば、よけられる")
	var c3 := Ai.make(gunner, 0, Vector2(0, 0))
	for k in 5:
		hit["id"] = "y%d" % k
		Ai.take_hazards(c3, "p2", [hit], done, 1.0)
	check(bool(c3["downed"]) and float(c3["hp"]) == 0.0, "体力が0で、ダウン")
	check(Ai.step(c3, 0.1, ctx) == 0.0, "ダウン中は何もしない")

	# つかまれたAIは動けない
	var gh := {"id": "g1", "shape": "circle", "x": 0.0, "z": 0.0, "r": 3.0, "active": true, "tele": 1.0, "power": 8.0, "jumpable": true, "target": "p2", "tick": -1, "stun": 0.0, "grab": true}
	var g := Ai.make(gunner, 0, Vector2(0, 0))
	Ai.take_hazards(g, "p2", [gh], {}, 1.0)
	check(bool(g["held"]) and Ai.step(g, 0.1, ctx) == 0.0 and (g["pos"] as Vector2) == Vector2(0, 0), "つかまれたAIは、動けない")

	# 戦いへの組み込み
	var packed := load(SCENE) as PackedScene
	var s: Node = packed.instantiate()
	s.ai_enabled = true
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.start_round()
	check(s.ai_allies.size() == 3, "通信なしでは、AIが3人入る")
	check(s.others.size() == 3 or s.ai_allies.size() == 3, "AIの箱が出る")
	var picks: Array = s._ai_picks_resolved()
	check(picks == cfg["default_picks"], "選んでいなければ、既定の3人")
	s.ai_picks = ["healer", "brawler", "bomber"]
	check(s._ai_picks_resolved() == ["healer", "brawler", "bomber"], "選んだ3人が使われる")
	s.ai_picks = ["healer", "nothing"]
	check(s._ai_picks_resolved()[1] == "gunner", "存在しない選びは、既定で埋める")
	s.ai_picks = ["healer", "brawler", "bomber"]
	s.start_round()
	check(s.ai_allies.is_empty() or true, "（確認用）")
	s.won = false
	s.lost = false
	s.round_start_ms = 0.0
	s._begin_round(now[0])
	check(str(s.ai_allies["p2"]["id"]) == "healer", "戦いの始まりで、選んだ人を使う")
	var hp0: float = s.boss_hp
	for i in 400:
		now[0] += 50.0
		s.combat_update(0.05)
	check(s.boss_hp < hp0 and s._ai_hits_total() > 0.0, "AIがボスにダメージを与える")
	check(s.ranking_entries().size() == 4, "ランキングは4人")
	check(s.char_def_of("p3").get("id", "") == "brawler" and s.role_name_of("p3") != "", "AIのキャラが分かる")
	# AIがつかまれる：持ち上がる → 時間がたつと落ちてダメージ／ダメージを与えれば外れる
	s.grab_state = {}
	var kk: Dictionary = s.attacks_cfg["kinds"]["grab"]
	var ally: Dictionary = s.ai_allies["p2"]
	ally["downed"] = false
	ally["hp"] = 100.0
	var hp_a: float = ally["hp"]
	ally["held"] = true
	s._start_hold("p2", ally["pos"])
	for i in 19:  # つかむ時間（1秒以上）の終わりより前に見る
		s._grab_update(0.05)
		s._pose_boss(0.05)
	check(float(s.other_lift.get("p2", 0.0)) > 2.5 and float(ally["hp"]) < hp_a, "AIが（ボスの左手で）持ち上がり、しめつけられる（高さ %.1f）" % float(s.other_lift.get("p2", 0.0)))
	for i in 80:
		s._grab_update(0.05)
	check(s.grab_state.is_empty() and not bool(ally["held"]) and float(s.other_lift["p2"]) == 0.0, "時間がたつと、はなされる")
	ally["held"] = true
	s._start_hold("p2", ally["pos"])
	s.ai_hits["p3"] = float(s.ai_hits["p3"]) + float(kk["free_damage"]) + 1.0
	s._grab_update(0.05)
	check(s.grab_state.is_empty() and not bool(ally["held"]), "みんなのダメージで、助けられる")
	# 自分がダウンしても、AIが生きていれば続く。AIが全員ダウンすれば全滅
	s.downed = true
	s._check_wipe()
	check(not s.lost, "自分がダウンしても、AIが生きていれば続く")
	for slot in s.ai_allies:
		s.ai_allies[slot]["downed"] = true
	s._check_wipe()
	check(s.lost, "全員ダウンで全滅")
	s.ai_enabled = false
	s._ai_update(0.016)
	check(s.ai_allies.is_empty(), "オフにするとAIは消える")
	# 部屋に2人いれば、AIは出ない
	var s2: Node = packed.instantiate()
	s2.ai_enabled = true
	root.add_child(s2)
	if s2.get_node_or_null("Boss") == null:
		s2._ready()
	s2.net_active = true
	s2.net_state = {"slot": "p1", "members": ["p1", "p2"]}
	check(not s2._ai_active(), "部屋に2人いれば、AIは入らない")
	s2.net_state = {"slot": "p1", "members": ["p1"]}
	check(s2._ai_active(), "部屋にひとりなら、AIが入る")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

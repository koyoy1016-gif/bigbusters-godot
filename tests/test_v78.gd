extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v78.gd
## 版78：8人の味方の、キャラごとの攻撃（A・Y・X・必殺）。data/char_actions.json・scripts/combat/skill_hits.gd・scripts/prototype/battle_skills.gd。
## 確かめること：剣士は変わらない／キャラを選ぶと、そのキャラの攻撃になる／当たりの形（ビーム・爆発・まわり）／ダブルビームは2本とも当たる／
## 20連パンチは20回／超高速モード・ドーム・回復・蘇生・時間停止・呼び出しの効果／回復に乱数がない／動き（アニメ）が全部ある

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const SkillHits := preload("res://scripts/combat/skill_hits.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const CV := preload("res://scripts/characters/character_view.gd")
const IDS := ["brawler", "sprinter", "gunner", "bomber", "mage", "guardian", "summoner", "healer"]
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make(char_id: String, ai_on: bool = false) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = char_id
	s.ai_enabled = ai_on
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	return s


## ボスを止めて（攻撃されないように）、ボスの前 gap m に立ち、技 id を最後まで流す。与えたダメージを返す
func run_action(s: Node, id: String, gap: float, sec: float = -1.0) -> float:
	s.skill_time_stop_left = 999.0
	var bp: Vector3 = s.boss.position
	var br := float(s.config["boss_size"]) * 0.5
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + gap)
	s.facing = Vector2(0, -1)
	if id == "ultimate":
		s.gauge.value = s.gauge.max_value
	var h0: float = s.my_hits
	var ok: bool = s.perform(id)
	if not ok:
		return -1.0
	var dur: float = float(s.actions.def(id).get("duration_sec", 0.5)) if sec < 0.0 else sec
	var t := 0.0
	# 版79：飛ぶ物（銃弾・魔法・プレゼント）は、技が終わった後に当たることがある。少し長く流す
	while t < dur + 2.6:
		s._actions_update(0.05)
		s.combat_update(0.05)
		t += 0.05
	return float(s.my_hits) - h0


func ap(id: String) -> float:
	return float(CD.find(CD.load_config(), id)["stats"]["attack_power"])


func total_mult(s: Node, id: String) -> float:
	var t := 0.0
	for h in s.actions.def(id).get("hits", []):
		t += float(h["multiplier"])
	return t


func _initialize() -> void:
	# ---- 1. 設定の読み方 ----
	var base := Actions.load_config()
	check(not Actions.config_for("hero_swordsman").has("character"), "剣士は共通の actions.json のまま")
	check(str(Actions.config_for("hero_swordsman")["actions"]["main"]["name"]) == "五段斬り", "剣士の X は五段斬り（変えない）")
	for id in IDS:
		var c := Actions.config_for(id)
		var ok := true
		for k in ["normal", "sub", "main", "ultimate"]:
			if c["actions"][k] == base["actions"][k]:
				ok = false
		check(str(c.get("character", "")) == id and ok and c["actions"].has("thrown"), "%s：A・Y・X・必殺がキャラ専用（投げられる・ふっ飛びは共通のまま）" % id)

	# ---- 2. 当たりの形 ----
	var beam := {"shape": "beam", "length": 10.0, "half_width": 0.5, "side": 0.0}
	check(SkillHits.hits(beam, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(0, -9), 1.0), "ビーム：前 9m に当たる")
	check(not SkillHits.hits(beam, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(3, -5), 1.0), "ビーム：横 3m には当たらない")
	check(SkillHits.hits({"shape": "beam", "length": 10.0, "half_width": 0.3, "side": 1.0}, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(1, -5), 0.1)
		and not SkillHits.hits({"shape": "beam", "length": 10.0, "half_width": 0.3, "side": -1.0}, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(1, -5), 0.1),
		"ビーム：side で左右にずれる（ダブルビームの2本）")
	var blast := {"shape": "blast", "at_boss": true, "max_dist": 7.0, "radius": 2.0}
	check(SkillHits.hits(blast, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(0, -6), 1.5), "爆発：届く所のボスに当たる")
	check(not SkillHits.hits(blast, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(0, -12), 1.5), "爆発：遠すぎるボスには当たらない（7m まで）")
	check(SkillHits.hits({"shape": "self", "radius": 4.0}, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2(4, 0), 0.5), "まわり：半径の中は、どの向きでも当たる")

	# ---- 3. キャラごとに、A・Y・X・必殺を実際に使う ----
	for id in IDS:
		var s := make(id)
		check(str(s.actions.cfg.get("character", "")) == id, "%s：選ぶと、そのキャラの攻撃になる" % id)
		for k in ["normal", "sub", "main", "ultimate"]:
			var def: Dictionary = s.actions.def(k)
			var gap := 1.0
			var dealt := run_action(s, k, gap)
			var want := total_mult(s, k) * ap(id) * float(s.config["attack_multiplier"])
			if def.get("hits", []).is_empty():
				check(dealt >= 0.0, "%s %s（%s）：使える（効果の技）" % [id, k, def.get("name", "")])
			else:
				check(dealt > 0.0 and dealt <= want + 0.01, "%s %s（%s）：当たる（%.1f ／ 全部当たれば %.1f）" % [id, k, def.get("name", ""), dealt, want])
			s.actions.reset()
		s.queue_free()

	# ---- 4. 決まりの技 ----
	var f := make("brawler")
	check((f.actions.def("main")["hits"] as Array).size() == 20, "ファイター：20連パンチは20回")
	var d20 := run_action(f, "main", 0.8)
	var w20 := (19.0 * 0.38 + 1.6) * ap("brawler")  # 版79：19発＋しめの大きな1発
	check(is_equal_approx(d20, w20), "20連パンチは、1発ずつ計算して全部当たると %.1f（%.1f）" % [w20, d20])
	f.queue_free()

	var g := make("gunner")
	var hs: Array = g.actions.def("main")["hits"]
	var sides := {}
	for h in hs:
		sides[float(h.get("side", 0.0))] = true
	# 版80：ガンナーの X は、ビームをやめて「ダブル連射」（左右かわるがわる12発の弾）。ダメージの合計は同じ
	check(hs.size() == 12 and sides.size() == 2, "ダブル連射：左右から12発")
	var dg := run_action(g, "main", 4.0)
	check(is_equal_approx(dg, 12.0 * 0.5 * ap("gunner")), "ダブル連射：12発とも同じボスに当たる（%.2f）" % dg)
	check(g.skill_log.count("fire") >= 12 and g.skill_fx_log.count("beam") == 0, "ダブル連射：弾を12発撃つ（ビームは出ない）")
	g.queue_free()

	var sp := make("sprinter")
	run_action(sp, "main", 1.0)
	check(is_equal_approx(sp.skills.speed_mult(sp._my_slot()), 1.75), "超高速モード：速さ1.75倍")
	check(is_equal_approx(sp.actions.cd_rate, 1.75), "超高速モード：待ち時間の減りも1.75倍")
	var p0: Vector3 = sp.player.position
	sp.skill_time_stop_left = 999.0
	sp.stick_vec = Vector2(1, 0)
	sp._process(0.1)
	var moved := Vector2(sp.player.position.x - p0.x, sp.player.position.z - p0.z).length()
	check(absf(moved - 10.0 * 1.75 * 0.1) < 0.05, "超高速モード：走る速さ 10×1.75 m/秒（%.2f m/0.1秒）" % moved)
	sp.stick_vec = Vector2.ZERO
	sp.queue_free()

	var ar := make("guardian")
	run_action(ar, "main", 1.0)
	check(is_equal_approx(ar.skills.dealt_mult(), 0.25) and is_equal_approx(ar.skills.taken_mult(), 0.25), "ドーム：攻撃力50%低下 × 受けるダメージ50%軽減（敵も味方も 0.25 倍）")
	var hp0: float = ar.my_hp
	ar._take_damage(40.0)
	check(is_equal_approx(hp0 - ar.my_hp, 10.0), "ドームの間、40のダメージは10になる")
	ar.skill_domes = []  # 版79：膜は skill_domes
	check(is_equal_approx(ar.skills.dealt_mult(), 1.0), "ドームが消えたら元にもどる")
	ar.queue_free()

	var hl := make("healer", true)
	hl.skill_time_stop_left = 999.0
	hl._set_my_hp(50.0)
	var aslot: String = hl.ai_allies.keys()[0]
	hl.ai_allies[aslot]["hp"] = 0.0
	hl.ai_allies[aslot]["downed"] = true
	hl.ai_allies[aslot]["pos"] = Vector2(hl.player.position.x + 1.0, hl.player.position.z)
	hl.skills.apply_effect(hl._my_slot(), {"type": "heal", "amount": 40.0, "radius": 7.0}, Vector2(0, -1), 7.5)
	check(is_equal_approx(hl.my_hp, 90.0), "ヒール：40ちょうど回復（乱数・クリティカルなし）")
	hl.skills.apply_effect(hl._my_slot(), {"type": "revive", "radius": 10.0, "hp_ratio": 0.5}, Vector2(0, -1), 7.5)
	check(not bool(hl.ai_allies[aslot]["downed"]) and is_equal_approx(float(hl.ai_allies[aslot]["hp"]), float(hl.ai_allies[aslot]["max_hp"]) * 0.5), "天使の祈り：倒れた味方を体力50%で起こす")
	hl.queue_free()

	var mg := make("mage")
	mg.skill_time_stop_left = 0.0
	mg.skills.apply_effect(mg._my_slot(), {"type": "time_stop", "sec": 3.0, "resist_sec": 20.0, "resist_mult": 0.5}, Vector2(0, -1), 18.0)
	check(mg.skills.boss_frozen() and is_equal_approx(mg.skill_time_stop_left, 3.0), "時間停止：ボスが3秒止まる")
	var pos0: Vector3 = mg.boss.position
	var n0: int = mg.last_attack_n
	for i in 40:
		mg.combat_update(0.05)
	check(mg.boss.position == pos0 and mg.last_attack_n == n0 and mg.current_hazards.is_empty(), "止まっている間は、ボスは動かず、攻撃もしない")
	check(absf(mg.boss_freeze_total - 2.0) < 0.06, "止まった時間をボスの時計から引く（%.2f 秒）" % mg.boss_freeze_total)
	mg.skill_time_stop_left = 0.0
	mg.skills.apply_effect(mg._my_slot(), {"type": "time_stop", "sec": 3.0, "resist_sec": 20.0, "resist_mult": 0.5}, Vector2(0, -1), 18.0)
	check(is_equal_approx(mg.skill_time_stop_left, 1.5), "すぐまた止めると、ボスの耐性で半分（1.5秒）")
	mg.queue_free()

	var ty := make("summoner")
	ty.skill_time_stop_left = 999.0
	ty.skills.apply_effect(ty._my_slot(), {"type": "summon", "unit": "plush", "count": 5, "sec": 10.0, "interval": 1.0, "multiplier": 0.6, "speed": 5.0, "reach": 1.0, "max_active": 7},
		Vector2(0, -1), ap("summoner"))
	check(ty.skill_summons.size() == 5, "ぬいぐるみ部隊：5体出る")
	var h1: float = ty.my_hits
	for i in 200:
		ty.combat_update(0.05)
	var hits_s: float = ty.my_hits - h1
	check(hits_s > 0.0 and is_equal_approx(fmod(hits_s, 0.6 * ap("summoner")), 0.0) or is_equal_approx(fmod(hits_s, 0.6 * ap("summoner")), 0.6 * ap("summoner")),
		"ぬいぐるみが歩いてボスを攻撃する（1回 %.2f、合計 %.1f）" % [0.6 * ap("summoner"), hits_s])
	ty.skills.apply_effect(ty._my_slot(), {"type": "summon", "unit": "plush", "count": 5, "sec": 10.0, "max_active": 7}, Vector2(0, -1), 9.0)
	var alive := 0
	for u in ty.skill_summons:
		if float(u["life"]) > 0.0:
			alive += 1
	check(alive <= 7, "同時に出せるのは7体まで（%d）" % alive)
	ty.queue_free()

	# ---- 5. 動き（アニメ）：キャラの技の動きが全部ある ----
	var cfg := CD.load_config()
	for id in IDS:
		var def := CD.find(cfg, id)
		var v: Node3D = CV.new()
		root.add_child(v)
		v.setup(def)
		var miss: Array = []
		var acfg := Actions.config_for(id)
		for k in ["normal", "sub", "main", "ultimate"]:
			for st in acfg["actions"][k].get("steps", []):
				var an := CD.animation_for(def, str(st["anim"]))
				if an == "" or not v.player.has_animation(an):
					miss.append(st["anim"])
				else:
					var dur := float(acfg["actions"][k].get("duration_sec", 0.5))
					var len: float = v.player.get_animation(an).length
					if absf(len - dur) > 0.05 and not bool(acfg["actions"][k].get("duration_from_cooldown", false)):
						miss.append("%s（長さ %.2f／技 %.2f）" % [st["anim"], len, dur])
		check(miss.is_empty(), "%s：技の動きがそろっていて、長さが技と同じ %s" % [id, str(miss)])
		v.queue_free()
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v112.gd
## 版112：演出。必殺技の名前（役職の色・画面に入る大きさ）・敵の登場（試合に1回）・ボスの覚醒（1回）・
## 敵の攻撃の名前（右上・攻撃の始まりと同じ時・入れかえ・ためない）。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const CD := preload("res://scripts/characters/character_data.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func count(arr: Array, prefix: String) -> int:
	return arr.filter(func(x: Variant) -> bool: return str(x).begins_with(prefix)).size()


func _initialize() -> void:
	# ---- 1. 名前と字 ----
	var acfg := Attacks.load_config()
	var names: Dictionary = acfg.get("display_names", {})
	var missing_names: Array = []
	for kind in acfg["kinds"]:
		var forms: Dictionary = ((acfg["kinds"][kind] as Dictionary).get("ai", {}) as Dictionary).get("forms", {})
		if not forms.is_empty() and str(names.get(kind, "")) == "":
			missing_names.append(kind)
	check(missing_names.is_empty(), "ボスが使う攻撃には、全部名前がある %s" % str(missing_names))
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "summoner"
	s.ai_enabled = false
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [6000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	var font: Font = load("res://assets/fonts/NotoSansJP-Regular-subset.ttf")
	var texts: Array = names.values()
	for key in ["enemy_intro", "awakening_fx", "enemy_attack_label"]:
		for v in (s.config[key] as Dictionary).values():
			if v is String and not str(v).begins_with("#"):
				texts.append(v)
	var lack := ""
	for t in texts:
		for ch in str(t):
			if ch != " " and not font.has_char(ch.unicode_at(0)) and not lack.contains(ch):
				lack += ch
	check(lack == "", "演出の字が、ゲームの字（フォント）にある：" + lack)

	# ---- 2. 敵の登場：試合の始めに1回 ----
	s.start_round()
	var ec: Dictionary = s.config["enemy_intro"]
	check(count(s.cue_log, "intro") == 1 and is_equal_approx(float(s.enemy_intro["left"]), float(ec["sec"])), "試合が始まると、敵の登場が1回出る")
	check(str(s.enemy_intro["name"]) == str(ec["name"]) and str(s.enemy_intro["role"]) == "BOSS" and str(ec["title"]) == "ENEMY APPROACH",
		"ENEMY APPROACH・敵の名前（%s）・役（BOSS）" % str(ec["name"]))
	s.skill_time_stop_left = 999.0
	for i in 60:
		s.update_cues(0.05)
		s.combat_update(0.05)
	check(count(s.cue_log, "intro") == 1 and float(s.enemy_intro["left"]) == 0.0, "戦いが進んでも、もう出ない（%.1f 秒で消える）" % float(ec["sec"]))
	check(float(ec["sec"]) < float(acfg["first_delay_sec"]), "登場は、ボスの最初の攻撃の前に終わる")

	# ---- 3. 敵の攻撃の名前：攻撃の始まりと同じ時・入れかえ・ためない ----
	s.skill_time_stop_left = 0.0
	now[0] += 30000.0
	var a1: Dictionary = s.force_attack("bat_h")
	s.combat_update(0.016)
	check(str(s.enemy_attack["text"]) == "横振り" and int(s.enemy_attack["n"]) == int(a1["n"]) and float(s.enemy_attack["left"]) > 0.0 and not bool(s.enemy_attack["ult"]),
		"攻撃が始まると、右上に名前（横振り）")
	for i in 5:
		s.update_cues(0.016)
		s.combat_update(0.016)
	check(count(s.cue_log, "attack:") == 1, "同じ攻撃の間は、名前を出し直さない")
	now[0] += 500.0
	s.force_attack("bat_v")
	s.combat_update(0.016)
	check(str(s.enemy_attack["text"]) == "縦振り＋衝撃波" and count(s.cue_log, "attack:") == 2, "次の攻撃で、名前を入れかえる（前の名前は消える）")
	check(s.enemy_attack is Dictionary and float(s.enemy_attack["left"]) == float(s.config["enemy_attack_label"]["sec"]), "名前はいつも1つだけ（ためない）")
	s.show_enemy_attack("bottle_ride", 9999)
	check(bool(s.enemy_attack["ult"]) and str(s.enemy_attack["text"]) == "巨大酒瓶ライド", "ボスの必殺技は、必殺技の印つき")
	s.update_cues(10.0)
	check(float(s.enemy_attack["left"]) == 0.0, "少したつと、名前は消える")
	s.show_enemy_attack("bat_h", 10000)
	s._on_boss_fall()
	check(float(s.enemy_attack["left"]) == 0.0, "ボスが倒れたら、攻撃の名前も消す")

	# ---- 4. 覚醒：1回だけ ----
	s._on_boss_awake()
	s._on_boss_awake()
	check(count(s.cue_log, "awaken") == 1 and float(s.awaken_fx["left"]) > 0.0, "覚醒の演出は1回だけ（2回呼んでも1回）")
	check(str(s.phase_text["text"]) != str(s.config.get("boss_awake_text", "覚醒！")), "前の「覚醒！」の字は出さない（新しい演出だけ）")
	check(str(s.config["awakening_fx"]["title"]) == "AWAKENING" and str(s.config["awakening_fx"]["sub"]) == "覚醒", "AWAKENING と 覚醒")

	# ---- 5. 次の試合：演出は作り直す（前の物は残らない）----
	var log0: int = count(s.cue_log, "intro")
	s.won = true
	s._begin_round(now[0] + 1000.0)
	check(count(s.cue_log, "intro") == log0 + 1 and not s.awaken_fx_shown and float(s.awaken_fx["left"]) == 0.0 and float(s.enemy_attack["left"]) == 0.0,
		"次の試合：登場はまた1回・覚醒と攻撃の名前は消える")
	s._on_boss_awake()
	check(count(s.cue_log, "awaken") == 2, "次の試合の覚醒は、また1回出る")

	# ---- 6. 必殺技の名前：役職の色・画面に入る大きさ ----
	s.actions.reset()
	s.gauge.value = s.gauge.max_value
	s.skill_time_stop_left = 999.0
	check(s.perform("ultimate"), "必殺技を使う")
	var rc := Color(str(CD.find(CD.load_config(), "summoner")["role_color"]))
	check((s.banner["color"] as Color).is_equal_approx(rc), "必殺技の名前は、役職の色（兵隊：%s）" % rc.to_html())
	var hud: Object = s.hud
	for screen in [Vector2(648, 1152), Vector2(1152, 648), Vector2(648, 1402)]:
		s.banner["left"] = float(s.banner["total"])  # はね上がりの一番大きい時
		s.banner["text"] = "とても長い必殺技の名前のテストです"
		var L: Dictionary = hud.banner_layout(screen)
		check(float(L["w"]) <= screen.x * float(s.config["ult_banner"]["max_w_frac"]) + 0.5, "%s：長い名前は、画面に入る大きさにする（幅 %.0f）" % [str(screen), float(L["w"])])
		s.banner["text"] = "兵隊包囲攻撃"
		s.banner["left"] = 0.5
		L = hud.banner_layout(screen)
		check(float(L["fs"]) >= float(s.config["ui_font_size"]) * 2.0 or float(L["w"]) >= screen.x * 0.8, "%s：短い名前は大きいまま（字の高さ %.0f）" % [str(screen), float(L["fs"])])
	# なかま（AI）の必殺技：そのなかまの役職の色
	var ally_col := Color(str(CD.find(CD.load_config(), "healer")["role_color"]))
	s._show_banner("エンジェルレイ", "介護士", 1.6, ally_col)
	check((s.banner["color"] as Color).is_equal_approx(ally_col), "なかまの必殺技は、なかまの役職の色")

	# ---- 7. 敵の攻撃の名前の場所：右上・体力の表示と重ならない ----
	s.show_enemy_attack("walk_swing", 20000)
	for screen in [Vector2(648, 1152), Vector2(1152, 648), Vector2(648, 1402), Vector2(864, 1152)]:
		var r: Rect2 = hud.enemy_attack_rect(screen)
		var L2: Dictionary = s.hp_hud.layout(screen)
		var ok: bool = Rect2(Vector2.ZERO, screen).encloses(r) and r.get_center().x > screen.x * 0.5 and r.get_center().y < screen.y * 0.25
		check(ok, "%s：攻撃の名前は右上（%s）" % [str(screen), str(r)])
		check(not r.intersects(L2["boss_rect"]) and not r.intersects(L2["party_rect"]), "%s：ボス・なかまの体力の表示と重ならない" % str(screen))

	root.remove_child(s)
	s.free()
	Engine.time_scale = 1.0
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

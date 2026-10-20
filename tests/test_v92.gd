extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v92.gd
## 版92：戦いの画面の、上の文字の行をやめて、体力の表示を新しくした。
## 確かめること：
##   1. 上の文字の行（説明・BOSS HP・やく/体力・なかま・通信）は描かない
##   2. 自分：丸いアイコン＋体力の数字。数字は本当の体力（切り上げ）。30 未満で赤・30 ちょうどはふつうの色・29 で赤
##   3. 自分：ダメージ・回復で、すぐ数字が変わる。倒れたら「ダウン」
##   4. ボス：アイコン＋メーター＋数字（いま / 最大）。本当の体力と同じ割合。減った分はおくれて縮む帯。覚醒（第2形態）はむらさき・ラベルも変わる。満タンにもどる時は帯もすぐ合わせる
##   5. 場所：画面の中・ボスと自分が重ならない・スティックとボタンに重ならない（たて・横の4つの画面の形）
##   6. 画面に固定：カメラが動いても、場所と大きさは同じ
##   7. 読みやすさ：字はふちどり・下じきは濃い（夕方・夜のどちらでも）。版の数字は右下に小さく
##   8. 顔の絵：画面の流れが、自分のキャラの顔の絵を戦いに渡す（作れない所では、役の色の丸と人の形）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func circle_hits_rect(c: Vector2, r: float, rect: Rect2) -> bool:
	var q := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return q.distance_to(c) < r


func _initialize() -> void:
	# ---- 1. 上の文字の行 ----
	var src := FileAccess.get_file_as_string("res://scripts/prototype/battle_hud.gd")
	var a := src.find("func _draw_overlay")
	var body := src.substr(a, src.find("\nfunc ", a + 10) - a)
	check(not body.contains("build_team_text()") and not body.contains("build_room_text(") and not body.contains("hint_portrait") and not body.contains("player_hp_label") and not body.contains("boss_hp_label"), "上の文字の行（説明・BOSS HP・やく/体力・なかま・通信）は描かない")
	check(body.contains("b.hp_hud.draw(screen)"), "かわりに、新しい体力の表示を描く")

	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.set_process(false)
	var hh = s.hp_hud
	var hc: Dictionary = s.config["hud"]
	var max_hp: float = s.role_value("hp")

	# ---- 2. 自分の数字と色 ----
	s.my_hp = 30.0
	var v: Dictionary = hh.player_view()
	check(int(v["hp"]) == 30 and not bool(v["low"]) and (v["color"] as Color).is_equal_approx(Color(str(hc["hp_color"]))), "体力 30：ふつうの色")
	s.my_hp = 29.0
	v = hh.player_view()
	check(int(v["hp"]) == 29 and bool(v["low"]) and (v["color"] as Color).is_equal_approx(Color(str(hc["hp_low_color"]))), "体力 29：赤")
	s.my_hp = 29.4
	v = hh.player_view()
	check(int(v["hp"]) == 30 and not bool(v["low"]), "体力 29.4 は、数字が 30（切り上げ）なので、ふつうの色（数字と色がずれない）")
	s.my_hp = 1.0
	check(bool(hh.player_view()["low"]), "体力 1：赤")
	check(int(hh.player_view()["max"]) == ceili(max_hp), "最大の体力（/ %d）も出す" % ceili(max_hp))

	# ---- 3. ダメージ・回復ですぐ変わる ----
	s.my_hp = max_hp
	s.downed = false
	s._take_damage(40.0) if s.has_method("_take_damage") else s._set_my_hp(s.my_hp - 40.0)
	check(int(hh.player_view()["hp"]) == ceili(s.my_hp) and s.my_hp < max_hp, "ダメージで、すぐ数字が減る（%d）" % int(hh.player_view()["hp"]))
	s._set_my_hp(minf(max_hp, s.my_hp + 25.0))
	check(int(hh.player_view()["hp"]) == ceili(s.my_hp), "回復で、すぐ数字が増える（%d）" % int(hh.player_view()["hp"]))
	s._set_my_hp(0.0)
	v = hh.player_view()
	check(bool(v["down"]) and int(v["hp"]) == 0 and bool(v["low"]), "倒れたら 0・赤・ダウン")
	s.downed = false
	s.my_hp = max_hp

	# ---- 4. ボス ----
	hh.reset()
	hh.step(0.016)
	var bv: Dictionary = hh.boss_view()
	check(absf(float(bv["frac"]) - s.boss_hp / s.phase.max_hp()) < 0.0001 and int(bv["hp"]) == ceili(s.boss_hp) and int(bv["max"]) == int(s.phase.max_hp()), "ボスのメーターと数字は、本当の体力（%d / %d）" % [int(bv["hp"]), int(bv["max"])])
	check(str(bv["label"]) == str(hc["boss"]["label"]) and (bv["color"] as Color).is_equal_approx(Color(str(hc["boss"]["bar_color"]))), "第1形態：BOSS・赤")
	var before: float = float(bv["frac"])
	s.boss_hp = s.boss_hp - s.phase.max_hp() * 0.2
	hh.step(0.016)
	bv = hh.boss_view()
	check(float(bv["frac"]) < before - 0.19, "ダメージで、メーターがすぐ短くなる（%.2f → %.2f）" % [before, float(bv["frac"])])
	check(float(bv["trail"]) > float(bv["frac"]) + 0.15, "減った分は、黄色の帯で少し残る")
	for i in 120:
		hh.step(1.0 / 60.0)
	check(absf(float(hh.boss_view()["trail"]) - float(hh.boss_view()["frac"])) < 0.001, "2秒で、帯もいまの体力まで縮む")
	s.phase.phase = BossPhase.AWAKE
	s.boss_hp = s.phase.max_hp()
	hh.step(0.016)
	bv = hh.boss_view()
	check(str(bv["label"]) == str(hc["boss"]["label_awake"]) and (bv["color"] as Color).is_equal_approx(Color(str(hc["boss"]["bar_color_awake"]))), "覚醒（第2形態）：%s・むらさき" % str(bv["label"]))
	check(is_equal_approx(float(bv["trail"]), float(bv["frac"])), "満タンにもどる時は、帯もすぐ合わせる")
	s.phase.phase = BossPhase.NORMAL

	# ---- 5. 場所 ----
	var screens := {"iPhone たて": Vector2(390, 844), "たて 9:16": Vector2(648, 1152), "横 16:9": Vector2(1152, 648), "iPhone 横": Vector2(844, 390)}
	var br := float(s.config["button_radius_px"])
	var sr := float(s.config["stick_radius_px"])
	for nm in screens:
		var sz: Vector2 = screens[nm]
		s.apply_orientation(sz)
		var base: Array = s.config["portrait_base_size"] if sz.y > sz.x else s.config["landscape_base_size"]
		var scr := Vector2(float(base[0]), float(base[1]))  # 画面の字・ボタンは、この大きさで描く（content_scale）
		if sz.y > sz.x:
			scr.y = scr.x * sz.y / sz.x
		else:
			scr.x = scr.y * sz.x / sz.y
		var L: Dictionary = hh.layout(scr)
		var boss_r: Rect2 = L["boss_rect"]
		var pl_r: Rect2 = L["player_rect"]
		var full := Rect2(Vector2.ZERO, scr)
		check(full.encloses(boss_r) and full.encloses(pl_r), "%s：体力の表示は画面の中" % nm)
		check(not boss_r.intersects(pl_r), "%s：ボスと自分の表示が重ならない" % nm)
		var hit := false
		hit = hit or circle_hits_rect(s.hud._stick_center(scr), sr, boss_r) or circle_hits_rect(s.hud._stick_center(scr), sr, pl_r)
		for id in s.actions.ids():
			var bc: Vector2 = s.hud._button_center(str(id), scr)
			hit = hit or circle_hits_rect(bc, br + 6.0, boss_r) or circle_hits_rect(bc, br + 6.0, pl_r)
		check(not hit, "%s：スティック・ボタンに重ならない" % nm)
		check(float(L["bottom"]) < scr.y * 0.2, "%s：上のほう（画面の上から %.0f%% まで）に収まり、戦いの場所をかくさない" % [nm, float(L["bottom"]) / scr.y * 100.0])

	# ---- 6. 画面に固定 ----
	var L1: Dictionary = hh.layout(Vector2(648, 1152))
	s.player.position = Vector3(10, s.ground_y, -10)
	for i in 60:
		s.camera_update(1.0 / 60.0)
	s._impact([0.0, 0.3, 0.15])
	for i in 10:
		s.camera_update(1.0 / 60.0)
	var L2: Dictionary = hh.layout(Vector2(648, 1152))
	check((L1["boss_rect"] as Rect2).is_equal_approx(L2["boss_rect"]) and (L1["player_rect"] as Rect2).is_equal_approx(L2["player_rect"]), "カメラが動いても・ゆれても・寄っても、表示の場所と大きさは同じ")

	# ---- 7. 読みやすさ ----
	check(int(hc["outline_px"]) >= 3 and Color(str(hc["outline_color"])).get_luminance() < 0.1, "字は黒いふちどり（%d px）で、夕方・夜のどちらの背景でも読める" % int(hc["outline_px"]))
	check(Color(str(hc["boss"]["back_color"])).a >= 0.7 and Color(str(hc["player"]["panel_color"])).a >= 0.5, "下じきは濃い（背景にうもれない）")
	check(Color(str(hc["hp_low_color"])).r > 0.9 and Color(str(hc["hp_low_color"])).g < 0.4, "赤ははっきりした赤 %s" % str(hc["hp_low_color"]))
	check(body.contains("build_label") and body.contains("version_alpha"), "版の数字は、右下に小さく・うすく（確認用）")

	# ---- 8. 顔の絵 ----
	var gf := FileAccess.get_file_as_string("res://scripts/flow/game_flow.gd")
	check(gf.contains("bt.hud_portrait = tex"), "画面の流れが、自分のキャラの顔の絵を戦いに渡す")
	var hsrc := FileAccess.get_file_as_string("res://scripts/prototype/battle_hp_hud.gd")
	check(hsrc.contains("draw_colored_polygon(pts") and hsrc.contains("role_color()"), "顔の絵は丸く切りぬいて描く。ないときは役の色の丸")
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

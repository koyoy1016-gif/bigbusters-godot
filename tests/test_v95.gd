extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v95.gd
## 版95：体力の表示をバーに（数字なし）。戦う4人のアイコンとバーを、たてに並べる。
## 確かめること：
##   1. 数字は描かない（ボスもキャラも）。ボスはアイコン＋メーター（＋ BOSS の文字）のまま
##   2. 4人：自分（いちばん上・金のふち）と AI の味方3人。本当の体力と同じ割合のバー。キャラのID も正しい
##   3. 体力 30 未満のバーは赤・30 ちょうどは緑（だれでも）。たおれたら空のバー
##   4. ダメージ・回復で、すぐバーの長さが変わる（自分・AI）
##   5. たてに並ぶ：4つの四角は、上から順に、同じ x・同じ幅で重ならない。アイコンはバーの左
##   6. 場所：たて画面はボスの下の左、横画面は左上（ボスと重ならない）。スティック・ボタンと重ならない
##   7. 通信のなかま：部屋の人の体力（共有された値）を使う
##   8. 顔の絵：作る係があれば、4人分を1回ずつ頼む（何度も頼まない）

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


## 顔の絵を作る係のかわり（頼まれた回数を数える）
class FakePortraits extends Node:
	var asked := {}
	func request(id: String, _def: Dictionary, cb: Callable) -> void:
		asked[id] = int(asked.get(id, 0)) + 1
		var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
		cb.call(ImageTexture.create_from_image(img))


func _initialize() -> void:
	# ---- 1. 数字は描かない ----
	var hsrc := FileAccess.get_file_as_string("res://scripts/prototype/battle_hp_hud.gd")
	check(not hsrc.contains("\"%d / %d\"") and not hsrc.contains("str(int(v[\"hp\"]))") and not hsrc.contains("/ %d"), "体力の数字は描かない（ボスもキャラも）")
	check(hsrc.contains("_draw_boss") and hsrc.contains("str(v[\"label\"])"), "ボスはアイコン＋メーター＋「BOSS」の文字")

	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "brawler"
	s.ai_enabled = true
	var fp := FakePortraits.new()
	root.add_child(fp)
	s.portrait_source = fp
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.set_process(false)
	s._ai_update(0.016)
	var hh = s.hp_hud
	var hc: Dictionary = s.config["hud"]
	var green := Color(str(hc["party"]["bar_color"]))
	var red := Color(str(hc["hp_low_color"]))

	# ---- 2. 4人 ----
	var pv: Array = hh.party_views()
	check(pv.size() == 4, "4人のバー（自分＋AI 3人）：%d" % pv.size())
	check(bool(pv[0]["me"]) and str(pv[0]["id"]) == "brawler", "いちばん上は自分（%s）" % str(pv[0]["id"]))
	var ids_ok := true
	for i in range(1, pv.size()):
		var slot := str(pv[i]["slot"])
		ids_ok = ids_ok and s.ai_allies.has(slot) and str(pv[i]["id"]) == str(s.ai_allies[slot]["id"]) and not bool(pv[i]["me"])
	check(ids_ok, "あとの3人は AI の味方（キャラも正しい）")
	check(hsrc.contains("me_ring"), "自分のアイコンは金のふち")

	# ---- 3. 色 ----
	s.my_hp = 30.0
	check((hh.party_views()[0]["color"] as Color).is_equal_approx(green), "自分の体力 30：緑")
	s.my_hp = 29.0
	check((hh.party_views()[0]["color"] as Color).is_equal_approx(red), "自分の体力 29：赤")
	var slot1 := str(pv[1]["slot"])
	var a1: Dictionary = s.ai_allies[slot1]
	a1["hp"] = 30.0
	check((hh.party_views()[1]["color"] as Color).is_equal_approx(green), "なかまの体力 30：緑")
	a1["hp"] = 12.0
	check((hh.party_views()[1]["color"] as Color).is_equal_approx(red), "なかまの体力 12：赤（なかまも同じ決まり）")
	a1["hp"] = 0.0
	a1["downed"] = true
	var d1: Dictionary = hh.party_views()[1]
	check(bool(d1["down"]) and is_zero_approx(float(d1["ratio"])), "たおれたなかまは、空のバー・暗いアイコン")
	a1["downed"] = false

	# ---- 4. すぐ変わる ----
	var mx: float = s.role_value("hp")
	s.my_hp = mx
	var r0: float = float(hh.party_views()[0]["ratio"])
	s._set_my_hp(mx * 0.5)
	var r1: float = float(hh.party_views()[0]["ratio"])
	check(is_equal_approx(r0, 1.0) and absf(r1 - 0.5) < 0.01, "自分のダメージで、すぐバーが半分（%.2f → %.2f）" % [r0, r1])
	a1["hp"] = float(a1["max_hp"]) * 0.25
	check(absf(float(hh.party_views()[1]["ratio"]) - 0.25) < 0.02, "なかまの体力が減ると、すぐバーが短くなる")
	a1["hp"] = float(a1["max_hp"])
	check(is_equal_approx(float(hh.party_views()[1]["ratio"]), 1.0), "回復すると、すぐ満タン")

	# ---- 5・6. たてに並ぶ・場所 ----
	var screens := {"iPhone たて": Vector2(390, 844), "たて 9:16": Vector2(648, 1152), "横 16:9": Vector2(1152, 648), "iPhone 横": Vector2(844, 390)}
	var br := float(s.config["button_radius_px"])
	var sr := float(s.config["stick_radius_px"])
	for nm in screens:
		var sz: Vector2 = screens[nm]
		s.apply_orientation(sz)
		var base: Array = s.config["portrait_base_size"] if sz.y > sz.x else s.config["landscape_base_size"]
		var scr := Vector2(float(base[0]), float(base[1]))
		if sz.y > sz.x:
			scr.y = scr.x * sz.y / sz.x
		else:
			scr.x = scr.y * sz.x / sz.y
		var L: Dictionary = hh.layout(scr)
		var cells: Array = L["cells"]
		var col_ok := cells.size() == 4
		for i in range(1, cells.size()):
			var c0: Rect2 = cells[i - 1]["cell"]
			var c1: Rect2 = cells[i]["cell"]
			col_ok = col_ok and c1.position.y >= c0.end.y - 0.01 and is_equal_approx(c1.position.x, c0.position.x) and is_equal_approx(c1.size.x, c0.size.x)
		for c in cells:
			col_ok = col_ok and (c["icon"] as Vector2).x < (c["bar"] as Rect2).position.x and (c["bar"] as Rect2).size.x > 40.0
		check(col_ok, "%s：4人は上から順に、たてに並ぶ（アイコンの右にバー）" % nm)
		var party: Rect2 = L["party_rect"]
		var boss: Rect2 = L["boss_rect"]
		var place_ok: bool = not party.intersects(boss) and Rect2(Vector2.ZERO, scr).encloses(party) and party.end.x < scr.x * 0.5
		if sz.y > sz.x:
			place_ok = place_ok and party.position.y >= boss.end.y
		else:
			place_ok = place_ok and party.end.x <= boss.position.x
		check(place_ok, "%s：%s" % [nm, "ボスの下の左" if sz.y > sz.x else "左上（ボスの左）"])
		var hit := circle_hits_rect(s.hud._stick_center(scr), sr, party)
		for id in s.actions.ids():
			hit = hit or circle_hits_rect(s.hud._button_center(str(id), scr), br + 6.0, party)
		check(not hit, "%s：スティック・ボタンに重ならない" % nm)

	# ---- 7. 通信のなかま ----
	s.ai_allies = {}
	s.net_active = true
	s.net_state = {"slot": "p1", "members": ["p1", "p2", "p3"], "hp": {"p2": {"hp": 20.0, "round": s.round_start_ms}, "p3": {"hp": 150.0, "round": s.round_start_ms}}, "chars": {"p2": "gunner", "p3": "mage"}}
	pv = hh.party_views()
	check(pv.size() == 3 and str(pv[1]["slot"]) == "p2" and str(pv[1]["id"]) == "gunner" and int(pv[1]["hp"]) == 20 and bool(pv[1]["low"]), "通信のなかま：部屋の体力（p2 は 20 で赤）とキャラを使う")
	check(str(pv[2]["id"]) == "mage" and not bool(pv[2]["low"]), "p3 は 150 で緑")
	s.net_active = false
	s.net_state = {}

	# ---- 8. 顔の絵 ----
	s._ai_reset()
	for i in 3:
		for v in hh.party_views():
			hh.portrait_of(str(v["id"]))
	var once := true
	for id in fp.asked:
		once = once and int(fp.asked[id]) == 1
	check(fp.asked.size() >= 4 and once, "顔の絵は、4人分を1回ずつ頼む（%s）" % str(fp.asked))
	check(s.hud_portraits.has("brawler"), "できた顔の絵は覚えておく")
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

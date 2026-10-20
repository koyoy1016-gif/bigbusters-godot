extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v102.gd
## 版102（軽量化①：戦いの毎コマのスクリプト処理）。見た目・動きは変えずに、毎コマのむだな仕事を減らした。
## 確かめること：
##   1. 体力の表示は overlay の子の板（overlay の絵より下＝前と同じ重なり）。見た目が変わらないコマは描き直さない。
##      体力が変わる・ボスの帯が縮む間・当たって光る間は描き直す。帯が縮み終わったら止まる
##   2. CharacterData.has_model・find は、覚えた答えでも、前の調べ方と同じ答え（全キャラ・ない id）。characters の配列が変われば作り直す
##   3. role() は、同じキャラの間は同じ物を返す（中身は作り直した物と同じ）。キャラを変えると、そのキャラの性能になる
##   4. 画面の字の色（設定の "#rrggbb"）を覚えても、同じ色

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const CharacterData := preload("res://scripts/characters/character_data.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = false
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
	# ---- 1. 体力の表示の板 ----
	check(hh.layer != null and hh.layer.get_parent() == s.overlay and hh.layer.show_behind_parent and hh.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "体力の表示は overlay の子の板（overlay の絵より下・さわれない）")
	hh.layer.size = Vector2(648, 1152)
	for i in 3:
		hh.update(1.0 / 60.0)
		await process_frame
	var r0: int = hh.redraws
	for i in 20:
		hh.update(1.0 / 60.0)
		await process_frame
	check(hh.redraws == r0, "何も変わらない 20 コマは、描き直さない（%d 回）" % (hh.redraws - r0))
	s.my_hp = float(s.my_hp) - 7.0
	hh.update(1.0 / 60.0)
	await process_frame
	check(hh.redraws == r0 + 1, "自分の体力が変わったコマは、描き直す")
	s.player_hit_flash = 0.2
	hh.update(1.0 / 60.0)
	await process_frame
	s.player_hit_flash = 0.0
	hh.update(1.0 / 60.0)
	await process_frame
	check(hh.redraws == r0 + 3, "当たって光る・光り終わる時も、描き直す")
	# ボスに大きなダメージ → 帯が縮む間は描き直し、終わったら止まる
	var r1: int = hh.redraws
	s.boss_hp = float(s.boss_hp) * 0.6
	var during := 0
	for i in 150:
		hh.update(1.0 / 60.0)
		await process_frame
	during = hh.redraws - r1
	var r2: int = hh.redraws
	for i in 20:
		hh.update(1.0 / 60.0)
		await process_frame
	check(during >= 10 and hh.redraws == r2, "ボスが減った：帯が縮む間は描き直し（%d 回）、縮み終わったら止まる" % during)
	check(absf(float(hh.boss_view()["trail"]) - float(hh.boss_view()["frac"])) < 0.001, "帯は、いまの体力まで縮んだ（前と同じ動き）")
	var L1: Dictionary = hh.layout(Vector2(648, 1152))
	check(L1 == hh.layout(Vector2(648, 1152)) and hh.layout(Vector2(1152, 648))["portrait"] == false and hh.layout(Vector2(648, 1152))["portrait"] == true, "場所の計算は、画面の大きさが変われば作り直す")

	# ---- 2. has_model・find ----
	var cfg := CharacterData.load_config()
	var same := true
	for c in cfg["characters"]:
		var id := str(c["id"])
		var lin := {}
		for c2 in cfg["characters"]:
			if str(c2["id"]) == id:
				lin = c2
				break
		same = same and CharacterData.find(cfg, id) == lin
		same = same and CharacterData.has_model(c) == (str(c.get("model", "")) != "" and ResourceLoader.exists(str(c.get("model", ""))))
		same = same and CharacterData.has_model(c) == CharacterData.has_model(c)
	check(same and CharacterData.find(cfg, "no_such_id").is_empty() and not CharacterData.has_model({}), "has_model・find は、前の調べ方と同じ答え（%d 人・ない id は空）" % (cfg["characters"] as Array).size())
	var cfg2 := {"characters": [{"id": "x1", "name": "a"}, {"id": "x1", "name": "b"}]}
	check(str(CharacterData.find(cfg2, "x1").get("name", "")) == "a", "別の characters の配列では作り直す（同じ id なら先の物）")
	(cfg2["characters"] as Array).append({"id": "x2", "name": "c"})
	check(str(CharacterData.find(cfg2, "x2").get("name", "")) == "c", "配列に足したら、作り直す")

	# ---- 3. role ----
	var r_a: Dictionary = s.role()
	check(r_a == s._make_role() and is_same(r_a, s.role()), "role()：同じキャラの間は同じ物（中身は作り直した物と同じ）")
	s.selected_character = "brawler"
	var r_b: Dictionary = s.role()
	check(r_b == s._make_role() and str(r_b.get("character_name", "")) != str(r_a.get("character_name", "")), "キャラを変えると、そのキャラの性能")
	s.selected_character = "hero_swordsman"

	# ---- 4. 色 ----
	var ok := true
	for key in ["text_color", "button_text_color", "stick_base_color", "button_color", "banner_color", "ultimate_ring_color"]:
		ok = ok and s.hud._cc(key) == Color(str(s.config[key])) and s.hud._cc(key) == Color(str(s.config[key]))
	check(ok, "画面の字の色は、覚えても同じ色")
	s.queue_free()
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

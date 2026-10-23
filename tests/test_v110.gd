extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v110.gd
## 版110：A・X・Y・必殺のボタン（右下に2×2・同じ大きさ・大きな字と技の名前）。Y の出始めは回避（版114：Y は前の技＋出始めの回避）。
## （回避の動きの細かい確かめは test_player_actions、AI の回避は test_v71）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const HUD := preload("res://scripts/prototype/battle_hud.gd")
const IDS := ["hero_swordsman", "brawler", "sprinter", "gunner", "bomber", "mage", "guardian", "summoner", "healer"]
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make(char_id: String) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = char_id
	s.ai_enabled = false
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [4000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.skill_time_stop_left = 999.0  # ボスを止める（攻撃されないように）
	return s


## 自分の足もとに当たる、円の攻撃
func hazard(id: String, s: Node) -> Dictionary:
	return {"id": id, "shape": "circle", "x": s.player.position.x, "z": s.player.position.z, "r": 2.0, "active": true, "tele": 1.0,
		"power": 20.0, "jumpable": false, "target": "", "tick": -1, "style": "bottle", "kb": "none", "kb_mode": "radial"}


func _initialize() -> void:
	# ---- 1. 版114：Y は、9人とも「前の Y の技＋出始めの回避」（同じ時間）。くわしくは test_v114 ----
	var first: Dictionary = {}
	for cid in IDS:
		var sub: Dictionary = (Actions.config_for(cid)["actions"] as Dictionary).get("sub", {})
		var ok := bool(sub.get("dodge", false)) and sub.get("i_window", null) is Array and float(sub.get("cooldown_sec", 0.0)) > 0.0 and str(sub.get("name", "")) != ""
		check(ok, "%s：Y の出始めは回避（%s）" % [cid, sub.get("name", "")])
		if first.is_empty():
			first = sub
		else:
			check(JSON.stringify(sub["i_window"]) == JSON.stringify(first["i_window"]), "%s：よけられる時間は、みんな同じ" % cid)
		var acts: Dictionary = Actions.config_for(cid)["actions"]
		for id in ["normal", "sub", "main", "ultimate"]:
			check(str((acts.get(id, {}) as Dictionary).get("name", "")) != "", "%s：%s に技の名前がある（ボタンに出す）" % [cid, id])
	var w: Array = first["i_window"]
	check(float(w[1]) - float(w[0]) < float(first["duration_sec"]) and float(w[1]) - float(w[0]) < float(first["cooldown_sec"]),
		"よけられる時間（%.2f秒）は、技の長さ・待ち時間より短い（ずっと無敵にならない）" % (float(w[1]) - float(w[0])))

	# ---- 3. 戦いの画面：よけられる時間の中に当たれば「回避成功」（受けない）。外なら受ける ----
	var s := make("mage")  # 版114：Y の技が、出始めのあとは無敵ではないキャラ（魔法師のチャージ魔法）
	var hp0: float = s.my_hp
	s.player.position = Vector3(0.0, s.ground_y, 6.0)
	check(s.perform("sub"), "Y で回避を始められる")
	s.actions.update(float(w[0]) + 0.05)
	check(s.actions.dodging(), "回避の、よけられる時間の中")
	s.hazard_done = {}
	s._apply_hazards([hazard("d1", s)])
	check(is_equal_approx(s.my_hp, hp0) and s.dodge_count == 1 and s.dodge_text_left > 0.0, "よけられる時間の中に当たった攻撃は、受けない（回避成功・「回避！」）")
	s._apply_hazards([hazard("d1", s)])
	check(s.dodge_count == 1, "同じ攻撃で、回避成功は1回だけ")
	while s.actions.busy() and s.actions.t <= float(w[1]) + 0.02:
		s.actions.update(0.02)
	check(s.actions.busy() and not s.actions.invulnerable(), "転がり終わりぎわは、もう無敵ではない")
	s._apply_hazards([hazard("d2", s)])
	check(s.my_hp < hp0 and s.dodge_count == 1, "よけられる時間の外で当たれば、ふつうに受ける")
	var hp1: float = s.my_hp
	s.actions.reset()
	s.hazard_done = {}
	s._apply_hazards([hazard("d3", s)])
	check(s.my_hp < hp1 and s.dodge_count == 1, "回避していない時は、ふつうに受ける")
	check(not s.perform("sub") or s.actions.cooldown_left("sub") > 0.0, "回避のあとは待ち時間")
	s.actions.reset()
	check(s.perform("sub") and not s.perform("sub"), "回避の最中にもう1度押しても、始め直さない")

	# ---- 4. ボタン：右下に2×2・同じ大きさ・重ならない・画面の中・押せる場所 ----
	var hud: Object = s.hud
	var letters: Dictionary = (s.config["battle_buttons"] as Dictionary)["letters"]
	check(str(letters.get("normal")) == "A" and str(letters.get("main")) == "X" and str(letters.get("sub")) == "Y" and str(letters.get("ultimate")) == "必殺",
		"ボタンの字は A（通常）・X（スキル）・Y（回避）・必殺")
	# 画面の大きさは「基準の大きさ（縦 648×1152・横 1152×648）を広げた物」（project.godot の stretch＝expand）。
	# iPhone 縦（390×844）→ 648×1402、横 → 1402×648。タブレット縦（768×1024）→ 864×1152、横 → 1152×864
	for screen in [Vector2(648, 1152), Vector2(1152, 648), Vector2(648, 1402), Vector2(1402, 648), Vector2(864, 1152), Vector2(1152, 864)]:
		var rects := {}
		for id in s.actions.ids():
			rects[str(id)] = hud._button_rect(str(id), screen)
		var size0: Vector2 = (rects["normal"] as Rect2).size
		var same := true
		var inside := true
		var lower := true
		for id in rects:
			var r: Rect2 = rects[id]
			same = same and r.size.is_equal_approx(size0)
			inside = inside and Rect2(Vector2.ZERO, screen).encloses(r)
			lower = lower and r.get_center().y > screen.y * 0.5 and r.get_center().x > screen.x * 0.5
		check(rects.size() == 4 and same, "%s：ボタンは4つ・同じ大きさ" % str(screen))
		check(inside and lower, "%s：ボタンは画面の中・右下" % str(screen))
		var overlap := false
		var keys := rects.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				overlap = overlap or (rects[keys[i]] as Rect2).intersects(rects[keys[j]])
		check(not overlap, "%s：ボタンは重ならない" % str(screen))
		var hit_ok := true
		for id in rects:
			hit_ok = hit_ok and hud._button_at((rects[id] as Rect2).get_center(), screen) == id
		check(hit_ok, "%s：ボタンの真ん中を触ると、そのボタン" % str(screen))
		check((rects["normal"] as Rect2).get_center().x > (rects["sub"] as Rect2).get_center().x and (rects["normal"] as Rect2).get_center().y > (rects["main"] as Rect2).get_center().y,
			"%s：A は右下（親指の休む所）" % str(screen))
	check(HUD.is_portrait(Vector2(648, 1152)) and not HUD.is_portrait(Vector2(1152, 648)), "縦長・横長で、ボタンの置き方を変える")

	# ---- 5. 味方の体力のバーの上に、役職名 ----
	var lab: Array = s.hp_hud._label_of("summoner")
	check(str(lab[0]) == "兵隊" and (lab[1] as Color) == Color(str(CD.find(CD.load_config(), "summoner")["role_color"])), "体力のバーの上の名前は、役職名と役職の色")

	root.remove_child(s)
	s.free()
	Engine.time_scale = 1.0
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

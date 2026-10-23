extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v114.gd
## 版114：Y＝キャラの前の Y の技＋出始めの回避（ユーザー決定）。X は前の技にもどす（瞬：超高速モード・魔法師：時間停止）。
## （回避の動きの細かい確かめは test_player_actions、AI は test_v71）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const Y_NAMES := {"hero_swordsman": "かわし斬り", "brawler": "ダッシュキック", "sprinter": "バニッシュ", "gunner": "バックステップ射撃",
	"bomber": "置きプレゼント＆バックジャンプ", "mage": "チャージ魔法", "guardian": "シールドチャージ", "summoner": "ぬいぐるみの突撃", "healer": "いやしの光"}
const X_NAMES := {"hero_swordsman": "五段斬り", "brawler": "10連パンチ", "sprinter": "超高速モード", "gunner": "ダブル連射", "bomber": "びっくりプレゼント",
	"mage": "時間停止", "guardian": "シールドドーム", "summoner": "小隊召集", "healer": "いやしのドーム"}
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
	var now := [4500000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.skill_time_stop_left = 999.0  # ボスを止める（攻撃されないように）
	return s


func hazard(id: String, s: Node) -> Dictionary:
	return {"id": id, "shape": "circle", "x": s.player.position.x, "z": s.player.position.z, "r": 2.5, "active": true, "tele": 1.0,
		"power": 20.0, "jumpable": false, "target": "", "tick": -1, "style": "bottle", "kb": "none", "kb_mode": "radial"}


func _initialize() -> void:
	# ---- 1. Y は前の技・出始めは回避（9人とも同じ時間）。X は前の技 ----
	var w0: Array = []
	for cid in Y_NAMES:
		var acts: Dictionary = Actions.config_for(cid)["actions"]
		var y: Dictionary = acts["sub"]
		var skill := not (y.get("hits", []) as Array).is_empty() or not (y.get("effects", []) as Array).is_empty()
		check(str(y["name"]) == str(Y_NAMES[cid]) and skill, "%s：Y は前の技（%s）" % [cid, y["name"]])
		check(bool(y.get("dodge", false)) and y.get("i_window", null) is Array, "%s：Y の出始めは回避" % cid)
		if w0.is_empty():
			w0 = y["i_window"]
		check(JSON.stringify(y["i_window"]) == JSON.stringify(w0), "%s：回避の時間は、みんな同じ" % cid)
		check(str(acts["main"]["name"]) == str(X_NAMES[cid]), "%s：X は前の技（%s）" % [cid, acts["main"]["name"]])
	check(is_equal_approx(float(w0[0]), 0.0) and is_equal_approx(float(w0[1]), 0.3), "回避は、技の出始めの0.3秒")
	var sx: Dictionary = Actions.config_for("sprinter")["actions"]["sub"]
	check(is_equal_approx(float(sx["effects"][0]["sec"]), 2.5), "瞬のバニッシュ（Y）は2.5秒のまま（版111）")

	# ---- 2. 戦い：Y を使うと、敵へ技を出す。出始めに当たった攻撃はよける・あとは受ける ----
	var s := make("hero_swordsman")
	var bp: Vector3 = s.boss.position
	var br := float(s.config["boss_size"]) * 0.5
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + 2.0)
	s.facing = Vector2(1, 0)  # 横を向いていても、技は敵へ
	var hp0: float = s.my_hp
	var hits0: float = s.my_hits
	check(s.perform("sub") and s.actions.aim.dot(Vector2(bp.x - s.player.position.x, bp.z - s.player.position.z).normalized()) > 0.9, "Y：敵の方へ技を出す（にげる向きではない）")
	s.actions.update(0.1)
	check(s.actions.dodging(), "Y の出始めは、回避の時間")
	s.hazard_done = {}
	s._apply_hazards([hazard("y1", s)])
	check(is_equal_approx(s.my_hp, hp0) and s.dodge_count == 1 and s.dodge_text_left > 0.0, "出始めに当たった攻撃は受けない（回避成功・「回避！」）")
	for i in 60:
		s._actions_update(0.02)
		s.combat_update(0.02)
	check(s.my_hits > hits0, "Y の技は、敵に当たる（%.1f）" % (s.my_hits - hits0))
	var hp1: float = s.my_hp
	s.actions.reset()
	s.hazard_done = {}
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + 4.0)
	s.perform("sub")
	s.actions.update(0.45)
	s.player.position.y = s.ground_y
	check(not s.actions.dodging(), "出始めをすぎると、回避の時間ではない")
	s._apply_hazards([hazard("y2", s)])
	check(s.my_hp < hp1 and s.dodge_count == 1, "回避の時間のあとに当たれば、ふつうに受ける")
	check(not s.perform("sub") or s.actions.cooldown_left("sub") > 0.0, "Y のあとは待ち時間（続けて押しても、ずっと無敵にはならない）")
	root.remove_child(s)
	s.free()

	# ---- 3. 押し続けても、ずっと無敵にはならない ----
	for cid in ["brawler", "gunner", "summoner"]:
		var a := Actions.new(Actions.config_for(cid))
		var inv := 0.0
		var t := 0.0
		while t < 8.0:
			a.start("sub", Vector2(0, -1))
			a.update(0.02)
			if a.invulnerable():
				inv += 0.02
			t += 0.02
		check(inv < 8.0 * 0.3, "%s：Y を8秒押し続けても、無敵は %.1f 秒だけ" % [cid, inv])

	# ---- 4. AI：出始めの回避でよけられる攻撃は、Y でよける。Y は攻めにも使う ----
	var ai := {"stats": CD.find(CD.load_config(), "gunner")["stats"], "actions": Actions.new(Actions.config_for("gunner"))}
	var acts2: Actions = AiAlly.act(ai)
	check(AiAlly.dodge_covers(acts2, [{"dt": 0.15, "h": {"jumpable": false}}]), "AI：出始めの0.3秒に当たる攻撃は、Y でよけられる（ジャンプでよけられない攻撃も）")
	check(not AiAlly.dodge_covers(acts2, [{"dt": 0.6, "h": {"jumpable": false}}]), "AI：出始めのあとに当たる攻撃は、Y ではよけられない")

	# ---- 5. ボタン・編成の表示 ----
	var g := make("gunner")
	var bc: Dictionary = g.config["battle_buttons"]
	check(str(bc["letters"]["sub"]) == "Y" and str(bc.get("sub_tag", "")) == "回避", "Y のボタン：大きく Y・上に小さく「回避」・下に技の名前")
	check(str(g.actions.def("sub")["name"]) == "バックステップ射撃", "Y のボタンの技の名前は、そのキャラの Y の技")
	root.remove_child(g)
	g.free()
	var gf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_flow.json"))
	check(str(gf["formation_move_sub"]) == "Y（回避＋技）", "編成の画面：Y（回避＋技）")
	Engine.time_scale = 1.0
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v111.gd
## 版111：キャラの技。兵隊（A ぬいぐるみ1体・続けて押した2回目は2体／X 小隊召集4人×2回／必殺 兵隊包囲攻撃8人×2回／
## 攻撃の時に少し下がる／呼び出しの攻撃回数と退場）・拳士 10連パンチ・瞬の透明 2.5秒。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const CD := preload("res://scripts/characters/character_data.gd")
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
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.skill_time_stop_left = 999.0  # ボスを止める（攻撃されないように）
	return s


func ap(id: String) -> float:
	return float(CD.find(CD.load_config(), id)["stats"]["attack_power"])


## ボスの前 gap m に立って、ボスの方を向く
func stand(s: Node, gap: float) -> void:
	var bp: Vector3 = s.boss.position
	var br := float(s.config["boss_size"]) * 0.5
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + gap)
	s.facing = Vector2(0, -1)


func tick(s: Node, sec: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 0.0001:
		s._actions_update(dt)
		s.combat_update(dt)
		t += dt
	Engine.time_scale = 1.0


func boss_dist(s: Node) -> float:
	return Vector2(s.player.position.x - s.boss.position.x, s.player.position.z - s.boss.position.z).length()


## 呼び出した物が、撃ち終わるか、全部いなくなるまで進める。[撃った時刻の一覧（秒）, 進めた秒]
func run_summons(s: Node, max_sec: float) -> Array:
	var shots: Array = []
	var left := {}
	var t := 0.0
	while t < max_sec:
		for u in s.skill_summons:
			var al := int(u.get("attacks_left", -1))
			if left.has(u["slot_i"] * 1000 + int(u["n"])) and int(left[u["slot_i"] * 1000 + int(u["n"])]) > al:
				shots.append(t)
			left[u["slot_i"] * 1000 + int(u["n"])] = al
		tick(s, 0.05)
		t += 0.05
		if s.skill_summons.is_empty() and t > 0.5:
			break
	return [shots, t]


func _initialize() -> void:
	# ---- 1. 兵隊の技の設定 ----
	var acts: Dictionary = Actions.config_for("summoner")["actions"]
	var a: Dictionary = acts["normal"]
	var a2: Dictionary = acts.get("normal2", {})
	check(str(a["name"]) == "ぬいぐるみ投げ" and (a["hits"] as Array).size() == 1, "A：ぬいぐるみ投げ（1体・1回当たる）")
	check(str((a.get("combo", {}) as Dictionary).get("next", "")) == "normal2", "A を続けて押すと、2回目は normal2")
	check(str(a2.get("name", "")) == "ぬいぐるみ2体投げ" and (a2["hits"] as Array).size() == 2, "2回目：ぬいぐるみ2体投げ（2回当たる）")
	var same := true
	for h in a2.get("hits", []):
		same = same and is_equal_approx(float(h["multiplier"]), float(a["hits"][0]["multiplier"])) and (h as Dictionary).has("proj")
	check(same, "2体のぬいぐるみは、それぞれ A と同じ強さの、飛ぶ物")
	check(not (Actions.config_for("summoner")["order"] as Array).has("normal2"), "2体投げのボタンはない（A を続けて押す）")
	var x: Dictionary = acts["main"]
	var xe: Dictionary = x["effects"][0]
	check(str(x["name"]) == "小隊召集" and str(xe["type"]) == "summon" and int(xe["count"]) == 4 and int(xe["attacks"]) == 2, "X：小隊召集（兵隊4人・1人2回撃つ）")
	var u: Dictionary = acts["ultimate"]
	var ue: Dictionary = (u["effects"] as Array).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "summon")[0]
	check(str(u["name"]) == "兵隊包囲攻撃" and int(ue["count"]) == 8 and int(ue["attacks"]) == 2 and str(ue["formation"]) == "surround",
		"必殺：兵隊包囲攻撃（兵隊8人で敵を囲む・1人2回撃つ）")
	check((u["effects"] as Array).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "summon").size() == 1, "必殺で呼ぶのは兵隊だけ（ぬいぐるみの大行進はやめた）")
	for id in ["normal", "normal2", "main", "ultimate"]:
		var path: Array = acts[id]["path"]
		check(not path.is_empty() and float(path[path.size() - 1]["fwd"]) < 0.0, "兵隊 %s：攻撃の時に少し下がる（%.2f m）" % [id, float(path[path.size() - 1]["fwd"]) if not path.is_empty() else 0.0])

	# ---- 2. 続けて押す（player_actions）----
	var pa := Actions.new(Actions.config_for("summoner"))
	check(pa.start("normal", Vector2(0, -1)) and pa.active == "normal", "1回目は1体投げ")
	check(not pa.start("normal", Vector2(0, -1)), "投げている間に押しても、始まらない")
	while pa.busy():
		pa.update(0.02)
	check(pa.combo_next("normal") == "normal2", "投げ終わってすぐは、次の A が2体投げ（ボタンの名前も変わる）")
	check(pa.start("normal", Vector2(0, -1), 0.4) and pa.active == "normal2", "続けて押した2回目は、2体投げ")
	check(pa.cooldown_left("normal") > 0.0, "2体投げの間は、A のボタンも待ち時間")
	while pa.busy():
		pa.update(0.02)
	check(pa.combo_next("normal") == "" and pa.start("normal", Vector2(0, -1)) and pa.active == "normal", "3回目は、また1体投げ（2体投げは続かない）")
	while pa.busy():
		pa.update(0.02)
	pa.update(float(a["combo"]["window_sec"]) + 0.05)
	check(pa.combo_next("normal") == "" and pa.start("normal", Vector2(0, -1)) and pa.active == "normal", "少し待ってから押すと、1体投げ")
	pa.cancel()
	check(pa.combo_next("normal") == "", "やめた時は、続けて押せる状態も消える")

	# ---- 3. 戦い：A 1体 → 続けて 2体（それぞれ A と同じダメージ）----
	var s := make("summoner")
	stand(s, 5.0)
	var one := float(a["hits"][0]["multiplier"]) * ap("summoner") * float(s.config["attack_multiplier"])
	var d0 := boss_dist(s)
	var h0: float = s.my_hits
	check(s.perform("normal"), "A を押す")
	tick(s, 0.4)
	var d1 := boss_dist(s)
	tick(s, 1.0)
	check(is_equal_approx(s.my_hits - h0, one), "A：ぬいぐるみ1体が当たる（%.2f）" % (s.my_hits - h0))
	check(d1 > d0 + 0.3, "A：投げる時に少し下がる（%.2f m）" % (d1 - d0))
	stand(s, 5.0)
	s.actions.reset()
	check(s.perform("normal"), "もう一度 A")
	tick(s, 0.45)
	h0 = s.my_hits
	var projs0: int = s.skill_projs.size()
	check(s.perform("normal") and s.actions.active == "normal2", "続けて押すと、2体投げ")
	tick(s, 0.5)
	check(s.skill_projs.size() - projs0 >= 2 or s.my_hits - h0 > 0.0, "ぬいぐるみが2体飛ぶ")
	tick(s, 1.5)
	check(is_equal_approx(s.my_hits - h0, one * 3.0), "2体投げ：2体それぞれ A と同じ強さで当たる（前の1体と合わせて %.2f）" % (s.my_hits - h0))

	# ---- 4. X 小隊召集：4人・そろって2回ずつ撃って、消える ----
	s.actions.reset()
	s.skills.reset()
	s.skill_time_stop_left = 999.0  # reset で解けるので、もう一度ボスを止める
	stand(s, 5.0)
	h0 = s.my_hits
	check(s.perform("main"), "X を押す")
	tick(s, 0.6)
	var soldiers: Array = s.skill_summons.filter(func(v: Dictionary) -> bool: return str(v["unit"]) == "soldier")
	check(soldiers.size() == 4, "X：兵隊が4人出る")
	var r := run_summons(s, 9.0)
	var shots: Array = r[0]
	check(shots.size() == 8, "X：4人が2回ずつ撃つ（%d 発）" % shots.size())
	check(s.skill_summons.is_empty() and float(r[1]) < 6.0, "撃ち終わったら、すぐ消える（%.1f 秒。前は10秒いた）" % float(r[1]))
	if shots.size() == 8:
		shots.sort()
		check(float(shots[3]) - float(shots[0]) < 0.25 and float(shots[7]) - float(shots[4]) < 0.25, "4人そろって撃つ（1回めの幅 %.2f 秒・2回めの幅 %.2f 秒）" % [float(shots[3]) - float(shots[0]), float(shots[7]) - float(shots[4])])
	tick(s, 1.0)
	var want_x := 8.0 * float(x["effects"][0]["multiplier"]) * ap("summoner") * float(s.config["attack_multiplier"])
	check(is_equal_approx(s.my_hits - h0, want_x), "X：8発ぶんのダメージ（%.1f ／ %.1f）" % [s.my_hits - h0, want_x])

	# 遠くから呼んでも（行進して着く時刻がちがっても）、全員が着いてから、そろって撃つ
	s.actions.reset()
	stand(s, 11.0)
	s.player.position.x += 3.0
	s.perform("main")
	tick(s, 0.6)
	r = run_summons(s, 9.0)
	shots = r[0]
	shots.sort()
	check(shots.size() == 8 and float(shots[3]) - float(shots[0]) < 0.25, "遠くから呼んでも、4人そろって撃つ（%d 発・1回めの幅 %.2f 秒）" % [shots.size(), float(shots[3]) - float(shots[0]) if shots.size() >= 4 else -1.0])
	tick(s, 1.0)

	# ---- 5. 必殺 兵隊包囲攻撃：8人で敵を囲む・2回ずつ撃って、消える ----
	s.actions.reset()
	stand(s, 5.0)
	s.gauge.value = s.gauge.max_value
	h0 = s.my_hits
	var hits_before: int = s.skill_summons.size()
	check(s.perform("ultimate"), "必殺技を使う")
	check(str((s.banner as Dictionary).get("text", "")) == "兵隊包囲攻撃", "必殺技の名前（兵隊包囲攻撃）を出す")
	tick(s, 1.2)
	var ring: Array = s.skill_summons.filter(func(v: Dictionary) -> bool: return str(v["unit"]) == "soldier")
	check(ring.size() == 8 and hits_before == 0, "必殺：兵隊が8人出る")
	var c := Vector2(s.boss.position.x, s.boss.position.z)
	var br := float(s.config["boss_size"]) * 0.5
	var angs: Array = []
	var dist_ok := true
	for v in ring:
		var p: Vector2 = v["pos"]
		angs.append(atan2(p.y - c.y, p.x - c.x))
		dist_ok = dist_ok and absf(p.distance_to(c) - (br + float(ue["ring"]))) < 0.5
	angs.sort()
	var min_gap := TAU
	for i in angs.size():
		var g := (float(angs[(i + 1) % angs.size()]) - float(angs[i]) + TAU) if i == angs.size() - 1 else float(angs[i + 1]) - float(angs[i])
		min_gap = minf(min_gap, g)
	var dists := ""
	for v in ring:
		dists += "%.2f " % (v["pos"] as Vector2).distance_to(c)
	check(dist_ok, "兵隊は、敵のふちから %.1f m の輪に立つ（中心からの距離 %s）" % [float(ue["ring"]), dists])
	check(min_gap > TAU / 8.0 * 0.8, "兵隊は、敵のまわりに等しく並ぶ（いちばん近い2人の角度 %.0f 度）" % rad_to_deg(min_gap))
	r = run_summons(s, 8.0)
	check((r[0] as Array).size() == 16 and s.skill_summons.is_empty(), "必殺：8人が2回ずつ撃って（%d 発）、消える" % (r[0] as Array).size())
	tick(s, 1.0)
	var want_u := 16.0 * float(ue["multiplier"]) * ap("summoner") * float(s.config["attack_multiplier"])
	check(is_equal_approx(s.my_hits - h0, want_u), "必殺：16発ぶんのダメージ（%.1f ／ %.1f）" % [s.my_hits - h0, want_u])

	# ---- 6. 戦いの場所のふち：囲む兵隊も、下がる本体も、外へ出ない ----
	var half := float(s.config["bounds"])
	s.boss.position.x = half - 1.0
	s.boss.position.z = half - 1.0
	var places: Array = s.skills.summon_places(s._my_slot(), ue, 8)
	var inside := true
	for pl in places:
		var p: Vector2 = pl["pos"]
		inside = inside and absf(p.x) <= half and absf(p.y) <= half
	check(places.size() == 8 and inside, "敵が場所のすみにいても、兵隊は場所の中に出る")
	s.boss.position = Vector3(0, s.boss.position.y, 0)
	s.actions.reset()
	s.player.position = Vector3(0.0, s.ground_y, half - 0.05)
	s.facing = Vector2(0, -1)
	s.perform("normal")
	tick(s, 0.6)
	check(s.player.position.z <= half + 0.001, "ふちで下がっても、場所の外へ出ない（z=%.2f）" % s.player.position.z)
	root.remove_child(s)
	s.free()

	# ---- 7. 拳士 10連パンチ（動きと当たりが同じ時刻）----
	var b_acts: Dictionary = Actions.config_for("brawler")["actions"]
	var bx: Dictionary = b_acts["main"]
	var hits: Array = bx["hits"]
	check(str(bx["name"]) == "10連パンチ" and hits.size() == 10, "拳士 X：10連パンチ（10回当たる）")
	var bdef := CD.find(CD.load_config(), "brawler")
	var anim: Dictionary = (bdef.get("built_anims", {}) as Dictionary).get("Brawler_X", {})
	var adur := 0.0
	for seg in anim.get("segments", []):
		adur += float(seg["dur"])
	check(is_equal_approx(adur, float(bx["duration_sec"])), "動きの長さ（%.2f 秒）と技の長さ（%.2f 秒）が同じ" % [adur, float(bx["duration_sec"])])
	var keys := {}
	for k in anim.get("root_lift", []):
		keys[snappedf(float(k[0]), 0.001)] = true
	var synced := true
	for h in hits:
		synced = synced and keys.has(snappedf(float(h["t"]), 0.001))
	check(synced, "10回の当たりは、どれも拳を出す時刻（動きのキー）と同じ")
	check(float(bx["duration_sec"]) < 2.0, "立ち止まる時間が短くなった（%.2f 秒。前は2.55秒）" % float(bx["duration_sec"]))

	# ---- 8. 瞬の透明 2.5秒（それ以外は変えない）----
	var sx: Dictionary = Actions.config_for("sprinter")["actions"]["sub"]  # 版114：バニッシュは、また Y
	var ve: Dictionary = sx["effects"][0]
	check(str(ve["type"]) == "vanish" and is_equal_approx(float(ve["sec"]), 2.5) and is_equal_approx(float(ve["speed"]), 1.3) and is_equal_approx(float(ve["bonus"]), 1.5),
		"瞬：透明は2.5秒（前は3.0秒）。速さ1.3倍・現れた一撃1.5倍はそのまま")
	var sp := make("sprinter")
	stand(sp, 3.0)
	sp.perform("sub")
	tick(sp, float(ve["t"]) + 2.3)
	check(sp.skills.is_vanished(sp._my_slot()), "2.3秒たっても、まだ消えている")
	tick(sp, 0.4)
	check(not sp.skills.is_vanished(sp._my_slot()), "2.5秒たつと、現れる")
	root.remove_child(sp)
	sp.free()

	Engine.time_scale = 1.0
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

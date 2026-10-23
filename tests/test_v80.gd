extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v80.gd
## 版80：攻撃の見た目（何が飛んでいるか・当たったかが分かる）。
## 確かめること：
##   1. ガンナー：A・Y・X・必殺の全部が「弾」（ビームなし）。X は12発の連射、必殺は大きな砲弾10発。ダメージの合計は版79と同じ
##   2. 飛ぶ物の大きさ：弾・魔法の玉・プレゼント・ぬいぐるみが大きくなり、光の粒（尾）を引く
##   3. 飛んでいる間も大きさ（scale）が保たれる（版79までは、向きを入れると1にもどっていた不具合）
##   4. 当たった所：火花に、白い一瞬の光と衝撃の輪。砲弾は小さな爆発、魔法は魔法の輪
##   5. ボス：つづけて当たっても、1発ごとにのけぞる（短く、すぐ戻る）・1発ごとに光る
##   6. ぬいぐるみ：背が約1.6m（ふつうのキャラの約半分）。落ちたプレゼントの箱も大きい
##   7. ダメージは当たった時（版79のまま）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const SkillFx := preload("res://scripts/fx/skill_fx.gd")
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
	await process_frame  # 画面の木に入ってから（飛ぶ物・ぬいぐるみの形が作られる）
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.set_process(false)
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.skill_time_stop_left = 999.0
	return s


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


func cfg(id: String) -> Dictionary:
	return Actions.config_for(id)["actions"]


func total_mult(hits: Array) -> float:
	var t := 0.0
	for h in hits:
		t += float(h["multiplier"])
	return t


func _initialize() -> void:
	# ---- 1. ガンナー：全部「弾」 ----
	var g := cfg("gunner")
	for id in ["normal", "sub", "main", "ultimate"]:
		var hits: Array = g[id]["hits"]
		var all_proj := not hits.is_empty()
		for h in hits:
			if not (h as Dictionary).has("proj") or str((h as Dictionary).get("shape", "")) == "beam":
				all_proj = false
		check(all_proj, "ガンナー %s：すべての当たりが飛ぶ弾（ビームの当たりはない）" % id)
		var beam_fx := false
		for f in (g[id] as Dictionary).get("fx_events", []):
			if str((f as Dictionary).get("kind", "")) == "beam":
				beam_fx = true
		check(not beam_fx, "ガンナー %s：ビームの見た目を出さない" % id)
	check((g["main"]["hits"] as Array).size() == 12 and is_equal_approx(total_mult(g["main"]["hits"]), 6.0), "ガンナー X：12発の連射（倍率の合計 6.0 は版79と同じ）")
	check((g["ultimate"]["hits"] as Array).size() == 10 and is_equal_approx(total_mult(g["ultimate"]["hits"]), 23.0), "ガンナー 必殺：砲弾10発（倍率の合計 23.0 は版79と同じ）")
	check(str(g["ultimate"]["hits"][0]["proj"]["prop"]) == "cannon_shell", "ガンナー 必殺：大きな砲弾の形")
	var sides := {}
	for h in g["main"]["hits"]:
		sides[str(h["proj"]["from"])] = true
	check(sides.has("muzzle_L") and sides.has("muzzle_R"), "ガンナー X：左右の大砲から、かわるがわる撃つ")
	check(SkillFx.prop_mesh("cannon_shell") != null and SkillFx.prop_mesh("bullet") != null, "弾・砲弾の形がある（data/props.json）")
	var bl: AABB = SkillFx.prop_mesh("bullet").get_aabb()
	check(bl.size.z < 0.7, "弾：尾が短い（ビームに見えない。長さ %.2f m）" % bl.size.z)

	# ---- 2. 飛ぶ物の大きさと尾 ----
	var gp: Dictionary = g["normal"]["hits"][0]["proj"]
	check(float(gp["scale"]) >= 2.0 and gp.has("trail"), "ガンナーの弾：2倍以上の大きさ・光の尾")
	var mp: Dictionary = cfg("mage")["normal"]["hits"][0]["proj"]
	check(float(mp["scale"]) >= 2.0 and mp.has("trail"), "魔法の玉：2倍以上の大きさ・光の尾")
	var bp: Dictionary = cfg("bomber")["normal"]["hits"][0]["proj"]
	check(float(bp["scale"]) >= 2.0 and bp.has("trail"), "プレゼント：2倍以上の大きさ（約0.75m）・光の尾")
	check(float(cfg("bomber")["main"]["hits"][0]["proj"]["scale"]) >= 2.0, "大きなプレゼント（X）も大きい")
	check(str(cfg("mage")["normal"]["hits"][0]["fx"].get("kind", "")) == "magic", "魔法が当たった時：魔法の見た目（magic）")
	var tr := SkillFx.trail(Color.WHITE, 2.0)
	check(tr is CPUParticles3D and not tr.local_coords, "光の尾：粒が世界に残る（飛んだ道が見える）")
	tr.free()

	# ---- 3. 飛んでいる間も大きさが保たれる ----
	var s := await make("gunner")
	stand(s, 7.0)
	s.target_lock.set_target("boss")
	s.perform("normal")
	tick(s, 0.1)
	var big_ok := false
	for p in s.skill_projs:
		var n: Node3D = p.get("node")
		if n != null and is_instance_valid(n):
			big_ok = is_equal_approx(n.scale.x, float((p["spec"] as Dictionary)["scale"]))
			check(n.get_node_or_null("Trail") != null, "飛んでいる弾に、光の尾がついている")
	check(big_ok, "飛んでいる間も、弾の大きさ（scale）が保たれる")
	var hp0: float = s.boss_hp
	check(float(s.my_hits) == 0.0, "撃った瞬間（弾が飛んでいる間）は、まだダメージが入らない")

	# ---- 4. 当たった所の見た目 ----
	s.skill_fx_log.clear()
	tick(s, 0.5)
	check(s.boss_hp < hp0, "弾が当たってダメージが入った")
	check(s.skill_fx_log.has("hit_spark"), "当たった所に火花")
	check(s.skill_fx_log.has("ripple"), "当たった所に衝撃の輪（撃った人の方を向く）")
	var hc: Dictionary = s.config.get("hit_fx", {})
	check(float(hc.get("flash_scale", 0.0)) > 0.0 and float(hc.get("spark_scale", 0.0)) >= 1.0, "当たった瞬間の白い光の設定がある（data/prototype_stick.json の hit_fx）")
	var sp := SkillFx.make({"kind": "spark", "size": 0.8, "flash": 0.55, "color": "#ffd24a", "life": 0.35}, Vector3.ZERO, Vector3.ZERO, 0.0)
	check(sp.get_node_or_null("Flash") != null, "火花に、白い一瞬の光")
	SkillFx.tick(sp, 0.15)
	check(not (sp.get_node("Flash") as Node3D).visible, "白い光は0.1秒で消える（画面のじゃまをしない）")
	sp.free()
	s.queue_free()

	var m := await make("mage")
	stand(m, 5.0)
	m.target_lock.set_target("boss")
	m.skill_fx_log.clear()
	m.perform("normal")
	tick(m, 1.2)
	check(m.skill_fx_log.has("magic_burst"), "魔法が当たった所に、魔法の輪と星")
	m.queue_free()

	var u := await make("gunner")
	stand(u, 7.0)
	u.target_lock.set_target("boss")
	u.gauge.value = u.gauge.max_value
	u.skill_fx_log.clear()
	u.perform("ultimate")
	tick(u, 2.6)
	check(u.skill_fx_log.has("blast"), "砲弾が当たった所に、小さな爆発")
	u.queue_free()

	# ---- 5. ボスは1発ごとにのけぞる（止まらない） ----
	var b := await make("gunner")
	var dt := 1.0 / 30.0
	b.hit_flash = 0.0
	b._pose_boss(dt)
	var reacts := 0
	for i in 6:
		# 2コマごとに当たる（つづけて当たる）
		b.hit_flash = maxf(0.0, b.hit_flash - dt)
		if i % 2 == 0:
			b.hit_flash = float(b.config["hit_flash_sec"])
		var before: float = b.boss_model.flinch
		b._pose_boss(dt)
		if i % 2 == 0 and b.boss_model.flinch > before and b.boss_model.flinch > 0.7:
			reacts += 1
	check(reacts == 3, "つづけて当たっても、1発ごとにのけぞる（%d/3）" % reacts)
	for i in 10:
		b.hit_flash = maxf(0.0, b.hit_flash - dt)
		b._pose_boss(dt)
	check(b.boss_model.flinch < 0.01, "のけぞりは短く、すぐ戻る（0.33秒で 0）")
	var bfs := float((b.config["hit_fx"] as Dictionary)["boss_flash_sec"])
	check(bfs < float(b.config["hit_flash_sec"]), "ボスが光るのは当たった直後だけ（連射でも点めつする）")
	b.queue_free()

	# ---- 6. ぬいぐるみ・プレゼントの箱の大きさ ----
	var t := await make("summoner")
	stand(t, 3.0)
	t.target_lock.set_target("boss")
	t.perform("sub")  # 版114：兵隊の Y（ぬいぐるみの突撃）
	tick(t, 0.6)
	var plush_ok := 0
	for un in t.skill_summons:
		var node: Node3D = un.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var mi := node.get_child(0) as MeshInstance3D
		var hgt: float = mi.mesh.get_aabb().size.y * mi.scale.y
		if absf(hgt - 1.6) < 0.05:
			plush_ok += 1
	check(plush_ok == 2, "ぬいぐるみ2体の背が約1.6m（ふつうのキャラの約半分。%d/2）" % plush_ok)
	t.queue_free()

	var bo := await make("bomber")
	stand(bo, 4.0)
	bo.target_lock.set_target("boss")
	bo.perform("main")
	tick(bo, 1.2)
	var box_ok := false
	for gm in bo.skill_gimmicks:
		box_ok = float(gm.get("box_scale", 0.0)) >= 2.0
	check(box_ok, "落ちたびっくりプレゼントの箱も大きい")
	bo.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

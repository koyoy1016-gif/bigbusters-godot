extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v79.gd
## 版79：ターゲットロック・飛ぶ物（銃弾・魔法・プレゼント）・スピードの透明化・プレゼントのしかけ・兵隊の呼び出し・
## 青い守りの膜・緑の回復の膜・回復の光・役の色・発射口・動き（足が床につく・歩く・勝った）・強い攻撃の手ごたえ・体のかたむき。
## 確かめること：
##   1. 敵のタップで、いちばん近い敵を選ぶ／同じ敵でロックを外す／敵が倒れると外れる（ボスを選び直す）
##   2. 飛ぶ物は、撃った時ではなく、当たった時にダメージが入る（銃弾・魔法・放物線・メテオ）
##   3. 透明化：消えている間は当たらない、攻撃すると現れて1.5倍
##   4. プレゼント：落ちて、ゆれて、開いてから爆発（爆発の時にダメージ）
##   5. 兵隊：重ならずに出て、敵へ行き、弾を撃ってダメージ、時間で退場
##   6. 守りの膜（青・半透明）：受けるダメージが減り、波紋が出る／回復の膜（緑・半透明）：毎秒回復・倒れた味方が起きる
##   7. 役の色：ファイター＝赤、スピード・シールド＝青、ヒーラー＝緑、剣士・アタッカー＝黄。必殺技にオーラ
##   8. 発射口（つえの先・砲口・弓）が、キャラの形の中にある
##   9. 動き：腕・脚の姿勢で作った動きで、足が床につく（うかない・しずまない）。歩く・勝った・負けたの動きがある

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const TargetLock := preload("res://scripts/combat/target_lock.gd")
const Projectiles := preload("res://scripts/combat/projectiles.gd")
const SkillFx := preload("res://scripts/fx/skill_fx.gd")
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


## 時間を進める（攻撃の動き・効果・飛ぶ物）
func tick(s: Node, sec: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 0.0001:
		s._actions_update(dt)
		s.combat_update(dt)
		t += dt
	Engine.time_scale = 1.0


func _initialize() -> void:
	# ---- 1. ターゲットロック ----
	var cands := [{"kind": "boss", "index": -1, "screen": Vector2(400, 300), "r_px": 120.0},
		{"kind": "sub", "index": 3, "screen": Vector2(700, 500), "r_px": 30.0}]
	check(str(TargetLock.pick(Vector2(420, 320), cands, 30.0).get("kind", "")) == "boss", "ロック：ボスの上をタップすると、ボスを選ぶ")
	check(int(TargetLock.pick(Vector2(690, 520), cands, 30.0).get("index", -1)) == 3, "ロック：小さい敵も、まわりに少しゆとりを持って選べる")
	check(TargetLock.pick(Vector2(50, 50), cands, 30.0).is_empty(), "ロック：何もない所のタップは、何も選ばない")
	var tl := TargetLock.new()
	tl.set_target("boss")
	tl.tick(0.5)
	check(tl.is_locked() and is_equal_approx(tl.age, 0.5), "ロック：ロックしてからの秒（照準の出る動き）")
	tl.clear()
	check(not tl.is_locked(), "ロック：外せる")

	var s := make("gunner")
	await process_frame  # カメラが画面の木に入るのを待つ
	stand(s, 5.0)
	s.target_lock.set_target("boss")
	var aim: Vector2 = s._aim_direction("normal")
	var to_boss := Vector2(s.boss.position.x - s.player.position.x, s.boss.position.z - s.player.position.z)
	check(aim.normalized().dot(to_boss.normalized()) > 0.999, "ロック中は、どの技もロックした敵の方へ向く")
	var center := Vector3(s.boss.position.x, s.boss.position.y + 2.5, s.boss.position.z)
	s.camera_update(0.016)
	var tap := s.camera.unproject_position(center) as Vector2
	s.target_lock.clear()
	check(s.tap_select(tap) and s.target_lock.kind == "boss", "画面でボスをタップすると、ロックする")
	check(s.tap_select(tap) and not s.target_lock.is_locked(), "同じ敵をもう一度タップすると、ロックを外す")
	s.target_lock.set_target("sub", 2)
	s._target_lock_update(0.016)
	check(s.target_lock.kind == "boss", "ロックした敵がいない（倒れた）と外れて、ボスを選び直す")
	s.boss.visible = false
	s._target_lock_update(0.016)
	check(not s.target_lock.is_locked(), "ボスが消えたら、ロックを外す")
	s.boss.visible = true
	s.queue_free()

	# ---- 2. 飛ぶ物：当たった時にダメージ ----
	var p := Projectiles.make({"mode": "straight", "speed": 40.0, "radius": 0.2, "range": 30.0}, Vector3(0, 1.3, 10), Vector3(0, 1.3, 0), "p1", 10.0, "normal")
	var tgt := {"x": 0.0, "z": 0.0, "r": 2.0, "h": 5.0, "y0": 0.0}
	var res := ""
	var steps := 0
	while res == "" and steps < 100:
		res = Projectiles.step(p, 0.02, tgt)
		steps += 1
	check(res == "hit" and steps >= 9 and steps <= 12, "銃弾：まっすぐ飛び、敵の表面で当たる（%d コマ）" % steps)
	var hm := Projectiles.make({"mode": "homing", "speed": 15.0, "radius": 0.3, "range": 40.0, "turn_deg": 140.0, "life": 5.0}, Vector3(0, 1.3, 10), Vector3(6, 1.3, 6), "p1", 10.0, "normal")
	res = ""
	steps = 0
	while res == "" and steps < 300:
		res = Projectiles.step(hm, 0.02, tgt)
		steps += 1
	check(res == "hit", "魔法：横へ撃っても、ゆるく曲がって敵へ向かう")
	var ar := Projectiles.make({"mode": "arc", "speed": 12.0, "arc": 2.5}, Vector3(0, 1.5, 8), Vector3(0, 0, 2), "p1", 10.0, "normal")
	var top := 0.0
	res = ""
	while res == "":
		res = Projectiles.step(ar, 0.02, {})
		top = maxf(top, (ar["pos"] as Vector3).y)
	check(res == "land" and (ar["pos"] as Vector3).distance_to(Vector3(0, 0, 2)) < 0.05 and top > 2.5, "放物線：山なりに飛んで、ねらった所に落ちる（高さ %.1f）" % top)
	check(Projectiles.blast_hits(Vector3(0, 0, 3.5), 2.0, tgt) and not Projectiles.blast_hits(Vector3(0, 0, 6.5), 2.0, tgt), "爆発の半径＝ダメージの範囲")

	var g := make("gunner")
	stand(g, 6.0)
	var h0: float = g.my_hits
	g.perform("normal")
	tick(g, 0.06, 0.02)
	check(g.skill_projs.size() >= 1 and is_equal_approx(g.my_hits, h0), "ガンナー：撃った時は、まだダメージが入らない（弾が飛んでいる）")
	check(g.skill_fx_log.has("prop"), "ガンナー：銃口の光が出る")
	tick(g, 1.0)
	var want := 1.0 * ap("gunner") * float(g.config["attack_multiplier"])
	check(is_equal_approx(g.my_hits - h0, want), "ガンナー：2発が当たって、ダメージが入る（%.2f／%.2f）" % [g.my_hits - h0, want])
	check(g.skill_fx_log.has("spark"), "ガンナー：当たった所に火花")
	g.queue_free()

	var mg := make("mage")
	stand(mg, 5.0)
	h0 = mg.my_hits
	mg.perform("normal")
	tick(mg, 0.2)
	check(mg.skill_projs.size() == 1 and is_equal_approx(mg.my_hits, h0), "魔法使い：つえの先から魔法の玉が出る（まだ当たっていない）")
	tick(mg, 1.5)
	check(is_equal_approx(mg.my_hits - h0, ap("mage") * float(mg.config["attack_multiplier"])), "魔法使い：玉が当たってダメージ")
	h0 = mg.my_hits
	mg.gauge.value = mg.gauge.max_value
	mg.perform("ultimate")
	tick(mg, 1.35)
	var meteor_y := -1.0
	for pp in mg.skill_projs:
		meteor_y = (pp["pos"] as Vector3).y
	check(meteor_y > 5.0 and is_equal_approx(mg.my_hits, h0), "メテオ：空の高い所から落ちてくる（高さ %.1f m）" % meteor_y)
	tick(mg, 2.0)
	check(mg.my_hits - h0 > 300.0, "メテオ：落ちて当たると大きなダメージ（%.1f）" % (mg.my_hits - h0))
	mg.queue_free()

	# ---- 3. スピードファイターの透明化 ----
	var sp := make("sprinter")
	stand(sp, 1.0)
	sp.perform("sub")  # 版114：瞬のバニッシュは、また Y
	tick(sp, 0.3)
	check(sp.skills.is_vanished(sp._my_slot()), "Y：姿が消える")
	check(not sp.char_view.visible, "Y：消えている間は、体が見えない")
	check(sp.skill_ghosts.size() > 0 or sp.skill_log.has("ghost"), "Y：消える時に、青い残像が出る")
	var hp0: float = sp.my_hp
	sp._take_damage(30.0)
	check(is_equal_approx(sp.my_hp, hp0), "Y：消えている間は、ボスの攻撃に当たらない")
	check(is_equal_approx(sp.skills.speed_mult(sp._my_slot()), 1.3), "Y：消えている間は、1.3倍の速さで動く")
	tick(sp, 0.25)
	h0 = sp.my_hits
	sp.perform("normal")
	tick(sp, 0.3)
	check(sp.char_view.visible and not sp.skills.is_vanished(sp._my_slot()), "攻撃すると、姿を現す（残像が集まる）")
	check(is_equal_approx(sp.my_hits - h0, 1.5 * ap("sprinter") * float(sp.config["attack_multiplier"])), "現れた最初の攻撃は1.5倍（%.2f）" % (sp.my_hits - h0))
	sp.queue_free()

	# ---- 4. ボンバーのびっくりプレゼント ----
	var bo := make("bomber")
	stand(bo, 4.0)
	h0 = bo.my_hits
	bo.perform("main")
	var landed_t := -1.0
	var t := 0.0
	while t < 4.0:
		tick(bo, 0.05)
		t += 0.05
		if landed_t < 0.0 and bo.skill_gimmicks.size() > 0:
			landed_t = t
			check(is_equal_approx(bo.my_hits, h0), "プレゼント：落ちた時は、まだ爆発しない（ゆれて、ふたが開く）")
	check(landed_t > 0.0 and bo.skill_log.has("present"), "プレゼント：落ちると、しかけが動く")
	check(bo.skill_fx_log.has("confetti"), "プレゼント：開くと、紙ふぶき")
	check(is_equal_approx(bo.my_hits - h0, 6.0 * ap("bomber") * float(bo.config["attack_multiplier"])), "プレゼント：爆発で、ダメージ（%.1f）" % (bo.my_hits - h0))
	check(bo.skill_gimmicks.is_empty(), "プレゼント：爆発したら消える")
	bo.queue_free()

	# ---- 5. おもちゃの兵隊の呼び出し ----
	var ty := make("summoner")
	stand(ty, 6.0)
	ty.perform("main")
	tick(ty, 0.6)
	var soldiers: Array = ty.skill_summons.filter(func(u: Dictionary) -> bool: return str(u["unit"]) == "soldier")
	check(soldiers.size() == 4, "X（版111 小隊召集）：兵隊が4人出る")
	var min_d := 99.0
	for i in soldiers.size():
		for j in range(i + 1, soldiers.size()):
			min_d = minf(min_d, (soldiers[i]["pos"] as Vector2).distance_to(soldiers[j]["pos"]))
	check(min_d >= 1.0, "兵隊は、重ならずに出る（いちばん近い2人で %.2f m）" % min_d)
	check(ty.skill_log.has("warm_mini"), "兵隊の動きは、戦いの始めに前もって作る")
	h0 = ty.my_hits
	tick(ty, 4.0)
	var near := 0
	for u in soldiers:
		var d: float = (u["pos"] as Vector2).distance_to(Vector2(ty.boss.position.x, ty.boss.position.z))
		if d < float(ty.config["boss_size"]) * 0.5 + 6.0:
			near += 1
	check(near == 4, "兵隊は、敵の近くまで行進する")
	check(ty.my_hits - h0 > 0.0, "兵隊が小さな弾を撃って、ダメージを与える（%.1f）" % (ty.my_hits - h0))
	tick(ty, 7.0)
	check(ty.skill_summons.is_empty(), "撃ち終わると（または時間がたつと）、兵隊は退場する")
	ty.queue_free()

	# ---- 6. 守りの膜・回復の膜・回復の光 ----
	var gd := make("guardian")
	stand(gd, 1.0)
	gd.perform("main")
	tick(gd, 1.0)
	check(gd.skill_domes.size() == 1 and str(gd.skill_domes[0]["kind"]) == "dome", "アーマー X：守りの膜を張る")
	hp0 = gd.my_hp
	gd._take_damage(40.0)
	check(is_equal_approx(hp0 - gd.my_hp, 10.0), "膜の中では、40のダメージが10になる")
	check(gd.skill_fx_log.has("ripple"), "膜に攻撃が当たると、波紋が出る")
	var dm := SkillFx.dome_material(Color("#4f9bff"), 0.14)
	var c: Color = dm.get_shader_parameter("color")
	check(float(dm.get_shader_parameter("alpha")) < 0.5 and c.b > c.r, "守りの膜は、青い半透明")
	gd.queue_free()

	var hl := make("healer", true)
	stand(hl, 3.0)
	hl._set_my_hp(50.0)
	var aslot: String = hl.ai_allies.keys()[0]
	hl.ai_allies[aslot]["hp"] = 0.0
	hl.ai_allies[aslot]["downed"] = true
	hl.ai_allies[aslot]["pos"] = Vector2(hl.player.position.x + 1.0, hl.player.position.z)
	hl.perform("main")
	tick(hl, 0.65)
	check(hl.skill_domes.size() == 1 and str(hl.skill_domes[0]["kind"]) == "heal_dome", "エンジェル X：緑の回復の膜を張る")
	var hpa: float = hl.my_hp
	tick(hl, 1.0)
	check(absf(hl.my_hp - hpa - 8.0) < 0.5, "回復の膜：中の味方が、1秒に8回復（%.2f）" % (hl.my_hp - hpa))
	tick(hl, 1.2)
	check(not bool(hl.ai_allies[aslot]["downed"]), "回復の膜：倒れた味方が、2秒で起きる")
	var dmg := SkillFx.dome_material(Color("#4fe08a"), 0.12)
	var c2: Color = dmg.get_shader_parameter("color")
	check(c2.g > c2.r and c2.g > c2.b and float(dmg.get_shader_parameter("alpha")) < 0.5, "回復の膜は、緑の半透明")
	hl.ai_allies[aslot]["hp"] = 20.0
	hl.ai_allies[aslot]["pos"] = Vector2(hl.player.position.x + 8.0, hl.player.position.z + 4.0)
	hl._set_my_hp(hl.role_value("hp"))
	hl.skill_domes = []
	hl.actions.reset()
	hl.perform("sub")  # 版114：介護士の Y（いやしの光）
	tick(hl, 2.0)
	check(is_equal_approx(float(hl.ai_allies[aslot]["hp"]), 60.0), "いやしの光：いちばん減っている味方へ飛んで、40回復")
	hl.ally_lock = hl._my_slot()
	hl._set_my_hp(30.0)
	hl.ai_allies[aslot]["hp"] = 10.0
	hl.actions.reset()
	hl.perform("sub")  # 版114：介護士の Y（いやしの光）
	tick(hl, 2.0)
	check(is_equal_approx(hl.my_hp, 70.0) and is_equal_approx(float(hl.ai_allies[aslot]["hp"]), 10.0), "いやしの光：タップで選んだ味方へ送れる")
	hl.queue_free()

	# ---- 7. 役の色・必殺技のオーラ ----
	var col := func(id: String) -> Color: return Color(str(Actions.meta_for(id).get("aura", "#000000")))
	check((col.call("brawler") as Color).r > 0.8 and (col.call("brawler") as Color).g < 0.4, "ファイターは赤")
	check((col.call("sprinter") as Color).b > 0.8 and (col.call("guardian") as Color).b > 0.8, "スピード・シールドは青")
	check((col.call("healer") as Color).g > 0.8 and (col.call("healer") as Color).r < 0.5, "ヒーラーは緑")
	check((col.call("gunner") as Color).r > 0.9 and (col.call("gunner") as Color).g > 0.7 and (col.call("hero_swordsman") as Color).g > 0.7, "剣士・アタッカーは黄")
	for id in IDS + ["hero_swordsman"]:
		var u: Dictionary = Actions.config_for(id)["actions"]["ultimate"]
		var aura := false
		for e in u.get("effects", []):
			if str(e["type"]) == "aura" and str(e["color"]) == str(Actions.meta_for(id)["aura"]):
				aura = true
		check(aura, "%s：必殺技の間、役の色のオーラ" % id)

	# ---- 8. 発射口 ----
	var cfg := CD.load_config()
	var socks := {"gunner": ["muzzle_L", "muzzle_R"], "mage": ["staff_tip"], "healer": ["bow"], "bomber": ["hand_L"], "summoner": ["hand_R"]}
	for id in socks:
		var v: Node3D = CV.new()
		root.add_child(v)
		v.setup(CD.find(cfg, id))
		await process_frame
		for nm in socks[id]:
			var sp3: Vector3 = v.socket_position(nm)
			check(sp3 != Vector3.INF and sp3.y > 0.6 and sp3.y < 5.0 and Vector2(sp3.x, sp3.z).length() < 2.0, "%s：発射口 %s が体の近く（高さ %.2f）" % [id, nm, sp3.y])
		v.queue_free()
	await process_frame

	# ---- 9. 動き ----
	for id in IDS + ["hero_swordsman"]:
		var def := CD.find(cfg, id)
		var v: Node3D = CV.new()
		root.add_child(v)
		v.setup(def)
		check(v.has_action("walk") and v.has_action("win") and v.has_action("lose"), "%s：歩く・勝った・負けたの動きがある" % id)
		if id == "hero_swordsman":
			v.queue_free()
			continue
		var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
		var fl := sk.find_bone("foot.L")
		var fr := sk.find_bone("foot.R")
		var rest := sk.get_bone_global_rest(fl).origin.y
		var worst := 0.0  # A の間、床からのずれ（両足が床）
		var sink := 0.0  # A・X の間、床より下にしずむ量
		for k in ["normal", "main"]:
			var an := CD.animation_for(def, str(Actions.config_for(id)["actions"][k]["steps"][0]["anim"]))
			var len: float = v.player.get_animation(an).length
			for i in 5:
				v.player.play(an)
				v.player.seek(len * float(i) / 4.0 * 0.999, true)
				v.player.pause()
				await process_frame
				await process_frame
				sk.force_update_all_bone_transforms()
				var low := minf(sk.get_bone_global_pose(fl).origin.y, sk.get_bone_global_pose(fr).origin.y) - rest
				if k == "normal":
					worst = maxf(worst, absf(low))
				sink = maxf(sink, -low)
		if id == "healer":
			check(sink < 0.02, "%s：うかんでいるキャラ。足が床にしずまない（%.3f）" % [id, sink])
		else:
			check(worst < 0.02 and sink < 0.02, "%s：A の間、足が床についている（ずれ %.3f）。X でも床にしずまない（%.3f）" % [id, worst, sink])
		v.queue_free()

	# ---- 10. 歩く・勝った・かたむき・強い攻撃の手ごたえ ----
	var w := make("brawler")
	w.stick_vec = Vector2(0.3, 0.0)
	w._update_character(0.016)
	check(w.char_view.current_action == "walk", "スティックを少し倒すと、歩く")
	w.stick_vec = Vector2(1.0, 0.0)
	w._update_character(0.016)
	check(w.char_view.current_action == "run", "大きく倒すと、走る")
	for i in 10:
		w.player.position.x += 0.7
		w._update_character(0.1)
	w.stick_vec = Vector2.ZERO
	w._update_character(0.1)
	w._update_character(0.1)
	check(w.lean.length() > 0.01, "止まると、体が少しかたむく（%.3f）" % w.lean.length())
	for i in 60:
		w._update_character(0.1)
	check(w.lean.length() < 0.01, "止まったままなら、まっすぐにもどる")
	stand(w, 0.8)
	w.gauge.value = w.gauge.max_value
	w.cam_zoom = 0.0
	w.cam_zoom_goal = 0.0
	w.shake_amp = 0.0
	w.perform("ultimate")
	tick(w, 1.0)
	check((w.cam_zoom > 0.0 or w.cam_zoom_goal > 0.0) and w.shake_amp > 0.0, "必殺技が当たると、画面がゆれて、カメラが少し寄る（版91：寄るのも、なめらかに）")
	check(w.skill_fx_log.has("aura"), "必殺技の間、オーラが出る")
	Engine.time_scale = 1.0
	w.actions.reset()
	w.cam_zoom = 0.0
	w.cam_zoom_goal = 0.0
	w.shake_amp = 0.0
	w.perform("normal")
	tick(w, 0.4)
	check(is_equal_approx(w.cam_zoom, 0.0) and is_equal_approx(w.cam_zoom_goal, 0.0) and is_equal_approx(w.shake_amp, 0.0), "弱い攻撃（ジャブ）では、画面はゆれない")
	w.won = true
	w._update_character(0.1)
	check(w.char_view.current_action == "win", "勝ったら、喜ぶ動き")
	w.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

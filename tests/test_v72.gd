extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v72.gd
## 版72：剣士の必殺技「切り捨て御免」を作り直した：構え → ため → 前へ踏み込み → 斬り捨て（斬撃・火花・一瞬止まる）→ 止まって構え直し。
## 動き（Sword_Ultimate）は Sword_Attack の時間を変えて作る（anim_retime.gd）。動く向き・斬撃の向き・当たりが同じ。
## 版72b：約10m 駆けぬける（ボスがいても、すりぬける）。通った道で当たりを調べる。剣士の形の残像。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Actions := preload("res://scripts/combat/player_actions.gd")
const AnimRetime := preload("res://scripts/characters/anim_retime.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var hero: Dictionary = CharacterData.find(CharacterData.load_config(), "hero_swordsman")
	var spec: Dictionary = hero["built_anims"]["Sword_Ultimate"]
	var map: Array = spec["map"]

	# ---- 1. 動きの作り方（時間を変える） ----
	check(is_equal_approx(AnimRetime.source_time(map, 0.0), 0.0) and is_equal_approx(AnimRetime.source_time(map, 0.25), 0.28), "0.25秒で剣を上に構えきる（元の0.28秒）")
	check(absf(AnimRetime.source_time(map, 0.70) - 0.415) < 0.001, "0.70秒（当たる時刻）は、剣が前を通る所（元の0.415秒）")
	check(is_equal_approx(AnimRetime.source_time(map, 1.5), 1.3), "1.5秒で構えにもどる（元の1.30秒）")
	var tr: Dictionary = spec["tremble"]
	check(not is_equal_approx(AnimRetime.source_time(map, 0.4, tr), AnimRetime.source_time(map, 0.4)) and is_equal_approx(AnimRetime.source_time(map, 0.7, tr), AnimRetime.source_time(map, 0.7)), "ためている間だけ、剣がふるえる")
	var view := CharacterView.new()
	root.add_child(view)
	check(view.setup(hero), "剣士の見た目を作れる")
	var p: AnimationPlayer = view.player
	check(p != null and p.has_animation("Sword_Ultimate") and is_equal_approx(p.get_animation("Sword_Ultimate").length, 1.5), "必殺技の動き Sword_Ultimate ができる（1.5秒）")
	var src := p.get_animation("Sword_Attack")
	var ult := p.get_animation("Sword_Ultimate")
	var same := true
	for ti in src.get_track_count():
		if src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var path := src.track_get_path(ti)
		var ui := ult.find_track(path, Animation.TYPE_ROTATION_3D)
		if ui < 0:
			same = false
			continue
		var q1: Quaternion = ult.rotation_track_interpolate(ui, 0.70)
		var q2: Quaternion = src.rotation_track_interpolate(ti, AnimRetime.source_time(map, 0.70, tr))
		if q1.angle_to(q2) > 0.12:
			same = false
	check(same, "作った動きの0.70秒の形は、元の Sword_Attack の振り下ろしの形と同じ（全部の骨）")
	check(CharacterView.build_retimed(p, hero) == 0, "2回作らない（もうあれば、そのまま）")
	check(CharacterData.animation_for(hero, "ult_slash") == "Sword_Ultimate", "必殺技の動きの名前 ult_slash → Sword_Ultimate")
	root.remove_child(view)
	view.free()

	# ---- 2. 動きの流れ：構え・ため（前へ出ない）→ 踏み込み → 斬る → 止まる ----
	var acfg := Actions.load_config()
	var u: Dictionary = acfg["actions"]["ultimate"]
	check((u["steps"] as Array).size() == 1 and str(u["steps"][0]["anim"]) == "ult_slash", "必殺技は、作った動き（ult_slash）を流す")
	var act := Actions.new(acfg)
	check(act.start("ultimate", Vector2(0, -1), -1.0), "必殺技を始められる")
	var fwd := 0.0
	var max_before_dash := 0.0
	var at_dash_end := 0.0
	var hit_t := -1.0
	var fwd_at_hit := 0.0
	var marks := {}
	var t := 0.0
	var inv := true
	while act.busy():
		var evs := act.update(0.01)
		t += 0.01
		fwd += act.frame_move.x
		if act.busy() and not act.invulnerable():
			inv = false
		if t <= 0.55:
			max_before_dash = maxf(max_before_dash, fwd)
		if absf(t - 0.72) < 0.006:
			at_dash_end = fwd
		for ev in evs:
			if str(ev["type"]) == "hit":
				hit_t = t
				fwd_at_hit = fwd
			if str(ev["type"]) == "mark":
				marks[str(ev["name"])] = t
	check(max_before_dash <= 0.001, "構えとためでは、前へ出ない（少し下がる）")
	check(at_dash_end > 9.5 and at_dash_end < 10.5, "0.55〜0.72秒で、前へ一気に約10m踏み込む（%.1f m）" % at_dash_end)
	check(absf(fwd - at_dash_end) < 0.1, "斬ったあとは止まる（そのあと %.2f m）" % (fwd - at_dash_end))
	check(absf(hit_t - 0.70) < 0.02 and fwd_at_hit > 9.0, "踏み込みのおわり（0.70秒・%.1f m 進んだ所）で斬る" % fwd_at_hit)
	check(absf(float(marks.get("ult_charge", -1.0)) - 0.25) < 0.02 and absf(float(marks.get("ult_dash", -1.0)) - 0.55) < 0.02, "ため（0.25秒）・踏み込み（0.55秒）の印")
	check(inv, "動いている間は、ずっと無敵")

	# ---- 3. 戦いの中：ボスへ踏み込み、ボスの手前で止まり、正面へ斬って当たる ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	var bp: Vector3 = s.boss.position
	var boss_r := float(s.config["boss_size"]) * 0.5
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + 9.0)
	s.facing = Vector2(1, 0)  # 横を向いていても、ボスのほうへ出る
	s.gauge.charge(99999.0)
	var hits0: float = s.my_hits
	check(s.perform("ultimate"), "剣士が必殺技を使う")
	var aim0: Vector2 = s.actions.aim
	var to_boss := Vector2(bp.x - s.player.position.x, bp.z - s.player.position.z)
	check(aim0.normalized().dot(to_boss.normalized()) > 0.99, "向きはボスのほう")
	var hit_dmg := 0.0
	var dist_at_hit := -1.0
	var angle_at_hit := 99.0
	var tt := 0.0
	var before_hit_dmg := 0.0
	while s.actions.busy() and tt < 3.0:
		var before: float = s.my_hits
		s._actions_update(0.02)
		Engine.time_scale = 1.0
		tt += 0.02
		var got: float = s.my_hits - before
		if got > 0.0 and hit_dmg == 0.0:
			hit_dmg = got
			var pp := Vector2(s.player.position.x, s.player.position.z)
			dist_at_hit = pp.distance_to(Vector2(bp.x, bp.z))
			angle_at_hit = rad_to_deg(absf(s.actions.aim.angle_to(Vector2(bp.x, bp.z) - pp)))
		elif got > 0.0:
			before_hit_dmg += got
		if hit_dmg == 0.0 and tt < 0.6:
			before_hit_dmg += got
	check(before_hit_dmg == 0.0, "構え・ための間は、ダメージは入らない")
	check(is_equal_approx(hit_dmg, 22.5 * 22.0 * 0.7), "斬り捨てで、一撃 346.5 ダメージ（版74で0.7倍。%.1f）" % hit_dmg)
	var end_p := Vector2(s.player.position.x, s.player.position.z)
	var start_p := Vector2(bp.x, bp.z + 9.0)
	check(start_p.distance_to(end_p) > 9.0, "ボスがいても止まらず、約10m 駆けぬける（%.1f m）" % start_p.distance_to(end_p))
	check((end_p - Vector2(bp.x, bp.z)).dot(aim0) > 0.0, "ボスをすりぬけて、向こう側まで出る")
	var sweep_pt: Vector2 = s.HitArea.closest_on(start_p, end_p, Vector2(bp.x, bp.z))
	check(sweep_pt.distance_to(Vector2(bp.x, bp.z)) < 0.5 and (sweep_pt - start_p).normalized().dot(aim0) > 0.99, "当たり：踏み込んだ道（体の前の向き）が、ボスを通る")
	check(is_equal_approx(s.my_hits - hits0, hit_dmg), "当たりは1回だけ")
	var log: Array = s.ult_fx_log
	var ghosts := 0
	for x in log:
		if str(x) == "ghost":
			ghosts += 1
	check(log.has("charge") and ghosts >= 4 and log.has("slash") and log.has("hit"), "見た目：ための輪・剣士の形の残像 %d 体・斬撃・当たった火花（%s）" % [ghosts, str(log)])
	check(float(s.shake_amp) > 0.2, "当たると、画面がゆれる（一瞬止まる）")
	# 見た目そのもの：それぞれ形があり、時間とともに消える（画面なしでは戦いの中に出ないので、ここで直接作る）
	var fxcfg: Dictionary = acfg["actions"]["ultimate"]["fx"]
	var holder := Node3D.new()
	for kind in ["charge", "ghost", "slash"]:
		var n: Node3D = UltFx.spawn(holder, kind, Vector3(0, 0, 0), Vector2(0, 1), fxcfg, {"parts": [[BoxMesh.new(), Transform3D()]], "xform": Transform3D()})
		var mi: MeshInstance3D = null
		for c in n.get_children():
			if c is MeshInstance3D and not c.is_queued_for_deletion():
				mi = c
		var a0: float = n.mat.albedo_color.a
		n._process(float(n.life) * 0.9)
		var a1: float = n.mat.albedo_color.a
		if kind == "charge":
			check(mi.mesh != null and a1 > a0 and n.scale.x < 0.5 and absf(float(n.life) - 0.3) < 0.01, "見た目「ため」：金の輪が、ちぢみながら明るくなる（明るさ %.2f → %.2f、大きさ %.2f）" % [a0, a1, n.scale.x])
		else:
			check(mi.mesh != null and a1 < a0 and float(n.life) > 0.1 and float(n.life) < 0.5, "見た目「%s」：形があり、%.2f 秒で消えていく（明るさ %.2f → %.2f）" % [kind, float(n.life), a0, a1])
	var sl: Node3D = holder.get_node("UltFx_slash")
	var fwdv: Vector3 = sl.global_transform.basis.z if sl.is_inside_tree() else sl.transform.basis.z
	check(sl.position.z > 0.3 and absf(fwdv.normalized().x) < 0.5, "斬撃は、体の前（向いている方）に出る")
	holder.free()
	# ボスがすぐそば（体にふれるくらい）でも、すりぬけながら当たる
	s.actions.reset()
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + boss_r + 0.5)
	s.gauge.charge(99999.0)
	var h0: float = s.my_hits
	s.perform("ultimate")
	while s.actions.busy():
		s._actions_update(0.02)
		Engine.time_scale = 1.0
	check(is_equal_approx(s.my_hits - h0, 346.5), "ボスがすぐそばでも、駆けぬけながら当たる")
	# 遠すぎると当たらない（斬撃は出る）
	s.actions.reset()
	s.ult_fx_log.clear()
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + 25.0)
	s.gauge.charge(99999.0)
	var h1: float = s.my_hits
	s.perform("ultimate")
	while s.actions.busy():
		s._actions_update(0.02)
		Engine.time_scale = 1.0
	check(is_equal_approx(s.my_hits, h1) and s.ult_fx_log.has("slash") and not s.ult_fx_log.has("hit"), "遠すぎると当たらない（斬撃は出るが、火花は出ない）")
	root.remove_child(s)
	s.free()

	# ---- 4. AIの味方の必殺技にも、斬撃が出る ----
	var s2: Node = (load(SCENE) as PackedScene).instantiate()
	s2.ai_enabled = true
	root.add_child(s2)
	if s2.get_node_or_null("Boss") == null:
		s2._ready()
	var now2 := [6000000.0]
	s2.clock_ms = func() -> float: return now2[0]
	s2.sfx = null
	s2.start_round()
	for slot in s2.ai_allies:
		(s2.ai_allies[slot]["gauge"]).charge(99999.0)
	var t2 := 0.0
	while t2 < 30.0 and not s2.ult_fx_log.has("slash"):
		now2[0] += 50.0
		t2 += 0.05
		s2.combat_update(0.05)
		s2._pose_boss(0.05)
		Engine.time_scale = 1.0
	check(s2.ult_fx_log.has("charge") and s2.ult_fx_log.has("slash"), "AIの味方が必殺技を当てると、ための輪と斬撃が出る（%.1f 秒）" % t2)
	root.remove_child(s2)
	s2.free()
	Engine.time_scale = 1.0

	print("")
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

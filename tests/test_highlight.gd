extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_highlight.gd
## ハイライトの記録（highlight_recorder.gd）と再生の図（highlight_replay.gd）を確かめる。

const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const Replay := preload("res://scripts/flow/highlight_replay.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var r := Recorder.new()
	check(r.best_window(6.0).is_empty(), "記録がなければ、ハイライトなし")
	# p1：0〜20秒でゆっくり稼ぐ（合計20）。p2：10〜14秒で一気に稼ぐ（合計40）
	for i in 21:
		r.record("p1", float(i), float(i) * 0.1, 0.0, float(i))
		var h2 := 0.0 if i < 10 else (minf(float(i - 10), 4.0) * 10.0)
		r.record("p2", float(i), 1.0, float(i) * 0.1, h2)
	var best := r.best_window(6.0)
	check(best["slot"] == "p2", "いちばん稼いだ区間の人を選ぶ")
	check(is_equal_approx(float(best["damage"]), 40.0), "稼いだ量が正しい（40）")
	check(float(best["start"]) >= 10.0 and float(best["start"]) <= 11.0, "区間が、稼ぎはじめの近くから始まる")
	check(float(best["end"]) - float(best["start"]) <= 6.0, "区間は窓の長さ以内")
	var none := Recorder.new()
	for i in 10:
		none.record("p1", float(i), 0.0, 0.0, 0.0)
	check(none.best_window(6.0).is_empty(), "だれもダメージを与えていなければ、ハイライトなし")
	var ties := Recorder.new()
	ties.record("p2", 0.0, 0, 0, 0.0)
	ties.record("p2", 1.0, 0, 0, 5.0)
	ties.record("p1", 0.0, 0, 0, 0.0)
	ties.record("p1", 1.0, 0, 0, 5.0)
	check(ties.best_window(6.0)["slot"] == "p1", "同点なら、先の枠（p1）")
	r.record("p1", 5.0, 9, 9, 99.0)
	check(r.samples["p1"].size() == 21, "時間をさかのぼる記録は捨てる")
	var path := r.path("p2", 10.0, 14.0)
	check(path.size() == 5, "区間の足あとの数")
	check(r.path("zz", 0.0, 5.0).is_empty(), "知らない枠の足あとは空")
	check(Recorder.position_on_path(path, 12.0).is_equal_approx(Vector2(1.0, 1.2)), "足あとの途中の位置")
	check(Recorder.position_on_path(path, -5.0).is_equal_approx(Vector2(1.0, 1.0)) and Recorder.position_on_path(path, 99.0).is_equal_approx(Vector2(1.0, 1.4)), "範囲の外は端の位置")
	check(Recorder.position_on_path([], 1.0) == Vector2.ZERO, "空の足あとでも壊れない")
	# 版63：巨大酒瓶ライドの間（入れない時刻）は、ハイライトに選ばない。ライドが終わったら、ふつうに選ぶ
	var rb := Recorder.new()
	for i in 31:
		var tt := float(i)
		rb.record("p1", tt, 0, 0, (60.0 if i >= 12 else float(i) * 0.5) + (float(i - 20) * 1.0 if i >= 20 else 0.0))
		if i >= 8 and i <= 14:
			rb.block(tt)
	var bw := rb.best_window(6.0)
	check(not bw.is_empty() and (float(bw["start"]) > 14.0 or float(bw["end"]) < 8.0), "ライドの間をふくむ区間は、ハイライトにしない（%s〜%s）" % [bw.get("start", -1), bw.get("end", -1)])
	var rb2 := Recorder.new()
	for i in 10:
		rb2.record("p1", float(i), 0, 0, float(i))
		rb2.block(float(i))
	check(rb2.best_window(6.0).is_empty(), "ライドの間しかなければ、ハイライトなし")
	rb.clear()
	check(rb.blocked.is_empty(), "clear で入れない時刻も消える（次の戦いはふつうに選ぶ）")
	var c := Recorder.new()
	c.record("p1", 0.0, 0, 0, 0)
	c.clear()
	check(c.samples.is_empty(), "clear で空になる")

	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var fcfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_flow.json"))
	var rep := Replay.new()
	root.add_child(rep)
	rep.size = Vector2(400, 400)
	rep.setup(path, Vector2(0, -6), 15.0, Color.WHITE, cfg, fcfg)
	check(rep.built and rep.camera != null and rep.viewport != null, "3Dの再生の場面ができる")
	check(is_equal_approx(rep.span, 4.0), "再生の長さは区間の長さ")
	check(rep.current_position().is_equal_approx(Vector2(1.0, 1.0)), "再生は、最初の位置から始まる")
	check(rep.player_box.position.is_equal_approx(Vector3(1.0, rep.player_box.position.y, 1.0)), "箱が足あとの最初の位置にいる")
	rep.advance(2.0)
	check(rep.current_position().is_equal_approx(Vector2(1.0, 1.2)), "再生が進む")
	check(is_equal_approx(rep.player_box.position.z, 1.2), "箱が動く")
	rep.advance(10.0)
	check(rep.play_time == 0.0, "終わったら、最初から繰り返す")
	var fr: Dictionary = Replay.camera_frame(Vector2(0, 4), Vector2(0, -6), 7.0, 4.5)
	check((fr["look"] as Vector3).is_equal_approx(Vector3(0, 1.2, -1)), "カメラは、プレイヤーとボスの真ん中を見る")
	check(Replay.camera_frame(Vector2(2, 2), Vector2(2, 2), 7.0, 4.5)["pos"].is_finite(), "ボスと同じ位置でも壊れない")
	for pl in [Vector2(0, 4), Vector2(0, -5.5), Vector2(12, 12), Vector2(-3, -6)]:
		var f2: Dictionary = Replay.camera_frame(pl, Vector2(0, -6), 7.0, 4.5)
		var cp: Vector3 = f2["pos"]
		var fwd := ((f2["look"] as Vector3) - cp).normalized()
		var ok := true
		for target in [Vector3(pl.x, 1.0, pl.y), Vector3(0, 1.5, -6)]:
			ok = ok and fwd.dot((target - cp).normalized()) > 0.7
		check(ok, "プレイヤーもボスも、カメラの前にある（" + str(pl) + "）")
	# 本物のモデルがあるキャラなら、箱の代わりにモデルを出す
	const CharacterData := preload("res://scripts/characters/character_data.gd")
	var ccfg := CharacterData.load_config()
	var hero := CharacterData.find(ccfg, str(ccfg["player_character"]))
	var rep2 := Replay.new()
	root.add_child(rep2)
	rep2.size = Vector2(400, 400)
	rep2.setup(path, Vector2(0, -6), 15.0, Color.WHITE, cfg, fcfg, hero)
	check(rep2.char_view != null and not rep2.player_box.visible, "モデルのあるキャラは、箱を隠してモデルを出す")
	check(is_equal_approx(rep2.char_view.position.x, 1.0) and is_equal_approx(rep2.char_view.position.z, 1.0), "モデルが足あとの最初の位置にいる")
	rep2.advance(0.1)
	rep2.advance(0.1)
	check(rep2.char_view.current_action in ["idle", "run", "attack"], "モデルに動きが付く：" + str(rep2.char_view.current_action))
	var far_path := [Vector3(0, 10, 10), Vector3(1, 10, 11), Vector3(2, 10, 12), Vector3(3, 10, 13)]
	rep2.setup(far_path, Vector2(0, -6), 15.0, Color.WHITE, cfg, fcfg, hero)
	rep2.advance(0.5)
	rep2.advance(0.5)
	check(rep2.char_view.current_action == "run", "ボスから遠くて動いていると、走る")
	var near_path := [Vector3(0, 0, -3), Vector3(1, 0, -3), Vector3(2, 0, -3), Vector3(3, 0, -3)]
	rep2.setup(near_path, Vector2(0, -6), 15.0, Color.WHITE, cfg, fcfg, hero)
	rep2.advance(0.5)
	check(rep2.char_view.current_action == "attack", "ボスの近くでは、こうげきする")
	rep2.setup(path, Vector2(0, -6), 15.0, Color.WHITE, cfg, fcfg, {})
	check(rep2.char_view == null and rep2.player_box.visible, "モデルのないキャラ（空）なら、箱にもどる")
	# 版60：ボスの記録 → 本物のボスで再生する。サブ敵は、消してあれば出さない
	var br := Recorder.new()
	for i in 6:
		br.record_boss(float(i), Vector3(float(i), 0.0, -6.0), 0.1 * i, "bat_h" if i < 3 else "thrust", 0.2 * (i % 3), i >= 4, float(i), 1.0, true)
	br.record_boss(2.5, Vector3.ZERO, 0.0, "", 0.0, false, 0.0, 0.0, true)
	check(br.boss_samples.size() == 6, "ボスの記録：時間をさかのぼる記録は捨てる")
	var bt := br.boss_path(2.0, 3.0)
	check(bt.size() == 4 and is_equal_approx(float(bt[0]["t"]), 1.0) and is_equal_approx(float(bt[3]["t"]), 4.0), "ボスの区間の記録は、前後に1つずつ余分に入る")
	var mid := Recorder.boss_at(bt, 1.5)
	check(is_equal_approx(float(mid["x"]), 1.5) and is_equal_approx(float(mid["u"]), 0.3) and str(mid["kind"]) == "bat_h", "ボスの記録の途中：位置と、同じ攻撃の進みはつなぐ")
	var cross := Recorder.boss_at(bt, 2.5)
	check(str(cross["kind"]) == "bat_h" and is_equal_approx(float(cross["u"]), 0.4), "攻撃が変わる所では、進みをつながない")
	check(Recorder.boss_at([], 1.0).is_empty(), "ボスの記録が空でも壊れない")
	br.clear()
	check(br.boss_samples.is_empty(), "clear でボスの記録も空になる")
	var cfg_off := cfg.duplicate()
	cfg_off["sub_enemy_enabled"] = false
	var rep3 := Replay.new()
	root.add_child(rep3)
	rep3.size = Vector2(400, 400)
	rep3.setup(path, Vector2(0, -6), 15.0, Color.WHITE, cfg_off, fcfg, hero, bt)
	check(rep3.boss_model != null and rep3.boss_root.visible and not rep3.boss_box.visible, "ボスの記録があれば、箱ではなく本物のボスを出す")
	check(not rep3.crowd.visible, "サブ敵を消してあれば、ハイライトにも出ない")
	rep3.play_time = 0.0
	rep3.points = [Vector3(1.5, 0, 0), Vector3(3.5, 0, 0)]
	rep3.advance(0.0)
	check(is_equal_approx(rep3.boss_root.position.x, 1.5) and is_equal_approx(rep3.boss_root.position.z, -6.0), "本物のボスが、記録どおりの位置にいる")
	check(rep3.boss_xz.is_equal_approx(Vector2(1.5, -6.0)), "カメラとキャラの向きも、記録のボスの位置を使う")
	rep3.setup(path, Vector2(0, -6), 15.0, Color.WHITE, cfg, fcfg, hero, [])
	check(not rep3.boss_root.visible and rep3.boss_box.visible and rep3.crowd.visible == bool(cfg.get("sub_enemy_enabled", true)), "ボスの記録がなければ、箱にもどる")
	rep.setup([], Vector2.ZERO, 15.0, Color.WHITE)
	rep.advance(1.0)
	check(rep.current_position() == Vector2.ZERO, "足あとが空でも、壊れない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

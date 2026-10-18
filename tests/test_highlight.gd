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
	var t1 := Replay.camera_target_position(Vector2(0, 4), Vector2(0, -6), 7.0, 4.5)
	check(t1.is_equal_approx(Vector3(0, 4.5, 11)), "カメラは、ボスから見てプレイヤーの後ろ側（ボスが奥に見える）")
	check(Replay.camera_target_position(Vector2(2, 2), Vector2(2, 2), 7.0, 4.5).is_finite(), "ボスと同じ位置でも壊れない")
	var cam_to_player := (Vector3(rep.player_box.position.x, 1.0, rep.player_box.position.z) - rep.camera.position).normalized()
	check((-rep.camera.global_transform.basis.z).dot(cam_to_player) > 0.99 if rep.camera.is_inside_tree() else (-rep.camera.transform.basis.z).dot(cam_to_player) > 0.9, "カメラがプレイヤーのほうを向いている")
	rep.setup([], Vector2.ZERO, 15.0, Color.WHITE)
	rep.advance(1.0)
	check(rep.current_position() == Vector2.ZERO, "足あとが空でも、壊れない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

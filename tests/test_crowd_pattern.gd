extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_crowd_pattern.gd
## サブ敵の動き（crowd_pattern.gd）と、まとめ描画（sub_enemy_crowd.gd）を確かめる。

const CrowdPattern := preload("res://scripts/combat/crowd_pattern.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var c := Vector2(0, -6)
	var a := CrowdPattern.position_at(3, 10, 5.0, c, 9.0, 0.35, 1.5)
	var b := CrowdPattern.position_at(3, 10, 5.0, c, 9.0, 0.35, 1.5)
	check(a == b, "同じ時間なら、同じ位置（全員の画面で一致する）")
	check(CrowdPattern.position_at(3, 10, 6.0, c, 9.0, 0.35, 1.5) != a, "時間が進むと動く")
	var ok := true
	for i in 10:
		for t in [0.0, 3.3, 20.0, 99.0]:
			var d := CrowdPattern.position_at(i, 10, t, c, 9.0, 0.35, 1.5).distance_to(c)
			if d < 7.4 or d > 10.6:
				ok = false
	check(ok, "いつでも、ボスから半径±ゆれ幅の中にいる")
	var spread := CrowdPattern.position_at(0, 10, 0.0, c, 9.0, 0.35, 0.0).distance_to(CrowdPattern.position_at(1, 10, 0.0, c, 9.0, 0.35, 0.0))
	check(spread > 1.0, "となりの敵と重ならない")
	check(CrowdPattern.position_at(0, 0, 0.0, c, 9.0, 0.35, 0.0).is_finite(), "数が0でも壊れない")

	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	check(int(cfg["sub_enemy_count"]) >= 10 and int(cfg["sub_enemy_count"]) <= 15, "サブ敵は10〜15体（データ）")
	var crowd := SubCrowd.new()
	root.add_child(crowd)
	crowd.setup(cfg, c)
	var instances := 0
	for ch in crowd.get_children():
		if ch is MultiMeshInstance3D:
			instances += 1
	check(instances == 1, "全員を1つの描画（MultiMesh）でまとめる")
	check(crowd.multi.instance_count == int(cfg["sub_enemy_count"]), "体の数がデータと同じ")
	crowd.update_at(4.0)
	var p0 := crowd.last_positions[0]
	crowd.update_at(8.0)
	check(crowd.last_positions[0] != p0, "更新すると位置が変わる")
	check(is_equal_approx(crowd.last_positions[0].y, float((cfg["sub_enemy_size"] as Array)[1]) * 0.5), "足が床の上にある")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

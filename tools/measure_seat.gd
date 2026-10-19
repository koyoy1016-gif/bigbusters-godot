extends SceneTree
## 巨大酒瓶ライドで、ボスが瓶に座る姿勢の、腰・ひざ・足の位置を測り、脚が瓶に埋まっていないか（瓶の面からの距離）を出す。
## godot --headless --path . --script res://tools/measure_seat.gd
## 座標：ボスの足もと（原点）から、大きさ（model_scale）をかけた m。前が +z、上が +y、左が +x

const BM := preload("res://scripts/boss/boss_model.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")


func _initialize() -> void:
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(BM.load_config(), StandardMaterial3D.new())
	var cfg := Attacks.load_config()
	var k: Dictionary = cfg["kinds"]["bottle_ride"]
	var sc := float(m.cfg["model_scale"])
	m.animate(0.0, 1.0, {"kind": "bottle_ride", "u": 3.0, "k": k, "ride_phase": "pass", "ride_phase_t": 0.0, "clock": 0.0})
	var hip_y: float = (m.anim.bone_model_pos(m.pose, "upperleg01.L").y + m.anim.bone_model_pos(m.pose, "upperleg01.R").y) * 0.5 * sc
	print("SEAT 腰（ももの付け根）の高さ %.2f m（data の seat_hip は %.2f）" % [hip_y, float(k["seat_hip"])])
	var R := float(k["bottle_radius"])
	var L := float(k["half_len"]) * 2.0
	# 瓶の中心：ボスの原点から見て、上へ (seat_hip − seat_butt − R)、前へ seat_back
	var cy := float(k["seat_hip"]) - float(k["seat_butt"]) - R
	var cz := float(k["seat_back"])
	var worst := 99.0
	for b in ["upperleg02.L", "lowerleg01.L", "lowerleg02.L", "foot.L", "upperleg02.R", "lowerleg01.R", "lowerleg02.R", "foot.R"]:
		var p: Vector3 = m.anim.bone_model_pos(m.pose, b) * sc
		var rr := BottleMesh.radius_at(p.z - cz, L, R)
		var dist := Vector2(p.x, p.y - cy).length() - rr
		worst = minf(worst, dist)
		print("SEAT %s  x=%.2f y=%.2f z=%.2f  瓶の面から %.2f m" % [b, p.x, p.y, p.z, dist])
	print("SEAT いちばん近い骨と瓶の面の距離 %.2f m（脚の太さ ぶん、0.25 m 以上あれば埋まらない）" % worst)
	quit()

extends SceneTree
## ボスの攻撃の「実際に届く所」を測る（バットの先・しっぽの先・手の位置を、当たる時間のあいだ追う）。
## 当たり範囲（data/boss_attacks.json）を、見た目の動きに合わせるために使う。
## godot --headless --path . --script res://tools/measure_reach.gd
## 出力の座標：ボスの足もとが原点、ボスの前が +z、ボスの左が +x（m）

const BM := preload("res://scripts/boss/boss_model.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")


func _initialize() -> void:
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(BM.load_config(), StandardMaterial3D.new())
	var cfg := Attacks.load_config()
	var kinds: Dictionary = cfg["kinds"]
	for kind in ["bat_h", "bat_v", "bat_spin", "walk_swing", "spin_bat"]:
		var k: Dictionary = kinds[kind]
		var ranges := _hit_ranges(kind, k)
		var rmax := 0.0
		var rmin := 999.0
		var amin := 999.0
		var amax := -999.0
		var zmin := 999.0
		var zmax := -999.0
		var xmax := 0.0
		for rg in ranges:
			var u := float(rg[0])
			while u <= float(rg[1]):
				var res: Dictionary = m.animate(0.0, 1.0, {"kind": kind, "u": u, "k": k})
				var tip: Vector3 = m.bat_tip_local()
				var spin := float(res.get("spin", 0.0))
				tip = Basis(Vector3.UP, spin) * tip
				if kind != "walk_swing":
					tip.z += Attacks.step_forward(kind, u, k)  # 歩きながら振るの扇は、振るときのボスの位置が中心
				var h := Vector2(tip.x, tip.z)
				rmax = maxf(rmax, h.length())
				rmin = minf(rmin, h.length())
				var ang := rad_to_deg(atan2(tip.x, tip.z))
				amin = minf(amin, ang)
				amax = maxf(amax, ang)
				zmin = minf(zmin, tip.z)
				zmax = maxf(zmax, tip.z)
				xmax = maxf(xmax, absf(tip.x))
				u += 0.01
		print("REACH %s  バットの先：半径 %.2f〜%.2f m、角度 %.0f〜%.0f 度、前 %.2f〜%.2f m、横 ±%.2f m" % [kind, rmin, rmax, amin, amax, zmin, zmax, xmax])
	# しっぽ回し：しっぽの先
	var tk: Dictionary = kinds["tail_spin"]
	var w := float(tk["windup_sec"])
	m.animate(0.0, 1.0, {"kind": "tail_spin", "u": w + float(tk["sweep_sec"]) * 0.5, "k": tk})
	var tip_t: Vector3 = m.tail_tip_local()
	print("REACH tail_spin  しっぽの先：半径 %.2f m（高さ %.2f m）" % [Vector2(tip_t.x, tip_t.z).length(), tip_t.y])
	# つかみ：左手
	var gk: Dictionary = kinds["grab"]
	var hf := float(gk["follow_sec"]) + float(gk["lock_sec"])
	m.animate(0.0, 1.0, {"kind": "grab", "u": hf, "k": gk})
	var hand: Vector3 = m.hand_world("L") - m.global_position
	print("REACH grab  左手：前 %.2f m、横 %.2f m、高さ %.2f m" % [hand.z, hand.x, hand.y])
	quit()


## 当たっている時間（攻撃の秒）の区間
func _hit_ranges(kind: String, k: Dictionary) -> Array:
	match kind:
		"bat_h":
			return [[float(k["windup_sec"]), float(k["windup_sec"]) + float(k["swing_sec"])]]
		"bat_v":
			return [[float(k["windup_sec"]), float(k["windup_sec"]) + float(k["hit_sec"])]]
		"bat_spin":
			return [[float(k["windup_sec"]) + 0.1, float(k["duration"]) - float(k["recover_sec"])]]
		"spin_bat":
			return [[float(k["windup_sec"]), float(k["windup_sec"]) + float(k["run_sec"])]]
		"walk_swing":
			var out: Array = []
			for i in int(k["swings"]):
				var t := Attacks.swing_time(i, k)
				out.append([t, t + float(k["hit_sec"])])
			return out
	return []

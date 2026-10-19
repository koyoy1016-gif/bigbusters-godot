extends SceneTree
## 攻撃の動きの、バットの先の道を、時間ごとに出す（動きと当たり範囲を合わせる確認用）。
## godot --headless --path . --script res://tools/trace_tip.gd -- 攻撃の種類 [刻み秒]
## 出力：u（攻撃の秒）、角度（ボスの正面が0、左が+）、半径（m）、高さ（m）、体ごとの回転（度）、当たっているか（*）
const BM := preload("res://scripts/boss/boss_model.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[0] if args.size() > 0 else "bat_h"
	var step := float(args[1]) if args.size() > 1 else 0.04
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(BM.load_config(), StandardMaterial3D.new())
	var cfg := Attacks.load_config()
	var k: Dictionary = cfg["kinds"][kind]
	var ctx := {"boss": Vector2.ZERO, "yaw": 0.0, "members": [], "positions": {}, "locked": null, "round_start_ms": 1.0, "bounds": 15.0}
	var u := 0.0
	while u < float(k["duration"]):
		var res: Dictionary = m.animate(0.0, 1.0, {"kind": kind, "u": u, "k": k})
		var tip: Vector3 = Basis(Vector3.UP, float(res["spin"])) * m.bat_tip_local()
		var active := false
		for h in Attacks.hazards({"n": 1, "kind": kind, "start": 0.0, "end": 9.0}, u, cfg, ctx):
			if bool(h["active"]):
				active = true
		print("u=%.2f 角度=%4.0f 半径=%.1f 高さ=%.1f 回転=%4.0f %s" % [u, rad_to_deg(atan2(tip.x, tip.z)), Vector2(tip.x, tip.z).length(), tip.y, rad_to_deg(float(res["spin"])), "*" if active else ""])
		u += step
	quit()

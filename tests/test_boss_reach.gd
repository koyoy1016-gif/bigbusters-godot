extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_boss_reach.gd
## ボスの攻撃の「身振り」と「当たり範囲」がそろっているか：当たっている間、バット（しっぽ）の先が、当たり範囲の中にあるか。
## ボスの大きさ・バットの長さ・動きを変えたら、data/boss_attacks.json の範囲も直す（tools/trace_tip.gd で測れる）。

const BM := preload("res://scripts/boss/boss_model.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const MARGIN_M := 1.2  # 先の位置のずれを、この長さまで許す
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(BM.load_config(), StandardMaterial3D.new())
	var cfg := Attacks.load_config()
	var ctx := {"boss": Vector2.ZERO, "yaw": 0.0, "members": [], "positions": {}, "locked": null, "round_start_ms": 1.0, "bounds": 15.0}
	for kind in ["bat_h", "bat_v", "bat_spin", "walk_swing", "tail_spin", "thrust"]:
		var k: Dictionary = cfg["kinds"][kind]
		var a := {"n": 1, "kind": kind, "start": 0.0, "end": 99.0}
		var total := 0
		var inside := 0
		var u := 0.0
		while u < float(k["duration"]):
			var hz: Array = Attacks.hazards(a, u, cfg, ctx)
			# 衝撃波（バットのあとに地面を走る物）は、バットの先とは別なので数えない
			var act: Array = hz.filter(func(h: Dictionary) -> bool: return bool(h["active"]) and str(h.get("part", "")) != "wave")
			if not act.is_empty():
				var res: Dictionary = m.animate(0.0, 1.0, {"kind": kind, "u": u, "k": k})
				var local: Vector3 = m.tail_tip_local() if kind == "tail_spin" else m.bat_tip_local()
				var tip := Basis(Vector3.UP, float(res["spin"])) * local
				var p := Vector2(tip.x, tip.z) + Attacks.fwd_of(0.0) * Attacks.step_forward(kind, u, k)
				total += 1
				for h in act:
					if _near(h, p):
						inside += 1
						break
			u += 0.01
		check(total > 0 and float(inside) / float(total) >= 0.85, "%s：当たっている間、先が範囲の中（%d / %d）" % [kind, inside, total])
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)


## 範囲を MARGIN_M だけ広げて、中にあるか
func _near(h: Dictionary, p: Vector2) -> bool:
	var g := h.duplicate()
	match str(h["shape"]):
		"sector":
			g["r"] = float(h["r"]) + MARGIN_M
			g["half"] = float(h["half"]) + MARGIN_M / maxf(float(h["r"]), 1.0)
		"ring":
			g["r"] = float(h["r"]) + MARGIN_M
			g["r_in"] = maxf(0.0, float(h["r_in"]) - MARGIN_M)
		"obox":
			g["hx"] = float(h["hx"]) + MARGIN_M
			g["hz"] = float(h["hz"]) + MARGIN_M
		_:
			g["r"] = float(h["r"]) + MARGIN_M
	return Attacks.inside(g, p.x, p.y)

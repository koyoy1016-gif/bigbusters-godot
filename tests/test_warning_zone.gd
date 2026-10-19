extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_warning_zone.gd
## 攻撃の予告の見た目（版60。shaders/warning_zone.gdshader）を確かめる。
## ふつうの攻撃はオレンジの円・帯、巨大酒瓶ライドの道はピンクの帯＋矢印。ライドの道は、通り抜けるまで出ている。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg := Attacks.load_config()
	var zs: Dictionary = cfg.get("zone_style", {})
	check(zs.has("attack") and zs.has("ride"), "予告の色の設定がデータにある（attack と ride）")

	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var hz := [
		{"id": "c", "shape": "circle", "x": 2.0, "z": 1.0, "r": 3.0, "active": false, "tele": 0.5, "power": 10.0, "style": "zone"},
		{"id": "b", "shape": "obox", "x": 0.0, "z": 0.0, "hx": 1.0, "hz": 4.0, "yaw": 0.0, "active": false, "tele": 0.3, "power": 10.0, "style": "zone"},
		{"id": "l", "shape": "box", "x": 0.0, "z": -3.0, "hx": 15.0, "hz": 2.0, "band_z": -3.0, "band_half": 15.0, "dir": -1.0, "active": false, "tele": 1.0, "power": 22.0, "style": "ride_lane"},
		{"id": "r", "shape": "obox", "x": 4.0, "z": -3.0, "hx": 2.0, "hz": 5.0, "yaw": 0.0, "active": true, "tele": 1.0, "power": 22.0, "style": "ride"},
	]
	s._show_hazards(hz)
	var n0: MeshInstance3D = s.hazard_nodes[0]
	var n1: MeshInstance3D = s.hazard_nodes[1]
	var n2: MeshInstance3D = s.hazard_nodes[2]
	var n3: MeshInstance3D = s.hazard_nodes[3]
	var m0 := n0.material_override as ShaderMaterial
	check(m0 != null and m0.shader != null, "予告は、予告用の描き方（シェーダー）で描く")
	check(m0 != null and int(m0.get_shader_parameter("mode")) == 0 and is_equal_approx(float(m0.get_shader_parameter("progress")), 0.5), "円の予告：丸の形、進みが入る")
	check(m0 != null and (m0.get_shader_parameter("fill_color") as Color).is_equal_approx(Color(str(zs["attack"]["fill"]))), "ふつうの攻撃は、オレンジの色")
	var m1 := n1.material_override as ShaderMaterial
	check(m1 != null and int(m1.get_shader_parameter("mode")) == 1 and int(m1.get_shader_parameter("grow_axis")) == 1, "向きのある帯：四角の形、ボスの側から前へ広がる")
	var m2 := n2.material_override as ShaderMaterial
	check(m2 != null and int(m2.get_shader_parameter("mode")) == 2, "ライドの道：矢印の帯")
	check(m2 != null and (m2.get_shader_parameter("fill_color") as Color).is_equal_approx(Color(str(zs["ride"]["fill"]))), "ライドの道は、ピンクの色")
	check(m2 != null and is_equal_approx(float(m2.get_shader_parameter("dir")), -1.0), "矢印は、走る向きを指す")
	check(n0.visible and n1.visible and n2.visible, "予告が見えている")
	check(not n3.visible, "走っている瓶の当たり場所の面は出さない（瓶そのものが見える）")
	check(s.hazard_fill_nodes.all(func(f: Node3D) -> bool: return not f.visible), "前の「中から広がる濃い面」は使わない（1枚の面で描く）")

	# ライドの道は、走り始めたあとも、通り抜けるまで出ている
	var k: Dictionary = cfg["kinds"]["bottle_ride"]
	var ctx := {"bounds": 15.0, "n": 0, "boss": Vector2.ZERO, "round_start_ms": 0.0}
	var ok := true
	for ps in Attacks.ride_plan(k, ctx):
		var mid := (float(ps["start"]) + float(ps["end"])) * 0.5
		var a := {"kind": Attacks.BOTTLE_RIDE, "n": 0}
		var lanes: Array = Attacks.hazards(a, mid, cfg, ctx).filter(func(h: Dictionary) -> bool: return str(h["style"]) == "ride_lane" and absf(float(h["z"]) - float(ps["z"])) < 0.01)
		ok = ok and lanes.size() == 1
	check(ok, "ライドの道は、走っている間も出ている（5回とも）")
	root.remove_child(s)
	s.free()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

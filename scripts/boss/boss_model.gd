extends Node3D
## ボスの3Dモデル（部品をコードで組む）。大きな胴体（これを親ノードにする）に、頭・目・口・足、
## そして「長い手」2本を付ける。手は、いくつもの節をなめらかにつないだ曲線で、手の先の位置（胴体から見た座標）に合わせて伸び縮みする。
## 色は1つの材質をみんなで使うので、ダメージのときの白い点滅が、体ぜんぶに出る。

const StyleFx := preload("res://scripts/characters/style_fx.gd")
const ARM_SEGMENTS := 10

var skin: StandardMaterial3D
var dark: StandardMaterial3D
var arm_nodes := {"L": [], "R": []}
var hand_nodes := {}
var finger_pivots := {}
var hand_bend := {"L": Vector3.ZERO, "R": Vector3.ZERO}
var shoulder := {"L": Vector3(1.35, 0.8, 0.0), "R": Vector3(-1.35, 0.8, 0.0)}
var hand_target := {"L": Vector3.ZERO, "R": Vector3.ZERO}
var cfg: Dictionary = {}


static func load_config(path: String = "res://data/boss_model.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 胴体の大きさなどは config（data/boss_model.json）から。skin_material は、胴体と共有する材質
func build(config: Dictionary, skin_material: StandardMaterial3D) -> void:
	cfg = config
	skin = skin_material
	dark = StandardMaterial3D.new()
	dark.albedo_color = Color(str(config["dark_color"]))
	dark.roughness = 0.6
	var tr := float(config["torso_radius"])
	var th := float(config["torso_height"])
	# 頭（胴体にうずまった丸い頭）と、目・口
	var head := _sphere(float(config["head_radius"]), skin, Vector3(0, th * 0.5 + float(config["head_radius"]) * 0.2, tr * 0.25))
	add_child(head)
	for sx in [-1.0, 1.0]:
		var eye := _sphere(float(config["eye_radius"]), _mat(Color(str(config["eye_color"]))), head.position + Vector3(sx * float(config["eye_gap"]), 0.15, float(config["head_radius"]) * 0.85))
		add_child(eye)
		var pupil := _sphere(float(config["eye_radius"]) * 0.45, dark, eye.position + Vector3(0, 0, float(config["eye_radius"]) * 0.8))
		add_child(pupil)
	# おこったまゆ（目の上に、内側が下がる棒）
	for sx in [-1.0, 1.0]:
		var brow := MeshInstance3D.new()
		var brm := BoxMesh.new()
		brm.size = Vector3(float(config["eye_radius"]) * 2.6, 0.1, 0.12)
		brm.material = dark
		brow.mesh = brm
		brow.position = head.position + Vector3(sx * float(config["eye_gap"]), 0.15 + float(config["eye_radius"]) * 1.25, float(config["head_radius"]) * 0.86)
		brow.rotation = Vector3(0, 0, sx * -0.38)
		add_child(brow)
	var mouth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(float(config["head_radius"]) * 1.1, 0.12, 0.1)
	bm.material = dark
	mouth.mesh = bm
	mouth.position = head.position + Vector3(0, -0.35, float(config["head_radius"]) * 0.92)
	add_child(mouth)
	# 歯（口の上に白い四角をならべる）
	var tooth_mat := _mat(Color("#f4efe0"))
	for k in 5:
		var tooth := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.09, 0.14, 0.06)
		tm.material = tooth_mat
		tooth.mesh = tm
		tooth.position = mouth.position + Vector3((float(k) - 2.0) * 0.16, 0.12, 0.02)
		add_child(tooth)
	# 肩のふくらみ
	for sx in [-1.0, 1.0]:
		add_child(_sphere(float(config["arm_radius"]) * 2.2, skin, Vector3(sx * tr * 0.92, th * 0.2, 0.0)))
	# 足（太い2本）と、足の裏
	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var leg_len := float(config["leg_length"])
		cm.top_radius = float(config["leg_radius"])
		cm.bottom_radius = float(config["leg_radius"]) * 1.15
		cm.height = leg_len
		cm.radial_segments = 12
		cm.material = skin
		leg.mesh = cm
		leg.position = Vector3(sx * float(config["leg_gap"]), -th * 0.5 * 0.8 - leg_len * 0.5 + 0.2, 0.1)
		add_child(leg)
		var foot := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(float(config["leg_radius"]) * 2.4, 0.3, float(config["leg_radius"]) * 3.0)
		fm.material = dark
		foot.mesh = fm
		foot.position = leg.position + Vector3(0, -leg_len * 0.5 - 0.05, float(config["leg_radius"]) * 0.7)
		add_child(foot)
	# 長い手
	shoulder["L"] = Vector3(tr * 0.92, th * 0.2, 0.0)
	shoulder["R"] = Vector3(-tr * 0.92, th * 0.2, 0.0)
	for side in ["L", "R"]:
		for i in ARM_SEGMENTS:
			var seg := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.radial_segments = 10
			sm.rings = 1
			sm.material = skin
			seg.mesh = sm
			add_child(seg)
			arm_nodes[side].append(seg)
		var hand := Node3D.new()
		add_child(hand)
		var hr := float(config["hand_radius"])
		# てのひら（平たい丸）
		var palm := _sphere(hr, skin, Vector3.ZERO)
		palm.scale = Vector3(1.0, 1.0, 0.55)
		hand.add_child(palm)
		# 指4本（2つの節。曲げられる）と、親指
		finger_pivots[side] = []
		for k in 5:
			var thumb := k == 4
			var a := (float(k) - 1.5) * 0.4 if not thumb else 0.0
			var base := Vector3(sin(a) * hr * 0.85, -hr * 0.75, 0.0) if not thumb else Vector3(hr * 0.9, -hr * 0.1, 0.0)
			var len1 := hr * (0.75 if not thumb else 0.6)
			var len2 := hr * (0.65 if not thumb else 0.5)
			var rad := hr * (0.2 if not thumb else 0.24)
			var p1 := Node3D.new()
			p1.position = base
			if thumb:
				p1.rotation = Vector3(0, 0, 1.0)
			else:
				p1.rotation = Vector3(0, 0, -a * 0.6)
			hand.add_child(p1)
			p1.add_child(_finger_seg(rad, len1))
			var p2 := Node3D.new()
			p2.position = Vector3(0, -len1, 0)
			p1.add_child(p2)
			p2.add_child(_sphere(rad * 1.05, skin, Vector3.ZERO))
			p2.add_child(_finger_seg(rad * 0.85, len2))
			(finger_pivots[side] as Array).append([p1, p2])
		hand_nodes[side] = hand
	pose_idle(0.0)


func _finger_seg(radius: float, length: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = length + radius * 1.2
	cm.radial_segments = 8
	cm.rings = 2
	cm.material = skin
	mi.mesh = cm
	mi.position = Vector3(0, -length * 0.5, 0)
	return mi


## 手をにぎる／ひらく。k：0（ひらく）〜 1（にぎる）。親指は、半分だけ曲げる
func set_curl(side: String, k: float) -> void:
	var list: Array = finger_pivots.get(side, [])
	for i in list.size():
		var pair: Array = list[i]
		var f := 0.5 if i == 4 else 1.0
		(pair[0] as Node3D).rotation.x = -k * 1.25 * f
		(pair[1] as Node3D).rotation.x = -k * 1.7 * f


## 手の大きさを変える（1.0 がふつう）
func set_hand_scale(side: String, s: float) -> void:
	(hand_nodes[side] as Node3D).scale = Vector3.ONE * s


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	StyleFx.style_material(m)
	return m


func _sphere(radius: float, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	sm.material = mat
	mi.mesh = sm
	mi.position = pos
	return mi


## 手の先の位置を決めて、節を並べなおす。target は、胴体から見た座標
func set_hand(side: String, target: Vector3, bend: Vector3 = Vector3.ZERO) -> void:
	hand_target[side] = target
	hand_bend[side] = bend
	_layout_arm(side)


func _layout_arm(side: String) -> void:
	var s: Vector3 = shoulder[side]
	var h: Vector3 = hand_target[side]
	var out := 1.0 if side == "L" else -1.0
	var control := (s + h) * 0.5 + Vector3(out * float(cfg["arm_bow"]), -float(cfg["arm_sag"]) * clampf((h - s).length() / float(cfg["arm_length"]), 0.2, 1.0), 0.0) + (hand_bend[side] as Vector3)
	var pts: Array = []
	for i in ARM_SEGMENTS + 1:
		var t := float(i) / float(ARM_SEGMENTS)
		pts.append(s.lerp(control, t).lerp(control.lerp(h, t), t))
	var r0 := float(cfg["arm_radius"])
	var r1 := float(cfg["arm_radius"]) * 0.7
	for i in ARM_SEGMENTS:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg: MeshInstance3D = arm_nodes[side][i]
		var d := b - a
		var len := maxf(d.length(), 0.01)
		var cm := seg.mesh as CylinderMesh
		cm.height = len * 1.08
		cm.bottom_radius = lerpf(r0, r1, float(i) / ARM_SEGMENTS)
		cm.top_radius = lerpf(r0, r1, float(i + 1) / ARM_SEGMENTS)
		seg.position = (a + b) * 0.5
		seg.basis = Basis(Quaternion(Vector3.UP, d / len))
	var hand: Node3D = hand_nodes[side]
	hand.position = h
	# 指が、手の進む向きのさきをむくように、少しかたむける
	var tip: Vector3 = (pts[ARM_SEGMENTS] as Vector3) - (pts[ARM_SEGMENTS - 1] as Vector3)
	if tip.length() > 0.01:
		hand.basis = Basis(Quaternion(Vector3.DOWN, tip.normalized()))


## ふだんの姿勢：両手を体の前でゆらゆらさせる。time は秒
func pose_idle(time: float) -> void:
	for side in ["L", "R"]:
		var out := 1.0 if side == "L" else -1.0
		var ph := 0.0 if side == "L" else 1.7
		var s: Vector3 = shoulder[side]
		set_hand(side, s + Vector3(out * (1.4 + 0.25 * sin(time * 1.3 + ph)), -3.9 + 0.3 * sin(time * 1.1 + ph), 2.3 + 0.35 * cos(time * 0.9 + ph)))


func hand_world(side: String) -> Vector3:
	return to_global(hand_target[side])

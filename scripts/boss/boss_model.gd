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
		hand.add_child(_sphere(float(config["hand_radius"]), skin, Vector3.ZERO))
		for k in 4:
			var f := MeshInstance3D.new()
			var fcm := CapsuleMesh.new()
			fcm.radius = float(config["hand_radius"]) * 0.22
			fcm.height = float(config["hand_radius"]) * 1.7
			fcm.material = skin
			f.mesh = fcm
			var a := (float(k) - 1.5) * 0.42
			f.position = Vector3(sin(a) * float(config["hand_radius"]) * 0.8, -float(config["hand_radius"]) * 0.9, cos(a) * float(config["hand_radius"]) * 0.4)
			f.rotation = Vector3(0, 0, -a * 0.5)
			hand.add_child(f)
		hand_nodes[side] = hand
	pose_idle(0.0)


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
func set_hand(side: String, target: Vector3) -> void:
	hand_target[side] = target
	_layout_arm(side)


func _layout_arm(side: String) -> void:
	var s: Vector3 = shoulder[side]
	var h: Vector3 = hand_target[side]
	var out := 1.0 if side == "L" else -1.0
	var control := (s + h) * 0.5 + Vector3(out * float(cfg["arm_bow"]), -float(cfg["arm_sag"]) * clampf((h - s).length() / float(cfg["arm_length"]), 0.2, 1.0), 0.0)
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

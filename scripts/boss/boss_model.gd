extends Node3D
## ボスの3Dモデル（部品をコードで組む）。イメージ図：二足歩行の鬼（角・赤いモヒカン・ジャケット・だぶだぶのズボン・しっぽ）。
## 平常時は腕2本＋小さめの腕2本でバットをかつぎ、体力が減ると「覚醒」して、酔っぱらった赤い姿（腕8本・はちまき・お酒）になる。
## 体力60%でよろけて倒れ、起き上がるときに覚醒する（update_form）。
## 大きな腕（L, R）は、手の先の位置（モデルの座標）に合わせて、いくつもの節をなめらかにつないだ曲線で伸び縮みする（攻撃の動きが使う）。
## 小さな腕（L2, R2, L3, R3, L4, R4）は、ふだんはゆらゆら動く飾り（覚醒の手は、あとで攻撃にも使う）。
## 色は材質を共有し、ダメージのときの白い点滅は set_flash で、すべての材質に出す。
## 軽くするため、組み終わったら動かない部品を親ごとに1つの形にまとめる（_bake。色は頂点の色）。腕の節としっぽは MultiMesh（まとめて1回で描く）。
## 指は「開いた手」と「にぎった手」を前もってまとめておき、set_curl で切り替える。
## モデルの原点は、足もとの床（高さ0）。向きは +Z が前（プレイヤー側）。

const StyleFx := preload("res://scripts/characters/style_fx.gd")
const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const BigArmSegments := 10
const SmallArmSegments := 5
const BIG := ["L", "R"]
const SMALL := ["L2", "R2", "L3", "R3", "L4", "R4"]

var skin: StandardMaterial3D
var dark: StandardMaterial3D
var mats: Array = []  ## 点滅させる材質（すべて）
var cfg: Dictionary = {}
var arm_nodes := {}  ## 腕のid → 節のノード
var hand_nodes := {}
var finger_pivots := {}
var hand_bend := {}
var hand_target := {}
var shoulder_base := {}
var shoulder := {}
var _hand_ready := {}
var arm_radius := {}
var arm_len := {}
var arm_forms := {}  ## 腕のid → この姿のときだけ出す（"" ならいつでも）
var frame_delta := 0.0
var lean := Vector2.ZERO  ## 体のかたむき（x：前へ、y：横へ。ラジアン）
var crouch := 0.0  ## しゃがみ具合（0〜1）
var form := "normal"  ## "normal"（平常時）／"awake"（覚醒）
var stagger_t := -1.0  ## よろけて倒れる動きの経過秒（動いていなければ -1）
var _flinch := 0.0
var _model_y := 0.0
var _model_y_set := false
var rig: Node3D  ## 体の部品の親（しゃがみで下がる）
var legs: Node3D
var bat: Node3D
var awake_nodes: Array = []  ## 覚醒のときだけ出す物
var normal_nodes: Array = []  ## 平常時だけ出す物
var tail_nodes: Array = []
var held_items := {}
var head: Node3D
var _clock := 0.0
var merge_cache := {}  ## まとめた形の材質（頂点の色で描く）
var arm_mm: MultiMeshInstance3D  ## 腕の節（全部の腕を1つで描く）
var arm_seg_sleeve: Array = []  ## 節の番号 → そで（true）か肌（false）か
var arm_visible := {}
var sleeve_color := Color.WHITE
var tail_mm: MultiMeshInstance3D
var tail_scales: Array = []
var hand_open := {}
var hand_fist := {}
var _band: Node3D


static func load_config(path: String = "res://data/boss_model.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 設定は config（data/boss_model.json）から。skin_material は、肌の材質（色は姿に合わせて変える）
func build(config: Dictionary, skin_material: StandardMaterial3D) -> void:
	cfg = config
	skin = skin_material
	skin.albedo_color = Color(str(cfg["skin_normal"]))
	mats.append(skin)
	dark = _mat(Color(str(cfg["dark_color"])))
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	legs = Node3D.new()
	legs.name = "Legs"
	add_child(legs)
	_build_legs()
	_build_upper()
	_build_head()
	_build_tail()
	_build_arms()
	_attach_props()
	_bake()
	_apply_form("normal")
	pose_idle(0.0)


# ---- 部品づくり ----

func _mat(color: Color, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	StyleFx.style_material(m)
	StyleFx.apply_outline(m, float(StyleFx.config().get("outline_width_boss", 0.05)) * 0.5)
	mats.append(m)
	return m


func _put(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mesh.material = mat if mesh is PrimitiveMesh else null
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _sphere(r: float, segs: int = 14, rings: int = 8) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m


func _cyl(r0: float, r1: float, h: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = r0
	m.top_radius = r1
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


## 2点の間に、太さの変わる棒をわたす
func _limb(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, segs: int = 10) -> MeshInstance3D:
	var d := b - a
	var len := maxf(d.length(), 0.01)
	var mi := _put(parent, _cyl(r0, r1, len, segs), mat, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d / len))
	return mi


func _build_legs() -> void:
	var pants := _mat(Color(str(cfg["pants_color"])))
	var boot := _mat(Color(str(cfg["boot_color"])))
	var sole := _mat(Color(str(cfg["dark_color"])))
	for sx in [-1.0, 1.0]:
		_limb(legs, Vector3(sx * 0.55, 1.55, 0.0), Vector3(sx * 0.62, 0.85, 0.12), 0.44, 0.4, pants)
		_limb(legs, Vector3(sx * 0.62, 0.85, 0.12), Vector3(sx * 0.62, 0.32, 0.05), 0.4, 0.46, pants)
		_put(legs, _box(0.62, 0.34, 1.0), boot, Vector3(sx * 0.62, 0.17, 0.3))
		_put(legs, _box(0.66, 0.1, 1.04), sole, Vector3(sx * 0.62, 0.05, 0.3))


func _build_upper() -> void:
	var pants := _mat(Color(str(cfg["pants_color"])))
	var jacket := _mat(Color(str(cfg["jacket_color"])))
	var sleeve := _mat(Color(str(cfg["sleeve_color"])))
	var gold := _mat(Color(str(cfg["emblem_color"])), 0.4)
	_put(rig, _box(1.5, 0.6, 0.9), pants, Vector3(0.0, 1.6, 0.0))
	_put(rig, _box(1.55, 0.14, 0.95), dark, Vector3(0.0, 1.95, 0.0))
	_put(rig, _box(0.26, 0.2, 0.06), gold, Vector3(0.0, 1.95, 0.5))
	# 胴（肌）
	_put(rig, _sphere(1.0, 16, 10), skin, Vector3(0.0, 2.7, 0.0), Vector3.ZERO, Vector3(1.05, 1.0, 0.72))
	# ジャケット：背中の大きな板（トラの印）、前の2枚、肩の白いそで
	_put(rig, _box(1.9, 1.7, 0.14), jacket, Vector3(0.0, 2.65, -0.62))
	_put(rig, _cyl(0.5, 0.5, 0.05, 16), gold, Vector3(0.0, 2.7, -0.71), Vector3(90.0, 0.0, 0.0))
	for sx in [-1.0, 1.0]:
		_put(rig, _box(0.6, 1.5, 0.12), jacket, Vector3(sx * 0.82, 2.6, 0.52), Vector3(0.0, sx * -12.0, sx * -4.0))
		_put(rig, _sphere(0.55, 12, 8), sleeve, Vector3(sx * 1.2, 3.3, 0.0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
		_put(rig, _sphere(0.44, 10, 6), sleeve, Vector3(sx * 1.25, 2.65, -0.1), Vector3.ZERO, Vector3(0.9, 0.7, 0.9))
	# ネックレス
	_put(rig, _cyl(0.5, 0.5, 0.04, 12), gold, Vector3(0.0, 3.2, 0.5), Vector3(70.0, 0.0, 0.0))


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 3.75, 0.2)
	rig.add_child(head)
	var hair := _mat(Color(str(cfg["hair_color"])))
	var horn := _mat(Color(str(cfg["horn_color"])), 0.4)
	var eye_mat := _mat(Color(str(cfg["eye_color"])), 0.3)
	var tooth := _mat(Color("#f4efe0"))
	_put(head, _sphere(0.62, 16, 10), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.05, 0.95))
	# 角
	for sx in [-1.0, 1.0]:
		_put(head, _cyl(0.16, 0.0, 0.7, 8), horn, Vector3(sx * 0.34, 0.62, 0.0), Vector3(0.0, 0.0, sx * -22.0))
		_put(head, _cyl(0.0, 0.12, 0.5, 6), skin, Vector3(sx * 0.66, 0.0, -0.05), Vector3(0.0, 0.0, sx * -80.0))
	# 赤いモヒカン（うしろへ流れる）
	for i in 6:
		var k := float(i) / 5.0
		_put(head, _cyl(0.2 - 0.06 * k, 0.02, 0.55 - 0.12 * k, 6), hair, Vector3(0.0, 0.62 - 0.15 * k, 0.32 - 0.62 * k), Vector3(-20.0 - 55.0 * k, 0.0, 0.0))
	# 目・まゆ・口・牙
	for sx in [-1.0, 1.0]:
		_put(head, _sphere(0.14, 8, 5), eye_mat, Vector3(sx * 0.24, 0.08, 0.52))
		_put(head, _sphere(0.06, 6, 4), dark, Vector3(sx * 0.24, 0.08, 0.64))
		_put(head, _box(0.36, 0.07, 0.08), dark, Vector3(sx * 0.24, 0.3, 0.52), Vector3(0.0, 0.0, sx * -22.0))
	_put(head, _box(0.62, 0.1, 0.08), dark, Vector3(0.0, -0.28, 0.55))
	for k in 4:
		var tx := (float(k) - 1.5) * 0.14
		_put(head, _cyl(0.04, 0.0, 0.16, 5), tooth, Vector3(tx, -0.2 if k % 2 == 0 else -0.35, 0.58), Vector3(180.0 if k % 2 == 1 else 0.0, 0.0, 0.0))
	# はちまき（覚醒のときだけ）
	var band := _mat(Color("#f2efe6"))
	_band = Node3D.new()
	_band.name = "Band"
	head.add_child(_band)
	_put(_band, _cyl(0.64, 0.64, 0.16, 16), band, Vector3(0.0, 0.3, 0.0))
	_put(_band, _cyl(0.1, 0.1, 0.03, 12), _mat(Color("#c0203a")), Vector3(0.0, 0.3, 0.64), Vector3(90.0, 0.0, 0.0))
	awake_nodes.append(_band)


func _build_tail() -> void:
	var tail_mat := _mat(Color(str(cfg["tail_color"])))
	var tuft := Color(str(cfg["hair_color"]))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _sphere(1.0, 8, 5)
	mm.instance_count = 9
	for i in 9:
		var k := float(i) / 8.0
		var r := 0.26 * (1.0 - 0.6 * k)
		tail_scales.append(Vector3(r, r, r) * (Vector3(1.6, 1.6, 2.4) if i == 8 else Vector3.ONE))
		mm.set_instance_color(i, tail_mat.albedo_color if i < 8 else tuft)
		tail_nodes.append(i)
	tail_mm = MultiMeshInstance3D.new()
	tail_mm.name = "Tail"
	tail_mm.multimesh = mm
	tail_mm.material_override = MeshMerge.vc_material(tail_mat, merge_cache)
	add_child(tail_mm)
	_update_tail(0.0)


func _update_tail(clock: float) -> void:
	var base := Vector3(0.0, 1.9 - 0.5 * crouch, -0.7)
	for i in tail_nodes.size():
		var k := float(i) / float(tail_nodes.size() - 1)
		var sway := sin(clock * 1.6 - k * 2.4) * 0.5 * k
		var p := base + Vector3(sway, -0.55 * k * (1.0 + 0.4 * k) + 0.45 * sin(k * PI) * (1.0 - crouch), -1.4 * k * (1.0 + 0.3 * k))
		tail_mm.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(tail_scales[i]), p))


# ---- 腕 ----

func _build_arms() -> void:
	var bt := float(cfg["torso_arm_y"])
	var defs := {
		"L": [Vector3(1.2, bt, 0.0), float(cfg["arm_radius"]), float(cfg["arm_length"]), ""],
		"R": [Vector3(-1.2, bt, 0.0), float(cfg["arm_radius"]), float(cfg["arm_length"]), ""],
		"L2": [Vector3(1.0, bt - 0.55, -0.35), float(cfg["small_arm_radius"]), float(cfg["small_arm_length"]), ""],
		"R2": [Vector3(-1.0, bt - 0.55, -0.35), float(cfg["small_arm_radius"]), float(cfg["small_arm_length"]), ""],
		"L3": [Vector3(0.95, bt - 1.0, -0.4), float(cfg["small_arm_radius"]), float(cfg["small_arm_length"]), "awake"],
		"R3": [Vector3(-0.95, bt - 1.0, -0.4), float(cfg["small_arm_radius"]), float(cfg["small_arm_length"]), "awake"],
		"L4": [Vector3(0.9, bt - 1.4, -0.45), float(cfg["small_arm_radius"]), float(cfg["small_arm_length"]), "awake"],
		"R4": [Vector3(-0.9, bt - 1.4, -0.45), float(cfg["small_arm_radius"]), float(cfg["small_arm_length"]), "awake"],
	}
	var sleeve := _mat(Color(str(cfg["sleeve_color"])))
	for id in defs:
		var d: Array = defs[id]
		shoulder_base[id] = d[0]
		shoulder[id] = d[0]
		arm_radius[id] = d[1]
		arm_len[id] = d[2]
		arm_forms[id] = d[3]
		hand_bend[id] = Vector3.ZERO
		hand_target[id] = Vector3.ZERO
		_hand_ready[id] = false
		var big := BIG.has(id)
		var n := BigArmSegments if big else SmallArmSegments
		arm_nodes[id] = []
		arm_visible[id] = true
		for i in n:
			(arm_nodes[id] as Array).append(arm_seg_sleeve.size())
			arm_seg_sleeve.append(big and i < 2)
		var hand := Node3D.new()
		add_child(hand)
		hand_nodes[id] = hand
		var hr := float(cfg["hand_radius"]) * (1.0 if big else 0.7)
		var palm := _put(hand, _sphere(hr, 10, 6), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.55))
		palm.set_meta("finger", true)
		finger_pivots[id] = []
		var claw := _mat(Color(str(cfg["horn_color"])), 0.4)
		for k in (5 if big else 3):
			var thumb := big and k == 4
			var a := (float(k) - (1.5 if big else 1.0)) * (0.4 if big else 0.5) if not thumb else 0.0
			var base := Vector3(sin(a) * hr * 0.85, -hr * 0.75, 0.0) if not thumb else Vector3(hr * 0.9, -hr * 0.1, 0.0)
			var len1 := hr * (0.75 if not thumb else 0.6)
			var len2 := hr * 0.65
			var rad := hr * (0.2 if not thumb else 0.24)
			var p1 := Node3D.new()
			p1.set_meta("finger", true)
			p1.position = base
			p1.rotation = Vector3(0, 0, 1.0) if thumb else Vector3(0, 0, -a * 0.6)
			hand.add_child(p1)
			p1.add_child(_finger_seg(rad, len1))
			var p2 := Node3D.new()
			p2.position = Vector3(0, -len1, 0)
			p1.add_child(p2)
			if big:
				p2.add_child(_sphere_node(rad * 1.05))
			p2.add_child(_finger_seg(rad * 0.85, len2))
			# つめ
			var nail := _put(p2, _cyl(rad * 0.7, 0.0, hr * 0.35, 5), claw, Vector3(0, -len2 - rad, 0), Vector3(180.0, 0.0, 0.0))
			nail.name = "Nail"
			(finger_pivots[id] as Array).append([p1, p2])
	# 肩・腕のつけ根の見た目（そでの丸み）は _build_upper にある
	# 腕の節：全部の腕を、1つの MultiMesh で描く（形は作り直さず、節ごとの変形だけ変える）
	sleeve_color = sleeve.albedo_color
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var unit := CylinderMesh.new()
	unit.top_radius = 1.0
	unit.bottom_radius = 1.0
	unit.height = 1.0
	unit.radial_segments = 10
	unit.rings = 1
	mm.mesh = unit
	mm.instance_count = arm_seg_sleeve.size()
	arm_mm = MultiMeshInstance3D.new()
	arm_mm.name = "Arms"
	arm_mm.multimesh = mm
	arm_mm.material_override = MeshMerge.vc_material(skin, merge_cache)
	add_child(arm_mm)
	_refresh_arm_colors()


func _refresh_arm_colors() -> void:
	if arm_mm == null:
		return
	for i in arm_seg_sleeve.size():
		arm_mm.multimesh.set_instance_color(i, sleeve_color if arm_seg_sleeve[i] else skin.albedo_color)


## 組み終わった部品を、親ごとに1つの形にまとめる（軽くするため）。手は「開いた手」「にぎった手」の2つを作る
func _bake() -> void:
	for id in hand_nodes:
		_bake_hand(id)
	var containers: Array = [legs, rig, head, _band, bat]
	for id in held_items:
		containers.append(held_items[id])
	for n in containers:
		if n != null:
			MeshMerge.merge_children(n, [skin], merge_cache)
	# 点滅させる材質は、肌と、まとめた形の材質
	mats = [skin]
	for k in merge_cache:
		mats.append(merge_cache[k])


func _bake_hand(id: String) -> void:
	var hand: Node3D = hand_nodes[id]
	var parts_nodes: Array = []
	var others: Array = []
	for c in hand.get_children():
		if c.has_meta("finger"):
			parts_nodes.append(c)
		else:
			others.append(c)
	for state in [["Open", 0.0], ["Fist", 0.85]]:
		_curl_pivots(id, float(state[1]))
		var mesh := MeshMerge.merge_parts(MeshMerge.collect(hand, others), [skin], merge_cache)
		var mi := MeshInstance3D.new()
		mi.name = str(state[0])
		mi.mesh = mesh
		hand.add_child(mi)
		others.append(mi)
		if state[0] == "Open":
			hand_open[id] = mi
		else:
			hand_fist[id] = mi
	for n in parts_nodes:
		hand.remove_child(n)
		n.free()
	finger_pivots.erase(id)
	(hand_fist[id] as Node3D).visible = false


func _sphere_node(r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := _sphere(r, 8, 5)
	sm.material = skin
	mi.mesh = sm
	return mi


func _finger_seg(radius: float, length: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = length + radius * 1.2
	cm.radial_segments = 6
	cm.rings = 2
	cm.material = skin
	mi.mesh = cm
	mi.position = Vector3(0, -length * 0.5, 0)
	return mi


## 手に持つ物：平常時はバット（右手）、覚醒はお酒のびん・ひょうたん（腕ごと）
func _attach_props() -> void:
	var steel := _mat(Color(str(cfg["bat_color"])), 0.35)
	bat = Node3D.new()
	bat.name = "Bat"
	(hand_nodes["R"] as Node3D).add_child(bat)
	var shaft := _put(bat, _cyl(0.2, 0.1, 3.4, 10), steel, Vector3(0.0, 1.5, 0.0))
	_put(bat, _cyl(0.1, 0.1, 0.5, 8), dark, Vector3(0.0, -0.1, 0.0))
	_put(bat, _sphere(0.3, 8, 5), steel, Vector3(0.0, 3.3, 0.0))
	for k in 6:
		var a := float(k) * TAU / 6.0
		_put(bat, _cyl(0.0, 0.09, 0.28, 4), steel, Vector3(cos(a) * 0.28, 2.4 + 0.3 * float(k % 3), sin(a) * 0.28), Vector3(sin(a) * 70.0, 0.0, -cos(a) * 70.0))
	bat.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	normal_nodes.append(bat)
	shaft.name = "Shaft"
	# お酒
	var glass := _mat(Color(str(cfg["bottle_color"])), 0.2)
	var jug := _mat(Color(str(cfg["jug_color"])), 0.5)
	var label := _mat(Color("#f2efe6"))
	for id in ["L", "L2", "R2", "L3", "R3", "L4", "R4"]:
		var item := Node3D.new()
		item.name = "Drink"
		(hand_nodes[id] as Node3D).add_child(item)
		if id == "L" or id == "L3" or id == "R4":
			_put(item, _sphere(0.42, 10, 6), jug, Vector3(0.0, -0.45, 0.0), Vector3.ZERO, Vector3(1.0, 1.15, 1.0))
			_put(item, _cyl(0.12, 0.12, 0.3, 8), jug, Vector3(0.0, -0.05, 0.0))
			_put(item, _box(0.34, 0.34, 0.04), label, Vector3(0.0, -0.45, 0.42))
		else:
			_put(item, _cyl(0.2, 0.2, 0.7, 8), glass, Vector3(0.0, -0.55, 0.0))
			_put(item, _cyl(0.09, 0.2, 0.3, 8), glass, Vector3(0.0, -0.05, 0.0))
			_put(item, _box(0.22, 0.28, 0.03), label, Vector3(0.0, -0.55, 0.21))
		item.visible = false
		held_items[id] = item
		awake_nodes.append(item)


# ---- 姿・表情の切り替え ----

func _apply_form(name: String) -> void:
	form = name
	var awake := name == "awake"
	skin.albedo_color = Color(str(cfg["skin_awake"] if awake else cfg["skin_normal"]))
	for n in awake_nodes:
		(n as Node3D).visible = awake
	for n in normal_nodes:
		(n as Node3D).visible = not awake
	for id in arm_nodes:
		var vis: bool = str(arm_forms[id]) == "" or (str(arm_forms[id]) == "awake" and awake)
		arm_visible[id] = vis
		(hand_nodes[id] as Node3D).visible = vis
		_layout_arm(id)
	_refresh_arm_colors()


func skin_color() -> Color:
	return skin.albedo_color


## 戦いの始まりなどで、平常時の姿にもどす
func reset_form() -> void:
	stagger_t = -1.0
	crouch = 0.0
	_apply_form("normal")


func is_staggering() -> bool:
	return stagger_t >= 0.0


func is_awake() -> bool:
	return form == "awake"


## 体力の割合（1.0 が満タン）を見て、姿を変える。60%でよろけ始め（倒れて）、起き上がるとき覚醒する。50%以下なら、必ず覚醒の姿
func update_form(hp_ratio: float, delta: float) -> void:
	if form == "normal" and stagger_t < 0.0 and hp_ratio <= float(cfg["stagger_at"]) and hp_ratio > float(cfg["awake_at"]) - 0.02:
		stagger_t = 0.0
	if form == "normal" and hp_ratio <= float(cfg["awake_at"]) and stagger_t < 0.0:
		_apply_form("awake")
	if stagger_t >= 0.0:
		stagger_t += delta
		if form == "normal" and stagger_t >= float(cfg["stagger_swap_sec"]):
			_apply_form("awake")
		if stagger_t >= float(cfg["stagger_sec"]):
			stagger_t = -1.0
	if form == "awake" and hp_ratio > float(cfg["stagger_at"]) + 0.05 and stagger_t < 0.0:
		reset_form()


## よろけて倒れる動きの、いまのかたむき（x：前へ）としゃがみ具合
func _stagger_pose() -> Vector2:
	var t := stagger_t
	var total := float(cfg["stagger_sec"])
	var s := float(cfg["stagger_swap_sec"])
	if t < 0.5:
		return Vector2(lerpf(0.0, -0.5, t / 0.5), 0.0)
	if t < 1.3:
		var k := (t - 0.5) / 0.8
		return Vector2(lerpf(-0.5, 0.75, smoothstep(0.0, 1.0, k)), lerpf(0.0, 0.85, smoothstep(0.0, 1.0, k)))
	if t < s:
		return Vector2(0.75 + 0.05 * sin(t * 9.0), 0.85)
	var k2 := clampf((t - s) / maxf(0.01, total - s), 0.0, 1.0)
	return Vector2(lerpf(0.75, float(cfg["awake_lean"]), smoothstep(0.0, 1.0, k2)), lerpf(0.85, float(cfg["awake_crouch"]), smoothstep(0.0, 1.0, k2)))


# ---- 手のあつかい（大きな腕は、攻撃の動きが使う） ----

## にぎる（k=1）／ひらく（k=0）。軽くするため、前もって作った「開いた手」「にぎった手」を切り替える
func set_curl(side: String, k: float) -> void:
	if hand_open.has(side):
		(hand_open[side] as Node3D).visible = k < 0.45
		(hand_fist[side] as Node3D).visible = k >= 0.45
		return
	_curl_pivots(side, k)


func _curl_pivots(side: String, k: float) -> void:
	var list: Array = finger_pivots.get(side, [])
	for i in list.size():
		var pair: Array = list[i]
		var f := 0.5 if (BIG.has(side) and i == 4) else 1.0
		(pair[0] as Node3D).rotation.x = -k * 1.25 * f
		(pair[1] as Node3D).rotation.x = -k * 1.7 * f


func set_hand_scale(side: String, s: float) -> void:
	(hand_nodes[side] as Node3D).scale = Vector3.ONE * s


## 手の先の位置を決めて、節を並べなおす。target は、モデルの座標。frame_delta があれば、目標へなめらかに近づく
func set_hand(side: String, target: Vector3, bend: Vector3 = Vector3.ZERO) -> void:
	if frame_delta > 0.0 and bool(_hand_ready[side]):
		var k := 1.0 - exp(-float(cfg.get("hand_follow_rate", 12.0)) * frame_delta)
		target = (hand_target[side] as Vector3).lerp(target, k)
	_hand_ready[side] = true
	hand_target[side] = target
	hand_bend[side] = bend
	_layout_arm(side)


func _layout_arm(side: String) -> void:
	var s: Vector3 = shoulder[side]
	var h: Vector3 = hand_target[side]
	var out := 1.0 if side.begins_with("L") else -1.0
	var length := float(arm_len[side])
	var control := (s + h) * 0.5 + Vector3(out * float(cfg["arm_bow"]), -float(cfg["arm_sag"]) * clampf((h - s).length() / length, 0.2, 1.0), 0.0) + (hand_bend[side] as Vector3)
	var segs: Array = arm_nodes[side]
	var n := segs.size()
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(s.lerp(control, t).lerp(control.lerp(h, t), t))
	var r0 := float(arm_radius[side])
	var r1 := r0 * 0.7
	var mm := arm_mm.multimesh
	var vis: bool = arm_visible.get(side, true)
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		var len := maxf(d.length(), 0.01)
		var r := lerpf(r0, r1, (float(i) + 0.5) / n)
		var basis := Basis(Quaternion(Vector3.UP, d / len)) * Basis.from_scale(Vector3(r, len * 1.08, r)) if vis else Basis.from_scale(Vector3.ZERO)
		mm.set_instance_transform(int(segs[i]), Transform3D(basis, (a + b) * 0.5))
	var hand: Node3D = hand_nodes[side]
	hand.position = h
	var tip: Vector3 = (pts[n] as Vector3) - (pts[n - 1] as Vector3)
	if tip.length() > 0.01:
		hand.basis = Basis(Quaternion(Vector3.DOWN, tip.normalized()))


## ふだんの姿勢：大きな腕は体の前でゆらゆら（平常時は、右手でバットをかつぐ）。小さな腕も、ゆらゆら
func pose_idle(time: float) -> void:
	for side in ["L", "R"]:
		var out := 1.0 if side == "L" else -1.0
		var ph := 0.0 if side == "L" else 1.7
		var s: Vector3 = shoulder[side]
		var rest := s + Vector3(out * (1.5 + 0.25 * sin(time * 1.3 + ph)), -3.7 + 0.3 * sin(time * 1.1 + ph), 2.0 + 0.35 * cos(time * 0.9 + ph))
		if side == "R" and form == "normal":
			# バットを肩にのせる（手は、肩の上のうしろ）
			rest = s + Vector3(-0.6 + 0.1 * sin(time * 1.2), 1.1 + 0.08 * sin(time * 1.5), -0.5)
		set_hand(side, rest)
	pose_small_arms(time)


## 小さな腕（飾り）。ふだんは、ゆらゆら。覚醒では、お酒を持って大きくゆれる
func pose_small_arms(time: float) -> void:
	var awake := form == "awake"
	for id in SMALL:
		if str(arm_forms[id]) == "awake" and not awake:
			continue
		var out := 1.0 if id.begins_with("L") else -1.0
		var idx := int(id.substr(1, 1))
		var ph := float(idx) * 1.3 + (0.0 if out > 0.0 else 2.1)
		var s: Vector3 = shoulder[id]
		var swing := 0.6 if awake else 0.25
		var target := s + Vector3(out * (0.9 + 0.35 * sin(time * 1.7 + ph) * swing / 0.25 * 0.4), -1.3 + 0.4 * sin(time * 2.0 + ph) * (swing / 0.25 * 0.5) + (1.2 if awake and idx == 2 else 0.0), 0.9 + 0.5 * cos(time * 1.4 + ph))
		set_hand(id, target)


## よろけて倒れているときの腕：だらりとたれて、ゆれる
func pose_stagger_arms(time: float) -> void:
	for id in BIG:
		var out := 1.0 if id == "L" else -1.0
		var s: Vector3 = shoulder[id]
		set_hand(id, s + Vector3(out * (2.2 + 0.4 * sin(time * 5.0)), -3.0 + 0.3 * cos(time * 4.0), 1.2))
	pose_small_arms(time * 2.0)


func hand_world(side: String) -> Vector3:
	return to_global(hand_target[side])


# ---- 1コマごとの動き ----

## 1コマの始まりに呼ぶ。1コマの長さ（秒）を教える。0 を渡すと、手はすぐ目標へ動く
func begin_frame(delta: float) -> void:
	frame_delta = delta


## すべての材質を、白く光らせる（ダメージのとき）
func set_flash(on: bool) -> void:
	for m in mats:
		var sm := m as StandardMaterial3D
		sm.emission_enabled = on
		if on:
			sm.emission = Color(1, 1, 1)
			sm.emission_energy_multiplier = 0.9


## 体の動き：息づかい、攻撃の予備動作でのかたむき、やられたときのよろけ、覚醒のしゃがみ、よろけて倒れる。
## goal_lean：かたむきの目標（x：前へ、y：横へ）。hit_now：ダメージをうけた、その瞬間なら true
func update_body(delta: float, clock: float, goal_lean: Vector2, hit_now: bool) -> void:
	_clock = clock
	if not _model_y_set:
		_model_y = position.y
		_model_y_set = true
	if hit_now:
		_flinch = float(cfg.get("flinch", 0.09))
	_flinch = move_toward(_flinch, 0.0, delta * float(cfg.get("flinch_recover", 0.5)))
	var goal_crouch := float(cfg["awake_crouch"]) if form == "awake" else 0.0
	var goal_x := goal_lean.x + (float(cfg["awake_lean"]) if form == "awake" else 0.0)
	if is_staggering():
		var sp := _stagger_pose()
		goal_x = sp.x
		goal_crouch = sp.y
		goal_lean.y = 0.0
	var rate := 1.0 - exp(-float(cfg.get("lean_rate", 8.0)) * delta)
	lean = lean.lerp(Vector2(goal_x, goal_lean.y), rate)
	crouch = lerpf(crouch, goal_crouch, 1.0 - exp(-10.0 * delta))
	var breath := sin(clock * float(cfg.get("breath_speed", 1.8)))
	rotation.x = lean.x - _flinch
	rotation.z = lean.y + float(cfg.get("sway", 0.025)) * sin(clock * 0.9)
	var drop := crouch * float(cfg["crouch_drop"])
	position.y = _model_y + float(cfg.get("bob", 0.07)) * breath - drop
	scale = Vector3.ONE * float(cfg["model_scale"]) * (1.0 + float(cfg.get("breath_scale", 0.014)) * breath)
	rig.position.y = 0.0
	legs.scale = Vector3(1.0, 1.0 - 0.18 * crouch, 1.0)
	for id in shoulder:
		var base: Vector3 = shoulder_base[id]
		shoulder[id] = Vector3(base.x, base.y - 0.3 * crouch, base.z + 0.25 * crouch)
	if head != null:
		head.rotation.x = 0.18 * crouch + (0.5 if is_staggering() and stagger_t > 1.0 and stagger_t < float(cfg["stagger_swap_sec"]) else 0.0)
	_update_tail(clock)

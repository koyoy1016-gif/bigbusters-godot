extends Node3D
## ボスの3Dモデル（部品をコードで組む）。参考画像：docs/ref/boss_oni_reference.jpg
## 平常時：紫の肌の細身の鬼。赤と黒のリーゼント、うしろへ反った角2本、とがった耳、牙の見える笑い顔。
## 紺のスカジャン（背中にトラ、白っぽい袖）を肩にはおり、袖はからっぽで垂れる。むき出しの胸に金のネックレスと南京錠。
## 紺のだぶだぶのズボン、腰の鎖、黒に白いつま先のハイカットのスニーカー。長いしっぽ（先が赤い毛）。
## 腕は大きな2本（左手でとげバットを肩にかつぐ）＋腰のうしろの小さな2本。
## 体力60%でよろけて倒れ、起き上がるとき「覚醒」：赤い肌・はちまき（酔）・はだし・腕8本・酒のびんととっくり（update_form）。
##
## 形は scripts/core/shape_kit.gd（輪切りをつないだ筒）と、基本の形（球・箱など）で作る。
## 軽くするため、組み終わったら動かない部品を親ごとに1つの形にまとめる（_bake。色は頂点の色）。
## 姿で色が変わる肌（腕・耳＝skin、胴・顔＝skin_red）だけは、材質のまま別の面にする。
## 腕の節としっぽは MultiMesh（まとめて1回で描く）。指は「開いた手」「にぎった手」を前もってまとめて、set_curl で切り替える。
## 大きな腕（L, R）は、手の先の位置（モデルの座標）に合わせて、いくつもの節をなめらかにつないだ曲線で伸び縮みする（攻撃の動きが使う）。
## モデルの原点は、足もとの床（高さ0）。向きは +Z が前（プレイヤー側）。左（L）は +X。

const StyleFx := preload("res://scripts/characters/style_fx.gd")
const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const ShapeKit := preload("res://scripts/core/shape_kit.gd")
const BigArmSegments := 10
const SmallArmSegments := 6
const TailSegments := 12
const BIG := ["L", "R"]
const SMALL := ["L2", "R2", "L3", "R3", "L4", "R4"]
const TIGER_TEX := "res://assets/textures/boss/tiger.png"
const YOI_TEX := "res://assets/textures/boss/yoi.png"
const SAKE_TEX := "res://assets/textures/boss/sake.png"

var skin: StandardMaterial3D  ## 腕・耳・しっぽ（紫。覚醒で赤紫）
var skin_red: StandardMaterial3D  ## 胴・顔（赤紫。覚醒で赤）
var mats: Array = []  ## 点滅させる材質（すべて）
var cfg: Dictionary = {}
var col: Dictionary = {}
var arm_nodes := {}  ## 腕のid → 節の番号の一覧
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
var shoes: Node3D
var feet: Node3D
var leg_skel: Skeleton3D  ## 脚の骨（もも・すね・足）
var leg_rest := {}  ## "L"/"R" → [腰, ひざ, 足首]（休みの位置）
var walk_phase := 0.0
var tail_whip := 0.0  ## しっぽをまっすぐ長くのばす具合（0〜1。しっぽ回しで使う）
var aura_particles: CPUParticles3D  ## 覚醒のオーラの粒
var aura_ground: MeshInstance3D
var aura_glow_mat: StandardMaterial3D
var follow_boost := 1.0  ## 手が目標へ近づく速さの倍率（速い振りのときに上げる）
var walk_amount := 0.0
var bat: Node3D
var awake_nodes: Array = []  ## 覚醒のときだけ出す物
var normal_nodes: Array = []  ## 平常時だけ出す物
var tail_nodes: Array = []  ## しっぽの節の番号
var held_items := {}
var head: Node3D
var _clock := 0.0
var merge_cache := {}  ## まとめた形の材質（頂点の色で描く）
var arm_mm: MultiMeshInstance3D  ## 腕の節（全部の腕を1つで描く）
var arm_seg_sleeve: Array = []  ## 節の番号 → そで（true）か肌（false）か
var arm_visible := {}
var sleeve_color := Color.WHITE
var tail_mm: MultiMeshInstance3D  ## しっぽの節
var tail_deco_mm: MultiMeshInstance3D  ## しっぽのとげと、先の毛
var tail_scales: Array = []
var hand_open := {}
var hand_fist := {}
var _band: Node3D
var _flash_on := false
var _flash_ready := false
var _sleeves: Node3D
var _bat_rest := Vector3.ZERO  ## バットを肩にかつぐときの、左手の位置（ここに近いほど、バットを肩にのせる向きにする）


static func load_config(path: String = "res://data/boss_model.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 設定は config（data/boss_model.json）から。skin_material は、肌の材質（色は姿に合わせて変える）
func build(config: Dictionary, skin_material: StandardMaterial3D) -> void:
	cfg = config
	col = cfg.get("colors", {})
	skin = skin_material
	skin.albedo_color = Color(str(cfg["skin_normal"]))
	skin_red = skin.duplicate() as StandardMaterial3D
	skin_red.albedo_color = Color(str(cfg["torso_normal"]))
	mats.append(skin)
	mats.append(skin_red)
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	legs = Node3D.new()
	legs.name = "Legs"
	add_child(legs)
	_build_legs()
	_build_torso()
	_build_jacket()
	_build_head()
	_build_tail()
	_build_arms()
	_attach_props()
	_bake()
	_build_aura()
	_apply_form("normal")
	pose_idle(0.0)


# ---- 部品づくり ----

func _c(key: String) -> Color:
	return Color(str(col.get(key, "#ff00ff")))


func _mat(color: Color, rough: float = 0.6, metal: float = 0.0, two_sided: bool = false, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	StyleFx.style_material(m)
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex != null:
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.rim_enabled = false
	StyleFx.apply_outline(m, float(StyleFx.config().get("outline_width_boss", 0.05)) * 0.5)
	mats.append(m)
	return m


func _put(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = mat
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


## 向き n（外向き）に、表を向けて置く（模様の板など）
func _put_facing(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, n: Vector3) -> MeshInstance3D:
	var mi := _put(parent, mesh, mat, pos)
	mi.basis = Basis.looking_at(-n.normalized(), Vector3.UP)
	return mi


func _sphere(r: float, segs: int = 12, rings: int = 7) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m


func _cyl(r0: float, r1: float, h: float, segs: int = 8) -> CylinderMesh:
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


func _torus(inner: float, outer: float, segs: int = 10) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segs
	m.ring_segments = 5
	return m


## 2点の間に、とがった角（つの・とげ・つめ）を置く
func _spike(parent: Node3D, base: Vector3, tip: Vector3, r: float, mat: Material, segs: int = 6) -> MeshInstance3D:
	var d := tip - base
	var len := maxf(d.length(), 0.01)
	var mi := _put(parent, _cyl(r, 0.0, len, segs), mat, (base + tip) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d / len))
	return mi


## 鎖：道（2次曲線）にそって、輪を交互に向きを変えて並べる
func _chain(parent: Node3D, a: Vector3, ctrl: Vector3, b: Vector3, links: int, size: float, mat: Material) -> void:
	var pts := ShapeKit.curve(a, ctrl, b, links)
	for i in links:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := (p1 - p0).normalized()
		var mi := _put(parent, _torus(size * 0.45, size, 8), mat, (p0 + p1) * 0.5)
		var q := Quaternion(Vector3.RIGHT, d)
		mi.basis = Basis(q) * Basis(Vector3.RIGHT, PI * 0.5 * float(i % 2))


## 脚：もも・すね・足の3つの骨（Skeleton3D）。部品は骨ごとに印（meta "bone"）を付けて組み、あとで骨についていく1つの形にまとめる（_skin_legs）。
## しゃがみ・歩きは、足首の位置を決めて、ひざの曲がりを計算で出す（_pose_legs）。脚を縮めないので、体が埋もれて見えない
func _build_legs() -> void:
	_build_leg_skeleton()
	var pants := _mat(_c("pants"))
	for sx in [-1.0, 1.0]:
		var side := "L" if sx > 0.0 else "R"
		_tag(_put(legs, ShapeKit.loft([
			[Vector3(sx * 0.30, 2.08, 0.0), 0.34, 0.34],
			[Vector3(sx * 0.36, 1.66, 0.02), 0.40, 0.40],
			[Vector3(sx * 0.42, 1.20, 0.05), 0.37, 0.38],
			[Vector3(sx * 0.43, 1.04, 0.05), 0.33, 0.34],
		], pants, 12), pants), "thigh." + side)
		_tag(_put(legs, ShapeKit.loft([
			[Vector3(sx * 0.43, 1.30, 0.06), 0.31, 0.32],
			[Vector3(sx * 0.43, 1.12, 0.05), 0.38, 0.38],
			[Vector3(sx * 0.46, 0.80, 0.02), 0.41, 0.40],
			[Vector3(sx * 0.49, 0.58, -0.02), 0.30, 0.30],
			[Vector3(sx * 0.50, 0.46, -0.04), 0.23, 0.24],
		], pants, 12), pants), "shin." + side)
	# 平常時：ハイカットのスニーカー（黒に、白いつま先と底）
	shoes = Node3D.new()
	shoes.name = "Shoes"
	legs.add_child(shoes)
	normal_nodes.append(shoes)
	var shoe := _mat(_c("shoe"))
	var white := _mat(_c("shoe_white"))
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.5
		var b := "foot." + ("L" if sx > 0.0 else "R")
		_tag(_put(shoes, ShapeKit.loft([
			[Vector3(x, 0.24, -0.30), 0.20, 0.20],
			[Vector3(x, 0.27, -0.06), 0.23, 0.24],
			[Vector3(x, 0.22, 0.24), 0.24, 0.19],
			[Vector3(x, 0.15, 0.46), 0.21, 0.13],
			[Vector3(x, 0.12, 0.58), 0.13, 0.09],
		], shoe, 10), shoe), b)
		_tag(_put(shoes, ShapeKit.loft([[Vector3(x, 0.30, -0.06), 0.22, 0.22], [Vector3(x, 0.58, -0.05), 0.25, 0.25]], shoe, 10), shoe), b)
		_tag(_put(shoes, ShapeKit.loft([
			[Vector3(x, 0.06, -0.32), 0.22, 0.07],
			[Vector3(x, 0.06, 0.30), 0.26, 0.08],
			[Vector3(x, 0.07, 0.62), 0.15, 0.06],
		], white, 10), white), b)
		_tag(_put(shoes, _sphere(1.0, 10, 6), white, Vector3(x, 0.15, 0.48), Vector3.ZERO, Vector3(0.21, 0.11, 0.14)), b)
		for k in 3:
			_tag(_put(shoes, _box(0.24, 0.035, 0.05), white, Vector3(x, 0.46 - 0.06 * k, 0.08 + 0.12 * k), Vector3(-35.0, 0.0, 0.0)), b)
	# 覚醒：はだし（つめのある足）
	feet = Node3D.new()
	feet.name = "Feet"
	legs.add_child(feet)
	awake_nodes.append(feet)
	var claw := _mat(_c("claw"), 0.4)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.5
		var b := "foot." + ("L" if sx > 0.0 else "R")
		_tag(_put(feet, ShapeKit.loft([
			[Vector3(x, 0.22, -0.26), 0.17, 0.18],
			[Vector3(x, 0.18, 0.05), 0.21, 0.15],
			[Vector3(x, 0.10, 0.40), 0.22, 0.09],
			[Vector3(x, 0.08, 0.52), 0.16, 0.06],
		], skin, 10), skin), b)
		_tag(_put(feet, ShapeKit.loft([[Vector3(x, 0.20, -0.06), 0.19, 0.19], [Vector3(x, 0.52, -0.05), 0.22, 0.22]], skin, 10), skin), b)
		for k in 4:
			var tx: float = x + (float(k) - 1.5) * 0.1
			_tag(_spike(feet, Vector3(tx, 0.08, 0.5), Vector3(tx + (float(k) - 1.5) * 0.04, 0.02, 0.7), 0.035, claw, 5), b)


## 覚醒のオーラ：体のまわりから、赤紫の炎のような粒が立ちのぼる＋足もとの光の輪。粒は1回で描く（CPUParticles3D）
func _build_aura() -> void:
	var a: Dictionary = cfg.get("aura", {})
	var aura := Node3D.new()
	aura.name = "Aura"
	add_child(aura)
	awake_nodes.append(aura)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 粒の形：まん中が明るく、ふちが消える、やわらかい丸（小さな画像をその場で作る）
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	soft.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = soft
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.95, 1.5)
	quad.material = mat
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.mesh = quad
	p.amount = int(a.get("amount", 26))
	p.lifetime = float(a.get("lifetime", 1.1))
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 2.6
	p.emission_ring_radius = float(a.get("radius", 1.5))
	p.emission_ring_inner_radius = float(a.get("radius", 1.5)) * 0.55
	p.position = Vector3(0, 1.6, 0)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(str(a.get("color_start", "#ff5a3c")), 0.0))
	grad.add_point(0.15, Color(str(a.get("color_start", "#ff5a3c")), 1.0))
	grad.add_point(0.6, Color(str(a.get("color_mid", "#c83cff")), 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(str(a.get("color_end", "#5a1e8c")), 0.0))
	p.color_ramp = grad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.add_child(p)
	aura_particles = p
	# 足もとの光の輪
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_color = Color(str(a.get("ground_color", "#ff3c6e")), 0.35)
	var disc := CylinderMesh.new()
	disc.top_radius = float(a.get("radius", 1.5)) * 1.5
	disc.bottom_radius = disc.top_radius
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	disc.material = gmat
	aura_ground = MeshInstance3D.new()
	aura_ground.name = "Glow"
	aura_ground.mesh = disc
	aura_ground.position = Vector3(0, 0.05, 0)
	aura_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.add_child(aura_ground)
	aura_glow_mat = gmat


## オーラのゆらめき（毎コマ）。足もとの輪が、脈を打つように明るくなる
func _update_aura(clock: float) -> void:
	if aura_glow_mat == null or form != "awake":
		return
	var pulse := 0.5 + 0.5 * sin(clock * 5.0)
	aura_glow_mat.albedo_color.a = 0.22 + 0.25 * pulse
	aura_ground.scale = Vector3.ONE * (1.0 + 0.12 * pulse)


func _tag(mi: MeshInstance3D, bone: String) -> MeshInstance3D:
	mi.set_meta("bone", bone)
	return mi


## 脚の骨。もも（腰の関節）→すね（ひざ）→足（足首）。位置は data/boss_model.json の leg_joints
func _build_leg_skeleton() -> void:
	leg_skel = Skeleton3D.new()
	leg_skel.name = "LegSkeleton"
	add_child(leg_skel)
	var j: Dictionary = cfg.get("leg_joints", {"hip": [0.30, 2.08, 0.0], "knee": [0.43, 1.18, 0.05], "ankle": [0.50, 0.46, -0.04]})
	var root := leg_skel.add_bone("root")
	leg_skel.set_bone_rest(root, Transform3D.IDENTITY)
	for sx in [-1.0, 1.0]:
		var side := "L" if sx > 0.0 else "R"
		var hip := _jv(j["hip"], sx)
		var knee := _jv(j["knee"], sx)
		var ankle := _jv(j["ankle"], sx)
		leg_rest[side] = [hip, knee, ankle]
		var t := leg_skel.add_bone("thigh." + side)
		leg_skel.set_bone_parent(t, root)
		leg_skel.set_bone_rest(t, Transform3D(Basis.IDENTITY, hip))
		var sh := leg_skel.add_bone("shin." + side)
		leg_skel.set_bone_parent(sh, t)
		leg_skel.set_bone_rest(sh, Transform3D(Basis.IDENTITY, knee - hip))
		var f := leg_skel.add_bone("foot." + side)
		leg_skel.set_bone_parent(f, sh)
		leg_skel.set_bone_rest(f, Transform3D(Basis.IDENTITY, ankle - knee))
	leg_skel.reset_bone_poses()


static func _jv(a: Array, sx: float) -> Vector3:
	return Vector3(float(a[0]) * sx, float(a[1]), float(a[2]))


## 脚の部品を、骨についていく形にまとめる（ズボン／くつ／はだしの足、それぞれ1つ）
func _skin_legs() -> void:
	for container in [legs, shoes, feet]:
		var parts: Array = []
		var skin_res := Skin.new()
		var bind_of := {}
		var skip: Array = [shoes, feet] if container == legs else []
		for c in (container as Node3D).get_children():
			if not (c is MeshInstance3D) or skip.has(c):
				continue
			var bone := str(c.get_meta("bone", "root"))
			var bi := leg_skel.find_bone(bone)
			if not bind_of.has(bi):
				bind_of[bi] = skin_res.get_bind_count()
				skin_res.add_named_bind(bone, leg_skel.get_bone_global_rest(bi).affine_inverse())
			parts.append({"mesh": (c as MeshInstance3D).mesh, "xf": (c as Node3D).transform, "bone": bind_of[bi], "node": c})
		if parts.is_empty():
			continue
		var mesh := MeshMerge.merge_parts(parts, [skin, skin_red], merge_cache)
		for p in parts:
			var n: Node = p["node"]
			container.remove_child(n)
			n.free()
		var mi := MeshInstance3D.new()
		mi.name = "Skinned"
		mi.mesh = mesh
		container.add_child(mi)
		mi.skin = skin_res
		mi.skeleton = mi.get_path_to(leg_skel)


## 2つの骨（長さ l1・l2）を、根元 a から先 c へ届くように曲げる。曲がる向きは pole。ひざの位置を返す
static func solve_two_bone(a: Vector3, c: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := c - a
	var dist := clampf(d.length(), 0.001, l1 + l2 - 0.001)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var p := pole - dir * pole.dot(dir)
	p = p.normalized() if p.length() > 0.0001 else Vector3.FORWARD
	return a + dir * l1 * cos_a + p * l1 * sqrt(1.0 - cos_a * cos_a)


## 骨の向き：休みの向き rest_dir（曲がる向き rest_pole）を、新しい向き new_dir（曲がる向き pole）へ回す
static func _aim_basis(rest_dir: Vector3, rest_pole: Vector3, new_dir: Vector3, pole: Vector3) -> Basis:
	var f0 := _frame(rest_dir, rest_pole)
	var f1 := _frame(new_dir, pole)
	return f1 * f0.transposed()


static func _frame(y: Vector3, z_hint: Vector3) -> Basis:
	var yy := y.normalized()
	var zz := (z_hint - yy * z_hint.dot(yy))
	zz = zz.normalized() if zz.length() > 0.0001 else Vector3(0, 0, 1)
	var xx := yy.cross(zz).normalized()
	return Basis(xx, yy, zz)


## 足首の位置（モデルの座標）を決めて、脚の骨を曲げる。hip_drop：腰がどれだけ下がったか
func _pose_legs(hip_drop: float, fwd: float) -> void:
	if leg_skel == null:
		return
	var c := crouch
	var splay := float(cfg.get("crouch_splay", 0.32)) * c
	for sx in [-1.0, 1.0]:
		var side := "L" if sx > 0.0 else "R"
		var r: Array = leg_rest[side]
		var hip_r: Vector3 = r[0]
		var knee_r: Vector3 = r[1]
		var ankle_r: Vector3 = r[2]
		var hip := hip_r + Vector3(0.0, -hip_drop, fwd)
		# 歩き：片足ずつ前へ（上げながら）出し、うしろへ送る
		var ph := walk_phase + (0.0 if sx > 0.0 else PI)
		var stride := float(cfg.get("walk_stride", 0.42)) * walk_amount
		var lift := float(cfg.get("walk_lift", 0.28)) * walk_amount
		var ankle := ankle_r + Vector3(sx * splay, lift * maxf(0.0, cos(ph)), stride * sin(ph) + 0.06 * c)
		var pole := Vector3(sx * (0.15 + 0.9 * c), 0.0, 1.0).normalized()
		var l1 := (knee_r - hip_r).length()
		var l2 := (ankle_r - knee_r).length()
		var knee := solve_two_bone(hip, ankle, l1, l2, pole)
		var rest_pole := Vector3(0, 0, 1)
		var b1 := _aim_basis(knee_r - hip_r, rest_pole, knee - hip, pole)
		var b2 := _aim_basis(ankle_r - knee_r, rest_pole, ankle - knee, pole)
		# 足は床と平らに（つま先は少し外へ）。歩きで、けり出すときにかかとが少し上がる
		var toe_out := Basis(Vector3.UP, sx * 0.35 * c)
		var heel := Basis(Vector3.RIGHT, 0.35 * walk_amount * maxf(0.0, -sin(ph)) * maxf(0.0, cos(ph + 0.6)))
		var bf := toe_out * heel
		var g_thigh := Transform3D(b1, hip)
		var g_shin := Transform3D(b2, knee)
		var g_foot := Transform3D(bf, ankle)
		_set_bone("thigh." + side, g_thigh)
		_set_bone("shin." + side, g_thigh.affine_inverse() * g_shin)
		_set_bone("foot." + side, g_shin.affine_inverse() * g_foot)


func _set_bone(bone: String, local: Transform3D) -> void:
	var i := leg_skel.find_bone(bone)
	leg_skel.set_bone_pose_position(i, local.origin)
	leg_skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


## 歩きの進み。phase：足の運びの角度（ラジアン、増え続けてよい）。amount：歩きの強さ（0＝立ち止まり〜1）
func set_walk(phase: float, amount: float) -> void:
	walk_phase = phase
	walk_amount = clampf(amount, 0.0, 1.0)


func _build_torso() -> void:
	var pants := _mat(_c("pants"))
	var belt := _mat(_c("belt"))
	var stud := _mat(_c("stud"), 0.3, 0.6)
	var gold := _mat(_c("gold"), 0.3, 0.7)
	# 腰（ズボンの上）とベルト
	_put(rig, ShapeKit.loft([[Vector3(0, 1.86, 0), 0.55, 0.38], [Vector3(0, 2.06, 0), 0.62, 0.42], [Vector3(0, 2.3, 0), 0.5, 0.36]], pants, 14), pants)
	_put(rig, ShapeKit.loft([[Vector3(0, 2.15, 0), 0.535, 0.385], [Vector3(0, 2.3, 0), 0.52, 0.375]], belt, 16), belt)
	_put(rig, _box(0.16, 0.12, 0.05), stud, Vector3(0, 2.225, 0.39))
	for k in 8:
		var a := PI * 0.5 + (float(k) - 3.5) * 0.32
		_put(rig, _sphere(0.025, 6, 4), stud, Vector3(cos(a) * 0.54, 2.225, sin(a) * 0.39))
	# 腰の鎖（左の前からうしろへ、たれる）
	_chain(rig, Vector3(0.42, 2.2, 0.27), Vector3(0.72, 1.45, 0.2), Vector3(0.5, 2.15, -0.26), 12, 0.05, gold)
	# 胴（はだか。赤紫）：細い腰から、広い胸へ
	_put(rig, ShapeKit.loft([
		[Vector3(0, 2.2, 0.02), 0.42, 0.28],
		[Vector3(0, 2.5, 0.04), 0.44, 0.3],
		[Vector3(0, 2.86, 0.05), 0.55, 0.34],
		[Vector3(0, 3.16, 0.03), 0.64, 0.36],
		[Vector3(0, 3.34, 0.0), 0.56, 0.32],
		[Vector3(0, 3.46, -0.02), 0.3, 0.22],
	], skin_red, 14), skin_red)
	for sx in [-1.0, 1.0]:
		_put(rig, _sphere(1.0, 10, 6), skin_red, Vector3(sx * 0.22, 3.04, 0.3), Vector3.ZERO, Vector3(0.24, 0.15, 0.12))
	# 腹筋のすじ（少し暗い線）
	var line := _mat(Color(str(cfg["torso_normal"])).darkened(0.35))
	_put(rig, _box(0.02, 0.5, 0.03), line, Vector3(0, 2.62, 0.345), Vector3(-6.0, 0, 0))
	for k in 2:
		_put(rig, _box(0.3, 0.02, 0.03), line, Vector3(0, 2.5 + 0.18 * k, 0.345 + 0.02 * k))
	# 肩（紫。腕のつけ根）
	for sx in [-1.0, 1.0]:
		var sh: Array = cfg["arm_shoulder"]
		_put(rig, _sphere(0.22, 10, 6), skin, Vector3(sx * float(sh[0]) * 0.92, float(sh[1]), float(sh[2])))
	# 首
	_put(rig, ShapeKit.loft([[Vector3(0, 3.4, -0.02), 0.17, 0.16], [Vector3(0, 3.74, 0.02), 0.15, 0.15]], skin_red, 10), skin_red)
	# 金のネックレス2本（首のうしろから、胸の上に垂れる）と、南京錠
	for k in 2:
		var low := 2.75 - 0.35 * float(k)
		var fwd := 0.85 + 0.1 * float(k)
		_put(rig, ShapeKit.tube(ShapeKit.curve(Vector3(0.2, 3.47, -0.03), Vector3(0, low, fwd), Vector3(-0.2, 3.47, -0.03), 12), 0.022, 0.022, gold, 5), gold)
	_put(rig, _box(0.12, 0.13, 0.05), gold, Vector3(0, 2.86, 0.47))
	_put(rig, _torus(0.03, 0.05, 8), gold, Vector3(0, 2.95, 0.47), Vector3(90.0, 0, 0))


func _build_jacket() -> void:
	var navy := _mat(_c("jacket"), 0.7, 0.0, true)
	var back := _mat(_c("jacket_back"), 0.7, 0.0, true)
	var sleeve := _mat(_c("sleeve"))
	var red := _mat(_c("rib_red"), 0.7, 0.0, true)
	var white := _mat(_c("rib_white"), 0.7, 0.0, true)
	var gap := 0.62  # 前の開き（ラジアン）
	var a0 := PI * 0.5 + gap
	var a1 := PI * 0.5 - gap + TAU
	# 胴の部分（前が開いている）。前の身ごろは紺、背中は黒
	var body := [
		[Vector3(0, 2.2, 0), 0.6, 0.44],
		[Vector3(0, 2.6, -0.01), 0.62, 0.44],
		[Vector3(0, 3.0, -0.02), 0.72, 0.46],
		[Vector3(0, 3.3, -0.03), 0.79, 0.46],
		[Vector3(0, 3.48, -0.04), 0.42, 0.32],
	]
	# 角度：PI/2 が前、3PI/2 が背中。前の開きの右はしから、横・背中・横をまわって、左はしまで
	var b0 := PI + 0.55
	var b1 := TAU - 0.55
	_put(rig, ShapeKit.loft(body, navy, 6, Vector3.RIGHT, a0, b0, false), navy)
	_put(rig, ShapeKit.loft(body, back, 10, Vector3.RIGHT, b0, b1, false), back)
	_put(rig, ShapeKit.loft(body, navy, 6, Vector3.RIGHT, b1, a1, false), navy)
	# すそのリブ（赤・白・赤のしま）と、えり
	var hem := [[0.0, red], [0.04, white], [0.08, red]]
	for h in hem:
		var y: float = 2.12 + float(h[0])
		_put(rig, ShapeKit.loft([[Vector3(0, y, 0), 0.61, 0.45], [Vector3(0, y + 0.045, 0), 0.61, 0.45]], h[1], 18, Vector3.RIGHT, a0, a1, false), h[1])
	_put(rig, ShapeKit.loft([[Vector3(0, 3.44, -0.03), 0.45, 0.35], [Vector3(0, 3.58, -0.04), 0.36, 0.28]], red, 14, Vector3.RIGHT, a0, a1, false), red)
	# 背中のトラ、胸の小さなトラ
	var tiger := _mat(Color.WHITE, 0.7, 0.0, false, load(TIGER_TEX) as Texture2D)
	_put_facing(rig, ShapeKit.plate(Vector2(0.78, 0.78), tiger), tiger, Vector3(0, 2.88, -0.475), Vector3.FORWARD)
	for sx in [-1.0, 1.0]:
		var a: float = PI * 0.5 + sx * (gap + 0.22)
		var n := Vector3(cos(a), 0, sin(a))
		_put_facing(rig, ShapeKit.plate(Vector2(0.2, 0.2), tiger), tiger, Vector3(cos(a) * 0.735, 3.02, sin(a) * 0.475) + n * 0.01, n)
	# 肩にはおった袖（平常時だけ。からっぽで、うしろに垂れる。白っぽい袖に、紺と赤のそで口）。覚醒では、上の腕が袖を着る
	var cuff_navy := _mat(_c("jacket"))
	var cuff_red := _mat(_c("rib_red"))
	var sleeves := Node3D.new()
	sleeves.name = "Sleeves"
	rig.add_child(sleeves)
	normal_nodes.append(sleeves)
	_sleeves = sleeves
	sleeve_color = sleeve.albedo_color
	for sx in [-1.0, 1.0]:
		var top := Vector3(sx * 0.8, 3.3, -0.1)
		_put(sleeves, _sphere(1.0, 10, 6), sleeve, top + Vector3(0, 0, -0.04), Vector3.ZERO, Vector3(0.23, 0.19, 0.23))
		var pts := ShapeKit.curve(top, Vector3(sx * 1.04, 2.7, -0.26), Vector3(sx * 0.94, 1.92, -0.22), 6)
		var rings: Array = []
		for i in pts.size():
			rings.append([pts[i], lerpf(0.22, 0.16, float(i) / 6.0), lerpf(0.2, 0.15, float(i) / 6.0)])
		_put(sleeves, ShapeKit.loft(rings, sleeve, 10), sleeve)
		var end: Vector3 = pts[pts.size() - 1]
		var dir: Vector3 = (end - (pts[pts.size() - 2] as Vector3)).normalized()
		_put(sleeves, ShapeKit.loft([[end - dir * 0.02, 0.165, 0.155], [end + dir * 0.06, 0.16, 0.15]], cuff_red, 10), cuff_red)
		_put(sleeves, ShapeKit.loft([[end + dir * 0.06, 0.16, 0.15], [end + dir * 0.14, 0.15, 0.14]], cuff_navy, 10), cuff_navy)


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	var hp: Array = cfg["head_pos"]
	head.position = Vector3(float(hp[0]), float(hp[1]), float(hp[2]))
	head.scale = Vector3.ONE * float(cfg.get("head_scale", 1.0))
	rig.add_child(head)
	var hair := _mat(_c("hair"))
	var hair_dark := _mat(_c("hair_dark"))
	var horn := _mat(_c("horn"), 0.4)
	var eye := _mat(_c("eye"), 0.3)
	var pupil := _mat(_c("pupil"))
	var tooth := _mat(_c("tooth"))
	var mouth := _mat(_c("mouth"))
	# 頭（あごは細め）
	_put(head, ShapeKit.loft([
		[Vector3(0, -0.25, 0.07), 0.1, 0.1],
		[Vector3(0, -0.16, 0.05), 0.21, 0.22],
		[Vector3(0, 0.0, 0.0), 0.27, 0.28],
		[Vector3(0, 0.14, -0.01), 0.26, 0.27],
		[Vector3(0, 0.26, -0.02), 0.18, 0.2],
		[Vector3(0, 0.32, -0.03), 0.06, 0.07],
	], skin_red, 14), skin_red)
	# 目（黄色・つり目）、まゆ（怒り）、鼻、笑った口と牙
	for sx in [-1.0, 1.0]:
		_put(head, _sphere(1.0, 10, 6), eye, Vector3(sx * 0.11, 0.04, 0.24), Vector3(0, 0, sx * 14.0), Vector3(0.085, 0.045, 0.04))
		_put(head, _sphere(0.024, 6, 4), pupil, Vector3(sx * 0.115, 0.04, 0.275))
		_put(head, _box(0.15, 0.035, 0.05), hair_dark, Vector3(sx * 0.11, 0.105, 0.25), Vector3(0, 0, sx * 20.0))
	_spike(head, Vector3(0, -0.01, 0.25), Vector3(0, -0.04, 0.34), 0.04, skin_red, 6)
	_put(head, _box(0.27, 0.075, 0.05), mouth, Vector3(0, -0.12, 0.225))
	_put(head, _box(0.24, 0.045, 0.05), tooth, Vector3(0, -0.112, 0.24))
	for sx in [-1.0, 1.0]:
		_put(head, _box(0.08, 0.04, 0.05), mouth, Vector3(sx * 0.15, -0.09, 0.2), Vector3(0, sx * -20.0, sx * 28.0))
		_spike(head, Vector3(sx * 0.07, -0.125, 0.255), Vector3(sx * 0.065, -0.2, 0.255), 0.022, tooth, 5)
	# とがった耳（紫）
	for sx in [-1.0, 1.0]:
		_put(head, ShapeKit.tube([Vector3(sx * 0.24, 0.02, -0.02), Vector3(sx * 0.36, 0.08, -0.05), Vector3(sx * 0.48, 0.16, -0.1)], 0.075, 0.004, skin, 6, 0.45), skin)
	# リーゼント（赤い大きな前髪が、上へ盛り上がって、うしろへ流れる。黒いすじ入り）
	# うしろ頭と横は黒っぽい地毛、上に赤い大きな前髪
	_put(head, _sphere(1.0, 12, 7), hair_dark, Vector3(0, 0.1, -0.07), Vector3.ZERO, Vector3(0.28, 0.24, 0.28))
	var path := ShapeKit.curve(Vector3(0, 0.18, 0.2), Vector3(0, 0.74, 0.4), Vector3(0, 0.34, -0.58), 10)
	var rings: Array = []
	for i in path.size():
		var k := float(i) / 10.0
		rings.append([path[i], 0.14 + 0.13 * sin(k * PI * 0.8), 0.07 + 0.11 * sin(k * PI)])
	_put(head, ShapeKit.loft(rings, hair, 12), hair)
	for sx in [-1.0, 1.0]:
		var side_path := ShapeKit.curve(Vector3(sx * 0.17, 0.2, 0.08), Vector3(sx * 0.26, 0.42, 0.08), Vector3(sx * 0.2, 0.34, -0.32), 6)
		var side_rings: Array = []
		for i in side_path.size():
			side_rings.append([side_path[i], 0.07 + 0.05 * sin(float(i) / 6.0 * PI), 0.06 + 0.06 * sin(float(i) / 6.0 * PI)])
		_put(head, ShapeKit.loft(side_rings, hair, 8), hair)
	var path2 := ShapeKit.curve(Vector3(-0.1, 0.3, 0.2), Vector3(-0.14, 0.66, 0.3), Vector3(-0.12, 0.36, -0.5), 7)
	var rings2: Array = []
	for i in path2.size():
		rings2.append([path2[i], 0.07, 0.07 + 0.04 * sin(float(i) / 7.0 * PI)])
	_put(head, ShapeKit.loft(rings2, hair_dark, 8), hair_dark)
	for sx in [-1.0, 0.0, 1.0]:
		_spike(head, Vector3(sx * 0.13, 0.2, -0.22), Vector3(sx * 0.2, -0.02, -0.46), 0.09, hair if sx != 0.0 else hair_dark, 6)
	for sx in [-1.0, 1.0]:
		_spike(head, Vector3(sx * 0.24, 0.12, -0.02), Vector3(sx * 0.27, -0.1, 0.02), 0.06, hair_dark, 5)
	# 角（こめかみから、上へ、うしろへ反る）
	for sx in [-1.0, 1.0]:
		_put(head, ShapeKit.tube(ShapeKit.curve(Vector3(sx * 0.16, 0.2, 0.02), Vector3(sx * 0.44, 0.44, 0.02), Vector3(sx * 0.36, 0.68, -0.32), 8), 0.105, 0.008, horn, 8), horn)
	# はちまき（覚醒のときだけ）：白い布と、前の「酔」、うしろの結び目
	var band := _mat(_c("band"))
	_band = Node3D.new()
	_band.name = "Band"
	head.add_child(_band)
	_put(_band, ShapeKit.loft([[Vector3(0, 0.07, -0.01), 0.29, 0.3], [Vector3(0, 0.17, -0.01), 0.285, 0.295]], band, 16, Vector3.RIGHT, 0.0, TAU, false), band)
	var yoi := _mat(Color.WHITE, 0.8, 0.0, false, load(YOI_TEX) as Texture2D)
	_put_facing(_band, ShapeKit.plate(Vector2(0.15, 0.15), yoi), yoi, Vector3(0, 0.12, 0.302), Vector3.BACK)
	for sx in [-1.0, 1.0]:
		_put(_band, ShapeKit.tube([Vector3(0, 0.12, -0.29), Vector3(sx * 0.1, 0.05, -0.42), Vector3(sx * 0.16, -0.12, -0.48)], 0.05, 0.03, band, 6, 0.35), band)
	awake_nodes.append(_band)


func _build_tail() -> void:
	var r: Array = cfg["tail_radius"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 2.0
	cap.radial_segments = 8
	cap.rings = 2
	mm.mesh = cap
	mm.instance_count = TailSegments
	for i in TailSegments:
		tail_nodes.append(i)
		tail_scales.append(lerpf(float(r[0]), float(r[1]), float(i) / float(TailSegments - 1)))
	tail_mm = MultiMeshInstance3D.new()
	tail_mm.name = "Tail"
	tail_mm.multimesh = mm
	tail_mm.material_override = MeshMerge.vc_material(skin, merge_cache)
	add_child(tail_mm)
	# とげ（節ごとに1つ）と、先の赤い毛（5本）
	var deco := MultiMesh.new()
	deco.transform_format = MultiMesh.TRANSFORM_3D
	deco.use_colors = true
	deco.mesh = _cyl(1.0, 0.0, 1.0, 5)
	deco.instance_count = TailSegments + 5
	for i in deco.instance_count:
		deco.set_instance_color(i, _c("spine") if i < TailSegments else _c("tuft"))
	tail_deco_mm = MultiMeshInstance3D.new()
	tail_deco_mm.name = "TailDeco"
	tail_deco_mm.multimesh = deco
	tail_deco_mm.material_override = MeshMerge.vc_material(_mat(_c("tuft")), merge_cache)
	add_child(tail_deco_mm)
	_refresh_tail_colors()
	_update_tail(0.0)


func _refresh_tail_colors() -> void:
	for i in TailSegments:
		tail_mm.multimesh.set_instance_color(i, skin.albedo_color)


## しっぽの道：腰のうしろから、下へ・うしろへ垂れて、先が横に巻き上がる（k は 0〜1）
func _tail_point(k: float, clock: float) -> Vector3:
	var b: Array = cfg["tail_base"]
	var base := Vector3(float(b[0]), float(b[1]) - float(cfg.get("hip_y", 2.08)) * float(cfg["crouch_drop"]) * crouch, float(b[2]))
	var sway := sin(clock * 1.6 - k * 2.4) * 0.35 * k
	var rest := base + Vector3(1.5 * k * k + sway, -2.3 * k + 1.4 * k * k + 0.3 * crouch * k, -0.95 * sin(k * PI * 0.8))
	if tail_whip <= 0.0:
		return rest
	# しっぽ回し：うしろへ、ひざくらいの高さで、まっすぐ長くのばす
	var whip := base + Vector3(0.25 * k * sin(clock * 9.0), -1.1 * k + 0.25 * k * k, -float(cfg.get("tail_whip_len", 3.4)) * k)
	return rest.lerp(whip, tail_whip)


func _update_tail(clock: float) -> void:
	if tail_mm == null:
		return
	var mm := tail_mm.multimesh
	var deco := tail_deco_mm.multimesh
	var n := TailSegments
	for i in n:
		var a := _tail_point(float(i) / float(n), clock)
		var b := _tail_point(float(i + 1) / float(n), clock)
		var d := b - a
		var len := maxf(d.length(), 0.01)
		var rr := float(tail_scales[i])
		var q := Quaternion(Vector3.UP, d / len)
		mm.set_instance_transform(i, Transform3D(Basis(q) * Basis.from_scale(Vector3(rr * 2.0, (len + rr * 2.0) * 0.5, rr * 2.0)), (a + b) * 0.5))
		# とげ：節の上側（体から外向き）に立てる
		var up := (Vector3.UP - (d / len) * Vector3.UP.dot(d / len)).normalized()
		var h := rr * 1.3
		deco.set_instance_transform(i, Transform3D(Basis(Quaternion(Vector3.UP, up)) * Basis.from_scale(Vector3(rr * 0.45, h, rr * 0.45)), (a + b) * 0.5 + up * (rr + h * 0.4)))
	# 先の毛：先から、扇のように広がる
	var tip := _tail_point(1.0, clock)
	var dir := (tip - _tail_point(0.92, clock)).normalized()
	for k in 5:
		var spread := (float(k) - 2.0) * 0.32
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var d2 := (dir + side * spread + Vector3.UP * 0.25 * cos(float(k))).normalized()
		var h2 := 0.45
		deco.set_instance_transform(TailSegments + k, Transform3D(Basis(Quaternion(Vector3.UP, d2)) * Basis.from_scale(Vector3(0.09, h2, 0.09)), tip + d2 * h2 * 0.5))


# ---- 腕 ----

func _build_arms() -> void:
	var sh: Array = cfg["arm_shoulder"]
	var sm: Array = cfg["small_arm_shoulders"]
	var big_r := float(cfg["arm_radius"])
	var big_l := float(cfg["arm_length"])
	var sr := float(cfg["small_arm_radius"])
	var sl := float(cfg["small_arm_length"])
	var defs := {
		"L": [Vector3(float(sh[0]), float(sh[1]), float(sh[2])), big_r, big_l, ""],
		"R": [Vector3(-float(sh[0]), float(sh[1]), float(sh[2])), big_r, big_l, ""],
	}
	for k in 3:
		var p: Array = sm[k]
		var f := "" if k == 0 else "awake"
		defs["L" + str(k + 2)] = [Vector3(float(p[0]), float(p[1]), float(p[2])), sr, sl, f]
		defs["R" + str(k + 2)] = [Vector3(-float(p[0]), float(p[1]), float(p[2])), sr, sl, f]
	var claw := _mat(_c("claw"), 0.4)
	var cuff := _mat(_c("cuff"), 0.5)
	var stud := _mat(_c("stud"), 0.3, 0.6)
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
			arm_seg_sleeve.append(big and i < 6)  # 覚醒のとき、上の腕の付け根から6節は袖
		var hand := Node3D.new()
		add_child(hand)
		hand_nodes[id] = hand
		var hr := float(cfg["hand_radius"]) * (1.0 if big else 0.75)
		# 手首の黒い腕輪（小さな腕は、とげ付き）
		_put(hand, _torus(hr * 0.5, hr * 0.78, 12), cuff, Vector3(0, hr * 0.85, 0))
		if not big:
			for k in 5:
				var a := float(k) * TAU / 5.0
				_spike(hand, Vector3(cos(a) * hr * 0.75, hr * 0.85, sin(a) * hr * 0.75), Vector3(cos(a) * hr * 1.05, hr * 0.85, sin(a) * hr * 1.05), hr * 0.1, stud, 4)
		var palm := _put(hand, _sphere(hr, 10, 6), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.1, 0.55))
		palm.set_meta("finger", true)
		finger_pivots[id] = []
		for k in 5:
			var thumb := k == 4
			var a := (float(k) - 1.5) * 0.38 if not thumb else 0.0
			var base := Vector3(sin(a) * hr * 0.85, -hr * 0.8, 0.0) if not thumb else Vector3(hr * 0.85, -hr * 0.15, 0.1 * hr)
			var len1 := hr * (0.75 if not thumb else 0.55)
			var len2 := hr * 0.6
			var rad := hr * (0.17 if not thumb else 0.2)
			var p1 := Node3D.new()
			p1.set_meta("finger", true)
			p1.position = base
			p1.rotation = Vector3(0, 0, 1.0) if thumb else Vector3(0, 0, -a * 0.6)
			hand.add_child(p1)
			p1.add_child(_finger_seg(rad, len1))
			var p2 := Node3D.new()
			p2.position = Vector3(0, -len1, 0)
			p1.add_child(p2)
			p2.add_child(_finger_seg(rad * 0.85, len2))
			# 長いつめ
			_spike(p2, Vector3(0, -len2 - rad * 0.3, 0), Vector3(0, -len2 - rad - hr * 0.55, hr * 0.08), rad * 0.75, claw, 5)
			(finger_pivots[id] as Array).append([p1, p2])
	# 腕の節：全部の腕を、1つの MultiMesh で描く（形は作り直さず、節ごとの変形だけ変える）
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var unit := CapsuleMesh.new()
	unit.radius = 0.5
	unit.height = 2.0
	unit.radial_segments = 10
	unit.rings = 2
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
	var awake := form == "awake"
	for i in arm_seg_sleeve.size():
		arm_mm.multimesh.set_instance_color(i, sleeve_color if (awake and arm_seg_sleeve[i]) else skin.albedo_color)


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


## 手に持つ物：平常時はとげバット（左手）、覚醒は酒のびん・とっくり
func _attach_props() -> void:
	var steel := _mat(_c("bat"), 0.35, 0.7)
	var spike := _mat(_c("spike"), 0.3, 0.7)
	var grip := _mat(_c("grip"))
	var gold := _mat(_c("gold"), 0.3, 0.7)
	bat = Node3D.new()
	bat.name = "Bat"
	(hand_nodes["L"] as Node3D).add_child(bat)
	_put(bat, ShapeKit.loft([
		[Vector3(0, -0.2, 0), 0.075, 0.075],
		[Vector3(0, -0.12, 0), 0.07, 0.07],
		[Vector3(0, -0.06, 0), 0.05, 0.05],
		[Vector3(0, 0.7, 0), 0.06, 0.06],
		[Vector3(0, 1.5, 0), 0.12, 0.12],
		[Vector3(0, 2.2, 0), 0.14, 0.14],
		[Vector3(0, 2.3, 0), 0.11, 0.11],
	], steel, 10), steel)
	_put(bat, ShapeKit.loft([[Vector3(0, -0.06, 0), 0.058, 0.058], [Vector3(0, 0.55, 0), 0.064, 0.064]], grip, 10), grip)
	for k in 16:
		var a := float(k) * 2.4
		var y := 1.3 + 0.9 * float(k) / 15.0
		var r := lerpf(0.11, 0.14, (y - 1.3) / 0.9)
		var o := Vector3(cos(a), 0, sin(a))
		_spike(bat, Vector3(0, y, 0) + o * r * 0.9, Vector3(0, y, 0) + o * (r + 0.13), 0.035, spike, 5)
	for k in 3:
		_put(bat, _torus(0.12, 0.15, 10), gold, Vector3(0, 1.85 + 0.06 * k, 0), Vector3(20.0 + 15.0 * k, 0, 10.0))
	_put(bat, _box(0.1, 0.11, 0.05), gold, Vector3(0.16, 1.7, 0))
	bat.position = Vector3(0, -0.12, 0.0)
	normal_nodes.append(bat)
	# 酒：大きな腕は一升瓶、小さな腕はとっくりと一升瓶をかわりばんこに
	var glass := _mat(_c("bottle"), 0.2)
	var jug := _mat(_c("jug"), 0.5)
	var rope := _mat(_c("rope"))
	var label := _mat(Color.WHITE, 0.8, 0.0, false, load(SAKE_TEX) as Texture2D)
	var i := 0
	for id in ["L", "R", "L2", "R2", "L3", "R3", "L4", "R4"]:
		var item := Node3D.new()
		item.name = "Drink"
		(hand_nodes[id] as Node3D).add_child(item)
		var s := 1.0 if BIG.has(id) else 0.8
		if i % 3 == 1:
			_put(item, _sphere(0.3 * s, 10, 6), jug, Vector3(0, -0.42 * s, 0.12 * s), Vector3.ZERO, Vector3(1.0, 1.15, 1.0))
			_put(item, _cyl(0.09 * s, 0.07 * s, 0.24 * s, 8), jug, Vector3(0, -0.06 * s, 0.12 * s))
			_put(item, _torus(0.07 * s, 0.1 * s, 8), rope, Vector3(0, -0.14 * s, 0.12 * s))
			_put_facing(item, ShapeKit.plate(Vector2(0.24, 0.24) * s, label), label, Vector3(0, -0.42 * s, 0.12 * s + 0.31 * s), Vector3.BACK)
		else:
			_put(item, _cyl(0.13 * s, 0.13 * s, 0.6 * s, 10), glass, Vector3(0, -0.5 * s, 0.14 * s))
			_put(item, _cyl(0.05 * s, 0.13 * s, 0.24 * s, 10), glass, Vector3(0, -0.08 * s, 0.14 * s))
			_put_facing(item, ShapeKit.plate(Vector2(0.18, 0.24) * s, label), label, Vector3(0, -0.5 * s, 0.14 * s + 0.135 * s), Vector3.BACK)
		item.visible = false
		held_items[id] = item
		awake_nodes.append(item)
		i += 1


## 組み終わった部品を、親ごとに1つの形にまとめる（軽くするため）。手は「開いた手」「にぎった手」の2つを作る
func _bake() -> void:
	for id in hand_nodes:
		_bake_hand(id)
	_skin_legs()
	var containers: Array = [rig, _sleeves, head, _band, bat]
	for id in held_items:
		containers.append(held_items[id])
	for n in containers:
		if n != null:
			MeshMerge.merge_children(n, [skin, skin_red], merge_cache)
	# 点滅させる材質は、肌と、まとめた形の材質
	mats = [skin, skin_red]
	for k in merge_cache:
		mats.append(merge_cache[k])
	# 光る準備：はじめから「光る」を入れておき、明るさ0にしておく（あとで材質の種類が変わらないように）
	_flash_ready = false
	set_flash(false)


func _bake_hand(id: String) -> void:
	var hand: Node3D = hand_nodes[id]
	var parts_nodes: Array = []
	var others: Array = []
	for c in hand.get_children():
		if c.has_meta("finger"):
			parts_nodes.append(c)
		elif c is MeshInstance3D:
			parts_nodes.append(c)  # 腕輪・とげ（手と一緒に動く）
		else:
			others.append(c)  # 手に持つ物（バット・酒）は、別にまとめる
	for state in [["Open", 0.0], ["Fist", 0.85]]:
		_curl_pivots(id, float(state[1]))
		var mesh := MeshMerge.merge_parts(MeshMerge.collect(hand, others), [skin, skin_red], merge_cache)
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


# ---- 姿・表情の切り替え ----

func _apply_form(name: String) -> void:
	form = name
	var awake := name == "awake"
	skin.albedo_color = Color(str(cfg["skin_awake"] if awake else cfg["skin_normal"]))
	skin_red.albedo_color = Color(str(cfg["torso_awake"] if awake else cfg["torso_normal"]))
	for n in awake_nodes:
		(n as Node3D).visible = awake
	if aura_particles != null:
		aura_particles.emitting = awake
	for n in normal_nodes:
		(n as Node3D).visible = not awake
	for id in arm_nodes:
		var vis: bool = str(arm_forms[id]) == "" or (str(arm_forms[id]) == "awake" and awake)
		arm_visible[id] = vis
		(hand_nodes[id] as Node3D).visible = vis
		_layout_arm(id)
	_refresh_arm_colors()
	if tail_mm != null:
		_refresh_tail_colors()


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
		var f := 0.5 if i == 4 else 1.0
		(pair[0] as Node3D).rotation.x = -k * 1.25 * f
		(pair[1] as Node3D).rotation.x = -k * 1.7 * f


func set_hand_scale(side: String, s: float) -> void:
	(hand_nodes[side] as Node3D).scale = Vector3.ONE * s


## 手の先の位置を決めて、節を並べなおす。target は、モデルの座標。frame_delta があれば、目標へなめらかに近づく
func set_hand(side: String, target: Vector3, bend: Vector3 = Vector3.ZERO) -> void:
	if frame_delta > 0.0 and bool(_hand_ready[side]):
		var k := 1.0 - exp(-float(cfg.get("hand_follow_rate", 12.0)) * follow_boost * frame_delta)
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
	var r1 := r0 * 0.72
	var mm := arm_mm.multimesh
	var vis: bool = arm_visible.get(side, true)
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		var len := maxf(d.length(), 0.01)
		# 前腕（先の半分）は、少し太く（毛深い前腕）
		var k := (float(i) + 0.5) / n
		var r := lerpf(r0, r1, k) * (1.0 + 0.18 * sin(clampf((k - 0.45) / 0.5, 0.0, 1.0) * PI))
		var basis := Basis(Quaternion(Vector3.UP, d / len)) * Basis.from_scale(Vector3(r * 2.0, (len + r * 2.0) * 0.5, r * 2.0)) if vis else Basis.from_scale(Vector3.ZERO)
		mm.set_instance_transform(int(segs[i]), Transform3D(basis, (a + b) * 0.5))
	var hand: Node3D = hand_nodes[side]
	hand.position = h
	var tip: Vector3 = (pts[n] as Vector3) - (pts[n - 1] as Vector3)
	if tip.length() > 0.01:
		hand.basis = Basis(Quaternion(Vector3.DOWN, tip.normalized())) * Basis.from_scale(hand.basis.get_scale())
	if side == "L" and bat != null and bat.visible:
		_aim_bat(h, tip)


## バットの向き：かつぐ位置の近くでは、肩にのせて頭のうしろを通す向き。手が離れると（攻撃）、腕の向きにそって振る
func _aim_bat(h: Vector3, tip: Vector3) -> void:
	var carry := Vector3(-0.95, 0.18, -0.32).normalized()
	var swing := tip.normalized() if tip.length() > 0.01 else Vector3.DOWN
	var k := clampf(1.0 - (h - _bat_rest).length() / 1.6, 0.0, 1.0) if _bat_rest != Vector3.ZERO else 0.0
	var d := swing.lerp(carry, k).normalized()
	var hb := (hand_nodes["L"] as Node3D).basis.orthonormalized()
	bat.basis = hb.inverse() * Basis(Quaternion(Vector3.UP, d))


## ふだんの姿勢。平常時：左手でバットを肩にかつぎ、右腕は長く垂らす。覚醒：両腕を広げて、酒を持つ
func pose_idle(time: float) -> void:
	for side in ["L", "R"]:
		var out := 1.0 if side == "L" else -1.0
		var ph := 0.0 if side == "L" else 1.7
		var s: Vector3 = shoulder[side]
		var rest: Vector3
		if form == "awake":
			rest = s + Vector3(out * (1.35 + 0.2 * sin(time * 1.3 + ph)), -0.9 + 0.3 * sin(time * 1.1 + ph), 0.75 + 0.2 * cos(time * 0.9 + ph))
		elif side == "L":
			# バットを肩にかつぐ：手は肩の少し上・前
			rest = s + Vector3(0.1 + 0.04 * sin(time * 1.2), 0.32 + 0.05 * sin(time * 1.5), 0.3)
		else:
			# 長い腕を、ひざのあたりまで垂らす
			rest = s + Vector3(-0.42 - 0.08 * sin(time * 1.3), -2.15 + 0.1 * sin(time * 1.1), 0.3 + 0.12 * cos(time * 0.9))
		var bend := Vector3.ZERO
		if form != "awake" and side == "L":
			bend = Vector3(0.75, -1.0, 0.15)  # ひじを外・下へ曲げて、肩の前でバットを持つ
			_bat_rest = rest
		set_hand(side, rest, bend)
	pose_small_arms(time)


## 小さな腕。ふだんは、腰のうしろで、ゆらゆら。覚醒では、酒を持って大きくゆれる
func pose_small_arms(time: float) -> void:
	var awake := form == "awake"
	for id in SMALL:
		if str(arm_forms[id]) == "awake" and not awake:
			continue
		var out := 1.0 if id.begins_with("L") else -1.0
		var idx := int(id.substr(1, 1))
		var ph := float(idx) * 1.3 + (0.0 if out > 0.0 else 2.1)
		var s: Vector3 = shoulder[id]
		var target: Vector3
		if awake:
			# 体のまわりに広げて持つ（上の腕ほど高く。地面につけない＝体が埋もれて見えない）
			var lifts: Array = cfg.get("awake_small_lift", [0.55, -0.15, -0.7])
			var up := float(lifts[clampi(idx - 2, 0, lifts.size() - 1)])
			target = s + Vector3(out * (1.45 + 0.2 * float(idx - 2) + 0.15 * sin(time * 1.7 + ph)), up + 0.2 * sin(time * 2.0 + ph), 0.55 + 0.15 * float(idx % 2) + 0.15 * cos(time * 1.4 + ph))
		else:
			target = s + Vector3(out * (0.75 + 0.12 * sin(time * 1.7 + ph)), -1.45 + 0.12 * sin(time * 2.0 + ph), 0.05 + 0.15 * cos(time * 1.4 + ph))
		set_hand(id, target)


## よろけて倒れているときの腕：だらりとたれて、ゆれる
func pose_stagger_arms(time: float) -> void:
	for id in BIG:
		var out := 1.0 if id == "L" else -1.0
		var s: Vector3 = shoulder[id]
		set_hand(id, s + Vector3(out * (1.4 + 0.3 * sin(time * 5.0)), -2.4 + 0.25 * cos(time * 4.0), 0.9))
	pose_small_arms(time * 2.0)


func hand_world(side: String) -> Vector3:
	return to_global(hand_target[side])


# ---- 1コマごとの動き ----

## 1コマの始まりに呼ぶ。1コマの長さ（秒）を教える。0 を渡すと、手はすぐ目標へ動く
func begin_frame(delta: float) -> void:
	frame_delta = delta


## 光らせ方は「明るさ」だけ変える（材質の種類を切り替えると、ブラウザでは描き方の作り直しで一瞬止まるため）。
## 同じ状態なら何もしない（毎コマ呼ばれるため）
func set_flash(on: bool) -> void:
	if on == _flash_on and _flash_ready:
		return
	_flash_on = on
	_flash_ready = true
	for m in mats:
		var sm := m as StandardMaterial3D
		if not sm.emission_enabled:
			sm.emission_enabled = true
			sm.emission = Color(1, 1, 1)
		sm.emission_energy_multiplier = float(cfg.get("flash_energy", 0.45)) if on else 0.0


func is_flashing() -> bool:
	return _flash_on


## しゃがむ：腰を下げ、ひざを外へ曲げる（がに股）。上半身・肩・しっぽも下げる。足は床についたまま
func apply_crouch() -> void:
	var c := crouch
	# 歩くと、1歩ごとに腰が少し上下する
	var bob := float(cfg.get("walk_bob", 0.07)) * walk_amount * (0.5 - 0.5 * cos(2.0 * walk_phase))
	var drop := float(cfg.get("hip_y", 2.08)) * float(cfg["crouch_drop"]) * c + bob
	rig.position = Vector3(0.0, -drop, 0.12 * c)
	for id in shoulder:
		var base: Vector3 = shoulder_base[id]
		shoulder[id] = Vector3(base.x, base.y - drop, base.z + 0.12 * c)
	_pose_legs(drop, 0.12 * c)


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
	position.y = _model_y + float(cfg.get("bob", 0.07)) * breath
	scale = Vector3.ONE * float(cfg["model_scale"]) * (1.0 + float(cfg.get("breath_scale", 0.014)) * breath)
	apply_crouch()
	if head != null:
		head.rotation.x = 0.18 * crouch + (0.5 if is_staggering() and stagger_t > 1.0 and stagger_t < float(cfg["stagger_swap_sec"]) else 0.0)
	_update_tail(clock)
	_update_aura(clock)

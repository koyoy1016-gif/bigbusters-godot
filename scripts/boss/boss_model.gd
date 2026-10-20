extends Node3D
## ボスの3Dモデル。体は剣士と同じ人型（assets/models/hero_swordsman.glb、MPFB の骨）を大きくしたもの。
## 動きも剣士と同じ動き素材（hero_ual.res）を使う（boss_anim.gd・boss_moves.gd）。腕は2本。
## 見た目は鬼：紫の肌、反った角、赤と黒のリーゼント、牙、白っぽい袖のスカジャン、金のネックレス、とげバット（右手）、しっぽ。
## 小物は tools/make_oni.py が data/attachments.json に書く（oni_ で始まる）。骨についていく1つの形にまとめる（描く回数を減らす）。
## 体力60%でよろけて倒れ、起き上がるとき「覚醒」：赤い肌・はちまき・左手に一升瓶・バットは持たない・前かがみ・オーラ。
## モデルの原点は、足もとの床（高さ0）。向きは +Z が前。
## 設定は data/boss_model.json

const CharacterView := preload("res://scripts/characters/character_view.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const BossAnim := preload("res://scripts/boss/boss_anim.gd")
const Moves := preload("res://scripts/boss/boss_moves.gd")
const TailSegments := 12

var cfg: Dictionary = {}
var col: Dictionary = {}
var form := "normal"  ## "normal"（平常時）／"awake"（覚醒）
var stagger_t := -1.0  ## よろけて倒れる動きの経過秒（動いていなければ -1）
var model: Node3D  ## 人型のモデル（大きくしてある）
var skel: Skeleton3D
var anim := BossAnim.new()
var pose: Dictionary = {}  ## いまの姿勢
var skin: StandardMaterial3D  ## 体の肌（紫。覚醒で赤）
var mats: Array = []  ## 点滅させる材質
var merge_cache := {}
var normal_items: MeshInstance3D  ## 平常時だけの小物（バット）
var awake_items: MeshInstance3D  ## 覚醒時だけの小物（はちまき・一升瓶）
var tail_mm: MultiMeshInstance3D
var tail_deco_mm: MultiMeshInstance3D
var tail_scales: Array = []
var tail_whip := 0.0  ## しっぽをまっすぐ長くのばす具合（0〜1）
var aura: Node3D
var aura_particles: CPUParticles3D
var aura_ground: MeshInstance3D
var aura_glow_mat: StandardMaterial3D
var sweep_hands := {}
var bat_in_hand := true  ## バットを手に持っているか（バット投げの間は false）
var spray: CPUParticles3D  ## 酒をまくしぶき（世界に直接置く）  ## 必殺技の大きな手（"L"/"R" → Node3D。世界に直接置く）
var flinch := 0.0
var _clock := 0.0
var _flash_on := false
var _flash_ready := false
var _hip_rest := Vector3.ZERO
var _hip_basis_rest := Basis.IDENTITY


static func load_config(path: String = "res://data/boss_model.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 設定は config（data/boss_model.json）。skin_material は、肌の材質（色は姿に合わせて変える）
func build(config: Dictionary, skin_material: StandardMaterial3D) -> void:
	cfg = config
	col = cfg.get("colors", {})
	var packed := load(str(cfg["model"])) as PackedScene
	model = packed.instantiate() as Node3D
	model.name = "Human"
	model.scale = Vector3.ONE * float(cfg["model_scale"])
	model.set_meta("outline_width", float(cfg.get("outline_width", 0.022)))
	add_child(model)
	add_to_group("styled")
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skin = skin_material
	_setup_materials()
	var groups: Dictionary = cfg["item_groups"]
	var all: Array = []
	for g in groups:
		all.append_array(groups[g])
	CharacterView.attach_items(model, all)
	CharacterView.bake_items(model, groups["common"], "OniCommon")
	normal_items = CharacterView.bake_items(model, groups["normal"], "OniNormal")
	awake_items = CharacterView.bake_items(model, groups["awake"], "OniAwake")
	for mi in model.find_children("Oni*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(i)
			if sm is StandardMaterial3D:
				mats.append(sm)
	anim.setup(skel, load(str(cfg["anim_library"])) as AnimationLibrary, model)
	var hip := skel.find_bone("spine05")
	_hip_rest = _rest_global(hip).origin
	_hip_basis_rest = _rest_global(hip).basis
	_build_tail()
	_build_aura()
	_build_sweep_hands()
	_build_spray()
	_apply_form("normal")
	pose = anim.sample("Idle", 0.0)
	anim.apply(pose)
	_flash_ready = false
	set_flash(false)


func _rest_global(bi: int) -> Transform3D:
	var t := skel.get_bone_rest(bi)
	var p := skel.get_bone_parent(bi)
	while p >= 0:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t


func _c(key: String) -> Color:
	return Color(str(col.get(key, "#ff00ff")))


## 体の材質：剣士のモデルと材質を共有しているので、形をコピーして、ボス用の材質に差しかえる（剣士の色は変えない）
func _setup_materials() -> void:
	var hide: Array = cfg.get("hide_meshes", [])
	var tint: Dictionary = cfg.get("mesh_tint", {})
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var nm := str(mi.name)
		var hidden := false
		for h in hide:
			if nm.contains(str(h)):
				hidden = true
		if hidden:
			mi.visible = false
			continue
		var mesh := mi.mesh.duplicate() as Mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i) as StandardMaterial3D
			var m: StandardMaterial3D = src.duplicate() as StandardMaterial3D if src != null else StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.cull_mode = BaseMaterial3D.CULL_BACK
			m.clearcoat_enabled = false
			m.normal_enabled = false
			if nm == "Human":
				# 肌：剣士の肌の画像に、色を重ねる（姿で色を変える）
				m.albedo_color = Color(str(cfg["skin_normal"]))
				skin = m
			else:
				for key in tint:
					if nm.contains(str(key)):
						m.albedo_color = Color(str(tint[key]))
						if bool(cfg.get("tint_drop_texture", true)):
							m.albedo_texture = null
			StyleFx.style_material(m)
			StyleFx.apply_outline(m, float(cfg.get("outline_width", 0.022)))
			mesh.surface_set_material(i, m)
			mats.append(m)
		mi.mesh = mesh


# ---- しっぽ（腰のうしろから。腰の動きについていく） ----

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
		tail_scales.append(lerpf(float(r[0]), float(r[1]), float(i) / float(TailSegments - 1)))
	tail_mm = MultiMeshInstance3D.new()
	tail_mm.name = "Tail"
	tail_mm.multimesh = mm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(1, 1, 1)
	StyleFx.style_material(tm)
	tail_mm.material_override = MeshMerge.vc_material(tm, merge_cache)
	model.add_child(tail_mm)
	var deco := MultiMesh.new()
	deco.transform_format = MultiMesh.TRANSFORM_3D
	deco.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	deco.mesh = cone
	deco.instance_count = TailSegments + 5
	for i in deco.instance_count:
		deco.set_instance_color(i, _c("spine") if i < TailSegments else _c("tuft"))
	tail_deco_mm = MultiMeshInstance3D.new()
	tail_deco_mm.name = "TailDeco"
	tail_deco_mm.multimesh = deco
	tail_deco_mm.material_override = tail_mm.material_override
	model.add_child(tail_deco_mm)
	mats.append(tail_mm.material_override)
	_refresh_tail_colors()


func _refresh_tail_colors() -> void:
	for i in TailSegments:
		tail_mm.multimesh.set_instance_color(i, skin.albedo_color)


## しっぽの道（モデルの座標。休みの姿勢の腰を基準。k は 0〜1）
func _tail_point(k: float, clock: float) -> Vector3:
	var b: Array = cfg["tail_base"]
	var base := Vector3(float(b[0]), float(b[1]), float(b[2]))
	var L := float(cfg.get("tail_len", 1.1))
	var sway := sin(clock * 1.6 - k * 2.4) * 0.16 * k
	var rest := base + Vector3(0.22 * k * k + sway, (-0.95 * k + 0.6 * k * k) * L, -0.45 * L * sin(k * PI * 0.8))
	if tail_whip <= 0.0:
		return rest
	var whip := base + Vector3(0.1 * k * sin(clock * 9.0), -0.42 * k + 0.1 * k * k, -float(cfg.get("tail_whip_len", 1.5)) * k)
	return rest.lerp(whip, tail_whip)


func _update_tail(clock: float) -> void:
	# 腰の骨の、休みの姿勢からの動き（位置と向き）を、しっぽ全体にかける
	var mm := tail_mm.multimesh
	var deco := tail_deco_mm.multimesh
	var pts := _tail_points(clock)
	for i in TailSegments:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		var len := maxf(d.length(), 0.01)
		var rr := float(tail_scales[i])
		mm.set_instance_transform(i, Transform3D(Basis(Quaternion(Vector3.UP, d / len)) * Basis.from_scale(Vector3(rr * 2.0, (len + rr * 2.0) * 0.5, rr * 2.0)), (a + b) * 0.5))
		var up := (Vector3.UP - (d / len) * Vector3.UP.dot(d / len)).normalized()
		var h := rr * 1.3
		deco.set_instance_transform(i, Transform3D(Basis(Quaternion(Vector3.UP, up)) * Basis.from_scale(Vector3(rr * 0.45, h, rr * 0.45)), (a + b) * 0.5 + up * (rr + h * 0.4)))
	var tip: Vector3 = pts[TailSegments]
	var dir: Vector3 = (tip - (pts[TailSegments - 1] as Vector3)).normalized()
	for k in 5:
		var spread := (float(k) - 2.0) * 0.32
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var d2 := (dir + side * spread + Vector3.UP * 0.25 * cos(float(k))).normalized()
		var h2 := 0.2
		deco.set_instance_transform(TailSegments + k, Transform3D(Basis(Quaternion(Vector3.UP, d2)) * Basis.from_scale(Vector3(0.04, h2, 0.04)), tip + d2 * h2 * 0.5))


## しっぽの道の点（モデルの座標。腰の骨の、休みの姿勢からの動きをかける）
func _tail_points(clock: float) -> Array:
	var hip_now := anim.bone_model_pos(pose, "spine05")
	var rot := _hip_model_basis() * _hip_basis_rest.inverse()
	var pts: Array = []
	for i in TailSegments + 1:
		var p := _tail_point(float(i) / float(TailSegments), clock)
		pts.append(hip_now + rot * (p - _hip_rest))
	return pts


## しっぽの先の位置（ボスの足もとから見た、大きさをかけた長さ）
func tail_tip_local() -> Vector3:
	var pts := _tail_points(_clock)
	return (pts[pts.size() - 1] as Vector3) * float(cfg["model_scale"])


func _hip_model_basis() -> Basis:
	var bi := skel.find_bone("spine05")
	var chain: Array = []
	var p := bi
	while p >= 0:
		chain.push_front(p)
		p = skel.get_bone_parent(p)
	var b := Basis.IDENTITY
	var r: Array[Quaternion] = pose["r"]
	for i in chain:
		b = b * Basis(r[i])
	return anim.s2m * b


# ---- 覚醒のオーラ ----

func _build_aura() -> void:
	var a: Dictionary = cfg.get("aura", {})
	aura = Node3D.new()
	aura.name = "Aura"
	add_child(aura)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	quad.size = Vector2(1.1, 1.8)
	quad.material = mat
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.mesh = quad
	p.amount = int(a.get("amount", 30))
	p.lifetime = float(a.get("lifetime", 1.1))
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = float(a.get("height", 3.5))
	p.emission_ring_radius = float(a.get("radius", 1.6))
	p.emission_ring_inner_radius = float(a.get("radius", 1.6)) * 0.55
	p.position = Vector3(0, float(a.get("height", 3.5)) * 0.5, 0)
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
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_color = Color(str(a.get("ground_color", "#ff3c6e")), 0.35)
	var disc := CylinderMesh.new()
	disc.top_radius = float(a.get("radius", 1.6)) * 1.6
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


func _update_aura(clock: float) -> void:
	if aura_glow_mat == null or form != "awake":
		return
	var pulse := 0.5 + 0.5 * sin(clock * 5.0)
	aura_glow_mat.albedo_color.a = 0.22 + 0.25 * pulse
	aura_ground.scale = Vector3.ONE * (1.0 + 0.12 * pulse)


# ---- 必殺技の大きな手（ボスの手が、画面のはしからはしへ走る技。手だけを大きく出す） ----

func _build_sweep_hands() -> void:
	for side in ["L", "R"]:
		var hand := Node3D.new()
		hand.name = "SweepHand" + side
		hand.top_level = true
		hand.visible = false
		add_child(hand)
		var palm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 12
		sm.rings = 6
		sm.material = skin
		palm.mesh = sm
		palm.scale = Vector3(1.0, 0.45, 1.1)
		hand.add_child(palm)
		for f in 5:
			var thumb := f == 4
			var cap := CapsuleMesh.new()
			cap.radius = 0.11
			cap.height = 0.75 if not thumb else 0.55
			cap.radial_segments = 8
			cap.rings = 2
			cap.material = skin
			var fi := MeshInstance3D.new()
			fi.mesh = cap
			var x := (float(f) - 1.5) * 0.24
			if thumb:
				fi.position = Vector3(0.62 * (1.0 if side == "L" else -1.0), 0.0, 0.05)
				fi.rotation_degrees = Vector3(0, 0, 80 * (1.0 if side == "L" else -1.0))
			else:
				fi.position = Vector3(x, 0.0, 0.75)
				fi.rotation_degrees = Vector3(90, 0, 0)
			hand.add_child(fi)
		sweep_hands[side] = hand


# ---- 酒のしぶき（一升瓶をふり上げたとき、空へ飛ぶ） ----

func _build_spray() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.34
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = mat
	spray = CPUParticles3D.new()
	spray.name = "SakeSpray"
	spray.top_level = true
	spray.mesh = sm
	spray.one_shot = true
	spray.emitting = false
	spray.explosiveness = 0.85
	spray.amount = int(cfg.get("spray_amount", 36))
	spray.lifetime = 1.3
	spray.direction = Vector3.UP
	spray.spread = 28.0
	spray.initial_velocity_min = 6.0
	spray.initial_velocity_max = 11.0
	spray.gravity = Vector3(0, -14.0, 0)
	spray.scale_amount_min = 0.7
	spray.scale_amount_max = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(str(cfg.get("sake_color", "#f2e6b8")), 0.95))
	grad.set_color(1, Color(str(cfg.get("sake_color", "#f2e6b8")), 0.0))
	spray.color_ramp = grad
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spray)


## 酒を空へまく（左手の一升瓶から）
func spray_sake() -> void:
	if spray == null:
		return
	spray.global_position = hand_world("L") + Vector3(0, 0.5, 0)
	spray.restart()


# ---- 姿 ----

func _apply_form(name: String) -> void:
	form = name
	var awake := name == "awake"
	skin.albedo_color = Color(str(cfg["skin_awake"] if awake else cfg["skin_normal"]))
	if normal_items != null:
		normal_items.visible = bat_in_hand  # バットは、覚醒しても持ったまま（投げている間だけ消す）
	if awake_items != null:
		awake_items.visible = awake
	if aura != null:
		var aura_on := awake and bool((cfg.get("aura", {}) as Dictionary).get("enabled", true))  # 版61：オーラは消して、色の変化だけ
		aura.visible = aura_on
		aura_particles.emitting = aura_on
	if tail_mm != null:
		_refresh_tail_colors()


## バットを手に持つ／持たない（バット投げ）
func set_bat_visible(on: bool) -> void:
	bat_in_hand = on
	if normal_items != null:
		normal_items.visible = on


func skin_color() -> Color:
	return skin.albedo_color


func reset_form() -> void:
	stagger_t = -1.0
	_apply_form("normal")


func is_staggering() -> bool:
	return stagger_t >= 0.0


func is_awake() -> bool:
	return form == "awake"


## 第1形態の体力が0になった：よろけて倒れる（倒れたまま → 起き上がるときに覚醒の姿へ）。体力の管理は scripts/combat/boss_phase.gd
func begin_fall() -> void:
	if stagger_t < 0.0 and form == "normal":
		stagger_t = 0.0


## 1コマ進める（倒れる演出の進み）。起き上がるときに覚醒の姿へ変わる
func update_form(delta: float) -> void:
	if stagger_t >= 0.0:
		stagger_t += delta
		if form == "normal" and stagger_t >= float(cfg["stagger_swap_sec"]):
			_apply_form("awake")
		if stagger_t >= float(cfg["stagger_sec"]):
			stagger_t = -1.0


## 光らせ方は「明るさ」だけ変える（材質の種類を切り替えると、ブラウザでは描き方の作り直しで一瞬止まるため）
func set_flash(on: bool) -> void:
	if on == _flash_on and _flash_ready:
		return
	_flash_on = on
	_flash_ready = true
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm == null:
			continue
		if not sm.emission_enabled:
			sm.emission_enabled = true
			sm.emission = Color(1, 1, 1)
		sm.emission_energy_multiplier = float(cfg.get("flash_energy", 0.45)) if on else 0.0


func is_flashing() -> bool:
	return _flash_on


# ---- 1コマごとの動き ----

## 1コマ進める。st：いまの状況（boss_moves.gd の build_pose を見る）。戻り値：{spin: 体ごと回る角度（ラジアン）}
func animate(delta: float, clock: float, st: Dictionary) -> Dictionary:
	_clock = clock
	if bool(st.get("hit_now", false)):
		flinch = 1.0
	flinch = move_toward(flinch, 0.0, delta * float(cfg.get("flinch_decay_per_sec", 4.0)))
	st["flinch"] = flinch
	st["awake"] = form == "awake"
	st["stagger_t"] = stagger_t
	st["stagger_sec"] = float(cfg["stagger_sec"])
	st["stagger_swap_sec"] = float(cfg["stagger_swap_sec"])
	var res := Moves.build_pose(anim, st, cfg)
	pose = res["pose"]
	anim.apply(pose)
	tail_whip = float(res.get("whip", 0.0))
	_update_tail(clock)
	_update_aura(clock)
	return res


## 手（手首の少し先）の世界の位置。side は "L"（左手）か "R"（右手）
func hand_world(side: String) -> Vector3:
	var wrist := anim.bone_model_pos(pose, "wrist." + side)
	var fing := anim.bone_model_pos(pose, "finger3-1." + side)
	var local := wrist.lerp(fing, 1.4)
	if is_inside_tree():
		return model.to_global(local)
	# 木に入っていないとき（テストなど）：親をたどって計算する
	var t := model.transform
	var node: Node = self
	while node is Node3D:
		t = (node as Node3D).transform * t
		node = node.get_parent()
	return t * local


## バットの先の位置（ボスの足もとから見た、大きさをかけた長さ。ボスの向き・回転は入れない）
func bat_tip_local(p: Dictionary = {}) -> Vector3:
	var ps: Dictionary = pose if p.is_empty() else p
	var bt: Dictionary = cfg.get("bat_tip", {})
	var off: Array = bt.get("offset", [0, 0.08, 0])
	var aim_a: Array = bt.get("aim", [0, 1, 0])
	var aim := Vector3(float(aim_a[0]), float(aim_a[1]), float(aim_a[2])).normalized()
	var wx := anim.bone_model_xform(ps, "wrist.R")
	var tip := wx * (Vector3(float(off[0]), float(off[1]), float(off[2])) + Basis(Quaternion(Vector3.UP, aim)) * Vector3(0, float(bt.get("length", 1.3)), 0))
	return tip * float(cfg["model_scale"])

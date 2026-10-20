extends RefCounted
## 版78・79：キャラごとの攻撃の見た目。形は make で作り、毎コマ tick で動かす（寿命が来たら false を返す。呼ぶ側が消す）。
## 数値は data/char_actions.json の fx_events / hits の fx。小物（プレゼント・銃弾・魔法の玉など）は data/props.json（tools/make_props.py）。
## kind：
##   beam・slash（帯の光）、orb（飛ぶ玉。prop があれば小物）、blast（爆発の球）、ring（広がる輪）、pillar（光の柱）、
##   dome・heal_dome・clock（半透明の膜。shaders/skill_dome.gdshader。青＝守り、緑＝回復、紫＝時間停止）、
##   aura（体を包む光と、立ちのぼる粒。必殺技の色）、spark（当たった所の火花）、ripple（膜に当たった波紋）、
##   confetti（紙ふぶき）、smoke（けむり）、rise（上へのぼる光の筋）、prop（小物をその場に出す：魔法陣・砲口の光など）
## ブラウザで重くしないよう、1つの見た目は、形を数こ・粒は数十こまでにする。

const BodyBuilder := preload("res://scripts/characters/body_builder.gd")
const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const DOME_SHADER := preload("res://shaders/skill_dome.gdshader")
const PROPS_PATH := "res://data/props.json"
const FxPool := preload("res://scripts/fx/fx_pool.gd")

static var _props: Dictionary = {}
static var _prop_meshes: Dictionary = {}
## 版105（軽量化）：形（球・輪・筒・板・星）は、同じ大きさなら1回だけ作って使いまわす（前は出すたびに作り直していて、
## 技を出した瞬間の1コマが長くなっていた）。色とすけ方は、形ではなく、その見た目だけの材質（material_override）に持たせる
static var _shapes: Dictionary = {}


static func _shape(key: String, make_fn: Callable) -> Mesh:
	if not _shapes.has(key):
		_shapes[key] = make_fn.call()
	return _shapes[key]


static func _sphere(radius: float, height: float, seg: int, rings: int, hemi: bool = false) -> Mesh:
	return _shape("sphere|%s|%s|%d|%d|%s" % [radius, height, seg, rings, hemi], func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = seg
		m.rings = rings
		m.is_hemisphere = hemi
		return m)


static func _torus(inner: float, outer: float, rings: int, seg: int) -> Mesh:
	return _shape("torus|%s|%s|%d|%d" % [inner, outer, rings, seg], func() -> Mesh:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = rings
		m.ring_segments = seg
		return m)


static func _cylinder(radius: float, height: float, seg: int) -> Mesh:
	return _shape("cyl|%s|%s|%d" % [radius, height, seg], func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = seg
		m.rings = 1
		return m)


## 見た目の材質（形の材質ではなく、この見た目だけの材質。消える時に色のすけ具合を変える）
static func mat_of(mi: GeometryInstance3D) -> Material:
	if mi == null:
		return null
	if mi.material_override != null:
		return mi.material_override
	if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
		return (mi as MeshInstance3D).mesh.surface_get_material(0)
	return null


static func props() -> Dictionary:
	if _props.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPS_PATH)) if FileAccess.file_exists(PROPS_PATH) else null
		_props = (parsed as Dictionary).get("props", {}) if parsed is Dictionary else {}
	return _props


## 小物の形（部品をまとめた1つの形。光る部品は、光る材質のまま別の面）。同じ名前は使いまわす。なければ null
static func prop_mesh(name: String) -> ArrayMesh:
	if _prop_meshes.has(name):
		return _prop_meshes[name]
	var parts: Array = props().get(name, [])
	if parts.is_empty():
		return null
	var list: Array = []
	var keep: Array = []
	for part in parts:
		var m := BodyBuilder.make_part_mesh(part)
		if m == null:
			continue
		var mat := m.surface_get_material(0) as StandardMaterial3D
		if mat != null and (mat.emission_enabled or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			keep.append(mat)
		list.append({"mesh": m, "xf": BodyBuilder.part_transform(part)})
	var merged := MeshMerge.merge_parts(list, keep, {})
	_prop_meshes[name] = merged
	return merged


## 見た目の材質。版105：同じ種類（色・光・すけ具合・板の向き）の、使い終わった材質があれば使いまわす（fx_pool.gd）。
## 使っている間に変わる所（色のすけ具合・光の強さ）は、ここで元にもどす
static func _mat(color: Color, emission: float = 1.2, alpha: float = 1.0, billboard: int = BaseMaterial3D.BILLBOARD_DISABLED) -> StandardMaterial3D:
	var key := "std|%s|%.3f|%.3f|%d" % [color.to_html(), emission, alpha, billboard]
	var m := FxPool.take(key) as StandardMaterial3D
	if m != null:
		m.albedo_color = Color(color.r, color.g, color.b, alpha)
		m.emission_energy_multiplier = emission
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = emission > 0.0
	m.emission = color
	m.emission_energy_multiplier = emission
	if billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		m.billboard_mode = billboard
	FxPool.mark(m, key)
	return m


## 膜の材質（aura：体を包む光の作り）。版105：使いまわす（消えていく具合 fade・脈 pulse は元にもどす）
static func dome_material(color: Color, alpha: float, aura: bool = false) -> ShaderMaterial:
	var key := "dome|%s|%.3f|%s" % [color.to_html(), alpha, aura]
	var sm := FxPool.take(key) as ShaderMaterial
	if sm == null:
		sm = ShaderMaterial.new()
		sm.shader = DOME_SHADER
		if aura:
			sm.set_shader_parameter("hex_alpha", 0.0)
			sm.set_shader_parameter("rim_alpha", 0.9)
		FxPool.mark(sm, key)
	sm.set_shader_parameter("color", color)
	sm.set_shader_parameter("alpha", alpha)
	sm.set_shader_parameter("fade", 0.0)
	sm.set_shader_parameter("pulse", 0.0)
	return sm


static func _particles(color: Color, amount: int, life: float, spread: float, vel: Vector2, gravity: Vector3, size: float, box: Vector3,
		one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = gravity
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var mat := _mat(color, 2.0, 0.9, BaseMaterial3D.BILLBOARD_PARTICLES)
	p.mesh = _shape("quad|0.12", func() -> Mesh:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.12, 0.12)
		return qm)
	p.material_override = mat
	p.emitting = true
	return p


## 見た目を作る。spec：{kind, color, life, ...}。from：始まり（足もと、または発射口）、to：終わり（ねらう所）。height：from が足もとのときの手の高さ
static func make(spec: Dictionary, from: Vector3, to: Vector3, height: float) -> Node3D:
	var kind := str(spec.get("kind", "blast"))
	var col := Color(str(spec.get("color", "#ffffff")))
	var root := Node3D.new()
	root.name = "SkillFx_" + kind
	root.set_meta("kind", kind)
	root.set_meta("life", float(spec.get("life", 0.4)))
	root.set_meta("age", 0.0)
	root.set_meta("spec", spec)
	root.set_meta("from", from)
	root.set_meta("to", to)
	var mi := MeshInstance3D.new()
	mi.name = "Shape"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	match kind:
		"beam", "slash":
			var d := to - from
			if not bool(spec.get("tilt", false)):
				d.y = 0.0
			var len := maxf(d.length(), 0.1)
			var w := float(spec.get("width", 0.25))
			# 長さ1の筒を、長さの分だけのばす（前は長さごとに筒を作っていた。形は同じ）
			mi.mesh = _cylinder(w, 1.0, 10)
			mi.scale = Vector3(1.0, len, 1.0)
			mi.material_override = _mat(col, 2.0, float(spec.get("alpha", 0.85)))
			root.set_meta("len", len)
			root.position = from + Vector3(0, height, 0) + d * 0.5
			var dir := d.normalized() if d.length() > 0.001 else Vector3.FORWARD
			root.basis = Basis(Quaternion(Vector3.UP, dir))
			if kind == "beam":
				var core := MeshInstance3D.new()
				core.mesh = _cylinder(w * 0.4, 1.0, 8)
				core.scale = Vector3(1.0, len, 1.0)
				core.material_override = _mat(Color(1, 1, 1), 2.5, 0.95)
				root.add_child(core)
				# ビームの通り道の、うず巻く輪（3つ、流れる）
				for k in 3:
					var ring := MeshInstance3D.new()
					ring.mesh = _torus(w * 1.3, w * 1.7, 16, 4)
					ring.material_override = _mat(col, 2.2, 0.7)
					ring.name = "Ring%d" % k
					ring.position = Vector3(0, -len * 0.5 + len * (k + 0.5) / 3.0, 0)
					root.add_child(ring)
		"orb":
			var pm := prop_mesh(str(spec.get("prop", ""))) if spec.has("prop") else null
			if pm != null:
				mi.mesh = pm
				root.scale = Vector3.ONE * float(spec.get("scale", 1.0))
			else:
				var r := float(spec.get("radius", 0.2))
				mi.mesh = _sphere(r, r * 2.0, 12, 6)
				mi.material_override = _mat(col, 2.0, 1.0)
			root.position = from + Vector3(0, height, 0)
		"prop":
			mi.mesh = prop_mesh(str(spec.get("prop", "")))
			root.position = to + Vector3(0, float(spec.get("y", 0.05)), 0)
			root.scale = Vector3.ONE * float(spec.get("scale", 1.0))
			var aimv := to - from
			aimv.y = 0.0
			if aimv.length() > 0.01:
				root.rotation.y = atan2(aimv.x, aimv.z)
		"blast":
			mi.mesh = _sphere(1.0, 2.0, 20, 10)
			mi.material_override = _mat(col, 1.4, 0.7)
			root.position = to
			root.scale = Vector3.ONE * 0.05
			# 外へ飛ぶ火の粉
			root.add_child(_particles(col.lightened(0.3), 18, 0.5, 70.0, Vector2(4.0, 8.0), Vector3(0, -9, 0), 1.2, Vector3(0.3, 0.3, 0.3), true))
		"dome", "heal_dome", "clock", "aura":
			var hemi: bool = kind in ["dome", "heal_dome"]
			mi.mesh = _sphere(1.0, 1.0 if hemi else 2.0, 28, 14, hemi)
			mi.material_override = dome_material(col, float(spec.get("alpha", 0.18)), kind == "aura")
			root.position = to if kind == "clock" else from
			root.scale = Vector3.ONE * 0.05
			if kind == "aura":
				# 体を包む、たてに長い光（だ円）と、足もとの輪と、立ちのぼる粒
				mi.scale = Vector3(0.8, 1.25, 0.8)
				mi.position = Vector3(0, 1.0, 0)
				var ring2 := MeshInstance3D.new()
				ring2.mesh = _torus(0.9, 1.0, 28, 4)
				ring2.material_override = _mat(col, 2.2, 0.85)
				ring2.name = "Ground"
				ring2.scale = Vector3(1.0, 0.3, 1.0)
				ring2.position = Vector3(0, 0.05, 0)
				root.add_child(ring2)
				root.add_child(_particles(col.lightened(0.25), 24, 0.9, 12.0, Vector2(2.0, 3.5), Vector3(0, 0.5, 0), 1.0, Vector3(0.45, 0.1, 0.45), false))
			if kind == "heal_dome":
				root.add_child(_particles(Color("#9dffb8"), 28, 1.6, 8.0, Vector2(0.8, 1.6), Vector3(0, 0.6, 0), 0.9, Vector3(0.8, 0.05, 0.8), false))
		"ring":
			mi.mesh = _torus(0.9, 1.0, 24, 4)
			mi.material_override = _mat(col, 1.8, 0.8)
			root.position = to + Vector3(0, 0.08, 0)
			root.scale = Vector3(0.1, 0.4, 0.1)
		"pillar":
			var pr := float(spec.get("radius", 1.0))
			var tall := float(spec.get("tall", 8.0))
			mi.mesh = _cylinder(pr, tall, 14)
			mi.material_override = _mat(col, 1.8, 0.45)
			root.position = to + Vector3(0, tall * 0.5, 0)
		"spark":
			# 当たった所：星形の光（すぐ消える）、広がる輪、飛び散る火花
			mi.mesh = _star_mesh(float(spec.get("size", 0.6)), col)
			mi.material_override = _star_material(col)
			root.position = to
			root.add_child(_particles(col.lightened(0.35), int(spec.get("amount", 12)), 0.35, 80.0, Vector2(3.0, 6.0), Vector3(0, -6, 0), 0.8,
				Vector3(0.1, 0.1, 0.1), true))
			# 版80：当たった瞬間の、白い一瞬の光（0.1秒で消える）
			var fl := float(spec.get("flash", 0.0)) * float(spec.get("size", 0.6))
			if fl > 0.0:
				var fm := MeshInstance3D.new()
				fm.name = "Flash"
				fm.mesh = _sphere(fl, fl * 2.0, 10, 5)
				fm.material_override = _mat(Color(1, 1, 0.92), 3.0, 0.85)
				fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(fm)
		"ripple":
			mi.mesh = _torus(0.85, 1.0, 24, 4)
			mi.material_override = _mat(col, 2.2, 0.85)
			root.position = to
			var nrm := (to - from).normalized()
			if nrm.length() > 0.5:
				root.basis = Basis(Quaternion(Vector3.UP, nrm))
			root.scale = Vector3(0.1, 0.25, 0.1)
		"confetti":
			root.position = to + Vector3(0, 0.6, 0)
			for c in ["#e6343a", "#ffd84a", "#3f6fd1", "#3d9a4a", "#d65aa0"]:
				root.add_child(_particles(Color(c), 8, 1.2, 45.0, Vector2(4.0, 7.0), Vector3(0, -6, 0), 1.0, Vector3(0.2, 0.1, 0.2), true))
		"smoke":
			root.position = to
			var sp := _particles(Color(str(spec.get("color", "#e8e4dc"))), 10, 0.7, 60.0, Vector2(0.6, 1.4), Vector3(0, 0.4, 0), 3.0, Vector3(0.3, 0.1, 0.3), true)
			(sp.material_override as StandardMaterial3D).emission_energy_multiplier = 0.2
			(sp.material_override as StandardMaterial3D).albedo_color.a = 0.6
			root.add_child(sp)
		"rise":
			root.position = to
			root.add_child(_particles(col, 20, 0.9, 6.0, Vector2(2.5, 4.0), Vector3(0, 1.5, 0), 0.9, Vector3(0.4, 0.05, 0.4), true))
	FxPool.track(root)  # 版105：消える時に、材質を返す（次の見た目で使いまわす）
	return root


## 版80：飛ぶ物が引く光の粒（世界に残る。飛ぶ物が消えると一緒に消える）。k：飛ぶ物の大きさ
static func trail(col: Color, k: float = 1.0) -> CPUParticles3D:
	var p := _particles(col, 16, 0.32, 25.0, Vector2(0.2, 0.6), Vector3.ZERO, clampf(0.9 * k, 1.0, 2.6), Vector3(0.06, 0.06, 0.06), false)
	p.name = "Trail"
	p.local_coords = false
	p.direction = Vector3.BACK
	return p


## 星の形（大きさごとに1回だけ作る。色は _star_material）
static func _star_mesh(size: float, _col: Color = Color.WHITE) -> Mesh:
	return _shape("star|%s" % size, func() -> Mesh: return _make_star(size))


static func _star_material(col: Color) -> StandardMaterial3D:
	return _mat(col.lightened(0.4), 3.0, 0.95, BaseMaterial3D.BILLBOARD_ENABLED)


static func _make_star(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * (float(i) + 0.5) / n
		var a2 := TAU * (float(i) + 1.0) / n
		var p0 := Vector3(cos(a0), sin(a0), 0) * size
		var p1 := Vector3(cos(a1), sin(a1), 0) * size * 0.35
		var p2 := Vector3(cos(a2), sin(a2), 0) * size
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(p1)
		st.add_vertex(p2)
	return st.commit()


## 1コマ進める。まだ続くなら true。follow：ついていく位置（INF ならついていかない）
static func tick(n: Node3D, delta: float, follow: Vector3 = Vector3.INF) -> bool:
	var age := float(n.get_meta("age", 0.0)) + delta
	n.set_meta("age", age)
	var life := float(n.get_meta("life", 0.4))
	var k := clampf(age / maxf(life, 0.001), 0.0, 1.0)
	var spec: Dictionary = n.get_meta("spec", {})
	var mi := n.get_node_or_null("Shape") as MeshInstance3D
	match str(n.get_meta("kind", "")):
		"beam":
			var f := 1.0 + 0.15 * sin(age * 60.0)
			var shrink := 1.0 - smoothstep(0.75, 1.0, k)
			var grow := smoothstep(0.0, 0.08, k)
			n.scale = Vector3(f * shrink * grow, 1.0, f * shrink * grow)
			for i in 3:
				var r := n.get_node_or_null("Ring%d" % i) as Node3D
				if r != null and mi != null:
					var len := float(n.get_meta("len", 1.0))
					r.position.y = fposmod(r.position.y + len * 0.5 + delta * 18.0, len) - len * 0.5
		"slash":
			n.scale = Vector3(1.0 - k, 1.0, 1.0 - k)
		"orb":
			var from: Vector3 = n.get_meta("from")
			var to: Vector3 = n.get_meta("to")
			var h := float(spec.get("height", 1.3))
			var arc := float(spec.get("arc", 0.0))
			var p := from.lerp(to, k)
			p.y = lerpf(from.y + h, to.y + 0.3, k) + arc * 4.0 * k * (1.0 - k)
			n.position = p
		"prop":
			var spin := float(spec.get("spin", 0.0))
			if spin != 0.0:
				n.rotate_y(spin * delta)
			var fade := 1.0 - smoothstep(0.8, 1.0, k)
			var pop := smoothstep(0.0, 0.12, k)
			n.scale = Vector3.ONE * float(spec.get("scale", 1.0)) * pop * fade
		"blast":
			var r := float(spec.get("radius", 2.0))
			n.scale = Vector3.ONE * r * (0.3 + 0.7 * sqrt(k))
			if mi != null:
				(mat_of(mi) as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - k)
		"ring":
			var r2 := float(spec.get("radius", 3.0))
			n.scale = Vector3(r2 * k + 0.1, 0.4, r2 * k + 0.1)
			if mi != null:
				(mat_of(mi) as StandardMaterial3D).albedo_color.a = 0.8 * (1.0 - k)
		"ripple":
			var r4 := float(spec.get("radius", 0.9))
			n.scale = Vector3(r4 * (0.2 + k), 0.25, r4 * (0.2 + k))
			if mi != null:
				(mat_of(mi) as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - k)
		"spark":
			if mi != null:
				mi.scale = Vector3.ONE * (0.6 + 0.8 * k)
				(mat_of(mi) as StandardMaterial3D).albedo_color.a = 0.95 * (1.0 - smoothstep(0.2, 0.6, k))
			var fm := n.get_node_or_null("Flash") as MeshInstance3D
			if fm != null:
				# 一瞬ふくらんで、すぐ消える（0.1秒）
				var kf := clampf(age / 0.1, 0.0, 1.0)
				fm.scale = Vector3.ONE * (0.6 + 0.6 * kf)
				fm.visible = kf < 1.0
				(mat_of(fm) as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - kf)
		"dome", "heal_dome", "aura", "clock":
			var r3 := float(spec.get("radius", 3.0))
			# 3段階：広がる（はじめの 0.35 秒）→ たもつ（ゆっくり脈打つ）→ うすくなって消える（さいごの 0.6 秒）
			var grow2 := smoothstep(0.0, minf(0.35, life * 0.3), age)
			var fade2 := 1.0 - smoothstep(maxf(life - 0.6, life * 0.7), life, age)
			n.scale = Vector3.ONE * r3 * (0.3 + 0.7 * grow2) * (1.0 + 0.02 * sin(age * 5.0))
			if follow != Vector3.INF:
				n.position = follow
			if mi != null and mat_of(mi) is ShaderMaterial:
				var smat := mat_of(mi) as ShaderMaterial
				smat.set_shader_parameter("fade", fade2 * grow2)
				var pulse := float(n.get_meta("pulse", 0.0))
				if pulse > 0.0:
					n.set_meta("pulse", maxf(0.0, pulse - delta * 3.0))
				smat.set_shader_parameter("pulse", float(n.get_meta("pulse", 0.0)))
			for c in n.get_children():
				if c is CPUParticles3D and age > life - 0.6:
					(c as CPUParticles3D).emitting = false
		"pillar":
			var fade3 := 1.0 - smoothstep(0.7, 1.0, k)
			n.scale = Vector3(fade3 + 0.05, 1.0, fade3 + 0.05)
	return age < life

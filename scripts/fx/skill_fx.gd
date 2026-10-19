extends RefCounted
## 版78：キャラごとの攻撃の見た目（ビーム・飛ぶ玉・爆発・衝撃の輪・ドーム・光の柱・時間停止・速さのオーラ）。
## 形は make で作り、毎コマ tick で動かす（寿命が来たら false を返す。呼ぶ側が消す）。数値は data/char_actions.json の fx_events / hits の fx。
## 1つの見た目は、単色の光る材質の形を1〜2こだけ使う（ブラウザで重くしない）。

const SHAPES := ["beam", "orb", "blast", "ring", "dome", "pillar", "clock", "aura", "slash"]


static func _mat(color: Color, emission: float = 1.2, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = emission > 0.0
	m.emission = color
	m.emission_energy_multiplier = emission
	return m


## 見た目を作る。spec：{kind, color, life, ...}。from：始まり（足もと）、to：終わり（ねらう所）。height：手の高さ
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
			d.y = 0.0
			var len := maxf(d.length(), 0.1)
			var cm := CylinderMesh.new()
			var w := float(spec.get("width", 0.25))
			cm.top_radius = w
			cm.bottom_radius = w
			cm.height = len
			cm.radial_segments = 10
			cm.rings = 1
			cm.material = _mat(col, 2.0, float(spec.get("alpha", 0.85)))
			mi.mesh = cm
			root.position = from + Vector3(0, height, 0) + d * 0.5
			var dir := d.normalized() if d.length() > 0.001 else Vector3.FORWARD
			root.basis = Basis(Quaternion(Vector3.UP, dir))
			if kind == "beam":
				# 芯（白く細い）
				var core := MeshInstance3D.new()
				var c2 := CylinderMesh.new()
				c2.top_radius = w * 0.4
				c2.bottom_radius = w * 0.4
				c2.height = len
				c2.radial_segments = 8
				c2.rings = 1
				c2.material = _mat(Color(1, 1, 1), 2.5, 0.95)
				core.mesh = c2
				root.add_child(core)
		"orb":
			var sm := SphereMesh.new()
			var r := float(spec.get("radius", 0.2))
			sm.radius = r
			sm.height = r * 2.0
			sm.radial_segments = 12
			sm.rings = 6
			sm.material = _mat(col, 2.0, 1.0)
			mi.mesh = sm
			root.position = from + Vector3(0, height, 0)
		"blast", "dome", "clock", "aura":
			var s2 := SphereMesh.new()
			s2.radius = 1.0
			s2.height = 1.0 if kind == "dome" else 2.0
			s2.is_hemisphere = kind == "dome"
			s2.radial_segments = 20
			s2.rings = 10
			s2.material = _mat(col, 1.4, float(spec.get("alpha", 0.45 if kind != "blast" else 0.7)))
			mi.mesh = s2
			root.position = to
			if kind == "dome":
				root.position = from
			root.scale = Vector3.ONE * 0.05
		"ring":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.9
			tm.outer_radius = 1.0
			tm.rings = 24
			tm.ring_segments = 4
			tm.material = _mat(col, 1.8, 0.8)
			mi.mesh = tm
			root.position = to + Vector3(0, 0.08, 0)
			root.scale = Vector3(0.1, 0.4, 0.1)
		"pillar":
			var cm2 := CylinderMesh.new()
			var pr := float(spec.get("radius", 1.0))
			cm2.top_radius = pr
			cm2.bottom_radius = pr
			cm2.height = float(spec.get("tall", 8.0))
			cm2.radial_segments = 14
			cm2.rings = 1
			cm2.material = _mat(col, 1.8, 0.45)
			mi.mesh = cm2
			root.position = to + Vector3(0, cm2.height * 0.5, 0)
	return root


## 1コマ進める。まだ続くなら true
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
			n.scale = Vector3(f * shrink, 1.0, f * shrink)
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
		"blast":
			var r := float(spec.get("radius", 2.0))
			n.scale = Vector3.ONE * r * (0.3 + 0.7 * sqrt(k))
			if mi != null:
				(mi.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - k)
		"ring":
			var r2 := float(spec.get("radius", 3.0))
			n.scale = Vector3(r2 * k + 0.1, 0.4, r2 * k + 0.1)
			if mi != null:
				(mi.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = 0.8 * (1.0 - k)
		"dome", "aura", "clock":
			var r3 := float(spec.get("radius", 3.0))
			var grow := smoothstep(0.0, 0.12, k)
			var fade := 1.0 - smoothstep(0.9, 1.0, k)
			n.scale = Vector3.ONE * r3 * grow * (1.0 + 0.03 * sin(age * 6.0))
			if follow != Vector3.INF:
				n.position = follow
			if mi != null:
				(mi.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = float(spec.get("alpha", 0.35)) * fade
		"pillar":
			var fade2 := 1.0 - smoothstep(0.7, 1.0, k)
			n.scale = Vector3(fade2 + 0.05, 1.0, fade2 + 0.05)
	return age < life

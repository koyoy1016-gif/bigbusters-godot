extends Node3D
## 版72：剣士の必殺技の見た目（1つずつ出して、時間がたつと消える）。
## kind："charge"（足もとの金の輪が、ちぢみながら明るくなる＝力をためる）／"ghost"（剣士の形の残像。版72b）／"slash"（大きな三日月の斬撃）。
## 数値は data/actions.json の ultimate の fx。残像の形は、踏み込みの始めに1回だけ写し取り、同じ形を何体も使う（重くしない）。

var kind := ""
var life := 0.3
var age := 0.0
var mat: StandardMaterial3D = null
var base_alpha := 1.0


## 出す。parent：付ける所。pos：床の上の位置（高さは kind ごとに決める）。aim：前の向き (x, z)。fx：設定
static func spawn(parent: Node, kind_name: String, pos: Vector3, aim: Vector2, fx: Dictionary, extra: Dictionary = {}) -> Node3D:
	var n: Node3D = (load("res://scripts/fx/ultimate_fx.gd") as GDScript).new()
	n.name = "UltFx_" + kind_name
	n.kind = kind_name
	parent.add_child(n)
	n.call("_build", pos, aim, fx, extra)
	return n


func _make_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


func _build(pos: Vector3, aim: Vector2, fx: Dictionary, extra: Dictionary) -> void:
	var a := aim.normalized() if aim.length() > 0.001 else Vector2(0, 1)
	var yaw := atan2(a.x, a.y)
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	match kind:
		"charge":
			life = float(fx.get("charge_sec", 0.3))
			var tm := TorusMesh.new()
			var r := float(fx.get("ring_r", 1.6))
			tm.inner_radius = r * 0.88
			tm.outer_radius = r
			tm.rings = 32
			tm.ring_segments = 4
			mi.mesh = tm
			mat = _make_mat(Color(str(fx.get("ring_color", "#ffd24a"))))
			position = Vector3(pos.x, pos.y + 0.06, pos.z)
		"ghost":
			# 剣士の形（bake_ghost で写した形）を、半透明の光る色で出す
			life = float(fx.get("ghost_life", 0.45))
			base_alpha = float(fx.get("ghost_alpha", 0.55))
			mat = _make_mat(Color(str(fx.get("ghost_color", "#9fd8ff"))))
			mi.queue_free()
			mi = null
			transform = extra.get("xform", Transform3D(Basis(Vector3.UP, yaw), pos))
			for part in extra.get("parts", []):
				var pm := MeshInstance3D.new()
				pm.mesh = part[0]
				pm.transform = part[1]
				pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pm.material_override = mat
				add_child(pm)
		"slash":
			life = float(fx.get("slash_life", 0.32))
			mi.mesh = arc_mesh(float(fx.get("slash_radius", 2.8)))
			mat = _make_mat(Color(str(fx.get("slash_color", "#fff3c4"))))
			position = Vector3(pos.x, pos.y + 1.2, pos.z) + Vector3(a.x, 0.0, a.y) * 0.6
			rotation = Vector3(0.0, yaw, deg_to_rad(float(fx.get("slash_tilt_deg", -28.0))))
	if mi != null:
		mi.material_override = mat
	_apply(0.0)


## 版72b：view（剣士の見た目）の、いまのポーズの形を写し取る。[[形, view から見た位置], ...]。写せなければ []
static func bake_ghost(view: Node3D) -> Array:
	var out: Array = []
	if view == null or not view.is_inside_tree():
		return out
	var inv := view.global_transform.affine_inverse()
	for n in view.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n
		if not m.visible or m.mesh == null or m.has_meta("proxy"):
			continue  # 版103：影だけ・輪郭線だけの形（proxy）は写さない（重なって色が濃くなるため）
		var baked: Mesh = m.bake_mesh_from_current_skeleton_pose() if m.skin != null or m.skeleton != NodePath("") else m.mesh
		if baked == null:
			continue
		out.append([baked, inv * m.global_transform])
	return out


## 三日月の形（前 +Z を中心に、左右へ広がる。両はしは細くなる）
static func arc_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	var half := deg_to_rad(85.0)
	var prev_o := Vector3.ZERO
	var prev_i := Vector3.ZERO
	for i in seg + 1:
		var f := float(i) / seg
		var ang := lerpf(-half, half, f)
		var thick := sin(f * PI) * 0.45 + 0.02  # まん中が太い
		var o := Vector3(sin(ang), 0.0, cos(ang)) * radius
		var inn := Vector3(sin(ang), 0.0, cos(ang)) * radius * (1.0 - thick)
		if i > 0:
			st.add_vertex(prev_o)
			st.add_vertex(o)
			st.add_vertex(inn)
			st.add_vertex(prev_o)
			st.add_vertex(inn)
			st.add_vertex(prev_i)
		prev_o = o
		prev_i = inn
	return st.commit()


func _apply(k: float) -> void:
	if mat == null:
		return
	match kind:
		"charge":
			# ちぢみながら、明るくなる（力が集まる）
			scale = Vector3.ONE * lerpf(1.0, 0.35, k)
			mat.albedo_color.a = lerpf(0.25, 0.95, k)
		"ghost":
			mat.albedo_color.a = base_alpha * (1.0 - k)
		"slash":
			# すぐ出て、少し広がりながら消える
			scale = Vector3.ONE * lerpf(0.85, 1.15, k)
			mat.albedo_color.a = 1.0 - k * k


func _process(delta: float) -> void:
	age += delta
	var k := clampf(age / maxf(life, 0.01), 0.0, 1.0)
	_apply(k)
	if age >= life:
		queue_free()

extends RefCounted
## 版108：はじめて描く時の準備（シェーダー作り）を、戦いの始まりにすませるための「写し」を作る。
## スマホのブラウザ（WebGL）では、はじめて使う描き方（材質の種類 × ふつう／たくさん並べる × 色／影）を描く瞬間に、
## シェーダーを作るため画面が止まる。覚醒やボスの攻撃で、はじめて出る見た目（酒の雨・巨大酒瓶・火・覚醒の小物…）が多いので、
## 戦いの画面ができた時に、同じ形・同じ材質の「写し」を、見えない所（カメラの前の地面の下）に数コマだけ出して、先に準備させる。
## 写しは、元の形・材質をそのまま使う（新しい材質は作らない）。元のノードは動かさない・見せない。
## 骨で動く形（skin）は、骨なしで写す（Compatibility の描き方は、骨の有無でシェーダーを作り分けない。scene.glsl）。
## 粒（CPUParticles3D）は、たくさん並べる描き方なので、粒のまま写し、全部を最初のコマに出す。


## root（とその下）の、描く物すべての写し。root は木に入っていなくてもよい
static func copies_under(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var list: Array = []
	if root is GeometryInstance3D:
		list.append(root)
	list.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for g in list:
		var c := copy_of(g as GeometryInstance3D)
		if c != null:
			out.append(c)
	return out


## 1つの形の写し（同じ形・同じ材質・同じ影の設定）。写せない物は null
static func copy_of(g: GeometryInstance3D) -> GeometryInstance3D:
	var c: GeometryInstance3D = null
	if g is CPUParticles3D:
		var p := (g as CPUParticles3D).duplicate(0) as CPUParticles3D
		p.top_level = false
		p.local_coords = true
		p.one_shot = false
		p.explosiveness = 1.0  # 最初のコマで全部の粒を出す（並べる数が 0 だと描かない）
		p.emitting = true
		c = p
	elif g is MultiMeshInstance3D:
		var mm := MultiMeshInstance3D.new()
		mm.multimesh = (g as MultiMeshInstance3D).multimesh
		c = mm
	elif g is Label3D:
		var l := (g as Label3D).duplicate(0) as Label3D
		if l.text == "":
			l.text = "0123456789"
		c = l
	elif g is MeshInstance3D:
		var src := g as MeshInstance3D
		if src.mesh == null:
			return null
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		for i in src.get_surface_override_material_count():
			var m := src.get_surface_override_material(i)
			if m != null:
				mi.set_surface_override_material(i, m)
		c = mi
	else:
		return null
	c.name = "Warm_" + str(g.name)
	c.material_override = g.material_override
	c.material_overlay = g.material_overlay
	c.cast_shadow = g.cast_shadow
	c.transparency = g.transparency
	c.visible = true
	c.set_meta("draw_warm", true)
	return c

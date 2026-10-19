extends RefCounted
## 小さな部品（箱・球・円柱など。shape_kit.gd で作った印 "part" つきの形も）を、1つの形にまとめる（描画の回数を減らして、軽くする）。
## 色は「頂点の色」にうつすので、色ちがいの部品も1回で描ける。
## keep_mats に入れた材質（例：姿で色が変わる肌）は、頂点の色にせず、その材質のまま別の面にまとめる。
## 材質は cache（モデルごとの辞書）で使いまわす。まとめたあとの材質は cache の値（点滅などに使う）。


## 部品の材質から、頂点の色で描く材質を作る（同じ見た目のものは、cache で使いまわす）
static func vc_material(src: StandardMaterial3D, cache: Dictionary) -> StandardMaterial3D:
	# つやと金属っぽさの違いでは、面を分けない（トゥーン調ではほとんど見えず、面が分かれると描く回数が増えるため）。
	# 分けるのは、模様の画像・すけ方・両面かどうか、だけ
	var tex_key := ""
	if src.albedo_texture != null:
		tex_key = src.albedo_texture.resource_path if src.albedo_texture.resource_path != "" else str(src.albedo_texture.get_instance_id())
	var key := "vc|%s|%d|%s|%d" % [tex_key, src.transparency, "a" if src.albedo_color.a < 0.999 else "", src.cull_mode]
	if cache.has(key):
		return cache[key]
	var m := src.duplicate() as StandardMaterial3D
	m.albedo_color = Color(1, 1, 1, src.albedo_color.a)
	m.metallic = 0.0
	m.roughness = 0.6
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.emission_enabled = false
	cache[key] = m
	return m


## まとめられる部品の形か（箱・球などの基本の形、または shape_kit.gd の形）
static func is_part(mesh: Mesh) -> bool:
	return mesh is PrimitiveMesh or (mesh != null and mesh.has_meta("part"))


static func _src_material(mesh: Mesh) -> StandardMaterial3D:
	if mesh is PrimitiveMesh:
		return (mesh as PrimitiveMesh).material as StandardMaterial3D
	return mesh.surface_get_material(0) as StandardMaterial3D


static func _arrays(mesh: Mesh) -> Array:
	if mesh is PrimitiveMesh:
		return (mesh as PrimitiveMesh).get_mesh_arrays()
	return mesh.surface_get_arrays(0)


## parts：[{mesh: 形, xf: Transform3D（まとめる先の座標）, bone: 骨の番号（スキンの bind の番号。なくてもよい）}] を、
## 1つの ArrayMesh にする。部品がなければ null。bone があれば、骨の動きについていく形（スキン）になる
static func merge_parts(parts: Array, keep_mats: Array, cache: Dictionary) -> ArrayMesh:
	var groups := {}  # 材質 → {v, n, c, i, b, w}
	var skinned := false
	for p in parts:
		if (p as Dictionary).has("bone"):
			skinned = true
	var order: Array = []
	for p in parts:
		var pm := p["mesh"] as Mesh
		if not is_part(pm):
			continue
		var src := _src_material(pm)
		if src == null:
			continue
		var target: Material = src if keep_mats.has(src) else vc_material(src, cache)
		if not groups.has(target):
			groups[target] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "u": PackedVector2Array(), "i": PackedInt32Array(), "b": PackedInt32Array(), "w": PackedFloat32Array()}
			order.append(target)
		var g: Dictionary = groups[target]
		var arrays := _arrays(pm)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var xf: Transform3D = p["xf"]
		var nb := xf.basis.inverse().transposed()
		var color := src.albedo_color if not keep_mats.has(src) else Color(1, 1, 1, 1)
		var base: int = (g["v"] as PackedVector3Array).size()
		var gv: PackedVector3Array = g["v"]
		var gn: PackedVector3Array = g["n"]
		var gc: PackedColorArray = g["c"]
		var gu: PackedVector2Array = g["u"]
		var gi: PackedInt32Array = g["i"]
		var gb: PackedInt32Array = g["b"]
		var gw: PackedFloat32Array = g["w"]
		var bone := int(p.get("bone", 0))
		for k in verts.size():
			gv.append(xf * verts[k])
			gn.append((nb * norms[k]).normalized() if k < norms.size() else Vector3.UP)
			gc.append(color)
			gu.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
			if skinned:
				gb.append_array([bone, 0, 0, 0])
				gw.append_array([1.0, 0.0, 0.0, 0.0])
		if idx.is_empty():
			for k in verts.size():
				gi.append(base + k)
		else:
			# 向きが裏返る変形（拡大率がマイナス）では、三角形の向きを直す
			var flip := xf.basis.determinant() < 0.0
			for k in range(0, idx.size(), 3):
				if flip:
					gi.append(base + idx[k])
					gi.append(base + idx[k + 2])
					gi.append(base + idx[k + 1])
				else:
					gi.append(base + idx[k])
					gi.append(base + idx[k + 1])
					gi.append(base + idx[k + 2])
		g["v"] = gv
		g["n"] = gn
		g["c"] = gc
		g["u"] = gu
		g["i"] = gi
		g["b"] = gb
		g["w"] = gw
	if order.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for mat in order:
		var g: Dictionary = groups[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		arr[Mesh.ARRAY_COLOR] = g["c"]
		arr[Mesh.ARRAY_TEX_UV] = g["u"]
		arr[Mesh.ARRAY_INDEX] = g["i"]
		if skinned:
			arr[Mesh.ARRAY_BONES] = g["b"]
			arr[Mesh.ARRAY_WEIGHTS] = g["w"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


## node の下の部品を、node から見た変形つきで集める（部品の子の部品もたどる）。skip に入れた物（とその下）は集めない
static func collect(node: Node3D, skip: Array = [], acc: Transform3D = Transform3D.IDENTITY, out: Array = []) -> Array:
	for c in node.get_children():
		if not (c is Node3D) or skip.has(c):
			continue
		var c3 := c as Node3D
		if not c3.visible:
			continue
		var xf := acc * c3.transform
		if c is MeshInstance3D and is_part((c as MeshInstance3D).mesh):
			out.append({"mesh": (c as MeshInstance3D).mesh, "xf": xf, "node": c})
		collect(c3, skip, xf, out)
	return out


## node のすぐ下にある部品（MeshInstance3D）だけを1つにまとめ、元の部品は消す。まとめた物を返す（部品がなければ null）。
## 子の Node3D（動く関節など）と、skip に入れた物は、そのまま残す
static func merge_children(node: Node3D, keep_mats: Array, cache: Dictionary, skip: Array = []) -> MeshInstance3D:
	var parts: Array = []
	for c in node.get_children():
		if c is MeshInstance3D and not skip.has(c) and (c as MeshInstance3D).visible and is_part((c as MeshInstance3D).mesh) and (c as MeshInstance3D).get_child_count() == 0:
			parts.append({"mesh": (c as MeshInstance3D).mesh, "xf": (c as Node3D).transform, "node": c})
	if parts.size() < 2:
		return null
	var mesh := merge_parts(parts, keep_mats, cache)
	if mesh == null:
		return null
	for p in parts:
		var n: Node = p["node"]
		node.remove_child(n)
		n.free()
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = mesh
	node.add_child(mi)
	return mi

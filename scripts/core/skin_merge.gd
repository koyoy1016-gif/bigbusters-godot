extends RefCounted
## 版103（軽量化）：同じ骨（Skeleton3D）で動く、骨つきの形（スキン）の面をいくつも、1つの面にまとめる。
## 影だけ・輪郭線だけを、キャラ全体で少ない回数で描くために使う（前は、面の数だけ何回も描いていた）。
## 点の位置・向き（法線）・骨と重みを、そのまま写す（色・模様は写さない：影と輪郭線には使わないため）。
## 速さ：点の配列はエンジンの append_array でつなぎ、スクリプトで1つずつ直すのは「三角形の番号のずらし」だけ。
##   骨の表（Skin）がちがう形（小物など）は、骨の番号をまとめた表の番号に付けかえる（小さいので軽い）。
## 同じキャラ（同じモデル）なら、まとめた形と骨の表を使いまわせる（呼ぶ側が覚える）。

## parts：[{"mi": MeshInstance3D, "surface": int}]。skel：骨。skin：まとめた骨の表（いくつかのまとめで共有する時に渡す。なければ作る）
## 戻り値：{"arrays": 面の配列, "flags": 面の印, "skin": Skin, "verts": 点の数} か、まとめられなければ {}
static func merge(parts: Array, skel: Skeleton3D, skin: Skin = null, bind_index: Dictionary = {}) -> Dictionary:
	if parts.is_empty() or skel == null:
		return {}
	if skin == null:
		skin = Skin.new()
		bind_index = {}
	# まとめた骨の表：まだ空なら、いちばん多く使われている表（体の部品）をそのまま土台にする（その部品は、番号の付けかえがいらない）
	var base_skin: Skin = null
	if skin.get_bind_count() == 0:
		base_skin = _most_used_skin(parts)
		if base_skin != null:
			for i in base_skin.get_bind_count():
				var bname := _bind_name(base_skin, i, skel)
				if bname == "":
					return {}
				var key := [bname, base_skin.get_bind_pose(i)]
				if not bind_index.has(key):
					bind_index[key] = skin.get_bind_count()
				skin.add_named_bind(bname, base_skin.get_bind_pose(i))
		skin.set_meta("base_skin", base_skin)
	else:
		base_skin = skin.get_meta("base_skin", null)
	var per := 4
	for p in parts:
		if ((p["mi"] as MeshInstance3D).mesh.surface_get_format(int(p["surface"])) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0:
			per = 8
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for p in parts:
		var mi := p["mi"] as MeshInstance3D
		var si := int(p["surface"])
		if (mi.mesh.surface_get_format(si) & Mesh.ARRAY_FORMAT_BONES) == 0:
			return {}  # 骨のない面は、まとめない（呼ぶ側が、元のまま残す）
		var arr := mi.mesh.surface_get_arrays(si)
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n := pv.size()
		if n == 0:
			continue
		var pb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var pw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var src_per := pb.size() / n
		if mi.skin == null or (mi.skin != base_skin and not _same_skin(mi.skin, base_skin, skel)):
			# 骨の表がちがう：番号を付けかえる
			var remap := _bind_map(mi, skel, skin, bind_index)
			if remap.is_empty():
				return {}
			for i in pb.size():
				pb[i] = int(remap.get(pb[i], 0)) if pw[i] > 0.0 else 0
		if src_per != per:
			# 1点の骨の数をそろえる（4 → 8：足りない分は重み 0）
			var nb := PackedInt32Array()
			var nw := PackedFloat32Array()
			nb.resize(n * per)
			nw.resize(n * per)
			for i in n:
				for k in mini(src_per, per):
					nb[i * per + k] = pb[i * src_per + k]
					nw[i * per + k] = pw[i * src_per + k]
			pb = nb
			pw = nw
		var base := verts.size()
		verts.append_array(pv)
		var pn: Variant = arr[Mesh.ARRAY_NORMAL]
		if pn is PackedVector3Array and (pn as PackedVector3Array).size() == n:
			normals.append_array(pn)
		else:
			var up := PackedVector3Array()
			up.resize(n)
			up.fill(Vector3.UP)
			normals.append_array(up)
		bones.append_array(pb)
		weights.append_array(pw)
		var start := indices.size()
		var pi: Variant = arr[Mesh.ARRAY_INDEX]
		if pi is PackedInt32Array and not (pi as PackedInt32Array).is_empty():
			indices.append_array(pi)
		else:
			var seq := PackedInt32Array()
			seq.resize(n)
			for i in n:
				seq[i] = i
			indices.append_array(seq)
		if base > 0:
			for k in range(start, indices.size()):
				indices[k] += base
	if verts.is_empty():
		return {}
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	out[Mesh.ARRAY_INDEX] = indices
	return {"arrays": out, "flags": Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0, "skin": skin, "verts": verts.size()}


## まとめた配列（merge の戻り値）を、面にした形。groups の順に、面を1つずつ
static func to_mesh(groups: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for g in groups:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (g as Dictionary)["arrays"], [], {}, int((g as Dictionary)["flags"]))
	return mesh


static func _most_used_skin(parts: Array) -> Skin:
	var count := {}
	var best: Skin = null
	var best_n := -1
	for p in parts:
		var s := (p["mi"] as MeshInstance3D).skin
		if s == null:
			continue
		var k := s.get_instance_id()
		count[k] = int(count.get(k, 0)) + 1
		if int(count[k]) > best_n:
			best_n = int(count[k])
			best = s
	return best


## 2つの骨の表が同じ（同じ順の、同じ骨・同じ姿勢）なら true。同じなら、骨の番号をそのまま使える
static func _same_skin(a: Skin, b: Skin, skel: Skeleton3D) -> bool:
	if b == null or a.get_bind_count() != b.get_bind_count():
		return false
	for i in a.get_bind_count():
		if a.get_bind_pose(i) != b.get_bind_pose(i):
			return false
		if a.get_bind_name(i) != b.get_bind_name(i) or a.get_bind_bone(i) != b.get_bind_bone(i):
			if _bind_name(a, i, skel) != _bind_name(b, i, skel):
				return false
	return true


static func _bind_name(s: Skin, i: int, skel: Skeleton3D) -> String:
	var bname := str(s.get_bind_name(i))
	if bname == "":
		var bb := s.get_bind_bone(i)
		if bb < 0 or bb >= skel.get_bone_count():
			return ""
		bname = skel.get_bone_name(bb)
	return bname if skel.find_bone(bname) >= 0 else ""


## mi の骨の表（Skin。なければ骨のもとの姿勢から作る）の番号 → まとめた表 skin の番号。同じ骨・同じ姿勢は1つにする
static func _bind_map(mi: MeshInstance3D, skel: Skeleton3D, skin: Skin, bind_index: Dictionary) -> Dictionary:
	var remap := {}
	var src := mi.skin
	if src == null:
		for b in skel.get_bone_count():
			remap[b] = _add_bind(skel.get_bone_name(b), skel.get_bone_global_rest(b).affine_inverse(), skin, bind_index)
		return remap
	for i in src.get_bind_count():
		var bname := _bind_name(src, i, skel)
		if bname == "":
			return {}
		remap[i] = _add_bind(bname, src.get_bind_pose(i), skin, bind_index)
	return remap


static func _add_bind(bname: String, pose: Transform3D, skin: Skin, bind_index: Dictionary) -> int:
	var key := [bname, pose]
	if bind_index.has(key):
		return int(bind_index[key])
	var idx := skin.get_bind_count()
	skin.add_named_bind(bname, pose)
	bind_index[key] = idx
	return idx

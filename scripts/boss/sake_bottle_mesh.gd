extends RefCounted
## 一升瓶の形（版63）。横から見た輪郭（長さの位置 → 半径）を、軸のまわりに回して、1つのなめらかな面にする。
## 部品を重ねないので、ずれたり、すき間ができたり、浮いて見えたりしない。色は頂点の色（ガラス・ラベル・首・ふた）。
## 巨大酒瓶ライドの瓶と、投げる酒瓶の両方で使う（形をそろえる）。画像は使わない。
## 向き：長さは +Z（底が -Z、口が +Z）。中心は長さの真ん中。length（全体の長さ）・radius（胴の半径）で大きさが決まる

## 輪郭：[長さの割合（0＝底、1＝口の先）, 半径の割合（胴＝1）, 色の種類]
## 実物の一升瓶（高さ約40cm・胴の直径約10.5cm）の比率に近づけた
const PROFILE := [
	[0.000, 0.00, "glass"],
	[0.000, 0.80, "glass"],
	[0.012, 0.95, "glass"],
	[0.030, 1.00, "glass"],
	[0.170, 1.00, "glass"],
	[0.170, 1.025, "label"],
	[0.440, 1.025, "label"],
	[0.440, 1.00, "glass"],
	[0.560, 1.00, "glass"],
	[0.610, 0.96, "glass"],
	[0.660, 0.84, "glass"],
	[0.705, 0.66, "glass"],
	[0.745, 0.50, "glass"],
	[0.785, 0.41, "neck"],
	[0.900, 0.37, "neck"],
	[0.915, 0.43, "neck"],
	[0.930, 0.43, "neck"],
	[0.930, 0.40, "cap"],
	[0.995, 0.40, "cap"],
	[1.000, 0.36, "cap"],
	[1.000, 0.00, "cap"],
]

static var _cache := {}


## colors：{glass, label, neck, cap}（Color）。segs：まわりの分け方
static func build(length: float, radius: float, colors: Dictionary, segs: int = 20) -> ArrayMesh:
	var key := "%.3f_%.3f_%d_%s" % [length, radius, segs, str(colors)]
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# 輪郭の線分ごとに、まわりの帯を作る（色の境目は、同じ位置に点を2つ置いて、くっきり分ける）
	for i in PROFILE.size() - 1:
		var a: Array = PROFILE[i]
		var b: Array = PROFILE[i + 1]
		var za := (float(a[0]) - 0.5) * length
		var zb := (float(b[0]) - 0.5) * length
		var ra := float(a[1]) * radius
		var rb := float(b[1]) * radius
		if is_equal_approx(za, zb) and is_equal_approx(ra, rb):
			continue
		var col: Color = colors.get(str(b[2]) if str(a[2]) != str(b[2]) and is_equal_approx(za, zb) else str(a[2]), Color.WHITE)
		# 面の向き（輪郭の線に直角、外向き）
		var dz := zb - za
		var dr := rb - ra
		var nlen := sqrt(dz * dz + dr * dr)
		var nr := dz / nlen
		var nz := -dr / nlen
		var base := verts.size()
		for s in segs + 1:
			var ang := TAU * float(s) / float(segs)
			var cx := cos(ang)
			var cy := sin(ang)
			verts.append(Vector3(cx * ra, cy * ra, za))
			verts.append(Vector3(cx * rb, cy * rb, zb))
			var nn := Vector3(cx * nr, cy * nr, nz).normalized()
			norms.append(nn)
			norms.append(nn)
			cols.append(col)
			cols.append(col)
		for s in segs:
			var v0 := base + s * 2
			idx.append_array([v0, v0 + 1, v0 + 2, v0 + 2, v0 + 1, v0 + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.28
	mat.metallic_specular = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	_cache[key] = m
	return m


## 設定（data/boss_attacks.json の bottle_ride の色）から、色の表を作る
static func colors_from(k: Dictionary) -> Dictionary:
	return {"glass": Color(str(k.get("bottle_color", "#3f7a4a"))), "label": Color(str(k.get("label_color", "#f1e7cf"))),
		"neck": Color(str(k.get("neck_color", "#2f6a3c"))), "cap": Color(str(k.get("cap_color", "#b8322a")))}


## 輪郭の、長さの位置 z（中心が0）での半径。瓶の外に出ているかの確認（テスト）に使う
static func radius_at(z: float, length: float, radius: float) -> float:
	var f := z / length + 0.5
	for i in PROFILE.size() - 1:
		var a: Array = PROFILE[i]
		var b: Array = PROFILE[i + 1]
		if f >= float(a[0]) and f <= float(b[0]) and float(b[0]) > float(a[0]):
			var w := (f - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), w) * radius
	return 0.0

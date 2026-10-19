extends RefCounted
## コードで形を作る道具（Blender を使えない環境でも、なめらかな体を作るため）。
## loft：輪切り（だ円）を道にそって並べ、つないだ筒を作る。胴・脚・しっぽ・角・髪などに使う。
## 作った形は ArrayMesh（面は1つ）。材質は面に付ける。mesh_merge.gd でまとめられるよう、印 "part" を付ける。


## rings：[[中心 Vector3, 横の半径, 奥の半径], ...]。横の向きは side（道に直角になるよう直す）。
## arc_from・arc_to：輪の一部だけ作る（ラジアン。0 が横、PI/2 が奥の向き。前を開けた上着などに使う）。
## caps：両はしをふさぐ（輪をぜんぶ作るときだけ）
static func loft(rings: Array, mat: Material, segs: int = 12, side: Vector3 = Vector3.RIGHT, arc_from: float = 0.0, arc_to: float = TAU, caps: bool = true) -> ArrayMesh:
	var full := absf(arc_to - arc_from - TAU) < 0.001
	var cols := segs + (0 if full else 1)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var count := rings.size()
	for i in count:
		var c: Vector3 = rings[i][0]
		var w := float(rings[i][1])
		var d := float(rings[i][2])
		var prev: Vector3 = rings[maxi(i - 1, 0)][0]
		var next: Vector3 = rings[mini(i + 1, count - 1)][0]
		var t := (next - prev).normalized()
		if t.length() < 0.5:
			t = Vector3.UP
		var bx := side - t * side.dot(t)
		if bx.length() < 0.01:
			bx = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
		bx = bx.normalized()
		var bz := bx.cross(t)
		for j in cols:
			var a := arc_from + (arc_to - arc_from) * float(j) / float(segs)
			var ca := cos(a)
			var sa := sin(a)
			v.append(c + bx * ca * w + bz * sa * d)
			n.append((bx * ca / maxf(w, 0.001) + bz * sa / maxf(d, 0.001)).normalized())
			uv.append(Vector2(float(j) / float(segs), float(i) / float(maxi(count - 1, 1))))
	for i in count - 1:
		for j in segs:
			var j2 := (j + 1) % cols if full else j + 1
			var a0 := i * cols + j
			var a1 := i * cols + j2
			var b0 := (i + 1) * cols + j
			var b1 := (i + 1) * cols + j2
			# Godot は「時計回り」が表
			idx.append_array([a0, a1, b0, a1, b1, b0])
	if caps and full:
		for end: int in [0, count - 1]:
			var c: Vector3 = rings[end][0]
			var dir: Vector3 = (rings[mini(end + 1, count - 1)][0] - rings[maxi(end - 1, 0)][0]).normalized()
			var out := -dir if end == 0 else dir
			var center := v.size()
			v.append(c)
			n.append(out)
			uv.append(Vector2(0.5, 0.5))
			for j in cols:
				var k: int = end * cols + j
				var k2: int = end * cols + (j + 1) % cols
				if end == 0:
					idx.append_array([center, k2, k])
				else:
					idx.append_array([center, k, k2])
	return _finish(v, n, uv, idx, mat)


## 道（points）にそって、太さが r0 から r1 へ変わる丸い筒（つの・しっぽの毛・髪の束など）
static func tube(points: Array, r0: float, r1: float, mat: Material, segs: int = 8, squash: float = 1.0) -> ArrayMesh:
	var rings: Array = []
	var cnt := points.size()
	for i in cnt:
		var k := float(i) / float(maxi(cnt - 1, 1))
		var r := lerpf(r0, r1, k)
		rings.append([points[i], r, r * squash])
	return loft(rings, mat, segs)


## 2次のベジェ曲線の上の点を n+1 個（なめらかな道を作る）
static func curve(a: Vector3, ctrl: Vector3, b: Vector3, n: int) -> Array:
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


## 平らな四角（模様の板：トラの刺しゅう・文字など）。normal の向きに表を向ける
static func plate(size: Vector2, mat: Material) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var v := PackedVector3Array([Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)])
	var n := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var uv := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var idx := PackedInt32Array([0, 2, 1, 0, 3, 2])
	return _finish(v, n, uv, idx, mat)


static func _finish(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, mat: Material) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	m.set_meta("part", true)
	return m

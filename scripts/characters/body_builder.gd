extends RefCounted
## キャラの見た目を、データ（data/character_looks.json）から作る道具（2026-10-20）。
## 土台は剣士と同じ体（MakeHuman の CC0 の体・人の骨格。動きも同じ物が使える）。その上で：
##   1. 体格（bulk）：骨のまわりの太さを、部位ごとに変える（筋肉・細身・ずんぐり）。頭の大きさ（head_scale）
##   2. 塗り（paint）：体の面を、部位・高さなどで選んで、服の色にする（ぴったりした服・肌着）。しま模様もできる
##   3. 重ね着（shells）：体の面を少し外へ出した、もう1枚の服（ぶかぶかのズボン・手袋の巻き布など）。骨についていく
##   4. 部品（parts）：帽子・武器・盾・羽などの形を、骨に付ける（loft・tube・rod・box・sphere・torus・extrude）
## 座標は「モデル座標」（体の前が +Z、上が +Y、キャラの左が +X。体の高さは約1.97）。骨の静止の姿勢（Aポーズ）で書く。
## Blender は、この作業環境では使えない（入れられない）。そのため、ここでコードで作る。

const ShapeKit := preload("res://scripts/core/shape_kit.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const LOOKS_PATH := "res://data/character_looks.json"
## 胴・脚・足の面（もとの体では、服の下は消されている）。この形を、肌や服として塗る
const BODY_PARTS := ["male_casualsuit06", "shoes01"]
## 剣士の肌の画像（young_lightskinned_male_diffuse3）の平均の色（PIL で測った値）
const SKIN_TEX_AVG := Color(0.781, 0.609, 0.508)

static var _looks: Dictionary = {}


static func load_looks() -> Dictionary:
	if _looks.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_PATH))
		_looks = (parsed as Dictionary).get("looks", {}) if parsed is Dictionary else {}
	return _looks


## 骨の名前 → 部位の名前（体格・塗りの範囲に使う）
static func group_of(bone: String) -> String:
	if bone.begins_with("neck"):
		return "neck"
	if bone in ["spine01", "spine02"] or bone.begins_with("clavicle") or bone.begins_with("breast") or bone.begins_with("shoulder"):
		return "chest"
	if bone in ["spine03", "spine04"]:
		return "belly"
	if bone in ["spine05", "root"] or bone.begins_with("pelvis"):
		return "hips"
	if bone.begins_with("upperarm"):
		return "upperarm"
	if bone.begins_with("lowerarm"):
		return "forearm"
	if bone.begins_with("wrist") or bone.begins_with("finger") or bone.begins_with("metacarpal"):
		return "hand"
	if bone.begins_with("upperleg"):
		return "thigh"
	if bone.begins_with("lowerleg"):
		return "shin"
	if bone.begins_with("foot") or bone.begins_with("toe"):
		return "foot"
	return "head"


## モデル（剣士の glb の場面）に、見た目 look を当てはめる。作った面の三角形の数を返す（失敗は -1）
static func apply(model: Node, look: Dictionary) -> int:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return -1
	var sk := found[0] as Skeleton3D
	var rest := _rests(sk)
	var tails := _tails(sk, rest)
	var keep: Array = look.get("keep", [])
	var tris := 0
	var bodies: Array = []
	for c in sk.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var nm := str(mi.name)
		# 体の面：もとの体（頭・首・腕）と、服の下で消されている胴・脚・足を、Tシャツ・ズボン・くつの形で補う
		if nm == "Human" or BODY_PARTS.has(nm.trim_prefix("Human_")):
			bodies.append(mi)
			continue
		var ok := false
		for k in keep:
			if nm == "Human_" + str(k) or nm.begins_with("Human_" + str(k)):
				ok = true
		if not ok:
			sk.remove_child(mi)
			mi.free()
			continue
		_deform_instance(mi, sk, rest, tails, look)
		tris += _tri_count(mi.mesh)
	if bodies.is_empty():
		return -1
	var mats: Array = []
	var keys := {}
	for mi in bodies:
		var base_mat: Material
		if str(mi.name) == "Human":
			base_mat = _skin_material(mi.mesh.surface_get_material(0), look)
		else:
			# もとの体の肌の画像の平均の色（SKIN_TEX_AVG）をかけて、腕・顔の肌と同じ色にそろえる
			var sc := Color(str(look.get("skin", "#ffffff"))) * SKIN_TEX_AVG
			base_mat = _material(sc.to_html(false), 0.0, 0.75, 0.0, "none")
		mats.append(base_mat)
		tris += _build_body(mi, sk, rest, tails, look, mats, keys, mats.size() - 1)
	tris += _attach_parts(sk, rest, look.get("parts", []))
	return tris


# ---------------------------------------------------------------- 骨の情報

static func _rests(sk: Skeleton3D) -> Array:
	var out: Array = []
	out.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var t := sk.get_bone_rest(i)
		var p := sk.get_bone_parent(i)
		if p >= 0:
			t = (out[p] as Transform3D) * t
		out[i] = t
	return out


## 骨のはし（子の骨の位置）。子がなければ、骨の向き（+Y）に 0.08 のばした所
static func _tails(sk: Skeleton3D, rest: Array) -> Array:
	var out: Array = []
	out.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var kids := sk.get_bone_children(i)
		var me := group_of(sk.get_bone_name(i))
		var tail := Vector3.INF
		for k in kids:
			var kn := sk.get_bone_name(k)
			# 指より手首、顔の小骨より頭、など：同じ部位の続きを優先
			if group_of(kn) == me or tail == Vector3.INF:
				tail = (rest[k] as Transform3D).origin
				if group_of(kn) == me:
					break
		if tail == Vector3.INF:
			var t := rest[i] as Transform3D
			tail = t.origin + t.basis.y.normalized() * 0.08
		out[i] = tail
	return out


static func _bind_bones(mi: MeshInstance3D, sk: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	var skin := mi.skin
	if skin == null:
		return out
	for b in skin.get_bind_count():
		var nm := str(skin.get_bind_name(b))
		var bi := sk.find_bone(nm) if nm != "" else skin.get_bind_bone(b)
		out.append(bi)
	return out


# ---------------------------------------------------------------- 体格

## 1つの頂点の新しい位置（骨の重みでまぜる）。spec は {部位: 数 または [横, 奥]}、head は頭の大きさ
static func _deform_point(v: Vector3, bones: PackedInt32Array, weights: PackedFloat32Array, base: int, bind: PackedInt32Array,
		sk: Skeleton3D, rest: Array, tails: Array, spec: Dictionary, head_scale: float, head_pivot: Vector3) -> Vector3:
	var disp := Vector3.ZERO
	for k in 4:
		var w := weights[base + k]
		if w <= 0.0:
			continue
		var bi := bind[bones[base + k]] if bones[base + k] < bind.size() else -1
		if bi < 0:
			continue
		var g := group_of(sk.get_bone_name(bi))
		if g == "head":
			if absf(head_scale - 1.0) > 0.0001:
				disp += w * ((head_pivot + (v - head_pivot) * head_scale) - v)
			continue
		if not spec.has(g):
			continue
		var a := (rest[bi] as Transform3D).origin
		var b: Vector3 = tails[bi]
		var p := _closest_on(v, a, b)
		var off := v - p
		var f: Variant = spec[g]
		var nv: Vector3
		if f is Array:
			nv = p + Vector3(off.x * float(f[0]), off.y, off.z * float(f[1]))
		else:
			nv = p + off * float(f)
		disp += w * (nv - v)
	return v + disp


static func _closest_on(v: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-8:
		return a
	return a + ab * clampf((v - a).dot(ab) / l2, 0.0, 1.0)


static func _head_pivot(sk: Skeleton3D, rest: Array) -> Vector3:
	var h := sk.find_bone("head")
	return (rest[h] as Transform3D).origin if h >= 0 else Vector3(0, 1.8, 0)


## 目・まゆ・髪など、体以外の形も、同じ体格・頭の大きさに合わせる
static func _deform_instance(mi: MeshInstance3D, sk: Skeleton3D, rest: Array, tails: Array, look: Dictionary) -> void:
	var bind := _bind_bones(mi, sk)
	var src := mi.mesh
	var out := ArrayMesh.new()
	var spec: Dictionary = look.get("bulk", {})
	var hs := float(look.get("head_scale", 1.0))
	var piv := _head_pivot(sk, rest)
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nv := PackedVector3Array()
		nv.resize(v.size())
		for i in v.size():
			nv[i] = _deform_point(v[i], bo, we, i * 4, bind, sk, rest, tails, spec, hs, piv)
		arr[Mesh.ARRAY_VERTEX] = nv
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := src.surface_get_material(s)
		if m is StandardMaterial3D and look.has("tint_" + str(mi.name).trim_prefix("Human_")):
			m = (m as StandardMaterial3D).duplicate()
			(m as StandardMaterial3D).albedo_color = Color(str(look["tint_" + str(mi.name).trim_prefix("Human_")]))
		out.surface_set_material(s, m)
	mi.mesh = out


# ---------------------------------------------------------------- 体（塗り・重ね着）

static func _build_body(mi: MeshInstance3D, sk: Skeleton3D, rest: Array, tails: Array, look: Dictionary, mats: Array, mat_keys: Dictionary, base_id: int) -> int:
	var bind := _bind_bones(mi, sk)
	var src := mi.mesh
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var vc := v.size()
	var mname := "body" if str(mi.name) == "Human" else ("shoes" if str(mi.name).contains("shoes") else "suit")
	# 頂点ごとの部位（いちばん重い部位）
	var dom := PackedStringArray()
	dom.resize(vc)
	var dom_bone := PackedInt32Array()
	dom_bone.resize(vc)
	for i in vc:
		var sums := {}
		var heavy := -1
		var heavy_w := -1.0
		for k in 4:
			var w := we[i * 4 + k]
			if w <= 0.0:
				continue
			var bi := bind[bo[i * 4 + k]] if bo[i * 4 + k] < bind.size() else -1
			if bi < 0:
				continue
			var g := group_of(sk.get_bone_name(bi))
			sums[g] = float(sums.get(g, 0.0)) + w
			if w > heavy_w:
				heavy_w = w
				heavy = bi
		dom_bone[i] = heavy
		var best := "head"
		var bw := -1.0
		for g in sums:
			if float(sums[g]) > bw:
				bw = float(sums[g])
				best = g
		dom[i] = best
	# 頂点の、いちばん重い骨の軸から外への向き（線の模様を、体の外側・前などに置くため）
	var rad := PackedVector3Array()
	rad.resize(vc)
	for i in vc:
		var bi := dom_bone[i]
		if bi < 0:
			continue
		var a := (rest[bi] as Transform3D).origin
		rad[i] = (v[i] - _closest_on(v[i], a, tails[bi])).normalized()
	# 体格
	var spec: Dictionary = look.get("bulk", {})
	var hs := float(look.get("head_scale", 1.0))
	var piv := _head_pivot(sk, rest)
	var dv := PackedVector3Array()
	dv.resize(vc)
	for i in vc:
		dv[i] = _deform_point(v[i], bo, we, i * 4, bind, sk, rest, tails, spec, hs, piv)
	# 三角形ごとの色（材質の番号）。0 は肌。塗りの決まりを順に見て、最後に当たった物
	var tri_n := idx.size() / 3
	var tri_mat := PackedInt32Array()
	tri_mat.resize(tri_n)
	tri_mat.fill(base_id)
	var hidden := PackedByteArray()
	hidden.resize(tri_n)
	var paint: Array = look.get("paint", [])
	var rule_mats: Array = []
	for r in paint:
		# 色 "skin" は、その面のもとの肌（腕・顔と同じ肌の材質）
		rule_mats.append([base_id] if str(r.get("color", "")) == "skin" else _rule_material_ids(r, mats, mat_keys))
	for t in tri_n:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var info := _tri_info(v, nrm, rad, dom, a, b, c)
		info["m"] = mname
		for ri in paint.size():
			var r: Dictionary = paint[ri]
			if _match(r, info):
				tri_mat[t] = _pick_color(r, rule_mats[ri], info)
	# 重ね着
	var shells: Array = look.get("shells", [])
	var shell_tris: Array = []  # [{mat, tris:[t...], rule}]
	for r in shells:
		var ids := _rule_material_ids(r, mats, mat_keys)
		var list := {}
		for t in tri_n:
			var info := _tri_info(v, nrm, rad, dom, idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2])
			info["m"] = mname
			if _match(r, info):
				var m := _pick_color(r, ids, info)
				if not list.has(m):
					list[m] = []
				(list[m] as Array).append(t)
				if bool(r.get("hide_under", false)):
					hidden[t] = 1
		shell_tris.append({"rule": r, "lists": list})
	# 消す面（hide）：もとの体と服の形が重なる所など
	for r in look.get("hide", []):
		for t in tri_n:
			if hidden[t] == 1:
				continue
			var info := _tri_info(v, nrm, rad, dom, idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2])
			info["m"] = mname
			if _match(r, info):
				hidden[t] = 1
	# 面を作る（使う頂点だけを持つ、材質ごとの面）
	var out := ArrayMesh.new()
	var total := 0
	var by_mat := {}
	for t in tri_n:
		if hidden[t] == 1:
			continue
		var m := tri_mat[t]
		if not by_mat.has(m):
			by_mat[m] = []
		(by_mat[m] as Array).append(t)
	var ms: Array = by_mat.keys()
	ms.sort()
	for m in ms:
		total += _add_surface(out, arr, dv, nrm, idx, by_mat[m], mats[m], 0.0, {}, bo, we, bind, sk, rest, tails, v)
	for st in shell_tris:
		var r: Dictionary = st["rule"]
		var lists: Dictionary = st["lists"]
		for m in lists:
			total += _add_surface(out, arr, dv, nrm, idx, lists[m], mats[m], float(r.get("offset", 0.01)), r.get("puff", {}), bo, we, bind, sk, rest, tails, v)
	mi.mesh = out
	return total


## 塗りの決まり r の色の材質の番号（しま模様なら複数）
static func _rule_material_ids(r: Dictionary, mats: Array, keys: Dictionary) -> Array:
	var ids: Array = []
	var cols: Array = []
	if r.has("stripes"):
		cols = (r["stripes"] as Dictionary).get("colors", [])
	else:
		cols = [r.get("color", "#888888")]
	for col in cols:
		var key := "%s|%s|%s|%s|%s" % [col, r.get("metallic", 0.0), r.get("roughness", 0.8), r.get("emission", 0.0), r.get("tex", "")]
		if not keys.has(key):
			keys[key] = mats.size()
			mats.append(_material(str(col), float(r.get("metallic", 0.0)), float(r.get("roughness", 0.8)), float(r.get("emission", 0.0)), str(r.get("tex", ""))))
		ids.append(keys[key])
	return ids


static func _pick_color(r: Dictionary, ids: Array, info: Dictionary) -> int:
	if ids.size() <= 1 or not r.has("stripes"):
		return ids[0]
	var s: Dictionary = r["stripes"]
	var c: Vector3 = info["c"]
	var axis := str(s.get("axis", "x"))
	var x := 0.0
	match axis:
		"y":
			x = c.y
		"z":
			x = c.z
		"angle":
			x = atan2(c.x, c.z) / TAU
		_:
			x = c.x
	var k := int(floor((x + float(s.get("offset", 0.0))) / float(s.get("period", 0.1))))
	return ids[posmod(k, ids.size())]


static func _tri_info(v: PackedVector3Array, nrm: PackedVector3Array, rad: PackedVector3Array, dom: PackedStringArray, a: int, b: int, c: int) -> Dictionary:
	var cen := (v[a] + v[b] + v[c]) / 3.0
	var n := (nrm[a] + nrm[b] + nrm[c]).normalized()
	var r := (rad[a] + rad[b] + rad[c]).normalized()
	return {"c": cen, "n": n, "r": r, "g": [dom[a], dom[b], dom[c]]}


## 範囲の決まり：rx_out・rz・ry（骨の軸から外への向き。rx_out は体の外側が +）、groups（3頂点のうち2つ以上がこの部位）、y・x・z・x_abs（中心の座標の範囲）、nz・ny（向きの範囲）、
## side（"L" は +X 側、"R" は −X 側）、any（どれかに当たる）、not（当たらない）、mesh（"body"・"suit"・"shoes" のどれの面か）
static func _match(r: Dictionary, info: Dictionary) -> bool:
	if r.has("mesh") and not (r["mesh"] as Array).has(info.get("m", "")):
		return false
	if r.has("groups"):
		var gs: Array = r["groups"]
		var hit := 0
		for g in info["g"]:
			if gs.has(g):
				hit += 1
		if hit < 2:
			return false
	var c: Vector3 = info["c"]
	var n: Vector3 = info["n"]
	if not _in(r, "y", c.y) or not _in(r, "x", c.x) or not _in(r, "z", c.z) or not _in(r, "x_abs", absf(c.x)):
		return false
	if not _in(r, "nz", n.z) or not _in(r, "ny", n.y) or not _in(r, "nx_out", n.x * signf(c.x + 0.00001)):
		return false
	var rd: Vector3 = info.get("r", Vector3.ZERO)
	if not _in(r, "rx_out", rd.x * signf(c.x + 0.00001)) or not _in(r, "rz", rd.z) or not _in(r, "ry", rd.y):
		return false
	if r.has("side"):
		if str(r["side"]) == "L" and c.x < 0.0:
			return false
		if str(r["side"]) == "R" and c.x > 0.0:
			return false
	if r.has("ellipse"):
		# 体の前などの楕円の中：{"center":[x,y], "r":[rx,ry], "plane":"xy"}
		var e: Dictionary = r["ellipse"]
		var ce: Array = e["center"]
		var rr: Array = e["r"]
		var px := absf(c.x) if bool(e.get("mirror", false)) else c.x
		var q := Vector2((px - float(ce[0])) / float(rr[0]), (c.y - float(ce[1])) / float(rr[1]))
		if q.length() > 1.0:
			return false
	if r.has("any"):
		var ok := false
		for sub in r["any"]:
			if _match(sub, info):
				ok = true
				break
		if not ok:
			return false
	if r.has("not"):
		for sub in r["not"]:
			if _match(sub, info):
				return false
	return true


static func _in(r: Dictionary, key: String, x: float) -> bool:
	if not r.has(key):
		return true
	var lim: Array = r[key]
	return x >= float(lim[0]) and x <= float(lim[1])


## 選んだ三角形 tris を、1つの面として out に足す。offset>0 なら外へ出した重ね着（puff で骨のまわりにふくらませる）
static func _add_surface(out: ArrayMesh, arr: Array, dv: PackedVector3Array, nrm: PackedVector3Array, idx: PackedInt32Array, tris: Array,
		mat: Material, offset: float, puff: Dictionary, bo: PackedInt32Array, we: PackedFloat32Array, bind: PackedInt32Array,
		sk: Skeleton3D, rest: Array, tails: Array, orig: PackedVector3Array) -> int:
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var nb := PackedInt32Array()
	var nw := PackedFloat32Array()
	var ni := PackedInt32Array()
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	for t in tris:
		for k in 3:
			var vi := idx[t * 3 + k]
			if not remap.has(vi):
				remap[vi] = nv.size()
				var p := dv[vi]
				if not puff.is_empty():
					p = _deform_point(p, bo, we, vi * 4, bind, sk, rest, tails, puff, 1.0, Vector3.ZERO)
				nv.append(p + nrm[vi] * offset)
				nn.append(nrm[vi])
				nuv.append(uv[vi] if vi < uv.size() else Vector2.ZERO)
				for j in 4:
					nb.append(bo[vi * 4 + j])
					nw.append(we[vi * 4 + j])
			ni.append(remap[vi])
	if ni.is_empty():
		return 0
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = nv
	a[Mesh.ARRAY_NORMAL] = nn
	a[Mesh.ARRAY_TEX_UV] = nuv
	a[Mesh.ARRAY_BONES] = nb
	a[Mesh.ARRAY_WEIGHTS] = nw
	a[Mesh.ARRAY_INDEX] = ni
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	out.surface_set_material(out.get_surface_count() - 1, mat)
	return ni.size() / 3


static func _skin_material(src: Material, look: Dictionary) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = Color(str(look.get("skin", "#ffffff")))
	return m


static func _material(col: String, metallic: float, rough: float, emission: float, tex: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col)
	mat.metallic = metallic
	mat.roughness = rough
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(col)
		mat.emission_energy_multiplier = emission
	StyleFx.style_material(mat, "" if tex == "none" else StyleFx.texture_for(metallic, tex))
	StyleFx.apply_outline(mat, float(StyleFx.config().get("outline_width", 0.014)))
	return mat


static func _tri_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ---------------------------------------------------------------- 部品

## parts を骨に付ける（Item_look_* の BoneAttachment3D。あとで character_view.bake_items が1つにまとめる）。三角形の数を返す
static func _attach_parts(sk: Skeleton3D, rest: Array, parts: Array) -> int:
	var holders := {}
	var tris := 0
	var all: Array = []
	for p in parts:
		all.append(p)
		if bool((p as Dictionary).get("mirror", false)):
			all.append(mirror_part(p))
	for p in all:
		var part: Dictionary = p
		var bone := str(part.get("bone", "spine01"))
		var bi := sk.find_bone(bone)
		if bi < 0:
			continue
		if not holders.has(bone):
			var h := BoneAttachment3D.new()
			h.name = "Item_look_" + bone.replace(".", "_")
			h.bone_name = bone
			sk.add_child(h)
			holders[bone] = h
		var mesh := make_part_mesh(part)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var inv := (rest[bi] as Transform3D).affine_inverse()
		mi.transform = inv * part_transform(part)
		(holders[bone] as Node3D).add_child(mi)
		tris += _tri_count(mesh)
	return tris


## 左右反対の部品（x の符号を逆に、骨の .L と .R を入れかえる）
static func mirror_part(p: Dictionary) -> Dictionary:
	var q := p.duplicate(true)
	q.erase("mirror")
	var bone := str(q.get("bone", ""))
	if bone.ends_with(".L"):
		q["bone"] = bone.trim_suffix(".L") + ".R"
	elif bone.ends_with(".R"):
		q["bone"] = bone.trim_suffix(".R") + ".L"
	for key in ["center", "from", "to"]:
		if q.has(key):
			q[key][0] = -float(q[key][0])
	if q.has("points"):
		for pt in q["points"]:
			pt[0] = -float(pt[0])
	if q.has("rings"):
		for rg in q["rings"]:
			rg[0][0] = -float(rg[0][0])
	if q.has("rotation_deg"):
		q["rotation_deg"][1] = -float(q["rotation_deg"][1])
		q["rotation_deg"][2] = -float(q["rotation_deg"][2])
	if q.has("points2d") and bool(q.get("mirror_2d", true)):
		pass
	q["_mirrored"] = true
	return q


## 部品の置き場所（モデル座標）。loft・tube・rod は点をそのまま使うので、ここでは center と回転だけ
static func part_transform(part: Dictionary) -> Transform3D:
	var shape := str(part.get("shape", "box"))
	if shape in ["loft", "tube", "rod"]:
		return Transform3D.IDENTITY
	var c: Array = part.get("center", [0, 0, 0])
	var rot: Array = part.get("rotation_deg", [0, 0, 0])
	var b := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(float(rot[2]))))
	if bool(part.get("_mirrored", false)) and shape == "extrude":
		b = b * Basis.from_scale(Vector3(-1, 1, 1))
	var sq: Array = part.get("squash", [1, 1, 1])
	if shape in ["sphere", "torus", "extrude", "box"] and sq.size() == 3:
		b = b * Basis.from_scale(Vector3(float(sq[0]), float(sq[1]), float(sq[2])))
	return Transform3D(b, Vector3(float(c[0]), float(c[1]), float(c[2])))


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## 部品の形（ArrayMesh、印 "part" つき。材質つき）
static func make_part_mesh(part: Dictionary) -> ArrayMesh:
	var mat := _material(str(part.get("color", "#cccccc")), float(part.get("metallic", 0.0)), float(part.get("roughness", 0.8)),
		float(part.get("emission", 0.0)), str(part.get("tex", "")))
	if bool(part.get("double", false)):
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var segs := int(part.get("segs", 12))
	match str(part.get("shape", "box")):
		"loft":
			var rings: Array = []
			for rg in part["rings"]:
				rings.append([_v3(rg[0]), float(rg[1]), float(rg[2])])
			var side_a: Array = part.get("side", [1, 0, 0])
			return ShapeKit.loft(rings, mat, segs, _v3(side_a), deg_to_rad(float(part.get("arc_from", 0.0))),
				deg_to_rad(float(part.get("arc_to", 360.0))), bool(part.get("caps", true)))
		"tube":
			var pts: Array = []
			for pt in part["points"]:
				pts.append(_v3(pt))
			if bool(part.get("smooth", false)) and pts.size() == 3:
				pts = ShapeKit.curve(pts[0], pts[1], pts[2], int(part.get("steps", 6)))
			return ShapeKit.tube(pts, float(part["r0"]), float(part["r1"]), mat, segs, float(part.get("squash", 1.0)))
		"rod":
			var sq: Array = part.get("squash", [1, 1])
			var a := _v3(part["from"])
			var b := _v3(part["to"])
			var r0 := float(part["r0"])
			var r1 := float(part["r1"])
			return ShapeKit.loft([[a, r0 * float(sq[0]), r0 * float(sq[1])], [b, r1 * float(sq[0]), r1 * float(sq[1])]], mat, segs, _v3(part.get("side", [1, 0, 0])))
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = float(part["r"])
			sm.height = float(part["r"]) * 2.0
			sm.radial_segments = segs
			sm.rings = maxi(segs / 2, 4)
			return _from_primitive(sm, mat)
		"box":
			var bm := BoxMesh.new()
			bm.size = _v3(part["size"])
			return _from_primitive(bm, mat)
		"torus":
			var tm := TorusMesh.new()
			var R := float(part["R"])
			var r := float(part["r"])
			tm.inner_radius = R - r
			tm.outer_radius = R + r
			tm.rings = segs * 2
			tm.ring_segments = 6
			return _from_primitive(tm, mat)
		"extrude":
			return _extrude(part.get("points2d", []), float(part.get("depth", 0.02)), mat, float(part.get("bevel", 0.0)))
	return null


static func _from_primitive(pm: PrimitiveMesh, mat: Material) -> ArrayMesh:
	var arr := pm.get_mesh_arrays()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	m.set_meta("part", true)
	return m


## 平らな形（多角形）を、厚み depth で押し出す。面は XY、厚みは Z（−depth/2〜+depth/2）。盾・羽根・ハートなど
static func _extrude(pts2: Array, depth: float, mat: Material, bevel: float) -> ArrayMesh:
	var poly := PackedVector2Array()
	for p in pts2:
		poly.append(Vector2(float(p[0]), float(p[1])))
	if poly.size() < 3:
		return null
	if not Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return null
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var h := depth * 0.5
	# 表（+Z）と裏（−Z）
	for side in [1.0, -1.0]:
		var base := v.size()
		for p in poly:
			v.append(Vector3(p.x, p.y, h * side))
			n.append(Vector3(0, 0, side))
			uv.append(p)
		for i in range(0, tri.size(), 3):
			if side > 0.0:
				idx.append_array([base + tri[i], base + tri[i + 2], base + tri[i + 1]])
			else:
				idx.append_array([base + tri[i], base + tri[i + 1], base + tri[i + 2]])
	# 側面
	var cnt := poly.size()
	for i in cnt:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % cnt]
		var e := (p1 - p0).normalized()
		var out := Vector3(e.y, -e.x, 0.0)
		var base2 := v.size()
		v.append_array([Vector3(p0.x, p0.y, h), Vector3(p1.x, p1.y, h), Vector3(p1.x, p1.y, -h), Vector3(p0.x, p0.y, -h)])
		for k in 4:
			n.append(out)
			uv.append(Vector2.ZERO)
		idx.append_array([base2, base2 + 1, base2 + 2, base2, base2 + 2, base2 + 3])
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

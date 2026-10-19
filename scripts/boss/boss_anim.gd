extends RefCounted
## ボスの動き。剣士と同じ動き素材（hero_ual.res。Quaternius の人の動き）を「時刻を指定して」取り出し、まぜて、骨に入れる。
## AnimationPlayer は使わない：攻撃の動きを、攻撃が始まってからの秒（u）で決めるため（予告・当たりと、振る瞬間がぴったり合う）。
## 動き素材にない動き（ひねり・前かがみ・腕を広げる など）は、骨の回転を「足し算」して作る（モデルの座標で書く）。
##
## 姿勢の形：{"r": Array[Quaternion]（骨ごとの回転。親から見た向き）, "p": Vector3（根の骨の位置）}

const ProceduralAnims := preload("res://scripts/characters/procedural_anims.gd")

var sk: Skeleton3D
var lib: AnimationLibrary
var n := 0
var rest: Array[Transform3D] = []
var rest_q: Array[Quaternion] = []  ## 骨ごとの休みの回転（毎回作らないよう、前もって）
var _chain_cache := {}  ## 骨の番号の組 → 根からその骨までの骨（番号の小さい順）
var parents: PackedInt32Array = PackedInt32Array()
var root_bi := 0
var s2m := Basis.IDENTITY  ## 骨の空間 → モデルの空間の回転
var m2s := Basis.IDENTITY
var tracks := {}  ## 動きの名前 → {"rot": {骨の番号: 道の番号}, "pos": 道の番号 か -1, "len": 長さ, "loop": bool}
var driven: PackedInt32Array = PackedInt32Array()  ## 毎コマ書きこむ骨
var upper := {}  ## 上半身の骨（歩きながら振るとき、ここだけ攻撃の動き）


func setup(skeleton: Skeleton3D, library: AnimationLibrary, model_root: Node) -> void:
	sk = skeleton
	lib = library
	n = sk.get_bone_count()
	rest.resize(n)
	rest_q.resize(n)
	parents.resize(n)
	for i in n:
		rest[i] = sk.get_bone_rest(i)
		rest_q[i] = rest[i].basis.get_rotation_quaternion()
		parents[i] = sk.get_bone_parent(i)
	root_bi = maxi(0, sk.find_bone("root"))
	var t := Transform3D.IDENTITY
	var node: Node = sk
	while node != null and node != model_root:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	s2m = t.basis.orthonormalized()
	m2s = s2m.inverse()
	var used := {}
	for name in lib.get_animation_list():
		var a := lib.get_animation(name)
		var info := {"rot": {}, "pos": -1, "len": a.length, "loop": a.loop_mode != Animation.LOOP_NONE}
		for i in a.get_track_count():
			var bone := str(a.track_get_path(i)).get_slice(":", 1)
			var bi := sk.find_bone(bone)
			if bi < 0:
				continue
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				info["rot"][bi] = i
				used[bi] = true
			elif a.track_get_type(i) == Animation.TYPE_POSITION_3D and bi == root_bi:
				info["pos"] = i
		tracks[str(name)] = info
	for bname in ["spine04", "spine02", "neck02", "upperarm02.L", "upperarm02.R"]:
		var bi2 := sk.find_bone(bname)
		if bi2 >= 0:
			used[bi2] = true
	used[root_bi] = true
	for i in n:
		assert(parents[i] < i, "骨の番号は、親が先（_chain_of の並べ方の前提）")
	var keys := used.keys()
	keys.sort()
	driven = PackedInt32Array(keys)
	# 上半身：spine03 とその下（腕・首・頭）
	var top := sk.find_bone("spine03")
	for i in n:
		var p := i
		while p >= 0:
			if p == top:
				upper[i] = true
				break
			p = parents[p]


func has_clip(name: String) -> bool:
	return tracks.has(name)


func clip_len(name: String) -> float:
	return float(tracks[name]["len"]) if tracks.has(name) else 1.0


## 休みの姿勢
func rest_pose() -> Dictionary:
	return {"r": rest_q.duplicate(), "p": rest[root_bi].origin}


## 動き name の、t 秒の姿勢。くり返す動きは、t を長さで割ったあまりにする
func sample(name: String, t: float) -> Dictionary:
	var pose := rest_pose()
	if not tracks.has(name):
		return pose
	var info: Dictionary = tracks[name]
	var a := lib.get_animation(name)
	var len := float(info["len"])
	var tt := fposmod(t, len) if bool(info["loop"]) else clampf(t, 0.0, len)
	var r: Array[Quaternion] = pose["r"]
	var rot: Dictionary = info["rot"]
	for bi in rot:
		r[bi] = a.rotation_track_interpolate(int(rot[bi]), tt)
	if int(info["pos"]) >= 0:
		var p: Vector3 = a.position_track_interpolate(int(info["pos"]), tt)
		# その場で動く（前後左右に流れないように、根の位置は高さだけ使う）
		var p0: Vector3 = rest[root_bi].origin
		pose["p"] = Vector3(p0.x, p.y, p0.z)
	return pose


## 2つの姿勢をまぜる（w=0 で a、1 で b）。only があれば、その骨だけ b に寄せる
func blend(a: Dictionary, b: Dictionary, w: float, only: Dictionary = {}) -> Dictionary:
	if w <= 0.0:
		return a
	if w >= 1.0 and only.is_empty():
		return b
	var ra: Array[Quaternion] = a["r"]
	var rb: Array[Quaternion] = b["r"]
	var r: Array[Quaternion] = ra.duplicate()
	for bi in driven:
		if only.is_empty() or only.has(bi):
			r[bi] = ra[bi].slerp(rb[bi], w)
	var p: Vector3 = a["p"]
	if only.is_empty():
		p = p.lerp(b["p"], w)
	return {"r": r, "p": p}


## 骨の回転を足す。deltas：{骨の名前: モデルの座標の回転(Basis)}。offset：根の位置のずれ（モデルの座標）。
## 親から順に、全体の向きを計算し、その骨の全体の向きの前に回転をかける（モデルの座標で「前へ曲げる」などと書ける）
func add(pose: Dictionary, deltas: Dictionary, offset: Vector3 = Vector3.ZERO) -> Dictionary:
	if deltas.is_empty() and offset == Vector3.ZERO:
		return pose
	var by_bi := {}
	for name in deltas:
		var bi := bone_index(str(name))
		if bi >= 0:
			by_bi[bi] = m2s * (deltas[name] as Basis) * s2m
	var r: Array[Quaternion] = (pose["r"] as Array).duplicate()
	# 回す骨と、その親たち（根まで）だけを、親から順に計算する（全部の骨を計算すると重い）
	var bones := _chain_of(by_bi.keys())
	var g := {}
	for i in bones:
		var p := parents[i]
		var local := Basis(r[i])
		var gb := local if p < 0 else (g[p] as Basis) * local
		if by_bi.has(i):
			gb = (by_bi[i] as Basis) * gb
			r[i] = (gb if p < 0 else (g[p] as Basis).inverse() * gb).get_rotation_quaternion()
		g[i] = gb
	return {"r": r, "p": (pose["p"] as Vector3) + m2s * offset}


var _bi_cache := {}
func bone_index(name: String) -> int:
	if not _bi_cache.has(name):
		_bi_cache[name] = sk.find_bone(name)
	return int(_bi_cache[name])


## 骨たちと、その親たち（根まで）を、番号の小さい順（親が先）に並べたもの
func _chain_of(bis: Array) -> Array:
	var key := str(bis)
	if _chain_cache.has(key):
		return _chain_cache[key]
	var set := {}
	for bi in bis:
		var p := int(bi)
		while p >= 0 and not set.has(p):
			set[p] = true
			p = parents[p]
	var out := set.keys()
	out.sort()
	_chain_cache[key] = out
	return out


## 姿勢を骨に書きこむ
func apply(pose: Dictionary) -> void:
	var r: Array[Quaternion] = pose["r"]
	for bi in driven:
		sk.set_bone_pose_rotation(bi, r[bi])
	sk.set_bone_pose_position(root_bi, pose["p"])


## 骨の全体の位置（モデルの座標。いまの姿勢から計算する）
func bone_model_pos(pose: Dictionary, bone: String) -> Vector3:
	var bi := bone_index(bone)
	if bi < 0:
		return Vector3.ZERO
	var chain: Array = []
	var p := bi
	while p >= 0:
		chain.push_front(p)
		p = parents[p]
	var t := Transform3D.IDENTITY
	var r: Array[Quaternion] = pose["r"]
	for i in chain:
		var origin: Vector3 = pose["p"] if i == root_bi else rest[i].origin
		t = t * Transform3D(Basis(r[i]), origin)
	return s2m * t.origin


## 区切りごとに、攻撃の時刻 u を動きの時刻へ変える。keys：[[u0, c0], [u1, c1], ...]（u は増える順）。区切りの中は、なめらかに
static func remap(u: float, keys: Array) -> float:
	if keys.is_empty():
		return 0.0
	if u <= float(keys[0][0]):
		return float(keys[0][1])
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if u <= float(b[0]):
			var f := (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			if a.size() > 2 and str(a[2]) == "linear":
				return lerpf(float(a[1]), float(b[1]), f)
			return lerpf(float(a[1]), float(b[1]), f * f * (3.0 - 2.0 * f))
	return float(keys[keys.size() - 1][1])


# ---- 足し算の回転（モデルの座標。前が +Z、上が +Y、キャラの左が +X） ----

static func fwd(a: float) -> Basis:
	return ProceduralAnims.fwd(a)


static func lean(a: float) -> Basis:
	return ProceduralAnims.lean(a)


static func yaw(a: float) -> Basis:
	return ProceduralAnims.yaw(a)


## 横へ倒す（+ で、キャラの左へ倒れる＝頭が +X へ）
static func roll(a: float) -> Basis:
	return Basis(Vector3.FORWARD, deg_to_rad(a))


## 腕を横へ上げる（side="L" は +X へ、"R" は -X へ。a 度）
static func raise_side(side: String, a: float) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(a) * (1.0 if side == "L" else -1.0))

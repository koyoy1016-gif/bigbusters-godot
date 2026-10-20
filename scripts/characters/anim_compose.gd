extends RefCounted
## 版78：いまある動き（hero_ual.res の13こ）を切り取って、つなぎ・くり返し・左右反対・骨のひねりを足して、
## キャラ専用の新しい動きを作る（新しい素材はいらない。剣士の必殺技と同じ考え方を広げた物）。
##
## spec（data/characters.json の built_anims の1つ。"segments" があるときに、この道具を使う）：
##   segments：[{anim: 元の動き, from: 元の秒, to: 元の秒, dur: 新しい長さ, mirror: 左右反対, ease: なめらかに}, ...]
##             を順につなぐ。to < from なら逆に流す。from == to なら、その姿勢で止まる（dur 秒）
##   repeat：segments を何回くり返すか（20連パンチなど）
##   blend：つなぎ目を、この秒数でなめらかにまぜる（0.06 など）
##   offsets：{骨の名前: [[新しい秒, [x度, y度, z度]], ...]} 骨をその角度だけ、さらにひねる（骨の向きを基準。間はなめらか）。
##            骨の名前の後ろに "*" があれば、左右の両方（.L と .R、R は反対の向き）
##   segments の1つに sym: "L" なら、右の骨は左の骨の左右反対（左右そろった姿勢。両腕を前へ、など）。"R" はその逆
##   segments の1つに arms_from: {anim, t} なら、腕・肩・手の骨だけ、その動きのその秒の姿勢にする（脚は元の動き）
##   aim：{骨: [[新しい秒, [x, y, z], 強さ], ...]} 骨（腕など）を、モデルの中のその向き（+Z が前、+Y が上、+X がキャラの左）へ向ける。
##        強さ 0 で元の動きのまま、1 でその向き。骨の名前の後ろに "*" で左右両方（右は x が反対）。skeleton が要る
##   root_lock：true なら、体の位置（root の移動）を、元の動きの最初の位置に止める（前へ進むのは actions.json の path で）
##   root_lift：[[秒, 上げる量], ...] 体（root）を上げ下げする。lift_units: "leg_abs" なら（版79）、低いほうの足首が床にくるように
##             腰の高さを毎コマ計算し（脚を曲げても、足が床からうかない・しずまない）、root_lift は「さらに上げる量（脚の長さ＝1）」

const FPS := 30.0
const SKEL := "Human_rig/Skeleton3D:"


static func is_compose(spec: Dictionary) -> bool:
	return spec.has("segments")


## 新しい動きの長さ
static func length_of(spec: Dictionary) -> float:
	var one := 0.0
	for s in spec.get("segments", []):
		one += float(s.get("dur", 0.2))
	return one * float(maxi(1, int(spec.get("repeat", 1))))


## 新しい秒 t のとき：どの区切りの、元の動きの何秒か。{seg, src_t, local}
static func locate(spec: Dictionary, t: float) -> Dictionary:
	var segs: Array = spec.get("segments", [])
	var one := 0.0
	for s in segs:
		one += float(s.get("dur", 0.2))
	if segs.is_empty() or one <= 0.0:
		return {}
	var reps := maxi(1, int(spec.get("repeat", 1)))
	var tt := clampf(t, 0.0, one * reps - 0.00001)
	var local := fmod(tt, one)
	var acc := 0.0
	for i in segs.size():
		var s: Dictionary = segs[i]
		var d := float(s.get("dur", 0.2))
		if local <= acc + d or i == segs.size() - 1:
			var k := clampf((local - acc) / maxf(d, 0.0001), 0.0, 1.0)
			if bool(s.get("ease", true)):
				k = smoothstep(0.0, 1.0, k)
			return {"seg": i, "src_t": lerpf(float(s.get("from", 0.0)), float(s.get("to", 0.0)), k), "k": k, "into": local - acc}
		acc += d
	return {}


## 左右の名前を入れかえる（upperarm01.L ↔ upperarm01.R）
static func mirror_name(bone: String) -> String:
	if bone.ends_with(".L"):
		return bone.trim_suffix(".L") + ".R"
	if bone.ends_with(".R"):
		return bone.trim_suffix(".R") + ".L"
	return bone


## 左右反対の回転（体の左右が鏡うつしの骨の場合：x はそのまま、y・z の向きが反対）
static var mirror_mode := 0


static func mirror_rot(q: Quaternion) -> Quaternion:
	match mirror_mode:
		1:
			return Quaternion(-q.x, q.y, -q.z, q.w)
		2:
			return Quaternion(-q.x, -q.y, q.z, q.w)
	return Quaternion(q.x, -q.y, -q.z, q.w)


## 元の動きの集まり lib から、spec の新しい動きを作る
static func build(lib: AnimationLibrary, spec: Dictionary, sk: Skeleton3D = null) -> Animation:
	var segs: Array = spec.get("segments", [])
	var out := Animation.new()
	var len := length_of(spec)
	out.length = len
	out.loop_mode = Animation.LOOP_LINEAR if bool(spec.get("loop", false)) else Animation.LOOP_NONE
	if segs.is_empty() or len <= 0.0:
		return out
	# 使う元の動きの、骨ごとの回転の線（と root の位置の線）
	var srcs := {}
	for s in segs:
		var names := [str(s.get("anim", ""))]
		if s.get("arms_from", null) is Dictionary:
			names.append(str(s["arms_from"].get("anim", "")))
		for an in names:
			if not srcs.has(an) and lib.has_animation(an):
				srcs[an] = lib.get_animation(an)
	var bones := {}
	for an in srcs:
		var a: Animation = srcs[an]
		for ti in a.get_track_count():
			if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				bones[str(a.track_get_path(ti)).trim_prefix(SKEL)] = true
	var offsets: Dictionary = _expand_offsets(spec.get("offsets", {}))
	for bn in offsets:
		bones[bn] = true
	var blend := float(spec.get("blend", 0.05))
	var frames := maxi(1, int(ceil(len * FPS)))
	var aims: Dictionary = _expand_aims(spec.get("aim", {}))
	if sk == null:
		aims = {}
	for bn in aims:
		bones[bn] = true
	# 1コマごとの、骨の回転（元の動き＋ひねり）
	var table := {}
	for bn in bones:
		var qs: Array = []
		for f in frames + 1:
			var t := minf(float(f) / FPS, len)
			var q := _sample_rot(srcs, segs, spec, str(bn), t, blend)
			if q == Quaternion.IDENTITY and sk != null and sk.find_bone(str(bn)) >= 0 and not _has_track(srcs, str(bn)):
				q = sk.get_bone_rest(sk.find_bone(str(bn))).basis.get_rotation_quaternion()
			if offsets.has(bn):
				q = q * _offset_at(offsets[bn], t)
			qs.append(q.normalized())
		table[bn] = qs
	# 腕を、ねらった向きへ向ける（aim。骨のつながりで計算する）
	if not aims.is_empty():
		var order: Array = aims.keys()
		order.sort_custom(func(a: String, b: String) -> bool: return sk.find_bone(a) < sk.find_bone(b))
		for f in frames + 1:
			var t := minf(float(f) / FPS, len)
			for bn in order:
				var bi := sk.find_bone(str(bn))
				if bi < 0:
					continue
				var key := _aim_at(aims[bn], t)
				var w := float(key[1])
				if w <= 0.001:
					continue
				var gp := _global_basis(sk, sk.get_bone_parent(bi), table, f)
				var q0: Quaternion = table[bn][f]
				var cur := (gp * Basis(q0)).y.normalized()
				var want: Vector3 = (key[0] as Vector3).normalized()
				var turn := Quaternion(cur, want) if cur.dot(want) > -0.999 else Quaternion(Vector3.FORWARD, PI)
				var ng := Basis(turn) * (gp * Basis(q0))
				var q1 := (gp.inverse() * ng).get_rotation_quaternion()
				table[bn][f] = q0.slerp(q1, w).normalized()
	# 版79：lift_units が "leg_abs" なら、足を床につける。plant（[[秒, "LR"/"L"/"R"/""], ...]）：
	#   "LR" 両足：床に届きにくいほうの足で腰の高さを決め、もう片方の脚は、ひざを曲げて床に下ろす（2本の骨の IK）
	#   "L"/"R" その足だけ床に（けり・片足立ち）、"" どちらも決めない（低いほうの足が床。跳ぶときは root_lift で上げる）
	var leg_abs := str(spec.get("lift_units", "")) == "leg_abs" and sk != null and sk.find_bone("root") >= 0 and sk.find_bone("foot.L") >= 0
	var rest_y := 0.0
	var leg_len := 1.0
	var foot_rest := 0.0
	var ground_rel: Array = []  ## コマごとの、床の高さ（root の原点から見た足首の高さ）
	if leg_abs:
		rest_y = sk.get_bone_global_rest(sk.find_bone("root")).origin.y
		foot_rest = sk.get_bone_global_rest(sk.find_bone("foot.L")).origin.y
		leg_len = maxf(0.1, rest_y - foot_rest)
		for side in ["L", "R"]:
			for bn in ["upperleg01." + side, "lowerleg01." + side]:
				if not table.has(bn) and sk.find_bone(bn) >= 0:
					var qs: Array = []
					for f in frames + 1:
						qs.append(sk.get_bone_rest(sk.find_bone(bn)).basis.get_rotation_quaternion())
					table[bn] = qs
					bones[bn] = true
		var plant: Array = spec.get("plant", [])
		for f in frames + 1:
			var t := minf(float(f) / FPS, len)
			var mode := str(_step_at(plant, t, ""))
			var fl := _bone_rel(sk, "foot.L", table, f).origin.y
			var fr := _bone_rel(sk, "foot.R", table, f).origin.y
			var g := minf(fl, fr)
			if mode == "L":
				g = fl
			elif mode == "R":
				g = fr
			elif mode == "LR":
				g = maxf(fl, fr)
				var low := "L" if fl < fr else "R"
				if absf(fl - fr) > 0.002 and absf(fl - fr) < leg_len * 0.45:
					_plant_leg(sk, low, table, f, g)
			ground_rel.append(g)
	for bn in bones:
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, NodePath(SKEL + str(bn)))
		out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		for f in frames + 1:
			out.rotation_track_insert_key(nt, minf(float(f) / FPS, len), table[bn][f])
	# 体の位置（root）：元の最初の区切りの位置で止めるか、元のまま流す
	var first: Animation = srcs.get(str(segs[0].get("anim", "")), null)
	if first != null:
		var rt := first.find_track(NodePath(SKEL + "root"), Animation.TYPE_POSITION_3D)
		if rt >= 0:
			var nt2 := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(nt2, NodePath(SKEL + "root"))
			for f in frames + 1:
				var t := minf(float(f) / FPS, len)
				var p: Vector3
				if bool(spec.get("root_lock", true)):
					p = first.position_track_interpolate(rt, float(segs[0].get("from", 0.0)))
				else:
					var loc := locate(spec, t)
					var sa: Animation = srcs.get(str(segs[int(loc["seg"])].get("anim", "")), first)
					var rti := sa.find_track(NodePath(SKEL + "root"), Animation.TYPE_POSITION_3D)
					p = sa.position_track_interpolate(rti, float(loc["src_t"])) if rti >= 0 else Vector3.ZERO
				var dy: Variant = spec.get("root_lift", null)
				if dy is Array:
					if leg_abs:
						# 低いほうの足首が、床（静止の足首の高さ）にくるように、腰の高さを決める。root_lift はさらに上げる量（跳ぶ・うく）
						p.y = foot_rest - float(ground_rel[f]) + leg_len * _scalar_at(dy, t)
					else:
						p.y += _scalar_at(dy, t)
				out.position_track_insert_key(nt2, t, p)
	return out


## 骨の、体（root の原点）から見た位置と向き。コマ f の骨の回転（table）と、骨の静止の位置から計算する
static func _bone_rel(sk: Skeleton3D, bone: String, table: Dictionary, f: int) -> Transform3D:
	var bi := sk.find_bone(bone)
	if bi < 0:
		return Transform3D.IDENTITY
	var chain: Array = []
	var c := bi
	while c >= 0:
		chain.push_front(c)
		c = sk.get_bone_parent(c)
	var g := Transform3D.IDENTITY
	for i in chain.size():
		var b: int = chain[i]
		var nm := sk.get_bone_name(b)
		var q: Quaternion = table[nm][f] if table.has(nm) else sk.get_bone_rest(b).basis.get_rotation_quaternion()
		var o := Vector3.ZERO if i == 0 else sk.get_bone_rest(b).origin
		g = g * Transform3D(Basis(q), o)
	return g


## 片方の脚を、ひざを曲げて（2本の骨の IK）、足首の高さを y にする（足首の前後・左右の位置は変えない）
static func _plant_leg(sk: Skeleton3D, side: String, table: Dictionary, f: int, y: float) -> void:
	var up := "upperleg01." + side
	var lo := "lowerleg01." + side
	var H := _bone_rel(sk, up, table, f).origin
	var K := _bone_rel(sk, lo, table, f).origin
	var F := _bone_rel(sk, "foot." + side, table, f).origin
	var a := H.distance_to(K)
	var bl := K.distance_to(F)
	var T := Vector3(F.x, y, F.z)
	var d := clampf(H.distance_to(T), absf(a - bl) + 0.001, a + bl - 0.001)
	var u0 := (F - H).normalized()
	var u1 := (T - H).normalized()
	# ひざの曲がる向き（いまの向きを保つ。まっすぐなら、体の前）
	var n := (K - H) - u0 * (K - H).dot(u0)
	n = n - u1 * n.dot(u1)
	if n.length() < 0.001:
		n = Vector3(0, 0, 1) - u1 * u1.z
	n = n.normalized()
	var x := (a * a - bl * bl + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var K2 := H + u1 * x + n * h
	var F2 := H + u1 * d
	_rotate_bone_to(sk, up, table, f, (K - H).normalized(), (K2 - H).normalized())
	var K3 := _bone_rel(sk, lo, table, f).origin
	var F3 := _bone_rel(sk, "foot." + side, table, f).origin
	_rotate_bone_to(sk, lo, table, f, (F3 - K3).normalized(), (F2 - K3).normalized())


## 骨 bone を、モデルの中で、向き from が向き to になるように回す（table を書きかえる）
static func _rotate_bone_to(sk: Skeleton3D, bone: String, table: Dictionary, f: int, from: Vector3, to: Vector3) -> void:
	if from.dot(to) > 0.99999:
		return
	var bi := sk.find_bone(bone)
	var pg := _bone_rel(sk, sk.get_bone_name(sk.get_bone_parent(bi)), table, f).basis if sk.get_bone_parent(bi) >= 0 else Basis.IDENTITY
	var q0: Quaternion = table[bone][f]
	var g := pg * Basis(q0)
	var ng := Basis(Quaternion(from, to)) * g
	table[bone][f] = (pg.inverse() * ng).get_rotation_quaternion().normalized()


## くり返しでない値の列 [[秒, 値], ...] の、秒 t の値（前の値のまま）
static func _step_at(keys: Array, t: float, def: Variant) -> Variant:
	var v: Variant = def
	for k in keys:
		if float(k[0]) <= t + 0.0001:
			v = k[1]
	return v


static func _has_track(srcs: Dictionary, bn: String) -> bool:
	for an in srcs:
		if (srcs[an] as Animation).find_track(NodePath(SKEL + bn), Animation.TYPE_ROTATION_3D) >= 0:
			return true
	return false


## 骨 bi の、モデルの中での向き（コマ f。表 table にある骨はその回転、ない骨は静止の回転）
static func _global_basis(sk: Skeleton3D, bi: int, table: Dictionary, f: int) -> Basis:
	var chain: Array = []
	var c := bi
	while c >= 0:
		chain.push_front(c)
		c = sk.get_bone_parent(c)
	var g := Basis.IDENTITY
	for b in chain:
		var nm := sk.get_bone_name(b)
		var q: Quaternion = table[nm][f] if table.has(nm) else sk.get_bone_rest(b).basis.get_rotation_quaternion()
		g = g * Basis(q)
	return g


## aim：{骨: [[秒, [x, y, z], 強さ0〜1], ...]}。骨の名前の後ろに "*" で左右両方（右は x が反対）
static func _expand_aims(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var name := str(k)
		if name.ends_with("*"):
			var base := name.trim_suffix("*")
			out[base + ".L"] = src[k]
			var mir: Array = []
			for key in src[k]:
				var d: Array = key[1]
				mir.append([key[0], [-float(d[0]), float(d[1]), float(d[2])], key[2] if (key as Array).size() > 2 else 1.0])
			out[base + ".R"] = mir
		else:
			out[name] = src[k]
	return out


## aim の、秒 t の [向き, 強さ]
static func _aim_at(keys: Array, t: float) -> Array:
	var dir := func(k: Array) -> Vector3: return Vector3(float(k[1][0]), float(k[1][1]), float(k[1][2]))
	var wt := func(k: Array) -> float: return float(k[2]) if k.size() > 2 else 1.0
	if t <= float(keys[0][0]):
		return [dir.call(keys[0]), wt.call(keys[0])]
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var k := smoothstep(0.0, 1.0, (t - float(keys[i - 1][0])) / maxf(0.0001, float(keys[i][0]) - float(keys[i - 1][0])))
			var d := (dir.call(keys[i - 1]) as Vector3).lerp(dir.call(keys[i]), k)
			return [d if d.length() > 0.01 else Vector3.UP, lerpf(wt.call(keys[i - 1]), wt.call(keys[i]), k)]
	var last: Array = keys[keys.size() - 1]
	return [dir.call(last), wt.call(last)]


static func _expand_offsets(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var name := str(k)
		if name.ends_with("*"):
			var base := name.trim_suffix("*")
			out[base + ".L"] = src[k]
			var mir: Array = []
			for key in src[k]:
				var e: Array = key[1]
				mir.append([key[0], [float(e[0]), -float(e[1]), -float(e[2])]])
			out[base + ".R"] = mir
		else:
			out[name] = src[k]
	return out


## 骨 bn の、新しい秒 t の回転（つなぎ目は blend 秒でまぜる）
static func _sample_rot(srcs: Dictionary, segs: Array, spec: Dictionary, bn: String, t: float, blend: float) -> Quaternion:
	var loc := locate(spec, t)
	if loc.is_empty():
		return Quaternion.IDENTITY
	var q := _rot_in(srcs, segs[int(loc["seg"])], bn, float(loc["src_t"]))
	var into := float(loc["into"])
	if blend > 0.0 and into < blend and (int(loc["seg"]) > 0 or int(spec.get("repeat", 1)) > 1) and t > blend:
		var prev := locate(spec, t - into - 0.0001)
		if not prev.is_empty():
			var qp := _rot_in(srcs, segs[int(prev["seg"])], bn, float(prev["src_t"]))
			q = qp.slerp(q, smoothstep(0.0, 1.0, into / blend))
	return q


const ARM_KEYS := ["arm", "clavicle", "shoulder", "wrist", "finger", "metacarpal"]


static func _is_arm(bn: String) -> bool:
	for k in ARM_KEYS:
		if bn.contains(k):
			return true
	return false


static func _rot_in(srcs: Dictionary, seg: Dictionary, bn: String, st: float) -> Quaternion:
	var sym := str(seg.get("sym", ""))
	if sym != "" and bn.ends_with("." + ("R" if sym == "L" else "L")):
		var s2 := seg.duplicate()
		s2.erase("sym")
		return mirror_rot(_rot_in(srcs, s2, mirror_name(bn), st))
	var af: Variant = seg.get("arms_from", null)
	if af is Dictionary and _is_arm(bn):
		var s3 := seg.duplicate()
		s3.erase("arms_from")
		s3["anim"] = str(af.get("anim", ""))
		s3["mirror"] = bool(af.get("mirror", false))
		return _rot_in(srcs, s3, bn, float(af.get("t", 0.0)))
	var a: Animation = srcs.get(str(seg.get("anim", "")), null)
	if a == null:
		return Quaternion.IDENTITY
	# mirror_arms：腕だけ左右反対（体の向きはそのまま。交互のパンチなど）
	var mir := bool(seg.get("mirror", false)) or (bool(seg.get("mirror_arms", false)) and _is_arm(bn))
	var look := mirror_name(bn) if mir else bn
	var ti := a.find_track(NodePath(SKEL + look), Animation.TYPE_ROTATION_3D)
	if ti < 0:
		return Quaternion.IDENTITY
	var q := a.rotation_track_interpolate(ti, st)
	return mirror_rot(q) if mir else q


static func _offset_at(keys: Array, t: float) -> Quaternion:
	var e := _vec_at(keys, t)
	return Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))


static func _vec_at(keys: Array, t: float) -> Vector3:
	if keys.is_empty():
		return Vector3.ZERO
	var v := func(k: Array) -> Vector3: return Vector3(float(k[1][0]), float(k[1][1]), float(k[1][2]))
	if t <= float(keys[0][0]):
		return v.call(keys[0])
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var k := smoothstep(0.0, 1.0, (t - float(keys[i - 1][0])) / maxf(0.0001, float(keys[i][0]) - float(keys[i - 1][0])))
			return (v.call(keys[i - 1]) as Vector3).lerp(v.call(keys[i]), k)
	return v.call(keys[keys.size() - 1])


static func _scalar_at(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var k := smoothstep(0.0, 1.0, (t - float(keys[i - 1][0])) / maxf(0.0001, float(keys[i][0]) - float(keys[i - 1][0])))
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), k)
	return float(keys[keys.size() - 1][1])

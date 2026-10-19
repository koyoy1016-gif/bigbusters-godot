extends RefCounted
## MPFB（MakeHuman）の骨に、コードで動き（待ち・走る・ジャンプ・こうげき・たおれる）を付ける。
## 数値は data/procedural_anims.json。外から動きの素材（Quaternius など）を入れるまでの、つなぎ。
## 向きの決まり：モデルは +Z を向く。上は +Y。前に振る向きがプラスの角度。

const CONFIG_PATH := "res://data/procedural_anims.json"
const ANIM_NAMES := ["Idle", "Run", "Jump", "Sword_Attack", "Death"]
## 動かす骨。どの動きにも全部の骨の道を入れる（別の動きに変えたとき、前の動きの姿勢が残らないように）
const BONES := [
	"root", "spine05", "spine03", "spine02", "neck01", "head",
	"upperleg01.L", "lowerleg01.L", "upperleg01.R", "lowerleg01.R",
	"upperarm01.L", "lowerarm01.L", "upperarm01.R", "lowerarm01.R", "wrist.R",
]


static func load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## 前（+Z）へ a 度ふる回転（ぶらさがった手足なら、足先が前に出る）
static func fwd(a: float) -> Basis:
	return Basis(Vector3.RIGHT, -deg_to_rad(a))


## 体（立った部分）を前にかたむける回転。前に振る fwd とは、向きが逆になる
static func lean(a: float) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(a))


static func yaw(a: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(a))


## なめらかな 0→1
static func smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## はじめが速く、おわりがゆっくりな 0→1（ふりおろしの「ビシッ」）
static func ease_out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


## ある時刻の姿勢。返すのは {"rot": {骨の名前: モデル空間の回転(Basis)}, "offset": Vector3（腰の位置のずれ）}
static func pose_at(anim: String, t: float, cfg: Dictionary) -> Dictionary:
	var rot := {}
	var off := Vector3.ZERO
	match anim:
		"Idle":
			var c: Dictionary = cfg["idle"]
			var p := t / float(c["seconds"]) * TAU
			var b := float(c["breath_deg"])
			rot["spine03"] = fwd(sin(p) * b)
			rot["neck01"] = fwd(-sin(p) * b * 0.5)
			rot["head"] = yaw(sin(p * 0.5) * float(c["head_deg"]))
			var sw := float(c["arm_sway_deg"])
			rot["upperarm01.L"] = fwd(sin(p) * sw)
			rot["upperarm01.R"] = fwd(-sin(p) * sw)
			var kb := float(c["knee_bend_deg"])
			rot["upperleg01.L"] = fwd(kb * 0.5)
			rot["lowerleg01.L"] = fwd(-kb)
			rot["upperleg01.R"] = fwd(kb * 0.5)
			rot["lowerleg01.R"] = fwd(-kb)
			off.y = -absf(kb) * 0.002 + sin(p) * float(c["root_bob"])
			off.x = sin(p * 0.5) * float(c.get("shift", 0.0))
			rot["spine05"] = Basis(Vector3.FORWARD, deg_to_rad(sin(p * 0.5) * float(c.get("shift_tilt_deg", 0.0))))
		"Run":
			var c: Dictionary = cfg["run"]
			var p := t / float(c["seconds"]) * TAU
			var leg := float(c["leg_deg"])
			var knee := float(c["knee_deg"])
			var arm := float(c["arm_deg"])
			var elb := float(c["elbow_deg"])
			rot["upperleg01.L"] = fwd(sin(p) * leg)
			rot["upperleg01.R"] = fwd(-sin(p) * leg)
			rot["lowerleg01.L"] = fwd(-knee * (0.15 + 0.85 * maxf(0.0, cos(p))))
			rot["lowerleg01.R"] = fwd(-knee * (0.15 + 0.85 * maxf(0.0, -cos(p))))
			rot["upperarm01.L"] = fwd(-sin(p) * arm)
			rot["upperarm01.R"] = fwd(sin(p) * arm)
			rot["lowerarm01.L"] = fwd(elb * (0.7 + 0.3 * sin(p)))
			rot["lowerarm01.R"] = fwd(elb * (0.7 - 0.3 * sin(p)))
			rot["spine05"] = lean(float(c["lean_deg"]))
			rot["spine02"] = yaw(sin(p) * float(c["twist_deg"]))
			rot["head"] = yaw(-sin(p) * float(c["twist_deg"]) * float(c.get("head_counter", 0.0))) * lean(-float(c["lean_deg"]) * 0.8)
			off.y = cos(2.0 * p) * float(c["root_bob"])
		"Jump":
			var c: Dictionary = cfg["jump"]
			var p := t / float(c["seconds"]) * TAU
			var w := sin(p) * float(c["wobble_deg"])
			rot["upperleg01.L"] = fwd(float(c["hip_deg"]) + w)
			rot["upperleg01.R"] = fwd(float(c["hip_deg"]) * 0.5 - w)
			rot["lowerleg01.L"] = fwd(-float(c["knee_deg"]))
			rot["lowerleg01.R"] = fwd(-float(c["knee_deg"]) * 0.8)
			rot["upperarm01.L"] = fwd(float(c["arm_deg"]) + w)
			rot["upperarm01.R"] = fwd(float(c["arm_deg"]) - w)
			rot["lowerarm01.L"] = fwd(float(c["elbow_deg"]))
			rot["lowerarm01.R"] = fwd(float(c["elbow_deg"]))
			rot["spine05"] = lean(float(c["lean_deg"]))
		"Sword_Attack":
			var c: Dictionary = cfg["attack"]
			var u := t / float(c["seconds"])
			var we := float(c["windup_end"])
			var se := float(c["swing_end"])
			var wind := smooth(u / we)
			var swing := ease_out((u - we) / (se - we))
			var rec := smooth((u - se) / (1.0 - se))
			var rec_u := clampf((u - se) / (1.0 - se), 0.0, 1.0)
			# 右手：上にふりかぶる → 前へふりおろす → もどる
			var arm := lerpf(0.0, float(c["windup_arm_deg"]), wind)
			arm = lerpf(arm, float(c["swing_arm_deg"]), swing)
			arm = lerpf(arm, 0.0, rec)
			arm += float(c.get("overshoot_deg", 0.0)) * sin(PI * rec_u)
			var elbow := float(c["elbow_deg"]) * (wind * (1.0 - swing) + swing * 0.5) * (1.0 - rec)
			var tw := lerpf(0.0, -float(c["twist_deg"]), wind)
			tw = lerpf(tw, float(c["twist_deg"]), swing)
			tw = lerpf(tw, 0.0, rec)
			var lean_a := lerpf(0.0, float(c["lean_deg"]), swing) * (1.0 - rec)
			rot["upperarm01.R"] = fwd(arm)
			rot["lowerarm01.R"] = fwd(elbow)
			# 手首：腕が上がった分、手首を逆にまわして、刃が後ろを向かないようにする（持つ手の向きを、なるべく保つ）
			rot["wrist.R"] = fwd(-(arm + elbow) * float(c.get("wrist_cancel", 0.0)))
			rot["upperarm01.L"] = fwd(float(c["off_arm_deg"]) * (swing * (1.0 - rec)))
			rot["spine02"] = yaw(tw)
			rot["spine05"] = lean(lean_a)
			var step := float(c["step_hip_deg"]) * swing * (1.0 - rec)
			# ためのしゃがみ：ふりかぶるあいだ、ひざを曲げて少し沈む（そのあと一気にのびる）
			var crouch := float(c.get("crouch_deg", 0.0)) * wind * (1.0 - swing)
			rot["upperleg01.L"] = fwd(step + crouch)
			rot["upperleg01.R"] = fwd(-step * 0.6 + crouch)
			rot["lowerleg01.L"] = fwd(-crouch * 1.6)
			rot["lowerleg01.R"] = fwd(-step * 0.5 - crouch * 1.6)
			off.y = -float(c.get("crouch_drop", 0.0)) * wind * (1.0 - swing)
			off.z = float(c["lunge"]) * swing * (1.0 - rec)
		"Death":
			var c: Dictionary = cfg["death"]
			var u := t / float(c["seconds"])
			var f := smooth((u - float(c["fall_start"])) / (float(c["fall_end"]) - float(c["fall_start"])))
			rot["root"] = fwd(float(c["fall_deg"]) * f)
			off.y = -float(c["drop"]) * f
			rot["lowerleg01.L"] = fwd(-float(c["knee_deg"]) * f)
			rot["lowerleg01.R"] = fwd(-float(c["knee_deg"]) * f * 0.6)
			rot["upperarm01.L"] = fwd(float(c["arm_out_deg"]) * f)
			rot["upperarm01.R"] = fwd(float(c["arm_out_deg"]) * f)
	return {"rot": rot, "offset": off}


## 骨のある場面（モデルの根）から、動きの入った AnimationPlayer を作る。骨がなければ null
static func build_player(model: Node, cfg: Dictionary) -> AnimationPlayer:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty() or cfg.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	if sk.find_bone("root") < 0 or sk.find_bone("upperleg01.L") < 0:
		return null
	var lib := AnimationLibrary.new()
	for name in ANIM_NAMES:
		lib.add_animation(name, _make_animation(model, sk, name, cfg))
	var player := AnimationPlayer.new()
	player.name = "ProceduralAnimationPlayer"
	model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", lib)
	return player


## スケルトンの節（node）から、モデルの根までの変換（モデルの根の空間 → 骨の空間の変換に使う）
static func _skeleton_to_model(model: Node, sk: Skeleton3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != model:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _make_animation(model: Node, sk: Skeleton3D, anim_name: String, cfg: Dictionary) -> Animation:
	var fps := float(cfg.get("fps", 30))
	var key: String = {"Idle": "idle", "Run": "run", "Jump": "jump", "Sword_Attack": "attack", "Death": "death"}[anim_name]
	var seconds := float(cfg[key]["seconds"])
	var looping: bool = anim_name in ["Idle", "Run", "Jump"]
	var anim := Animation.new()
	anim.length = seconds
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var skel_path := model.get_path_to(sk)
	var s2m := _skeleton_to_model(model, sk)
	var m2s_basis := s2m.basis.inverse()
	var count := sk.get_bone_count()
	var touched := {}  # 骨の番号 → 回転の道の番号
	var pos_track := -1
	var frames := int(round(seconds * fps))
	for fi in frames + 1:
		var t := minf(fi / fps, seconds)
		var pose := pose_at(anim_name, t if not (looping and fi == frames) else 0.0, cfg)
		var rot: Dictionary = pose["rot"]
		for bn in BONES:
			if not rot.has(bn):
				rot[bn] = Basis.IDENTITY
		var offset: Vector3 = m2s_basis * (pose["offset"] as Vector3)
		var delta_by_bone := {}
		for bn in rot:
			var bi := sk.find_bone(bn)
			if bi >= 0:
				# モデル空間の回転 d を、骨の空間へ：S^-1 d S
				delta_by_bone[bi] = m2s_basis * (rot[bn] as Basis) * s2m.basis
		var globals: Array[Transform3D] = []
		globals.resize(count)
		for i in count:
			var rest := sk.get_bone_rest(i)
			var p := sk.get_bone_parent(i)
			var g: Transform3D = rest if p < 0 else globals[p] * rest
			if p < 0:
				g.origin += offset
			if delta_by_bone.has(i):
				g.basis = (delta_by_bone[i] as Basis) * g.basis
			globals[i] = g
			if delta_by_bone.has(i) or p < 0:
				var local: Transform3D = g if p < 0 else globals[p].affine_inverse() * g
				if delta_by_bone.has(i):
					if not touched.has(i):
						var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
						anim.track_set_path(tr, NodePath(str(skel_path) + ":" + sk.get_bone_name(i)))
						touched[i] = tr
					anim.rotation_track_insert_key(touched[i], t, local.basis.get_rotation_quaternion())
				if p < 0:
					if pos_track < 0:
						pos_track = anim.add_track(Animation.TYPE_POSITION_3D)
						anim.track_set_path(pos_track, NodePath(str(skel_path) + ":" + sk.get_bone_name(i)))
					anim.position_track_insert_key(pos_track, t, local.origin)
	return anim

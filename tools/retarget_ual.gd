extends SceneTree
## Quaternius の Universal Animation Library（CC0）の動きを、MPFBの骨の主人公（hero_swordsman.glb）に移して、
## res://assets/anims/hero_ual.res に保存する（作り直し用の手順）。
## 使い方: godot --headless --path . --script res://tools/retarget_ual.gd
## 元になるファイル（assets/anims/_ual_src.glb）は、配布のzipの Unreal-Godot/UAL1_Standard.glb。リポジトリには入れていない（.gitignore）。
## 方法：骨ごとに「元の骨の向き」を「先の骨の向き」に合わせる（Tポーズ／Aポーズの違いを吸収）。

const SRC := "res://assets/anims/_ual_src.glb"
const DST := "res://assets/models/hero_swordsman.glb"
const OUT := "res://assets/anims/hero_ual.res"
const FPS := 30.0

## 元の骨 → 先の骨
const MAP := {
	"pelvis": "root", "spine_01": "spine05", "spine_02": "spine03", "spine_03": "spine01", "neck_01": "neck01", "Head": "head",
	"clavicle_l": "clavicle.L", "upperarm_l": "upperarm01.L", "lowerarm_l": "lowerarm01.L", "hand_l": "wrist.L",
	"clavicle_r": "clavicle.R", "upperarm_r": "upperarm01.R", "lowerarm_r": "lowerarm01.R", "hand_r": "wrist.R",
	"thigh_l": "upperleg01.L", "calf_l": "lowerleg01.L", "foot_l": "foot.L", "ball_l": "toe1-1.L",
	"thigh_r": "upperleg01.R", "calf_r": "lowerleg01.R", "foot_r": "foot.R", "ball_r": "toe1-1.R",
}
## 向きを合わせる相手（先の骨 → [元の子の骨, 先の子の骨]）。なければ、向きの補正はしない
const DIRS := {
	"upperarm01.L": ["lowerarm_l", "lowerarm01.L"], "lowerarm01.L": ["hand_l", "wrist.L"], "wrist.L": ["middle_01_l", "finger3-1.L"],
	"upperarm01.R": ["lowerarm_r", "lowerarm01.R"], "lowerarm01.R": ["hand_r", "wrist.R"], "wrist.R": ["middle_01_r", "finger3-1.R"],
	"clavicle.L": ["upperarm_l", "upperarm01.L"], "clavicle.R": ["upperarm_r", "upperarm01.R"],
	"upperleg01.L": ["calf_l", "lowerleg01.L"], "lowerleg01.L": ["foot_l", "foot.L"], "foot.L": ["ball_l", "toe1-1.L"],
	"upperleg01.R": ["calf_r", "lowerleg01.R"], "lowerleg01.R": ["foot_r", "foot.R"], "foot.R": ["ball_r", "toe1-1.R"],
}
## ゲームの動作名 ← 元の動き名（ループするか）
const ANIMS := {
	"Idle": ["Sword_Idle", true], "Run": ["Jog_Fwd", true], "Sprint": ["Sprint", true], "Walk": ["Walk", true],
	"Jump": ["Jump", true], "Jump_Start": ["Jump_Start", false], "Jump_Land": ["Jump_Land", false],
	"Sword_Attack": ["Sword_Attack", false], "Death": ["Death01", false], "Hit": ["Hit_Chest", false],
	"Roll": ["Roll", false], "Spell": ["Spell_Simple_Shoot", false], "Punch": ["Punch_Jab", false],
}

var src_sk: Skeleton3D
var dst_sk: Skeleton3D
var src_player: AnimationPlayer
var dst_path := ""
var aligned := {}  # 先の骨の名前 → 補正した「静止の向き」（Quaternion）
var src_rest_q := {}
var s2m_q := Quaternion.IDENTITY
var src_path := ""
var cur_anim: Animation
var cur_time := 0.0
var src_cache := {}


func _init() -> void:
	var src_scene := load(SRC) as PackedScene
	var dst_scene := load(DST) as PackedScene
	if src_scene == null or dst_scene == null:
		print("読み込めません。", SRC, " と ", DST, " を確認してください")
		quit(1)
		return
	var src_root := src_scene.instantiate()
	var dst_root := dst_scene.instantiate()
	root.add_child(src_root)
	root.add_child(dst_root)
	src_sk = src_root.find_children("*", "Skeleton3D", true, false)[0]
	dst_sk = dst_root.find_children("*", "Skeleton3D", true, false)[0]
	src_player = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	dst_path = str(dst_root.get_path_to(dst_sk))
	src_path = str(src_root.get_path_to(src_sk))
	# 先の骨格が、モデルの中で回っている場合の補正（モデル空間 → 骨格空間）
	var t := Transform3D.IDENTITY
	var n: Node = dst_sk
	while n != null and n != dst_root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	s2m_q = t.basis.get_rotation_quaternion()
	print("先の骨格の道：", dst_path, " 向きの補正：", s2m_q)
	_prepare_alignment()
	var lib := AnimationLibrary.new()
	for name in ANIMS:
		var def: Array = ANIMS[name]
		var anim := _bake(str(def[0]), bool(def[1]))
		if anim != null:
			lib.add_animation(name, anim)
			print("  ", name, " ← ", def[0], "  ", snappedf(anim.length, 0.01), "秒  トラック ", anim.get_track_count())
	var err := ResourceSaver.save(lib, OUT)
	print("保存：", OUT, " 結果 ", err)
	quit(0 if err == OK else 1)


func _gq(sk: Skeleton3D, bone: int) -> Quaternion:
	return sk.get_bone_global_rest(bone).basis.get_rotation_quaternion()


func _prepare_alignment() -> void:
	for sname in MAP:
		var tname: String = MAP[sname]
		var si := src_sk.find_bone(sname)
		var ti := dst_sk.find_bone(tname)
		src_rest_q[sname] = _gq(src_sk, si)
		var tq := _gq(dst_sk, ti)
		if DIRS.has(tname):
			var pair: Array = DIRS[tname]
			var sc := src_sk.find_bone(str(pair[0]))
			var tc := dst_sk.find_bone(str(pair[1]))
			if sc >= 0 and tc >= 0:
				var sd := (src_sk.get_bone_global_rest(sc).origin - src_sk.get_bone_global_rest(si).origin).normalized()
				var td := (dst_sk.get_bone_global_rest(tc).origin - dst_sk.get_bone_global_rest(ti).origin).normalized()
				# 先の骨格はモデル空間から回っているかもしれない：同じ空間（元＝モデル空間）にそろえる
				td = s2m_q * td
				var q := Quaternion(td, sd) if td.cross(sd).length() > 0.0001 else Quaternion.IDENTITY
				aligned[tname] = q * (s2m_q * tq)
				continue
		aligned[tname] = s2m_q * tq


func _bake(src_name: String, looping: bool) -> Animation:
	if not src_player.has_animation(src_name):
		print("ない動き：", src_name)
		return null
	var src_anim := src_player.get_animation(src_name)
	var anim := Animation.new()
	anim.length = src_anim.length
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var tracks := {}
	for tname in aligned:
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath(dst_path + ":" + tname))
		tracks[tname] = tr
	var root_pos := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(root_pos, NodePath(dst_path + ":root"))
	var frames := int(round(src_anim.length * FPS))
	var hip_scale := dst_sk.get_bone_global_rest(dst_sk.find_bone("root")).origin.y / src_sk.get_bone_global_rest(src_sk.find_bone("pelvis")).origin.y
	var pelvis_rest := src_sk.get_bone_global_rest(src_sk.find_bone("pelvis")).origin
	var tpose := {}
	for fi in frames + 1:
		var time := minf(float(fi) / FPS, src_anim.length)
		cur_anim = src_anim
		cur_time = time
		src_cache.clear()
		tpose.clear()
		# 先の骨を、親から順に（番号は親のほうが小さい前提。念のため再帰で解く）
		for ti in dst_sk.get_bone_count():
			_solve(ti, tpose)
		for tname in aligned:
			var ti := dst_sk.find_bone(tname)
			var gq: Quaternion = tpose[ti]
			var pi := dst_sk.get_bone_parent(ti)
			var parent_q: Quaternion = tpose[pi] if pi >= 0 else Quaternion.IDENTITY
			var local := parent_q.inverse() * gq
			anim.rotation_track_insert_key(tracks[tname], time, local.normalized())
		var pel := _src_pos("pelvis")
		var delta := (pel - pelvis_rest) * hip_scale
		var rest_local := dst_sk.get_bone_rest(dst_sk.find_bone("root")).origin
		anim.position_track_insert_key(root_pos, time, rest_local + (s2m_q.inverse() * delta))
	return anim


## 先の骨 ti の、そのコマでの「骨格空間の向き」を tpose に入れる
func _solve(ti: int, tpose: Dictionary) -> Quaternion:
	if tpose.has(ti):
		return tpose[ti]
	var tname := dst_sk.get_bone_name(ti)
	var q: Quaternion
	if aligned.has(tname):
		var sname := ""
		for k in MAP:
			if MAP[k] == tname:
				sname = k
		var si := src_sk.find_bone(sname)
		var pose_q := _src_global_q(si)
		var delta := pose_q * (src_rest_q[sname] as Quaternion).inverse()
		# モデル空間の向き → 骨格空間
		q = s2m_q.inverse() * (delta * (aligned[tname] as Quaternion))
	else:
		var pi := dst_sk.get_bone_parent(ti)
		var parent_q: Quaternion = _solve(pi, tpose) if pi >= 0 else Quaternion.IDENTITY
		q = parent_q * dst_sk.get_bone_rest(ti).basis.get_rotation_quaternion()
	tpose[ti] = q
	return q


## 元の動きの、いまの時刻での「骨格空間の向き」。動きの道を直接読む（再生係は使わない）
func _src_global_q(si: int) -> Quaternion:
	if src_cache.has(si):
		return src_cache[si]
	var name := src_sk.get_bone_name(si)
	var tr := cur_anim.find_track(NodePath(src_path + ":" + name), Animation.TYPE_ROTATION_3D)
	var local: Quaternion = cur_anim.rotation_track_interpolate(tr, cur_time) if tr >= 0 else src_sk.get_bone_rest(si).basis.get_rotation_quaternion()
	var pi := src_sk.get_bone_parent(si)
	var q: Quaternion = (_src_global_q(pi) * local) if pi >= 0 else local
	src_cache[si] = q
	return q


func _src_pos(name: String) -> Vector3:
	var tr := cur_anim.find_track(NodePath(src_path + ":" + name), Animation.TYPE_POSITION_3D)
	if tr >= 0:
		var local: Vector3 = cur_anim.position_track_interpolate(tr, cur_time)
		var si := src_sk.find_bone(name)
		var pi := src_sk.get_bone_parent(si)
		return (src_sk.get_bone_global_rest(pi) * local) if pi >= 0 else local
	return src_sk.get_bone_global_rest(src_sk.find_bone(name)).origin

extends SceneTree
## ボスの姿（平常→60%でよろける→覚醒）の確認
var fails := 0
func check(name: String, ok: bool) -> void:
	print(("OK   " if ok else "FAIL ") + name)
	if not ok: fails += 1
func _init() -> void:
	var BM := load("res://scripts/boss/boss_model.gd")
	var cfg: Dictionary = BM.load_config()
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(cfg, StandardMaterial3D.new())
	check("はじめは平常の姿", not m.is_awake() and not m.is_staggering())
	check("肌は紫", m.skin_color().is_equal_approx(Color(str(cfg["skin_normal"]))))
	m.update_form(0.7, 0.1)
	check("70%ではよろけない", not m.is_staggering())
	m.update_form(0.59, 0.1)
	check("60%を切るとよろける", m.is_staggering() and not m.is_awake())
	for i in 40: m.update_form(0.58, 0.1)
	check("起き上がると覚醒（赤い肌）", m.is_awake() and not m.is_staggering() and m.skin_color().is_equal_approx(Color(str(cfg["skin_awake"]))))
	m.reset_form()
	check("リセットで平常にもどる", not m.is_awake())
	m.update_form(0.45, 0.1)
	check("50%以下で始まれば、すぐ覚醒", m.is_awake())
	m.reset_form()
	# 脚の骨：しゃがんでも、足は床のまま（脚を縮めず、ひざを曲げる）
	var knee: Vector3 = BM.solve_two_bone(Vector3(0, 2, 0), Vector3(0, 0.6, 0), 0.9, 0.8, Vector3(0, 0, 1))
	check("ひざの計算：ももの長さが保たれる", absf((knee - Vector3(0, 2, 0)).length() - 0.9) < 0.001)
	check("ひざの計算：すねの先が足首に届く", absf((Vector3(0, 0.6, 0) - knee).length() - 0.8) < 0.001)
	check("ひざは前へ曲がる", knee.z > 0.1)
	m.update_form(0.45, 0.1)
	m.crouch = float(cfg["awake_crouch"])
	m.apply_crouch()
	var sk: Skeleton3D = m.leg_skel
	var foot: Vector3 = _chain(sk, "L").origin
	var hip: Vector3 = sk.get_bone_pose_position(sk.find_bone("thigh.L"))
	check("覚醒でしゃがむと、腰が下がる", hip.y < 2.08 - 0.3)
	check("しゃがんでも、足首は床の近く", absf(foot.y - 0.46) < 0.05)
	m.pose_idle(0.8)
	var hl: Vector3 = m.hand_target["L4"]
	check("覚醒のいちばん下の腕も、手は床につかない（体が埋もれて見えない）", hl.y > 0.45)
	m.set_walk(1.0, 1.0)
	m.apply_crouch()
	var fl: Vector3 = _chain(sk, "L").origin
	var fr: Vector3 = _chain(sk, "R").origin
	check("歩くと、左右の足が前後にずれる", absf(fl.z - fr.z) > 0.3)
	m.reset_form()
	# 腕の関節：上腕と前腕は、まっすぐの骨（長さは変わらない）。ひじで曲がる
	m.begin_frame(0.0)
	var sh: Vector3 = m.shoulder["R"]
	m.set_hand("R", sh + Vector3(-1.0, -1.5, 1.2))
	var el: Vector3 = m.arm_elbow["R"]
	var ul := float(cfg["upper_arm_len"])
	var fl2 := float(cfg["fore_arm_len"])
	var hr: Vector3 = m.hand_target["R"]
	check("腕は、上腕と前腕の長さが変わらない（くねくねしない）", absf((el - sh).length() - ul) < 0.01 and absf((hr - el).length() - fl2) < 0.01)
	var straight: bool = (hr - sh).length() < ul + fl2 - 0.05
	check("近い目標では、ひじが曲がる", straight)
	m.set_hand("R", sh + Vector3(-6.0, 0.0, 0.0))
	el = m.arm_elbow["R"]
	var d1: Vector3 = (el - sh).normalized()
	var hr2: Vector3 = m.hand_target["R"]
	var d2: Vector3 = (hr2 - el).normalized()
	check("届かない遠くの目標では、腕はまっすぐのまま伸びる", d1.dot(d2) > 0.99)
	m.set_flash(true)
	check("点滅を出せる", m.is_flashing() and (m.skin as StandardMaterial3D).emission_energy_multiplier > 0.0)
	m.set_flash(false)
	check("点滅を消せる", not m.is_flashing() and (m.skin as StandardMaterial3D).emission_energy_multiplier == 0.0)
	check("点滅で材質の種類は変わらない（光る設定は入れたまま、明るさだけ変える）", (m.skin as StandardMaterial3D).emission_enabled)
	print("失敗: ", fails)
	quit()


## 脚の骨の姿勢をたどって、足の位置を出す（木に入れたばかりで、骨の全体の姿勢がまだ計算されないため）
func _chain(sk: Skeleton3D, side: String) -> Transform3D:
	var t := Transform3D.IDENTITY
	for b in ["thigh.", "shin.", "foot."]:
		var i := sk.find_bone(b + side)
		t = t * Transform3D(Basis(sk.get_bone_pose_rotation(i)), sk.get_bone_pose_position(i))
	return t

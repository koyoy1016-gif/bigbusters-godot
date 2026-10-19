extends SceneTree
## ボスの姿（平常→60%でよろける→覚醒）と、動き（剣士と同じ動き素材。攻撃の動きは攻撃の秒で決まる）の確認
var fails := 0
func check(name: String, ok: bool) -> void:
	print(("OK   " if ok else "FAIL ") + name)
	if not ok: fails += 1


func _init() -> void:
	var BM := load("res://scripts/boss/boss_model.gd")
	var Attacks := load("res://scripts/combat/boss_attacks.gd")
	var cfg: Dictionary = BM.load_config()
	var acfg: Dictionary = Attacks.load_config()
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(cfg, StandardMaterial3D.new())
	check("体は人型の骨（剣士と同じ）", m.skel != null and m.skel.find_bone("upperarm01.L") >= 0 and m.skel.find_bone("upperleg01.R") >= 0)
	check("動き素材がある（待ち・歩き・剣の攻撃・つかみ・倒れる）", m.anim.has_clip("Idle") and m.anim.has_clip("Walk") and m.anim.has_clip("Sword_Attack") and m.anim.has_clip("Punch") and m.anim.has_clip("Death"))
	check("はじめは平常の姿", not m.is_awake() and not m.is_staggering())
	check("肌は紫", m.skin_color().is_equal_approx(Color(str(cfg["skin_normal"]))))
	m.update_form(0.1)
	check("倒れる合図がなければ、よろけない", not m.is_staggering())
	m.begin_fall()
	check("第1形態の体力が0になると、よろけて倒れる", m.is_staggering() and not m.is_awake())
	for i in 40: m.update_form(0.1)
	check("起き上がると覚醒（赤い肌）", m.is_awake() and not m.is_staggering() and m.skin_color().is_equal_approx(Color(str(cfg["skin_awake"]))))
	m.stagger_t = 1.2
	var p_down: Dictionary = m.animate(0.016, 0.0, {})["pose"]
	check("よろけると、倒れる（頭が低くなる）", m.anim.bone_model_pos(p_down, "head").y < 1.2)
	m.stagger_t = -1.0
	m.reset_form()
	check("リセットで平常にもどる", not m.is_awake())
	# 歩き：歩いた道のりで、足が前後に動く
	var p0: Dictionary = m.animate(0.016, 1.0, {"walk_dist": 0.0, "walk_speed": 3.0})["pose"]
	var p1: Dictionary = m.animate(0.016, 1.0, {"walk_dist": 0.9, "walk_speed": 3.0})["pose"]
	var fl0: Vector3 = m.anim.bone_model_pos(p0, "foot.L")
	var fl1: Vector3 = m.anim.bone_model_pos(p1, "foot.L")
	check("歩くと、足が前後に動く", absf(fl0.z - fl1.z) > 0.1)
	# 攻撃：同じ秒なら同じ姿勢（全員の画面で同じ動き）。当たる瞬間に、バットを持つ右手が大きく動いている
	var k: Dictionary = acfg["kinds"]["bat_v"]
	var w := float(k["windup_sec"])
	var a1: Dictionary = m.animate(0.016, 2.0, {"kind": "bat_v", "u": w, "k": k})["pose"]
	var a2: Dictionary = m.animate(0.016, 5.0, {"kind": "bat_v", "u": w, "k": k})["pose"]
	check("攻撃の姿勢は、攻撃の秒だけで決まる", m.anim.bone_model_pos(a1, "wrist.R").distance_to(m.anim.bone_model_pos(a2, "wrist.R")) < 0.01)
	var before: Dictionary = m.animate(0.016, 2.0, {"kind": "bat_v", "u": w - 0.14, "k": k})["pose"]
	check("縦振り：ふりかぶったとき手は高く、当たる瞬間は低い（たたきつける）", m.anim.bone_model_pos(before, "wrist.R").y > m.anim.bone_model_pos(a1, "wrist.R").y + 0.3)
	# つかみ：持ち上げると、左手が高くなる。投げる動きで、手がうしろから前へ
	var gk: Dictionary = acfg["kinds"]["grab"]
	m.animate(0.016, 2.0, {"kind": "grab", "u": 1.0, "k": gk, "grab": {"phase": "hold", "t": 0.0, "throw_sec": float(gk["throw_sec"]), "release_sec": float(gk["release_sec"])}})
	var low: Vector3 = m.hand_world("L")
	m.animate(0.016, 2.0, {"kind": "grab", "u": 1.5, "k": gk, "grab": {"phase": "hold", "t": 0.8, "throw_sec": float(gk["throw_sec"]), "release_sec": float(gk["release_sec"])}})
	var high: Vector3 = m.hand_world("L")
	check("つかんだら、左手で持ち上げる", high.y > low.y + 1.0)
	# しっぽ：腰についていく（回す技では、うしろへ長くのびる）
	m.animate(0.016, 1.0, {"kind": "tail_spin", "u": float(acfg["kinds"]["tail_spin"]["windup_sec"]), "k": acfg["kinds"]["tail_spin"]})
	check("しっぽ回しでは、しっぽがのびる", m.tail_whip > 0.5)
	m.set_flash(true)
	check("点滅を出せる", m.is_flashing() and m.skin.emission_energy_multiplier > 0.0)
	m.set_flash(false)
	check("点滅を消せる", not m.is_flashing() and m.skin.emission_energy_multiplier == 0.0)
	check("点滅で材質の種類は変わらない（光る設定は入れたまま、明るさだけ変える）", m.skin.emission_enabled)
	print("失敗: ", fails)
	quit(1 if fails > 0 else 0)

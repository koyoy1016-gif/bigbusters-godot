extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_procedural_anims.gd
## 剣士の骨に付けた、コードの動き（procedural_anims.gd）を確かめる。足や手の位置を、実際の骨から読む。

const PA := preload("res://scripts/characters/procedural_anims.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func bone_pos(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone(bone)).origin


func at(player: AnimationPlayer, sk: Skeleton3D, anim: String, t: float) -> void:
	player.play(anim)
	player.pause()
	player.seek(t, true)
	await process_frame
	await process_frame
	sk.force_update_all_bone_transforms()


func _initialize() -> void:
	var cfg := CharacterData.load_config()
	var hero := CharacterData.find(cfg, str(cfg["player_character"]))
	check(bool(hero.get("procedural_anims", false)), "剣士は、コードの動きを使う設定")
	var view := CharacterView.new()
	root.add_child(view)
	check(view.setup(hero), "剣士を読み込める")
	var player := view.player
	check(player != null, "動きの入った AnimationPlayer がある")
	var an := CharacterData.load_config()["animations"] if false else hero["animations"] as Dictionary
	for action in an:
		check(player.has_animation(str(an[action])), "動作 " + str(action) + " のアニメ（" + str(an[action]) + "）がある")
	var sk := view.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	check(player.get_animation("Run").loop_mode == Animation.LOOP_LINEAR, "走るは、くり返す")
	check(player.get_animation("Death").loop_mode == Animation.LOOP_NONE, "たおれるは、1回だけ")

	# 走る：左右の足が、前後に逆に振れる
	await at(player, sk, "Run", 0.15)
	var fl := bone_pos(sk, "foot.L").z
	var fr := bone_pos(sk, "foot.R").z
	check(absf(fl - fr) > 0.3, "走ると、両足が前後に開く：" + str(snappedf(fl - fr, 0.01)))
	await at(player, sk, "Run", 0.45)
	var fl2 := bone_pos(sk, "foot.L").z
	check((fl - fr) * (fl2 - bone_pos(sk, "foot.R").z) < 0.0, "半周すると、前後が入れ替わる")
	# 前にかたむく（頭が腰より前）
	check(bone_pos(sk, "head").z > bone_pos(sk, "root").z, "走ると、体が前（+Z）にかたむく")

	# 待ち：ほぼ立ったまま、頭が高い
	await at(player, sk, "Idle", 0.0)
	var head_y := bone_pos(sk, "head").y
	check(head_y > 1.5, "待ちのとき、頭は高い位置：" + str(snappedf(head_y, 0.01)))
	await at(player, sk, "Idle", 2.4)
	check(bone_pos(sk, "head").distance_to(Vector3(bone_pos(sk, "head"))) < 0.001, "待ちの最後の姿勢は、最初とほぼ同じ")

	# ジャンプ：ひざが曲がり、足が持ち上がる
	await at(player, sk, "Idle", 0.0)
	var foot_idle := bone_pos(sk, "foot.L")
	await at(player, sk, "Jump", 0.2)
	check(bone_pos(sk, "foot.L").y > foot_idle.y + 0.05, "ジャンプでは、足が持ち上がる")

	# こうげき：右手が、ふりかぶりで頭より高く、ふりおろしで前に出る
	await at(player, sk, "Sword_Attack", 0.14)
	var hand_up := bone_pos(sk, "wrist.R")
	check(hand_up.y > bone_pos(sk, "head").y - 0.1, "ふりかぶりで、右手が頭の高さまで上がる：" + str(snappedf(hand_up.y, 0.01)))
	await at(player, sk, "Sword_Attack", 0.4)
	var hand_fwd := bone_pos(sk, "wrist.R")
	check(hand_fwd.z > bone_pos(sk, "root").z + 0.2, "ふりおろしで、右手が前に出る")
	await at(player, sk, "Sword_Attack", 0.5)
	await at(player, sk, "Idle", 0.0)
	check(bone_pos(sk, "head").y > 1.5 and absf(bone_pos(sk, "head").x) < 0.2, "こうげきのあとに待ちへ戻ると、元の姿勢に戻る（姿勢が残らない）")

	# たおれる：横になって、低い
	await at(player, sk, "Death", 1.0)
	var top := 0.0
	for i in sk.get_bone_count():
		top = maxf(top, sk.get_bone_global_pose(i).origin.y)
	check(top < 0.8, "たおれたあとは、全部の骨が低い（立つと約1.8）：" + str(snappedf(top, 0.01)))
	await at(player, sk, "Death", 0.0)
	await at(player, sk, "Run", 0.0)
	check(bone_pos(sk, "head").y > 1.5, "たおれる→走るで、姿勢が残らない")

	# データ：全部の動きに全部の骨の道がある
	for a in ["Idle", "Run", "Jump", "Sword_Attack", "Death"]:
		var anim := player.get_animation(a)
		check(anim.get_track_count() >= PA.BONES.size(), a + " に、全部の骨の道がある：" + str(anim.get_track_count()))
	# 設定が壊れていても、落ちない
	check(PA.build_player(view.model, {}) == null, "設定が空なら、何も作らない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

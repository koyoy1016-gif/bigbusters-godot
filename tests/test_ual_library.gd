extends SceneTree
## 本物の動き素材（Quaternius UAL。CC0）を移した動きの集まり（assets/anims/hero_ual.res）のテスト

const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
var failures := 0


func check(ok: bool, name: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", name)


func _init() -> void:
	var cfg := CharacterData.load_config()
	var hero := CharacterData.find(cfg, str(cfg["player_character"]))
	check(str(hero.get("anim_library", "")) != "", "主人公に動きの集まりが設定されている")
	var lib := load(str(hero["anim_library"])) as AnimationLibrary
	check(lib != null, "動きの集まりが読める")
	if lib == null:
		quit(1)
		return
	for n in ["Idle", "Run", "Jump", "Sword_Attack", "Death", "Hit"]:
		check(lib.has_animation(n), "動きがある: " + n)
	for action in ["idle", "run", "jump", "attack", "down"]:
		check(lib.has_animation(CharacterData.animation_for(hero, action)), "動作の名前が対応している: " + action)
	check(lib.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR and lib.get_animation("Run").loop_mode == Animation.LOOP_LINEAR, "待ち・走りはくり返す")
	check(lib.get_animation("Sword_Attack").loop_mode == Animation.LOOP_NONE and lib.get_animation("Death").loop_mode == Animation.LOOP_NONE, "こうげき・たおれるは1回")
	var size := FileAccess.get_file_as_bytes(str(hero["anim_library"])).size()
	check(size < 1500000, "動きの容量が小さい：" + str(size))
	# 走りと待ちで、足の向きが違う（動きが入っている）
	var run := lib.get_animation("Run")
	var tr := run.find_track(NodePath("Human_rig/Skeleton3D:upperleg01.L"), Animation.TYPE_ROTATION_3D)
	check(tr >= 0, "足の動きの道がある")
	if tr >= 0:
		var a: Quaternion = run.rotation_track_interpolate(tr, 0.0)
		var b: Quaternion = run.rotation_track_interpolate(tr, run.length * 0.5)
		check(a.angle_to(b) > 0.3, "走りで、足が前後にふれる")
	# 見た目に組み込まれる
	var view := CharacterView.new()
	root.add_child(view)
	check(view.setup(hero) and view.player != null and view.player.has_animation("Run"), "見た目が、動きの集まりを使う")
	view.play_action("attack")
	check(view.player.current_animation == "Sword_Attack" and is_equal_approx(view.player.speed_scale, 1.0) or view.player.current_animation == "Sword_Attack", "こうげきの動きが始まる")
	view.play_action("idle")
	check(view.player.current_animation == "Sword_Attack", "こうげきは、最後まで見せる（待ちに割りこまれない）")
	view.play_action("down")
	check(view.player.current_animation == "Death", "たおれるだけは、割りこめる")
	# ライセンスの記録
	var lic := FileAccess.get_file_as_string("res://assets/LICENSES.md")
	check(lic.contains("Quaternius") and lic.contains("CC0"), "ライセンスに記録されている")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

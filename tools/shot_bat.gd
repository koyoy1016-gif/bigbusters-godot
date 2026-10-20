extends SceneTree
## 版105：ボスが投げたバット（飛んでいる所）の写真（まとめる前と後の見た目を比べる用）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_bat.gd -- 出力.png
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = false
	root.add_child(s)
	await process_frame
	var now := [5.0e6]
	s.clock_ms = func() -> float: return float(now[0])
	s.start_round()
	for i in 5:
		await process_frame
	s.force_attack("bat_throw")
	var fb: Node3D = null
	for i in 400:
		now[0] = float(now[0]) + 1000.0 / 60.0
		await process_frame
		fb = s.attack_fx._fly_bat
		if fb != null and fb.visible and i > 3:
			now[0] = float(now[0]) + 1000.0 / 60.0 * 8.0
			await process_frame
			break
	s.set_process(false)
	s.camera.look_at_from_position(fb.global_position + Vector3(0, 3, 9), fb.global_position, Vector3.UP)
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("BATSHOT ", out, " visible=", fb.visible if fb != null else false)
	quit(0)

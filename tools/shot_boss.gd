extends SceneTree
## ボスだけを、決まった姿勢・カメラで撮る（見た目の確認用）。
## xvfb-run ... --script res://tools/shot_boss.gd -- 出力.png [normal|awake] [curl]
const BM := preload("res://scripts/boss/boss_model.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://boss.png"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#6f9f78")
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.5
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(5, 7, 14)
	root.add_child(cam)
	cam.look_at(Vector3(0, 3.5, 0))
	var m: Node3D = BM.new()
	root.add_child(m)
	var mat := StandardMaterial3D.new()
	StyleFx.style_material(mat)
	m.build(BM.load_config(), mat)
	if args.size() > 1 and args[1] == "awake":
		m._apply_form("awake")
	m.scale = Vector3.ONE
	m.pose_idle(0.0)
	if args.size() > 2 and args[2] == "curl":
		m.set_curl("L", 1.0)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit(0)

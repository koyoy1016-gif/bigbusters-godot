extends SceneTree
## ボスだけを、参考画像（docs/ref/boss_oni_reference.jpg）と同じ4方向（正面・横・背中・斜め）で撮って、横に並べる（見た目の確認用）。
## xvfb-run -a -s "-screen 0 400x560x24" godot --path . --rendering-driver opengl3 --resolution 400x560 --script res://tools/shot_boss.gd -- 出力.png [normal|awake] [curl]
const BM := preload("res://scripts/boss/boss_model.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const VIEWS := [0.0, 90.0, 180.0, 35.0]  # 正面・横（右を向く）・背中・斜め


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://boss.png"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#e8e8ea")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.55
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 2.5, 9.2)
	root.add_child(cam)
	cam.look_at(Vector3(0, 2.4, 0))
	var m: Node3D = BM.new()
	root.add_child(m)
	var mat := StandardMaterial3D.new()
	StyleFx.style_material(mat, "skin")
	m.build(BM.load_config(), mat)
	var awake := args.size() > 1 and args[1] == "awake"
	if awake:
		m._apply_form("awake")
	var parts: Array = []
	for yaw in VIEWS:
		m.rotation = Vector3.ZERO
		m.scale = Vector3.ONE
		m.begin_frame(0.0)
		m.crouch = float(m.cfg["awake_crouch"]) if awake else 0.0
		m.pose_idle(0.8)
		m._update_tail(0.8)
		m.apply_crouch()
		m.pose_idle(0.8)
		m._update_tail(0.8)
		if args.size() > 2 and args[2] == "curl":
			m.set_curl("R", 1.0)
		m.rotation_degrees.y = yaw
		for i in 3:
			await process_frame
		parts.append(root.get_texture().get_image())
	var w: int = (parts[0] as Image).get_width()
	var h: int = (parts[0] as Image).get_height()
	var sheet := Image.create(w * parts.size(), h, false, (parts[0] as Image).get_format())
	for i in parts.size():
		sheet.blit_rect(parts[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("SHOT ", out)
	quit(0)

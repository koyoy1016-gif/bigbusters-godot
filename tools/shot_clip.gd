extends SceneTree
## 動き素材（hero_ual.res）の1つの動きを、何こかの時刻で撮って横に並べる（どんな動きか確かめる用）。
## xvfb-run -a -s "-screen 0 320x400x24" godot --path . --rendering-driver opengl3 --resolution 320x400 --script res://tools/shot_clip.gd -- 出力.png 動きの名前 秒1,秒2,...
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var clip := args[1] if args.size() > 1 else "Sword_Attack"
	var times: Array = []
	for x in (args[2] if args.size() > 2 else "0,0.3,0.6,0.9").split(","):
		times.append(float(x))
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
	cam.position = Vector3(2.2, 2.4, 3.6)
	root.add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	var v: Node3D = CV.new()
	root.add_child(v)
	v.setup(CD.find(CD.load_config(), "hero_swordsman"))
	v.scale = Vector3.ONE
	await process_frame
	cam.look_at_from_position(Vector3(2.2, 2.0, 3.8), Vector3(0, 1.0, 0), Vector3.UP)
	print("vp ", root.get_visible_rect(), " cam ", cam.global_position, " proj ", cam.unproject_position(Vector3(0, 1, 0)))
	var shots: Array = []
	for t in times:
		v.player.play(clip)
		v.player.seek(float(t), true)
		v.player.pause()
		for i in 3:
			await process_frame
		shots.append(root.get_texture().get_image())
	var w: int = (shots[0] as Image).get_width()
	var h: int = (shots[0] as Image).get_height()
	var sheet := Image.create(w * shots.size(), h, false, (shots[0] as Image).get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out)
	print("SHOT ", out)
	quit(0)

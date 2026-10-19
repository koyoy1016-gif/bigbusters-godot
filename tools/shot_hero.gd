extends SceneTree
## 主人公だけを、決まった動き・時刻で撮る（見た目の確認用）。xvfb-run ... --script res://tools/shot_hero.gd -- 出力.png 動き 秒
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var act := args[1] if args.size() > 1 else "run"
	var t := float(args[2]) if args.size() > 2 else 0.3
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
	cam.position = Vector3(1.6, 1.8, 3.2)
	root.add_child(cam)
	cam.look_at(Vector3(0, 1.1, 0))
	var v: Node3D = CV.new()
	root.add_child(v)
	var cfg := CD.load_config()
	v.setup(CD.find(cfg, "hero_swordsman"))
	v.scale = Vector3.ONE
	v.play_action(act)
	await process_frame
	if v.player != null:
		v.player.seek(t, true)
		v.player.pause()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit(0)

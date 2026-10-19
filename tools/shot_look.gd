extends SceneTree
## キャラの見た目の確認画像を撮る（参考画像と同じ8方向を、1枚に並べる）。
## xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/shot_look.gd -- キャラのid 出力.png [動き] [秒] [列数]
## 8方向：①正面 ②右前 ③右 ④右後 ⑤背面 ⑥左後 ⑦左 ⑧左前（キャラから見た右・左）
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const CELL := Vector2i(300, 520)
const VIEWS := [0.0, -45.0, -90.0, -135.0, 180.0, 135.0, 90.0, 45.0]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0]
	var out := args[1]
	var act := args[2] if args.size() > 2 else "idle"
	var t := float(args[3]) if args.size() > 3 else 0.4
	var cols := int(args[4]) if args.size() > 4 else 4
	var views: Array = VIEWS if cols > 1 else [VIEWS[0]]
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#cfd3d8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.55
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.1
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var v: Node3D = CV.new()
	vp.add_child(v)
	var cfg := CD.load_config()
	var def: Dictionary = CD.find(cfg, id)
	if def.is_empty():
		print("NO CHAR ", id)
		quit(1)
		return
	v.setup(def)
	v.scale = Vector3.ONE
	var top := 2.25
	cam.position = Vector3(0, top * 0.5, 5.2)
	cam.look_at_from_position(cam.position, Vector3(0, top * 0.48, 0))
	v.play_action(act)
	await process_frame
	if v.player != null:
		var anim := CD.animation_for(def, act)
		if anim != "" and v.player.has_animation(anim):
			v.player.play(anim)
			v.player.seek(t, true)
			v.player.pause()
	var sheet := Image.create(CELL.x * mini(cols, views.size()), CELL.y * int(ceil(float(views.size()) / float(cols))), false, Image.FORMAT_RGB8)
	for i in views.size():
		v.rotation_degrees.y = float(views[i])
		for k in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	sheet.save_png(out)
	print("SHOT ", out)
	quit(0)

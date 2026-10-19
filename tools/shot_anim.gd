extends SceneTree
## キャラの動きを、何コマか並べて撮る（動きの確認用）。
## xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/shot_anim.gd -- キャラのid 動き 出力.png [コマ数] [向き度] [始めの秒] [終わりの秒]
## 動き：キャラの animations のキー（attack など）か、動きの名前そのもの。向き度：カメラの回りこみ（0＝正面、-60＝右前）
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const CELL := Vector2i(260, 420)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0]
	var key := args[1]
	var out := args[2]
	var n := int(args[3]) if args.size() > 3 else 6
	var yaw := float(args[4]) if args.size() > 4 else -40.0
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
	var cam := Camera3D.new()
	cam.fov = 34.0
	vp.add_child(cam)
	var v: Node3D = CV.new()
	vp.add_child(v)
	var def: Dictionary = CD.find(CD.load_config(), id)
	v.setup(def)
	v.scale = Vector3.ONE
	v.rotation_degrees.y = yaw
	cam.look_at_from_position(Vector3(0, 1.2, 5.6), Vector3(0, 1.05, 0))
	var anim := CD.animation_for(def, key)
	if anim == "" or not v.player.has_animation(anim):
		anim = key
	if not v.player.has_animation(anim):
		print("NO ANIM ", anim)
		quit(1)
		return
	var len: float = v.player.get_animation(anim).length
	var t0 := float(args[5]) if args.size() > 5 else 0.0
	var t1 := float(args[6]) if args.size() > 6 else len
	print("ANIM ", anim, " len=", len)
	var sheet := Image.create(CELL.x * n, CELL.y, false, Image.FORMAT_RGB8)
	for i in n:
		var t := lerpf(t0, t1, float(i) / float(maxi(1, n - 1)))
		v.player.play(anim)
		v.player.seek(minf(t, len - 0.001), true)
		v.player.pause()
		for k in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	sheet.save_png(out)
	print("SHOT ", out)
	quit(0)

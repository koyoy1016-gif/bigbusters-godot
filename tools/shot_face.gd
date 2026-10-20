extends SceneTree
## 顔のアップ（正面・ななめ・横）。xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/shot_face.gd -- キャラのid 出力.png
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const CELL := Vector2i(360, 400)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
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
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.rotation_degrees = Vector3(-30, 20, 0)
	var cam := Camera3D.new()
	cam.fov = 20.0
	vp.add_child(cam)
	var v: Node3D = CV.new()
	vp.add_child(v)
	var def: Dictionary = CD.find(CD.load_config(), args[0]).duplicate(true)
	if args.size() > 2 and args[2] in ["live", "nomorph"]:
		const BB2 := preload("res://scripts/characters/body_builder.gd")
		var lk2: Dictionary = BB2.load_looks()[def["look"]].duplicate(true)
		if args[2] == "nomorph":
			lk2.erase("morphs")
			lk2.erase("bones")
		BB2.load_looks()["_live"] = lk2
		def["look"] = "_live"
		def["model"] = "res://assets/models/hero_swordsman.glb"
	if args.size() > 2 and args[2] == "bare":
		# 顔を見るため：その場で作り、頭の部品（帽子・髪）を外す
		const BB := preload("res://scripts/characters/body_builder.gd")
		var lk: Dictionary = BB.load_looks()[def["look"]].duplicate(true)
		lk["parts"] = (lk.get("parts", []) as Array).filter(func(pt: Dictionary) -> bool: return str(pt.get("bone", "")) != "head" or bool(pt.get("face", false)))
		BB.load_looks()["_bare"] = lk
		def["look"] = "_bare"
		def["model"] = "res://assets/models/hero_swordsman.glb"
	v.setup(def)
	v.scale = Vector3.ONE
	await process_frame
	if v.player != null:
		v.player.stop()
	var sk0 := v.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	sk0.reset_bone_poses()
	# 頭の骨の位置を探す
	var sk := v.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	await process_frame
	var hp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))).origin + Vector3(0, 0.06, 0)
	var sheet := Image.create(CELL.x * 3, CELL.y, false, Image.FORMAT_RGB8)
	var views := [0.0, -90.0, 180.0] if args.size() > 3 else [0.0, -35.0, -90.0]
	for i in 3:
		v.rotation_degrees.y = views[i]
		cam.look_at_from_position(hp + Vector3(0, -0.3, 2.6) if args.size() > 3 else hp + Vector3(0, 0.03, 1.5), hp)
		for k in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	sheet.save_png(args[1])
	print("SHOT ", args[1])
	quit(0)

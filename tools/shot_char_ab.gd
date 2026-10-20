extends SceneTree
## 版103：キャラの影・輪郭線をまとめる前と後を、同じ姿勢・同じ光で撮る（見た目が同じかを比べる用。測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 900x600 --path . --script res://tools/shot_char_ab.gd -- 出力.png on/off
## off：前のやり方（面ごとに影・輪郭線。画質「高」で戦いに入った時と同じく、作ったあとに輪郭線を全部に付ける）
## 3つめの引数に boss を入れると、ボスだけを撮る（版103）
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const IDS := ["healer", "bomber", "brawler", "summoner"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	CV.proxies_enabled = args[1] == "on"
	StyleFx.outline_on = true
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 40
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 7.5), Vector3(0, 1.0, 0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = OS.get_environment("AB_NOSHADOW") == ""
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -35, 0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	world.add_child(ground)
	var cfg := CD.load_config()
	if args.size() > 2 and args[2] == "boss":
		# ボス（同じ姿勢：build の時の Idle の最初の形）
		var BM := load("res://scripts/boss/boss_model.gd")
		var bm: Node3D = BM.new()
		world.add_child(bm)
		var bmat := StandardMaterial3D.new()
		bm.build(BM.load_config(), bmat)
		bm.scale = Vector3.ONE * 0.45
		bm.position = Vector3(0, 0, -1.5)
		cam.look_at_from_position(Vector3(0, 3.0, 8.5), Vector3(0, 1.6, 0), Vector3.UP)
		StyleFx.set_outline(root, true)
		if OS.get_environment("AB_RESTORE") != "":
			# 調べ用：まとめた輪郭線の形を隠し、元の材質に線をもどす
			for mi in bm.find_children("*", "MeshInstance3D", true, false):
				if mi.has_meta("outline_proxy"):
					mi.visible = false
				elif mi.has_meta("outline_merged"):
					for si in mi.mesh.get_surface_count():
						var mm: Material = mi.get_active_material(si)
						mm.next_pass = StyleFx.outline_material(0.022)
		for i in 8:
			await process_frame
		var dcb := 0.0
		for i in 3:
			await process_frame
			dcb += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		root.get_texture().get_image().save_png(args[0])
		print("CHAR_AB ", args[1], " boss draw_calls=", roundi(dcb / 3.0))
		quit(0)
		return
	var x := -3.0
	for id in IDS:
		var v := CV.new()
		world.add_child(v)
		v.setup(CD.find(cfg, id))
		v.position = Vector3(x, 0, 0)
		x += 2.0
		if v.player != null:
			v.play_action("idle")
			v.player.seek(0.3, true)
			v.player.pause()
	StyleFx.set_outline(root, true)  # 戦いに入った時と同じ（作ったあとに、画質の切りかえで線を付ける）
	for i in 8:
		await process_frame
	var dc := 0.0
	for i in 3:
		await process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	root.get_texture().get_image().save_png(args[0])
	print("CHAR_AB ", args[1], " draw_calls=", roundi(dc / 3.0))
	quit(0)

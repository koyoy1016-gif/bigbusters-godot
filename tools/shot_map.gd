extends SceneTree
## 版88：戦いのマップ（渋谷のスクランブル交差点）の写真を撮る（見た目の確認用）。
## xvfb-run -a godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_map.gd -- 出力.png 見方 [画質]
## 見方：sky（交差点のうしろの上から、街なみ）・top（真上から）・street（人の目の高さ）・battle（戦いのカメラ）
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Quality := preload("res://scripts/core/quality.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var view := args[1] if args.size() > 1 else "sky"
	var qname := args[2] if args.size() > 2 else "high"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	Quality.apply(qname, Quality.load_config(), root, get_nodes_in_group("sun"))
	s.set_map_quality(qname)
	s.start_round()
	for i in 20:
		await process_frame
	if view != "battle":
		s.set_process(false)
		var cam := Camera3D.new()
		cam.environment = s.camera.environment
		cam.far = 3000.0
		root.add_child(cam)
		match view:
			"top":
				cam.fov = 60.0
				cam.look_at_from_position(Vector3(0, 160, 0.01), Vector3.ZERO, Vector3.FORWARD)
			"street":
				cam.fov = 70.0
				cam.look_at_from_position(Vector3(4, 1.7, 22), Vector3(-2, 6, -40), Vector3.UP)
			_:
				cam.fov = 60.0
				cam.look_at_from_position(Vector3(0, 34, 48), Vector3(0, 6, -40), Vector3.UP)
		cam.current = true
		for i in 6:
			await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit(0)

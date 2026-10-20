extends SceneTree
## 版88：戦いのマップ（渋谷のスクランブル交差点）の写真を撮る（見た目の確認用）。
## xvfb-run -a godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_map.gd -- 出力.png 見方 [画質] [時間帯] [切りかえの途中の割合]
## 見方：sky（交差点のうしろの上から、街なみ）・top（真上から）・street（人の目の高さ）・battle（戦いのカメラ）
## 時間帯（版90）：evening（夕方・ふだん）・night（夜・覚醒）。割合 0〜1 を入れると、切りかえの途中
## 版92：環境変数 SHOT_HP に数を入れると、自分の体力をその数にして撮る（体力の表示の確認用）
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Quality := preload("res://scripts/core/quality.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var view := args[1] if args.size() > 1 else "sky"
	var qname := args[2] if args.size() > 2 else "high"
	var tname := args[3] if args.size() > 3 else "evening"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	Quality.apply(qname, Quality.load_config(), root, get_nodes_in_group("sun"))
	s.set_map_quality(qname)
	s.start_round()
	for i in 20:
		await process_frame
	if OS.get_environment("SHOT_HP") != "":
		s.my_hp = float(OS.get_environment("SHOT_HP"))
	s.set_process(false)  # 時間帯を、ここで決めた値のままにする（戦いのカメラは、20フレームで動いた所のまま）
	if s.tod.is_ready():
		s.tod.snap(tname == "night")
		if args.size() > 4:
			s.tod.t = float(args[4])
			s.tod.target = s.tod.t
			s.tod.apply()
	if view == "battle":
		s.overlay.queue_redraw()  # 画面の字・体力の表示も、いまの値で描きなおす
		for i in 4:
			await process_frame
	else:
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

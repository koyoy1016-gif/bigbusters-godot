extends SceneTree
## 版112：演出の写真を撮る（見た目の確認用）。
## xvfb-run -a godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_cues.gd -- 出力.png 種類 秒 [キャラのid]
## 種類：intro（敵の登場）・awaken（ボスの覚醒）・attack（敵の攻撃の名前）・attack_ult（敵の必殺技の名前）・ult（自分の必殺技の名前）
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var kind := args[1]
	var at := float(args[2]) if args.size() > 2 else 0.5
	var cid := args[3] if args.size() > 3 else "summoner"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = cid
	s.ai_enabled = false
	root.add_child(s)
	await process_frame
	s.start_round()
	for i in 10:
		await process_frame
	s.set_process(false)
	s.skill_time_stop_left = 999.0
	s.enemy_intro["left"] = 0.0
	var bp: Vector3 = s.boss.position
	s.player.position = Vector3(bp.x + 0.6, s.ground_y, bp.z + float(s.config["boss_size"]) * 0.5 + 5.0)
	s.facing = Vector2(0, -1)
	match kind:
		"intro":
			s.show_enemy_intro()
		"awaken":
			s.show_awakening()
		"attack":
			s.show_enemy_attack("bat_v", 101)
		"attack_ult":
			s.show_enemy_attack("bottle_ride", 102)
		"ult":
			s.gauge.value = s.gauge.max_value
			s.perform("ultimate")
	var t := 0.0
	while t < at:
		await process_frame
		var dt := 1.0 / 30.0
		s.update_cues(dt)
		s.banner["left"] = maxf(0.0, float(s.banner["left"]) - dt)
		if kind == "ult":
			s._actions_update(dt)
		s.camera_update(dt)
		s.overlay.queue_redraw()
		Engine.time_scale = 1.0
		t += dt
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out, " cues=", s.cue_log)
	quit(0)

extends SceneTree
## 版84：蘇生の輪の写真を撮る（見た目の確認用）。
## xvfb-run -a godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_revive.gd -- 出力.png [me]
## me：自分が倒れた所（ふつうは、AIが倒れて、自分が起こしている所）
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var me := args.size() > 1 and args[1] == "me"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	s.start_round()
	for i in 10:
		await process_frame
	s.skill_time_stop_left = 999.0
	s.set_process(false)
	var dt := 1.0 / 30.0
	var bp: Vector3 = s.boss.position
	s.player.position = Vector3(bp.x + 1.0, s.ground_y, bp.z + 9.0)
	for i in 10:
		s._actions_update(dt)
		s.combat_update(dt)
		s._ai_update(dt)
		await process_frame
	var slots: Array = s.ai_allies.keys()
	if me:
		s._set_my_hp(0.0)
	else:
		var a: Dictionary = s.ai_allies[slots[0]]
		a["pos"] = Vector2(s.player.position.x - 1.2, s.player.position.z - 1.0)
		a["hp"] = 0.0
		a["downed"] = true
	for i in 70:
		s._actions_update(dt)
		s.combat_update(dt)
		s._ai_update(dt)
		if s.char_view != null and s.char_view.player != null:
			s.char_view.player.advance(0.0)
		s.camera_update(dt)
		s.overlay.queue_redraw()
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out, " log=", s.revive_sys.log)
	quit(0)

extends SceneTree
## キャラの技を戦いの画面で使って、途中の写真を撮る（見た目の確認用）。
## xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/shot_skill.gd -- 出力.png キャラのid 技（normal・sub・main・ultimate） 秒
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var cid := args[1]
	var act := args[2]
	var at := float(args[3]) if args.size() > 3 else 0.5
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = cid
	s.ai_enabled = false
	root.add_child(s)
	await process_frame
	s.start_round()
	for i in 10:
		await process_frame
	s.skill_time_stop_left = 999.0
	var bp: Vector3 = s.boss.position
	var br := float(s.config["boss_size"]) * 0.5
	var gap := 5.0 if act in ["main", "normal"] and cid in ["gunner", "mage", "bomber", "healer", "summoner"] else 1.2
	s.player.position = Vector3(bp.x + 0.6, s.ground_y, bp.z + br + gap)
	s.facing = Vector2(0, -1)
	if act == "ultimate":
		s.gauge.value = s.gauge.max_value
	s.set_process(false)
	s.perform(act)
	var t := 0.0
	while t < at:
		await process_frame
		var dt := 1.0 / 30.0
		s._actions_update(dt)
		s.combat_update(dt)
		if s.char_view != null and s.char_view.player != null:
			s.char_view.player.advance(0.0)
		t += dt
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out, " hits=", s.my_hits, " active=", s.round_active(), " inv=", s.phase.invulnerable(), " fx=", s.skill_fx_log, " log=", s.skill_log)
	quit(0)

extends SceneTree
## 版103：影・輪郭線をまとめる前と後の写真（見た目が同じかを比べる用。測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_proxy_ab.gd -- 出力.png on/off [lobby/battle]
## on：まとめる（いま）・off：まとめない（前）。画質「高」（影・輪郭線あり）。描画の回数も出す。
const SCENE := "res://scenes/game_flow.tscn"
const CV := preload("res://scripts/characters/character_view.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	CV.proxies_enabled = (args[1] if args.size() > 1 else "on") == "on"
	var where := args[2] if args.size() > 2 else "lobby"
	seed(7)
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.quality_name = "high"
	flow._apply_quality()
	flow.goto("lobby")
	for i in 40:
		await process_frame
	if where == "battle":
		flow.play()
		for i in 5:
			await process_frame
		var b: Node = flow.battle
		b.start_round()
		b.ai_enabled = false
		for i in 3:
			await process_frame
		b.set_process(false)
		var k := 0
		for slot in b.other_target.keys():
			var pos := Vector2(0.35 + 0.15 * k, 0.62)
			b.other_target[slot] = pos
			b.other_pos[slot] = pos
			k += 1
		b._update_others(0.0)
		b.player.position = Vector3(-2.0, b.player.position.y, 4.0)
		b.camera_vel = Vector3.ZERO
		b.camera_target = Vector3(-2.0, 0, 4.0) * float(b.config["camera_follow"])
		for i in 60:
			b.camera_update(1.0 / 60.0)
		for p in b.find_children("*", "AnimationPlayer", true, false):
			(p as AnimationPlayer).pause()
	for i in 6:
		await process_frame
	var dc := 0.0
	for i in 3:
		await process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	root.get_texture().get_image().save_png(out)
	print("AB ", args[1], " ", where, " draw_calls=", roundi(dc / 3.0))
	quit(0)

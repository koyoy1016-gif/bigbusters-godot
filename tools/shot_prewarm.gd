extends SceneTree
## 版108：戦いの始まりの「先に1回描く」（見た目の写し）が、画面に見えていないかを確かめる（測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/shot_prewarm.gd -- 出力のはじめ
## 戦いの画面ができた直後（写しが出ている）で全体を止め、写しを出したまま撮る → 写しを隠して撮る。2枚のちがう画素の数を出す（0 なら見えていない）。

const SCENE := "res://scenes/game_flow.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "/tmp/prewarm"
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.quality_name = "high"
	flow._apply_quality()
	flow.goto("lobby")
	for i in 20:
		await process_frame
	flow.play()
	await process_frame
	var b: Node = flow.battle
	var nodes: Array = b.skills.prewarm_nodes.duplicate()
	paused = true  # 動きを止める（描くのは続く）
	for i in 3:
		await process_frame
	var a := root.get_texture().get_image()
	a.save_png(prefix + "_with.png")
	for n in nodes:
		if is_instance_valid(n):
			(n as Node3D).visible = false
	for i in 3:
		await process_frame
	var c := root.get_texture().get_image()
	c.save_png(prefix + "_without.png")
	var diff := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := c.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.004:
				diff += 1
	print("PREWARM_SHOT nodes=%d diff_pixels=%d of %d" % [nodes.size(), diff, a.get_width() * a.get_height()])
	paused = false
	quit(0)

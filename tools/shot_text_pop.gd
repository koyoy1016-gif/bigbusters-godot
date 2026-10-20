extends SceneTree
## 版99：ダメージの数字と必殺技の名前の「はね上がり」の写真（直す前と後で、見た目が同じかを比べる用）。
## xvfb-run -a godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_text_pop.gd -- 出力.png
## 3種類の数字（ふつう：出た瞬間・強い：はね上がりの途中・特別：落ち着いた時）と、必殺技の名前（はね上がりの途中）を、時間を止めて撮る。
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = false
	root.add_child(s)
	await process_frame
	s.start_round()
	for i in 20:
		await process_frame
	s.set_process(false)
	var dn: RefCounted = s.damage_numbers()
	dn.items.clear()
	var w: Vector3 = s.boss.global_position + Vector3(0.0, 4.0, 0.0)
	var a: Dictionary = dn.add(128.0, w + Vector3(-3.0, 0.0, 0.0), "normal")
	var bb: Dictionary = dn.add(1240.0, w, "strong")
	var c: Dictionary = dn.add(386.0, w + Vector3(3.0, -1.5, 0.0), "critical")
	a["age"] = 0.0
	bb["age"] = 0.07
	c["age"] = 0.4
	s.hud._show_banner("ためし の わざ", "", 1.2)
	s.banner["left"] = 1.2 - 0.06
	s.overlay.queue_redraw()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit(0)

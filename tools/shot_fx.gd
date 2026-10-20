extends SceneTree
## 版105：技の見た目（SkillFx）を並べて撮る（材質を使いまわす前と後で、見た目が同じかを比べる用）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 900x600 --path . --script res://tools/shot_fx.gd -- 出力.png [くり返し]
## くり返し：同じ見た目を何回か出して消してから撮る（2回目からは、使いまわした材質で出る）
const SkillFx := preload("res://scripts/fx/skill_fx.gd")
const KINDS := ["blast", "ring", "spark", "ripple", "aura", "dome", "heal_dome", "pillar", "slash", "beam", "orb", "smoke"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rounds := int(args[1]) if args.size() > 1 else 1
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.18)
	var cam := Camera3D.new()
	cam.environment = env
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 9, 16), Vector3(0, 1, 0), Vector3.UP)
	var nodes := []
	for r in rounds:
		for n in nodes:
			(n as Node).queue_free()
		await process_frame
		await process_frame
		nodes.clear()
		var i := 0
		for kind in KINDS:
			var x := -9.0 + (i % 6) * 3.6
			var z := -3.0 + (i / 6) * 6.0
			var spec := {"kind": kind, "color": "#ffb02a" if i % 2 == 0 else "#5fb8ff", "life": 1.0, "radius": 1.2, "tall": 3.0, "amount": 12, "flash": 0.6, "size": 0.8}
			var n := SkillFx.make(spec, Vector3(x, 0, z), Vector3(x + 1.5, 0.5, z), 1.0)
			world.add_child(n)
			nodes.append(n)
			i += 1
		for n in nodes:
			SkillFx.tick(n, 0.3)
	for f in 4:
		await process_frame
	root.get_texture().get_image().save_png(args[0])
	print("FXSHOT ", args[0])
	quit(0)

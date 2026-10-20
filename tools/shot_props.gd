extends SceneTree
## 技の小物（data/props.json）を並べて撮る。xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/shot_props.gd -- 出力.png
const SkillFx := preload("res://scripts/fx/skill_fx.gd")
const CELL := Vector2i(220, 220)
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var names: Array = SkillFx.props().keys()
	var cols := 6
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#6f8a74")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.rotation_degrees = Vector3(-40, 30, 0)
	var cam := Camera3D.new()
	cam.fov = 35.0
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	var sheet := Image.create(CELL.x * cols, CELL.y * int(ceil(names.size() / float(cols))), false, Image.FORMAT_RGB8)
	for i in names.size():
		var m := SkillFx.prop_mesh(str(names[i]))
		mi.mesh = m
		var aabb := m.get_aabb()
		var c := aabb.get_center()
		var r := maxf(aabb.size.length(), 0.3)
		mi.rotation_degrees = Vector3(0, -35, 0)
		cam.look_at_from_position(c + Vector3(0.3, 0.35, 1.0).normalized() * r * 1.5, c)
		for k in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
		print(i, " ", names[i])
	sheet.save_png(out)
	quit(0)

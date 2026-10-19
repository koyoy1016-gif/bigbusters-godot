extends SceneTree
## 戦いの画面の重さを測る（AI3人つき）。画面ありで動かす：
## xvfb-run -a -s "-screen 0 648x1152x24" godot --path . --rendering-driver opengl3 --script res://tools/perf_probe.gd -- low
## 描画回数・面の数・部品の数・スクリプトの処理時間を出す。ソフトウェア描画なのでFPSは実機と違う。比べるのは「数」。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Quality := preload("res://scripts/core/quality.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")


func _count(node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
		out["mesh_instances"] += 1
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out["surfaces"] += mi.mesh.get_surface_count()
		var top := _top_group(node)
		out["by_group"][top] = int(out["by_group"].get(top, 0)) + 1
	if node is MultiMeshInstance3D:
		out["multimesh"] += 1
	if node is Skeleton3D:
		out["skeletons"] += 1
	if node is AnimationPlayer or node is AnimationTree:
		out["anim_players"] += 1
	if node is Light3D:
		out["lights"] += 1
		if (node as Light3D).shadow_enabled:
			out["shadow_lights"] += 1
	if node is GPUParticles3D or node is CPUParticles3D:
		out["particles"] += 1
	out["nodes"] += 1
	for c in node.get_children():
		_count(c, out)


func _top_group(node: Node) -> String:
	var n := node
	while n != null and n.get_parent() != null and n.get_parent().get_parent() != null and n.get_parent().get_parent() != root:
		n = n.get_parent()
	return str(n.name) if n != null else "?"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var qname := args[0] if args.size() > 0 else "low"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	var qcfg := Quality.load_config()
	Quality.apply(qname, qcfg, root, get_nodes_in_group("sun"))
	StyleFx.set_outline(root, bool(qcfg["presets"][qname].get("outline", false)))
	Engine.max_fps = 0
	s.start_round()
	for i in 60:
		await process_frame
	var frames := 180
	var t0 := Time.get_ticks_usec()
	var proc_sum := 0.0
	var draw_sum := 0.0
	var prim_sum := 0.0
	var obj_sum := 0.0
	for i in frames:
		await process_frame
		proc_sum += Performance.get_monitor(Performance.TIME_PROCESS)
		draw_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj_sum += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	var out := {"mesh_instances": 0, "surfaces": 0, "multimesh": 0, "skeletons": 0, "anim_players": 0, "lights": 0, "shadow_lights": 0, "particles": 0, "nodes": 0, "by_group": {}}
	_count(root, out)
	print("PERF quality=", qname)
	print("PERF draw_calls=", int(draw_sum / frames), " primitives=", int(prim_sum / frames), " objects=", int(obj_sum / frames))
	print("PERF process_ms=", snappedf(proc_sum / frames * 1000.0, 0.01), " wall_ms_per_frame=", snappedf(wall, 0.01))
	print("PERF ", JSON.stringify(out))
	print("PERF ai=", s.ai_allies.size())
	quit(0)

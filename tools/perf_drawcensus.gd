extends SceneTree
## 版103：描画の回数の内訳（何が何回描かれているか。測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_drawcensus.gd -- 出力.json 画質(low/high) [場面 lobby/battle/both]
## 見えている形（GeometryInstance3D）ごとに：面（サーフェス）の数・影を落とすか・ふち取り（材質の next_pass）・透明か。
## 持ち主（キャラ・ボス・マップの部品・そのほか）ごとに合計し、「色を塗る回数＋ふち取り＋影」の見こみと、実際の描画の回数（RENDER_TOTAL_DRAW_CALLS_IN_FRAME）を出す。

const SCENE := "res://scenes/game_flow.tscn"


func owner_name(n: Node) -> String:
	var cur := n
	while cur != null:
		if cur.get_script() != null and str(cur.get_script().resource_path).ends_with("character_view.gd"):
			return "char:" + str(cur.get("character").get("id", "?"))
		if str(cur.name) == "Boss" or str(cur.name).begins_with("BossModel"):
			return "boss"
		if cur.has_meta("map_part"):
			return "map:" + str(cur.get_meta("map_part"))
		cur = cur.get_parent()
	var p := n.get_parent()
	return "other:" + (str(p.name) if p != null else "") + "/" + str(n.name)


func visible_tree(n: Node) -> bool:
	return n is Node3D and (n as Node3D).is_visible_in_tree()


func census(shadows_on: bool) -> Dictionary:
	var groups := {}
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		if not visible_tree(g):
			continue
		var gi := g as GeometryInstance3D
		var surfaces := 0
		var outline := 0
		var transparent := 0
		var mats: Array = []
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mi := gi as MeshInstance3D
			surfaces = mi.mesh.get_surface_count()
			for si in surfaces:
				mats.append(mi.get_active_material(si))
		elif gi is MultiMeshInstance3D:
			var mmi := gi as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.multimesh.mesh != null:
				surfaces = mmi.multimesh.mesh.get_surface_count()
				for si in surfaces:
					mats.append(mmi.material_override if mmi.material_override != null else mmi.multimesh.mesh.surface_get_material(si))
		elif gi is CPUParticles3D or gi is GPUParticles3D:
			surfaces = 1
			mats.append(gi.material_override)
		else:
			surfaces = 1
		for m in mats:
			var mm: Material = m
			if mm != null and mm.next_pass != null:
				outline += 1
			if mm is BaseMaterial3D and (mm as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				transparent += 1
		var shadow := surfaces if (shadows_on and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and transparent < surfaces) else 0
		var key := owner_name(gi)
		if not groups.has(key):
			groups[key] = {"nodes": 0, "surfaces": 0, "outline": 0, "shadow": 0, "transparent": 0}
		var d: Dictionary = groups[key]
		d["nodes"] += 1
		d["surfaces"] += surfaces
		d["outline"] += outline
		d["shadow"] += shadow
		d["transparent"] += transparent
	var total := {"surfaces": 0, "outline": 0, "shadow": 0}
	for k in groups:
		for f in total:
			total[f] += int(groups[k][f])
	return {"groups": groups, "total": total}


func measure(tag: String, shadows_on: bool) -> Dictionary:
	for i in 6:
		await process_frame
	var dc := 0.0
	for i in 4:
		await process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var c := census(shadows_on)
	c["draw_calls"] = roundi(dc / 4.0)
	c["objects"] = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	print("CENSUS ", tag, " draw_calls=", c["draw_calls"], " total=", c["total"])
	return c


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var qname := args[1] if args.size() > 1 else "high"
	var which := args[2] if args.size() > 2 else "both"
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.quality_name = qname
	flow._apply_quality()
	var shadows_on := qname == "high"
	var report := {"quality": qname}
	flow.goto("lobby")
	for i in 20:
		await process_frame
	if which != "battle":
		report["lobby"] = await measure("lobby", shadows_on)
	if which != "lobby":
		flow.play()
		for i in 5:
			await process_frame
		flow.battle.start_round()
		for i in 10:
			await process_frame
		flow.battle.ai_enabled = false
		flow.battle.set_process(false)
		report["battle"] = await measure("battle", shadows_on)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("CENSUS_DONE ", out_path)
	quit(0)

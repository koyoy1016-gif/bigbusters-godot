extends SceneTree
## 版108：戦いで1コマに描く三角形の数の内訳（持ち主ごと。測るだけ。画面なしでよい）。
## godot --headless --path . --script res://tools/perf_tris.gd -- 出力.json [画質 low/high] [awake]
## 色を塗る（ふつう）・ふち取り（材質の next_pass と、まとめたふち取り OutlineProxy）・影（影を落とす物）を分けて数える。
## 画面に入っているかは見ない（全部）。粒・MultiMesh は、並べる数×形の三角形。
## awake：覚醒させて、夜に変わりきってから数える。

const SCENE := "res://scenes/game_flow.tscn"
var tri_cache := {}


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


func tris_of(m: Mesh) -> Array:
	if m == null:
		return []
	if tri_cache.has(m):
		return tri_cache[m]
	var out: Array = []
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		out.append((idx.size() if idx.size() > 0 else verts.size()) / 3)
	tri_cache[m] = out
	return out


func visible_tree(n: Node) -> bool:
	return n is Node3D and (n as Node3D).is_visible_in_tree()


func census() -> Dictionary:
	var groups := {}
	var total := {"color": 0, "outline": 0, "shadow": 0}
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		if not visible_tree(g):
			continue
		var gi := g as GeometryInstance3D
		var mesh: Mesh = null
		var mult := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			mult = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		elif gi is CPUParticles3D:
			mesh = (gi as CPUParticles3D).mesh
			mult = (gi as CPUParticles3D).amount if (gi as CPUParticles3D).emitting else 0
		var ts := tris_of(mesh)
		var color := 0
		var outline := 0
		var shadow := 0
		var only_shadow := gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var is_outline_proxy := gi.has_meta("outline_proxy")
		for si in ts.size():
			var t := int(ts[si]) * mult
			var mat: Material = gi.material_override
			if mat == null and gi is MeshInstance3D:
				mat = (gi as MeshInstance3D).get_active_material(si)
			var transparent := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			if not only_shadow:
				if is_outline_proxy:
					outline += t
				else:
					color += t
					if mat != null and mat.next_pass != null:
						outline += t
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not transparent:
				shadow += t
		var key := owner_name(gi)
		if not groups.has(key):
			groups[key] = {"color": 0, "outline": 0, "shadow": 0, "nodes": 0}
		var d: Dictionary = groups[key]
		d["nodes"] += 1
		d["color"] += color
		d["outline"] += outline
		d["shadow"] += shadow
		total["color"] += color
		total["outline"] += outline
		total["shadow"] += shadow
	# 持ち主の種類でまとめる（map:* → map）
	var kinds := {}
	for k in groups:
		var kk := str(k).split(":")[0] if str(k).begins_with("map:") or str(k).begins_with("char:") else str(k)
		if str(k).begins_with("char:"):
			kk = str(k)
		if not kinds.has(kk):
			kinds[kk] = {"color": 0, "outline": 0, "shadow": 0, "nodes": 0}
		for f in ["color", "outline", "shadow", "nodes"]:
			kinds[kk][f] += int(groups[k][f])
	return {"total": total, "kinds": kinds, "groups": groups}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var qname := args[1] if args.size() > 1 else "high"
	var awake := args.size() > 2 and args[2] == "awake"
	var sim := [1.0e7]
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.quality_name = qname
	flow._apply_quality()
	flow.goto("lobby")
	for i in 20:
		await process_frame
	flow.play()
	for i in 5:
		await process_frame
	var b: Node = flow.battle
	b.clock_ms = func() -> float: return float(sim[0])
	b.start_round()
	for i in 30:
		await process_frame
		sim[0] = float(sim[0]) + 1000.0 / 60.0
	if awake:
		b.my_hits = float(b.phase.max1) + 1.0
		b._recompute_boss_hp()
		var w := 0
		while not b.phase.is_awake() and w < 900:
			await process_frame
			sim[0] = float(sim[0]) + 1000.0 / 60.0
			w += 1
		for i in 150:
			await process_frame
			sim[0] = float(sim[0]) + 1000.0 / 60.0
	b.set_process(false)
	var c := census()
	c["quality"] = qname
	c["awake"] = awake
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(c, "  "))
	f.close()
	print("TRIS total ", c["total"])
	var ks: Array = (c["kinds"] as Dictionary).keys()
	ks.sort_custom(func(x, y): return int(c["kinds"][x]["color"]) + int(c["kinds"][x]["outline"]) + int(c["kinds"][x]["shadow"]) > int(c["kinds"][y]["color"]) + int(c["kinds"][y]["outline"]) + int(c["kinds"][y]["shadow"]))
	for k in ks.slice(0, 16):
		print("TRIS ", k, " ", c["kinds"][k])
	quit(0)

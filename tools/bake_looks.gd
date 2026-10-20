extends SceneTree
## 見た目（data/character_looks.json）を、前もって作って保存する（ゲームの中では作らない＝読みこむだけで速い）。
## 画面のある描画で動かす（画面なしでは、作った形の中身が残らないため）：
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/bake_looks.gd [-- キャラのid ...]
## 作る物：
##   assets/models/chars/<id>.scn  ：ゲームで使う形（骨・動きは剣士と同じ。遠くでは軽い形に切りかわる LOD つき）
##   exports/<id>.glb               ：ほかのソフト（Blender など）で開ける形（骨つき。リポジトリの外に出す用）
const BB := preload("res://scripts/characters/body_builder.gd")
const CV := preload("res://scripts/characters/character_view.gd")
const BASE := "res://assets/models/hero_swordsman.glb"


func _initialize() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	var looks := BB.load_looks()
	if ids.is_empty():
		ids = looks.keys()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/chars"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://exports"))
	for id in ids:
		var model: Node3D = (load(BASE) as PackedScene).instantiate()
		model.name = str(id)
		root.add_child(model)
		var tris := BB.apply(model, looks[id])
		CV.bake_items(model)
		var lod_tris := 0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			# 版79：部品をまとめた形（Items）は、細い物（帽子のつば・まゆ・ひとみ）が消えるので、軽い形（LOD）を作らない
			if float(looks[id].get("bake_lod", 0.0)) > 0.0 and str(m.name) != "Items":
				# 呼び出す小さい兵隊など：小さく出る物は、形そのものを軽くする（三角形を減らした形だけを保存）
				m.mesh = _reduced(m.mesh, float(looks[id]["bake_lod"]))
			elif str(m.name) != "Items" and OS.get_environment("NOLOD") == "":
				m.mesh = _with_lods(m.mesh)
			lod_tris += _tris(m.mesh)
		model.set_meta("look_baked", str(id))
		model.scene_file_path = ""
		_own(model, model)
		var packed := PackedScene.new()
		packed.pack(model)
		var path := "res://assets/models/chars/%s.scn" % id
		var err := ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_scene(model, state)
		var gerr := doc.write_to_filesystem(state, ProjectSettings.globalize_path("res://exports/%s.glb" % id))
		print("BAKED %s tris=%d save=%d glb=%d" % [id, lod_tris, err, gerr])
		model.queue_free()
		await process_frame
	quit(0)


## 形に、遠くで使う軽い形（LOD）をつける。骨の重みはそのまま
func _with_lods(mesh: Mesh) -> Mesh:
	if not (mesh is ArrayMesh):
		return mesh
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {}, mesh.surface_get_material(s),
			"", mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	return out if out != null and out.get_surface_count() == mesh.get_surface_count() else mesh


## 形の三角形を、ratio ぐらいに減らす（軽い形の中から、いちばん近い物を選ぶ）
func _reduced(mesh: Mesh, ratio: float) -> Mesh:
	if not (mesh is ArrayMesh):
		return mesh
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {}, mesh.surface_get_material(s),
			"", mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	im.generate_lods(25.0, 60.0, [])
	var out := ArrayMesh.new()
	for s in im.get_surface_count():
		var arr := im.get_surface_arrays(s)
		var full: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var best := full
		for l in im.get_surface_lod_count(s):
			var li := im.get_surface_lod_indices(s, l)
			if li.size() >= 3 and absf(float(li.size()) / full.size() - ratio) < absf(float(best.size()) / full.size() - ratio):
				best = li
		arr[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, im.get_surface_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(s, im.get_surface_material(s))
	return out


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var idx = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else 0
	return n


func _own(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_own(c, owner_node)

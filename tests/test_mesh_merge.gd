extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_mesh_merge.gd
## 部品をまとめる仕組み（scripts/core/mesh_merge.gd）と、ボス・主人公の「描く部品の数」が増えすぎていないことを確かめる。
## 部品の数が多いと、スマホのブラウザで重くなる（描画の回数が増える）ため。上限は data/quality.json の draw_budget。

const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const BM := preload("res://scripts/boss/boss_model.gd")
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const Quality := preload("res://scripts/core/quality.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _box(parent: Node3D, color: Color, pos: Vector3, mat_keep: StandardMaterial3D = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	if mat_keep != null:
		bm.material = mat_keep
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		bm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


## 見えている部品（描く物）の数と、面（サーフェス）の数
func _draw_items(node: Node) -> Vector2i:
	var count := Vector2i.ZERO
	if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree():
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			count += Vector2i(1, (node as MeshInstance3D).mesh.get_surface_count())
		elif node is MultiMeshInstance3D:
			count += Vector2i(1, 1)
	for c in node.get_children():
		count += _draw_items(c)
	return count


func _initialize() -> void:
	await process_frame
	# まとめる仕組み
	var holder := Node3D.new()
	root.add_child(holder)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.5, 0.2, 0.8)
	_box(holder, Color(1, 0, 0), Vector3(0, 0, 0))
	_box(holder, Color(0, 0, 1), Vector3(2, 0, 0))
	_box(holder, Color(0, 1, 0), Vector3(-2, 0, 0))
	_box(holder, Color.WHITE, Vector3(0, 2, 0), skin)
	var joint := Node3D.new()
	holder.add_child(joint)
	_box(joint, Color(1, 1, 0), Vector3.ZERO)
	var cache := {}
	var merged := MeshMerge.merge_children(holder, [skin], cache)
	check(merged != null, "部品がまとまる")
	var direct_meshes := 0
	for c in holder.get_children():
		if c is MeshInstance3D:
			direct_meshes += 1
	check(direct_meshes == 1, "まとめたあと、親のすぐ下の部品は1つ：" + str(direct_meshes))
	check(joint.get_parent() == holder and joint.get_child_count() == 1, "動く関節（子の Node3D）は、そのまま残る")
	check(merged.mesh.get_surface_count() == 2, "色ちがいの部品は1つの面、肌は別の面（合わせて2つ）：" + str(merged.mesh.get_surface_count()))
	check(merged.mesh.surface_get_material(1) == skin or merged.mesh.surface_get_material(0) == skin, "肌の面は、肌の材質のまま（姿で色を変えられる）")
	var vc_mat: StandardMaterial3D = merged.mesh.surface_get_material(0) if merged.mesh.surface_get_material(0) != skin else merged.mesh.surface_get_material(1)
	check(vc_mat.vertex_color_use_as_albedo and cache.size() == 1, "ほかの部品は、頂点の色で描く材質（1つを使いまわす）")
	var arrays := merged.mesh.surface_get_arrays(0 if merged.mesh.surface_get_material(0) != skin else 1)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var red_ok := false
	var blue_ok := false
	for i in verts.size():
		if verts[i].x > 1.4 and colors[i].is_equal_approx(Color(0, 0, 1)):
			blue_ok = true
		if absf(verts[i].x) < 0.6 and colors[i].is_equal_approx(Color(1, 0, 0)):
			red_ok = true
	check(red_ok and blue_ok, "部品の位置と色が、頂点にうつっている")
	holder.queue_free()

	# ボス：部品の数
	var qcfg := Quality.load_config()
	var budget: Dictionary = qcfg.get("draw_budget", {})
	check(budget.has("boss") and budget.has("hero"), "部品の数の上限（data/quality.json の draw_budget）がある")
	var boss: Node3D = BM.new()
	root.add_child(boss)
	var bskin := StandardMaterial3D.new()
	boss.build(BM.load_config(), bskin)
	await process_frame
	var bn := _draw_items(boss)
	print("boss draw ", bn)
	check(bn.y <= int(budget.get("boss", 0)), "ボス（平常）を描く回数が上限以内：" + str(bn.y) + " / " + str(budget.get("boss", 0)))
	boss._apply_form("awake")
	await process_frame
	var ba := _draw_items(boss)
	print("boss awake draw ", ba)
	check(ba.y <= int(budget.get("boss_awake", 0)), "ボス（覚醒）を描く回数が上限以内：" + str(ba.y) + " / " + str(budget.get("boss_awake", 0)))
	check(boss.tail_mm != null and boss.tail_mm.multimesh.instance_count == BM.TailSegments, "しっぽの節は、まとめて描く（1回）")
	var oni := boss.model.find_child("OniCommon", true, false) as MeshInstance3D
	check(oni != null and oni.skin != null, "鬼の小物（角・髪・袖など）は、骨についていく1つの形（スキン）になる")
	check(boss.normal_items != null and boss.awake_items != null and boss.awake_items.visible and not boss.normal_items.visible, "覚醒では、バットを消して、はちまき・一升瓶を出す")
	boss._apply_form("normal")
	boss.set_flash(true)
	var all_flash := true
	for m in boss.mats:
		all_flash = all_flash and (m as StandardMaterial3D).emission_enabled and (m as StandardMaterial3D).emission_energy_multiplier > 0.0
	check(all_flash and boss.mats.has(boss.skin), "点滅は、まとめた形にも、肌にも出る")
	boss.set_flash(false)
	boss.queue_free()

	# 主人公：装備は1つのスキン付きの形にまとまる
	var cfg := CD.load_config()
	var hero := CD.find(cfg, "hero_swordsman")
	var v: Node3D = CV.new()
	root.add_child(v)
	check(v.setup(hero), "主人公を読み込める")
	await process_frame
	var items := v.model.find_child("Items", true, false) as MeshInstance3D
	check(items != null and items.skin != null, "装備は、骨についていく1つの形（スキン）になる")
	check(v.model.find_children("Item_*", "BoneAttachment3D", true, false).is_empty(), "骨ごとの小物の入れ物は、まとめたあと残らない")
	if items != null:
		var binds := []
		for i in items.skin.get_bind_count():
			binds.append(str(items.skin.get_bind_name(i)))
		check(binds.has("wrist.R") and binds.has("head") and binds.has("lowerarm01.L"), "刀（右手首）・結び髪（頭）・籠手（前腕）の骨につながる")
		check(items.mesh.get_surface_count() <= 4, "装備を描く回数は、材質の種類の数だけ（4回以内）：" + str(items.mesh.get_surface_count()))
	var hn := _draw_items(v)
	check(hn.y <= int(budget.get("hero", 0)), "主人公を描く回数が上限以内：" + str(hn.y) + " / " + str(budget.get("hero", 0)))
	v.queue_free()

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

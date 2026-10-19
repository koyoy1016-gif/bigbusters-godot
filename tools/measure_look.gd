extends SceneTree
## 見た目を当てはめた体の、高さごとの幅・奥行きを測る（部品を体の表面に置く位置を決めるため）。
## godot --headless --path . --script res://tools/measure_look.gd -- キャラのid
## 出す物：y ごとに、胴（|x|<0.25）の x の幅、z の前と後ろ。頭（y>1.7）の中心。全体の高さ。
const BodyBuilder := preload("res://scripts/characters/body_builder.gd")
const CD := preload("res://scripts/characters/character_data.gd")


func _initialize() -> void:
	var id := OS.get_cmdline_user_args()[0]
	var def: Dictionary = CD.find(CD.load_config(), id)
	var model: Node = (load("res://assets/models/hero_swordsman.glb") as PackedScene).instantiate()
	var look: Dictionary = BodyBuilder.load_looks().get(str(def.get("look", "")), {})
	print("tris ", BodyBuilder.apply(model, look))
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var body := sk.get_node("Human") as MeshInstance3D
	var pts := PackedVector3Array()
	for s in body.mesh.get_surface_count():
		pts.append_array(body.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	var top := -9.0
	for p in pts:
		top = maxf(top, p.y)
	print("top ", top)
	var y := 0.05
	while y < top:
		var xmin := 9.0
		var xmax := -9.0
		var zmin := 9.0
		var zmax := -9.0
		var lim := 0.25 if y > 0.95 and y < 1.7 else 9.0
		for p in pts:
			if absf(p.y - y) < 0.025 and absf(p.x) < lim:
				xmin = minf(xmin, p.x)
				xmax = maxf(xmax, p.x)
				zmin = minf(zmin, p.z)
				zmax = maxf(zmax, p.z)
		print("y %.2f  x[%.3f %.3f]  z[%.3f %.3f]" % [y, xmin, xmax, zmin, zmax])
		y += 0.05
	model.free()
	quit(0)

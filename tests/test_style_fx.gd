extends SceneTree
## 作風（質感・陰影・縁の光・輪郭線）のテスト

const SF := preload("res://scripts/characters/style_fx.gd")
const CV := preload("res://scripts/characters/character_view.gd")
var failures := 0


func check(ok: bool, name: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", name)


func _init() -> void:
	check(SF.texture("cloth") != null and SF.texture("steel") != null and SF.texture("skin") != null, "質感の画像が読める")
	check(SF.texture("nothing") == null, "ない名前は null")
	check(SF.texture_for(0.9) == "steel" and SF.texture_for(0.0) == "cloth" and SF.texture_for(0.0, "leather") == "leather", "質感の名前の決め方")
	var m := StandardMaterial3D.new()
	SF.style_material(m, "cloth")
	check(m.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON and m.rim_enabled and m.albedo_texture != null and m.uv1_triplanar, "段のついた陰影・縁の光・質感")
	for name in ["cloth", "steel", "skin", "leather"]:
		var img := (SF.texture(name) as Texture2D).get_image()
		check(img.get_width() <= 512 and img.get_height() <= 512, "質感は512以下: " + name)
	# 輪郭線の付け外し
	var root := Node3D.new()
	root.add_to_group("styled")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.material = StandardMaterial3D.new()
	mi.mesh = bm
	root.add_child(mi)
	var other := MeshInstance3D.new()
	var om := BoxMesh.new()
	om.material = StandardMaterial3D.new()
	other.mesh = om
	get_root().add_child(root)
	get_root().add_child(other)
	SF.set_outline(get_root(), true)
	check(bm.material.next_pass != null, "画質「高」で、輪郭線がつく")
	check(om.material.next_pass == null, "キャラ・ボス以外には、輪郭線をつけない")
	SF.set_outline(get_root(), false)
	check(bm.material.next_pass == null, "画質「低」で、輪郭線が外れる")
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/quality.json"))
	check(not bool(q["presets"]["low"]["outline"]) and bool(q["presets"]["high"]["outline"]), "輪郭線は「高」だけ")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

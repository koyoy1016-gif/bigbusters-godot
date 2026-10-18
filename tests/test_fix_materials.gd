extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_fix_materials.gd
## 書き出したモデルの材質直し（character_view.gd の fix_materials）を確かめる。

const CharacterView := preload("res://scripts/characters/character_view.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _make(mat_name: String) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.clearcoat_enabled = true
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _initialize() -> void:
	var holder := Node3D.new()
	var body := _make("Human.body")
	var hair := _make("Human.short04.003")
	var brow := _make("Human.eyebrow001")
	holder.add_child(body)
	holder.add_child(hair)
	body.add_child(brow)
	var n := CharacterView.fix_materials(holder, {})
	check(n == 3, "材質を3つ直した：" + str(n))
	var bm := body.mesh.surface_get_material(0) as StandardMaterial3D
	check(bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "体は不透明になる")
	check(bm.cull_mode == BaseMaterial3D.CULL_BACK, "裏は描かない")
	check(not bm.clearcoat_enabled, "クリアコートを切る")
	var hm := hair.mesh.surface_get_material(0) as StandardMaterial3D
	check(hm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "髪は切り抜きになる")
	var em := brow.mesh.surface_get_material(0) as StandardMaterial3D
	check(em.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "眉は切り抜きになる（子のノードでも直る）")
	var n2 := CharacterView.fix_materials(Node3D.new(), {})
	check(n2 == 0, "メッシュがなければ何もしない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

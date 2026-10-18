extends Node3D
## サブ敵の群れ。MultiMesh で、全員を1回の描画でまとめて出す。
## 数値は data/prototype_stick.json の sub_enemy_* にある。

const CrowdPattern := preload("res://scripts/combat/crowd_pattern.gd")

var multi: MultiMesh
var instance: MultiMeshInstance3D
var cfg: Dictionary = {}
var center := Vector2.ZERO
## 直近に並べた位置（確認用。ヘッドレスでは MultiMesh から読み戻せない）
var last_positions := PackedVector3Array()


func setup(config: Dictionary, boss_center: Vector2) -> void:
	cfg = config
	center = boss_center
	var count := int(cfg["sub_enemy_count"])
	var size: Array = cfg["sub_enemy_size"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size[0], size[1], size[2])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(cfg["sub_enemy_color"]))
	mesh.material = mat
	multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	instance = MultiMeshInstance3D.new()
	instance.name = "SubEnemies"
	instance.multimesh = multi
	add_child(instance)
	update_at(0.0)


## 戦いが始まってから t 秒の位置に並べ直す
func update_at(t: float) -> void:
	var count := multi.instance_count
	last_positions.resize(count)
	var h := float((cfg["sub_enemy_size"] as Array)[1]) * 0.5
	for i in count:
		var p := CrowdPattern.position_at(i, count, t, center, float(cfg["sub_enemy_radius"]), float(cfg["sub_enemy_speed"]), float(cfg["sub_enemy_wobble"]))
		var basis := Basis(Vector3.UP, CrowdPattern.heading_at(i, count, t, float(cfg["sub_enemy_speed"])))
		last_positions[i] = Vector3(p.x, h, p.y)
		multi.set_instance_transform(i, Transform3D(basis, last_positions[i]))

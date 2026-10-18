extends SubViewportContainer
## ハイライトの再生（3D）。ベストアタッカーの足あとの通りに動く箱を、後ろから追いかけるカメラで映す。
## ボスとサブ敵も、戦いの時間どおりに動く（サブ敵の動きは時間だけで決まるため再現できる）。
## 見た目は仮の箱。本物のキャラができたら差し替える。

const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")

var points: Array = []
var play_time := 0.0
var span := 0.0
var cam_distance := 7.0
var cam_height := 4.5
var cam_follow_per_sec := 6.0
var viewport: SubViewport
var camera: Camera3D
var player_box: MeshInstance3D
var player_material: StandardMaterial3D
var boss_box: MeshInstance3D
var crowd: Node3D
var boss_xz := Vector2.ZERO
var half := 15.0
var cam_pos := Vector3.ZERO
var built := false
var player_half_height := 0.5


func _build(config: Dictionary, flow_config: Dictionary) -> void:
	stretch = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	add_child(viewport)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(config["ground_size"])
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(str(config["ground_color"]))
	plane.material = gm
	ground.mesh = plane
	viewport.add_child(ground)
	var light := DirectionalLight3D.new()
	light.light_energy = float(config["light_energy"])
	var rot: Array = config["light_rotation_deg"]
	light.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	viewport.add_child(light)
	boss_box = _box(float(config["boss_size"]), Color(str(config["boss_color"])))
	boss_box.position = Vector3(boss_xz.x, float(config["boss_size"]) * 0.5, boss_xz.y)
	viewport.add_child(boss_box)
	player_box = _box(float(config["player_size"]), Color.WHITE)
	player_half_height = float(config["player_size"]) * 0.5
	player_material = player_box.mesh.material as StandardMaterial3D
	viewport.add_child(player_box)
	crowd = SubCrowd.new()
	viewport.add_child(crowd)
	crowd.setup(config, boss_xz)
	camera = Camera3D.new()
	camera.fov = float(config["camera_fov"])
	viewport.add_child(camera)
	cam_distance = float(flow_config.get("replay_cam_distance", cam_distance))
	cam_height = float(flow_config.get("replay_cam_height", cam_height))
	cam_follow_per_sec = float(flow_config.get("replay_cam_follow_per_sec", cam_follow_per_sec))
	built = true


func _box(size: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	m.mesh = mesh
	return m


## path_points：足あと [Vector3(時間, x, z)]。config：戦いの設定。flow_config：画面の流れの設定
func setup(path_points: Array, boss: Vector2, half_bounds: float, color: Color, config: Dictionary = {}, flow_config: Dictionary = {}) -> void:
	points = path_points
	boss_xz = boss
	half = half_bounds
	play_time = 0.0
	span = 0.0
	if not points.is_empty():
		span = (points[points.size() - 1] as Vector3).x - (points[0] as Vector3).x
	if not built and not config.is_empty():
		_build(config, flow_config)
	if built:
		player_material.albedo_color = color
		_place(true)


## 再生を進める。区間の終わりまで行ったら、最初から繰り返す
func advance(delta: float) -> void:
	play_time += delta
	var looped := false
	if span > 0.0 and play_time > span + 0.5:
		play_time = 0.0
		looped = true
	if built:
		_place(looped, delta)


func current_position() -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	return Recorder.position_on_path(points, (points[0] as Vector3).x + play_time)


## カメラの狙う位置：ボスから見てプレイヤーの後ろ側（ボスが奥に見える）
static func camera_target_position(player_xz: Vector2, boss: Vector2, distance: float, height: float) -> Vector3:
	var away := player_xz - boss
	var dir := away.normalized() if away.length() > 0.001 else Vector2(0, 1)
	return Vector3(player_xz.x + dir.x * distance, height, player_xz.y + dir.y * distance)


func _place(snap: bool, delta: float = 0.0) -> void:
	var p := current_position()
	var y: float = player_half_height
	player_box.position = Vector3(p.x, y, p.y)
	var t := (points[0] as Vector3).x + play_time if not points.is_empty() else play_time
	crowd.update_at(t)
	var want := camera_target_position(p, boss_xz, cam_distance, cam_height)
	cam_pos = want if snap else cam_pos.lerp(want, clampf(cam_follow_per_sec * delta, 0.0, 1.0))
	var look := Vector3(p.x, 1.0, p.y)
	camera.transform = Transform3D(Basis.looking_at(look - cam_pos, Vector3.UP), cam_pos)

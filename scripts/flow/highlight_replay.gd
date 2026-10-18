extends SubViewportContainer
## ハイライトの再生（3D）。ベストアタッカーの足あとの通りに動く箱を、後ろから追いかけるカメラで映す。
## ボスとサブ敵も、戦いの時間どおりに動く（サブ敵の動きは時間だけで決まるため再現できる）。
## 本物のモデルがあるキャラなら、そのモデル（走る・待つ・ボスの近くではこうげき）で出す。なければ箱

const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")

var points: Array = []
var play_time := 0.0
var span := 0.0
var cam_distance := 7.0
var cam_height := 4.5
var cam_follow_per_sec := 6.0
var viewport: SubViewport
var camera: Camera3D
var cam_look := Vector3.ZERO
var player_box: MeshInstance3D
var player_material: StandardMaterial3D
var boss_box: MeshInstance3D
var crowd: Node3D
var boss_xz := Vector2.ZERO
var half := 15.0
var cam_pos := Vector3.ZERO
var built := false
var player_half_height := 0.5
var char_view: Node3D = null  ## 本物のモデルの見た目（なければ null で、箱）
var last_xz := Vector2.ZERO
var has_last := false
var attack_distance := 4.0
var attack_repeat_sec := 0.8
var attack_timer := 0.0
var moving_speed := 0.5
var flow_cfg: Dictionary = {}
var char_def: Dictionary = {}


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
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(config["ambient_color"]))
	env.ambient_light_energy = float(config["ambient_energy"])
	camera.environment = env
	viewport.add_child(camera)
	flow_cfg = flow_config
	attack_distance = float(flow_config.get("replay_attack_distance", attack_distance))
	attack_repeat_sec = float(flow_config.get("replay_attack_repeat_sec", attack_repeat_sec))
	moving_speed = float(flow_config.get("replay_moving_speed", moving_speed))
	cam_distance = float(flow_config.get("replay_cam_distance", cam_distance))
	cam_height = float(flow_config.get("replay_cam_height", cam_height))
	cam_follow_per_sec = float(flow_config.get("replay_cam_follow_per_sec", cam_follow_per_sec))
	built = true


## キャラを切り替える。モデルがあれば箱を隠してモデルを出す。なければ箱
func _set_character(character: Dictionary) -> void:
	var same: bool = char_view != null and character.get("id", "") == char_def.get("id", "-")
	if same:
		return
	if char_view != null:
		char_view.queue_free()
		char_view = null
	char_def = character
	player_box.visible = true
	if character.is_empty() or not CharacterData.has_model(character):
		return
	var view := CharacterView.new()
	if not view.setup(character):
		view.free()
		return
	viewport.add_child(view)
	char_view = view
	player_box.visible = false


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
func setup(path_points: Array, boss: Vector2, half_bounds: float, color: Color, config: Dictionary = {}, flow_config: Dictionary = {}, character: Dictionary = {}) -> void:
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
		_set_character(character)
		has_last = false
		attack_timer = 0.0
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


## カメラの枠どり：プレイヤーとボスの両方が画面に入る。2人の真ん中を見て、斜め後ろから、離れているほど引く
## 戻り値：{pos: カメラの位置, look: 見る位置}
static func camera_frame(player_xz: Vector2, boss: Vector2, distance: float, height: float) -> Dictionary:
	var away := player_xz - boss
	var gap := away.length()
	var dir := away / gap if gap > 0.001 else Vector2(0, 1)
	var side := Vector2(-dir.y, dir.x)
	var back := (dir * 0.6 + side * 0.8).normalized()
	var mid := (player_xz + boss) * 0.5
	var d := distance + gap * 0.5
	return {"pos": Vector3(mid.x + back.x * d, height + gap * 0.3, mid.y + back.y * d), "look": Vector3(mid.x, 1.2, mid.y)}


func _place(snap: bool, delta: float = 0.0) -> void:
	var p := current_position()
	var y: float = player_half_height
	player_box.position = Vector3(p.x, y, p.y)
	if char_view != null:
		_update_character(p, snap, delta)
	var t := (points[0] as Vector3).x + play_time if not points.is_empty() else play_time
	crowd.update_at(t)
	var frame := camera_frame(p, boss_xz, cam_distance, cam_height)
	var want: Vector3 = frame["pos"]
	var k := clampf(cam_follow_per_sec * delta, 0.0, 1.0)
	cam_pos = want if snap else cam_pos.lerp(want, k)
	cam_look = frame["look"] if snap else cam_look.lerp(frame["look"], k)
	var look := cam_look
	camera.transform = Transform3D(Basis.looking_at(look - cam_pos, Vector3.UP), cam_pos)


## モデルの位置・向き・動き。動いていれば走る、止まっていれば待つ、ボスの近くならこうげき（くり返す）
func _update_character(p: Vector2, snap: bool, delta: float) -> void:
	char_view.position = Vector3(p.x, 0.0, p.y)
	var step := Vector2.ZERO
	if has_last and not snap and delta > 0.0:
		step = (p - last_xz) / delta
	last_xz = p
	has_last = true
	var to_boss := boss_xz - p
	var near_boss := to_boss.length() <= attack_distance
	attack_timer = maxf(0.0, attack_timer - delta)
	if near_boss:
		char_view.face(to_boss, delta)
		if attack_timer <= 0.0:
			char_view.current_action = ""
			char_view.play_action("attack")
			attack_timer = attack_repeat_sec
		elif attack_timer < attack_repeat_sec - 0.55:
			char_view.play_action("idle")
	else:
		attack_timer = 0.0
		var moving := step.length() > moving_speed
		char_view.play_action("run" if moving else "idle")
		if moving:
			char_view.face(step, delta)

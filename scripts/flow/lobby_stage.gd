extends Node3D
## 版81：ロビーの3Dの場面。まんなかにメインキャラ1人、後ろに編成の3人を、奥行きをつけて並べる。
## 編成が回る（スライド・タップ）と、同じキャラの形をそのまま新しい場所へ、なめらかに動かす（作り直さない）。
## 背景は、空の色と、遠くのビルの並び（2列。版86でくわしくする）。数値は data/lobby.json。
## 戦いに入るときは、game_flow.gd がこの場面ごと消す（ロビーの3Dを戦いに残さない）。

const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const CONFIG_PATH := "res://data/lobby.json"

var cfg: Dictionary = {}
var characters_cfg: Dictionary = {}
var camera: Camera3D
## 並んでいるキャラ：[{id, holder（場所と大きさ）, view（キャラの形。なければ null）, slot, from, t}]
var units: Array = []
var team: Array = []
var built_count := 0  # 作ったキャラの形の数（テストで、作り直していないかを見る）


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func setup(chars: Dictionary, config: Dictionary = {}) -> void:
	cfg = config if not config.is_empty() else load_config()
	characters_cfg = chars
	name = "LobbyStage"
	_build_world()


func _v3(key: String) -> Vector3:
	var a: Array = cfg[key]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _slot_pos(i: int) -> Vector3:
	var a: Array = (cfg["slots"] as Array)[i]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _build_world() -> void:
	# 空（上は青紫、地平は夕方のだいだい）
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(str(cfg["sky_top"]))
	sky_mat.sky_horizon_color = Color(str(cfg["sky_horizon"]))
	sky_mat.ground_horizon_color = Color(str(cfg["sky_horizon"]))
	sky_mat.ground_bottom_color = Color(str(cfg["ground_bottom"]))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(cfg["ambient_color"]))
	env.ambient_light_energy = float(cfg["ambient_energy"])
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
	# 光：夕日（影は画質の設定にまかせる）と、後ろからの青い光（体の縁を光らせて、背景から浮かせる）
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var d := _v3("sun_dir_deg")
	sun.rotation_degrees = d
	sun.light_color = Color(str(cfg["sun_color"]))
	sun.light_energy = float(cfg["sun_energy"])
	sun.add_to_group("sun")
	add_child(sun)
	var rim := OmniLight3D.new()
	rim.name = "Rim"
	rim.position = _v3("rim_pos")
	rim.light_color = Color(str(cfg["rim_color"]))
	rim.light_energy = float(cfg["rim_energy"])
	rim.omni_range = 7.0
	add_child(rim)
	# 床と、メインキャラの足もとの光る輪
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(str(cfg["ground_color"]))
	gm.roughness = 1.0
	pm.material = gm
	ground.mesh = pm
	ground.position = Vector3(0, 0, -10)
	add_child(ground)
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var tm := TorusMesh.new()
	tm.inner_radius = 1.25
	tm.outer_radius = 1.4
	tm.rings = 40
	tm.ring_segments = 4
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(str(cfg["stage_disc_color"]))
	tm.material = dm
	disc.mesh = tm
	disc.scale = Vector3(1, 0.05, 1)
	disc.position = _slot_pos(0) + Vector3(0, 0.03, 0)
	add_child(disc)
	add_child(_city())
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = _v3("camera_pos")
	add_child(camera)
	camera.look_at_from_position(camera.position, _v3("camera_look"), Vector3.UP)
	camera.current = true
	fit_camera(Vector2(648, 1152))


## 画面が縦長か横長かで、カメラの広さを変える（縦でも4人が入るように）
func fit_camera(screen: Vector2) -> void:
	if camera == null:
		return
	var portrait := screen.y > screen.x
	camera.fov = float(cfg["fov_portrait"]) if portrait else float(cfg["fov_landscape"])
	var look := _v3("camera_look") if portrait or not cfg.has("camera_look_landscape") else _v3("camera_look_landscape")
	if camera.is_inside_tree():
		camera.look_at_from_position(_v3("camera_pos"), look, Vector3.UP)
	else:
		camera.position = _v3("camera_pos")
		camera.basis = Basis.looking_at(look - _v3("camera_pos"), Vector3.UP)


## 遠くのビルの並び（列ごとに1つの形にまとめる。窓の光は頂点の色）
func _city() -> Node3D:
	var root := Node3D.new()
	root.name = "City"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("city_seed", 1))
	for layer in cfg["city_layers"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := int(layer["count"])
		var spread := float(layer["spread"])
		var body := Color(str(layer["color"]))
		var win := Color(str(layer["window"]))
		for i in n:
			var w := rng.randf_range(float(layer["width"][0]), float(layer["width"][1]))
			var h := rng.randf_range(float(layer["height"][0]), float(layer["height"][1]))
			var x := -spread * 0.5 + spread * (float(i) + rng.randf_range(0.1, 0.9)) / float(n)
			var z := float(layer["z"]) + rng.randf_range(-1.5, 1.5)
			_box(st, Vector3(x, h * 0.5, z), Vector3(w, h, w * 0.8), body)
			# 窓（手前の面に、光る小さな四角を数こ）
			var rows := int(h / 1.6)
			for r in rows:
				if rng.randf() < 0.45:
					continue
				var wx := x + rng.randf_range(-w * 0.3, w * 0.3)
				_box(st, Vector3(wx, 0.9 + r * 1.6, z + w * 0.4 + 0.02), Vector3(0.45, 0.55, 0.04), win)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)]]
	for f in faces:
		var q: Array = []
		for v in f:
			q.append(c + (v as Vector3) * h)
		st.set_color(col)
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[k])


## 編成（4人のキャラID。0 がメイン）を並べる。同じキャラは、形を作り直さずに新しい場所へ動かす
func set_team(ids: Array) -> void:
	team = ids.duplicate()
	var old := units
	units = []
	var used := {}
	for i in ids.size():
		var id := str(ids[i])
		var found := -1
		for k in old.size():
			if not used.has(k) and str(old[k]["id"]) == id:
				found = k
				break
		var u: Dictionary
		if found >= 0:
			used[found] = true
			u = old[found]
			u["from"] = (u["holder"] as Node3D).position
			u["from_scale"] = (u["holder"] as Node3D).scale.x
			u["t"] = 0.0
		else:
			u = _make_unit(id, i)
		u["slot"] = i
		units.append(u)
	for k in old.size():
		if not used.has(k):
			(old[k]["holder"] as Node).queue_free()


func _make_unit(id: String, slot: int) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "Unit_" + id
	holder.position = _slot_pos(slot)
	holder.scale = Vector3.ONE * 0.01
	add_child(holder)
	var view: Node3D = null
	var def := CharacterData.find(characters_cfg, id)
	if not def.is_empty() and CharacterData.has_model(def):
		var v := CharacterView.new()
		if v.setup(def):
			holder.add_child(v)
			v.play_action("idle")
			view = v
			built_count += 1
		else:
			v.free()
	return {"id": id, "holder": holder, "view": view, "slot": slot, "from": holder.position, "from_scale": 0.01, "t": 0.0}


func _process(delta: float) -> void:
	step(delta)


## 動きを1コマ進める：新しい場所へ、なめらかに（少し回りながら）動く
func step(delta: float) -> void:
	var dur := maxf(float(cfg.get("move_sec", 0.35)), 0.01)
	for u in units:
		var holder: Node3D = u["holder"]
		if not is_instance_valid(holder):
			continue
		var slot := int(u["slot"])
		u["t"] = minf(1.0, float(u["t"]) + delta / dur)
		var k := smoothstep(0.0, 1.0, float(u["t"]))
		var goal := _slot_pos(slot)
		var goal_s := float((cfg["slot_scale"] as Array)[slot])
		holder.position = (u["from"] as Vector3).lerp(goal, k)
		holder.scale = Vector3.ONE * lerpf(float(u["from_scale"]), goal_s, k)
		var turn := deg_to_rad(float((cfg["slot_turn_deg"] as Array)[slot]))
		holder.rotation.y = turn + deg_to_rad(float(cfg.get("spin_deg", 0.0))) * sin(PI * k) * (1.0 if float(u["t"]) < 1.0 else 0.0)


## 動きを終わらせる（テスト用）
func finish() -> void:
	step(999.0)


## 画面の点 p に、いちばん近いキャラの場所の番号（遠ければ -1）
func pick(p: Vector2, radius_px: float = -1.0) -> int:
	if camera == null or not camera.is_inside_tree():
		return -1
	var r := radius_px if radius_px > 0.0 else float(cfg["pick_radius_px"])
	var best := -1
	var best_d := r
	for u in units:
		var holder: Node3D = u["holder"]
		if not is_instance_valid(holder):
			continue
		var h := float(cfg["pick_height_m"]) * holder.scale.x
		var sp := camera.unproject_position(holder.global_position + Vector3(0, h, 0))
		var dd := sp.distance_to(p)
		if dd < best_d:
			best_d = dd
			best = int(u["slot"])
	return best


## 場所 slot の、画面の上の点（テスト・矢印の位置）
func screen_point(slot: int) -> Vector2:
	for u in units:
		if int(u["slot"]) == slot and camera != null and camera.is_inside_tree():
			var holder: Node3D = u["holder"]
			return camera.unproject_position(holder.global_position + Vector3(0, float(cfg["pick_height_m"]) * holder.scale.x, 0))
	return Vector2(-9999, -9999)

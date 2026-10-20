extends RefCounted
## 版88：戦いのマップを読む（data/maps.json の current。いまは渋谷のスクランブル交差点）。
## マップの 3D は tools/plateau_to_glb.py が PLATEAU から作った .glb（Terrain・Ground・Crosswalk・BldgNear・BldgFar・Signs・Screens）。
## 版89：建物の材質（タイル・ガラス・パネル）、自作の看板・大画面（絵は signs.png）。
## 交差点のまん中がゲームの (0,0,0)。戦いの場所（±bounds）は平らで、高さ 0（今までの緑の板と同じ高さ）。
## ここでは：材質（頂点の色・建物の窓のシェーダー）・見える距離（画質ごと）・影・空と霧と光・戦いの場所のさかい（光る線とうすい壁）を付ける。
## 動ける範囲そのもの（外へ出られない）は、今までどおり prototype_stick.json の bounds で、動きの計算が決める。

const CONFIG_PATH := "res://data/maps.json"
const BUILDING_SHADER := preload("res://shaders/city_buildings.gdshader")
const SIGN_SHADER := preload("res://shaders/city_signs.gdshader")
const SCREEN_SHADER := preload("res://shaders/city_screens.gdshader")

const GROUND_MESHES := ["Terrain", "Ground", "Crosswalk"]
const BUILDING_MESHES := ["BldgNear", "BldgFar"]
const SIGN_MESHES := ["Signs", "Screens"]


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## いまのマップの設定（なければ {}）
static func current_map(cfg: Dictionary = {}) -> Dictionary:
	if cfg.is_empty():
		cfg = load_config()
	var maps: Dictionary = cfg.get("maps", {})
	var m: Variant = maps.get(str(cfg.get("current", "")), null)
	return (m as Dictionary).duplicate(true) if m is Dictionary else {}


## マップを作る（読めなければ null）。bounds：戦いの場所の半分の幅（m）
static func build(map_cfg: Dictionary, quality: String, bounds: float) -> Node3D:
	var path := str(map_cfg.get("glb", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := Node3D.new()
	root.name = "Map"
	root.set_meta("map_name", str(map_cfg.get("name", "")))
	var scene := packed.instantiate()
	scene.name = "City"
	root.add_child(scene)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.vertex_color_use_as_albedo = true
	ground_mat.roughness = 0.95
	var cross_mat := StandardMaterial3D.new()
	cross_mat.vertex_color_use_as_albedo = true
	cross_mat.roughness = 0.7
	var bmat := ShaderMaterial.new()
	bmat.shader = BUILDING_SHADER
	var w: Dictionary = map_cfg.get("windows", {})
	for k in w:
		bmat.set_shader_parameter(str(k), float(w[k]))
	bmat.set_shader_parameter("fade_far", float((map_cfg.get("visible_m", {}) as Dictionary).get("high", 480.0)) * 0.8)
	var sky_cfg: Dictionary = map_cfg.get("sky", {})
	bmat.set_shader_parameter("sky_top", Color(str(sky_cfg.get("top", "#3a5390"))))
	bmat.set_shader_parameter("sky_horizon", Color(str(sky_cfg.get("horizon", "#f0b48a"))))
	var sc: Dictionary = map_cfg.get("signs", {})
	var atlas: Texture2D = null
	var ap := str(sc.get("atlas", ""))
	if ap != "" and ResourceLoader.exists(ap):
		atlas = load(ap) as Texture2D
	var smat := ShaderMaterial.new()
	smat.shader = SIGN_SHADER
	smat.set_shader_parameter("atlas", atlas)
	smat.set_shader_parameter("glow", float(sc.get("glow", 0.35)))
	smat.set_shader_parameter("glow_night", float(sc.get("glow_night", 1.1)))
	var scr := ShaderMaterial.new()
	scr.shader = SCREEN_SHADER
	scr.set_shader_parameter("atlas", atlas)
	scr.set_shader_parameter("glow", float(sc.get("screen_glow", 0.9)))
	scr.set_shader_parameter("glow_night", float(sc.get("screen_glow_night", 1.5)))
	scr.set_shader_parameter("hold_sec", float(sc.get("hold_sec", 6.0)))
	scr.set_shader_parameter("fade_sec", float(sc.get("fade_sec", 0.6)))
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := str(m.name)
		if nm in GROUND_MESHES:
			m.material_override = cross_mat if nm == "Crosswalk" else ground_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif nm in BUILDING_MESHES:
			m.material_override = bmat
		elif nm in SIGN_MESHES:
			m.material_override = scr if nm == "Screens" else smat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_meta("map_part", nm)
	root.add_child(_border(map_cfg.get("border", {}), bounds))
	set_quality(root, map_cfg, quality)
	return root


## 画質：遠い建物の見える距離・建物の影
static func set_quality(root: Node3D, map_cfg: Dictionary, quality: String) -> void:
	if root == null:
		return
	var vis: Dictionary = map_cfg.get("visible_m", {})
	var far := float(vis.get(quality, vis.get("low", 330.0)))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var part := str(m.get_meta("map_part", ""))
		if part == "":
			continue
		if part == "BldgFar" or part == "Terrain":
			m.visibility_range_end = far
			m.visibility_range_end_margin = 20.0
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if part == "BldgNear":
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality == "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif part == "BldgFar":
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("quality", quality)


## 空（夕方のグラデーション）・霧・まわりの明るさ
static func apply_environment(env: Environment, map_cfg: Dictionary) -> void:
	var sky_cfg: Dictionary = map_cfg.get("sky", {})
	if not sky_cfg.is_empty():
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(str(sky_cfg.get("top", "#2a3a6e")))
		sm.sky_horizon_color = Color(str(sky_cfg.get("horizon", "#f2a36b")))
		sm.ground_horizon_color = Color(str(sky_cfg.get("horizon", "#f2a36b")))
		sm.ground_bottom_color = Color(str(sky_cfg.get("ground", "#3a3440")))
		sm.sky_energy_multiplier = float(sky_cfg.get("energy", 1.0))
		sm.sun_angle_max = 20.0
		var sky := Sky.new()
		sky.sky_material = sm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
	var amb: Dictionary = map_cfg.get("ambient", {})
	if not amb.is_empty():
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(str(amb.get("color", "#c9c3d6")))
		env.ambient_light_energy = float(amb.get("energy", 0.7))
	var fog: Dictionary = map_cfg.get("fog", {})
	if not fog.is_empty():
		env.fog_enabled = true
		env.fog_light_color = Color(str(fog.get("color", "#c98f7a")))
		env.fog_density = float(fog.get("density", 0.0035))
		env.fog_sky_affect = float(fog.get("sky_affect", 0.4))


static func apply_light(light: DirectionalLight3D, map_cfg: Dictionary) -> void:
	var lc: Dictionary = map_cfg.get("light", {})
	if light == null or lc.is_empty():
		return
	var r: Array = lc.get("rotation_deg", [-45.0, 30.0, 0.0])
	light.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	light.light_color = Color(str(lc.get("color", "#ffffff")))
	light.light_energy = float(lc.get("energy", 1.0))


## 戦いの場所のさかい：床の光る線と、下が濃く上がうすい、すけた壁（ここから外へは出られない、の目じるし）
static func _border(bc: Dictionary, half: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Border"
	var col := Color(str(bc.get("color", "#7fd7ff")))
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(col.r, col.g, col.b, float(bc.get("alpha", 0.55)))
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, float(bc.get("wall_alpha", 0.14))))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	wall_mat.albedo_texture = gt
	var h := float(bc.get("wall_h", 1.4))
	for i in 4:
		var ang := float(i) * PI * 0.5
		var dir := Vector3(sin(ang), 0, cos(ang))
		var line := MeshInstance3D.new()
		line.name = "Line%d" % i
		var qm := QuadMesh.new()
		qm.size = Vector2(half * 2.0 + 0.12, 0.12)
		qm.orientation = PlaneMesh.FACE_Y
		qm.material = line_mat
		line.mesh = qm
		line.position = dir * half + Vector3(0, 0.035, 0)
		line.rotation.y = ang
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(line)
		var wall := MeshInstance3D.new()
		wall.name = "Wall%d" % i
		var wm := QuadMesh.new()
		wm.size = Vector2(half * 2.0, h)
		wm.material = wall_mat
		wall.mesh = wm
		wall.position = dir * half + Vector3(0, h * 0.5, 0)
		wall.rotation.y = ang
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wall)
	return root

extends Node3D
## 版81：ロビーの3Dの場面。まんなかにメインキャラ1人、後ろに編成の3人を、奥行きをつけて並べる。
## 編成が回る（スライド・タップ）と、同じキャラの形をそのまま新しい場所へ、なめらかに動かす（作り直さない）。
## 版81b：仕上げ。メインは光る台の上（金の輪がゆっくり脈打つ）、足もとにやわらかい影、空気の遠近（霧）、
##   夕方の空・太陽の光・流れる雲、街並み3列（窓の明かりがまたたく・遠くの塔の赤いランプ）、広場の街灯と手すり、
##   キャラのまわりをただよう光の粒、カメラのゆっくりしたゆれ、スライド中の奥行き（カメラが少し横へ）。
## 版94（ユーザーの指示）：キャラはふだん静止（待ちの動きの最初の形で止める。動かない）。
##   前（まんなか）に持ってこられた時だけ、そのキャラの A攻撃（戦いの「normal」＝右下のいちばん大きいボタンの技）を1回して、静止にもどる。
##   後ろへ行ったキャラは、すぐ静止。はじめてロビーを出した時は、だれも攻撃しない（静止）。
##   動きは戦いと同じ：data/char_actions.json（剣士は data/actions.json）の normal の最初の steps の anim と speed を、
##   キャラの形の play_step で流す（戦いと同じ関数）。当たり・音・光・待ち時間などの戦いの処理は呼ばない（動きだけ）。
##   A攻撃の動きがないキャラは、静止のまま（unsupported に記録）。止めている間は再生係が動かないので、軽い。
##   （版93 の「休まずくり返す」はやめた）
## 数値は data/lobby.json。戦いに入るときは、game_flow.gd がこの場面ごと消す（ロビーの3Dを戦いに残さない）。

const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const WINDOW_SHADER := preload("res://shaders/lobby_windows.gdshader")
const GROUND_SHADER := preload("res://shaders/lobby_ground.gdshader")
const CONFIG_PATH := "res://data/lobby.json"

var cfg: Dictionary = {}
var characters_cfg: Dictionary = {}
var camera: Camera3D
## 並んでいるキャラ：[{id, holder（場所と大きさ）, view（キャラの形。なければ null）, slot, from, t, cheer}]
var units: Array = []
var team: Array = []
var built_count := 0  # 作ったキャラの形の数（テストで、作り直していないかを見る）
var drag := 0.0  # スライド中の量（-1〜1）。カメラを少し横へ
var drag_now := 0.0
var clock := 0.0
var quality := "low"
var cam_base := Vector3.ZERO
var cam_look := Vector3.ZERO
var ring_mat: StandardMaterial3D
var beacon_mat: StandardMaterial3D
var clouds: Array = []
var motes: CPUParticles3D
var rng := RandomNumberGenerator.new()
var attack_cache: Dictionary = {}  ## 版93・94：キャラID → {anim（キャラの animations の名前）, speed}。なければ {}（設定を何度も読まない）
var unsupported: Array = []  ## 版93・94：A攻撃の動きがなく、静止のままのキャラID
const ATTACK_ACTION := "normal"  ## 版93：A攻撃＝戦いの normal（char_actions.json では label "A"）


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func setup(chars: Dictionary, config: Dictionary = {}) -> void:
	cfg = config if not config.is_empty() else load_config()
	characters_cfg = chars
	name = "LobbyStage"
	rng.seed = int(cfg.get("city_seed", 1))
	_build_world()


func _v3(key: String) -> Vector3:
	var a: Array = cfg[key]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _slot_pos(i: int) -> Vector3:
	var a: Array = (cfg["slots"] as Array)[i]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _unshaded(col: Color, alpha: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if alpha or col.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## やわらかい光の板（いつもカメラを向く。足し算で明るく）
func _glow_sprite(col: Color, size_m: float, pos: Vector3) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = Vector2(size_m, size_m)
	var m := _unshaded(col, true)
	m.albedo_texture = UiKit.soft_dot(64)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.disable_fog = true
	qm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_world() -> void:
	# 空（上は青紫、地平は夕方のだいだい）と、空気の遠近（遠くほど、地平の色にとける）
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(str(cfg["sky_top"]))
	sky_mat.sky_horizon_color = Color(str(cfg["sky_horizon"]))
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(str(cfg["sky_horizon"]))
	sky_mat.ground_bottom_color = Color(str(cfg["ground_bottom"]))
	sky_mat.sun_angle_max = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(cfg["ambient_color"]))
	env.ambient_light_energy = float(cfg["ambient_energy"])
	env.fog_enabled = true
	env.fog_light_color = Color(str(cfg.get("fog_color", "#7a5f96")))
	env.fog_density = float(cfg.get("fog_density", 0.016))
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(cfg.get("exposure", 1.05))
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
	# 光：夕日（影は画質の設定にまかせる）・後ろから青と桃色の光（体の縁を光らせて、背景から浮かせる）
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = _v3("sun_dir_deg")
	sun.light_color = Color(str(cfg["sun_color"]))
	sun.light_energy = float(cfg["sun_energy"])
	sun.add_to_group("sun")
	add_child(sun)
	for rim in cfg.get("rims", []):
		var o := OmniLight3D.new()
		o.name = "Rim"
		var p: Array = rim["pos"]
		o.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		o.light_color = Color(str(rim["color"]))
		o.light_energy = float(rim["energy"])
		o.omni_range = float(rim.get("range", 7.0))
		add_child(o)
	_build_ground()
	_build_platform()
	_build_sky_things()
	add_child(_city())
	_build_plaza()
	_build_motes()
	camera = Camera3D.new()
	camera.name = "Camera"
	cam_base = _v3("camera_pos")
	cam_look = _v3("camera_look")
	camera.position = cam_base
	add_child(camera)
	camera.look_at_from_position(cam_base, cam_look, Vector3.UP)
	camera.current = true
	fit_camera(Vector2(648, 1152))


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 70)
	var sm := ShaderMaterial.new()
	sm.shader = GROUND_SHADER
	sm.set_shader_parameter("base_color", Color(str(cfg["ground_color"])))
	sm.set_shader_parameter("line_color", Color(str(cfg.get("ground_line", "#544a72"))))
	sm.set_shader_parameter("glow_color", Color(str(cfg.get("ground_glow", "#8a5a44"))))
	pm.material = sm
	ground.mesh = pm
	ground.position = Vector3(0, 0, -15)
	add_child(ground)


## メインキャラの台：段になった円い台・金の輪（脈打つ）・内側の細い輪
func _build_platform() -> void:
	var top := float(cfg.get("platform_height", 0.22))
	var base := MeshInstance3D.new()
	base.name = "Platform"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.75
	cm.bottom_radius = 1.95
	cm.height = top
	cm.radial_segments = 48
	cm.rings = 1
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(str(cfg.get("platform_color", "#1f2746")))
	pm.metallic = 0.55
	pm.roughness = 0.32
	cm.material = pm
	base.mesh = cm
	base.position = _slot_pos(0) + Vector3(0, top * 0.5, 0)
	add_child(base)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = 1.66
	tm.outer_radius = 1.76
	tm.rings = 64
	tm.ring_segments = 6
	ring_mat = _unshaded(Color(str(cfg["stage_disc_color"])))
	ring_mat.disable_fog = true
	tm.material = ring_mat
	ring.mesh = tm
	ring.scale = Vector3(1, 0.35, 1)
	ring.position = _slot_pos(0) + Vector3(0, top + 0.01, 0)
	add_child(ring)
	var inner := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 1.12
	tm2.outer_radius = 1.15
	tm2.rings = 48
	tm2.ring_segments = 4
	tm2.material = _unshaded(Color(str(cfg["stage_disc_color"])).darkened(0.2))
	inner.mesh = tm2
	inner.scale = Vector3(1, 0.2, 1)
	inner.position = _slot_pos(0) + Vector3(0, top + 0.01, 0)
	add_child(inner)
	# 台の上の、やわらかい光（下から照らされているように）
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(4.6, 4.6)
	hq.orientation = PlaneMesh.FACE_Y
	var hm := _unshaded(Color(str(cfg.get("platform_glow", "#ffcf6a40"))), true)
	hm.albedo_texture = UiKit.soft_dot(64)
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.disable_fog = true
	hq.material = hm
	halo.mesh = hq
	halo.position = _slot_pos(0) + Vector3(0, top + 0.02, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)


## 太陽の光・流れる雲
func _build_sky_things() -> void:
	var sp: Array = cfg.get("sun_glow_pos", [7.0, 5.0, -48.0])
	add_child(_glow_sprite(Color(str(cfg.get("sun_glow", "#ffb46ad0"))), float(cfg.get("sun_glow_size", 26.0)), Vector3(float(sp[0]), float(sp[1]), float(sp[2]))))
	add_child(_glow_sprite(Color("#fff0c8"), float(cfg.get("sun_glow_size", 26.0)) * 0.22, Vector3(float(sp[0]), float(sp[1]), float(sp[2]) + 0.5)))
	clouds = []
	for i in int(cfg.get("cloud_count", 5)):
		var qm := QuadMesh.new()
		qm.size = Vector2(rng.randf_range(12.0, 20.0), rng.randf_range(2.6, 4.4))
		var m := _unshaded(Color(str(cfg.get("cloud_color", "#ffd2c4"))).darkened(rng.randf_range(0.0, 0.25)), true)
		m.albedo_color.a = rng.randf_range(0.28, 0.45)
		m.albedo_texture = UiKit.soft_dot(64)
		m.disable_fog = true
		qm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.position = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(12.0, 22.0), rng.randf_range(-58.0, -46.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		clouds.append({"node": mi, "speed": rng.randf_range(0.25, 0.6)})


## 遠くの街並み（列ごとに1つの形にまとめる。ビルは上が明るい色、窓の明かりは別の形で、またたく）
func _city() -> Node3D:
	var root := Node3D.new()
	root.name = "City"
	for layer in cfg["city_layers"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wst := SurfaceTool.new()
		wst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := int(layer["count"])
		var spread := float(layer["spread"])
		var body := Color(str(layer["color"]))
		var lit := body.lerp(Color(str(cfg.get("rooftop_light", "#d98a7a"))), float(layer.get("rim", 0.35)))
		var win := Color(str(layer["window"]))
		for i in n:
			var w := rng.randf_range(float(layer["width"][0]), float(layer["width"][1]))
			var h := rng.randf_range(float(layer["height"][0]), float(layer["height"][1]))
			var x := -spread * 0.5 + spread * (float(i) + rng.randf_range(0.1, 0.9)) / float(n)
			var z := float(layer["z"]) + rng.randf_range(-1.5, 1.5)
			var d := w * rng.randf_range(0.7, 1.0)
			_box(st, Vector3(x, h * 0.5, z), Vector3(w, h, d), body.darkened(0.25), lit)
			# 上の段（細くなる）・屋上のアンテナ
			if rng.randf() < 0.45:
				var h2 := h * rng.randf_range(0.15, 0.3)
				_box(st, Vector3(x, h + h2 * 0.5, z), Vector3(w * 0.62, h2, d * 0.62), body.darkened(0.1), lit.lightened(0.05))
				h += h2
			if rng.randf() < 0.35:
				_box(st, Vector3(x + w * 0.2, h + 0.9, z), Vector3(0.08, 1.8, 0.08), body, lit)
			# 窓（手前の面に、光る小さな四角を並べる）
			var rows := int((h - 0.8) / 0.95)
			var cols := maxi(2, int(w / 0.75))
			for r in rows:
				for c in cols:
					if rng.randf() < float(layer.get("dark_ratio", 0.5)):
						continue
					var wx := x - w * 0.5 + (float(c) + 0.5) * w / float(cols)
					var wy := 0.9 + r * 0.95
					if wy > h - 0.5:
						continue
					var wc := win.lerp(Color("#a8d4ff"), 0.6) if rng.randf() < 0.18 else win
					_box(wst, Vector3(wx, wy, z + d * 0.5 + 0.03), Vector3(0.5 * w / float(cols), 0.4, 0.04), wc, wc)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var wmat := ShaderMaterial.new()
		wmat.shader = WINDOW_SHADER
		var wmi := MeshInstance3D.new()
		wmi.mesh = wst.commit()
		wmi.material_override = wmat
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wmi)
	root.add_child(_tower())
	return root


## 遠くの電波塔（細くなる柱・展望台・アンテナ・赤いランプ）。どこにでもある形（実在の塔の形ではない）
func _tower() -> Node3D:
	var t := Node3D.new()
	t.name = "Tower"
	var tp: Array = cfg.get("tower_pos", [-15.0, 0.0, -40.0])
	t.position = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
	var h := float(cfg.get("tower_height", 30.0))
	var col := Color(str(cfg.get("tower_color", "#2c2550")))
	var mat := _unshaded(col)
	var parts := [[2.0, 0.55, h * 0.62, h * 0.31], [0.55, 0.32, h * 0.25, h * 0.62 + h * 0.125], [0.12, 0.05, h * 0.16, h * 0.87 + h * 0.08]]
	for p in parts:
		var cm := CylinderMesh.new()
		cm.bottom_radius = p[0]
		cm.top_radius = p[1]
		cm.height = p[2]
		cm.radial_segments = 10
		cm.rings = 1
		cm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.position = Vector3(0, p[3], 0)
		t.add_child(mi)
	var deck := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.25
	dm.bottom_radius = 1.0
	dm.height = 1.0
	dm.radial_segments = 14
	dm.material = mat
	deck.mesh = dm
	deck.position = Vector3(0, h * 0.62, 0)
	t.add_child(deck)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.27
	bm.bottom_radius = 1.27
	bm.height = 0.18
	bm.radial_segments = 14
	bm.material = _unshaded(Color(str(cfg.get("tower_light", "#9ad0ff"))))
	band.mesh = bm
	band.position = Vector3(0, h * 0.62 + 0.15, 0)
	t.add_child(band)
	beacon_mat = _unshaded(Color("#ff3a3a"))
	beacon_mat.disable_fog = true
	var bs := SphereMesh.new()
	bs.radius = 0.22
	bs.height = 0.44
	bs.material = beacon_mat
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = bs
	beacon.position = Vector3(0, h * 1.03, 0)
	t.add_child(beacon)
	return t


## 広場：手すり・街灯（やわらかい光）・木
func _build_plaza() -> void:
	var plaza := Node3D.new()
	plaza.name = "Plaza"
	add_child(plaza)
	var rail_z := float(cfg.get("rail_z", -11.5))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#2a2a40")
	metal.metallic = 0.6
	metal.roughness = 0.4
	var rail := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(44, 0.08, 0.08)
	rb.material = metal
	rail.mesh = rb
	rail.position = Vector3(0, 1.0, rail_z)
	plaza.add_child(rail)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.08, 1.0, 0.08)
	post_mesh.material = metal
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh
	mm.instance_count = 23
	for i in 23:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-22.0 + 2.0 * i, 0.5, rail_z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	plaza.add_child(mmi)
	var lamp_col := Color(str(cfg.get("lamp_color", "#ffd38a")))
	for x in cfg.get("lamp_x", [-8.0, -4.6, 4.6, 8.0]):
		var lx := float(x)
		var pole := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.06
		pc.bottom_radius = 0.09
		pc.height = 4.2
		pc.radial_segments = 8
		pc.material = metal
		pole.mesh = pc
		pole.position = Vector3(lx, 2.1, rail_z + 0.6)
		plaza.add_child(pole)
		var head := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.24
		hs.height = 0.48
		var hm := _unshaded(lamp_col)
		hm.disable_fog = true
		hs.material = hm
		head.mesh = hs
		head.position = Vector3(lx, 4.3, rail_z + 0.6)
		plaza.add_child(head)
		plaza.add_child(_glow_sprite(Color(lamp_col.r, lamp_col.g, lamp_col.b, 0.55), 2.6, Vector3(lx, 4.3, rail_z + 0.7)))
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(str(cfg.get("tree_color", "#2f4a4a")))
	leaf.roughness = 1.0
	for x in cfg.get("tree_x", [-11.0, 11.5]):
		var tx := float(x)
		var trunk := MeshInstance3D.new()
		var tcm := CylinderMesh.new()
		tcm.top_radius = 0.12
		tcm.bottom_radius = 0.18
		tcm.height = 1.6
		tcm.material = metal
		trunk.mesh = tcm
		trunk.position = Vector3(tx, 0.8, rail_z - 1.0)
		plaza.add_child(trunk)
		for k in 3:
			var crown := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.2 - 0.25 * k
			sm.height = (1.2 - 0.25 * k) * 1.8
			sm.radial_segments = 12
			sm.rings = 6
			sm.material = leaf
			crown.mesh = sm
			crown.position = Vector3(tx + 0.2 * k, 2.2 + 0.9 * k, rail_z - 1.0)
			plaza.add_child(crown)


## キャラのまわりを、ゆっくりのぼる光の粒
func _build_motes() -> void:
	motes = CPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = int(cfg.get("motes", 40))
	motes.lifetime = 6.0
	motes.preprocess = 6.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(6.0, 2.2, 4.0)
	motes.position = Vector3(0, 2.4, -2.5)
	motes.direction = Vector3.UP
	motes.spread = 30.0
	motes.initial_velocity_min = 0.08
	motes.initial_velocity_max = 0.25
	motes.gravity = Vector3(0, 0.05, 0)
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.85, 0.55, 0.0))
	ramp.add_point(0.25, Color(1, 0.85, 0.55, 0.9))
	ramp.add_point(0.75, Color(0.75, 0.85, 1.0, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.75, 0.85, 1.0, 0.0))
	motes.color_ramp = ramp
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.14)
	var m := _unshaded(Color.WHITE, true)
	m.albedo_texture = UiKit.soft_dot(32)
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_fog = true
	qm.material = m
	motes.mesh = qm
	add_child(motes)


## 画質：低いときは光の粒を減らす
func set_quality(name_text: String) -> void:
	quality = name_text
	if motes != null:
		motes.amount = int(cfg.get("motes", 40)) if name_text == "high" else int(cfg.get("motes_low", 20))


## 画面が縦長か横長かで、カメラの広さと向きを変える（縦でも4人が入るように）
func fit_camera(screen: Vector2) -> void:
	if camera == null:
		return
	var portrait := screen.y > screen.x
	camera.fov = float(cfg["fov_portrait"]) if portrait else float(cfg["fov_landscape"])
	cam_look = _v3("camera_look") if portrait or not cfg.has("camera_look_landscape") else _v3("camera_look_landscape")
	_aim_camera()


func _aim_camera() -> void:
	var sway := float(cfg.get("sway_m", 0.12))
	var off := Vector3(sin(clock * 0.27) * sway - drag_now * float(cfg.get("drag_shift_m", 0.9)), sin(clock * 0.21) * sway * 0.5, 0)
	var pos := cam_base + off
	if camera.is_inside_tree():
		camera.look_at_from_position(pos, cam_look, Vector3.UP)
	else:
		camera.position = pos
		camera.basis = Basis.looking_at(cam_look - pos, Vector3.UP)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col_bottom: Color, col_top: Color) -> void:
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
		for k in [0, 1, 2, 0, 2, 3]:
			var vv: Vector3 = f[k]
			st.set_color(col_top if vv.y > 0.0 else col_bottom)
			st.add_vertex(q[k])


## 編成（4人のキャラID。0 がメイン）を並べる。同じキャラは、形を作り直さずに新しい場所へ動かす。
## まんなかに新しく来た人は、着いたら A攻撃を1回（はじめて並べる時はしない）。後ろの人は静止（版94）
func set_team(ids: Array) -> void:
	var first := units.is_empty()
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
			u["cheer"] = i == 0 and int(u["slot"]) != 0
			if i != 0 and u.get("view") != null:
				set_still(u["view"])  # 版94：後ろへ行ったら、すぐ静止
		else:
			u = _make_unit(id, i)
			u["cheer"] = i == 0 and not first
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
	# 足もとの、やわらかい影
	var blob := MeshInstance3D.new()
	blob.name = "Blob"
	var bq := QuadMesh.new()
	bq.size = Vector2(2.0, 2.0)
	bq.orientation = PlaneMesh.FACE_Y
	var bm := _unshaded(Color(0.02, 0.0, 0.06, float(cfg.get("blob_alpha", 0.55))), true)
	bm.albedo_texture = UiKit.soft_dot(64)
	bq.material = bm
	blob.mesh = bq
	blob.position = Vector3(0, 0.02, 0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(blob)
	var view: Node3D = null
	var def := CharacterData.find(characters_cfg, id)
	if not def.is_empty() and CharacterData.has_model(def):
		var v := CharacterView.new()
		if v.setup(def):
			holder.add_child(v)
			# 版94：はじめは静止。A攻撃が終わったら静止にもどす合図を、作った時に1回だけつなぐ
			if v.player != null:
				v.player.animation_finished.connect(_on_anim_finished.bind(v))
			set_still(v)
			view = v
			built_count += 1
		else:
			v.free()
	return {"id": id, "holder": holder, "view": view, "slot": slot, "from": holder.position, "from_scale": 0.01, "t": 0.0, "cheer": false}


func _process(delta: float) -> void:
	step(delta)


## 動きを1コマ進める：新しい場所へ、なめらかに（少し回りながら）動く。カメラ・雲・輪・ランプも
func step(delta: float) -> void:
	clock += minf(delta, 0.1)
	var dur := maxf(float(cfg.get("move_sec", 0.35)), 0.01)
	var top := float(cfg.get("platform_height", 0.22))
	for u in units:
		var holder: Node3D = u["holder"]
		if not is_instance_valid(holder):
			continue
		var slot := int(u["slot"])
		var was := float(u["t"])
		u["t"] = minf(1.0, was + delta / dur)
		var k := smoothstep(0.0, 1.0, float(u["t"]))
		var goal := _slot_pos(slot) + (Vector3(0, top, 0) if slot == 0 else Vector3.ZERO)
		var goal_s := float((cfg["slot_scale"] as Array)[slot])
		var hop := sin(PI * k) * 0.35 if float(u["t"]) < 1.0 else 0.0
		holder.position = (u["from"] as Vector3).lerp(goal, k) + Vector3(0, hop, 0)
		holder.scale = Vector3.ONE * lerpf(float(u["from_scale"]), goal_s, k)
		var turn := deg_to_rad(float((cfg["slot_turn_deg"] as Array)[slot]))
		holder.rotation.y = turn + deg_to_rad(float(cfg.get("spin_deg", 0.0))) * sin(PI * k) * (1.0 if float(u["t"]) < 1.0 else 0.0)
		# 着いた：まんなか（前）に持ってこられた人だけ、A攻撃を1回（終わったら静止。_on_anim_finished）
		var view: Node3D = u.get("view")
		if was < 1.0 and float(u["t"]) >= 1.0 and bool(u.get("cheer", false)) and view != null:
			u["cheer"] = false
			play_attack(view, str(u["id"]))
	# カメラ（ゆっくりゆれる・スライド中は横へ）
	drag_now = lerpf(drag_now, drag, clampf(delta * 8.0, 0.0, 1.0))
	if camera != null:
		_aim_camera()
	# 台の金の輪が、ゆっくり脈打つ・塔のランプが点めつ・雲が流れる
	if ring_mat != null:
		var base := Color(str(cfg["stage_disc_color"]))
		ring_mat.albedo_color = base.lerp(Color.WHITE, 0.25 + 0.25 * sin(clock * 2.2))
	if beacon_mat != null:
		beacon_mat.albedo_color = Color("#ff3a3a") if fmod(clock, 1.6) < 0.5 else Color("#5a1010")
	for c in clouds:
		var n: Node3D = c["node"]
		n.position.x += float(c["speed"]) * delta
		if n.position.x > 36.0:
			n.position.x = -36.0


## 版93：キャラ id の A攻撃の動き（戦いと同じ anim と speed）。なければ {}
func attack_for(id: String) -> Dictionary:
	if attack_cache.has(id):
		return attack_cache[id]
	var out := {}
	var acts: Dictionary = Actions.config_for(id).get("actions", {})
	var steps: Array = (acts.get(ATTACK_ACTION, {}) as Dictionary).get("steps", [])
	if not steps.is_empty() and str((steps[0] as Dictionary).get("anim", "")) != "":
		out = {"anim": str(steps[0]["anim"]), "speed": float(steps[0].get("speed", 1.0))}
	attack_cache[id] = out
	return out


## 版93・94：A攻撃の動きを最初から1回流す（動きだけ。戦いの処理は呼ばない）。キャラにその動きがなければ、静止のまま
func play_attack(view: Node, id: String) -> bool:
	var a := attack_for(id)
	var def: Dictionary = view.get("character")
	var anim := CharacterData.animation_for(def, str(a.get("anim", ""))) if not a.is_empty() else ""
	var p: AnimationPlayer = view.get("player")
	if anim == "" or p == null or not p.has_animation(anim):
		if not unsupported.has(id):
			unsupported.append(id)
		set_still(view)
		return false
	return view.play_step(str(a["anim"]), float(a["speed"]))


## 版94：静止：待ちの動きの最初の形で止める（再生係を止めるので、動かない・軽い）
func set_still(view: Node) -> void:
	if not is_instance_valid(view):
		return
	view.play_action("idle")
	var p: AnimationPlayer = view.get("player")
	if p == null:
		return
	if p.current_animation != "":
		p.seek(0.0, true)
	p.pause()


## 版94：動きが終わった。A攻撃（1回）が終わったら、静止にもどる（くり返さない）
func _on_anim_finished(_name: StringName, view: Node) -> void:
	if not is_instance_valid(view) or str(view.get("current_action")) != "step":
		return
	set_still(view)


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

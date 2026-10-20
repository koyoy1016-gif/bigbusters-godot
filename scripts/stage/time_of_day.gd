extends RefCounted
## 版90：戦いのマップの時間帯。ふだんは夕方、ボスの覚醒（第2形態）の間は夜。
## data/maps.json の time_of_day.evening と .night の数値の間を、t（0 夕方〜1 夜）でなめらかに混ぜる。
## 変えるもの：空（city_sky.gdshader）・まわりの明るさ・霧・太陽（月）の色と強さ・建物の窓と1階の店・看板・大画面・街灯・横断歩道の白線の見えやすさ。
## 変えないもの：建物・道路・白線の形と場所、光の向き（影が動かないように）、カメラ。

const SKY_SHADER := preload("res://shaders/city_sky.gdshader")

var cfg: Dictionary = {}
var t := 0.0  ## いまの夜の割合（0 夕方〜1 夜）
var target := 0.0  ## めざす割合
var env: Environment
var light: DirectionalLight3D
var sky_mat: ShaderMaterial
var night_mats: Array = []  ## night（0〜1）を持つシェーダーの材質（建物・看板・大画面・街灯・光の輪）
var glass_mat: ShaderMaterial  ## 建物（ガラスにうつす空の色）
var cross_mat: StandardMaterial3D  ## 横断歩道（夜は少し光らせて、白線を見えやすく）
var pools: Array = []  ## 版98：街灯の光の輪。夜の割合が pool_show_from より小さい間（夕方）は隠す（見えないのに透明の重ね描きをしないため）
var applied := -1.0


## env・light・マップ（map_loader.build の結果）をつなぐ。夕方から始める
func setup(map_cfg: Dictionary, environment: Environment, sun: DirectionalLight3D, map_root: Node) -> void:
	cfg = map_cfg.get("time_of_day", {})
	env = environment
	light = sun
	if env != null and not cfg.is_empty():
		sky_mat = ShaderMaterial.new()
		sky_mat.shader = SKY_SHADER
		var sky := Sky.new()
		sky.sky_material = sky_mat
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED  # 空の反射は使わない（夜へ変える間、毎フレーム作りなおさないように）
		env.fog_enabled = true
	if light != null and cfg.has("light_rotation_deg"):
		var r: Array = cfg["light_rotation_deg"]
		light.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	if map_root != null:
		night_mats = map_root.get_meta("night_materials", [])
		glass_mat = map_root.get_meta("building_material", null)
		cross_mat = map_root.get_meta("crosswalk_material", null)
		pools = map_root.get_meta("light_pools", [])
	snap(false)


func is_ready() -> bool:
	return not cfg.is_empty()


## 夜にする・夕方にもどす（なめらかに。step で進む）
func set_night(on: bool) -> void:
	target = 1.0 if on else 0.0


## すぐに切りかえる（戦いの始まりなど）
func snap(on: bool) -> void:
	target = 1.0 if on else 0.0
	t = target
	apply()


## 時間を進める。変わったら true
func step(delta: float) -> bool:
	if is_equal_approx(t, target):
		if not is_equal_approx(applied, t):
			apply()
			return true
		return false
	var sec := float(cfg.get("to_night_sec", 1.6)) if target > t else float(cfg.get("to_evening_sec", 3.0))
	t = move_toward(t, target, delta / maxf(sec, 0.01))
	apply()
	return true


## 混ぜる割合（ゆっくり始まり、ゆっくり終わる：急に変わって見えないように）
func mix_k() -> float:
	return t * t * (3.0 - 2.0 * t)


## 夕方と夜の値を混ぜる（色は Color、数は float）
func value(key: String) -> Variant:
	var ev: Dictionary = cfg.get("evening", {})
	var ni: Dictionary = cfg.get("night", {})
	var a: Variant = ev.get(key, ni.get(key, 0.0))
	var b: Variant = ni.get(key, a)
	var k := mix_k()
	if a is String:
		return Color(str(a)).lerp(Color(str(b)), k)
	return lerpf(float(a), float(b), k)


func apply() -> void:
	applied = t
	if cfg.is_empty():
		return
	var k := mix_k()
	if sky_mat != null:
		sky_mat.set_shader_parameter("top_color", value("sky_top"))
		sky_mat.set_shader_parameter("mid_color", value("sky_mid"))
		sky_mat.set_shader_parameter("horizon_color", value("sky_horizon"))
		sky_mat.set_shader_parameter("ground_color", value("sky_ground"))
		sky_mat.set_shader_parameter("sun_color", value("sun_color"))
		sky_mat.set_shader_parameter("sun_glow", value("sun_glow"))
		sky_mat.set_shader_parameter("cloud_color", value("cloud_color"))
		sky_mat.set_shader_parameter("cloud_lit", value("cloud_lit"))
		sky_mat.set_shader_parameter("cloud_amount", value("cloud_amount"))
		sky_mat.set_shader_parameter("energy", value("sky_energy"))
		if light != null and light.is_inside_tree():
			sky_mat.set_shader_parameter("sun_dir", light.global_transform.basis.z.normalized())
		elif light != null:
			sky_mat.set_shader_parameter("sun_dir", Basis.from_euler(light.rotation).z.normalized())
	if env != null:
		env.ambient_light_color = value("ambient_color")
		env.ambient_light_energy = value("ambient_energy")
		env.fog_light_color = value("fog_color")
		env.fog_density = value("fog_density")
		env.fog_sky_affect = value("fog_sky_affect")
	if light != null:
		light.light_color = value("light_color")
		light.light_energy = value("light_energy")
	for m in night_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("night", k)
	var show_from := float(cfg.get("pool_show_from", 0.02))
	for pm in pools:
		if is_instance_valid(pm):
			(pm as Node3D).visible = k >= show_from
	if glass_mat != null:
		glass_mat.set_shader_parameter("sky_top", value("sky_top"))
		glass_mat.set_shader_parameter("sky_horizon", value("sky_horizon"))
	if cross_mat != null:
		# emission_enabled は map_loader が最初から true にしている（ここで切りかえると、シェーダーを作りなおして一瞬止まるため）
		cross_mat.emission_energy_multiplier = float(value("crosswalk_glow"))

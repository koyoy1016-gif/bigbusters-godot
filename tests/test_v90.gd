extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v90.gd
## 版90：ふだんは夕方、ボスの覚醒（第2形態）の間は夜。なめらかに切りかえる。
## 確かめること：
##   1. 設定：夕方の空はオレンジ（地平線）・赤むらさき（中）・暗めの青（上）。夜の空は紺・青むらさきで、夕方より暗いが真っ黒ではない
##   2. 戦いの始まりは夕方：空は自作の空のシェーダー・光・まわりの明るさ・霧が夕方の値
##   3. 覚醒すると夜へ：急に変わらず（1フレームの変化が小さい）、to_night_sec で夜になりきる。窓・看板・大画面・街灯・光の輪の night が 1
##   4. 夜も見える：横断歩道の白線が少し光る・まわりの明るさは 0.4 以上・街灯がある（戦いの場所の外）
##   5. 変わらないもの：マップの形（同じ部品）・光の向き（影が動かない）・カメラ
##   6. 覚醒が終わる（倒した）と夕方へもどる（to_evening_sec）。次の戦いは夕方から
##   7. 画面の流れ：曲の合図 awake と同じ時に夜へ向かい始める

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const MapLoader := preload("res://scripts/stage/map_loader.gd")
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _initialize() -> void:
	# ---- 1. 設定 ----
	var mc := MapLoader.current_map()
	var td: Dictionary = mc.get("time_of_day", {})
	var ev: Dictionary = td.get("evening", {})
	var ni: Dictionary = td.get("night", {})
	check(not ev.is_empty() and not ni.is_empty(), "時間帯の数値は data/maps.json の time_of_day（evening・night）")
	var eh := Color(str(ev["sky_horizon"]))
	var em := Color(str(ev["sky_mid"]))
	var et := Color(str(ev["sky_top"]))
	check(eh.r > eh.g and eh.g > eh.b, "夕方の地平線はオレンジ %s" % str(ev["sky_horizon"]))
	check(em.r > em.g and em.b > em.g, "夕方の空の中ほどは赤むらさき %s" % str(ev["sky_mid"]))
	check(et.b > et.r and lum(et) < 0.3, "夕方の空の上は暗めの青 %s" % str(ev["sky_top"]))
	var dark_ok := true
	for k in ["sky_top", "sky_mid", "sky_horizon"]:
		var cn := Color(str(ni[k]))
		var ce := Color(str(ev[k]))
		dark_ok = dark_ok and lum(cn) < lum(ce) and cn.b >= cn.r and maxf(cn.r, maxf(cn.g, cn.b)) >= 0.12
	check(dark_ok, "夜の空は夕方より暗く、紺・青むらさきで、真っ黒ではない（どの色も明るさが少し残る）")
	check(float(ni["ambient_energy"]) >= 0.4 and float(ni["light_energy"]) > 0.0, "夜も、まわりの明るさ（%.2f）と月の光が残る" % float(ni["ambient_energy"]))
	check(float(td["to_night_sec"]) >= 0.8 and float(td["to_night_sec"]) <= 2.5, "夜へは %.1f 秒（すぐ分かるが、急ではない）" % float(td["to_night_sec"]))

	# ---- 2. 始まりは夕方 ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.set_process(false)
	var env: Environment = s.camera.environment
	check(s.tod.is_ready() and is_zero_approx(s.tod.t), "戦いの始まりは夕方（t = %.2f）" % s.tod.t)
	check(env.background_mode == Environment.BG_SKY and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader.resource_path.ends_with("city_sky.gdshader"), "空は自作の空のシェーダー（3色のグラデーション・夕日のまわりの光・雲）")
	check(env.ambient_light_color.is_equal_approx(Color(str(ev["ambient_color"]))) and s.sun.light_color.is_equal_approx(Color(str(ev["light_color"]))), "まわりの明るさ・太陽の色は夕方の値")
	check(env.fog_enabled and is_equal_approx(env.fog_density, float(ev["fog_density"])), "霧は夕方の値")
	var mats: Array = s.map_root.get_meta("night_materials", [])
	check(mats.size() == 5, "night を持つ材質：建物・看板・大画面・街灯・光の輪（%d）" % mats.size())
	var all0 := true
	for m in mats:
		all0 = all0 and is_zero_approx(float((m as ShaderMaterial).get_shader_parameter("night")))
	check(all0, "夕方：窓・看板・街灯の night は 0")
	var rot0: Vector3 = s.sun.rotation
	var cam0: Transform3D = s.camera.global_transform
	var parts0 := {}
	for mi in s.map_root.find_children("*", "MeshInstance3D", true, false):
		parts0[str(mi.get_meta("map_part", ""))] = (mi as MeshInstance3D).mesh

	# ---- 3. 覚醒すると夜へ ----
	s.phase.phase = BossPhase.AWAKE
	check(s.night_wanted(), "ボスが覚醒（第2形態）すると、夜にしたい（night_wanted）")
	var dt := 1.0 / 60.0
	var max_step := 0.0
	var prev: float = s.tod.t
	var prev_amb := lum(env.ambient_light_color) * env.ambient_light_energy
	var mono := true
	var elapsed := 0.0
	var half_t := -1.0
	while elapsed < float(td["to_night_sec"]) + 0.2:
		s._time_of_day_update(dt)
		elapsed += dt
		max_step = maxf(max_step, absf(s.tod.mix_k() - prev))
		prev = s.tod.mix_k()
		var a := lum(env.ambient_light_color) * env.ambient_light_energy
		if a > prev_amb + 1e-4:
			mono = false
		prev_amb = a
		if half_t < 0.0 and elapsed >= float(td["to_night_sec"]) * 0.5:
			half_t = s.tod.t
	check(half_t > 0.3 and half_t < 0.7, "途中（%.1f 秒）では、夕方と夜の間（t = %.2f）" % [float(td["to_night_sec"]) * 0.5, half_t])
	check(max_step < 0.03, "1フレーム（1/60秒）で変わる量は小さい（いちばん大きくて %.3f）＝ちらつかない" % max_step)
	check(mono, "切りかえの間、まわりの明るさは行ったり来たりしない（だんだん暗くなる）")
	check(is_equal_approx(s.tod.t, 1.0), "%.1f 秒で夜になりきる" % float(td["to_night_sec"]))
	var all1 := true
	for m in mats:
		all1 = all1 and is_equal_approx(float((m as ShaderMaterial).get_shader_parameter("night")), 1.0)
	check(all1, "夜：窓・看板・大画面・街灯・光の輪の night は 1（明かりが目立つ）")
	var sky_mat := env.sky.sky_material as ShaderMaterial
	check((sky_mat.get_shader_parameter("top_color") as Color).is_equal_approx(Color(str(ni["sky_top"]))) and env.ambient_light_color.is_equal_approx(Color(str(ni["ambient_color"]))), "夜：空・まわりの明るさは夜の値")
	var w: Dictionary = mc["windows"]
	check(float(w["lit_night"]) > float(w["lit"]) and float(w["glow_night"]) > float(w["glow"]) and float(mc["signs"]["glow_night"]) > float(mc["signs"]["glow"]) and float(mc["lamps"]["glow_night"]) > float(mc["lamps"]["glow"]), "夜は、明かりのつく窓が多く、看板・街灯が強く光る")

	# ---- 4. 夜も見える ----
	var cross: StandardMaterial3D = s.map_root.get_meta("crosswalk_material")
	check(cross.emission_enabled and cross.emission_energy_multiplier > 0.05, "夜：横断歩道の白線が少し光る（暗やみにうもれない。%.2f）" % cross.emission_energy_multiplier)
	var parts := {}
	for mi in s.map_root.find_children("*", "MeshInstance3D", true, false):
		parts[str(mi.get_meta("map_part", ""))] = mi
	check(parts.has("Lamps") and parts.has("LightPools"), "街灯と、地面の光の輪がある")
	var pv: PackedVector3Array = (parts["LightPools"] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n_l := pv.size() / 4
	var half := float(s.config["bounds"])
	var lv: PackedVector3Array = (parts["Lamps"] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lamp_in := 0
	for v in lv:
		if absf(v.x) < half and absf(v.z) < half:
			lamp_in += 1
	check(n_l >= 8 and lamp_in == 0, "街灯は %d 本・戦いの場所の中には立てない" % n_l)

	# ---- 5. 変わらないもの ----
	var same := true
	for k in parts0:
		same = same and parts.has(k) and (parts[k] as MeshInstance3D).mesh == parts0[k]
	check(same and parts.size() == parts0.size(), "夕方と夜で、マップの形（部品）は同じ（別の街に入れかえない）")
	check(s.sun.rotation.is_equal_approx(rot0), "光の向きは変えない（影が動かない）")
	check(s.camera.global_transform.is_equal_approx(cam0), "時間帯でカメラは動かない")

	# ---- 6. 覚醒が終わると夕方へ ----
	s.phase.phase = BossPhase.DEAD
	s.won = true
	check(not s.night_wanted(), "倒した（覚醒が終わった）ら、夕方にもどしたい")
	elapsed = 0.0
	while elapsed < float(td["to_evening_sec"]) * 0.5:
		s._time_of_day_update(dt)
		elapsed += dt
	check(s.tod.t > 0.2 and s.tod.t < 0.8, "もどる途中（t = %.2f。ゆっくり）" % s.tod.t)
	while elapsed < float(td["to_evening_sec"]) + 0.2:
		s._time_of_day_update(dt)
		elapsed += dt
	check(is_zero_approx(s.tod.t) and env.ambient_light_color.is_equal_approx(Color(str(ev["ambient_color"]))), "%.1f 秒で夕方にもどる" % float(td["to_evening_sec"]))
	s.phase.phase = BossPhase.AWAKE
	s.won = false
	for i in 200:
		s._time_of_day_update(dt)
	s.lost = true
	s._begin_round(now[0])
	check(is_zero_approx(s.tod.t), "次の戦いは、夕方から（夜のまま始まらない）")

	# ---- 7. 曲の合図と同じ時 ----
	var src := FileAccess.get_file_as_string("res://scripts/prototype/stick_prototype.gd")
	check(src.contains("music_cue.emit(\"awake\")") and src.contains("phase.is_awake() and not won and not lost"), "夜は、覚醒の曲の合図（awake）と同じ、ボスの第2形態に合わせる")
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

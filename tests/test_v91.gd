extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v91.gd
## 版91：戦いのカメラ（高さ・角度・画角）を自然に。背景が跳ねない。
## 確かめること：
##   1. 画角：たて画面でも「たて」で決める（たて 75° 以下）。画面のはしの引きのばし（ゆがみ）が、前（版90）より小さい
##   2. 角度：見下ろす角度は 18〜35°。画面の上は地平線より上まで見える（交差点の先の建物・看板・空）
##   3. 広さ：画面の形（iPhone 9:19.5・9:16・横 16:9）が変わっても、見る点で横 20m 以上見える。距離は決めた範囲
##   4. 戦いの場所が見える：まん中・奥の2つの角・ボスの最初の位置が、画面の中
##   5. 跳ねない：自分が急に遠くへ動いても（復活など）、カメラは1フレームで少しずつ（0.6m 以下）
##   6. ゆれ：強い攻撃のゆれは、なめらか（1フレームの変化が小さい）で、カメラの向きは変えない（遠くの背景ははねない）
##   7. 寄り：強い攻撃のカメラの寄りも、1フレームで跳ばない
##   8. 時間帯（夕方・夜）を変えても、カメラは同じ（版90 のテストでも確かめた）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const CameraRig := preload("res://scripts/prototype/camera_rig.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


## 点 p が、カメラ（位置・向き・たての画角・画面の形）の画面に入るか
func on_screen(cam: Transform3D, fov_v: float, aspect: float, p: Vector3) -> bool:
	var d := cam.basis.inverse() * (p - cam.origin)
	if d.z >= -0.01:
		return false
	var tv := tan(deg_to_rad(fov_v) * 0.5)
	var th := tv * aspect
	return absf(d.x / -d.z) <= th and absf(d.y / -d.z) <= tv


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var rig_cfg: Dictionary = cfg.get("camera_rig", {})
	check(rig_cfg.has("portrait") and rig_cfg.has("landscape"), "カメラの数値は data/prototype_stick.json の camera_rig")

	# ---- 1〜3. 画角・角度・広さ ----
	var screens := {"iPhone たて 9:19.5": Vector2(390, 844), "たて 9:16": Vector2(648, 1152), "横 16:9": Vector2(1152, 648), "iPhone 横": Vector2(844, 390)}
	for nm in screens:
		var sz: Vector2 = screens[nm]
		var r := CameraRig.rig_for(cfg, sz)
		var rc: Dictionary = rig_cfg["portrait" if sz.y > sz.x else "landscape"]
		var fov := float(r["fov"])
		var pitch := rad_to_deg(atan2(float(r["offset"].y), float(r["offset"].z)))
		var aspect := sz.x / sz.y
		var half_h := atan(tan(deg_to_rad(fov) * 0.5) * aspect)
		var width := 2.0 * float(r["dist"]) * tan(half_h)
		check(bool(r["keep_height"]) and fov <= 75.0, "%s：画角は たて %.0f°（75° 以下）" % [nm, fov])
		check(pitch >= 18.0 and pitch <= 35.0, "%s：見下ろす角度 %.0f°" % [nm, pitch])
		check(pitch < fov * 0.5, "%s：画面の上は、地平線より %.0f° 上まで見える（建物・看板・空）" % [nm, fov * 0.5 - pitch])
		check(width >= 20.0, "%s：見る点で、横に %.1f m 見える" % [nm, width])
		check(float(r["dist"]) >= float(rc["min_dist_m"]) - 0.001 and float(r["dist"]) <= float(rc["max_dist_m"]) + 0.001, "%s：カメラの距離 %.1f m（決めた範囲）" % [nm, float(r["dist"])])
	# 前（版90）：たて画面で横 78° → たての画角は 110° 近く。はしの引きのばし 1/cos² で比べる
	var old_v := 2.0 * atan(tan(deg_to_rad(78.0) * 0.5) * (1152.0 / 648.0))
	var new_v := deg_to_rad(float(rig_cfg["portrait"]["fov"]))
	var old_s := 1.0 / pow(cos(old_v * 0.5), 2.0)
	var new_s := 1.0 / pow(cos(new_v * 0.5), 2.0)
	check(new_s < old_s * 0.6, "画面の上下のはしの引きのばし：前 %.1f 倍 → %.1f 倍（白線の太さ・建物のかたむきが自然に）" % [old_s, new_s])

	# ---- 4. 戦いの場所が見える ----
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
	var size := Vector2(390, 844)
	s.apply_orientation(size)
	s.player.position = Vector3(0, s.ground_y, 0)
	s.camera_target = Vector3.ZERO
	for i in 120:
		s.camera_update(1.0 / 60.0)
	var cam: Transform3D = s.camera.global_transform
	var half := float(s.config["bounds"])
	var bp: Array = s.config["boss_position"]
	var aspect := size.x / size.y
	var fov := float(s.camera.fov)
	check(on_screen(cam, fov, aspect, Vector3.ZERO), "戦いの場所のまん中が見える")
	check(on_screen(cam, fov, aspect, Vector3(-half * 0.8, 0, -half)) and on_screen(cam, fov, aspect, Vector3(half * 0.8, 0, -half)), "戦いの場所の奥（-%.0f m）の左右が見える" % half)
	check(on_screen(cam, fov, aspect, Vector3(float(bp[0]), 2.0, float(bp[1]))), "ボスの最初の位置が見える")
	var fwd := -cam.basis.z
	var look_pitch := rad_to_deg(asin(-fwd.y))
	check(absf(look_pitch - float(rig_cfg["portrait"]["pitch_deg"])) < 0.5, "カメラの向き：%.1f° 見下ろす（設定どおり）" % look_pitch)

	# ---- 5. 跳ねない ----
	var max_move := 0.0
	var prev: Vector3 = s.camera.global_position
	s.player.position = Vector3(12, s.ground_y, -12)
	for i in 120:
		s.camera_update(1.0 / 60.0)
		max_move = maxf(max_move, s.camera.global_position.distance_to(prev))
		prev = s.camera.global_position
	check(max_move <= 0.6, "自分が急に遠くへ動いても、カメラは1フレームに %.2f m まで（なめらかについていく）" % max_move)

	# ---- 6. ゆれ ----
	for i in 120:
		s.camera_update(1.0 / 60.0)
	var basis0: Basis = s.camera.global_transform.basis
	prev = s.camera.global_position
	s._hitstop(0.0, 0.3)
	var max_step := 0.0
	var same_dir := true
	for i in 30:
		s.camera_update(1.0 / 60.0)
		max_step = maxf(max_step, s.camera.global_position.distance_to(prev))
		prev = s.camera.global_position
		same_dir = same_dir and s.camera.global_transform.basis.is_equal_approx(basis0)
	var dist_now: float = s.camera.global_position.distance_to(s.camera_target + Vector3(0, s.camera_look_h, 0))
	var ang := rad_to_deg(max_step / dist_now)
	check(ang <= 0.5, "強い攻撃のゆれは、なめらか（1フレームで見え方が %.2f° まで）" % ang)
	check(same_dir, "ゆれの間も、カメラの向きは変えない（遠くの背景がはねない）")
	var src := FileAccess.get_file_as_string("res://scripts/prototype/stick_prototype.gd")
	check(not src.contains("randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)"), "でたらめなゆれ（毎フレーム乱数）は使っていない")

	# ---- 7. 寄り ----
	for i in 60:
		s.camera_update(1.0 / 60.0)
	prev = s.camera.global_position
	s._impact([0.0, 0.0, 0.15])
	max_step = 0.0
	var max_zoom := 0.0
	for i in 90:
		s.camera_update(1.0 / 60.0)
		max_step = maxf(max_step, s.camera.global_position.distance_to(prev))
		prev = s.camera.global_position
		max_zoom = maxf(max_zoom, s.cam_zoom)
	check(max_zoom > 0.1, "強い攻撃で、カメラが少し寄る（%.2f）" % max_zoom)
	var rel := max_step / dist_now
	check(rel <= 0.02, "寄る時も、1フレームで跳ばない（1フレームに距離の %.1f%%）" % (rel * 100.0))
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

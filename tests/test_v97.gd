extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v97.gd
## 版97（軽量化 A-1）：マップの大きな形を、前・遠い前（_Far）・カメラの後ろ（_Back）に分けた。
## 確かめること：
##   1. 分け方の数値は data/maps.json（build.split）。分けた形は、元の部品と同じ材質
##   2. 分けても三角形はへらない（道路の三角形の合計＝分ける前の数。.glb の記録と同じ）
##   3. 後ろの形は、全部の点が back_z_m より後ろ。戦いのカメラ（たて・横、自分がはしにいる時も）の後ろにあり、描かれない
##   4. 遠い形（far_m より遠い）：画質「低」では隠す・「高」では出す
##   5. 戦いの場所（±15m）の床・横断歩道・建物の正面は、前の形に入っている（見た目は変わらない）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const MapLoader := preload("res://scripts/stage/map_loader.gd")
const CameraRig := preload("res://scripts/prototype/camera_rig.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func tri_count(m: MeshInstance3D) -> int:
	var n := 0
	for si in m.mesh.get_surface_count():
		n += (m.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


## .glb の中の記録（asset.extras）を読む
func glb_extras(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var jl := bytes.decode_u32(12)
	var js: Variant = JSON.parse_string(bytes.slice(20, 20 + jl).get_string_from_utf8())
	return ((js as Dictionary).get("asset", {}) as Dictionary).get("extras", {}) if js is Dictionary else {}


func _initialize() -> void:
	var mc := MapLoader.current_map()
	var sp: Dictionary = (mc.get("build", {}) as Dictionary).get("split", {})
	check(not sp.is_empty() and (sp["parts"] as Array).has("Ground"), "分け方の数値は data/maps.json の build.split")
	var back_z := float(sp["back_z_m"])
	var far_m := float(sp["far_m"])

	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.sfx = null
	s.start_round()
	s.set_process(false)
	var pieces := {}
	for mi in s.map_root.find_children("*", "MeshInstance3D", true, false):
		var base := str(mi.get_meta("map_part", ""))
		if not pieces.has(base):
			pieces[base] = []
		(pieces[base] as Array).append(mi)

	# ---- 1. 材質 ----
	var mat_ok := true
	for base in sp["parts"]:
		var arr: Array = pieces.get(base, [])
		var zones := {}
		for m in arr:
			zones[str(m.get_meta("map_zone", ""))] = true
			mat_ok = mat_ok and (m as MeshInstance3D).material_override == (arr[0] as MeshInstance3D).material_override and (m as MeshInstance3D).material_override != null
		mat_ok = mat_ok and zones.has("near")
	check(mat_ok, "分けた形（前・遠い前・後ろ）は、元の部品と同じ材質")

	# ---- 2. 三角形はへらない ----
	var ex := glb_extras(str(mc["glb"]))
	var ground_sum := 0
	for m in pieces["Ground"]:
		ground_sum += tri_count(m)
	check(ground_sum == int((ex.get("stats", {}) as Dictionary).get("road_tris", -1)), "道路の三角形は、分けても同じ数（%d）" % ground_sum)
	var counts := {}
	for base in sp["parts"]:
		var line := []
		for m in pieces[base]:
			line.append("%s %d" % [str(m.get_meta("map_zone", "")), tri_count(m)])
		counts[base] = line
	print("     ", counts)

	# ---- 3. 後ろの形は、カメラの後ろ ----
	var backs := []
	for base in pieces:
		for m in pieces[base]:
			if str(m.get_meta("map_zone", "")) == "back":
				backs.append(m)
	var min_z := INF
	for m in backs:
		var ab: AABB = (m as MeshInstance3D).get_aabb()
		min_z = minf(min_z, ab.position.z)
	check(backs.size() >= 4 and min_z > back_z, "後ろの形（%d こ）は、全部の点が z > %.0f m（いちばん手前 %.1f m）" % [backs.size(), back_z, min_z])
	var half := float(s.config["bounds"])
	var follow := float(s.config["camera_follow"])
	var max_cam_z := -INF
	for sz in [Vector2(390, 844), Vector2(648, 1152), Vector2(1152, 648), Vector2(844, 390)]:
		var r := CameraRig.rig_for(s.config, sz)
		var cz: float = half * follow + float((r["offset"] as Vector3).z) * 1.05  # 自分が手前のはし・少しゆれても
		max_cam_z = maxf(max_cam_z, cz)
	check(max_cam_z < back_z, "戦いのカメラは、いちばん手前でも z = %.1f m（後ろの形は %.0f m より後ろなので、いつも描かれない）" % [max_cam_z, back_z])
	# 本当のカメラで：後ろの形の箱の角は、すべてカメラの後ろ
	s.apply_orientation(Vector2(390, 844))  # いちばんカメラが遠い（手前に来る）画面の形
	s.player.position = Vector3(half, s.ground_y, half)
	for i in 120:
		s.camera_update(1.0 / 60.0)
	# 箱の8つの角がすべて、カメラの面より後ろ（見える範囲の箱の判定でも、かならず描かれない）
	var cam: Transform3D = s.camera.global_transform
	var culled := true
	for m in backs:
		var ab: AABB = (m as MeshInstance3D).get_aabb()
		for k in 8:
			culled = culled and (cam.affine_inverse() * ab.get_endpoint(k)).z > 0.0
	check(culled, "自分が手前のはしにいる時（カメラ z = %.1f m）でも、後ろの形の箱は、すべてカメラの後ろ（描かれない）" % cam.origin.z)

	# ---- 4. 遠い形 ----
	var fars := []
	for base in pieces:
		for m in pieces[base]:
			if str(m.get_meta("map_zone", "")) == "far":
				fars.append(m)
	s.set_map_quality("low")
	var hid := not fars.is_empty()
	for m in fars:
		hid = hid and not (m as MeshInstance3D).visible
	check(hid, "画質「低」：%.0f m より遠い形（%d こ）は出さない" % [far_m, fars.size()])
	s.set_map_quality("high")
	var shown := true
	for m in fars:
		shown = shown and (m as MeshInstance3D).visible
	check(shown, "画質「高」：遠い形も出す")
	var vis: Dictionary = mc["visible_m"]
	check(float(vis["low"]) <= far_m + 0.5 and float(vis["high"]) > far_m, "見える距離の設定（低 %.0f m・高 %.0f m）と、分ける距離 %.0f m が合っている" % [float(vis["low"]), float(vis["high"]), far_m])

	# ---- 5. 戦いの場所は前の形 ----
	var near_ground: MeshInstance3D = null
	for m in pieces["Ground"]:
		if str(m.get_meta("map_zone", "")) == "near":
			near_ground = m
	var ab2: AABB = near_ground.get_aabb()
	check(ab2.has_point(Vector3(0, ab2.get_center().y, 0)) and ab2.position.x < -half and ab2.end.x > half and ab2.position.z < -half and ab2.end.z > half, "戦いの場所の床は、前の道路の形に入っている")
	var cw: MeshInstance3D = pieces["Crosswalk"][0]
	check((pieces["Crosswalk"] as Array).size() == 1 and cw.visible, "横断歩道は分けない（小さいので1つのまま）")
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

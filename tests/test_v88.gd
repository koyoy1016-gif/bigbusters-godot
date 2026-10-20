extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v88.gd
## 版88：戦いのマップを、渋谷のスクランブル交差点（PLATEAU の本物の形）に入れかえた。
## 確かめること：
##   1. 設定：いまのマップは渋谷・.glb がある・出典（PLATEAU・加工して作成）が設定と LICENSES.md にある・ステージの名前は「しぶや」（きたせんじゅ は残っていない）
##   2. 古いマップがない：緑の板（Ground）は作られず、マップは1つだけ。マップの部品（地形・道路・横断歩道・近い建物・遠い建物）がそろっている
##   3. 交差点のまん中＝今のマップのまん中：戦いの場所（±15m）の床は平ら（高さ 0）。中に建物はない。横断歩道がある
##   4. 本物の位置：渋谷スクランブルスクエア（いちばん高いビル）が、緯度・経度から計算した場所に、本物の高さである
##   5. 背景：まわりのどの方向にも建物がある（遠くまで）
##   6. 動ける範囲：外へ動かしても、±15m の中で止まる（自分・AIの味方）。足が床に合う（埋まらない・浮かない）
##   7. 画質：低では遠くの建物を早めに消す・高では近い建物の影。空と霧
##   8. 重さ：三角形の数・ファイルの大きさが目安の中

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const MapLoader := preload("res://scripts/stage/map_loader.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func verts_of(m: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if m == null or m.mesh == null:
		return out
	for si in m.mesh.get_surface_count():
		out.append_array(m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	return out


func tri_count(m: MeshInstance3D) -> int:
	var n := 0
	for si in m.mesh.get_surface_count():
		var a: Array = m.mesh.surface_get_arrays(si)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		n += idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## 床（道路の面）の三角形のうち、まん中の近くのもの [[a, b, c], …]
func near_tris(m: MeshInstance3D, half: float) -> Array:
	var out: Array = []
	for si in m.mesh.get_surface_count():
		var a: Array = m.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			var p0 := v[idx[i]]
			var p1 := v[idx[i + 1]]
			var p2 := v[idx[i + 2]]
			if minf(p0.x, minf(p1.x, p2.x)) > half or maxf(p0.x, maxf(p1.x, p2.x)) < -half or minf(p0.z, minf(p1.z, p2.z)) > half or maxf(p0.z, maxf(p1.z, p2.z)) < -half:
				continue
			out.append([p0, p1, p2])
	return out


## (x, z) の床の高さ（いちばん上の面）。床がなければ NAN
func floor_at(tris: Array, x: float, z: float) -> float:
	var best := NAN
	var p := Vector2(x, z)
	for t in tris:
		var a := Vector2(t[0].x, t[0].z)
		var b := Vector2(t[1].x, t[1].z)
		var c := Vector2(t[2].x, t[2].z)
		var v0 := c - a
		var v1 := b - a
		var v2 := p - a
		var den := v0.dot(v0) * v1.dot(v1) - v0.dot(v1) * v0.dot(v1)
		if absf(den) < 1e-9:
			continue
		var u := (v1.dot(v1) * v2.dot(v0) - v0.dot(v1) * v2.dot(v1)) / den
		var w := (v0.dot(v0) * v2.dot(v1) - v0.dot(v1) * v2.dot(v0)) / den
		if u >= -1e-5 and w >= -1e-5 and u + w <= 1.00001:
			var y: float = t[0].y + u * (t[2].y - t[0].y) + w * (t[1].y - t[0].y)
			best = y if is_nan(best) else maxf(best, y)
	return best


## 緯度・経度 → ゲームの座標（tools/plateau_to_glb.py の Frame と同じ計算）
func to_game(lat: float, lon: float, b: Dictionary) -> Vector2:
	var lat0 := float(b["center_lat"])
	var lon0 := float(b["center_lon"])
	var phi := deg_to_rad(lat0)
	var mlat := 111132.92 - 559.82 * cos(2.0 * phi) + 1.175 * cos(4.0 * phi)
	var mlon := 111412.84 * cos(phi) - 93.5 * cos(3.0 * phi) + 0.118 * cos(5.0 * phi)
	var e := (lon - lon0) * mlon
	var s := -(lat - lat0) * mlat
	var th := deg_to_rad(float(b["heading_deg"]))
	return Vector2(e * cos(th) + s * sin(th), -e * sin(th) + s * cos(th))


func _initialize() -> void:
	# ---- 1. 設定 ----
	var mc := MapLoader.current_map()
	check(str(MapLoader.load_config().get("current", "")) == "shibuya" and str(mc.get("name", "")) == "しぶや", "いまのマップは しぶや（data/maps.json）")
	check(ResourceLoader.exists(str(mc.get("glb", ""))), "渋谷の 3D（.glb）がある")
	var attr := str(mc.get("attribution", ""))
	check(attr.contains("PLATEAU") and attr.contains("渋谷区") and attr.contains("加工して作成"), "出典：" + attr)
	check(FileAccess.get_file_as_string("res://assets/LICENSES.md").contains(attr), "出典は assets/LICENSES.md にも書いてある")
	var gf := FileAccess.get_file_as_string("res://data/game_flow.json")
	check(gf.contains("\"name\": \"しぶや\"") and not gf.contains("きたせんじゅ") and not gf.contains("kitasenju"), "ステージの名前は しぶや（きたせんじゅ は残っていない）")

	# ---- 2. 古いマップがない ----
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
	s.skill_time_stop_left = 999.0
	check(s.get_node_or_null("Ground") == null, "前の緑の板（Ground）は作らない")
	var maps := s.find_children("Map", "Node3D", false, false)
	check(maps.size() == 1 and s.map_root == maps[0], "マップは1つだけ")
	var parts := {}
	for mi in s.map_root.find_children("*", "MeshInstance3D", true, false):
		parts[str(mi.get_meta("map_part", ""))] = mi
	check(parts.has("Terrain") and parts.has("Ground") and parts.has("Crosswalk") and parts.has("BldgNear") and parts.has("BldgFar"), "マップの部品：地形・道路・横断歩道・近い建物・遠い建物 %s" % str(parts.keys()))

	# ---- 3. 交差点のまん中 ----
	var half := float(s.config["bounds"])
	var ftris := near_tris(parts["Ground"], half + 1.0)
	var max_dy := 0.0
	var holes := 0
	var samples := 0
	var x := -half
	while x <= half + 0.001:
		var z := -half
		while z <= half + 0.001:
			var y := floor_at(ftris, x, z)
			samples += 1
			if is_nan(y):
				holes += 1
			else:
				max_dy = maxf(max_dy, absf(y))
			z += 1.0
		x += 1.0
	check(holes == 0 and max_dy <= 0.06, "戦いの場所の床は平らで、すきまがない（%d 点を調べた・高さのずれ %.3f m・すきま %d）" % [samples, max_dy, holes])
	var in_b := 0
	var bv := verts_of(parts["BldgNear"])
	for v in bv:
		if absf(v.x) <= half + 2.0 and absf(v.z) <= half + 2.0:
			in_b += 1
	check(in_b == 0, "戦いの場所（と、そのまわり2m）に建物がない")
	var cw := verts_of(parts["Crosswalk"])
	var cw_in := 0
	for v in cw:
		if absf(v.x) <= half and absf(v.z) <= half:
			cw_in += 1
	check(tri_count(parts["Crosswalk"]) >= 100 and cw_in > 20, "交差点の横断歩道（しま）がある（三角形 %d）" % tri_count(parts["Crosswalk"]))

	# ---- 4. 本物の位置（渋谷スクランブルスクエア：北緯 35.6584・東経 139.7023・高さ 約230m）----
	var b: Dictionary = mc["build"]
	var sq := to_game(35.6584, 139.7023, b)
	var top := -1.0
	for v in bv:
		if Vector2(v.x, v.z).distance_to(sq) < 45.0:
			top = maxf(top, v.y)
	check(top > 180.0 and top < 260.0, "渋谷スクランブルスクエアが、計算した場所（%.0f, %.0f）に本物の高さで立つ（%.0f m）" % [sq.x, sq.y, top])
	var highest := Vector3.ZERO
	for v in bv:
		if v.y > highest.y:
			highest = v
	check(Vector2(highest.x, highest.z).distance_to(sq) < 45.0, "いちばん高い建物は、スクランブルスクエア（%.0f, %.0f, 高さ %.0f）" % [highest.x, highest.z, highest.y])

	# ---- 5. 背景：まわりのどの方向にも建物 ----
	var dirs := [0, 0, 0, 0, 0, 0, 0, 0]
	var far_max := 0.0
	for v in verts_of(parts["BldgFar"]):
		far_max = maxf(far_max, Vector2(v.x, v.z).length())
	for v in bv:
		var d := Vector2(v.x, v.z)
		if d.length() > 30.0:
			dirs[int(floor((d.angle() + PI) / (TAU / 8.0))) % 8] += 1
	check(dirs.min() > 100, "まわりの8つの方向すべてに建物がある %s" % str(dirs))
	check(far_max > 380.0, "遠く（%.0f m）まで建物がある" % far_max)

	# ---- 6. 動ける範囲・足もと ----
	s.set_process(false)
	s.stick_vec = Vector2(1, 1)
	for i in 300:
		s._process(0.05)
	check(absf(s.player.position.x) <= half + 0.001 and absf(s.player.position.z) <= half + 0.001 and s.player.position.x > half - 1.0, "外へ動き続けても、戦いの場所（±%.0fm）のはしで止まる（%.1f, %.1f）" % [half, s.player.position.x, s.player.position.z])
	s.stick_vec = Vector2.ZERO
	var slot = s.ai_allies.keys()[0]
	(s.ai_allies[slot] as Dictionary)["pos"] = Vector2(80, -60)
	s.combat_update(0.05)
	var ap: Vector2 = (s.ai_allies[slot] as Dictionary)["pos"]
	check(absf(ap.x) <= half + 0.001 and absf(ap.y) <= half + 0.001, "AIの味方も、外には出られない（%.1f, %.1f）" % [ap.x, ap.y])
	var under := floor_at(ftris, s.player.position.x, s.player.position.z)
	check(is_equal_approx(s.player.position.y, s.ground_y) and not is_nan(under) and absf(under) <= 0.06, "足もとの床の高さは 0（キャラの足と同じ。埋まらない・浮かない。ずれ %.3f）" % under)

	# ---- 7. 画質・空 ----
	s.set_map_quality("low")
	var far_m: MeshInstance3D = parts["BldgFar"]
	check(is_equal_approx(far_m.visibility_range_end, float(mc["visible_m"]["low"])) and (parts["BldgNear"] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "画質「低」：遠くの建物は %.0f m まで・建物の影なし" % far_m.visibility_range_end)
	s.set_map_quality("high")
	check(is_equal_approx(far_m.visibility_range_end, float(mc["visible_m"]["high"])) and (parts["BldgNear"] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "画質「高」：遠くの建物は %.0f m まで・近い建物の影あり" % far_m.visibility_range_end)
	var env: Environment = s.camera.environment
	check(env.background_mode == Environment.BG_SKY and env.sky != null and env.fog_enabled, "空（夕方のグラデーション）と霧")
	check((parts["BldgNear"] as MeshInstance3D).material_override is ShaderMaterial, "建物は、窓を描くシェーダー（shaders/city_buildings.gdshader）")
	check(s.map_root.get_node_or_null("Border") != null, "戦いの場所のさかい（光る線とうすい壁）がある")

	# ---- 8. 重さ ----
	var total := 0
	for k in parts:
		total += tri_count(parts[k])
	check(total < 160000, "マップの三角形は 16万未満（%d）" % total)
	var size := FileAccess.get_file_as_bytes(str(mc["glb"])).size()
	check(size < 8000000, "マップのファイルは 8MB 未満（%.1f MB）" % (size / 1000000.0))
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

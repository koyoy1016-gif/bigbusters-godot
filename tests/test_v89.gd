extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v89.gd
## 版89：渋谷のマップの背景を、参考の写真に近づけた（横断歩道・建物の材質と色・自作の看板と大画面）。
## 確かめること：
##   1. 設定：材質・看板の数値が data/maps.json にある。看板の絵（signs.png）は 512×512 以下・自作（LICENSES.md に書いてある）
##   2. 部品：看板（Signs）と大画面（Screens）がある。それぞれ専用のシェーダーで、絵（signs.png）を使う。影は出さない
##   3. 建物の材質：タイルの壁・ガラス・パネルの3種類が、どれも使われている。屋根・設備も見分ける。UV（足もとの高さ）がある
##   4. 看板の場所：戦いの場所（±15m とまわり）にはない。交差点から 140m＋α の中。多くは交差点のほうを向く
##   5. 大画面：数は設定の max 以下で、1つ以上。2:1 の形
##   6. 横断歩道：白線の幅 45cm・長さ（横断歩道の幅）は設定のとおり。止まる線もある
##   7. 夜の準備：建物・看板・大画面のシェーダーに night（0〜1）がある（版90で覚醒とつなぐ）
##   8. 重さ：看板の三角形は 1万未満・マップのファイルは 8MB 未満

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const MapLoader := preload("res://scripts/stage/map_loader.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func arrays_of(m: MeshInstance3D) -> Array:
	return m.mesh.surface_get_arrays(0)


func tri_count(m: MeshInstance3D) -> int:
	var n := 0
	for si in m.mesh.get_surface_count():
		var a: Array = m.mesh.surface_get_arrays(si)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		n += idx.size() / 3
	return n


## 四角（三角形2つ）ごとの、辺と対角線の長さ（短い順。[0][1] 短い辺・[2][3] 長い辺・[4][5] 対角線）。3D の長さ
func quad_edges(m: MeshInstance3D) -> Array:
	var a := arrays_of(m)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out := []
	for i in range(0, idx.size(), 6):
		var ps := {}
		for j in 6:
			ps[idx[i + j]] = v[idx[i + j]]
		if ps.size() != 4:
			continue
		var pts: Array = ps.values()
		var e := []
		for j in 4:
			for k in range(j + 1, 4):
				e.append((pts[j] as Vector3).distance_to(pts[k]))
		e.sort()
		out.append(e)
	return out


func _initialize() -> void:
	# ---- 1. 設定 ----
	var mc := MapLoader.current_map()
	var b: Dictionary = mc.get("build", {})
	check(b.has("materials") and b.has("signs") and mc.has("signs"), "材質・看板の数値は data/maps.json（build.materials・build.signs・signs）")
	var mix: Dictionary = b["materials"]["mix"]
	var sums_ok := true
	for g in mix:
		var t := 0.0
		for k in mix[g]:
			t += float(mix[g][k])
		sums_ok = sums_ok and absf(t - 1.0) < 0.001
	check(sums_ok, "材質のえらぶ割合は、どの高さでも合計 1")
	var atlas_path := str(mc["signs"]["atlas"])
	var tex := load(atlas_path) as Texture2D
	check(tex != null and tex.get_width() <= 512 and tex.get_height() <= 512, "看板の絵 %s は 512×512 以下（%d×%d）" % [atlas_path, tex.get_width() if tex else 0, tex.get_height() if tex else 0])
	var lic := FileAccess.get_file_as_string("res://assets/LICENSES.md")
	check(lic.contains("signs.png") and lic.contains("make_signs.py"), "看板の絵は自作（assets/LICENSES.md に書いてある）")
	var maker := FileAccess.get_file_as_string("res://tools/make_signs.py")
	check(maker.contains("自作") and maker.contains("本物のお店・ブランドに似せない"), "看板の店名・ロゴは自作（作る道具 tools/make_signs.py に決まりを書いた）")

	# ---- 2. 部品 ----
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
	var parts := {}
	for mi in s.map_root.find_children("*", "MeshInstance3D", true, false):
		parts[str(mi.get_meta("map_part", ""))] = mi
	check(parts.has("Signs") and parts.has("Screens"), "看板（Signs）と大画面（Screens）がある %s" % str(parts.keys()))
	var sm: MeshInstance3D = parts.get("Signs")
	var scm: MeshInstance3D = parts.get("Screens")
	var smat := sm.material_override as ShaderMaterial
	var scmat := scm.material_override as ShaderMaterial
	check(smat != null and smat.shader.resource_path.ends_with("city_signs.gdshader") and smat.get_shader_parameter("atlas") == tex, "看板は city_signs.gdshader で、絵は signs.png")
	check(scmat != null and scmat.shader.resource_path.ends_with("city_screens.gdshader") and scmat.get_shader_parameter("atlas") == tex, "大画面は city_screens.gdshader で、絵は signs.png")
	check(is_equal_approx(float(scmat.get_shader_parameter("hold_sec")), float(mc["signs"]["hold_sec"])) and float(mc["signs"]["fade_sec"]) >= 0.3, "大画面は %.0f 秒ごとに、%.1f 秒かけて切りかえ（点めつしない）" % [float(mc["signs"]["hold_sec"]), float(mc["signs"]["fade_sec"])])
	check(sm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and scm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "看板・大画面は影を出さない（軽く）")

	# ---- 3. 建物の材質 ----
	var counts := {}
	var uv_ok := true
	for nm in ["BldgNear", "BldgFar"]:
		var a := arrays_of(parts[nm])
		var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var uvs = a[Mesh.ARRAY_TEX_UV]
		uv_ok = uv_ok and uvs != null and (uvs as PackedVector2Array).size() == cols.size()
		for c in cols:
			var k := int(round(c.a * 4.0))
			counts[k] = int(counts.get(k, 0)) + 1
	check(counts.has(2) and counts.has(3) and counts.has(4), "建物の壁は3種類（2 タイルの壁と窓・3 ガラス・4 横長の窓とパネル）がどれも使われる %s" % str(counts))
	check(counts.has(0) and counts.has(1), "屋根（0）・屋上の設備（1：金属）も見分ける")
	check(uv_ok, "建物に UV（足もとの高さ・建物ごとの乱数）がある")
	var bmat := (parts["BldgNear"] as MeshInstance3D).material_override as ShaderMaterial
	check(bmat.get_shader_parameter("sky_top") is Color and bmat.get_shader_parameter("sky_horizon") is Color, "ガラスに空の色をうつす（sky_top・sky_horizon を設定から）")

	# ---- 4. 看板の場所 ----
	var half := float(s.config["bounds"]) + 2.0
	var sa := arrays_of(sm)
	var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = sa[Mesh.ARRAY_NORMAL]
	var sc: PackedColorArray = sa[Mesh.ARRAY_COLOR]
	var inside := 0
	var too_far := 0
	var facing := 0
	var textured := 0
	var R := float(b["signs"]["radius_m"]) + 30.0
	for i in sv.size():
		var v := sv[i]
		if absf(v.x) <= half and absf(v.z) <= half:
			inside += 1
		if Vector2(v.x, v.z).length() > R:
			too_far += 1
		if sc[i].a > 0.5:
			textured += 1
			if sn[i].dot(-Vector3(v.x, 0, v.z).normalized()) > 0.3:
				facing += 1
	check(inside == 0, "看板は、戦いの場所（±%.0fm）の中にない" % half)
	check(too_far == 0, "看板は、交差点から %.0f m の中だけ" % R)
	check(textured > 400 and facing > textured / 2, "絵のある看板の多く（%d / %d 点）は、交差点のほうを向く" % [facing, textured])

	# ---- 5. 大画面 ----
	var quads := quad_edges(scm)
	var n_scr := quads.size()
	check(n_scr >= 1 and n_scr <= int(b["signs"]["screens"]["max"]), "大画面は %d まい（1〜%d）" % [n_scr, int(b["signs"]["screens"]["max"])])
	var shape_ok := true
	for e in quads:
		shape_ok = shape_ok and absf(e[2] / e[0] - 2.0) < 0.01 and e[2] >= 6.0
	check(shape_ok, "大画面は 2:1 の形で、幅 6m 以上")

	# ---- 6. 横断歩道 ----
	var cw := arrays_of(parts["Crosswalk"])
	var wv: PackedVector3Array = cw[Mesh.ARRAY_VERTEX]
	var widx: PackedInt32Array = cw[Mesh.ARRAY_INDEX]
	# 四角（三角形2つ）ごとに、短い辺と長い辺をはかる
	var stripe := float(b["crosswalk"]["stripe_m"])
	var bands := [float(b["crosswalk"]["band_m"]), float(b["crosswalk"]["diag_band_m"])]
	var n_quads := 0
	var good_w := 0
	var long_bands := 0
	var stop_lines := 0
	for i in range(0, widx.size(), 6):
		var ps := {}
		for j in 6:
			ps[widx[i + j]] = wv[widx[i + j]]
		if ps.size() != 4:
			continue
		var pts: Array = ps.values()
		var e := []
		for j in 4:
			for k in range(j + 1, 4):
				e.append(Vector2(pts[j].x, pts[j].z).distance_to(Vector2(pts[k].x, pts[k].z)))
		e.sort()
		n_quads += 1
		if absf(e[0] - stripe) < 0.02:
			good_w += 1
			if absf(e[2] - bands[0]) < 0.05 or absf(e[2] - bands[1]) < 0.05:
				long_bands += 1
			elif e[2] > 1.5:
				stop_lines += 1
	check(n_quads > 100 and good_w == n_quads, "横断歩道の白線の幅は、すべて %.0f cm（%d / %d 本）" % [stripe * 100.0, good_w, n_quads])
	check(long_bands > 100, "白線の長さ（横断歩道の幅）は %.1f m・ななめは %.1f m（%d 本）" % [bands[0], bands[1], long_bands])
	check(stop_lines >= 3, "車の止まる線がある（%d 本）" % stop_lines)

	# ---- 7. 夜の準備 ----
	var has_night := true
	for m in [bmat, smat, scmat]:
		var names := []
		for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
			names.append(str(u["name"]))
		has_night = has_night and names.has("night")
	check(has_night, "建物・看板・大画面のシェーダーに night（0 夕方〜1 夜）がある")

	# ---- 8. 重さ ----
	check(tri_count(sm) + tri_count(scm) < 10000, "看板・大画面の三角形は 1万未満（%d）" % (tri_count(sm) + tri_count(scm)))
	var size := FileAccess.get_file_as_bytes(str(mc["glb"])).size()
	check(size < 8000000, "マップのファイルは 8MB 未満（%.1f MB）" % (size / 1000000.0))
	s.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

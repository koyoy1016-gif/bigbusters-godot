extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v103.gd
## 版103（軽量化②：描画の回数）：キャラの影と輪郭線を、キャラ全体で少ない回数で描く（CharacterView.build_proxies・SkinMerge）。
## 確かめること（9人全員）：
##   1. 輪郭線の形（OutlineProxy・面は3つまで）と影の形（ShadowProxy）ができる。元の形は輪郭線を付けない（この形だけの材質の写し）。
##      不透明な元の形は影を落とさない（影の形が落とす）。切り抜き（髪・まゆ）の形は、影を元のまま自分で落とす
##   2. まとめた形の点の数＝元の面の点の数の合計（輪郭線は全部・影は不透明の面）
##   3. 骨を動かした時、まとめた形の点は、元の形の点と同じ場所に動く（骨の表の付けかえが正しい）
##   4. 同じキャラの2人目は、まとめた形を使いまわす（作り直さない）
##   5. 画質の切りかえ（StyleFx.set_outline）：輪郭線の形を出す／隠すだけ。元の形の材質に線を付けない
##   6. 必殺技の残像（bake_ghost）は、まとめた形を写さない
##   7. 描く回数の見こみ（画質「高」）：前より大きく減る

const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func originals(v: Node) -> Array:
	var out := []
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		if not mi.has_meta("proxy"):
			out.append(mi)
	return out


func proxies(v: Node) -> Dictionary:
	var out := {}
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("proxy"):
			out[str(mi.name)] = mi
	return out


## 骨で動かした点（every 点ごとに1つ）。items：[[面の配列, Skin], ...] を順につないだ点の番号で数える
func posed_points(sk: Skeleton3D, items: Array, every: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var idx := 0
	for it in items:
		var arr: Array = it[0]
		var skin: Skin = it[1]
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var pw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := pb.size() / maxi(1, pv.size())
		for i in pv.size():
			if (idx + i) % every == 0:
				var p := Vector3.ZERO
				for k in per:
					var w := pw[i * per + k]
					if w <= 0.0:
						continue
					var bnd := pb[i * per + k]
					var bname := str(skin.get_bind_name(bnd))
					var bi := sk.find_bone(bname) if bname != "" else skin.get_bind_bone(bnd)
					p += (sk.get_bone_global_pose(bi) * skin.get_bind_pose(bnd) * pv[i]) * w
				out.append(p)
		idx += pv.size()
	return out


func _initialize() -> void:
	StyleFx.outline_on = true
	var cfg := CD.load_config()
	var ok_struct := true
	var ok_counts := true
	var ok_pose := true
	var ok_cache := true
	var ok_toggle := true
	var before_draws := 0
	var after_draws := 0
	var notes := []
	for c in cfg["characters"]:
		var id := str(c["id"])
		var v := CV.new()
		root.add_child(v)
		v.setup(c)
		await process_frame  # 骨つきの形が骨とつながるまで待つ
		var px := proxies(v)
		var op: MeshInstance3D = px.get("OutlineProxy")
		var sb: MeshInstance3D = px.get("ShadowProxy_back")
		if op == null or sb == null:
			ok_struct = false
			notes.append(id + "：形がない")
			continue
		ok_struct = ok_struct and op.mesh.get_surface_count() <= 3 and op.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and op.visible
		ok_struct = ok_struct and sb.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var outline_pts := 0
		var shadow_pts := 0
		var surf := 0
		for mi in originals(v):
			var m := mi as MeshInstance3D
			if not m.has_meta("outline_merged"):
				continue
			var opaque := true
			for si in m.mesh.get_surface_count():
				surf += 1
				outline_pts += m.mesh.surface_get_array_len(si)
				var act := m.get_active_material(si) as StandardMaterial3D
				ok_struct = ok_struct and act != null and act.next_pass == null and act != m.mesh.surface_get_material(si)
				if (m.mesh.surface_get_material(si) as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					opaque = false
			if opaque:
				ok_struct = ok_struct and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				for si in m.mesh.get_surface_count():
					shadow_pts += m.mesh.surface_get_array_len(si)
			else:
				ok_struct = ok_struct and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var op_pts := 0
		for si in op.mesh.get_surface_count():
			op_pts += op.mesh.surface_get_array_len(si)
		var sp_pts: int = sb.mesh.surface_get_array_len(0) + ((px["ShadowProxy_both"] as MeshInstance3D).mesh.surface_get_array_len(0) if px.has("ShadowProxy_both") else 0)
		ok_counts = ok_counts and op_pts == outline_pts and sp_pts == shadow_pts
		# 描く回数の見こみ（色・線・影）
		var scissor_shadow := 0
		for mi in originals(v):
			if (mi as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				scissor_shadow += (mi as MeshInstance3D).mesh.get_surface_count()
		before_draws += surf * 4  # 色・線・影・線の影（面ごと）
		after_draws += surf + op.mesh.get_surface_count() * 2 + (px.size() - 1) + scissor_shadow
		# ---- 3. 骨を動かして、点が同じ場所に動くか ----
		var sk := v.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for b in sk.get_bone_count():
			if b % 3 == 0:
				sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(Vector3(0.3, 1, 0.2).normalized(), 0.35))
		sk.force_update_all_bone_transforms()
		var orig_pts := PackedVector3Array()
		# 輪郭線の形の面の順（A：不透明・片面 → C：不透明・両面など → S：切り抜き）に、元の点を並べ、骨で動かした場所をくらべる
		# （画面なしでは、エンジンの「いまの姿勢の形を作る」が使えないので、骨の計算をここでする）
		var groups := [[], [], []]
		for mi in originals(v):
			var m2 := mi as MeshInstance3D
			if not m2.has_meta("outline_merged"):
				continue
			var opaque2 := m2.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for si in m2.mesh.get_surface_count():
				var g := 2
				if opaque2:
					g = 0 if (m2.mesh.surface_get_material(si) as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK else 1
				(groups[g] as Array).append([m2.mesh.surface_get_arrays(si), m2.skin])
		var orig_list: Array = []
		for g in groups:
			orig_list.append_array(g)
		var prox_list: Array = []
		for si in op.mesh.get_surface_count():
			prox_list.append([op.mesh.surface_get_arrays(si), op.skin])
		var A := posed_points(sk, orig_list, 37)
		var B := posed_points(sk, prox_list, 37)
		var maxd := INF
		if A.size() == B.size() and A.size() > 0:
			maxd = 0.0
			for i in A.size():
				maxd = maxf(maxd, A[i].distance_to(B[i]))
		ok_pose = ok_pose and maxd < 0.001
		notes.append("%s 面%d→線%d 点%d ずれ最大%.5fm" % [id, surf, op.mesh.get_surface_count(), op_pts, maxd])
		# ---- 4. 2人目は使いまわす ----
		var v2 := CV.new()
		root.add_child(v2)
		v2.setup(c)
		var px2 := proxies(v2)
		ok_cache = ok_cache and px2.has("OutlineProxy") and is_same((px2["OutlineProxy"] as MeshInstance3D).mesh, op.mesh) and is_same((px2["OutlineProxy"] as MeshInstance3D).skin, op.skin)
		# ---- 5. 画質の切りかえ ----
		StyleFx.set_outline(v2, false)
		var hidden: bool = not (px2["OutlineProxy"] as MeshInstance3D).visible
		StyleFx.set_outline(v2, true)
		var shown: bool = (px2["OutlineProxy"] as MeshInstance3D).visible
		var no_line := true
		for mi in originals(v2):
			var m4 := mi as MeshInstance3D
			if m4.has_meta("outline_merged"):
				for si in m4.mesh.get_surface_count():
					no_line = no_line and (m4.get_active_material(si) as StandardMaterial3D).next_pass == null
		ok_toggle = ok_toggle and hidden and shown and no_line
		v.queue_free()
		v2.queue_free()
	for n in notes:
		print("     ", n)
	check(ok_struct, "輪郭線の形（面は3つまで・影を落とす）と影の形ができる。元の形は線なしの材質の写し、不透明は影を落とさない、切り抜きは自分で落とす")
	check(ok_counts, "まとめた形の点の数＝元の面の点の数の合計（輪郭線：全部、影：不透明）")
	check(ok_pose, "骨を動かすと、まとめた形の点は元の形の点と同じ場所（1mm 未満）")
	check(ok_cache, "同じキャラの2人目は、まとめた形と骨の表を使いまわす")
	check(ok_toggle, "画質の切りかえ：輪郭線の形を出す／隠すだけ。元の形の材質に線は付かない")
	# 画面なしでは、残像を作るエンジンの計算（いまの姿勢の形）が動かないので、写す前に proxy をよけていることを、作りで確かめる
	var usrc := FileAccess.get_file_as_string("res://scripts/fx/ultimate_fx.gd")
	var gi := usrc.find("static func bake_ghost")
	var gbody := usrc.substr(gi, usrc.find("\nstatic func ", gi + 10) - gi)
	check(gbody.contains("has_meta(\"proxy\")") and gbody.find("has_meta(\"proxy\")") < gbody.find("bake_mesh_from_current_skeleton_pose"), "必殺技の残像は、まとめた形（proxy）を写さない")
	check(after_draws * 2 < before_draws, "描く回数の見こみ（画質「高」・9人の合計）：%d → %d" % [before_draws, after_draws])
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)

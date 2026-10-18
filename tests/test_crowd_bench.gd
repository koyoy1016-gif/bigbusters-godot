extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_crowd_bench.gd
## 負荷試験（crowd_bench.gd）と、骨つきの仮の人型（bench_character.gd）を確かめる。

const Char := preload("res://scripts/prototype/bench_character.gd")
const Bench := preload("res://scripts/prototype/crowd_bench.gd")
const SCENE := "res://scenes/prototype/crowd_bench.tscn"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	# 面の数の計算
	check(Char.radial_for(8000) == 26 and Char.radial_for(2000) == 13, "分割数は、面の数の目標から決まる")
	check(Char.radial_for(0) >= 4 and Char.radial_for(-5) >= 4, "目標が0やマイナスでも、最低の分割数")
	for target in [2000, 8000, 20000]:
		var tris := Char.character_tris(Char.radial_for(target))
		check(absi(tris - target) * 100 <= target * 15, "目標 %d に対して、実際の面の数 %d は、±15%%以内" % [target, tris])

	# 位置の並べ方
	check(Char.layout_positions(0, 1.5).is_empty(), "0体なら、位置はなし")
	var pos16 := Char.layout_positions(16, 1.5)
	check(pos16.size() == 16, "16体の位置が16個")
	var sx := 0.0
	var sy := 0.0
	for p in pos16:
		sx += p.x
		sy += p.y
	check(Bench.index_of([1.0, 4.0], 4) == 1 and Bench.index_of([1.0], 9) == -1, "配列の中の場所（小数でも見つかる）")
	check(absf(sx) < 0.001 and absf(sy) < 0.001, "並びの中心は、真ん中（0, 0）")
	var uniq := {}
	for p in pos16:
		uniq[str(p)] = true
	check(uniq.size() == 16, "同じ位置に重ならない")
	check(Char.layout_positions(1, 1.5)[0] == Vector2.ZERO, "1体なら、真ん中")

	# 人型：骨・面・重み
	var mat := StandardMaterial3D.new()
	var sk := Char.build(8000, mat)
	check(sk.get_bone_count() == 7, "骨は7本")
	var inst := sk.get_node("Body") as MeshInstance3D
	var arrays := inst.mesh.surface_get_arrays(0)
	var vcount := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	check(vcount > 0 and (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() == vcount * 4, "骨の番号が、頂点ごとに4つ")
	check((arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size() == vcount * 4, "重みも、頂点ごとに4つ")
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var ok_sum := true
	for v in vcount:
		var s := weights[v * 4] + weights[v * 4 + 1] + weights[v * 4 + 2] + weights[v * 4 + 3]
		if absf(s - 1.0) > 0.001:
			ok_sum = false
	check(ok_sum, "重みの合計は、どの頂点も1")
	check((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 == Char.character_tris(Char.radial_for(8000)), "実際の三角形の数が、計算と一致")
	check(inst.skin != null and inst.skeleton == NodePath(".."), "皮（Skin）と骨が結び付いている")
	var aabb := inst.mesh.get_aabb()
	check(aabb.size.y > 1.7 and aabb.size.y < 2.1, "背の高さは、約1.8〜2メートル：%.2f" % aabb.size.y)
	var head_h := 0.26 + 0.0
	check(aabb.size.y / head_h > 7.0 and aabb.size.y / head_h < 8.5, "約7〜8等身（頭の高さ0.26メートルに対して）")
	var before := sk.get_bone_pose_rotation(5)
	Char.animate(sk, 0.5, 0.0, 5.0, 0.6)
	check(sk.get_bone_pose_rotation(5) != before, "動きを付けると、脚の骨が回る")
	sk.free()

	# 測定の計算
	check(Bench.average([]) == 0.0 and is_equal_approx(Bench.average([30.0, 60.0]), 45.0), "FPSの平均")
	var steps := Bench.build_sweep_steps([4, 16], [2000, 8000])
	check(steps.size() == 4 and steps[0] == {"count": 4, "tris": 2000} and steps[3] == {"count": 16, "tris": 8000}, "測る組み合わせの一覧")

	# 画面
	var cfg: Dictionary = Bench.load_config()
	var font := load(str(cfg["ui_font_path"])) as Font
	var missing := ""
	var text := ""
	for k in cfg:
		if k.ends_with("_label") or k.ends_with("_text") or k in ["title", "unit_mb", "unit_k", "sweep_running"]:
			text += str(cfg[k])
	text += "0123456789:/ ."
	for ch in text:
		if not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	check(missing == "", "試験の文字が、すべてフォントにある（足りない字：%s）" % missing)
	var counts: Array = cfg["counts"]
	for c in cfg["sweep_counts"]:
		check(Bench.index_of(counts, int(c)) >= 0, "自動測定の数 %d は、選べる数の中にある" % int(c))
	for t in cfg["sweep_triangles"]:
		check(Bench.index_of(cfg["triangles"], int(t)) >= 0, "自動測定の面の数 %d は、選べる中にある" % int(t))

	var packed := load(SCENE) as PackedScene
	check(packed != null, "試験のシーンが読める")
	if packed != null:
		var b: Node = packed.instantiate()
		root.add_child(b)
		if b.config.is_empty():
			b._ready()
		check(b.characters.size() == 16 and b.current_tris() == 8000, "最初は、16体・8k")
		b.change_count(-1)
		check(b.characters.size() == 8 and b.current_count() == 8, "－を押すと、8体に減る")
		b.change_count(99)
		check(b.current_count() == 32 and b.characters.size() == 32, "＋を押し続けても、上限（32）で止まる")
		b.change_count(-99)
		check(b.current_count() == 1, "下限は1体")
		b.change_tris(-99)
		check(b.current_tris() == 2000, "面の数の下限は2k")
		b.toggle_shadow()
		check(b.light.shadow_enabled and b.shadow_button.text == "あり", "かげを「あり」にできる")
		b._apply_orientation(Vector2(390, 844))
		check(b.portrait_mode and b.camera.keep_aspect == Camera3D.KEEP_WIDTH, "縦画面では、カメラは幅基準")
		b._apply_orientation(Vector2(844, 390))
		check(not b.portrait_mode and b.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "横に戻る")
		# 自動測定：偽のFPS（30）で、全組み合わせを回す
		b.fps_source = func() -> float: return 30.0
		b.start_sweep()
		check(b.sweeping and b.sweep_steps.size() == 9, "自動測定が始まる（3×3=9組み合わせ）")
		var guard := 0
		while b.sweeping and guard < 5000:
			guard += 1
			b.sweep_update(0.1)
		check(not b.sweeping and b.sweep_results.size() == 9, "すべて測り終わる")
		check(int(b.sweep_results[0]["count"]) == 4 and int(b.sweep_results[8]["count"]) == 24 and int(b.sweep_results[8]["tris"]) == 20000, "測った組み合わせが、指定どおり（4体2k … 24体20k）")
		check(b.current_count() == 24 and b.current_tris() == 20000, "最後の組み合わせの画面になっている")
		check(is_equal_approx(float(b.sweep_results[0]["fps"]), 30.0), "平均のFPSが記録される")
		check(str(b.build_result_text()).split("\n").size() == 9 and str(b.build_result_text()).contains("FPS"), "結果の文字は9行")
		root.remove_child(b)
		b.free()

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v106.gd
## 版106（④ 入力の遅れの調べ）：指の入力が、ゲームの動きに何コマで届くかを確かめる。
## 画面なしでは、Godot の入力の道すじ（Input.parse_input_event）が動かないので、ウィンドウに入力をわたす push_input を使う
## （実機では、ブラウザから来た入力は、次のコマのはじめにまとめて渡される。そのあとの流れは同じ）。
## 確かめること：
##   1. スティックに指を置いて動かすと、次のコマ（入力がとどくコマ）で、自分が動き出す（それより遅れない）
##   2. 攻撃ボタンを押すと、同じコマで技が始まる（ボタンの光・技の名前）
##   3. 指をはなすと、同じコマで止まる
##   4. 見た目の先出し：戦う人の技・当たり・必殺技の見た目を、見えない所に出し、3コマで消す（材質は使いまわしの置き場へ）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)  # 画面の座標のまま（画面なしの窓は小さいので、引きのばしの変換をしない）


func drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	root.push_input(e, true)  # 画面の座標のまま（画面なしの窓は小さいので、引きのばしの変換をしない）


func _initialize() -> void:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = false
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	for i in 5:
		await process_frame
	var screen: Vector2 = s.get_viewport().get_visible_rect().size
	var c: Vector2 = s.hud._stick_center(screen)
	var r := float(s.config["stick_radius_px"])
	# ---- 1. スティック ----
	var p0: Vector3 = s.player.position
	touch(0, c, true)
	drag(0, c + Vector2(r, 0))
	var frames := 0
	while frames < 5 and s.player.position.distance_to(p0) < 0.0001:
		await process_frame
		frames += 1
	check(frames == 1, "スティックを動かすと、次のコマで自分が動き出す（%d コマ）" % frames)
	# ---- 3. はなす ----
	touch(0, c + Vector2(r, 0), false)
	await process_frame
	var p1: Vector3 = s.player.position
	await process_frame
	check(s.stick_vec == Vector2.ZERO and s.player.position.distance_to(p1) < 0.0001, "指をはなすと、そのコマで止まる")
	# ---- 2. 攻撃ボタン ----
	await process_frame
	var bc: Vector2 = s.hud._button_center("normal", screen)
	var busy0: bool = s.actions.busy()
	touch(1, bc, true)
	await process_frame
	check(not busy0 and s.actions.busy() and float(s.button_flash.get("normal", 0.0)) > 0.0, "攻撃ボタンを押すと、入力がとどくコマで技が始まる（ボタンも光る）")
	touch(1, bc, false)
	s.queue_free()
	await process_frame
	# ---- 4. 見た目の先出し（版106） ----
	var FxPool = load("res://scripts/fx/fx_pool.gd")
	var s2: Node = (load(SCENE) as PackedScene).instantiate()
	s2.selected_character = "mage"
	s2.ai_picks = ["healer", "gunner", "brawler"]
	s2.ai_enabled = true
	root.add_child(s2)
	await process_frame
	if s2.get_node_or_null("Boss") == null:
		s2._ready()
	var ids: Array = ["mage", "healer", "gunner", "brawler"]
	var free0: int = FxPool.free_count()
	s2.skills.prewarm_fx()
	var nodes: Array = s2.skills.prewarm_nodes.duplicate()
	var cam: Transform3D = s2.camera.global_transform
	var below := true
	var in_front := true
	for n in nodes:
		var p: Vector3 = (n as Node3D).global_position
		below = below and p.y < float(s2.ground_y) - 5.0
		in_front = in_front and (cam.affine_inverse() * p).z < 0.0
	check(nodes.size() >= ids.size() * 3 + 2 and below and in_front, "戦いの始まりに、%d 人の技・当たり・必殺技の見た目を %d こ、カメラの前の地面の下（見えない所）に出す" % [ids.size(), nodes.size()])
	for i in 4:
		s2.skills.prewarm_step()
	await process_frame
	await process_frame
	var gone := true
	for n in nodes:
		gone = gone and not is_instance_valid(n)
	check(gone and s2.skills.prewarm_nodes.is_empty() and FxPool.free_count() > free0, "3コマで消え、材質は使いまわしの置き場へ（%d → %d）" % [free0, FxPool.free_count()])
	var src := FileAccess.get_file_as_string("res://scripts/prototype/stick_prototype.gd")
	check(src.contains("skills.prewarm_fx()") and src.contains("skills.prewarm_step()"), "戦いの画面ができた時に先出しし、毎コマ片づける")
	s2.queue_free()
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
